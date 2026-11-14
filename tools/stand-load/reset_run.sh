#!/bin/bash
# Замер сброса МИ (план 86): откат imdb, наполнение до FILL (1m | 5m), сервер, сброс через прокси под событиями
# и двумя операторами; снимки pg_locks раз в 10 с, WAL до и после, место на диске.
#   IMBIN=im-85e reset_run.sh <метка> <1m|5m>
set -u
TAG=$1; FILL=$2; L=~/Work/stand/load; O=$L/out/$TAG; mkdir -p $O
C=$(docker ps --format '{{.Names}}' | grep '^ac_db')
q(){ docker exec $C psql -U postgres imdb -Atc "$1"; }
st(){ echo "$1" > $L/status.txt; echo "$(date +%T) $1" >> $O/log.txt; }
free_gb(){ df -BG / | awk 'NR==2{print $4+0}'; }
cd ~/Work/stand
for p in $(pgrep -f 'stand/bin/im-8'); do kill $p; done; sleep 2
st "План 86, сброс $FILL: откат imdb"
bash $L/restore_imdb.sh >> $O/log.txt 2>&1
st "План 86, сброс $FILL: наполнение"
docker exec -i $C psql -U im -d imdb -q < $L/bulk-fill.sql >> $O/log.txt 2>&1
if [ $FILL = 5m ]; then
  for n in 1 2 3 4 5; do
    [ $(free_gb) -lt 8 ] && { st "сброс $FILL: меньше 8 ГБ, стоп"; exit 1; }
    docker exec -i $C psql -U im -d imdb -q < $L/bulk-fill-x10.sql >> $O/log.txt 2>&1
    st "План 86, сброс 5m: наполнение, часть $n из 5 готова, свободно $(free_gb) ГБ"
  done
fi
q "analyze" >/dev/null
q "select (select count(*) from incidents) inc, (select count(*) from events) ev, (select count(*) from incident_journal) jr, pg_database_size('imdb')" > $O/before.txt
echo "free_gb $(free_gb)" >> $O/before.txt
[ $(q "select count(*) from incidents") -lt 900000 ] && { st "сброс $FILL: наполнение не удалось, стоп"; exit 1; }
(nohup flock lock-server ./run-im-binary.sh /home/slava/Work/stand/bin/${IMBIN:-im-85e} >$O/server.log 2>&1 &)
sleep 10
(nohup ./run-agent.sh >/dev/null 2>&1 &)
sleep 15
cd $L
# операторы и поток событий того же заказчика
RELOAD=stream nohup python3 -I load_ops.py 2 5 120 $TAG-ops > $O/ops.out 2>&1 &
nohup python3 -I burst.py 7200 7200 2 $TAG-burst $O > $O/burst.out 2>&1 &
BP=$!
sleep 60
# снимки блокировок, процессов и диска
( while [ ! -f $O/.reset-done ]; do
    echo "{\"t\": $(date +%s), \"free_gb\": $(free_gb), \"locks\": $(q "select replace(coalesce(json_agg(x)::text,'[]'),E'\n',' ') from (select l.locktype, l.mode, l.granted, c.relname, a.pid, left(a.query,80) q, now()-a.query_start dur from pg_locks l left join pg_class c on c.oid=l.relation join pg_stat_activity a on a.pid=l.pid where a.datname='imdb' and a.pid<>pg_backend_pid() and (not l.granted or l.locktype='relation' and l.mode like '%Exclusive%')) x"), \"waiting\": $(q "select count(*) from pg_stat_activity where datname='imdb' and wait_event is not null and state='active'")}" >> $O/locks.jsonl
    [ $(free_gb) -lt 8 ] && { echo "мало места" >> $O/log.txt; q "select pg_cancel_backend(pid) from pg_stat_activity where query like 'DELETE FROM%'"; }
    sleep 10; done ) &
W0=$(q "select pg_current_xlog_location()")
st "План 86, сброс $FILL: идёт сброс (с $(date +%H:%M))"
python3 -I reset_probe.py $O >> $O/log.txt 2>&1
W1=$(q "select pg_current_xlog_location()")
touch $O/.reset-done
q "select pg_xlog_location_diff('$W1','$W0')" > $O/wal.txt
echo "$W0 $W1" >> $O/wal.txt
sleep 120   # что после сброса: события и операторы
kill $BP 2>/dev/null; touch $L/out/$TAG-ops/.stop
sleep 30
q "select (select count(*) from incidents) inc, (select count(*) from events) ev, (select count(*) from sources) src, pg_database_size('imdb')" > $O/after.txt
echo "free_gb $(free_gb)" >> $O/after.txt
st "План 86, сброс $FILL: готово, разбор"
echo done >> $O/log.txt
