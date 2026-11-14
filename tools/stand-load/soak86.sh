#!/bin/bash
# План 86, задача 3: 6 часов волнами на OPS операторах. Цикл 35 мин: обычная работа, на 10-й мин лавина Г
# (burst 5000 60 8), на 20-й — лавина Д (burst 10000 60 8), дальше пауза без лавин. Сверка среза — IM_LIVE_SLICE_VERIFY=5m.
# Раз в 15 мин — soak.jsonl: окно журнала операторов (win.py), память и потоки сервера, соединения, размер базы, диск,
# живые, сверки среза из журнала сервера. В конце — verify_ops.py.
#   IMBIN=im-86 OPS=100 HOURS=6 soak86.sh <метка>
set -u
TAG=$1; L=~/Work/stand/load; O=$L/out/$TAG; BIN=${IMBIN:-im-86}; OPS=${OPS:-100}; MIN=$(( ${HOURS:-6} * 60 ))
mkdir -p $O; C=$(docker ps --format '{{.Names}}' | grep '^ac_db')
q(){ docker exec $C psql -U postgres imdb -Atc "$1"; }
free_gb(){ df -BG / | awk 'NR==2{print $4+0}'; }
say(){ echo "$(date '+%F %T') $*" >> $O/driver.txt; }
cd ~/Work/stand
for p in $(pgrep -f 'stand/bin/im-8'); do kill $p; done; sleep 2
bash $L/restore_imdb.sh >> $O/driver.txt 2>&1
LOGLINE=$(wc -l < ~/Work/stand/im-server.log)
(IM_LIVE_SLICE_VERIFY=5m nohup flock lock-server ./run-im-binary.sh /home/slava/Work/stand/bin/$BIN >/dev/null 2>&1 &)
sleep 10; (nohup ./run-agent.sh >/dev/null 2>&1 &); sleep 10
SP=$(pgrep -x $BIN | head -1); cd $L
RELOAD=stream nohup python3 -I load_ops.py $OPS 5 $((MIN + 5)) $TAG > $O/run.txt 2>&1 & LP=$!
say "старт: $OPS операторов, $MIN мин, сервер $SP, генератор $LP"
T0=$(date +%s); next=$((T0 + 900)); k=0
while [ $(( $(date +%s) - T0 )) -lt $((MIN * 60)) ]; do
  [ $(free_gb) -lt 8 ] && { say "меньше 8 ГБ — стоп"; break; }
  el=$(( ($(date +%s) - T0) / 60 )); ph=$(( el % 35 ))
  if [ $ph -eq 10 ] || [ $ph -eq 20 ]; then
    if [ $ph -eq 10 ]; then nm=G; n=5000; else nm=D; n=10000; fi
    k=$((k+1)); res=$(python3 -I burst.py $n 60 8 $TAG-$nm$k $O 2>&1 | tail -1); say "лавина $nm$k: $res"
  fi
  now=$(date +%s)
  if [ $now -ge $next ]; then
    rss=$(awk '/VmRSS/{print $2}' /proc/$SP/status 2>/dev/null); thr=$(awk '/Threads/{print $2}' /proc/$SP/status 2>/dev/null)
    ver=$(tail -n +$LOGLINE ~/Work/stand/im-server.log | grep -c '"live slice: verified"')
    tot=$(tail -n +$LOGLINE ~/Work/stand/im-server.log | grep '"live slice: verified"' | tail -1 | grep -o '"total":[0-9]*' | cut -d: -f2)
    vf=$(tail -n +$LOGLINE ~/Work/stand/im-server.log | grep -c '"live slice: verify failed"')
    w=$(python3 -I win.py $O $((now - 900)) $now 2>&1 | tr '\n' ' ' | cut -c1-600)
    echo "{\"t\": $now, \"min\": $(( (now - T0) / 60 )), \"srv_rss_mb\": $(( ${rss:-0} / 1024 )), \"srv_threads\": ${thr:-0}, \"conns\": $(q "select count(*) from pg_stat_activity where datname='imdb'"), \"db_mb\": $(( $(q "select pg_database_size('imdb')") / 1048576 )), \"free_gb\": $(free_gb), \"live\": $(q "select count(*) from incidents where state<>'closed' and deleted_at is null"), \"verified\": $ver, \"mismatch_total\": ${tot:-null}, \"verify_failed\": $vf, \"win\": $(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$w")}" >> $O/soak.jsonl
    echo "План 86, 6 часов: $(( (now - T0) / 60 )) мин из $MIN; живых $(q "select count(*) from incidents where state<>'closed' and deleted_at is null"); сервер $(( ${rss:-0} / 1024 )) МБ; сверок $ver, расхождений ${tot:-0}" > $L/status.txt
    next=$((next + 900))
  fi
  sleep 30
done
touch $O/.stop; wait $LP; sleep 5
cat $O/emit-burst.jsonl >> $O/emit.jsonl 2>/dev/null; cat $O/labels-burst.txt >> $O/labels.txt 2>/dev/null
python3 -I verify_ops.py $O > $O/verify.txt 2>&1; say "verify_ops: код $?, FAIL $(grep -c '^FAIL' $O/verify.txt)"
cd ~/Work/stand && (nohup ./run-agent.sh >/dev/null 2>&1 &)
echo "План 86, 6 часов: готово, разбор" > $L/status.txt
say "конец"
