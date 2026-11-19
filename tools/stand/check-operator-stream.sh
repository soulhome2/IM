#!/usr/bin/env bash
# Локальный стенд: уровень В плана 56 — поток операторского API через шлюз облака, настоящие токены, две curl -N.
# Инциденты даёт agent-emulator, переходы идут по HTTP. Запускается руками, это не тест. Базы напрямую не трогает.
# Каждая проверка — строка "OK|FAIL|SKIP <что>", код выхода — число FAIL.
# Без файла пароля оба потока — две сессии test@axxonnet.test, разные пользователи дают SKIP с причиной.
set -uo pipefail
STAND_DIR="${STAND_DIR:-$HOME/Work/stand}"
CLOUD_REPO="${CLOUD_REPO:-$HOME/Work/axxoncloudgo}"
HERE="$(dirname "$(readlink -f "$0")")"
API="${API:-https://axxonnet.test/api/v1/im-backend}"
CLOUD="${CLOUD:-https://axxonnet.test}"
DIRECT="${DIRECT:-http://127.0.0.1:5000/api/v1/im-backend}"
CA="$CLOUD_REPO/tools/util/rootCA.axxonnet.test.pem"
EMU="$STAND_DIR/bin/agent-emulator"
source "$HERE/test-operator.sh"; EMAIL="$TEST_EMAIL"
SECOND_EMAIL="${SECOND_EMAIL:-user@gmail.com}"
SECOND_PASS_FILE="${SECOND_PASS_FILE:-$STAND_DIR/second-operator.pass}"
LIMIT_MS=2000   # событие дольше этого — значит, его держит буфер
PING_SEC=20     # пинг идёт раз в 15 с
TMP=$(mktemp -d)
declare -A PID=()
cleanup() { local p; for p in "${PID[@]}"; do kill "$p" 2>/dev/null; done; rm -rf "$TMP"; }
trap cleanup EXIT
FAILS=0; OKS=0; SKIPS=0; LATENCY=''
source "$HERE/seen-body.sh"
RUN="stage5a-$(date +%s)"; RUNS=0

check() { # check <что> <условие истинно?>
  if [ "$2" = "1" ]; then echo "OK   $1"; OKS=$((OKS+1)); else echo "FAIL $1"; FAILS=$((FAILS+1)); fi
}
skip() { echo "SKIP $1"; SKIPS=$((SKIPS+1)); }
yes_no() { "$@" && echo 1 || echo 0; }
finish() {
  echo "задержки, мс:${LATENCY:- нет}"
  echo "итого: OK $OKS, FAIL $FAILS, SKIP $SKIPS"
  echo "итого ошибок: $FAILS"
  exit "$FAILS"
}
now() { echo "${EPOCHREALTIME/[.,]/}"; }  # микросекунды

# req <метод> <путь> <токен> [заголовки...] — код ответа в $CODE, тело в $TMP/body. Тело запроса — в переменной BODY.
req() {
  local method=$1 path=$2 tok=$3; shift 3
  local args=(-s --max-time 20 --cacert "$CA" -X "$method" -o "$TMP/body" -D "$TMP/hdr" -w '%{http_code}' -H "Authorization: Bearer $tok")
  [ -n "${BODY:-}" ] && args+=(-H 'Content-Type: application/json' -d "$BODY")
  for h in "$@"; do args+=(-H "$h"); done
  CODE=$(curl "${args[@]}" "$API$path")
}
field() { jq -r "$1 // empty" "$TMP/body" 2>/dev/null; }
is_code() { [ "$CODE" = "$1" ] && echo 1 || echo 0; }

# stamp — каждая строка со временем прихода: "<мкс> <строка>".
stamp() { local line; while IFS= read -r line; do printf '%s %s\n' "$(now)" "$line"; done; }

# open_stream <имя> <токен> [Last-Event-ID] — curl -N через шлюз, журнал кадров в $TMP/<имя>.log.
open_stream() {
  local name=$1 tok=$2 last=${3:-}
  local args=(-s -N --cacert "$CA" -D "$TMP/$name.hdr" -H "Authorization: Bearer $tok" -H 'Accept: text/event-stream')
  [ -n "$last" ] && args+=(-H "Last-Event-ID: $last")
  : > "$TMP/$name.log"
  curl "${args[@]}" "$API/operator/stream" > >(stamp > "$TMP/$name.log") 2>/dev/null &
  PID[$name]=$!
}
close_stream() { kill "${PID[$1]}" 2>/dev/null; wait "${PID[$1]}" 2>/dev/null; unset "PID[$1]"; }

