#!/usr/bin/env bash
# Локальный стенд: уровень Г плана 55 — путь инцидента через операторские переходы, только HTTP через шлюз облака.
# Инцидент даёт agent-emulator (одно событие), дальше claim, hold, resume, transfer, accept, close.
# Запускается руками, это не тест. Базы imdb и ac_db напрямую не трогает; единственная запись мимо переходов —
# правило доступа через старый HTTP API (решение 60), только на этом стенде и только если у группы 1 правил нет.
# Каждая проверка — строка "OK|FAIL|SKIP <что>", код выхода — число FAIL.
set -uo pipefail
STAND_DIR="${STAND_DIR:-$HOME/Work/stand}"
CLOUD_REPO="${CLOUD_REPO:-$HOME/Work/axxoncloudgo}"
HERE="$(dirname "$(readlink -f "$0")")"
IM_REPO="${IM_REPO:-$(cd "$HERE/../.." && pwd)}"
API="${API:-https://axxonnet.test/api/v1/im-backend}"
CLOUD="${CLOUD:-https://axxonnet.test}"
CA="$CLOUD_REPO/tools/util/rootCA.axxonnet.test.pem"
EMU="$STAND_DIR/bin/agent-emulator"
FIXTURE="${FIXTURE:-$IM_REPO/Specification/Workflow_machine/fixtures/demo.json}"
source "$HERE/test-operator.sh"; EMAIL="$TEST_EMAIL"
SECOND_EMAIL="${SECOND_EMAIL:-user@gmail.com}"
SECOND_PASS_FILE="${SECOND_PASS_FILE:-$STAND_DIR/second-operator.pass}"
GROUP_ID=1  # cloud-admin
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
jq_is() { [ "$(jq -r "$1" "$TMP/body" 2>/dev/null)" = "$2" ] && echo 1 || echo 0; }
field() { jq -r "$1 // empty" "$TMP/body" 2>/dev/null; }
finish() { echo "итого ошибок: $FAILS"; exit "$FAILS"; }

# group_holds <группа> <источник> — источник лежит в группе или в её вложенных группах.
group_holds() {
  local child
  req GET "/sources/groups/tree?parentGroupGuid=$1" "$TOKEN"
  [ "$(jq -r --arg s "$2" 'any(.sources[]?; .guid == $s)' "$TMP/body" 2>/dev/null)" = true ] && return 0
  for child in $(jq -r '.childGroups[]?.guid' "$TMP/body" 2>/dev/null); do
    group_holds "$child" "$2" && return 0
  done
  return 1
}

# Вход второго оператора и разбор отказов: SKIP только по шагу 5 плана 56, остальное FAIL. Заранее смотрим то, из-за чего
# второй оператор получил бы отказ: права на accept и close, agentState (условие agentReady).
SECOND_PERMS='incident:accept incident:close'
source "$(dirname "$(readlink -f "$0")")/second-operator.sh"
skip_second() { skip "второй оператор: $SECOND_WHY; передача не проверяется, см. открытый вопрос 7 плана 55"; }

# --- Шаг 1. Вход.
operator_login || { echo "SKIP вход: $OPERATOR_WHY"; exit 2; }
check "вход $EMAIL: токен есть" "$([ -n "$TOKEN" ] && echo 1 || echo 0)"

# Первым шагом: оператор начинает в offline (решение 76 плана 56) и на линию выходит сам.
BODY='{"agentState":"ready"}' req PUT /operator/session/agent-state "$TOKEN"
check "первый: PUT agent-state ready: 200 (получено $CODE)" "$(is_code 200)"

second_login
if [ -n "$SECOND" ]; then
  check "вход второго оператора $SECOND_EMAIL: токен есть, incident:accept и incident:close есть, agentState = ready" 1
elif [ -n "$SECOND_BAD" ]; then
  check "второй оператор: $SECOND_BAD" 0
else
  skip_second
fi

