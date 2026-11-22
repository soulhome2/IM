#!/usr/bin/env python3
"""План 99, этап 2, замер задачи 5 в покое: цена ключа повтора на действие оператора — один оператор, сервер напрямую (без nginx).
  python3 -I quiet_idem.py <порт> <кругов> <с ключом 1|0> [метка]
load-op-01 берёт новый инцидент и гоняет «отложить» и «вернуть в работу» по кругу (2 перехода на круг); с ключом — у каждого
перехода свой idempotencyKey. Печатает p50/p95/среднее перехода (мс), json в одну строку. Инцидент в конце закрывается."""
import http.client, json, os, ssl, sys, time, statistics, uuid
port, n, keyed = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3] == "1"; tag = sys.argv[4] if len(sys.argv) > 4 else ""
ca = os.path.expanduser("~/Work/axxoncloudgo/tools/util/rootCA.axxonnet.test.pem")
ctx = ssl.create_default_context(cafile=ca); ctx.verify_flags &= ~ssl.VERIFY_X509_STRICT
c = http.client.HTTPSConnection("axxonnet.test", context=ctx, timeout=30)
c.request("POST", "/api/v3/ac-backend/users/login", json.dumps({"email": "load-op-01@axxonnet.test", "password": "111111"}), {"Content-Type": "application/json"})
tok = json.loads(c.getresponse().read())["accessToken"]; c.close()
H = {"Authorization": "Bearer " + tok, "Content-Type": "application/json"}
B = "/api/v1/im-backend/operator"
conn = http.client.HTTPConnection("127.0.0.1", port, timeout=60)
def req(m, p, body=None):
    conn.request(m, B + p, json.dumps(body) if body is not None else None, H); r = conn.getresponse(); raw = r.read()
    return r.status, (json.loads(raw) if raw else None)
rows = []
for q in ("filter=open&sort=priority_then_oldest&pageSize=50", "filter=open&sort=oldest_first&pageSize=50", "filter=open&sort=priority_then_newest&pageSize=50", "filter=open&sort=reaction_deadline&pageSize=50"):
    code, js = req("GET", "/incidents?" + q)
    rows = [x for x in js.get("items", []) if x.get("state") == "new"]
    if rows: break
assert rows, "нет новых: " + str([(x.get("state"), x.get("ownership")) for x in js.get("items", [])][:10])
guid = rows[0]["guid"]
def tr(tid, form=None):
    code, card = req("GET", "/incidents/" + guid); inc = card.get("incident", card)
    body = {"surface": "card", "expectedState": inc.get("state"), "expectedAddressee": (inc.get("addressee") or {}).get("id") or "",
            "expectedPriority": inc.get("priority"), "journalSeen": inc.get("journalSeq") or 0}
    if form: body["formValues"] = form
    if keyed: body["idempotencyKey"] = "q-" + uuid.uuid4().hex
    t = time.perf_counter(); code, js = req("POST", "/incidents/%s/transitions/%s" % (guid, tid), body)
    return code, (time.perf_counter() - t) * 1000
assert tr("claim")[0] == 200
ms, bad = [], 0
for i in range(n):
    for tid, f in (("hold", {"reasonId": "patrol", "comment": "замер"}), ("resume", None)):
        code, m = tr(tid, f)
        if code != 200: bad += 1
        else: ms.append(m)
tr("close", {"resultId": "false_alarm", "causeId": "equipment", "comment": "замер"})
a = sorted(ms)
print(json.dumps({"tag": tag, "keyed": keyed, "port": port, "n": len(a), "bad": bad, "p50": round(a[len(a)//2], 2), "p95": round(a[int(len(a)*.95)], 2),
                  "mean": round(statistics.mean(a), 2)}, ensure_ascii=False))