lines() { wc -l < "$TMP/$1.log"; }
last_id() { sed -n 's/^[0-9]* id: //p' "$TMP/$1.log" | tail -1; }
# frames <поток> [сколько строк пропустить] — кадры с данными: {"t":<мкс прихода>,"f":<сообщение>} по одному в строке.
frames() { tail -n +$(( ${2:-0} + 1 )) "$TMP/$1.log" | sed -n 's/^\([0-9]*\) data: \(.*\)$/{"t":\1,"f":\2}/p'; }

# wait_frame <поток> <с какой строки> <условие jq на .f> <секунд> — первый подходящий кадр: $FRAME и $STAMP, иначе они пусты.
wait_frame() {
  local name=$1 from=$2 cond=$3 sec=$4 end hit
  end=$(( $(now) + sec * 1000000 ))
  while :; do
    hit=$(frames "$name" "$from" | jq -c "select($cond)" 2>/dev/null | head -1)
    if [ -n "$hit" ]; then STAMP=$(jq -r .t <<<"$hit"); FRAME=$(jq -c .f <<<"$hit"); return 0; fi
    if [ "$(now)" -ge "$end" ]; then STAMP=''; FRAME=''; return 1; fi
    sleep 0.02
  done
}
# wait_line <поток> <с какой строки> <шаблон awk> <секунд> — строка журнала без времени пришла; $STAMP — когда.
wait_line() {
  local name=$1 from=$2 pat=$3 sec=$4 end hit
  end=$(( $(now) + sec * 1000000 ))
  while :; do
    hit=$(awk -v from="$from" -v pat="$pat" 'NR > from { s = $1; l = $0; sub(/^[0-9]+ ?/, "", l); if (l ~ pat) { print s; exit } }' "$TMP/$name.log")
    if [ -n "$hit" ]; then STAMP=$hit; return 0; fi
    if [ "$(now)" -ge "$end" ]; then STAMP=''; return 1; fi
    sleep 0.02
  done
}
# arrived <что> — итог ожидания: кадр пришёл и быстрее LIMIT_MS, считая от $T0.
arrived() {
  local ms
  if [ -z "$STAMP" ]; then check "$1: не пришло" 0; return; fi
  ms=$(( (STAMP - T0) / 1000 ))
  LATENCY="$LATENCY $ms"
  check "$1: $ms мс (нужно меньше $LIMIT_MS)" "$([ "$ms" -lt "$LIMIT_MS" ] && echo 1 || echo 0)"
}
# frames_are_whole <поток> — у каждого кадра с данными строка id: перед data: равна его .id, строк event: нет (контракт).
frames_are_whole() {
  local bad
  bad=$(awk '{ l = $0; sub(/^[0-9]+ ?/, "", l); if (index(l, "data: ") == 1) print prev "\t" substr(l, 7); prev = l }' "$TMP/$1.log" \
    | jq -R 'split("\t") | select((.[0] | sub("^id: "; "")) != (.[1] | fromjson | .id))' | wc -l)
  [ "$bad" = 0 ] && ! grep -Eq '^[0-9]+ event:' "$TMP/$1.log"
}

# new_incident — одно событие эмулятора; поток a даёт guid нового инцидента в $G, задержка считается от $T0.
new_incident() {
  local from
  from=$(lines a)
  RUNS=$((RUNS+1))
  T0=$(now)
  "$EMU" replay --limit 1 --run "$RUN-$RUNS" > "$TMP/emu" 2>&1
  EMU_CODE=$?
  check "agent-emulator replay --limit 1 --run $RUN-$RUNS: код $EMU_CODE, отправлено 1" \
    "$([ "$EMU_CODE" = 0 ] && grep -q 'отправлено 1,' "$TMP/emu" && echo 1 || echo 0)"
  wait_frame a "$from" '.f.type == "incident.created"' 5
  G=$(jq -r '.incidentGuid // empty' <<<"${FRAME:-null}")
}
# move <токен> <guid> <переход> <тело> — переход с тем, что видел оператор (RULE-142). $T0 — миг перед запросом.
move() {
  local tok=$1 g=$2 id=$3 body=$4 ver
  req GET "/operator/incidents/$g" "$tok"
  ver=$(field .version)
  T0=$(now)
  BODY=$(seen_body "$tok" "/operator/incidents/$g" "$body") req POST "/operator/incidents/$g/transitions/$id" "$tok"
}
CLAIM='{"surface":"card"}'
CLOSE='{"surface":"card","formValues":{"resultId":"false_alarm","causeId":"equipment","comment":"стенд: проверка потока"}}'

