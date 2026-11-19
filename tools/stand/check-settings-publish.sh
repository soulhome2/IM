#!/usr/bin/env bash
# План 64, шаг А: версии «Настроек поста» организации стенда через API.
# Черновик с limits.maxOnHold = 1 → проверка → публикация → GET active отдаёт 1 без перезапуска →
# откат к общей машине (черновик с прежним значением → публикация).
# Пишет в imdb: перед запуском — дамп imdb-before-p64-*.sql.
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

req() { # req <метод> <путь> [заголовки...] — код в $CODE, тело в $TMP/body, заголовки в $TMP/hdr; тело запроса — файл $SEND
  local method=$1 path=$2; shift 2
  local args=(-s --cacert "$CA" -X "$method" -o "$TMP/body" -D "$TMP/hdr" -w '%{http_code}' -H "Authorization: Bearer $TOKEN")
  [ -n "${SEND:-}" ] && args+=(-H 'Content-Type: application/json' --data-binary "@$SEND")
  for h in "$@"; do args+=(-H "$h"); done
  CODE=$(curl "${args[@]}" "$API$path")
}
check() { if [ "$2" = "1" ]; then echo "OK   $1"; else echo "FAIL $1"; FAILS=$((FAILS+1)); fi; }
etag() { grep -i '^etag:' "$TMP/hdr" | tail -1 | tr -d '\r' | cut -d' ' -f2-; }

# 1. Что сейчас.
SEND= req GET /operator/workflow/active
check "GET active → 200 (код $CODE)" "$([ "$CODE" = 200 ] && echo 1)"
cp "$TMP/body" "$TMP/active0.json"
OLD=$(jq -c '.limits.maxOnHold' "$TMP/active0.json")
TAG0=$(etag)
echo "     сейчас maxOnHold = $OLD, ETag $TAG0"

# 2. Черновик с maxOnHold = 1.
jq '.limits.maxOnHold = 1' "$TMP/active0.json" > "$TMP/draft.json"
SEND="$TMP/draft.json" req POST /operator/workflow/schemas
check "create → 201 (код $CODE)" "$([ "$CODE" = 201 ] && echo 1)"
GUID=$(jq -r '.schema.guid // .schema.schemaGuid // .guid // empty' "$TMP/body")
STATUS=$(jq -r '.schema.status // empty' "$TMP/body")
check "черновик: status draft ($STATUS), guid $GUID" "$([ "$STATUS" = draft ] && [ -n "$GUID" ] && echo 1)"

# 3. Проверка.
SEND= req POST "/operator/workflow/schemas/$GUID/validate"
check "validate → valid true (код $CODE, $(jq -c . "$TMP/body" | cut -c1-120))" "$([ "$CODE" = 200 ] && [ "$(jq -r .valid "$TMP/body")" = true ] && echo 1)"

# 4. Публикация.
SEND= req POST "/operator/workflow/schemas/$GUID/publish"
check "publish → 200, published (код $CODE)" "$([ "$CODE" = 200 ] && [ "$(jq -r .schema.status "$TMP/body")" = published ] && echo 1)"
echo "     версия настроек: $(jq -r '.schema.version' "$TMP/body")"

# 5. Новое без перезапуска.
SEND= req GET /operator/workflow/active
NOW=$(jq -c '.limits.maxOnHold' "$TMP/body")
TAG1=$(etag)
check "GET active: maxOnHold = 1 ($NOW)" "$([ "$NOW" = 1 ] && echo 1)"
check "ETag сменился ($TAG1)" "$([ -n "$TAG1" ] && [ "$TAG1" != "$TAG0" ] && echo 1)"

# 6. Список версий.
SEND= req GET /operator/workflow/schemas
echo "     список: $(jq -c '[.[] | {v:.version, s:.status}] | .[:5]' "$TMP/body" 2>/dev/null)"

if [ "${KEEP:-}" = 1 ]; then echo "KEEP=1: настройки оставлены опубликованными, откат — повторный запуск без KEEP"; exit $FAILS; fi

# 7. Откат к общей: черновик с прежним значением → публикация.
jq --argjson v "$OLD" '.limits.maxOnHold = $v' "$TMP/active0.json" > "$TMP/back.json"
SEND="$TMP/back.json" req POST /operator/workflow/schemas
BACK=$(jq -r '.schema.guid // .schema.schemaGuid // .guid // empty' "$TMP/body")
SEND= req POST "/operator/workflow/schemas/$BACK/publish"
check "откат: publish → 200 (код $CODE)" "$([ "$CODE" = 200 ] && echo 1)"
SEND= req GET /operator/workflow/active
NOW=$(jq -c '.limits.maxOnHold' "$TMP/body")
check "после отката maxOnHold = $OLD ($NOW)" "$([ "$NOW" = "$OLD" ] && echo 1)"
exit $FAILS
