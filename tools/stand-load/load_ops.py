#!/usr/bin/env python3
"""Нагрузочный прогон стенда: N операторов load-op-NN ходят по очереди как люди, эмулятор подаёт события.

Запуск: python3 -I load_ops.py <операторов> <сек между пачками> <минут> [метка]
Пишет в imdb стенда: перед запуском снять дамп. Итог — load/out/<метка>/:
  log.jsonl     — каждый запрос: кто, что, код, мс, байт (и outcome переходов);
  stream.jsonl  — каждое incident.created из /operator/stream у каждого оператора: кто, инцидент, время прихода;
  labels.txt, emit.jsonl — пачки эмулятора и время их подачи; ids.json — id операторов; summary.json.

Оператор — три потока: цикл действий (паузы 0,5–3 с), heartbeat раз в 15 с, поток SSE.
Соединения keep-alive, как у браузера. Токен перевыпускается входом раз в 4 мин.
"""
import http.client, json, os, random, ssl, subprocess, sys, threading, time, urllib.parse, statistics

HOST = "axxonnet.test"
BASE = "/api/v1/im-backend"
CA = os.path.expanduser("~/Work/axxoncloudgo/tools/util/rootCA.axxonnet.test.pem")
STAND = os.path.expanduser("~/Work/stand")
EMU = os.path.join(STAND, "bin/agent-emulator")
# replay эмулятора получает 401 (ключа HMAC нет в базе) — та же пачка через прямой вход X-Dev-Agent
REPLAY = os.path.join(STAND, "load/replay_dev.py")
CTX = ssl.create_default_context(cafile=CA)
CTX.verify_flags &= ~ssl.VERIFY_X509_STRICT
N = int(sys.argv[1])
EVERY = float(sys.argv[2])
MINUTES = float(sys.argv[3])
RUN = sys.argv[4] if len(sys.argv) > 4 else time.strftime("ops-%Y%m%d-%H%M%S")
OUT = os.path.join(STAND, "load/out", RUN)
os.makedirs(OUT, exist_ok=True)
STOP = threading.Event()
LOCK = threading.Lock()
LOG = open(os.path.join(OUT, "log.jsonl"), "w")
SLOG = open(os.path.join(OUT, "stream.jsonl"), "w")
CHK = open(os.path.join(OUT, "check.jsonl"), "w")  # RELOAD=stream: сверка своей страницы с ответом сервера
HOLD_REASONS = ["third_party", "patrol", "no_data"]
FILTERS = ["open", "open", "open", "inbox", "mine", "foreign", "done", "all"]
SORTS = ["priority_then_oldest", "priority_then_newest", "oldest_first", "reaction_deadline"]
RELOAD = os.environ.get("RELOAD", "none")  # none | every (старый клиент) | throttle (Р-4, bff3e88) | stream (план 84)
assert RELOAD in ("none", "every", "throttle", "stream"), RELOAD
WORDS = ["стекл", "дым", "вход", "Гардероб", "пожар", "предмет", "СИЗ", "камера"]


def log(rec, f=None):
    rec["t"] = round(time.time(), 3)
    with LOCK:
        (f or LOG).write(json.dumps(rec, ensure_ascii=False) + "\n")


def flusher():
    while not STOP.wait(2):
        with LOCK:
            LOG.flush(); SLOG.flush(); CHK.flush()


