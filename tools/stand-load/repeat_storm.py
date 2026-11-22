#!/usr/bin/env python3
"""План 99, этап 2, шаг 5: повторы idempotencyKey во время падения узла.
  python3 -I repeat_storm.py <адрес балансировщика host:port> <секунд> <потоков> <каталог итога>
Каждый поток берёт свой новый инцидент (test@), «берёт» его и потом гоняет «отложить» и «вернуть в работу» по кругу. У каждого перехода
свой ключ; запрос с ключом уходит двумя копиями одновременно (через балансировщик — на разные узлы), а при сбое (обрыв, 5xx) тот же
ключ шлётся снова до 8 раз. Итог: на каждый ключ — один запрос на выполнение: число строк журнала «hold», «resume» не больше числа ключей,
по которым был хоть один ответ 200 + число ключей, ответа на которые не было вовсе (неопределённые). Ответ 200 на копию ключа — только с тем же телом."""
import http.client, json, os, ssl, subprocess, sys, threading, time, uuid, urllib.parse
HP, SECS, TH, OUT = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]; os.makedirs(OUT, exist_ok=True)
host, port = HP.split(":"); port = int(port)
CA = os.path.expanduser("~/Work/axxoncloudgo/tools/util/rootCA.axxonnet.test.pem")
CTX = ssl.create_default_context(cafile=CA); CTX.verify_flags &= ~ssl.VERIFY_X509_STRICT
API = "/api/v1/im-backend/operator"
DBC = subprocess.run("docker ps --format '{{.Names}}' | grep '^ac_db'", shell=True, capture_output=True, text=True).stdout.split()[0]
def sql(q):
    r = subprocess.run(["docker", "exec", DBC, "psql", "-U", "postgres", "imdb", "-Atc", q], capture_output=True, text=True)
    if r.returncode: raise RuntimeError(r.stderr)
    return r.stdout.strip()
pw = open(os.path.expanduser("~/Work/stand/test-operator.pass")).read().rstrip("\n")
TOK = [None, 0]
def token():
    if time.time() - TOK[1] > 200:
        c = http.client.HTTPSConnection("axxonnet.test", context=CTX, timeout=30)
        c.request("POST", "/api/v3/ac-backend/users/login", json.dumps({"email": "test@axxonnet.test", "password": pw}), {"Content-Type": "application/json"})
        TOK[0] = json.loads(c.getresponse().read())["accessToken"]; TOK[1] = time.time(); c.close()
    return TOK[0]
def call(m, p, body=None):
    try:
        c = http.client.HTTPConnection(host, port, timeout=40)
        c.request(m, API + p, json.dumps(body) if body is not None else None, {"Authorization": "Bearer " + token(), "Content-Type": "application/json"})
        r = c.getresponse(); raw = r.read(); c.close(); return r.status, raw
    except Exception as e:
        return -1, str(e).encode()
LOCK = threading.Lock(); STAT = {"keys": 0, "ok_keys": 0, "unknown_keys": 0, "retries": 0, "copy_diff": 0, "codes": {}}
KEYS = {"hold": [], "resume": []}  # (incident, key, ответ 200 был ли)
def add(code):
    STAT["codes"][str(code)] = STAT["codes"].get(str(code), 0) + 1
def keyed(g, tid, body):
    k = "storm-" + uuid.uuid4().hex; body = dict(body, idempotencyKey=k)
    answers = []
    def one(out):
        for attempt in range(8):
            code, raw = call("POST", "/incidents/%s/transitions/%s" % (g, tid), body)
            with LOCK: add(code)
            if code == 200 or 400 <= code < 500:
                out.append((code, raw)); return
            with LOCK: STAT["retries"] += 1
            time.sleep(0.5)
        out.append((code, raw))
    a, b = [], []
    t1 = threading.Thread(target=one, args=(a,)); t2 = threading.Thread(target=one, args=(b,)); t1.start(); t2.start(); t1.join(); t2.join()
    got200 = [x for x in a + b if x[0] == 200]
    with LOCK:
        STAT["keys"] += 1
        if got200:
            STAT["ok_keys"] += 1
            if len(got200) == 2 and got200[0][1] != got200[1][1]: STAT["copy_diff"] += 1
        elif all(x[0] in (-1,) or x[0] >= 500 for x in a + b): STAT["unknown_keys"] += 1
        KEYS[tid].append((g, k, bool(got200)))
    return bool(got200)
