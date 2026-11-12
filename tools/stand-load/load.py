#!/usr/bin/env python3
"""Нагрузочный прогон стенда: два оператора одновременно работают с инцидентами, эмулятор подаёт события.

Запуск: python3 -I load.py [минут] [сек между пачками событий]  (по умолчанию 10 и 60).
Пишет в imdb стенда: перед запуском снять дамп. Итог — load/out/<метка>/ (log.jsonl, summary.json, labels.txt).

Каждый оператор в цикле: читает очередь, берёт новый инцидент (иногда — тот же, что второй, чтобы проверить
гонку), иногда откладывает и возобновляет, иногда передаёт второму, закрывает. Принятие переданного — в его цикле.
Раз в 15 с — heartbeat с открытым инцидентом. Каждый запрос пишется: кто, что, код, время, версия.
"""
import json, os, random, ssl, subprocess, sys, threading, time, urllib.request, urllib.error, uuid, statistics

API = "https://axxonnet.test/api/v1/im-backend"
CA = os.path.expanduser("~/Work/axxoncloudgo/tools/util/rootCA.axxonnet.test.pem")
STAND = os.path.expanduser("~/Work/stand")
EMU = os.path.join(STAND, "bin/agent-emulator")
CTX = ssl.create_default_context(cafile=CA)
CTX.verify_flags &= ~ssl.VERIFY_X509_STRICT  # корневой сертификат стенда без Authority Key Identifier
MINUTES = float(sys.argv[1]) if len(sys.argv) > 1 else 10
EVERY = float(sys.argv[2]) if len(sys.argv) > 2 else 60
RUN = time.strftime("load-%Y%m%d-%H%M%S")
OUT = os.path.join(STAND, "load/out", RUN)
os.makedirs(OUT, exist_ok=True)
STOP = threading.Event()
LOCK = threading.Lock()
LOG = open(os.path.join(OUT, "log.jsonl"), "w")
HOLD_REASONS = ["third_party", "patrol", "no_data"]


def log(rec):
    rec["t"] = time.time()
    with LOCK:
        LOG.write(json.dumps(rec, ensure_ascii=False) + "\n")
        LOG.flush()


class Tokens:
    def __init__(self):
        self.lock = threading.Lock()
        self.refresh()

    def refresh(self):
        with self.lock:
            out = subprocess.run(["bash", os.path.join(STAND, "load/tokens.sh")], capture_output=True, text=True, timeout=120)
            parts = out.stdout.split()
            if len(parts) != 4:
                raise SystemExit("вход не удался: " + out.stderr.strip()[-300:])
            self.tok = {"A": parts[0], "B": parts[2]}
            self.id = {"A": parts[1], "B": parts[3]}
            self.at = time.time()


TOK = Tokens()


def call(who, method, path, body=None, headers=None, op=None):
    h = {"Authorization": "Bearer " + TOK.tok[who]}
    data = None
    if body is not None:
        data = json.dumps(body).encode()
        h["Content-Type"] = "application/json"
    h.update(headers or {})
    req = urllib.request.Request(API + path, data=data, method=method, headers=h)
    t0 = time.time()
    code, raw, hdr = 0, b"", {}
    try:
        with urllib.request.urlopen(req, context=CTX, timeout=60) as r:
            code, raw, hdr = r.status, r.read(), dict(r.headers)
    except urllib.error.HTTPError as e:
        code, raw, hdr = e.code, e.read(), dict(e.headers)
    except Exception as e:  # сеть, таймаут
        code, raw = -1, str(e).encode()
    ms = (time.time() - t0) * 1000
    try:
        js = json.loads(raw) if raw else None
    except ValueError:
        js = None
    rec = {"who": who, "op": op or method + " " + path.split("?")[0], "code": code, "ms": round(ms, 1)}
    if code >= 400 or code < 0:
        rec["err"] = (js or {}).get("code") if isinstance(js, dict) else raw[:200].decode(errors="replace")
        rec["key"] = (js or {}).get("messageKey") if isinstance(js, dict) else None
    log(rec)
    if code == 401 and time.time() - TOK.at > 30:
        TOK.refresh()
    return code, js, hdr, rec