# --- Шаг 2. Правило доступа группы 1: у cloud-admin нет правил — одно правило на корневую группу, где лежит источник
# первого события набора. Корневых групп на стенде несколько, источник события — в какой-то из них.
req GET /access-rules "$TOKEN"
check "GET /access-rules: 200 (получено $CODE)" "$(is_code 200)"
RULES=$(jq -r --argjson id "$GROUP_ID" '[.[]? | select(.id == $id) | .rules[]?] | length' "$TMP/body" 2>/dev/null)
if [ "$CODE" = 200 ] && [ "$RULES" = 0 ]; then
  DEVICE=$(jq -r '[.incidents[] | select((.eventGuid // "") != "" and ((.devices // []) | length) > 0)] | unique_by(.eventGuid) | min_by(.occurredAt) | .devices[0]' "$FIXTURE")
  req GET /sources "$TOKEN"
  SOURCE=$(jq -r --arg uid "$DEVICE" '[.[]? | select(.uid == $uid)][0].guid // empty' "$TMP/body" 2>/dev/null)
  check "источник первого события найден (устройство $DEVICE)" "$([ -n "$SOURCE" ] && echo 1 || echo 0)"
  req GET /sources/groups/tree "$TOKEN"
  jq -r '.childGroups[]? | "\(.guid) \(.name)"' "$TMP/body" 2>/dev/null > "$TMP/roots"
  ROOT=''; ROOT_NAME=''
  while read -r guid name; do
    if group_holds "$guid" "$SOURCE"; then ROOT=$guid; ROOT_NAME=$name; break; fi
  done < "$TMP/roots"
  check "корневая группа источника: ${ROOT_NAME:-не найдена}" "$([ -n "$ROOT" ] && echo 1 || echo 0)"
  [ -n "$ROOT" ] || finish
  BODY="{\"userGroupId\":$GROUP_ID,\"rules\":[{\"sourceGroupGuid\":\"$ROOT\"}]}" req POST /access-rules "$TOKEN"
  RULE=$(field '.rules[0].guid')
  check "POST /access-rules: 200 (получено $CODE)" "$(is_code 200)"
  check "  в ответе есть guid правила" "$([ -n "$RULE" ] && echo 1 || echo 0)"
  if [ -z "$RULE" ]; then echo "ВНИМАНИЕ: правило могло быть создано, проверить GET /access-rules"; finish; fi
  echo "СОЗДАНО правило доступа: группа $GROUP_ID (cloud-admin), корневая группа «$ROOT_NAME» ($ROOT), guid правила $RULE"
  echo "Удалить (TOKEN — токен $EMAIL): curl --cacert $CA -X DELETE -H \"Authorization: Bearer \$TOKEN\" -H 'Content-Type: application/json' -d '[\"$RULE\"]' $API/access-rules"
else
  echo "правила доступа не менялись: у группы $GROUP_ID правил — ${RULES:-?}"
fi

# --- Шаг 3. Сессия: Directory запоминает обоих.
req GET /operator/session "$TOKEN"
check "первый: GET /operator/session: 200 (получено $CODE)" "$(is_code 200)"
if [ -n "$SECOND" ]; then
  req GET /operator/session "$SECOND"
  check "второй: GET /operator/session: 200 (получено $CODE)" "$(is_code 200)"
  SECOND_ID=$(field '.operator.guid')
  check "  второй: operator.guid есть" "$([ -n "$SECOND_ID" ] && echo 1 || echo 0)"
fi

# --- Шаг 4. Один инцидент от эмулятора. В старом GET /incidents поля state нет: инцидент ищем по guid события
# из вывода эмулятора (самый новый), а state проверяем по карточке на шаге 5.
RUN="stage4c-$(date +%s)"
"$EMU" replay --limit 1 --run "$RUN" > "$TMP/emu" 2>&1
EMU_CODE=$?
EVENT=$(grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' "$TMP/emu" | head -1)
check "agent-emulator replay --limit 1 --run $RUN: код $EMU_CODE, отправлено 1" \
  "$([ "$EMU_CODE" = 0 ] && grep -q 'отправлено 1,' "$TMP/emu" && echo 1 || echo 0)"
req GET /incidents "$TOKEN"
check "GET /incidents (старый): 200 (получено $CODE)" "$(is_code 200)"
G=$(jq -r --arg e "$EVENT" '[.[]? | select(.event.guid == $e)] | max_by(.createdAt).guid // empty' "$TMP/body" 2>/dev/null)
check "инцидент события ${EVENT:-?}: ${G:-нет}" "$([ -n "$G" ] && echo 1 || echo 0)"
[ -n "$G" ] || finish

# --- Шаг 5–6. Карточка и переходы; на каждом шаге — код и state.
CARD="/operator/incidents/$G"
got() { echo "получено $CODE$(c=$(field .code); [ -n "$c" ] && echo ", code $c")"; }

req GET "$CARD" "$TOKEN"
check "GET карточки: 200 ($(got))" "$(is_code 200)"
check "  state = new (получено $(field .state))" "$(jq_is .state new)"
VER=$(field .version)
check "  ETag = \"$VER\"" "$(grep -iq "^etag: \"$VER\"" "$TMP/hdr" && [ -n "$VER" ] && echo 1 || echo 0)"
[ -n "$VER" ] || finish

