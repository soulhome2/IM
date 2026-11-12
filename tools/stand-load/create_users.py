#!/usr/bin/env python3
"""Создаёт в облаке стенда пользователей load-op-01..NN@axxonnet.test (пароль 111111) в группе по умолчанию cloud-user
(test@ с рангом роли 0 не может создать пользователя в группе cloud-admin). Права роли cloud-user выдаются отдельно: grant-im-role.sh cloud-user.
Повторный запуск дублей не плодит: уже существующих пропускает. Вход — test@ (пароль из файла стенда).
Запуск: python3 -I create_users.py [N=50]"""
import json, os, ssl, sys, urllib.request, urllib.error
CLOUD = "https://axxonnet.test"
CTX = ssl.create_default_context(cafile=os.path.expanduser("~/Work/axxoncloudgo/tools/util/rootCA.axxonnet.test.pem"))
CTX.verify_flags &= ~ssl.VERIFY_X509_STRICT
N = int(sys.argv[1]) if len(sys.argv) > 1 else 50

def call(m, p, body=None, tok=None):
    r = urllib.request.Request(CLOUD + p, data=json.dumps(body).encode() if body is not None else None, method=m)
    r.add_header("Content-Type", "application/json")
    if tok: r.add_header("Authorization", "Bearer " + tok)
    try:
        with urllib.request.urlopen(r, context=CTX, timeout=30) as x:
            raw = x.read(); return x.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        return e.code, e.read()[:300]

pw = open(os.path.expanduser("~/Work/stand/test-operator.pass")).read().rstrip("\n")
_, t = call("POST", "/api/v3/ac-backend/users/login", {"email": "test@axxonnet.test", "password": pw})
tok = t["accessToken"]
code, users = call("GET", "/api/v3/ac-backend/users?page%5Blimit%5D=1000", tok=tok)
assert code == 200, (code, users)
by = {u["login"]: u for u in users}
for i in range(1, N + 1):
    login = "load-op-%02d@axxonnet.test" % i
    if login in by:
        print(login, "есть, id", by[login]["id"], "группы", by[login]["userGroupIds"]); continue
    code, js = call("POST", "/api/v3/ac-backend/users", {"login": login, "password": "111111"}, tok)
    print(login, "создан" if code == 200 else "ОШИБКА", code, js)
