#!/bin/bash
# План 99, 7б: тот же тихий замер на базе с ~2000 живых инцидентов (как у поста, а не 172 тыс. после нагрузок): откат, 
# остальные живые мягко «удалены» меткой 2000-01-01, сервер p99 с IM_LIVE_SLICE_VERIFY=0 и 1m.
#   quiet_small.sh <запросов на вид> <метка>
N=${1:-30000}; TAG=${2:-quiet-small}; L=~/Work/stand/load; O=$L/out/$TAG; mkdir -p $O; cd ~/Work/stand
C=$(docker ps --format '{{.Names}}' | grep '^ac_db')
run() {
  local name=$1 ver=$2
  echo "План 99, 7б: малая база, $name" > $L/status.txt
  systemctl --user stop im-stand-server 2>/dev/null; pkill -f "^$HOME/Work/stand/bin/im-"; sleep 1
  bash $L/plan90G/restore_dump.sh ~/Work/stand/backup/imdb-before-p99-stage1-2026-11-21.dump > $O/$name.restore.log 2>&1
  docker exec $C psql -U postgres imdb -Atc "update incidents set deleted_at='2000-01-01 00:00:00+00' where deleted_at is null and state<>'closed' and guid not in (select guid from incidents where deleted_at is null and state<>'closed' order by random() limit 2000)" > /dev/null
  docker exec $C psql -U postgres imdb -Atc "select count(*) from incidents where deleted_at is null and state<>'closed'" > $O/$name.live.txt
  : > im-server.log
  IM_LIVE_SLICE_VERIFY=$ver IM_LOG_LEVEL=info ./run-im-cluster.sh im-p99-ff6b5f1 1 > /dev/null
  sleep 15
  python3 -I $L/quiet_queue.py 5000 $N $name > $O/$name.json 2>$O/$name.err
  cp im-server.log $O/$name.server.log
}
run verify0 0
run verify1m 1m
echo "$TAG готово" > $L/status.txt
