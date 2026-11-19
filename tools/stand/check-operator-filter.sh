#!/usr/bin/env bash
# Локальный стенд: фильтр и выборка очереди (этап 5б, уровень В) через шлюз облака, настоящий токен.
# Инцидент даёт agent-emulator (одно событие), он же закрывается в конце. Запускается руками, это не тест.
# Базы imdb и ac_db напрямую не трогает, пользователей и правил доступа не создаёт.
# Каждая проверка — строка "OK|FAIL|SKIP <что>", код выхода — число FAIL.
set -uo pipefail
STAND_DIR="${STAND_DIR:-$HOME/Work/stand}"
CLOUD_REPO="${CLOUD_REPO:-$HOME/Work/axxoncloudgo}"
HERE="$(dirname "$(readlink -f "$0")")"
API="${API:-https://axxonnet.test/api/v1/im-backend}"
CLOUD="${CLOUD:-https://axxonnet.test}"
CA="$CLOUD_REPO/tools/util/rootCA.axxonnet.test.pem"
EMU="$STAND_DIR/bin/agent-emulator"
source "$HERE/test-operator.sh"; EMAIL="$TEST_EMAIL"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
FAILS=0
source "$HERE/seen-body.sh"

# req <метод> <путь> <токен|-> [заголовки...] — код ответа в $CODE, тело в $TMP/body. Тело запроса — в переменной BODY.
req() {
  local method=$1 path=$2 tok=$3; shift 3
  local args=(-s --max-time 20 --cacert "$CA" -X "$method" -o "$TMP/body" -D "$TMP/hdr" -w '%{http_code}')
  [ "$tok" != "-" ] && args+=(-H "Authorization: Bearer $tok")
  [ -n "${BODY:-}" ] && args+=(-H 'Content-Type: application/json' -d "$BODY")
  for h in "$@"; do args+=(-H "$h"); done
  CODE=$(curl "${args[@]}" "$API$path")
}
check() { # check <что> <условие истинно?>
  if [ "$2" = "1" ]; then echo "OK   $1"; else echo "FAIL $1"; FAILS=$((FAILS+1)); fi
}
skip() { echo "SKIP $1"; }
is_code() { [ "$CODE" = "$1" ] && echo 1 || echo 0; }
is_eq() { [ "$1" = "$2" ] && echo 1 || echo 0; }
jq_is() { [ "$(jq -r "$1" "$TMP/body" 2>/dev/null)" = "$2" ] && echo 1 || echo 0; }
jq_true() { local a=(); [ "${1:-}" = --argjson ] && { a=(--argjson "$2" "$3"); shift 3; }; [ "$(jq -r --arg g "${G:-}" "${a[@]}" "$1" "$TMP/body" 2>/dev/null)" = true ] && echo 1 || echo 0; }
field() { jq -r "$1 // empty" "$TMP/body" 2>/dev/null; }
finish() { echo "итого ошибок: $FAILS"; exit "$FAILS"; }
got() { echo "получено $CODE$(c=$(field .code); [ -n "$c" ] && echo ", code $c")"; }
filter() { BODY="$1" req POST /operator/incidents/filter "$TOKEN"; }
selection() { BODY="$1" req POST /operator/incidents/selection "$TOKEN"; }

# --- Вход и выход на линию: оператор начинает в offline (решение 76 плана 56).
operator_login || { echo "SKIP вход: $OPERATOR_WHY"; exit 2; }
check "вход $EMAIL: токен есть" "$([ -n "$TOKEN" ] && echo 1 || echo 0)"
BODY='{"agentState":"ready"}' req PUT /operator/session/agent-state "$TOKEN"
check "PUT agent-state ready: 200 ($(got))" "$(is_code 200)"

