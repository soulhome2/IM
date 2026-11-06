#!/usr/bin/env bash
# Облако после перезагрузки машины. Стек ac сам целиком не поднимается:
#  - ac_db и ac_monitoring-db остаются 0/1 (политика перезапуска «при сбое»);
#  - ac_arpserver теряет имя в сети, из-за этого ac_nginx и ac_haproxy падают по кругу.
# Данные в томах сохраняются. Модули после этого поднимаются своими скриптами (например modules/im/up.sh --restart).
source "$(dirname "$0")/lib.sh"
for s in ac_db ac_monitoring-db ac_arpserver; do
  say "перезапуск $s"; D docker service update --force --detach=false --quiet "$s" || true
done
say "Ждём облако"; wait_http "$CLOUD/" 180 && echo "облако отвечает" || echo "облако ещё не ответило — docker service ls"
