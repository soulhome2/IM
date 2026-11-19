#!/usr/bin/env bash
# Локальный стенд, этап 6 (Task 18): планировщик на настоящей связке — эскалация по нормативу и молчание.
# Нужен сервер с патчем машины (im-machine-patch.sh, решение 210): уровень 1 — второй оператор, reactionSec 60,
# idleHoldSec 60, idleReleaseSec 120. Только HTTP через шлюз облака; инцидент даёт agent-emulator (одно событие).
# Шаги: второй на линии; событие; ждём до 480 с (опрос раз в 10 с) pending_acceptance с адресатом-вторым и уровнем 1;
# второй — accept; второй молчит — on_hold с причиной no_link; ещё молчит — new.
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
SECOND_EMAIL="${SECOND_EMAIL:-user@gmail.com}"
SECOND_PASS_FILE="${SECOND_PASS_FILE:-$STAND_DIR/second-operator.pass}"
SECOND_PERMS='incident:accept'
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
finish() { echo "итого ошибок: $FAILS"; exit "$FAILS"; }
got() { echo "получено $CODE$(c=$(field .code); [ -n "$c" ] && echo ", code $c")"; }
source "$(dirname "$(readlink -f "$0")")/second-operator.sh"

operator_login || { echo "SKIP вход: $OPERATOR_WHY"; exit 2; }
check "вход $EMAIL: токен есть" "$([ -n "$TOKEN" ] && echo 1 || echo 0)"
BODY='{"agentState":"ready"}' req PUT /operator/session/agent-state "$TOKEN"
check "первый: PUT agent-state ready: 200 (получено $CODE)" "$(is_code 200)"

# --- Второй на линии.
second_login
if [ -n "$SECOND" ]; then
  check "второй $SECOND_EMAIL на линии, id $SECOND_ID" 1
elif [ -n "$SECOND_BAD" ]; then
  check "второй оператор: $SECOND_BAD" 0; finish
else
  skip "второй оператор: $SECOND_WHY (second-operator.sh); эскалация на второго не проверяется"; finish
fi

# --- Событие эмулятора.
RUN="stage6-sched-$(date +%s)"
"$EMU" replay --limit 1 --run "$RUN" > "$TMP/emu" 2>&1
EMU_CODE=$?
EVENT=$(grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' "$TMP/emu" | head -1)
check "agent-emulator replay --limit 1 --run $RUN: код $EMU_CODE, отправлено 1" \
  "$([ "$EMU_CODE" = 0 ] && grep -q 'отправлено 1,' "$TMP/emu" && echo 1 || echo 0)"
req GET /incidents "$TOKEN"
G=$(jq -r --arg e "$EVENT" '[.[]? | select(.event.guid == $e)] | max_by(.createdAt).guid // empty' "$TMP/body" 2>/dev/null)
check "инцидент события ${EVENT:-?}: ${G:-нет}" "$([ -n "$G" ] && echo 1 || echo 0)"
[ -n "$G" ] || finish
CARD="/operator/incidents/$G"

# wait_card <секунд> <jq-условие> — опрос карточки раз в 10 с; в $WAITED — сколько прошло.
wait_card() {
  local limit=$1 cond=$2 start=$SECONDS
  while :; do
    req GET "$CARD" "$TOKEN"
    WAITED=$((SECONDS - start))
    [ "$CODE" = 200 ] && [ "$(jq -r "$cond" "$TMP/body" 2>/dev/null)" = true ] && return 0
    [ "$WAITED" -ge "$limit" ] && return 1
    sleep 10
  done
}
show() { jq -r '"state \(.state), адресат \(.addressee.id // "-"), владелец \(.owner.id // "-"), уровень \(.escalationLevel), причина \(.holdReasonId // "-")"' "$TMP/body" 2>/dev/null; }

# --- Эскалация по нормативу реакции.
COND=".state == \"pending_acceptance\" and .addressee.id == \"$SECOND_ID\" and .escalationLevel == 1"
# До 480 с: эскалация идёт по нарушению реакции, норматив события эмулятора (приоритет 75) — 7 мин.
wait_card 480 "$COND"; ok=$?
check "эскалация: pending_acceptance, адресат — второй, уровень 1 (через $WAITED с; $(show))" "$([ $ok = 0 ] && echo 1 || echo 0)"
[ $ok = 0 ] || finish

# --- Второй принимает.
req GET "$CARD" "$SECOND"
VER=$(field .version)
BODY=$(seen_body "$SECOND" "$CARD" '{"surface":"card"}') req POST "$CARD/transitions/accept" "$SECOND"
check "второй: accept: 200 ($(got)), state $(field .incident.state)" "$(is_code 200)"
[ "$CODE" = 200 ] || finish

# --- Второй молчит: ни запросов, ни heartbeat. idleHoldSec 60 — on_hold с no_link.
wait_card 120 '.state == "on_hold" and .holdReasonId == "no_link"'; ok=$?
check "молчание: on_hold, причина no_link (через $WAITED с; $(show))" "$([ $ok = 0 ] && echo 1 || echo 0)"
[ $ok = 0 ] || finish

# --- Ещё 60 с (idleReleaseSec 120) — в очередь.
wait_card 120 '.state == "new"'; ok=$?
check "возврат: new (через $WAITED с; $(show))" "$([ $ok = 0 ] && echo 1 || echo 0)"
echo "инцидент $G"
finish
