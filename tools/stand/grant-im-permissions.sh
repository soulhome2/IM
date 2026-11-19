#!/usr/bin/env bash
# Локальный стенд: выдаёт группе cloud-admin 20 прав incident_manager.* из машины МИ.
# Список прав роли заменяется целиком: прежние incident_manager.* убираются, остальные остаются.
# Повторный запуск безопасен.
set -euo pipefail
CLOUD_REPO="${CLOUD_REPO:-$HOME/Work/axxoncloudgo}"
IM_SERVER_REPO="${IM_SERVER_REPO:-$HOME/Work/incident-manager-server}"
HERE="$(dirname "$(readlink -f "$0")")"
export CLOUD='https://axxonnet.test'
export CA="$CLOUD_REPO/tools/util/rootCA.axxonnet.test.pem"
export SCHEMA="$IM_SERVER_REPO/api/im/operator/workflow_schema.v1.json"
source "$HERE/test-operator.sh"
# Пароль читает сам python из файла; здесь только проверка файла и прав (как в operator_login).
[ -f "$TEST_PASS_FILE" ] || { echo "нет файла $TEST_PASS_FILE" >&2; exit 1; }
mode=$(stat -c '%a' "$TEST_PASS_FILE"); [ "$mode" = 600 ] || { echo "права файла $TEST_PASS_FILE — $mode, нужны 600" >&2; exit 1; }
export EMAIL="$TEST_EMAIL" TEST_PASS_FILE

exec python3 - <<'PY'
import json, os, ssl, sys, urllib.request

cloud, ca, schema = os.environ["CLOUD"], os.environ["CA"], os.environ["SCHEMA"]
with open(os.environ["TEST_PASS_FILE"], encoding="utf-8") as pf:
    password = pf.read().rstrip("\n")
ctx = ssl.create_default_context(cafile=ca)
ctx.verify_flags &= ~ssl.VERIFY_X509_STRICT  # корневой сертификат стенда без Authority Key Identifier

def call(method, path, body=None, token=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(cloud + path, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", "Bearer " + token)
    with urllib.request.urlopen(req, context=ctx, timeout=30) as r:
        raw = r.read()
        return r.status, (json.loads(raw) if raw else None)

with open(schema, encoding="utf-8") as f:
    wanted = [p["cloud"] for p in json.load(f)["permissions"]]
if len(wanted) != 20:
    sys.exit("в машине %d прав, ожидалось 20" % len(wanted))

_, tok = call("POST", "/api/v3/ac-backend/users/login",
              {"email": os.environ["EMAIL"], "password": password})
token = tok["accessToken"]

_, roles = call("GET", "/api/v3/ac-backend/roles/global", token=token)
found = False
for role in roles:
    if role["name"] == "cloud-admin":
        found = True
        kept = [p for p in role["permissions"] if not p.startswith("incident_manager.")]
        role["permissions"] = kept + wanted
if not found:
    sys.exit("роль cloud-admin не найдена")

status, _ = call("PATCH", "/api/v3/ac-backend/roles/global", roles, token=token)
print("PATCH /roles/global -> %d" % status)

# Права сессии: /me отдаёт их по группам; после смены роли берём новый токен.
_, tok = call("POST", "/api/v3/ac-backend/users/login",
              {"email": os.environ["EMAIL"], "password": password})
_, me = call("GET", "/api/v3/ac-backend/me", token=tok["accessToken"])
flat = []
for res, v in me["capabilities"].get("incident_manager", {}).items():
    for act, a in v["actions"].items():
        flat += [(res + "." if res else "") + act + ("." + s if s else "") for s in (a["scopes"] or [""])]
print("в /me incident_manager: %d прав" % len(flat))
for name in sorted(flat):
    print("  " + name)
PY