def transition(who, inc, tid, form=None, op=None):
    body = {"surface": "card"}
    if form:
        body["formValues"] = form
    code, js, _, rec = call(who, "POST", f"/operator/incidents/{inc['guid']}/transitions/{tid}", body,
                            {"If-Match": '"%s"' % inc["version"]}, op=op or "transition:" + tid)
    rec2 = {"who": who, "op": "outcome", "tid": tid, "inc": inc["guid"], "code": code,
            "from": inc.get("state"), "to": (js or {}).get("incident", {}).get("state") if code == 200 else None}
    log(rec2)
    if code == 200:
        inc.update(js["incident"])
    return code


def queue(who, filt="open"):
    code, js, _, _ = call(who, "GET", f"/operator/incidents?filter={filt}&pageSize=100&sort=createdAt", op="queue:" + filt)
    return (js or {}).get("items", []) if code == 200 else []


def card(who, guid):
    code, js, _, _ = call(who, "GET", f"/operator/incidents/{guid}", op="card")
    return js if code == 200 else None


CURRENT = {"A": None, "B": None}


def heartbeat(who):
    while not STOP.wait(15):
        call(who, "POST", "/operator/session/heartbeat", {"openIncidentGuid": CURRENT[who]} if CURRENT[who] else {}, op="heartbeat")


def operator(who):
    other = "B" if who == "A" else "A"
    rnd = random.Random(hash(who) + int(time.time()))
    while not STOP.is_set():
        # 1. Переданные мне — принять.
        for row in queue(who, "inbox"):
            if STOP.is_set():
                break
            if row.get("state") == "pending_acceptance":
                inc = card(who, row["guid"])
                if inc and inc.get("state") == "pending_acceptance" and inc.get("ownership") == "target":
                    if transition(who, inc, "accept") != 200:
                        continue
                    CURRENT[who] = inc["guid"]
                    work(who, other, inc, rnd, allow_transfer=False)
                elif inc:
                    log({"who": who, "op": "inbox:stale", "code": 0, "ms": 0, "inc": row["guid"],
                         "state": inc.get("state"), "ownership": inc.get("ownership")})
        # 2. Новый — взять. Иногда целимся в тот же, что и второй (первый в списке), иначе — случайный.
        rows = [r for r in queue(who) if r.get("state") == "new"]
        if not rows:
            STOP.wait(2)
            continue
        row = rows[0] if rnd.random() < 0.3 else rnd.choice(rows)
        inc = card(who, row["guid"])
        if not inc or inc.get("state") != "new":
            continue
        if transition(who, inc, "claim") != 200:
            continue
        CURRENT[who] = inc["guid"]
        work(who, other, inc, rnd, allow_transfer=True)
        STOP.wait(rnd.uniform(0.5, 2))


def work(who, other, inc, rnd, allow_transfer):
    # После «стоп» инцидент не бросаем на середине и новых запросов не начинаем: взятый остаётся взятым.
    STOP.wait(rnd.uniform(0.5, 2))
    if STOP.is_set():
        return
    if inc.get("state") != "in_progress":
        return
    if rnd.random() < 0.25:
        if transition(who, inc, "hold", {"reasonId": rnd.choice(HOLD_REASONS), "comment": "нагрузка: удержание"}) == 200:
            STOP.wait(rnd.uniform(1, 3))
            transition(who, inc, "resume")
    if allow_transfer and rnd.random() < 0.2:
        if transition(who, inc, "transfer", {"targetId": TOK.id[other], "comment": "нагрузка: передача"}) == 200:
            CURRENT[who] = None
            return
    STOP.wait(rnd.uniform(0.5, 2))
    code = transition(who, inc, "close", {"resultId": "false_alarm", "comment": "нагрузка: закрытие"})
    if code == 412:  # версия ушла (эскалация, таймер) — перечитать и закрыть ещё раз
        fresh = card(who, inc["guid"])
        if fresh and fresh.get("state") == "in_progress":
            inc.update(fresh)
            transition(who, inc, "close", {"resultId": "false_alarm", "comment": "нагрузка: закрытие"}, op="transition:close-retry")
    CURRENT[who] = None


def emitter():
    n = 0
    while not STOP.is_set():
        label = f"{RUN}-{n}"
        t0 = time.time()
        r = subprocess.run([EMU, "replay", "--run", label], capture_output=True, text=True, timeout=300)
        ok = r.returncode == 0
        log({"who": "emu", "op": "replay", "label": label, "code": 0 if ok else r.returncode,
             "ms": round((time.time() - t0) * 1000, 1), "out": (r.stdout + r.stderr).strip()[-200:]})
        with open(os.path.join(OUT, "labels.txt"), "a") as f:
            f.write(label + "\n")
        n += 1
        STOP.wait(max(0, EVERY - (time.time() - t0)))


