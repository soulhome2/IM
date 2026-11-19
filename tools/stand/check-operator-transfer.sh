#!/usr/bin/env bash
# Локальный стенд: передача двумя операторами (Task 8 плана 62). Только HTTP через шлюз облака.
# Инцидент даёт agent-emulator (одно событие). Первый берёт его (claim), передаёт второму (transfer), второй принимает
# (accept); после каждого шага — GET карточки. Адресатов передачи первый смотрит ДО входа второго: после перезапуска
# сервера второй должен быть в списке по строке operator_sessions (Task 6), а не по памяти процесса.
# trap на EXIT закрывает созданный инцидент без обработки и отдельной строкой проверяет closed по API.
# IM_STAND_FAIL_AFTER=claim — выйти сразу после claim (проверка уборки).
# Каждая проверка — строка "OK|FAIL|SKIP <что>". Код: число FAIL; нет второго оператора — SKIP и код 2.
set -uo pipefail
STAND_DIR="${STAND_DIR:-$HOME/Work/stand}"
CLOUD_REPO="${CLOUD_REPO:-$HOME/Work/axxoncloudgo}"
HERE="$(dirname "$(readlink -f "$0")")"
API="${API:-https://axxonnet.test/api/v1/im-backend}"
CLOUD="${CLOUD:-https://axxonnet.test}"
CA="${CA:-$CLOUD_REPO/tools/util/rootCA.axxonnet.test.pem}"
EMU="$STAND_DIR/bin/agent-emulator"
FAIL_AFTER="${IM_STAND_FAIL_AFTER:-}"
source "$HERE/test-operator.sh"; EMAIL="$TEST_EMAIL"
SECOND_EMAIL="${SECOND_EMAIL:-user@gmail.com}"
SECOND_PASS_FILE="${SECOND_PASS_FILE:-$STAND_DIR/second-operator.pass}"
TMP=$(mktemp -d)
FAILS=0; G=''; TOKEN=''; SECOND=''
source "$HERE/seen-body.sh"

