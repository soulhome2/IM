#!/usr/bin/env python3
"""План 99, этап 2, П6: повтор того же idempotencyKey на другом узле — тот же ответ, действие одно.
  python3 -I p6_idem.py <порты через запятую, прямо на узлы> <каталог итога>
test@ (облако). Новые инциденты берутся из очереди после пачки событий (replay_dev.py на :5000). Части:
  а) «взять» с ключом на узле X, тот же запрос на Y и Z: код и тело (кроме ничего) побайтно как у первого; строк журнала «claim» у инцидента одна;
  б) то же одновременно на двух узлах (барьер): оба ответа 200 и совпадают; строка журнала одна;
  в) одновременно на всех узлах; г) другой ключ на том же инциденте после первого — отказ по состоянию, строка журнала всё ещё одна."""
import http.client, json, os, random, ssl, subprocess, sys, threading, time, uuid
PORTS = [int(x) for x in sys.argv[1].split(",")]; OUT = sys.argv[2]; os.makedirs(OUT, exist_ok=True)
CA = os.path.expanduser("~/Work/axxoncloudgo/tools/util/rootCA.axxonnet.test.pem")
CTX = ssl.create_default_context(cafile=CA); CTX.verify_flags &= ~ssl.VERIFY_X509_STRICT
API = "/api/v1/im-backend/operator"
DBC = subprocess.run("docker ps --format '{{.Names}}' | grep '^ac_db'", shell=True, capture_output=True, text=True).stdout.split()[0]
def sql(q):
    r = subprocess.run(["docker", "exec", DBC, "psql", "-U", "postgres", "imdb", "-Atc", q], capture_output=True, text=True)
    if r.returncode: raise RuntimeError(r.stderr)
    return r.stdout.strip()
pw = open(os.path.expanduser("~/Work/stand/test-operator.pass")).read().rstrip("\n")
c = http.client.HTTPSConnection("axxonnet.test", context=CTX, timeout=30)
c.request("POST", "/api/v3/ac-backend/users/login", json.dumps({"email": "test@axxonnet.test", "password": pw}), {"Content-Type": "application/json"})
TOK = json.loads(c.getresponse().read())["accessToken"]; c.close()
def call(port, m, p, body=None):
    cn = http.client.HTTPConnection("127.0.0.1", port, timeout=60)
    h = {"Authorization": "Bearer " + TOK, "Content-Type": "application/json"}
    t = time.time(); cn.request(m, API + p, json.dumps(body) if body is not None else None, h); r = cn.getresponse(); raw = r.read(); cn.close()
    return r.status, raw, round((time.time() - t) * 1000), r.getheader("ETag")
def news(n):
    got = []; seen = set()
    for rep in range(10):
        for s in ("priority_then_newest", "priority_then_oldest", "oldest_first", "reaction_deadline"):
            code, raw, _, _ = call(PORTS[0], "GET", "/incidents?filter=open&pageSize=50&sort=" + s)
            for x in json.loads(raw).get("items", []):
                if x.get("state") == "new" and x["guid"] not in seen:
                    seen.add(x["guid"]); got.append(x["guid"])
        if len(got) >= n: break
        subprocess.run(["python3", "-I", os.path.expanduser("~/Work/stand/load/replay_dev.py"), "p6" + uuid.uuid4().hex[:8]], capture_output=True)
    assert len(got) >= n, "новых инцидентов %d из %d" % (len(got), n)
    return got[:n]
def body_for(guid):
    code, raw, _, _ = call(PORTS[0], "GET", "/incidents/" + guid); inc = json.loads(raw); inc = inc.get("incident", inc)
    return {"surface": "card", "expectedState": inc.get("state"), "expectedAddressee": (inc.get("addressee") or {}).get("id") or "",
            "expectedPriority": inc.get("priority"), "journalSeen": inc.get("journalSeq") or 0}
def claims(guid): return int(sql("select count(*) from incident_journal where incident_guid='%s' and transition='claim'" % guid))
res = {"a": [], "b": [], "c": [], "d": []}; fails = []
def check(name, ok, d):
    print(("OK   " if ok else "FAIL ") + name + ": " + d, flush=True)
    if not ok: fails.append(name + ": " + d)
# а) последовательно X → Y → Z
gs = news(10)
for g in gs:
    body = body_for(g); body["idempotencyKey"] = "p6a-" + uuid.uuid4().hex
    order = random.sample(PORTS, min(3, len(PORTS)))
    rs = [call(p, "POST", "/incidents/%s/transitions/claim" % g, body) for p in order]
    same = all(r[0] == rs[0][0] and r[1] == rs[0][1] and r[3] == rs[0][3] for r in rs)
    n = claims(g)
    res["a"].append({"inc": g, "ports": order, "codes": [r[0] for r in rs], "ms": [r[2] for r in rs], "same": same, "journal_claims": n})
    check("а) %s %s" % (g[:8], order), rs[0][0] == 200 and same and n == 1, "коды %s, ответы одинаковы %s, строк claim %d" % ([r[0] for r in rs], same, n))
# б) одновременно на двух узлах; в) на всех
def together(ports, g, body):
    bar = threading.Barrier(len(ports)); out = [None] * len(ports)
    def go(i):
        bar.wait(); out[i] = call(ports[i], "POST", "/incidents/%s/transitions/claim" % g, body)
    ts = [threading.Thread(target=go, args=(i,)) for i in range(len(ports))]
    [t.start() for t in ts]; [t.join() for t in ts]; return out
for kind, ports, cnt in (("b", PORTS[:2], 20), ("c", PORTS, 10)):
    for g in news(cnt):
        body = body_for(g); body["idempotencyKey"] = "p6%s-" % kind + uuid.uuid4().hex
        rs = together(ports, g, body)
        same = all(r[0] == rs[0][0] and r[1] == rs[0][1] for r in rs); n = claims(g)
        res[kind].append({"inc": g, "codes": [r[0] for r in rs], "ms": [r[2] for r in rs], "same": same, "journal_claims": n})
        check("%s) %s" % (kind, g[:8]), rs[0][0] == 200 and same and n == 1, "коды %s, мс %s, одинаковы %s, строк claim %d" % ([r[0] for r in rs], [r[2] for r in rs], same, n))
# г) другой ключ на том же инциденте — отказ, действие не повторилось
for g in gs[:5]:
    body = body_for(g); body["idempotencyKey"] = "p6d-" + uuid.uuid4().hex
    r = call(random.choice(PORTS), "POST", "/incidents/%s/transitions/claim" % g, body); n = claims(g)
    res["d"].append({"inc": g, "code": r[0], "journal_claims": n})
    check("г) %s" % g[:8], r[0] >= 400 and n == 1, "код %d, строк claim %d" % (r[0], n))
json.dump({"res": res, "fails": fails}, open(OUT + "/p6.json", "w"), ensure_ascii=False, indent=1)
print("П6: %s, расхождений %d" % ("ВСЁ СОШЛОСЬ" if not fails else "ЕСТЬ ПАДЕНИЯ", len(fails)))
sys.exit(1 if fails else 0)
