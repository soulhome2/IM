#!/usr/bin/env bash
# Локальный стенд, этап 6 (Task 18): пишет $STAND_DIR/im-machine-patch.json по решению 210 плана 60 —
# JSON Merge Patch машины стенда: уровень эскалации 1 — второй оператор (60 с), потолок 1, алерты — первому,
# молчание: idleHoldSec 60, idleReleaseSec 120. id обоих — operator.guid из GET /operator/session.
# Сервер читает файл при старте только с IM_TEST_SUPPORT=true IM_MACHINE_PATCH=<файл>. Снимается: rm файла и запуск без переменных.
# Вход второго — second-operator.sh (он сам читает свой файл пароля); второй при этом выходит на линию.
# Запускать под замком стенда ($STAND_DIR/lock-server). Код выхода 0 — файл записан.
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
SECOND_PERMS='incident:accept'
OUT="${OUT:-$STAND_DIR/im-machine-patch.json}"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

req() {
  local method=$1 path=$2 tok=$3; shift 3
  local args=(-s --max-time 20 --cacert "$CA" -X "$method" -o "$TMP/body" -D "$TMP/hdr" -w '%{http_code}')
  [ "$tok" != "-" ] && args+=(-H "Authorization: Bearer $tok")
  [ -n "${BODY:-}" ] && args+=(-H 'Content-Type: application/json' -d "$BODY")
  for h in "$@"; do args+=(-H "$h"); done
  CODE=$(curl "${args[@]}" "$API$path")
}
field() { jq -r "$1 // empty" "$TMP/body" 2>/dev/null; }
source "$(dirname "$(readlink -f "$0")")/second-operator.sh"

operator_login || { echo "$OPERATOR_WHY" >&2; exit 1; }
req GET /operator/session "$TOKEN"
FIRST_ID=$(field .operator.guid)
[ "$CODE" = 200 ] && [ -n "$FIRST_ID" ] || { echo "FAIL GET /operator/session первого: $CODE"; exit 1; }

second_login
if [ -z "$SECOND" ]; then echo "FAIL второй оператор: ${SECOND_BAD:-$SECOND_WHY}"; exit 1; fi

jq -n --arg first "$FIRST_ID" --arg second "$SECOND_ID" '{
  escalation: {levels: [{level: 1, targetKind: "user", target: $second, reactionSec: 60}], maxLevel: 1},
  alerts: {targetKind: "user", target: $first},
  session: {idleHoldSec: 60, idleReleaseSec: 120}
}' > "$OUT" || { echo "FAIL запись $OUT"; exit 1; }
echo "OK   $OUT: первый $FIRST_ID, второй $SECOND_ID, sha256 файла $(sha256sum "$OUT" | cut -d' ' -f1)"
