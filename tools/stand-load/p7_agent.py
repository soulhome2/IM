#!/usr/bin/env python3
"""План 99, этап 2, П7: команда агенту, записанная на узле W, доходит до опроса, который висит на узле V ≠ W.
  python3 -I p7_agent.py <порты узлов через запятую, прямо> <кругов> <каталог итога>
Только тестовая сборка (-tags imtest): в боевой сборке команду агенту ставит в очередь лишь тестовый маршрут
POST /api/v1/im-agent/test/agents/{guid}/commands (Enqueue из сценария макросов в сервер ещё не подключён). Агент входит по X-Dev-Agent
(IM_AGENT_DEV_AUTH). Каждый круг: опрос GET /commands?wait=20 повисает на V, через 0,5 с команда ставится на W; время — от начала запроса
записи до ответа опроса (мс); команда в ответе та же, что записана. Пары (W, V) идут по кругу по всем узлам."""
import http.client, json, sys, threading, time, uuid, os, statistics, itertools
PORTS = [int(x) for x in sys.argv[1].split(",")]; ROUNDS = int(sys.argv[2]); OUT = sys.argv[3]; os.makedirs(OUT, exist_ok=True)
AG = str(uuid.uuid4()); BASE = "/api/v1/im-agent"
def call(port, m, p, body=None, timeout=60):
    c = http.client.HTTPConnection("127.0.0.1", port, timeout=timeout)
    h = {"X-Dev-Agent": AG, "Content-Type": "application/json"}
    c.request(m, BASE + p, json.dumps(body) if body is not None else None, h); r = c.getresponse(); raw = r.read(); c.close()
    return r.status, (json.loads(raw) if raw else None)
now = lambda: time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
for p in PORTS:  # агент на каждом узле: опрос на узле V должен знать агента
    code, js = call(p, "POST", "/heartbeat", {"sentAt": now(), "capabilities": ["macros"]}); assert code in (200, 204), (code, js)
code, js = call(PORTS[0], "POST", "/sync/macros", [{"uid": "gate", "name": "Ворота"}]); assert code in (200, 204), (code, js)
pairs = [(w, v) for w in PORTS for v in PORTS if w != v]
res = []
for i in range(ROUNDS):
    w, v = pairs[i % len(pairs)]
    got = {}
    def poll():
        t = time.time(); code, js = call(v, "GET", "/commands?wait=20", timeout=40); got.update(t1=time.time(), code=code, js=js)
    th = threading.Thread(target=poll); th.start(); time.sleep(0.5)
    t0 = time.time(); code, cmd = call(w, "POST", "/test/agents/%s/commands" % AG, {"macroUid": "gate", "ttlSec": 0}); assert code == 200, (code, cmd)
    th.join(30)
    ok = got.get("code") == 200 and isinstance(got.get("js"), list) and len(got["js"]) == 1 and got["js"][0]["guid"] == cmd["guid"]
    ms = round((got.get("t1", time.time() + 99) - t0) * 1000)
    res.append({"i": i, "writer": w, "waiter": v, "ok": ok, "ms": ms})
    print("%s круг %d: запись %d → опрос %d: %d мс" % ("OK  " if ok else "FAIL", i, w, v, ms), flush=True)
    if ok:
        call(v, "POST", "/commands/%s/result" % cmd["guid"], {"status": "done"})
ms = sorted(r["ms"] for r in res if r["ok"])
print("итог: кругов %d, дошло %d, мс min %s p50 %s p95 %s max %s" % (ROUNDS, len(ms), ms[0] if ms else None, ms[len(ms)//2] if ms else None, ms[int(len(ms)*.95)] if ms else None, ms[-1] if ms else None))
json.dump({"agent": AG, "rounds": res}, open(OUT + "/p7.json", "w"), ensure_ascii=False, indent=1)
sys.exit(0 if len(ms) == ROUNDS and ms[-1] < 1000 else 1)
