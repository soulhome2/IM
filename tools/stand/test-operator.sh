# Вход test@ на стенде, общий для скриптов стенда. Подключается через source, затем operator_login.
# Ждёт: CA, CLOUD. Итог: $TOKEN (токен облака) или пустой $TOKEN и $OPERATOR_WHY (причина).
# Пароль только в файле TEST_PASS_FILE; в команду он идёт через stdin (jq --rawfile), в переменные и вывод не попадает.
TEST_EMAIL="${TEST_EMAIL:-test@axxonnet.test}"
TEST_PASS_FILE="${TEST_PASS_FILE:-${STAND_DIR:-$HOME/Work/stand}/test-operator.pass}"

operator_login() {
  local mode reply code
  TOKEN=''; OPERATOR_WHY=''
  if [ ! -f "$TEST_PASS_FILE" ]; then OPERATOR_WHY="нет файла $TEST_PASS_FILE"; return 1; fi
  mode=$(stat -c '%a' "$TEST_PASS_FILE")
  if [ "$mode" != 600 ]; then OPERATOR_WHY="права файла $TEST_PASS_FILE — $mode, нужны 600"; return 1; fi
  reply=$(jq -n --arg email "$TEST_EMAIL" --rawfile pass "$TEST_PASS_FILE" '{email: $email, password: ($pass | rtrimstr("\n"))}' \
    | curl -s --max-time 20 --cacert "$CA" -H 'Content-Type: application/json' -d @- -w '\n%{http_code}' "$CLOUD/api/v3/ac-backend/users/login")
  code=${reply##*$'\n'}
  TOKEN=$(jq -r '.accessToken // empty' <<<"${reply%$'\n'*}" 2>/dev/null)
  if [ -z "$TOKEN" ]; then OPERATOR_WHY="вход $TEST_EMAIL не дал токен (код $code)"; return 1; fi
}