def refresher():
    while not STOP.wait(240):
        TOK.refresh()


def race():
    """Раз в 20 с оба оператора в один момент делают одно и то же с одним инцидентом: claim нового,
    или один закрывает, а другой (через тестовый вход не нужен) пытается взять уже взятый.
    Ждём ровно один 200, второй — отказ 409/412/422, без 5xx."""
    rnd = random.Random(7)
    while not STOP.wait(20):
        rows = [r for r in queue("A") if r.get("state") == "new"]
        if not rows:
            continue
        row = rnd.choice(rows)
        gate = threading.Barrier(2)
        res = {}

        def go(who):
            inc = dict(row)
            gate.wait()
            res[who] = transition(who, inc, "claim", op="race:claim")
            if res[who] == 200:
                CURRENT_RACE[who] = inc

        ts = [threading.Thread(target=go, args=(w,)) for w in ("A", "B")]
        [t.start() for t in ts]
        [t.join() for t in ts]
        wins = [w for w, c in res.items() if c == 200]
        log({"who": "race", "op": "race:verdict", "inc": row["guid"], "code": 0 if len(wins) <= 1 else 1,
             "ms": 0, "codes": res, "wins": len(wins)})
        for w in wins:  # победитель закрывает, проигравший одновременно пытается закрыть чужой
            inc = CURRENT_RACE.pop(w)
            loser = "B" if w == "A" else "A"
            gate2 = threading.Barrier(2)
            r2 = {}

            def fin(who, inc_view):
                gate2.wait()
                r2[who] = transition(who, inc_view, "close", {"resultId": "false_alarm", "comment": "нагрузка: гонка"},
                                     op="race:close")

            t1 = threading.Thread(target=fin, args=(w, inc))
            t2 = threading.Thread(target=fin, args=(loser, dict(inc)))
            [t.start() for t in (t1, t2)]
            [t.join() for t in (t1, t2)]
            log({"who": "race", "op": "race:close-verdict", "inc": row["guid"],
                 "code": 0 if list(r2.values()).count(200) <= 1 else 1, "ms": 0, "codes": r2})


CURRENT_RACE = {}


def summary():
    recs = [json.loads(l) for l in open(os.path.join(OUT, "log.jsonl"))]
    by = {}
    for r in recs:
        if r["op"] == "outcome":
            continue
        by.setdefault(r["op"], []).append(r)
    ops = {}
    for op, rs in sorted(by.items()):
        ms = sorted(r["ms"] for r in rs)
        codes = {}
        for r in rs:
            k = str(r["code"]) + ("/" + str(r.get("err")) if r.get("err") else "")
            codes[k] = codes.get(k, 0) + 1
        pct = lambda p: ms[min(len(ms) - 1, int(len(ms) * p))]
        ops[op] = {"n": len(rs), "avg": round(statistics.mean(ms), 1), "p50": pct(.5), "p95": pct(.95), "p99": pct(.99),
                   "max": ms[-1], "codes": codes}
    outs = [r for r in recs if r["op"] == "outcome"]
    s = {"run": RUN, "minutes": MINUTES, "ops": ops,
         "transitions_ok": sum(1 for r in outs if r["code"] == 200),
         "server_errors": sum(1 for r in recs if r["code"] >= 500 or r["code"] < 0 and r["who"] != "emu")}
    json.dump(s, open(os.path.join(OUT, "summary.json"), "w"), ensure_ascii=False, indent=1)
    return s


if __name__ == "__main__":
    print("прогон", RUN, "→", OUT, flush=True)
    json.dump(TOK.id, open(os.path.join(OUT, "ids.json"), "w"))
    ths = [threading.Thread(target=f, args=a, daemon=True) for f, a in
           [(emitter, ()), (refresher, ()), (race, ()), (operator, ("A",)), (operator, ("B",)), (heartbeat, ("A",)), (heartbeat, ("B",))]]
    for t in ths:
        t.start()
    STOP.wait(MINUTES * 60)
    STOP.set()
    for t in ths:
        t.join(timeout=60)  # дождаться, пока каждый поток допишет начатый запрос в журнал прогона
    s = summary()
    print(json.dumps({k: v for k, v in s.items() if k != "ops"}, ensure_ascii=False))
    for op, v in s["ops"].items():
        print(f"{op:28} n={v['n']:5} p50={v['p50']:7} p95={v['p95']:7} max={v['max']:8} {v['codes']}")
