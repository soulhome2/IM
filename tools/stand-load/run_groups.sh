#!/bin/bash
# План 99, замер частых правок групп: откат imdb из копии, сервер N процессов, 100 операторов (run_p99.sh, без лавины),
# правки групп каждые IV секунд (group_edits.py, IV=0 — без правок), замеры раз в 5 с (соединения, процессор), сверка в конце.
#   IV=5 run_groups.sh <метка> <N> [минут=8]
set -u
TAG=$1; N=$2; MIN=${3:-8}; IV=${IV:-0}
BIN=im-p99-0c1af44
L=~/Work/stand/load; O=$L/out/$TAG; cd ~/Work/stand
rm -rf $O $O-p0; mkdir -p $O
C=$(docker ps --format '{{.Names}}' | grep '^ac_db')
echo "План 99, замер правок групп: $TAG — откат базы" > $L/status.txt
systemctl --user stop im-stand-server im-stand-server-{0..9} 2>/dev/null; ./run-im-balancer.sh stop 2>/dev/null; pkill -f "^$HOME/Work/stand/bin/im-"; sleep 1
bash $L/plan90G/restore_dump.sh ~/Work/stand/backup/imdb-before-p99-groups-2026-11-23.dump 2>&1 | tail -1
: > im-server.log; rm -f im-server-500?.log
./run-im-cluster.sh $BIN $N 2>&1 | tail -1
docker exec $C psql -U postgres imdb -qc "select pg_stat_statements_reset()" >/dev/null
sleep 20
echo "План 99, замер правок групп: $TAG — прогон ($N процессов, правки раз в $IV с)" > $L/status.txt
# замеры раз в 5 с: соединения imdb, процессор серверов (ps) и ac_db
( end=$(( $(date +%s) + MIN*60 + 150 )); while [ $(date +%s) -lt $end ]; do
    sp=$(ps -o %cpu= -p $(pgrep -f "^/home/slava/Work/stand/bin/$BIN" | paste -sd,) | awk '{s+=$1} END{print s}')
    dp=$(ps -o %cpu= -p $(pgrep -f '^postgres' | head -400 | paste -sd,) 2>/dev/null | awk '{s+=$1} END{print s}')
    cn=$(docker exec $C psql -U postgres imdb -Atc "select count(*) from pg_stat_activity where datname='imdb'")
    echo "{\"t\": $(date +%s), \"srv_cpu\": ${sp:-0}, \"pg_cpu\": ${dp:-0}, \"conns\": $cn}" >> $O/samp.jsonl
    sleep 5; done ) &
SP=$!
if [ "$IV" != 0 ]; then
  ( sleep 60; cd $L; python3 -I group_edits.py $IV $(( (MIN-1)*60 )) $O > $O/edits.out 2>&1 ) &
fi
SRVPAT=$BIN BURSTMIN=999 STEPMIN=$MIN bash $L/run_p99.sh $TAG
wait; kill $SP 2>/dev/null
cp ~/Work/stand/im-server*.log $O/ 2>/dev/null
docker exec $C psql -U postgres imdb -Atc "select calls, round(total_time::numeric), round((total_time/calls)::numeric,2), left(query,90) from pg_stat_statements where query ilike '%source_groups%' order by total_time desc limit 6" > $O/pgss-groups.txt
docker exec $C psql -U postgres imdb -Atc "select payload->>'kind', count(*) from stream_events where type='cache.invalidated' group by 1" > $O/feed-rows.txt
P=5000; [ $N -gt 1 ] && P="5001 5002 5003 5004 5005"
python3 -I $L/nodes_check.py $P > $O/nodes.txt 2>&1
echo "$TAG готово" > $L/status.txt
