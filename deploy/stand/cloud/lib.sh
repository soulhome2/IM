# Общее для скриптов стенда (облако и модули). Подключается через source.
set -euo pipefail
CLOUD_KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$CLOUD_KIT/cloud.env" ] || { echo "Нет $CLOUD_KIT/cloud.env — скопируйте cloud.env.example в cloud.env и поправьте пути" >&2; exit 1; }
# shellcheck disable=SC1091
source "$CLOUD_KIT/cloud.env"
CLOUD="https://axxonnet.test"
CA="$CLOUD_DIR/tools/util/rootCA.axxonnet.test.pem"
GATEWAY_D="$STAND_DIR/gateway.d"          # куски nginx от модулей
mkdir -p "$STAND_DIR/bin" "$STAND_DIR/backup" "$GATEWAY_D"

say()  { printf '\n== %s\n' "$*"; }
die()  { echo "ОШИБКА: $*" >&2; exit 1; }

# Загрузить env модуля: load_module_env <каталог модуля> <имя>
load_module_env() {
  [ -f "$1/$2.env" ] || die "Нет $1/$2.env — скопируйте $2.env.example в $2.env и поправьте пути"
  # shellcheck disable=SC1090
  source "$1/$2.env"
}

# docker: напрямую, а если группа docker ещё не применилась к сессии — через sg.
D() { if docker info >/dev/null 2>&1; then "$@"; else sg docker -c "$(printf '%q ' "$@")"; fi; }
go_env() { if [ -n "${GO_ENV_FILE:-}" ] && [ -f "$GO_ENV_FILE" ]; then source "$GO_ENV_FILE"; fi; }

db_container() { D docker ps -q -f name=ac_db | head -1; }
psql_root()    { D docker exec -i "$(db_container)" psql -U postgres postgres -v ON_ERROR_STOP=1 -At -q "$@"; }

check_pass_file() {
  [ -f "$TEST_PASS_FILE" ] || die "нет файла с паролем $TEST_PASS_FILE: printf '%s' 'пароль' > $TEST_PASS_FILE; chmod 600 $TEST_PASS_FILE"
  [ "$(stat -c '%a' "$TEST_PASS_FILE")" = 600 ] || die "права $TEST_PASS_FILE должны быть 600"
}

# Токен облака для TEST_EMAIL → $TOKEN
login() {
  check_pass_file
  TOKEN=$(jq -n --arg e "$TEST_EMAIL" --rawfile p "$TEST_PASS_FILE" '{email:$e,password:($p|rtrimstr("\n"))}' \
    | curl -s --max-time 20 --cacert "$CA" -H 'Content-Type: application/json' -d @- "$CLOUD/api/v3/ac-backend/users/login" \
    | jq -r '.accessToken // empty')
  [ -n "$TOKEN" ] || die "вход $TEST_EMAIL не дал токен"
}

wait_http() { # url [секунд]
  local n=${2:-180}
  for _ in $(seq "$n"); do
    [ "$(curl -sk -o /dev/null -w '%{http_code}' --max-time 3 "$1" || true)" = 200 ] && return 0
    sleep 1
  done
  return 1
}

# Фоновый процесс со своим pid-файлом: bg_stop <имя>; запуск — nohup … & echo $! > "$STAND_DIR/<имя>.pid"
bg_stop() {
  local p="$STAND_DIR/$1.pid"
  if [ -f "$p" ] && kill -0 "$(cat "$p")" 2>/dev/null; then kill "$(cat "$p")"; sleep 2; echo "$1 остановлен"; fi
  rm -f "$p"
}
