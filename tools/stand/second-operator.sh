# Вход второго оператора, общий для check-operator-stream.sh и check-operator-transitions.sh. Подключается через source.
# Ждёт: CA, CLOUD, TMP, TOKEN (первый оператор), SECOND_EMAIL, SECOND_PASS_FILE, SECOND_PERMS (нужные права), req, field.
#
# Итог second_login, по шагу 5 плана 56:
#   $SECOND     — токен, оператор на линии;
#   $SECOND_WHY — причина SKIP: нет файла, вход не прошёл, 403, нет права, нет правила (подтверждено),
#                 второй оператор — тот же пользователь, что и первый (одинаковый operator.guid);
#   $SECOND_BAD — причина FAIL: всё остальное. 5xx, 401, обрыв и agentState не ready после удачного PUT — это отказ
#                 стенда, а не «не проверено», он не должен уходить в SKIP.
# Пароль только в файле на стенде; в команду он идёт через stdin, в вывод не попадает. Ответ входа не печатается.
SECOND=''; SECOND_WHY=''; SECOND_BAD=''; SECOND_ID=''; SECOND_RULES=''

# second_refused <код> <что> — запрос второго оператора не дал 200. 403 — нет права, остальное — отказ.
second_refused() {
  if [ "$1" = 403 ]; then SECOND_WHY="$2 ответил 403"; else SECOND_BAD="$2 ответил $1"; fi
}

# second_reply <ответ входа, последняя строка — код> — токен в $SECOND_TOKEN. Вход не прошёл — это 4xx, остальное — отказ.
second_reply() {
  local code=${1##*$'\n'}
  SECOND_TOKEN=$(jq -r '.accessToken // empty' <<<"${1%$'\n'*}" 2>/dev/null)
  [ -n "$SECOND_TOKEN" ] && return
  case "$code" in
    4??) SECOND_WHY="вход $SECOND_EMAIL не прошёл ($code)";;
    *) SECOND_BAD="вход $SECOND_EMAIL ответил $code, токена нет";;
  esac
}

# second_on_line <токен> — выход на линию и сессия. До проверки agentState идёт PUT: начальное состояние offline (решение 76).
second_on_line() {
  local token=$1 perm state
  BODY='{"agentState":"ready"}' req PUT /operator/session/agent-state "$token"
  if [ "$CODE" != 200 ]; then second_refused "$CODE" 'PUT agent-state ready'; return; fi
  req GET /operator/session "$token"
  if [ "$CODE" != 200 ]; then second_refused "$CODE" 'GET /operator/session'; return; fi
  for perm in $SECOND_PERMS; do
    if [ "$(jq -r --arg p "$perm" 'any(.permissions[]?; . == $p)' "$TMP/body" 2>/dev/null)" != true ]; then
      SECOND_WHY="в GET /operator/session нет $perm"; return
    fi
  done
  state=$(field .agentState)
  if [ "$state" != ready ]; then SECOND_BAD="PUT agent-state ready дал 200, а agentState — ${state:-нет}"; return; fi
  SECOND_ID=$(field .operator.guid)
  req GET /operator/session "$TOKEN"
  if [ "$CODE" != 200 ]; then second_refused "$CODE" 'GET /operator/session первого'; return; fi
  if [ "$(field .operator.guid)" = "$SECOND_ID" ]; then SECOND_WHY="второй оператор — тот же пользователь"; return; fi
  SECOND=$token
}

second_login() {
  local mode reply
  if [ ! -f "$SECOND_PASS_FILE" ]; then SECOND_WHY="нет файла $SECOND_PASS_FILE"; return; fi
  mode=$(stat -c '%a' "$SECOND_PASS_FILE")
  if [ "$mode" != 600 ]; then SECOND_WHY="права файла $SECOND_PASS_FILE — $mode, нужны 600"; return; fi
  reply=$(jq -n --arg email "$SECOND_EMAIL" --rawfile pass "$SECOND_PASS_FILE" '{email: $email, password: ($pass | rtrimstr("\n"))}' \
    | curl -s --max-time 20 --cacert "$CA" -H 'Content-Type: application/json' -d @- -w '\n%{http_code}' "$CLOUD/api/v3/ac-backend/users/login")
  second_reply "$reply"
  [ -n "$SECOND_TOKEN" ] && second_on_line "$SECOND_TOKEN"
}

# second_rules <токен второго> — сколько правил доступа у групп второго: число в $SECOND_RULES, пусто — узнать не удалось.
# Группы даёт тот же разбор токена, что и серверу МИ; токен идёт через stdin. Правила читает первый оператор.
second_rules() {
  local groups
  SECOND_RULES=''
  groups=$(jq -n --arg t "$1" '{token: $t}' \
    | curl -s --max-time 20 --cacert "$CA" -H 'Content-Type: application/json' -d @- "$CLOUD/api/v1/auth/introspect-user-token?withUserGroups=true" \
    | jq -c '.accessData.authData.userGroupIds // empty' 2>/dev/null)
  [ -n "$groups" ] || return
  req GET /access-rules "$TOKEN"
  [ "$CODE" = 200 ] || return
  SECOND_RULES=$(jq -r --argjson g "$groups" '[.[]? | select(.id as $id | $g | index($id)) | .rules[]?] | length' "$TMP/body" 2>/dev/null)
}

# second_denied <код карточки не 200> <guid> — код 0: это SKIP, причина в $SECOND_WHY, код 1: отказ, причина в $SECOND_BAD.
# 404 — это SKIP только при подтверждённом отсутствии правил: при правиле он означает ошибку видимости.
second_denied() {
  local code=$1 g=$2
  if [ "$code" = 403 ]; then SECOND_WHY="$SECOND_EMAIL: GET карточки ответил 403"; return 0; fi
  if [ "$code" = 404 ]; then
    second_rules "$SECOND"
    if [ "$SECOND_RULES" = 0 ]; then SECOND_WHY="у групп $SECOND_EMAIL нет правил доступа (GET карточки 404)"; return 0; fi
    SECOND_BAD="$SECOND_EMAIL не видит инцидент $g (404), а правил у его групп: ${SECOND_RULES:-не удалось узнать}"
    return 1
  fi
  SECOND_BAD="$SECOND_EMAIL: GET карточки $g ответил $code"
  return 1
}
