#!/usr/bin/env bash
# МИ, шаг 3. Конфигуратор и место оператора (Vite) на машине, в фоне.
#   03-web.sh       — npm ci при первом запуске и (пере)запуск
#   03-web.sh stop  — остановить
# VITE_API_URL обязательно на локальное облако: иначе прокси Vite по умолчанию смотрит в боевое облако заказчика.
MOD="$(cd "$(dirname "$0")" && pwd)"
source "$MOD/../../cloud/lib.sh"
load_module_env "$MOD" im
PID="$STAND_DIR/vite.pid"; LOG="$STAND_DIR/vite.log"
stop() { bg_stop vite; }
[ "${1:-}" = stop ] && { stop; exit 0; }
cd "$IM_WEB_DIR"
[ -d node_modules ] || { say "npm ci"; npm ci; }
stop
VITE_API_URL="$CLOUD" NODE_TLS_REJECT_UNAUTHORIZED=0 nohup npx vite --host 0.0.0.0 --port "$IM_VITE_PORT" --strictPort >>"$LOG" 2>&1 &
echo $! > "$PID"
for _ in $(seq 30); do
  curl -s -o /dev/null "http://127.0.0.1:$IM_VITE_PORT/im/" && { echo "Vite слушает :$IM_VITE_PORT (журнал $LOG)"; exit 0; }
  sleep 1
done
tail -20 "$LOG"; die "Vite не ответил за 30 с"