# act <токен> <переход> <тело> <ждём state>: переход с тем, что видел оператор (RULE-142: state, адресат, журнал), версия — в $VER.
act() {
  local tok=$1 id=$2 body=$3 want=$4 next
  BODY=$(seen_body "$tok" "$CARD" "$body") req POST "$CARD/transitions/$id" "$tok"
  check "$id: 200 ($(got))" "$(is_code 200)"
  check "  state = $want (получено $(field .incident.state))" "$(jq_is .incident.state "$want")"
  next=$(field .incident.version)
  [ -n "$next" ] && VER=$next
}

OLD=$(seen_body "$TOKEN" "$CARD" '{"surface":"card"}')
act "$TOKEN" claim '{"surface":"card"}' in_progress

BODY="$OLD" req POST "$CARD/transitions/claim" "$TOKEN"
check "повтор claim со старым снимком (state new): 412 ($(got))" "$(is_code 412)"
check "  code = INCIDENT_CHANGED" "$(jq_is .code INCIDENT_CHANGED)"
check "  details.changed = state или addressee (получено $(field .details.changed))" "$([ "$(field .details.changed)" = state ] || [ "$(field .details.changed)" = addressee ] && echo 1 || echo 0)"
check "  current.state = in_progress (получено $(field .current.state))" "$(jq_is .current.state in_progress)"
BODY='{"surface":"card"}' req POST "$CARD/transitions/claim" "$TOKEN"
check "claim без expectedState: 428 ($(got))" "$(is_code 428)"

req GET /operator/reference/reasons/hold "$TOKEN"
check "GET /operator/reference/reasons/hold: 200 ($(got))" "$(is_code 200)"
REASON=$(jq -r '[.[]? | select(.setBy == "operator")][0].id // empty' "$TMP/body" 2>/dev/null)
check "причина удержания: ${REASON:-нет}" "$([ -n "$REASON" ] && echo 1 || echo 0)"

act "$TOKEN" hold "{\"surface\":\"card\",\"formValues\":{\"reasonId\":\"$REASON\",\"comment\":\"стенд: удержание\"}}" on_hold
act "$TOKEN" resume '{"surface":"card"}' in_progress

CLOSE='{"surface":"card","formValues":{"resultId":"false_alarm","causeId":"equipment","comment":"стенд: закрытие"}}'

# Адресаты инцидента — те же варианты, что форма «Передать» (offersTransferTo: нужны доступ и право принять). Второй
# оператор без правила получил бы отказ targetHasAccess: это SKIP, но только когда отсутствие правил подтверждено.
if [ -n "$SECOND" ] && [ -n "$SECOND_ID" ]; then
  req GET "/operator/transfer-targets?incidentGuid=$G" "$TOKEN"
  check "GET /operator/transfer-targets инцидента: 200 ($(got))" "$(is_code 200)"
  if [ "$(jq -r --arg id "$SECOND_ID" 'any(.[]?; .id == $id)' "$TMP/body" 2>/dev/null)" != true ]; then
    second_rules "$SECOND"
    if [ "$SECOND_RULES" = 0 ]; then
      SECOND_WHY="$SECOND_EMAIL нет среди адресатов инцидента: у его групп нет правил доступа"
      skip_second
    else
      check "$SECOND_EMAIL нет среди адресатов инцидента, а правил у его групп: ${SECOND_RULES:-не удалось узнать}" 0
    fi
    SECOND=''
  fi
fi

if [ -n "$SECOND" ] && [ -n "$SECOND_ID" ]; then
  act "$TOKEN" transfer "{\"surface\":\"card\",\"formValues\":{\"targetId\":\"$SECOND_ID\",\"comment\":\"стенд: передача\"}}" pending_acceptance
  act "$SECOND" accept '{"surface":"card"}' in_progress
  act "$SECOND" close "$CLOSE" closed
else
  skip "transfer: нет второго оператора"
  skip "accept: нет второго оператора"
  act "$TOKEN" close "$CLOSE" closed
fi

req GET "$CARD" "$TOKEN"
check "GET карточки после закрытия: 200 ($(got))" "$(is_code 200)"
check "  state = closed (получено $(field .state)), версия $VER" "$([ "$(field .state)" = closed ] && [ "$(field .version)" = "$VER" ] && echo 1 || echo 0)"

finish