# Вход второго оператора и разбор отказов: SKIP только по шагу 5, остальное FAIL.
SECOND_PERMS='incident:claim incident:close'
source "$(dirname "$(readlink -f "$0")")/second-operator.sh"

# second_sees <guid> — второй открывает карточку. Нет — строка SKIP или FAIL и код 1.
second_sees() {
  req GET "/operator/incidents/$1" "$SECOND"
  [ "$CODE" = 200 ] && return 0
  if second_denied "$CODE" "$1"; then skip "разные пользователи: $SECOND_WHY"; else check "разные пользователи: $SECOND_BAD" 0; fi
  return 1
}

# seen_by <поток> <от строки> <guid> <кто сделал> <что> — переход инцидента дошёл до потока, с верным actor.
seen_by() {
  wait_frame "$1" "$2" ".f.type == \"incident.transitioned\" and .f.incidentGuid == \"$3\"" 5
  arrived "$5"
  check "  actor — $4 (получено $(jq -r '.actor.id // empty' <<<"${FRAME:-null}"))" \
    "$([ "$(jq -r '.actor.id // empty' <<<"${FRAME:-null}")" = "$4" ] && echo 1 || echo 0)"
}

# Разные пользователи: у каждого свой инцидент, действия одного приходят другому без запроса. Передачи здесь нет:
# для обмена событиями хватает claim и close.
two_people() {
  local g1 g2 from
  check "вход второго оператора $SECOND_EMAIL: токен, PUT ready, incident:claim и incident:close есть" 1
  open_stream s "$SECOND"
  wait_line s 0 '^(id: [0-9]+)?$' 5
  check "поток второго оператора открыт ($(sed -n 's/^HTTP[^ ]* //p' "$TMP/s.hdr" | tr -d '\r' | head -1))" "$(grep -q '^HTTP[^ ]* 200' "$TMP/s.hdr" && echo 1 || echo 0)"

  from=$(lines s)
  new_incident; g1=$G
  check "инцидент для первого: ${g1:-нет}" "$([ -n "$g1" ] && echo 1 || echo 0)"
  [ -n "$g1" ] || return
  if ! second_sees "$g1"; then
    move "$TOKEN" "$g1" claim "$CLAIM"; move "$TOKEN" "$g1" close "$CLOSE"
    return
  fi
  wait_frame s "$from" ".f.type == \"incident.created\" and .f.incidentGuid == \"$g1\"" 5
  arrived "второй оператор: incident.created"

  new_incident; g2=$G
  check "инцидент для второго: ${g2:-нет}" "$([ -n "$g2" ] && echo 1 || echo 0)"
  [ -n "$g2" ] || return

  from=$(lines s)
  move "$TOKEN" "$g1" claim "$CLAIM"
  check "первый: claim: 200 (получено $CODE)" "$(is_code 200)"
  seen_by s "$from" "$g1" "$FIRST_ID" "claim первого дошёл до второго"

  from=$(lines a)
  move "$SECOND" "$g2" claim "$CLAIM"
  check "второй: claim: 200 (получено $CODE)" "$(is_code 200)"
  seen_by a "$from" "$g2" "$SECOND_ID" "claim второго дошёл до первого"

  from=$(lines s)
  move "$TOKEN" "$g1" close "$CLOSE"
  check "первый: close: 200 (получено $CODE)" "$(is_code 200)"
  seen_by s "$from" "$g1" "$FIRST_ID" "close первого дошёл до второго"

  from=$(lines a)
  move "$SECOND" "$g2" close "$CLOSE"
  check "второй: close: 200 (получено $CODE)" "$(is_code 200)"
  seen_by a "$from" "$g2" "$SECOND_ID" "close второго дошёл до первого"
  check "кадры второго оператора целые: id совпадает, строк event: нет" "$(yes_no frames_are_whole s)"
  close_stream s
}

