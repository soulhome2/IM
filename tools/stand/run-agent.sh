#!/usr/bin/env bash
# Эмулятор агента МИ на стенде: топология раз в 10 с, события раз в 1 с. Лог — $STAND_DIR/agent-emulator.log.
# Вход без ключа (X-Dev-Agent): агент 01a18217-… должен быть в базе — он приходит из файла резервной копии.
# Остановить: pkill -f '[b]in/agent-emulator run'
STAND_DIR="${STAND_DIR:-$HOME/Work/stand}"
IM_SERVER_REPO="${IM_SERVER_REPO:-$HOME/Work/incident-manager-server}"
cd "$IM_SERVER_REPO/tools/agent-emulator" || exit 1
nohup "$STAND_DIR/bin/agent-emulator" run --data testdata/agent-emulator.json \
  >> "$STAND_DIR/agent-emulator.log" 2>&1 &
echo "агент запущен, pid $!; лог: tail -f $STAND_DIR/agent-emulator.log"
