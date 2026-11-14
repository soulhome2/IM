#!/bin/bash
# Замер: откат imdb, перезапуск сервера (IMBIN, по умолчанию im-85e), прогон скрипта, эмулятор обратно.
#   IMBIN=im-85e measure.sh <имя прогона> <скрипт: run_20261113p.sh | run_84_45k.sh>
# замер плана 85: откат базы, перезапуск сервера, прогон, эмулятор обратно
set -u
RUNNAME=$1; SCRIPT=$2
cd ~/Work/stand
pkill -f '[b]in/im-8' ; sleep 2
bash load/restore_imdb.sh
(nohup flock lock-server ./run-im-binary.sh /home/slava/Work/stand/bin/${IMBIN:-im-85e} >/dev/null 2>&1 &)
sleep 8
cd load && RUN=$RUNNAME BIN=${IMBIN:-im-85e} RELOAD=stream bash $SCRIPT
cd ~/Work/stand && (nohup ./run-agent.sh >/dev/null 2>&1 &)
echo "measure done $RUNNAME"