# --- Шаг 1. Два входа одного пользователя. Оператор начинает в offline (решение 76 плана 56), на линию выходит сам.
operator_login || { echo "SKIP вход: $OPERATOR_WHY"; exit 2; }
check "вход $EMAIL: токен есть" "$([ -n "$TOKEN" ] && echo 1 || echo 0)"
BODY='{"agentState":"ready"}' req PUT /operator/session/agent-state "$TOKEN"
check "первая сессия: PUT agent-state ready: 200 (получено $CODE)" "$(is_code 200)"
req GET /operator/session "$TOKEN"
FIRST_ID=$(field .operator.guid)

TOKEN1=$TOKEN; operator_login; TOKEN2=$TOKEN; TOKEN=$TOKEN1
check "второй вход $EMAIL: токен есть" "$([ -n "$TOKEN2" ] && echo 1 || echo 0)"
[ -n "$TOKEN2" ] || finish
BODY='{"agentState":"ready"}' req PUT /operator/session/agent-state "$TOKEN2"
check "вторая сессия: PUT agent-state ready: 200 (получено $CODE)" "$(is_code 200)"

# --- Шаг 2. Две curl -N через шлюз. Без Last-Event-ID поток идёт с конца, первый кадр — один id, без data.
CODE=$(curl -s --max-time 5 --cacert "$CA" -o "$TMP/body" -w '%{http_code}' "$API/operator/stream")
check "поток без токена: 401 (получено $CODE)" "$(is_code 401)"

open_stream a "$TOKEN"
open_stream b "$TOKEN2"
for name in a b; do
  wait_line "$name" 0 '^id: [0-9]+$' 5
  check "поток $name через шлюз: первый кадр — id без data ($(sed -n '1s/^[0-9]* //p' "$TMP/$name.log"))" \
    "$([ -n "$STAMP" ] && [ "$(sed -n '2s/^[0-9]* *//p' "$TMP/$name.log")" = '' ] && echo 1 || echo 0)"
done
check "поток a: код 200" "$(grep -q '^HTTP[^ ]* 200' "$TMP/a.hdr" && echo 1 || echo 0)"
check "поток a: тип text/event-stream" "$(grep -iq '^content-type: text/event-stream' "$TMP/a.hdr" && echo 1 || echo 0)"
check "поток a: Cache-Control no-cache" "$(grep -iq '^cache-control: no-cache' "$TMP/a.hdr" && echo 1 || echo 0)"

# X-Accel-Buffering — указание шлюзу, nginx его читает и клиенту не передаёт (proxy_hide_header по умолчанию). Заголовок
# смотрим на прямом ответе сервера, а то, что шлюз не копит кадры, показывают задержки ниже.
curl -s --max-time 2 -o /dev/null -D "$TMP/direct.hdr" -H "Authorization: Bearer $TOKEN" "$DIRECT/operator/stream"
check "прямой ответ сервера: X-Accel-Buffering: no" "$(grep -iq '^x-accel-buffering: no' "$TMP/direct.hdr" && echo 1 || echo 0)"

# --- Шаг 3. Агент даёт инцидент: incident.created приходит в оба потока сразу.
FROM_B=$(lines b)
new_incident
arrived "поток a: incident.created"
G_A=$G; ID_A=$(jq -r '.id // empty' <<<"${FRAME:-null}"); INC_A=$(jq -r '.incident.guid // empty' <<<"${FRAME:-null}")
check "  incidentGuid есть: ${G_A:-нет}" "$([ -n "$G_A" ] && echo 1 || echo 0)"
[ -n "$G_A" ] || finish
check "  сводка инцидента в сообщении того же инцидента" "$([ "$INC_A" = "$G_A" ] && echo 1 || echo 0)"
wait_frame b "$FROM_B" ".f.type == \"incident.created\" and .f.incidentGuid == \"$G_A\"" 5
arrived "поток b: incident.created"
check "  то же сообщение: id $ID_A" "$([ "$(jq -r '.id // empty' <<<"${FRAME:-null}")" = "$ID_A" ] && echo 1 || echo 0)"