class Op:
    def __init__(self, i):
        self.i = i
        self.who = "op%02d" % i
        self.email = "load-op-%02d@axxonnet.test" % i
        self.tok = None
        self.tok_at = 0
        self.id = None
        self.tl = threading.local()  # своё HTTPS-соединение у каждого потока: общее давало SIGSEGV (2026-11-11)
        self.current = None
        self.rnd = random.Random(i * 7919 + int(time.time()))
        self.qs = {}  # состояние очереди: filter, sort, page, фильтры
        self.rows = []
        self.page = []  # RELOAD=stream: своя страница очереди, как кэш клиента
        self.total = 0
        self.open = None  # открытая карточка: её и связанные перечитывает поток
        self.reloads = 0

    def login(self):
        c = http.client.HTTPSConnection(HOST, context=CTX, timeout=30)
        t0 = time.time()
        try:
            c.request("POST", "/api/v3/ac-backend/users/login", json.dumps({"email": self.email, "password": "111111"}),
                      {"Content-Type": "application/json"})
            r = c.getresponse(); raw = r.read(); code = r.status
        except Exception as e:
            code, raw = -1, str(e).encode()
        finally:
            c.close()
        log({"who": self.who, "op": "login", "code": code, "ms": round((time.time() - t0) * 1000, 1), "bytes": len(raw)})
        if code == 200:
            self.tok = json.loads(raw)["accessToken"]
            self.tok_at = time.time()
        return code

    def call(self, method, path, body=None, headers=None, op=None):
        if time.time() - self.tok_at > 240:
            self.login()
        h = {"Authorization": "Bearer " + (self.tok or "")}
        data = None
        if body is not None:
            data = json.dumps(body)
            h["Content-Type"] = "application/json"
        h.update(headers or {})
        t0 = time.time()
        code, raw = 0, b""
        retried = 0
        if not hasattr(self.tl, "conn"):
            self.tl.conn = None
        for attempt in (0, 1):
            reused = self.tl.conn is not None
            try:
                if self.tl.conn is None:
                    self.tl.conn = http.client.HTTPSConnection(HOST, context=CTX, timeout=60)
                self.tl.conn.request(method, BASE + path, data, h)
                r = self.tl.conn.getresponse(); raw = r.read(); code = r.status
                if r.getheader("Connection", "").lower() == "close":
                    self.tl.conn.close(); self.tl.conn = None
                break
            except Exception as e:
                # Сбой на соединении keep-alive, которое закрыли между запросами (шлюз), — один повтор на новом,
                # как делает браузер; повтор отмечается в журнале (retry). Сбой на новом соединении — ошибка.
                try:
                    self.tl.conn.close()
                except Exception:
                    pass
                self.tl.conn = None
                code, raw = -1, str(e).encode()
                if not reused or attempt:
                    break
                retried = 1
        ms = (time.time() - t0) * 1000
        try:
            js = json.loads(raw) if raw else None
        except ValueError:
            js = None
        rec = {"who": self.who, "op": op or method + " " + path.split("?")[0], "code": code, "ms": round(ms, 1), "bytes": len(raw)}
        if retried:
            rec["retry"] = 1
        if code >= 400 or code < 0:
            rec["err"] = js.get("code") if isinstance(js, dict) else raw[:200].decode(errors="replace")
        log(rec)
        if code == 401:
            self.login()
        return code, js


OPS = []
REF = {}


def load_refs(op):
    def walk(nodes, acc):
        for n in nodes or []:
            acc.append(n["guid"]); walk(n.get("children"), acc)
        return acc
    _, sg = op.call("GET", "/operator/reference/source-groups", op="ref:source-groups")
    REF["groups"] = walk(sg if isinstance(sg, list) else [], [])
    _, et = op.call("GET", "/operator/reference/event-types", op="ref:event-types")
    REF["types"] = [x["guid"] for x in et or []]
    _, sc = op.call("GET", "/operator/reference/scenarios", op="ref:scenarios")
    REF["scen"] = [x["guid"] for x in sc or []]
    _, pr = op.call("GET", "/operator/reference/priorities", op="ref:priorities")
    REF["prio"] = [x["value"] for x in pr or []]
    _, dt = op.call("GET", "/operator/reference/device-types", op="ref:device-types")
    REF["dev"] = [x["id"] for x in dt or []]


def pause(op, a=0.5, b=3.0):
    STOP.wait(op.rnd.uniform(a, b))


def queue(op, kind):
    q = {k: v for k, v in op.qs.items() if v is not None}
    q.setdefault("filter", "open"); q.setdefault("pageSize", 50)
    code, js = op.call("GET", "/operator/incidents?" + urllib.parse.urlencode(q), op="queue:" + kind)
    if code == 200 and isinstance(js, dict):
        op.rows = js.get("items", []); op.total = js.get("total", 0)
        with LOCK:
            op.page = list(op.rows)
    op.call("GET", "/operator/incidents/counters", op="counters")
    return op.rows