# --- Один инцидент от эмулятора. Ищем его по guid события из вывода эмулятора, самый новый.
RUN="stage5b-$(date +%s)"
"$EMU" replay --limit 1 --run "$RUN" > "$TMP/emu" 2>&1
EMU_CODE=$?
EVENT=$(grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' "$TMP/emu" | head -1)
check "agent-emulator replay --limit 1 --run $RUN: код $EMU_CODE, отправлено 1" \
  "$([ "$EMU_CODE" = 0 ] && grep -q 'отправлено 1,' "$TMP/emu" && echo 1 || echo 0)"
req GET /incidents "$TOKEN"
G=$(jq -r --arg e "$EVENT" '[.[]? | select(.event.guid == $e)] | max_by(.createdAt).guid // empty' "$TMP/body" 2>/dev/null)
check "инцидент события ${EVENT:-?}: ${G:-нет}" "$([ -n "$G" ] && echo 1 || echo 0)"
[ -n "$G" ] || finish
req GET "/operator/incidents/$G" "$TOKEN"
check "GET карточки: 200 ($(got))" "$(is_code 200)"
SEEN=$(jq -c '{state: .state, addressee: (.addressee.id // ""), journalSeq: (.journalSeq // 0)}' "$TMP/body")
VER=$(field .version)
check "версия карточки: ${VER:-нет}" "$([ -n "$VER" ] && echo 1 || echo 0)"
[ -n "$VER" ] || finish

# --- filter без условий.
BODY='{}' req POST /operator/incidents/filter -
check "filter без токена: 401 ($(got))" "$(is_code 401)"

filter '{}'
check "filter без условий: 200 ($(got))" "$(is_code 200)"
ALL=$(field .count)
check "  count ($ALL) не меньше 1" "$([ "${ALL:-0}" -ge 1 ] 2>/dev/null && echo 1 || echo 0)"
check "  truncated = false: предел maxBulk null" "$(jq_is .truncated false)"
check "  в incidentGuids столько же, сколько в count" "$(jq_true '(.incidentGuids | length) == .count')"
check "  новый инцидент в incidentGuids" "$(jq_true 'any(.incidentGuids[]; . == $g)')"
check "  expected[инцидент] = то, что видно в карточке ($SEEN, RULE-142)" "$(jq_true --argjson s "$SEEN" '.expected[$g] == $s')"
check "  без отбора: scenarioGuid = null, excluded = 0" "$(jq_true '.scenarioGuid == null and .excluded == 0')"
check "  options.scenarios не пуст" "$(jq_true '(.options.scenarios | length) > 0')"
cp "$TMP/body" "$TMP/all"

# --- filter с условием. Значения берутся из вариантов самого ответа: каскад условия, число варианта равно числу запроса.
filter '{"filter":{"any":[{}]}}'
check "filter с пустым условием: 200 ($(got))" "$(is_code 200)"
check "  count тот же, что без условий" "$(is_eq "$(field .count)" "$ALL")"
check "  options.conditions — один элемент" "$(jq_is '.options.conditions | length' 1)"
DT=$(field '.options.conditions[0].deviceTypes[0].id')
DT_N=$(field '.options.conditions[0].deviceTypes[0].count')
DT2=$(field '.options.conditions[0].deviceTypes[1].id')
DT2_N=$(field '.options.conditions[0].deviceTypes[1].count')
check "  вариант типа устройства: ${DT:-нет} ($DT_N)" "$([ -n "$DT" ] && echo 1 || echo 0)"
[ -n "$DT" ] || finish
filter "{\"filter\":{\"any\":[{\"deviceTypeId\":\"$DT\"}]}}"
check "filter по типу устройства $DT: 200 ($(got))" "$(is_code 200)"
check "  count = числу варианта ($DT_N, получено $(field .count))" "$(is_eq "$(field .count)" "$DT_N")"
EV=$(field '.options.conditions[0].eventTypes[0].id')
EV_N=$(field '.options.conditions[0].eventTypes[0].count')
DEV=$(field '.options.conditions[0].devices[0].id')
DEV_N=$(field '.options.conditions[0].devices[0].count')
check "  вариант события: ${EV:-нет} ($EV_N)" "$([ -n "$EV" ] && echo 1 || echo 0)"
check "  вариант устройства: ${DEV:-нет} ($DEV_N)" "$([ -n "$DEV" ] && echo 1 || echo 0)"
filter "{\"filter\":{\"any\":[{\"deviceTypeId\":\"$DT\",\"eventTypeIds\":[\"$EV\"]}]}}"
check "filter по типу и событию $EV: 200, count = числу варианта ($EV_N, $(got), count $(field .count))" \
  "$([ "$CODE" = 200 ] && [ "$(field .count)" = "$EV_N" ] && echo 1 || echo 0)"
filter "{\"filter\":{\"any\":[{\"deviceTypeId\":\"$DT\",\"deviceGuids\":[\"$DEV\"]}]}}"
check "filter по типу и устройству: 200, count = числу варианта ($DEV_N, $(got), count $(field .count))" \
  "$([ "$CODE" = 200 ] && [ "$(field .count)" = "$DEV_N" ] && echo 1 || echo 0)"
if [ -n "$DT2" ]; then
  filter "{\"filter\":{\"any\":[{\"deviceTypeId\":\"$DT\"},{\"deviceTypeId\":\"$DT2\"}]}}"
  check "filter, два условия «ИЛИ»: count = сумме ($DT_N + $DT2_N, $(got), count $(field .count))" \
    "$([ "$CODE" = 200 ] && [ "$(field .count)" = "$((DT_N + DT2_N))" ] && echo 1 || echo 0)"
else
  skip "filter, два условия «ИЛИ»: в открытых инцидентах стенда один тип устройства"
fi
filter '{"filter":{"any":[{"deviceTypeId":"stage5b-no-such-type"}]}}'
check "filter по неизвестному типу: 200, count 0 ($(got), count $(field .count))" \
  "$([ "$CODE" = 200 ] && [ "$(field .count)" = 0 ] && echo 1 || echo 0)"

# --- Отказы filter.
filter '{"queueFilter":"stage5b-no-such-filter"}'
check "filter, неизвестный queueFilter: 422 FORM_FIELD_REQUIRED ($(got))" \
  "$([ "$CODE" = 422 ] && [ "$(field .code)" = FORM_FIELD_REQUIRED ] && echo 1 || echo 0)"
filter '{"filter":{"bad":1}}'
check "filter, плохой filter: 422 FORM_FIELD_REQUIRED ($(got))" \
  "$([ "$CODE" = 422 ] && [ "$(field .code)" = FORM_FIELD_REQUIRED ] && echo 1 || echo 0)"
filter '{"sourceGroupGuid":"not-a-guid"}'
check "filter, узел не guid: 404 ($(got))" "$(is_code 404)"

# --- filter с sameScenario. На стенде могут быть другие открытые инциденты, поэтому лучший сценарий не обязательно сценарий нашего.
filter '{"sameScenario":true}'
check "filter sameScenario: 200 ($(got))" "$(is_code 200)"
SC=$(field .scenarioGuid)
check "  scenarioGuid есть: ${SC:-нет}" "$([ -n "$SC" ] && echo 1 || echo 0)"
check "  scenarioGuid среди options.scenarios" "$(jq_true '.scenarioGuid as $s | any(.options.scenarios[]; .id == $s)')"
check "  в incidentGuids столько же, сколько в count ($(field .count))" "$(jq_true '(.incidentGuids | length) == .count')"
check "  число сценария = count + excluded или count" \
  "$(jq_true '.scenarioGuid as $s | (.options.scenarios[] | select(.id == $s) | .count) as $n | $n == .count or $n == (.count + .excluded)')"
SC_LIST=$(jq -c '.incidentGuids' "$TMP/body" 2>/dev/null)
check "  все отобранные есть в списке без условий" \
  "$([ "$(jq -r --argjson l "${SC_LIST:-[]}" '($l - .incidentGuids) | length' "$TMP/all" 2>/dev/null)" = 0 ] && echo 1 || echo 0)"
filter '{"sameScenario":true,"scenarioGuid":"not-a-guid"}'
check "filter sameScenario, сценарий не guid: 200, заменён лучшим ($(got))" \
  "$([ "$CODE" = 200 ] && [ "$(field .scenarioGuid)" = "$SC" ] && echo 1 || echo 0)"

# --- Выборка explicit.
selection "{\"mode\":\"explicit\",\"incidentGuids\":[\"$G\"]}"
check "selection explicit: 200 ($(got))" "$(is_code 200)"
check "  incidentGuids — ровно этот инцидент" "$(jq_true '.incidentGuids == [$g]')"
check "  expected[инцидент] = то, что видно в карточке ($SEEN, RULE-142)" "$(jq_true --argjson s "$SEEN" '.expected[$g] == $s')"
check "  claim: виден и доступен" "$(jq_true 'any(.actions[]; .id == "claim" and .visible and .enabled)')"

selection '{"mode":"explicit","incidentGuids":[]}'
check "selection explicit, пустой список: 422 BULK_SELECTION_INVALID ($(got))" \
  "$([ "$CODE" = 422 ] && [ "$(field .code)" = BULK_SELECTION_INVALID ] && echo 1 || echo 0)"
selection '{"mode":"explicit","incidentGuids":["not-a-guid"]}'
check "selection explicit, не guid: 400 BAD_REQUEST ($(got))" \
  "$([ "$CODE" = 400 ] && [ "$(field .code)" = BAD_REQUEST ] && echo 1 || echo 0)"
selection '{"mode":"stage5b-no-such-mode"}'
check "selection, неизвестный mode: 400 ($(got))" "$(is_code 400)"

# --- Выборка all_in_filter.
selection '{"mode":"all_in_filter","filter":"open"}'
check "selection all_in_filter: 200 ($(got))" "$(is_code 200)"
check "  новый инцидент в incidentGuids" "$(jq_true 'any(.incidentGuids[]; . == $g)')"
check "  truncated = false: предел maxBulk null" "$(jq_is .truncated false)"
check "  expected на каждый guid" "$(jq_true '(.expected | keys | sort) == (.incidentGuids | sort)')"
check "  actions — массив, есть claim" "$(jq_true 'any(.actions[]; .id == "claim")')"

# --- 400 массового маршрута: не-guid отвергается до расхода ключа (решение 95).
BODY='{"incidentGuids":["not-a-guid"],"idempotencyKey":"stage5b-'"$RUN"'"}' req POST /operator/incidents/transitions/hold/bulk "$TOKEN"
check "массовый hold, не guid: 400 BAD_REQUEST ($(got))" \
  "$([ "$CODE" = 400 ] && [ "$(field .code)" = BAD_REQUEST ] && echo 1 || echo 0)"

# --- Адресаты передачи: инцидент в работе у оператора, список адресатов из памяти процесса (решение 75).
BODY=$(seen_body "$TOKEN" "/operator/incidents/$G" '{"surface":"card"}') req POST "/operator/incidents/$G/transitions/claim" "$TOKEN"
check "claim: 200 ($(got))" "$(is_code 200)"
VER=$(field .incident.version)
selection "{\"mode\":\"explicit\",\"incidentGuids\":[\"$G\"]}"
check "selection explicit после claim: 200 ($(got))" "$(is_code 200)"
check "  transfer есть в actions" "$(jq_true 'any(.actions[]; .id == "transfer")')"
TARGETS=$(field '[.actions[] | select(.id == "transfer") | .fieldOptions.targetId.options[]?] | length')
ENABLED=$(jq -r '[.actions[] | select(.id == "transfer") | .enabled][0] // false' "$TMP/body" 2>/dev/null)
if [ "$ENABLED" = true ] && [ "${TARGETS:-0}" -gt 0 ]; then
  check "  transfer доступен, адресатов: $TARGETS" 1
elif [ "$ENABLED" != true ] && [ "${TARGETS:-0}" = 0 ]; then
  check "  адресаты transfer: список пуст и enabled: false — а список идёт из operator_sessions (Task 6 плана 62), второй оператор должен быть в нём и без входа" 0
else
  check "  transfer: enabled $ENABLED, адресатов ${TARGETS:-0} — должны совпадать" 0
fi

# --- Закрытие: инцидент уходит из выборки «все в фильтре».
BODY=$(seen_body "$TOKEN" "/operator/incidents/$G" '{"surface":"card","formValues":{"resultId":"false_alarm","causeId":"equipment","comment":"стенд: проверка фильтра"}}') \
  req POST "/operator/incidents/$G/transitions/close" "$TOKEN"
check "close: 200 ($(got))" "$(is_code 200)"
filter '{}'
check "filter после закрытия: инцидента нет" "$(jq_true 'any(.incidentGuids[]; . == $g) | not')"
selection '{"mode":"all_in_filter","filter":"open"}'
check "selection all_in_filter после закрытия: инцидента нет" "$(jq_true 'any(.incidentGuids[]; . == $g) | not')"

finish