# --- Шаг 4. Переход по HTTP: incident.transitioned в оба потока.
FROM_A=$(lines a); FROM_B=$(lines b)
move "$TOKEN" "$G_A" claim "$CLAIM"
check "claim: 200 (получено $CODE)" "$(is_code 200)"
seen_by a "$FROM_A" "$G_A" "$FIRST_ID" "поток a: incident.transitioned"
seen_by b "$FROM_B" "$G_A" "$FIRST_ID" "поток b: incident.transitioned"

# --- Шаг 5. Пинг: пустой комментарий каждые 15 с, через шлюз.
FROM_A=$(lines a); FROM_B=$(lines b)
T0=$(now)
wait_line a "$FROM_A" '^:' "$PING_SEC"
if [ -n "$STAMP" ]; then echo "     поток a: пинг через $(( (STAMP - T0) / 1000000 )) с"; fi
check "поток a: пинг за $PING_SEC с" "$([ -n "$STAMP" ] && echo 1 || echo 0)"
wait_line b "$FROM_B" '^:' "$PING_SEC"
check "поток b: пинг за $PING_SEC с" "$([ -n "$STAMP" ] && echo 1 || echo 0)"

# --- Шаг 6. Обрыв и повтор: поток b закрыт, пока его нет, инцидент закрывается; вернувшись с Last-Event-ID, он получает
# ровно то, что за это время увидел поток a, в том же порядке.
BASE=$(last_id b)
close_stream b
FROM_A=$(lines a)
move "$TOKEN" "$G_A" close "$CLOSE"
check "close при закрытом потоке b: 200 (получено $CODE)" "$(is_code 200)"
wait_frame a "$FROM_A" ".f.type == \"incident.transitioned\" and .f.incidentGuid == \"$G_A\"" 5
arrived "поток a: close"
sleep 0.5  # за переходом могут идти другие сообщения той же фиксации
END=$(last_id a)
open_stream c "$TOKEN2" "$BASE"
wait_line c 0 "^id: $END\$" 5
check "Last-Event-ID $BASE: дошло до $END" "$([ -n "$STAMP" ] && echo 1 || echo 0)"
frames a | jq -r --argjson base "$BASE" 'select((.f.id | tonumber) > $base) | "\(.f.id) \(.f.type)"' > "$TMP/want"
frames c | jq -r '"\(.f.id) \(.f.type)"' > "$TMP/got"
check "  пропущенное пришло целиком и по порядку: $(wc -l < "$TMP/got") из $(wc -l < "$TMP/want") ($(tr '\n' ';' < "$TMP/got"))" \
  "$([ -s "$TMP/want" ] && cmp -s "$TMP/want" "$TMP/got" && echo 1 || echo 0)"
check "  stream.reset нет" "$(grep -q 'stream.reset' "$TMP/got" && echo 0 || echo 1)"
close_stream c

# --- Шаг 7. Сброс: выдуманный Last-Event-ID — первым идёт stream.reset с id конца ленты.
for fake in 999999999999 not-a-number; do
  open_stream d "$TOKEN2" "$fake"
  wait_frame d 0 'true' 5
  check "Last-Event-ID $fake: первое сообщение stream.reset (получено $(jq -r '.type // "нет"' <<<"${FRAME:-null}"))" \
    "$([ "$(jq -r '.type // empty' <<<"${FRAME:-null}")" = stream.reset ] && echo 1 || echo 0)"
  check "  id сброса — конец ленты $END (получено $(jq -r '.id // "нет"' <<<"${FRAME:-null}"))" \
    "$([ "$(jq -r '.id // empty' <<<"${FRAME:-null}")" = "$END" ] && echo 1 || echo 0)"
  close_stream d
done

check "кадры потока a целые: id совпадает, строк event: нет" "$(yes_no frames_are_whole a)"

# --- Шаг 8. Разные пользователи. Нет файла, вход не прошёл, нет права или правила — SKIP с причиной.
second_login
if [ -n "$SECOND" ]; then
  two_people
elif [ -n "$SECOND_BAD" ]; then
  check "разные пользователи: $SECOND_BAD" 0
else
  skip "разные пользователи: $SECOND_WHY; через шлюз проверены две сессии одного $EMAIL"
fi

finish