def nav(op):
    """Одно действие с очередью, как у человека."""
    r = op.rnd
    k = r.choices(["tab", "sort", "next", "prev", "group", "type", "scen", "prio", "dev", "num", "text", "reset", "refresh"],
                  [14, 6, 10, 5, 6, 6, 4, 5, 3, 5, 5, 8, 15])[0]
    if k == "tab":
        op.qs = {"filter": r.choice(FILTERS), "sort": op.qs.get("sort")}
    elif k == "sort":
        op.qs["sort"] = r.choice(SORTS); op.qs["page"] = None
    elif k == "next":
        pages = max(1, (op.total + 49) // 50)
        op.qs["page"] = min(pages, (op.qs.get("page") or 1) + 1)
    elif k == "prev":
        op.qs["page"] = max(1, (op.qs.get("page") or 1) - 1)
    elif k == "group" and REF.get("groups"):
        op.qs["sourceGroupGuid"] = r.choice(REF["groups"]); op.qs["page"] = None
    elif k == "type" and REF.get("types"):
        op.qs["eventTypeGuid"] = r.choice(REF["types"]); op.qs["page"] = None
    elif k == "scen" and REF.get("scen"):
        op.qs["scenarioGuid"] = r.choice(REF["scen"]); op.qs["page"] = None
    elif k == "prio" and REF.get("prio"):
        op.qs["priority"] = r.choice(REF["prio"]); op.qs["page"] = None
    elif k == "dev" and REF.get("dev"):
        op.qs["deviceTypeId"] = r.choice(REF["dev"]); op.qs["page"] = None
    elif k == "num":
        n = r.choice(op.rows)["number"] if op.rows and op.rows[0].get("number") else r.randint(1, 20000)
        op.qs = {"filter": "all", "search": str(n)}
    elif k == "text":
        op.qs = {"filter": op.qs.get("filter") or "open", "search": r.choice(WORDS)}
    elif k == "reset":
        op.qs = {"filter": op.qs.get("filter") or "open"}
    queue(op, k)


def card(op, guid, full=True):
    op.open = guid
    code, inc = op.call("GET", f"/operator/incidents/{guid}", op="card")
    if code != 200 or not isinstance(inc, dict):
        return None
    if full:
        for sub, name in [("journal", "card:journal"), ("linked", "card:linked"), ("scenario", "card:scenario"),
                          ("actions?surface=card", "card:actions"), ("media", "card:media")]:
            if STOP.is_set() or op.rnd.random() < 0.15:
                continue
            pause(op, 0.3, 1.5)
            op.call("GET", f"/operator/incidents/{guid}/{sub}", op=name)
    return inc


def transition(op, inc, tid, form=None, opname=None):
    body = {"surface": "card"}
    if form:
        body["formValues"] = form
    code, js = op.call("POST", f"/operator/incidents/{inc['guid']}/transitions/{tid}", body,
                       {"If-Match": '"%s"' % inc["version"]}, op=opname or "transition:" + tid)
    log({"who": op.who, "op": "outcome", "tid": tid, "inc": inc["guid"], "code": code, "from": inc.get("state"),
         "to": (js or {}).get("incident", {}).get("state") if code == 200 and isinstance(js, dict) else None})
    if code == 200 and isinstance(js, dict) and js.get("incident"):
        inc.update(js["incident"])
    return code


def work(op):
    """Работа с инцидентом: принять переданное или взять новый, затем отложить/передать/закрыть."""
    r = op.rnd
    op.qs = {"filter": "inbox"}
    rows = queue(op, "inbox")
    inc = None
    for row in rows:
        if row.get("state") == "pending_acceptance":
            inc = card(op, row["guid"], full=False)
            if inc and inc.get("state") == "pending_acceptance" and inc.get("ownership") == "target":
                if transition(op, inc, "accept") == 200:
                    break
            inc = None
    if inc is None:
        op.qs = {"filter": "open", "sort": "priority_then_oldest"}
        rows = [x for x in queue(op, "open") if x.get("state") == "new"]
        if not rows:
            return
        row = rows[0] if r.random() < 0.3 else r.choice(rows)
        inc = card(op, row["guid"], full=False)
        if not inc or inc.get("state") != "new" or transition(op, inc, "claim") != 200:
            return
    op.current = inc["guid"]
    card(op, inc["guid"])  # открыл и смотрит карточку
    pause(op)
    if STOP.is_set() or inc.get("state") != "in_progress":
        op.current = None
        return
    if r.random() < 0.25:
        if transition(op, inc, "hold", {"reasonId": r.choice(HOLD_REASONS), "comment": "нагрузка: удержание"}) == 200:
            pause(op, 1, 3)
            transition(op, inc, "resume")
    if r.random() < 0.2 and len(OPS) > 1:
        op.call("GET", "/operator/transfer-targets?incidentGuid=" + inc["guid"], op="transfer-targets")
        other = r.choice([o for o in OPS if o is not op])
        if transition(op, inc, "transfer", {"targetId": other.id, "comment": "нагрузка: передача"}) == 200:
            op.current = None
            return
    pause(op)
    code = transition(op, inc, "close", {"resultId": "false_alarm", "comment": "нагрузка: закрытие"})
    if code == 412:
        fresh = card(op, inc["guid"], full=False)
        if fresh and fresh.get("state") == "in_progress":
            inc.update(fresh)
            transition(op, inc, "close", {"resultId": "false_alarm", "comment": "нагрузка: закрытие"}, "transition:close-retry")
    op.current = None


def operator(op):
    queue(op, "start")
    while not STOP.is_set():
        k = op.rnd.choices(["nav", "card", "work"], [60, 28, 12])[0]
        if k == "nav":
            nav(op)
        elif k == "card" and op.rows:
            card(op, op.rnd.choice(op.rows)["guid"])
            if op.rnd.random() < 0.5:
                pause(op); queue(op, "back")
        else:
            work(op)
        pause(op)


def reload_keys(op, keys):
    """Перечитать, как useReloadKeys клиента: активные запросы с этими ключами."""
    with LOCK:
        op.reloads += 1
    q = {k: v for k, v in op.qs.items() if v is not None}
    q.setdefault("filter", "open"); q.setdefault("pageSize", 50)
    g = op.open
    for k in keys:
        if STOP.is_set():
            return
        if k == "queue":
            code, js = op.call("GET", "/operator/incidents?" + urllib.parse.urlencode(q), op="reload:queue")
            if code == 200 and isinstance(js, dict):
                with LOCK:
                    op.page = list(js.get("items", []))
        elif k == "counters":
            op.call("GET", "/operator/incidents/counters", op="reload:counters")
        elif k == "tree":
            op.call("GET", "/operator/reference/source-groups?withCounters=true", op="reload:tree")
        elif k == "session":
            op.call("GET", "/operator/session", op="reload:session")
        elif k == "card" and g:
            op.call("GET", f"/operator/incidents/{g}", op="reload:card")
        elif k == "linked" and g:
            op.call("GET", f"/operator/incidents/{g}/linked?pageSize=50", op="reload:linked")


ALL_KEYS = ["session", "queue", "counters", "tree", "card", "linked"]
FAST_KEYS = ["queue", "card", "linked"]
SLOW_KEYS = ["counters", "tree", "session"]


class Reloader:
    """Свой поток перечитывания. ms=0 — старый клиент: одна загрузка за раз, событие во время загрузки даёт
    ровно одну загрузку после неё (решение 147). ms>0 — leading+trailing окно Р-4; now() — сброс мимо окна."""

    def __init__(self, op, keys, ms):
        self.op, self.keys, self.ms = op, keys, ms / 1000.0
        self.cv = threading.Condition()
        self.pending = self.force = False
        self.until = 0.0
        threading.Thread(target=self.loop, daemon=True).start()

    def fire(self, force=False):
        with self.cv:
            self.pending = True
            self.force = self.force or force
            self.cv.notify()

    def loop(self):
        while not STOP.is_set():
            with self.cv:
                while not self.pending and not STOP.is_set():
                    self.cv.wait(0.5)
                while not self.force and not STOP.is_set() and time.time() < self.until:
                    self.cv.wait(self.until - time.time())
                if STOP.is_set():
                    return
                self.pending = self.force = False
                self.until = time.time() + self.ms
            reload_keys(self.op, self.keys)


def place_of(row):
    """Что читают фильтры и порядки очереди (streamPatch.ts клиента): смена — строка может сместиться или уйти."""
    t = row.get("timer") or {}
    return json.dumps([row.get("state"), row.get("ownership"), (row.get("owner") or {}).get("id"),
                       (row.get("assignmentGroup") or {}).get("id"), row.get("priority"),
                       [t.get("id"), t.get("dueAt"), t.get("running")] if row.get("timer") else None,
                       row.get("linkedTo"), row.get("occurredAt")])


def patch_page(op, ev):
    """patchQueue клиента: same — строка была на странице и место не изменилось; moved; absent."""
    lost = ev.get("incidentGuid") if ev.get("type") == "incident.access_lost" else None
    row = ev.get("incident")
    guid = lost or (row or {}).get("guid")
    if not guid:
        return "absent"
    with LOCK:
        page = op.page
        for i, item in enumerate(page):
            if item.get("guid") != guid:
                continue
            if lost:
                op.page = page[:i] + page[i + 1:]
                return "moved"
            try:
                if int(row.get("version")) < int(item.get("version")):
                    return "same"
            except (TypeError, ValueError):
                pass
            op.page = page[:i] + [row] + page[i + 1:]
            return "same" if place_of(row) == place_of(item) else "moved"
    return "absent"


def reconcile(op):
    """Сверка страницы раз в 12 с (план 84) и выборочная проверка: совпала ли своя страница с ответом сервера."""
    while not STOP.wait(12):
        # Запрос — тот, что сейчас на экране у оператора: он листает и меняет фильтры.
        q = {k: v for k, v in op.qs.items() if v is not None}
        q.setdefault("filter", "open"); q.setdefault("pageSize", 50)
        with LOCK:
            mine = [(r.get("guid"), r.get("version"), r.get("state")) for r in op.page]
        code, js = op.call("GET", "/operator/incidents?" + urllib.parse.urlencode(q), op="reload:check")
        if code != 200 or not isinstance(js, dict):
            continue
        items = js.get("items", [])
        theirs = [(r.get("guid"), r.get("version"), r.get("state")) for r in items]
        a, b = {g: (v, st) for g, v, st in mine}, {g: (v, st) for g, v, st in theirs}
        rec = {"who": op.who, "op": "check:page", "code": 0, "ms": 0, "bytes": 0, "same": mine == theirs,
               "rows": len(theirs), "missing": len(set(b) - set(a)), "extra": len(set(a) - set(b)),
               "stale": sum(1 for g in set(a) & set(b) if a[g] != b[g]),
               "order": [g for g, _, _ in mine if g in b] != [g for g, _, _ in theirs if g in a]}
        log(rec, CHK)
        with LOCK:
            op.page = list(items)


def make_reload(op):
    if RELOAD == "stream":
        page = Reloader(op, ["queue"], 3000)
        fast, slow = Reloader(op, ["card", "linked"], 1000), Reloader(op, SLOW_KEYS, 3000)
        threading.Thread(target=reconcile, args=(op,), daemon=True).start()

        def go(reset=False, ev=None):
            if reset:
                page.fire(True); fast.fire(True); slow.fire(True)
                return
            if ev is None or patch_page(op, ev) != "same":
                page.fire()
            if op.open:
                fast.fire()
            slow.fire()
        return go
    if RELOAD == "every":
        r = Reloader(op, ALL_KEYS, 0)
        return lambda reset=False: r.fire()
    if RELOAD == "throttle":
        fast, slow = Reloader(op, FAST_KEYS, 1000), Reloader(op, SLOW_KEYS, 3000)

        def go(reset=False):
            fast.fire(reset); slow.fire(reset)
        return go
    return None


def heartbeat(op):
    while not STOP.wait(15):
        op.call("POST", "/operator/session/heartbeat", {"openIncidentGuid": op.current} if op.current else {}, op="heartbeat")


def stream(op):
    last = None
    on_event = make_reload(op)
    while not STOP.is_set():
        c = http.client.HTTPSConnection(HOST, context=CTX, timeout=300)
        h = {"Authorization": "Bearer " + op.tok, "Accept": "text/event-stream"}
        if last:
            h["Last-Event-ID"] = last
        t0 = time.time()
        try:
            c.request("GET", BASE + "/operator/stream", headers=h)
            r = c.getresponse()
            log({"who": op.who, "op": "stream:open", "code": r.status, "ms": round((time.time() - t0) * 1000, 1), "bytes": 0})
            if r.status != 200:
                r.read(); STOP.wait(2); continue
            data = []
            while not STOP.is_set():
                line = r.readline()
                if not line:
                    break
                line = line.decode().rstrip("\r\n")
                if line.startswith("id:"):
                    last = line[3:].strip()
                elif line.startswith("data:"):
                    data.append(line[5:].strip())
                elif line == "" and data:
                    now = time.time()
                    try:
                        ev = json.loads("\n".join(data))
                    except ValueError:
                        ev = {}
                    data = []
                    ty = ev.get("type")
                    if on_event:
                        mine = op.id and (ev.get("actor") or {}).get("id") == op.id
                        if ty == "stream.reset":
                            on_event(True)
                        elif not mine or ty == "incident.card_evicted":
                            on_event(ev=ev) if RELOAD == "stream" else on_event()
                    if ty == "incident.created":
                        log({"who": op.who, "inc": ev.get("incidentGuid"), "type": ty, "id": ev.get("id")}, SLOG)
                    elif ty == "stream.reset":
                        log({"who": op.who, "op": "stream:reset", "code": 0, "ms": 0, "bytes": 0})
        except Exception as e:
            if not STOP.is_set():
                log({"who": op.who, "op": "stream:drop", "code": -1, "ms": round((time.time() - t0) * 1000, 1), "bytes": 0,
                     "err": str(e)[:120]})
        finally:
            c.close()
        if not STOP.is_set():
            log({"who": op.who, "op": "stream:reconnect", "code": 0, "ms": 0, "bytes": 0})
            if on_event:
                on_event(True)  # onReconnect: всё и сразу
            STOP.wait(1)


def emitter():
    n = 0
    ef = open(os.path.join(OUT, "emit.jsonl"), "w")
    while not STOP.is_set():
        label = f"{RUN}-{n}"
        t0 = time.time()
        r = subprocess.run(["python3", "-I", REPLAY, label], capture_output=True, text=True, timeout=300)
        ms = round((time.time() - t0) * 1000, 1)
        log({"who": "emu", "op": "replay", "label": label, "code": 0 if r.returncode == 0 else r.returncode, "ms": ms,
             "out": (r.stdout + r.stderr).strip()[-200:]})
        ef.write(json.dumps({"label": label, "t0": t0, "ms": ms, "rc": r.returncode}) + "\n"); ef.flush()
        with open(os.path.join(OUT, "labels.txt"), "a") as f:
            f.write(label + "\n")
        n += 1
        STOP.wait(max(0, EVERY - (time.time() - t0)))


def race():
    """Раз в 20 с два случайных оператора в один момент берут один новый инцидент."""
    rnd = random.Random(7)
    while not STOP.wait(20):
        if len(OPS) < 2:
            return
        a, b = rnd.sample(OPS, 2)
        code, js = a.call("GET", "/operator/incidents?filter=open&pageSize=50&sort=priority_then_oldest", op="race:queue")
        rows = [x for x in (js or {}).get("items", []) if x.get("state") == "new"] if code == 200 else []
        if not rows:
            continue
        row = rnd.choice(rows)
        gate = threading.Barrier(2)
        res, won = {}, {}

        def go(o):
            inc = dict(row)
            gate.wait()
            res[o.who] = transition(o, inc, "claim", opname="race:claim")
            if res[o.who] == 200:
                won[o.who] = (o, inc)
        ts = [threading.Thread(target=go, args=(o,)) for o in (a, b)]
        [t.start() for t in ts]; [t.join() for t in ts]
        log({"who": "race", "op": "race:verdict", "inc": row["guid"], "code": 0 if len(won) <= 1 else 1, "ms": 0,
             "codes": res, "wins": len(won)})
        for o, inc in won.values():
            transition(o, inc, "close", {"resultId": "false_alarm", "comment": "нагрузка: гонка"}, "race:close")


def summary():
    recs = [json.loads(l) for l in open(os.path.join(OUT, "log.jsonl"))]
    by = {}
    for r in recs:
        if r["op"] in ("outcome", "race:verdict"):
            continue
        by.setdefault(r["op"], []).append(r)
    ops = {}
    for op, rs in sorted(by.items()):
        ms = sorted(r["ms"] for r in rs)
        codes = {}
        for r in rs:
            k = str(r["code"]) + ("/" + str(r.get("err"))[:60] if r.get("err") else "")
            codes[k] = codes.get(k, 0) + 1
        pct = lambda p: ms[min(len(ms) - 1, int(len(ms) * p))]
        ops[op] = {"n": len(rs), "p50": pct(.5), "p95": pct(.95), "p99": pct(.99), "max": ms[-1], "codes": codes,
                   "bytes_avg": round(statistics.mean(r.get("bytes", 0) for r in rs))}
    reqs = [r for r in recs if r["who"].startswith("op") and r["op"] not in ("outcome",) and not r["op"].startswith("stream:")]
    # 501 NOT_IMPLEMENTED у вложений карточки — известная заглушка сервера, не сбой: считается отдельно
    known = sum(1 for r in reqs if r["op"] == "card:media" and r["code"] == 501)
    errs = sum(1 for r in reqs if (r["code"] >= 500 or r["code"] < 0) and not (r["op"] == "card:media" and r["code"] == 501))
    s = {"run": RUN, "operators": N, "every": EVERY, "minutes": MINUTES, "requests": len(reqs), "errors_5xx_net": errs,
         "err_share": round(errs / max(1, len(reqs)), 4), "media_501": known,
         "err_4xx_unexpected": sum(1 for r in reqs if 400 <= r["code"] < 500 and r["code"] not in (409, 412, 422) and r["op"] != "card:media"),
         "retries": sum(1 for r in reqs if r.get("retry")),
         "reload_mode": RELOAD,
         "reloads_per_op_min": {o.who: round(o.reloads / max(MINUTES, 1e-9), 1) for o in OPS},
         "transitions_ok": sum(1 for r in recs if r["op"] == "outcome" and r["code"] == 200), "ops": ops}
    json.dump(s, open(os.path.join(OUT, "summary.json"), "w"), ensure_ascii=False, indent=1)
    return s


if __name__ == "__main__":
    print("прогон", RUN, "→", OUT, flush=True)
    for i in range(1, N + 1):
        o = Op(i)
        if o.login() != 200:
            raise SystemExit("вход не удался: " + o.email)
        c, s = o.call("PUT", "/operator/session/agent-state", {"agentState": "ready"}, op="agent-state")
        c, s = o.call("GET", "/operator/session", op="session")
        o.id = (s or {}).get("operator", {}).get("guid")
        OPS.append(o)
    json.dump({o.who: o.id for o in OPS}, open(os.path.join(OUT, "ids.json"), "w"))
    load_refs(OPS[0])
    ths = [threading.Thread(target=flusher, daemon=True)]
    for o in OPS:
        ths += [threading.Thread(target=stream, args=(o,), daemon=True)]
    for t in ths:
        t.start()
    time.sleep(3)  # потоки SSE открыты до первой пачки
    more = [threading.Thread(target=emitter, daemon=True), threading.Thread(target=race, daemon=True)]
    for o in OPS:
        more += [threading.Thread(target=operator, args=(o,), daemon=True), threading.Thread(target=heartbeat, args=(o,), daemon=True)]
    for t in more:
        t.start()
    # досрочная остановка: файл <каталог>/.stop
    end = time.time() + MINUTES * 60
    while time.time() < end and not os.path.exists(os.path.join(OUT, ".stop")):
        STOP.wait(5)
    STOP.set()
    for t in more:
        t.join(timeout=60)
    time.sleep(2)
    with LOCK:
        LOG.flush(); SLOG.flush(); CHK.flush()
    s = summary()
    print(json.dumps({k: v for k, v in s.items() if k != "ops"}, ensure_ascii=False))
    for op, v in s["ops"].items():
        print(f"{op:24} n={v['n']:6} p50={v['p50']:8} p95={v['p95']:8} p99={v['p99']:8} max={v['max']:9} {v['codes']}")
    sys.stdout.flush()
    os._exit(0)