def card_body(g):
    code, raw = call("GET", "/incidents/" + g)
    if code != 200: return None
    inc = json.loads(raw); inc = inc.get("incident", inc)
    return {"surface": "card", "expectedState": inc.get("state"), "expectedAddressee": (inc.get("addressee") or {}).get("id") or "",
            "expectedPriority": inc.get("priority"), "journalSeen": inc.get("journalSeq") or 0}
def pick_new(n):
    got = []
    for rep in range(10):
        for s in ("priority_then_newest", "priority_then_oldest", "oldest_first", "reaction_deadline"):
            code, raw = call("GET", "/incidents?filter=open&pageSize=50&sort=" + s)
            if code == 200:
                for x in json.loads(raw).get("items", []):
                    if x.get("state") == "new" and x["guid"] not in got: got.append(x["guid"])
        if len(got) >= n: break
        subprocess.run(["python3", "-I", os.path.expanduser("~/Work/stand/load/replay_dev.py"), "st" + uuid.uuid4().hex[:8]], capture_output=True)
    return got[:n]
INC = pick_new(TH); assert len(INC) == TH, "новых инцидентов %d" % len(INC)
END = time.time() + SECS
def worker(g):
    claimed = False
    for _ in range(5):
        b = card_body(g)
        if b and keyed_claim(g, b): claimed = True; break
        time.sleep(0.5)
    if not claimed: return
    while time.time() < END:
        for tid, form in (("hold", {"reasonId": "patrol", "comment": "повторы"}), ("resume", None)):
            b = card_body(g)
            if not b: time.sleep(0.5); continue
            if form: b["formValues"] = form
            keyed(g, tid, b)
CLAIMS = []
def keyed_claim(g, b):
    k = "storm-" + uuid.uuid4().hex; code, raw = call("POST", "/incidents/%s/transitions/claim" % g, dict(b, idempotencyKey=k)); CLAIMS.append((g, code)); return code == 200
ts = [threading.Thread(target=worker, args=(g,)) for g in INC]; [t.start() for t in ts]; [t.join() for t in ts]
# итог по журналу
res = {"stat": STAT, "per_incident": []}; bad = 0
for g in INC:
    for tid in ("hold", "resume"):
        keys = [k for (gg, k, ok) in KEYS[tid] if gg == g]; okn = sum(1 for (gg, k, ok) in KEYS[tid] if gg == g and ok); unk = len(keys) - okn
        rows = int(sql("select count(*) from incident_journal where incident_guid='%s' and transition='%s'" % (g, tid)))
        # строк не меньше успешных ключей и не больше успешных + ключей без успешного ответа (их запрос мог выполниться)
        good = okn <= rows <= okn + unk
        if not good: bad += 1
        res["per_incident"].append({"inc": g, "tid": tid, "keys": len(keys), "ok_keys": okn, "rows": rows, "ok": good})
res["bad"] = bad; json.dump(res, open(OUT + "/storm.json", "w"), ensure_ascii=False, indent=1)
print("повторы: ключей %d, с ответом 200 %d, без ответа %d, повторных попыток %d, расхождений копий %d, коды %s; нарушений по журналу %d" %
      (STAT["keys"], STAT["ok_keys"], STAT["unknown_keys"], STAT["retries"], STAT["copy_diff"], STAT["codes"], bad))
sys.exit(1 if bad or STAT["copy_diff"] else 0)
