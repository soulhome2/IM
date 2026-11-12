#!/usr/bin/env bash
# Нагрузочный прогон: печатает "токен1 id1 токен2 id2" двух операторов стенда (оба ready).
# (основа — check-p65.sh): ETag и If-Match (412), заменённый черновик (404 schema_replaced), предел тела (413),
# предупреждения в ответе версии, и пункт 2.12 — публикация версии «Настроек поста» с настоящими адресатами
# эскалации и алертов (первый и второй операторы стенда). Пишет в imdb: перед запуском — дамп imdb-before-p65-*.sql.
set -uo pipefail
API="${API:-https://axxonnet.test/api/v1/im-backend}"
CLOUD="${CLOUD:-https://axxonnet.test}"
CA="$HOME/Work/axxoncloudgo/tools/util/rootCA.axxonnet.test.pem"
source "$HOME/Work/stand/test-operator.sh"
SECOND_EMAIL="${SECOND_EMAIL:-user@gmail.com}"
SECOND_PASS_FILE="${SECOND_PASS_FILE:-$HOME/Work/stand/second-operator.pass}"
SECOND_PERMS='incident:accept'
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

req() { # для second-operator.sh: req <метод> <путь> <токен>, тело — $BODY
  local method=$1 path=$2 tok=$3; shift 3
  local args=(-s --max-time 20 --cacert "$CA" -X "$method" -o "$TMP/body" -D "$TMP/hdr" -w '%{http_code}')
  [ "$tok" != "-" ] && args+=(-H "Authorization: Bearer $tok")
  [ -n "${BODY:-}" ] && args+=(-H 'Content-Type: application/json' -d "$BODY")
  CODE=$(curl "${args[@]}" "$API$path")
}
field() { jq -r "$1 // empty" "$TMP/body" 2>/dev/null; }
source "$HOME/Work/stand/second-operator.sh"
operator_login >/dev/null || { echo "ERR first: $OPERATOR_WHY" >&2; exit 2; }
FIRST_TOKEN="$TOKEN"
req GET /operator/session "$TOKEN"; FIRST=$(field .operator.guid)
BODY='{"agentState":"ready"}' req PUT /operator/session/agent-state "$TOKEN"
BODY=
second_login
[ -n "${SECOND_ID:-}" ] || { echo "ERR second: ${SECOND_BAD:-${SECOND_WHY:-}}" >&2; exit 2; }
echo "$FIRST_TOKEN $FIRST $SECOND $SECOND_ID"
