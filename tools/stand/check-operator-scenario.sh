#!/usr/bin/env bash
# Локальный стенд, этап 6 (Task 18): сценарий из конфигуратора на настоящей связке, только HTTP через шлюз облака.
# Инцидент new, чей сценарий имеет хоть два шага и ни одного шага Image (вложение — этап 7); первый — claim;
# цикл GET …/scenario → ответ на cursorStepId (первый вариант или текст), expectedOwner и seenAnswer (RULE-142); progress.filled растёт на 1
# до completedAt; requiredStepsFilled.closing; close с результатом processed; строка очереди filled == total.
# Второй открывает тот же сценарий — 200, ответ — 403.
# Каждая проверка — строка "OK|FAIL|SKIP <что>", код выхода — число FAIL.
set -uo pipefail
STAND_DIR="${STAND_DIR:-$HOME/Work/stand}"
CLOUD_REPO="${CLOUD_REPO:-$HOME/Work/axxoncloudgo}"
HERE="$(dirname "$(readlink -f "$0")")"
API="${API:-https://axxonnet.test/api/v1/im-backend}"
CLOUD="${CLOUD:-https://axxonnet.test}"
CA="$CLOUD_REPO/tools/util/rootCA.axxonnet.test.pem"
source "$HERE/test-operator.sh"; EMAIL="$TEST_EMAIL"
SECOND_EMAIL="${SECOND_EMAIL:-user@gmail.com}"
SECOND_PASS_FILE="${SECOND_PASS_FILE:-$STAND_DIR/second-operator.pass}"
SECOND_PERMS=''
TEXT='стенд: ответ сценария'
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
FAILS=0
source "$HERE/seen-body.sh"

req() {
  local method=$1 path=$2 tok=$3; shift 3
  local args=(-s --max-time 20 --cacert "$CA" -X "$method" -o "$TMP/body" -D "$TMP/hdr" -w '%{http_code}')
  [ "$tok" != "-" ] && args+=(-H "Authorization: Bearer $tok")
  [ -n "${BODY:-}" ] && args+=(-H 'Content-Type: application/json' -d "$BODY")
  for h in "$@"; do args+=(-H "$h"); done
  CODE=$(curl "${args[@]}" "$API$path")
}
check() { if [ "$2" = "1" ]; then echo "OK   $1"; else echo "FAIL $1"; FAILS=$((FAILS+1)); fi; }
skip() { echo "SKIP $1"; }
is_code() { [ "$CODE" = "$1" ] && echo 1 || echo 0; }
field() { jq -r "$1 // empty" "$TMP/body" 2>/dev/null; }
etag() { grep -i '^etag:' "$TMP/hdr" | tail -1 | tr -d '\r' | sed 's/^[^:]*: *//; s/"//g'; }
finish() { echo "итого ошибок: $FAILS"; exit "$FAILS"; }
got() { echo "получено $CODE$(c=$(field .code); [ -n "$c" ] && echo ", code $c")"; }
source "$(dirname "$(readlink -f "$0")")/second-operator.sh"

operator_login || { echo "SKIP вход: $OPERATOR_WHY"; exit 2; }
check "вход $EMAIL: токен есть" "$([ -n "$TOKEN" ] && echo 1 || echo 0)"
BODY='{"agentState":"ready"}' req PUT /operator/session/agent-state "$TOKEN"
check "первый: PUT agent-state ready: 200 (получено $CODE)" "$(is_code 200)"

# --- Выбор инцидента: new, сценарий ≥ 2 шагов, без Image.
req GET '/operator/incidents?filter=open&state=new&pageSize=200' "$TOKEN"
check "GET /operator/incidents new: 200 (получено $CODE)" "$(is_code 200)"
jq -r '.items[] | select((.scenarioProgress.total // 0) >= 2) | .guid' "$TMP/body" > "$TMP/cands"
G=''
while read -r g; do
  req GET "/operator/incidents/$g/scenario" "$TOKEN"
  [ "$CODE" = 200 ] || continue
  if [ "$(jq -r '(.script.steps | length) >= 2 and all(.script.steps[]; .type != "Image")' "$TMP/body")" = true ]; then
    G=$g; NAME=$(field .name); STEPS=$(jq -r '[.script.steps[].type] | join(",")' "$TMP/body"); break
  fi
done < "$TMP/cands"
check "инцидент со сценарием ≥ 2 шагов без Image: ${G:-нет} (${NAME:-}; шаги $STEPS)" "$([ -n "$G" ] && echo 1 || echo 0)"
[ -n "$G" ] || finish
CARD="/operator/incidents/$G"

# --- claim.
BODY=$(seen_body "$TOKEN" "$CARD" '{"surface":"card"}') req POST "$CARD/transitions/claim" "$TOKEN"
check "claim: 200 ($(got)), state $(field .incident.state)" "$(is_code 200)"
[ "$CODE" = 200 ] || finish
VER=$(field .incident.version)

