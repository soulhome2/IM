#!/usr/bin/env python3
"""План 99, задача 7б: цена сверки с концом ленты на запрос очереди — один оператор на спокойном стенде, сервер напрямую (без nginx).
  python3 -I quiet_queue.py <порт> <запросов> [метка]
Оператор load-op-01 входит через облако, потом ходит прямо на 127.0.0.1:<порт>: очередь «Открытые» (pageSize 50), очередь «Мои»
и счётчики, по кругу; каждый ответ — мс. Печатает p50/p95/среднее по видам и в целом (json в одну строку)."""
import http.client, json, os, ssl, sys, time, statistics
port, n = int(sys.argv[1]), int(sys.argv[2]); tag = sys.argv[3] if len(sys.argv) > 3 else ""
ca = os.path.expanduser("~/Work/axxoncloudgo/tools/util/rootCA.axxonnet.test.pem")
ctx = ssl.create_default_context(cafile=ca); ctx.verify_flags &= ~ssl.VERIFY_X509_STRICT
c = http.client.HTTPSConnection("axxonnet.test", context=ctx, timeout=30)
c.request("POST", "/api/v3/ac-backend/users/login", json.dumps({"email": "load-op-01@axxonnet.test", "password": "111111"}), {"Content-Type": "application/json"})
tok = json.loads(c.getresponse().read())["accessToken"]; c.close()
h = {"Authorization": "Bearer " + tok}
paths = {"queue:open": "/api/v1/im-backend/operator/incidents?filter=open&pageSize=50",
         "queue:mine": "/api/v1/im-backend/operator/incidents?filter=mine&pageSize=50",
         "counters": "/api/v1/im-backend/operator/incidents/counters"}
conn = http.client.HTTPConnection("127.0.0.1", port, timeout=60)
res = {k: [] for k in paths}; bad = 0; slow = []; T0 = time.time()
def one(k):
    global bad
    t = time.perf_counter(); conn.request("GET", paths[k], headers=h); r = conn.getresponse(); r.read()
    ms = (time.perf_counter() - t) * 1000
    if r.status != 200: bad += 1
    if ms > 300: slow.append([round(time.time() - T0, 1), k, round(ms)])
    return ms
for i in range(20):
    for k in paths: one(k)
for i in range(n):
    for k in paths: res[k].append(one(k))
def st(a):
    a = sorted(a); return {"n": len(a), "p50": round(a[len(a)//2], 2), "p95": round(a[int(len(a)*.95)], 2), "mean": round(statistics.mean(a), 2)}
out = {k: st(v) for k, v in res.items()}; out["all"] = st(sum(res.values(), [])); out["non200"] = bad; out["secs"] = round(time.time() - T0); out["slow_gt100ms"] = slow[:40]; out["max"] = round(max(sum(res.values(), [])), 1); out["port"] = port; out["tag"] = tag
print(json.dumps(out, ensure_ascii=False))
