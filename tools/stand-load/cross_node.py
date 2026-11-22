#!/usr/bin/env python3
"""План 99, задача 7б, шаги 3 и 6: «запись на A — чтение на B» по таблице П1–П8.

  python3 -I cross_node.py <портA> <портB> <каталог итога> [только=П1a,П2,…]

A и B — два процесса сервера МИ на одной базе, оба напрямую (без nginx), токены из облака (https://axxonnet.test).
Сравнение — с SQL в базе imdb стенда (docker exec ac_db). Итог: <каталог>/cross.json (по шагам) и таблица в stdout.
Пишет в imdb (мягкое удаление инцидентов, правка правил доступа и членства группы, версия настроек, а в конце сброс МИ):
перед запуском — копия базы, после запуска — откат из неё. Шаги: П1a (SQL руками), П2 (правило доступа), П3 (состав группы),
П4 (публикация настроек поста), П5 (лидер такта, метка), П8 (seen_ms, адресаты передачи), П1b (сброс МИ, в самом конце).
"""
import http.client, json, os, ssl, subprocess, sys, time, urllib.parse

PA, PB, OUT = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
ONLY = None
for a in sys.argv[4:]:
    if a.startswith("только="):
        ONLY = set(a.split("=", 1)[1].split(","))
os.makedirs(OUT, exist_ok=True)
CA = os.path.expanduser("~/Work/axxoncloudgo/tools/util/rootCA.axxonnet.test.pem")
CTX = ssl.create_default_context(cafile=CA)
CTX.verify_flags &= ~ssl.VERIFY_X509_STRICT
API = "/api/v1/im-backend"
DBC = subprocess.run("docker ps --format '{{.Names}}' | grep '^ac_db'", shell=True, capture_output=True, text=True).stdout.split()[0]
RESULTS = []