# --- Ответы по шагам.
req GET "$CARD/scenario" "$TOKEN"
check "GET сценария: 200 (получено $CODE)" "$(is_code 200)"
FILLED=$(field .progress.filled); TOTAL=$(field .progress.total)
step_ok=1; n=0
while [ -z "$(field .result.completedAt)" ] && [ $n -lt 30 ]; do
  n=$((n + 1))
  STEP=$(field .cursorStepId)
  TYPE=$(jq -r --arg s "$STEP" '.script.steps[] | select(.id == $s) | .type' "$TMP/body")
  VALUE=$(jq -c --arg s "$STEP" --arg t "$TEXT" '.script.steps[] | select(.id == $s) |
    if ((.view.options // []) | length) > 0 then
      (if (.type | test("Check"; "i")) then [.view.options[0].id] else .view.options[0].id end)
    elif (.type | test("Message|Button"; "i")) then null else $t end' "$TMP/body")
  if [ "$VALUE" = null ]; then BODY=$(jq -nc --arg s "$STEP" '{stepId: $s}')
  else BODY=$(jq -nc --arg s "$STEP" --argjson v "$VALUE" '{stepId: $s, value: $v}'); fi
  OWNER=$(curl -s --max-time 20 --cacert "$CA" -H "Authorization: Bearer $TOKEN" "$API$CARD" | jq -r '.owner.id // ""')
  SEEN=$(jq -c --arg s "$STEP" '(.result.state // {})[$s].answeredAt // null' "$TMP/body")
  BODY=$(jq -c --arg o "$OWNER" --argjson a "$SEEN" '. + {expectedOwner: $o, seenAnswer: $a}' <<<"$BODY") req POST "$CARD/scenario/answer" "$TOKEN"
  NEW=$(field .progress.filled)
  ok=$([ "$CODE" = 200 ] && [ "$NEW" = $((FILLED + 1)) ] && echo 1 || echo 0)
  check "ответ $n: шаг $STEP ($TYPE) = $VALUE: $(got), filled $FILLED → ${NEW:-?} из $TOTAL" "$ok"
  [ "$ok" = 1 ] || { step_ok=0; break; }
  FILLED=$NEW
  E=$(etag); [ -n "$E" ] && VER=$E
  req GET "$CARD/scenario" "$TOKEN"
done
[ "$step_ok" = 1 ] || finish
check "сценарий завершён: completedAt $(field .result.completedAt), filled $FILLED из $(field .progress.total)" \
  "$([ -n "$(field .result.completedAt)" ] && echo 1 || echo 0)"
check "requiredStepsFilled.closing = true" "$([ "$(jq -r .requiredStepsFilled.closing "$TMP/body")" = true ] && echo 1 || echo 0)"

# --- close с результатом полной обработки.
BODY=$(seen_body "$TOKEN" "$CARD" '{"surface":"card","formValues":{"resultId":"processed","comment":"стенд: сценарий пройден"}}') \
  req POST "$CARD/transitions/close" "$TOKEN"
check "close processed: 200 ($(got)), state $(field .incident.state)" "$(is_code 200)"

# --- Строка очереди.
# По номеру инцидента (search, §7), а не перебором страниц: на стенде с тысячами инцидентов он дальше любой страницы.
NUM=$(curl -s --max-time 20 --cacert "$CA" -H "Authorization: Bearer $TOKEN" "$API$CARD" | jq -r '.number // ""')
req GET "/operator/incidents?filter=all&pageSize=200&search=$(jq -rn --arg n "$NUM" '$n|@uri')" "$TOKEN"
ROW=$(jq -c --arg g "$G" '.items[] | select(.guid == $g) | .scenarioProgress' "$TMP/body")
check "строка очереди: filled == total ($ROW)" "$(jq -r 'if . == null then 0 elif .filled == .total then 1 else 0 end' <<<"${ROW:-null}")"

# --- Второй.
second_login
if [ -z "$SECOND" ]; then
  if [ -n "$SECOND_BAD" ]; then check "второй оператор: $SECOND_BAD" 0; else skip "второй оператор: $SECOND_WHY (second-operator.sh)"; fi
  finish
fi
req GET "$CARD/scenario" "$SECOND"
check "второй: GET сценария: 200 ($(got))" "$(is_code 200)"
STEP=$(field .cursorStepId)
OWNER=$(curl -s --max-time 20 --cacert "$CA" -H "Authorization: Bearer $SECOND" "$API$CARD" | jq -r '.owner.id // ""')
BODY=$(jq -nc --arg s "$STEP" --arg t "$TEXT" --arg o "$OWNER" '{stepId: $s, value: $t, expectedOwner: $o, seenAnswer: null}') req POST "$CARD/scenario/answer" "$SECOND"
check "второй: ответ сценария: 403 ($(got))" "$(is_code 403)"
echo "инцидент $G"
finish
