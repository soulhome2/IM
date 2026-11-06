#!/usr/bin/env bash
# МИ, шаг 2. Сервер МИ на машине: сборка и запуск в фоне.
#   02-server.sh            — собрать и (пере)запустить
#   02-server.sh --no-build — перезапустить готовый бинарник
#   02-server.sh stop       — остановить
# При старте сервер сам применяет миграции и регистрирует права incident_manager.* в облаке.
MOD="$(cd "$(dirname "$0")" && pwd)"
source "$MOD/../../cloud/lib.sh"
load_module_env "$MOD" im
PID="$STAND_DIR/im-server.pid"; LOG="$STAND_DIR/im-server.log"; BIN="$STAND_DIR/bin/im"

stop() { bg_stop im-server; }
[ "${1:-}" = stop ] && { stop; exit 0; }

if [ "${1:-}" != --no-build ]; then
  say "Сборка сервера МИ"
  (cd "$IM_SERVER_DIR" && go_env && go build -o "$BIN" ./cmd/im)
fi
stop
say "Запуск (журнал $LOG)"
(
  export IM_DB_URL="postgresql://$IM_DB_USER:$IM_DB_PASS@127.0.0.1:5432/$IM_DB_NAME?sslmode=disable"
  export IM_SERVER_PORT IM_CLOUD_URL=axxonnet.test IM_S2S_CLOUD_URL=127.0.0.1:8000 IM_LOG_LEVEL="${IM_LOG_LEVEL:-debug}"
  export SSL_CERT_FILE="$CA"   # сертификат стенда — только для этого процесса
  nohup "$BIN" >>"$LOG" 2>&1 & echo $! > "$PID"
)
for _ in $(seq 30); do
  code=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$IM_SERVER_PORT/api/v1/im-backend/operator/session" || true)
  [ "$code" = 401 ] && { echo "сервер МИ слушает :$IM_SERVER_PORT (без токена 401 — так и должно быть)"; exit 0; }
  kill -0 "$(cat "$PID")" 2>/dev/null || { tail -20 "$LOG"; die "сервер МИ упал при старте"; }
  sleep 1
done
tail -20 "$LOG"; die "сервер МИ не ответил за 30 с"