req() { # req <метод> <путь> <токен|-> [заголовки...] — код в $CODE, тело в $TMP/body, тело запроса — в BODY
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
jq_is() { [ "$(jq -r "$1" "$TMP/body" 2>/dev/null)" = "$2" ] && echo 1 || echo 0; }
field() { jq -r "$1 // empty" "$TMP/body" 2>/dev/null; }
got() { echo "получено $CODE$(c=$(field .code); [ -n "$c" ] && echo ", code $c")"; }

SECOND_PERMS='incident:accept'
source "$(dirname "$(readlink -f "$0")")/second-operator.sh"

# enabled <токен> <переход> — переход доступен этому оператору в карточке G (версия — в $VER).
enabled() {
  req GET "/operator/incidents/$G" "$1"
  VER=$(field .version)
  [ "$CODE" = 200 ] && [ "$(jq -r --arg a "$2" 'any(.actions[]?; .id == $a and .enabled)' "$TMP/body" 2>/dev/null)" = true ]
}

# cleanup — инцидент, созданный скриптом, закрывается без обработки тем, кому close доступен; кому нет — сначала claim.
cleanup() {
  local code=$? tok step
  if [ -n "$G" ] && [ -n "$TOKEN" ]; then
    for step in 1 2 3 4; do
      req GET "/operator/incidents/$G" "$TOKEN"
      [ "$(field .state)" = closed ] && break
      for tok in "$TOKEN" ${SECOND:+"$SECOND"}; do
        if enabled "$tok" close; then
          BODY=$(seen_body "$tok" "/operator/incidents/$G" '{"surface":"card","formValues":{"resultId":"false_alarm","causeId":"equipment","comment":"стенд: уборка check-operator-transfer"}}') \
            req POST "/operator/incidents/$G/transitions/close" "$tok"
          break
        elif enabled "$tok" claim; then
          BODY=$(seen_body "$tok" "/operator/incidents/$G" '{"surface":"card"}') req POST "/operator/incidents/$G/transitions/claim" "$tok"
          break
        fi
      done
    done
    req GET "/operator/incidents/$G" "$TOKEN"
    check "уборка: инцидент $G закрыт по API (state $(field .state))" "$(jq_is .state closed)"
  fi
  rm -rf "$TMP"
  if [ "$code" = 2 ]; then exit 2; fi
  echo "итого ошибок: $FAILS"
  exit "$FAILS"
}
trap cleanup EXIT

# --- Вход первого и линия.
operator_login || { echo "SKIP вход: $OPERATOR_WHY"; exit 2; }
check "вход $EMAIL: токен есть" 1
BODY='{"agentState":"ready"}' req PUT /operator/session/agent-state "$TOKEN"
check "первый: PUT agent-state ready: 200 ($(got))" "$(is_code 200)"
if [ ! -f "$SECOND_PASS_FILE" ]; then
  echo "SKIP второй оператор: нет файла $SECOND_PASS_FILE"; exit 2
fi

# --- Один инцидент от эмулятора.
RUN="p62t8-$(date +%s)"
"$EMU" replay --limit 1 --run "$RUN" > "$TMP/emu" 2>&1
EMU_CODE=$?
EVENT=$(grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' "$TMP/emu" | head -1)
check "agent-emulator replay --limit 1 --run $RUN: код $EMU_CODE, отправлено 1" \
  "$([ "$EMU_CODE" = 0 ] && grep -q 'отправлено 1,' "$TMP/emu" && echo 1 || echo 0)"
req GET /incidents "$TOKEN"
G=$(jq -r --arg e "$EVENT" '[.[]? | select(.event.guid == $e)] | max_by(.createdAt).guid // empty' "$TMP/body" 2>/dev/null)
check "инцидент события ${EVENT:-?}: ${G:-нет}" "$([ -n "$G" ] && echo 1 || echo 0)"
[ -n "$G" ] || exit
CARD="/operator/incidents/$G"

# act <токен> <переход> <тело> — переход с тем, что видел оператор (RULE-142).
act() {
  req GET "$CARD" "$1"; VER=$(field .version)
  BODY=$(seen_body "$1" "$CARD" "$3") req POST "$CARD/transitions/$2" "$1"
  check "$2: 200 ($(got))" "$(is_code 200)"
}

req GET "$CARD" "$TOKEN"
check "GET карточки: 200, state new (получено $CODE, $(field .state))" "$([ "$CODE" = 200 ] && [ "$(field .state)" = new ] && echo 1 || echo 0)"
act "$TOKEN" claim '{"surface":"card"}'
req GET "$CARD" "$TOKEN"
check "  карточка: state in_progress (получено $(field .state))" "$(jq_is .state in_progress)"
FIRST_ID=$(req GET /operator/session "$TOKEN"; field .operator.guid)
if [ "$FAIL_AFTER" = claim ]; then echo "IM_STAND_FAIL_AFTER=claim: выход после claim"; exit; fi

# --- Адресаты до входа второго: только строка operator_sessions (Task 6).
req GET "/operator/transfer-targets?incidentGuid=$G" "$TOKEN"
check "GET /operator/transfer-targets инцидента до входа второго: 200 ($(got))" "$(is_code 200)"
cp "$TMP/body" "$TMP/targets-before"

# --- Вход второго.
second_login
if [ -z "$SECOND" ]; then
  if [ -n "$SECOND_BAD" ]; then check "второй оператор: $SECOND_BAD" 0; exit; fi
  echo "SKIP второй оператор: $SECOND_WHY"; exit 2
fi
check "вход второго $SECOND_EMAIL: agentState ready, incident:accept есть, id $SECOND_ID" 1
check "  до его входа он уже был среди адресатов" \
  "$([ "$(jq -r --arg id "$SECOND_ID" 'any(.[]?; .id == $id)' "$TMP/targets-before" 2>/dev/null)" = true ] && echo 1 || echo 0)"

# --- Передача и принятие.
act "$TOKEN" transfer "{\"surface\":\"card\",\"formValues\":{\"targetId\":\"$SECOND_ID\",\"comment\":\"стенд: передача\"}}"
req GET "$CARD" "$TOKEN"
check "  карточка: pending_acceptance, адресат — второй (получено $(field .state), $(field .addressee.id))" \
  "$([ "$(field .state)" = pending_acceptance ] && [ "$(field .addressee.id)" = "$SECOND_ID" ] && echo 1 || echo 0)"
act "$SECOND" accept '{"surface":"card"}'
req GET "$CARD" "$SECOND"
check "  карточка: in_progress, владелец — второй (получено $(field .state), $(field .owner.id), первый $FIRST_ID)" \
  "$([ "$(field .state)" = in_progress ] && [ "$(field .owner.id)" = "$SECOND_ID" ] && echo 1 || echo 0)"
