#!/usr/bin/env python3
"""Сброс МИ тем же запросом, что кнопка в интерфейсе (план 86): вход test@, POST /operator/admin/reset через прокси стенда.
   python3 -I reset_probe.py <каталог>   → <каталог>/reset.json {code, ms, body, t0, t1}"""
import http.client, json, os, ssl, sys, time
OUT = sys.argv[1]
HOST = "axxonnet.test"
CA = os.path.expanduser("~/Work/axxoncloudgo/tools/util/rootCA.axxonnet.test.pem")
ctx = ssl.create_default_context(cafile=CA); ctx.verify_flags &= ~ssl.VERIFY_X509_STRICT
pw = open(os.path.expanduser("~/Work/stand/test-operator.pass")).read().rstrip("\n")
def req(m, p, body, tok=None, timeout=30):
    c = http.client.HTTPSConnection(HOST, context=ctx, timeout=timeout)
    h = {"Content-Type": "application/json"}
    if tok: h["Authorization"] = "Bearer " + tok
    c.request(m, p, json.dumps(body), h); r = c.getresponse(); raw = r.read(); c.close()
    return r.status, raw
code, raw = req("POST", "/api/v3/ac-backend/users/login", {"email": "test@axxonnet.test", "password": pw})
tok = json.loads(raw)["accessToken"]
t0 = time.time()
try:
    code, raw = req("POST", "/api/v1/im-backend/operator/admin/reset", {"password": pw, "confirm": "RESET"}, tok, timeout=4 * 3600)
    body = raw.decode(errors="replace")[:4000]
except Exception as e:
    code, body = -1, repr(e)
t1 = time.time()
rec = {"code": code, "ms": round((t1 - t0) * 1000), "body": body, "t0": t0, "t1": t1}
json.dump(rec, open(os.path.join(OUT, "reset.json"), "w"), ensure_ascii=False)
print(json.dumps(rec, ensure_ascii=False)[:600])