def sql(q):
    r = subprocess.run(["docker", "exec", DBC, "psql", "-U", "postgres", "imdb", "-Atc", q], capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError("sql: " + r.stderr.strip())
    return r.stdout.strip()


def cloud_login(email, password):
    c = http.client.HTTPSConnection("axxonnet.test", context=CTX, timeout=30)
    c.request("POST", "/api/v3/ac-backend/users/login", json.dumps({"email": email, "password": password}), {"Content-Type": "application/json"})
    r = c.getresponse(); raw = r.read(); c.close()
    if r.status != 200:
        raise RuntimeError("login %s → %s" % (email, r.status))
    return json.loads(raw)["accessToken"]


def test_pass():
    return open(os.path.expanduser("~/Work/stand/test-operator.pass")).read().rstrip("\n")


class Node:
    def __init__(self, port, name):
        self.port, self.name = port, name

    def call(self, method, path, tok, body=None, headers=None, timeout=60):
        c = http.client.HTTPConnection("127.0.0.1", self.port, timeout=timeout)
        h = {"Authorization": "Bearer " + tok}
        data = None
        if body is not None:
            data = json.dumps(body); h["Content-Type"] = "application/json"
        h.update(headers or {})
        t = time.time()
        try:
            c.request(method, API + path, data, h)
            r = c.getresponse(); raw = r.read()
        finally:
            c.close()
        try:
            js = json.loads(raw) if raw else None
        except Exception:
            js = raw.decode("utf-8", "replace")[:300]
        return r.status, js, round((time.time() - t) * 1000), dict(r.getheaders())


A, B = Node(PA, "A"), Node(PB, "B")


def record(step, ok, detail, **kw):
    RESULTS.append({"step": step, "ok": ok, "detail": detail, **kw})
    print(("OK   " if ok else "FAIL ") + step + ": " + detail, flush=True)


def want(step):
    return ONLY is None or step in ONLY


def counters(node, tok):
    code, js, ms, _ = node.call("GET", "/operator/incidents/counters", tok)
    if code != 200:
        raise RuntimeError("counters %s → %s %s" % (node.name, code, js))
    return js


def wait_until(fn, timeout, every=1.0):
    t0 = time.time()
    while True:
        v = fn()
        if v is not None:
            return v, round(time.time() - t0, 1)
        if time.time() - t0 > timeout:
            return None, round(time.time() - t0, 1)
        time.sleep(every)


def converge(tok, target, nodes, timeout):
    """Сколько секунд узлу нужно, чтобы открытых в счётчике стало target; None — не дошёл."""
    res = {}
    t0 = time.time()
    pending = {n.name: n for n in nodes}
    last = {}
    while pending and time.time() - t0 < timeout:
        for name, n in list(pending.items()):
            v = counters(n, tok)["open"]
            last[name] = v
            if v == target:
                res[name] = round(time.time() - t0, 1); del pending[name]
        if pending:
            time.sleep(1.0)
    for name in pending:
        res[name] = None
    return res, last


ADMIN = cloud_login("test@axxonnet.test", test_pass())

# ---------------------------------------------------------------- П1a: SQL руками
if want("П1a"):
    try:
        base_a, base_b = counters(A, ADMIN)["open"], counters(B, ADMIN)["open"]
        MARK = "2000-01-01 00:00:00+00"
        t0 = time.time()
        nn = sql("with u as (update incidents set deleted_at='%s' where guid in (select guid from incidents where deleted_at is null and state<>'closed' order by random() limit 4000) returning 1) select count(*) from u" % MARK)
        # узел, уже севший на сверку, увидит запись при следующей сверке (раз в минуту)
        got = None
        deadline = time.time() + 200
        va = vb = None
        ta = tb = None
        while time.time() < deadline and (ta is None or tb is None):
            if ta is None:
                va = counters(A, ADMIN)["open"]
                if va != base_a: ta = round(time.time() - t0, 1)
            if tb is None:
                vb = counters(B, ADMIN)["open"]
                if vb != base_b: tb = round(time.time() - t0, 1)
            time.sleep(1.0)
        time.sleep(2)
        fa, fb = counters(A, ADMIN)["open"], counters(B, ADMIN)["open"]
        # возврат
        t1 = time.time()
        sql("update incidents set deleted_at=null where deleted_at='%s'" % MARK)
        back, last = converge(ADMIN, base_a, [A, B], 200)
        record("П1a SQL руками (мягкое удаление 4000 живых)", ta is not None and tb is not None and fa == fb and None not in back.values(),
               "открытых у test@ до %s/%s; изменение заметили: A через %s с, B через %s с; после %s/%s; возврат: A %s с, B %s с (сверка раз в минуту)" %
               (base_a, base_b, ta, tb, fa, fb, back.get("A"), back.get("B")),
               before=[base_a, base_b], after=[fa, fb], seen_after_s={"A": ta, "B": tb}, back_s=back)
    except Exception as e:
        record("П1a SQL руками", False, "ошибка: %r" % e)

# ---------------------------------------------------------------- П2: правило доступа
rules_deleted = []
if want("П2"):
    try:
        code, groups, _, _ = A.call("GET", "/access-rules", ADMIN)
        cand = []
        for g in groups:
            if g["id"] == 1:
                cand = [r for r in g["rules"] if r.get("sourceGroup")]
        done = False
        for r in cand[:8]:
            base_a, base_b = counters(A, ADMIN)["open"], counters(B, ADMIN)["open"]
            code, js, _, _ = A.call("DELETE", "/access-rules", ADMIN, [r["guid"]])
            if code not in (200, 204):
                record("П2 правило доступа", False, "DELETE /access-rules → %s %s" % (code, js)); done = True; break
            t0 = time.time()
            va, vb = counters(A, ADMIN)["open"], counters(B, ADMIN)["open"]
            dt = round(time.time() - t0, 2)
            changed = va != base_a
            if not changed:
                # правило ничего не меняло у test@ — вернуть и взять следующее
                A.call("POST", "/access-rules", ADMIN, {"userGroupID": 1, "rules": [{"sourceGroupGuid": r["sourceGroup"]["guid"]}]})
                continue
            time.sleep(1)
            vb2 = counters(B, ADMIN)["open"]
            code, js, _, _ = A.call("POST", "/access-rules", ADMIN, {"userGroupID": 1, "rules": [{"sourceGroupGuid": r["sourceGroup"]["guid"]}]})
            res, last = converge(ADMIN, base_a, [A, B], 30)
            record("П2 правило доступа (удалить на A, прочитать на B)", va == vb and va != base_a and None not in res.values(),
                   "правило группы «%s»: открытых у test@ до %s/%s, сразу после удаления A=%s B=%s (через %s с после ответа), через 1 с B=%s; правило создано заново — возврат A %s с, B %s с" %
                   (r["sourceGroup"]["name"], base_a, base_b, va, vb, dt, vb2, res.get("A"), res.get("B")),
                   before=[base_a, base_b], after=[va, vb], back_s=res)
            done = True
            break
        if not done:
            record("П2 правило доступа", False, "ни одно правило cloud-admin не меняет счётчик test@")
    except Exception as e:
        record("П2 правило доступа", False, "ошибка: %r" % e)

# ---------------------------------------------------------------- П3: состав группы устройств (дерево)
if want("П3"):
    try:
        srcs = sql("""select e.source_guid, count(*) c from incidents i join events e on e.guid=i.event_guid
                      where i.deleted_at is null and i.state<>'closed' and e.source_guid in (select source_guid from source_group_memberships)
                      group by 1 order by 2 desc limit 12""").split("\n")
        done = False
        for row in srcs:
            s, c = row.split("|")
            groups = sql("select group_guid from source_group_memberships where source_guid='%s'" % s).split()
            if not groups:
                continue
            base_a, base_b = counters(A, ADMIN)["open"], counters(B, ADMIN)["open"]
            for g in groups:
                A.call("DELETE", "/sources/groups/%s/memberships" % g, ADMIN, {"sourceGuids": [s]})
            t0 = time.time()
            va, vb = counters(A, ADMIN)["open"], counters(B, ADMIN)["open"]
            dt = round(time.time() - t0, 2)
            time.sleep(1)
            vb2 = counters(B, ADMIN)["open"]
            for g in groups:
                A.call("POST", "/sources/groups/%s/memberships" % g, ADMIN, {"sourceGuids": [s]})
            if va == base_a:
                continue
            res, last = converge(ADMIN, base_a, [A, B], 30)
            record("П3 состав групп устройств (убрать устройство из всех групп на A, прочитать на B)", va == vb == vb2 and None not in res.values(),
                   "устройство %s (%s живых) убрано из %d групп: открытых у test@ до %s/%s, сразу после A=%s B=%s (%s с после ответа), через 1 с B=%s; возврат: A %s с, B %s с" %
                   (s[:8], c, len(groups), base_a, base_b, va, vb, dt, vb2, res.get("A"), res.get("B")), before=[base_a, base_b], after=[va, vb], back_s=res)
            done = True
            break
        if not done:
            record("П3 состав группы", False, "не нашлось устройства, чьё удаление из групп меняет счётчик test@")
    except Exception as e:
        record("П3 состав группы", False, "ошибка: %r" % e)

# ---------------------------------------------------------------- П4: публикация настроек поста
if want("П4"):
    try:
        OPT = cloud_login("load-op-06@axxonnet.test", "111111")
        def limit(n):
            c, js, _, _ = n.call("GET", "/operator/session", OPT)
            return (js or {}).get("limits", {}).get("maxOnHold") if c == 200 else "код %s" % c
        code, act, _, hdr = A.call("GET", "/operator/workflow/active", ADMIN)
        old = act["limits"]["maxOnHold"]
        new = old + 1 if old < 9 else old - 1
        la0, lb0 = limit(A), limit(B)
        draft = json.loads(json.dumps(act)); draft["limits"]["maxOnHold"] = new
        code, js, _, _ = A.call("POST", "/operator/workflow/schemas", ADMIN, draft)
        guid = (js.get("schema") or {}).get("guid") or (js.get("schema") or {}).get("schemaGuid") or js.get("guid")
        A.call("POST", "/operator/workflow/schemas/%s/validate" % guid, ADMIN)
        t0 = time.time()
        code, js, _, _ = A.call("POST", "/operator/workflow/schemas/%s/publish" % guid, ADMIN)
        pub_ok = code == 200
        la1 = limit(A)
        lb1, dt = wait_until(lambda: (lambda v: v if v == new else None)(limit(B)), 30, 0.25)
        # откат: общая машина с прежним значением
        back = json.loads(json.dumps(act))
        code, js, _, _ = A.call("POST", "/operator/workflow/schemas", ADMIN, back)
        g2 = (js.get("schema") or {}).get("guid") or (js.get("schema") or {}).get("schemaGuid") or js.get("guid")
        A.call("POST", "/operator/workflow/schemas/%s/validate" % g2, ADMIN)
        A.call("POST", "/operator/workflow/schemas/%s/publish" % g2, ADMIN)
        lb2, dt2 = wait_until(lambda: (lambda v: v if v == old else None)(limit(B)), 30, 0.25)
        record("П4 публикация настроек поста на A — машина на B", pub_ok and lb1 == new and lb2 == old,
               "лимит maxOnHold в сессии оператора (из машины в памяти процесса): до A=%s B=%s; после публикации %s→%s: A=%s, B=%s через %s с; откат: B=%s через %s с" %
               (la0, lb0, old, new, la1, lb1, dt, lb2, dt2), seconds={"publish_to_B": dt, "rollback_to_B": dt2})
    except Exception as e:
        record("П4 публикация настроек", False, "ошибка: %r" % e)

# ---------------------------------------------------------------- П8: seen_ms и адресаты передачи
if want("П8"):
    try:
        op = cloud_login("load-op-05@axxonnet.test", "111111")
        code, _, _, _ = A.call("PUT", "/operator/session/agent-state", op, {"agentState": "ready"})
        code2, _, _, _ = A.call("POST", "/operator/session/heartbeat", op, {})
        time.sleep(1)
        code, sess, _, _ = A.call("GET", "/operator/session", op)
        uid = sess["operator"]["guid"]
        seen_sql = sql("select seen_ms, last_activity_ms, agent_state from operator_sessions where user_id=%s" % uid)
        def view(n):
            c1, tt, _, _ = n.call("GET", "/operator/transfer-targets", ADMIN)
            c2, pp, _, _ = n.call("GET", "/operator/admin/people", ADMIN)
            tt = sorted([(t["id"], t["kind"], t["available"], t.get("availabilityLabel")) for t in tt], key=str) if c1 == 200 else c1
            pp = sorted([(p["id"], p.get("stale")) for p in pp], key=str) if c2 == 200 else c2
            return tt, pp
        ta, pa = view(A); tb, pb = view(B)
        same_t, same_p = ta == tb, pa == pb
        diff = ""
        if not same_t and isinstance(ta, list) and isinstance(tb, list):
            diff = "; расходятся в адресатах: %s" % [x for x in ta if x not in tb][:3] + [x for x in tb if x not in ta][:3].__repr__()
        record("П8 адресаты передачи и люди (seen)", same_t and same_p,
               "оператор %s: agent-state=ready и пульс на A; в базе seen_ms/last_activity/state = %s; адресатов A=%s B=%s, одинаковы=%s; people одинаковы=%s%s" %
               (uid, seen_sql, len(ta) if isinstance(ta, list) else ta, len(tb) if isinstance(tb, list) else tb, same_t, same_p, diff),
               sql_row=seen_sql, transfer_same=same_t, people_same=same_p)
        # смена состояния на A: у адресата передачи «available» на B
        code3, js3, _, _ = A.call("PUT", "/operator/session/agent-state", op, {"agentState": "offline"})
        time.sleep(1)
        def avail(n):
            c, tt, _, _ = n.call("GET", "/operator/transfer-targets", ADMIN)
            return [(t["available"], t.get("availabilityLabel")) for t in tt if t["id"] == uid] if c == 200 else c
        av_a, av_b = avail(A), avail(B)
        A.call("PUT", "/operator/session/agent-state", op, {"agentState": "ready"})
        record("П8 смена состояния на A — адресат на B", code3 == 200 and av_a == av_b,
               "agent-state offline → %s; адресат %s: на A %s, на B %s" % (code3, uid, av_a, av_b), a=av_a, b=av_b)
        # пульс на B: адресаты видны на A?
        B.call("POST", "/operator/session/heartbeat", op, {})
        time.sleep(1)
        ta2, _ = view(A); tb2, _ = view(B)
        record("П8 после пульса на B", ta2 == tb2, "адресаты A и B одинаковы=%s" % (ta2 == tb2))
    except Exception as e:
        record("П8 адресаты и seen", False, "ошибка: %r" % e)

# ---------------------------------------------------------------- П5: лидер такта (метка)
if want("П5"):
    try:
        rows = []
        for i in range(12):
            r = sql("select (extract(epoch from now())*1000)::bigint - tick_ms, sweep_after from scheduler_marks order by tick_ms desc limit 1")
            n_locks = sql("select count(*) from pg_locks where locktype='advisory' and granted")
            rows.append((r, n_locks)); time.sleep(1)
        ages = [int(r.split("|")[0]) for r, _ in rows]
        record("П5 метка планировщика в таблице scheduler_marks", max(ages) < 15000 and all(n == "1" for _, n in rows),
               "возраст метки за 12 с: %s мс; замков лидера в базе: %s" % (ages, sorted(set(n for _, n in rows))), ages=ages)
    except Exception as e:
        record("П5 лидер такта", False, "ошибка: %r" % e)

# ---------------------------------------------------------------- П1b: сброс МИ (в самом конце, стирает данные МИ)
if want("П1b"):
    try:
        base_a, base_b = counters(A, ADMIN)["open"], counters(B, ADMIN)["open"]
        t0 = time.time()
        code, js, ms, _ = A.call("POST", "/operator/admin/reset", ADMIN, {"password": test_pass(), "confirm": "RESET"}, timeout=3600)
        rb = counters(B, ADMIN)["open"]; dt = round(time.time() - t0, 2)
        ra = counters(A, ADMIN)["open"]
        record("П1b сброс МИ на A — счётчик на B", code == 200 and rb == 0 and ra == 0,
               "сброс → %s за %s мс; открытых у test@ до A=%s B=%s; сразу после сброса A=%s, B=%s (через %s с после начала запроса); в базе живых: %s" %
               (code, ms, base_a, base_b, ra, rb, dt, sql("select count(*) from incidents where deleted_at is null and state<>'closed'")), code=code)
    except Exception as e:
        record("П1b сброс МИ", False, "ошибка: %r" % e)

json.dump(RESULTS, open(os.path.join(OUT, "cross.json"), "w"), ensure_ascii=False, indent=1)
print("итог: %d шагов, FAIL %d" % (len(RESULTS), sum(1 for r in RESULTS if not r["ok"])))
