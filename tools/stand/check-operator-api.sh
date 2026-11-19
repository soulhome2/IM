#!/usr/bin/env bash
# Локальный стенд: проверка каркаса операторского API (этап 2) через шлюз облака.
# Каждая проверка — строка "OK|FAIL <что>", код выхода — число FAIL.
set -uo pipefail
CLOUD_REPO="${CLOUD_REPO:-$HOME/Work/axxoncloudgo}"
HERE="$(dirname "$(readlink -f "$0")")"
API="${API:-https://axxonnet.test/api/v1/im-backend}"
CLOUD="${CLOUD:-https://axxonnet.test}"
CA="$CLOUD_REPO/tools/util/rootCA.axxonnet.test.pem"
source "$HERE/test-operator.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
FAILS=0

operator_login || { echo "SKIP вход: $OPERATOR_WHY"; exit 2; }

# req <метод> <путь> [токен|-] [заголовки...] — код ответа в $CODE, тип в $CTYPE, тело в $TMP/body. Тело запроса — в переменной BODY.
req() {
  local method=$1 path=$2 tok=$3; shift 3
  local args=(-s --cacert "$CA" -X "$method" -o "$TMP/body" -D "$TMP/hdr" -w '%{http_code}')
  [ "$tok" != "-" ] && args+=(-H "Authorization: Bearer $tok")
  [ -n "${BODY:-}" ] && args+=(-H 'Content-Type: application/json' -d "$BODY")
  for h in "$@"; do args+=(-H "$h"); done
  CODE=$(curl "${args[@]}" "$API$path")
  CTYPE=$(grep -i '^content-type:' "$TMP/hdr" | tail -1 | tr -d '\r' | cut -d' ' -f2-)
}
check() { # check <что> <условие истинно?>
  if [ "$2" = "1" ]; then echo "OK   $1"; else echo "FAIL $1"; FAILS=$((FAILS+1)); fi
}
jq_is() { [ "$(jq -r "$1" "$TMP/body" 2>/dev/null)" = "$2" ] && echo 1 || echo 0; }
is_problem() { case "$CTYPE" in application/problem+json*) echo 1;; *) echo 0;; esac; }

UUID=$(cat /proc/sys/kernel/random/uuid)

# Первым шагом: оператор начинает в offline (решение 76 плана 56) и на линию выходит сам.
BODY='{"agentState":"ready"}' req PUT /operator/session/agent-state "$TOKEN"
check "PUT /operator/session/agent-state ready: 200 (получено $CODE)" "$([ "$CODE" = 200 ] && echo 1 || echo 0)"

req GET /operator/session -
check "GET /operator/session без токена: 401 (получено $CODE)" "$([ "$CODE" = 401 ] && echo 1 || echo 0)"
check "  тип application/problem+json (получено $CTYPE)" "$(is_problem)"
check "  code = UNAUTHENTICATED" "$(jq_is .code UNAUTHENTICATED)"

req GET /operator/session "$TOKEN"
check "GET /operator/session: 200 (получено $CODE)" "$([ "$CODE" = 200 ] && echo 1 || echo 0)"
check "  permissions: 20 прав" "$(jq_is '.permissions | length' 20)"
check "  agentState = ready" "$(jq_is .agentState ready)"

req POST /test/reset "$TOKEN"
check "POST /test/reset: 404 в обычной сборке, решение 186 (получено $CODE)" "$([ "$CODE" = 404 ] && echo 1 || echo 0)"
check "  code = NOT_FOUND" "$(jq_is .code NOT_FOUND)"

req GET /operator/incidents "$TOKEN"
check "GET /operator/incidents: 200 (получено $CODE)" "$([ "$CODE" = 200 ] && echo 1 || echo 0)"
check "  в ответе items и total" "$(jq_is '(.items | type) + " " + (.total | type)' 'array number')"

req GET /operator/incidents/counters "$TOKEN"
check "GET /operator/incidents/counters: 200 (получено $CODE)" "$([ "$CODE" = 200 ] && echo 1 || echo 0)"

# Случайный UUID: инцидента нет, поэтому 404 раньше проверки expectedState (решение 47 плана 55). Имя перехода здесь не проверяется.
req POST "/operator/incidents/$UUID/transitions/claim" "$TOKEN"
check "POST .../transitions/claim, инцидента нет, без expectedState: 404 (получено $CODE)" "$([ "$CODE" = 404 ] && echo 1 || echo 0)"
check "  code = NOT_FOUND" "$(jq_is .code NOT_FOUND)"

req GET /operator/me "$TOKEN"
check "GET /operator/me: 404 (получено $CODE)" "$([ "$CODE" = 404 ] && echo 1 || echo 0)"
check "  тип application/problem+json (получено $CTYPE)" "$(is_problem)"

req GET /incidents "$TOKEN"
check "GET /incidents (старый): 200 (получено $CODE)" "$([ "$CODE" = 200 ] && echo 1 || echo 0)"

req GET /incidents -
check "GET /incidents без токена: 401 (получено $CODE)" "$([ "$CODE" = 401 ] && echo 1 || echo 0)"
check "  в теле есть key" "$([ "$(jq -r 'has("key")' "$TMP/body" 2>/dev/null)" = true ] && echo 1 || echo 0)"

echo "итого ошибок: $FAILS"
exit "$FAILS"
