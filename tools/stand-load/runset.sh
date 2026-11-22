#!/bin/bash
# План 99, задача 7б: один прогон «откат базы → сервер(ы) → 100 операторов».
#   runset.sh <метка> <бинарник> <N процессов> [STEPMIN]   (IM_LIVE_SLICE_VERIFY и др. — из окружения; EXTRA — фоновые команды)
set -u
TAG=$1; BIN=$2; N=$3; STEPMIN=${4:-12}
rm -rf ~/Work/stand/load/out/$TAG ~/Work/stand/load/out/$TAG-p0
L=~/Work/stand/load; cd ~/Work/stand
echo "План 99, задача 7б: $TAG — откат базы" > $L/status.txt
systemctl --user stop im-stand-server im-stand-server-{0..9} 2>/dev/null; pkill -f "^$HOME/Work/stand/bin/im-"; sleep 1
bash $L/plan90G/restore_dump.sh ~/Work/stand/backup/imdb-before-p99-stage1-2026-11-21.dump 2>&1 | tail -1
: > im-server.log; rm -f im-server-500?.log
IM_LOG_LEVEL=${IM_LOG_LEVEL:-info} ./run-im-cluster.sh $BIN $N
docker exec $(docker ps --format '{{.Names}}'|grep '^ac_db') psql -U postgres imdb -qc "select pg_stat_statements_reset()" >/dev/null
sleep 5
mkdir -p $L/out/$TAG
# EXTRA — свои команды рядом с нагрузкой (например lead_watch.sh и lead_kill.sh), запускаются в фоне после старта серверов
[ -n "${EXTRA:-}" ] && { eval "$EXTRA" & }
cd $L && SRVPAT=$BIN STEPMIN=$STEPMIN ./run_p99.sh $TAG
sleep 2; cp ~/Work/stand/im-server*.log $L/out/$TAG/ 2>/dev/null
echo "$TAG готово" > $L/status.txt
