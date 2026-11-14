#!/bin/bash
# План 86, задача 2: ступени операторов. На каждую ступень — откат imdb, сервер, N операторов процессами по 100
# (поток событий и гонки — только у первого), через 10 мин лавина Д (burst 10000 60 8), всего STEPMIN минут.
# Раз в минуту — процессор и память сервера, процессор базы и генератора, соединения с базой: res.jsonl.
#   IMBIN=im-86 STEPMIN=25 run_steps86.sh <метка> 100 200 300 500
set -u
TAG=$1; shift; L=~/Work/stand/load; BIN=${IMBIN:-im-86}; STEPMIN=${STEPMIN:-25}
C=$(docker ps --format '{{.Names}}' | grep '^ac_db')
q(){ docker exec $C psql -U postgres imdb -Atc "$1"; }
free_gb(){ df -BG / | awk 'NR==2{print $4+0}'; }
cpu(){ local s=0; for p in "$@"; do [ -r /proc/$p/stat ] && s=$((s + $(awk '{print $14+$15}' /proc/$p/stat))); done; echo $s; }
for N in "$@"; do
  O=$L/out/$TAG-$N; mkdir -p $O
  echo "План 86, ступени: $N операторов — подготовка" > $L/status.txt
  [ $(free_gb) -lt 8 ] && { echo "меньше 8 ГБ — стоп" >> $O/log.txt; exit 1; }
  cd ~/Work/stand
  for p in $(pgrep -f 'stand/bin/im-8'); do kill $p; done; sleep 2
  bash $L/restore_imdb.sh >> $O/log.txt 2>&1
  (nohup flock lock-server ./run-im-binary.sh /home/slava/Work/stand/bin/$BIN >/dev/null 2>&1 &)
  sleep 10; (nohup ./run-agent.sh >/dev/null 2>&1 &); sleep 10
  cd $L
  SP=$(pgrep -x $BIN | head -1)
  PIDS=(); k=0
  for ((b=0; b<N; b+=100)); do
    n=$(( N-b < 100 ? N-b : 100 ))
    if [ $b = 0 ]; then E=0; else E=1; fi
    OPBASE=$b NOEMIT=$E RELOAD=stream nohup python3 -I load_ops.py $n 5 $STEPMIN $TAG-$N-p$k > $O/p$k.out 2>&1 &
    PIDS+=($!); k=$((k+1))
  done
  echo "$(date +%T) старт $N, процессы ${PIDS[*]}, сервер $SP" >> $O/log.txt
  T0=$(date +%s); HZ=$(getconf CLK_TCK)
  ps0=$(cpu $SP); g0=$(cpu ${PIDS[@]}); t0=$T0; burst_done=0
  while [ $(( $(date +%s) - T0 )) -lt $((STEPMIN*60)) ]; do
    sleep 60
    now=$(date +%s); ps1=$(cpu $SP); g1=$(cpu ${PIDS[@]}); dt=$((now-t0))
    rss=$(awk '/VmRSS/{print $2}' /proc/$SP/status 2>/dev/null)
    dbcpu=$(docker stats --no-stream --format '{{.CPUPerc}}' $C)
    conns=$(q "select count(*) from pg_stat_activity where datname='imdb'")
    live=$(q "select count(*) from incidents where state<>'closed' and deleted_at is null")
    echo "{\"t\": $now, \"n\": $N, \"srv_cpu\": $(( (ps1-ps0)*100/HZ/dt )), \"gen_cpu\": $(( (g1-g0)*100/HZ/dt )), \"db_cpu\": \"$dbcpu\", \"srv_rss_mb\": $(( ${rss:-0}/1024 )), \"conns\": $conns, \"live\": $live, \"free_gb\": $(free_gb), \"load1\": $(cut -d' ' -f1 /proc/loadavg)}" >> $O/res.jsonl
    ps0=$ps1; g0=$g1; t0=$now
    echo "План 86, ступени: $N операторов, $(( (now-T0)/60 )) мин из $STEPMIN; живых $live; сервер $(( ${rss:-0}/1024 )) МБ" > $L/status.txt
    if [ $burst_done = 0 ] && [ $((now-T0)) -ge 600 ]; then
      echo "$(date +%T) лавина Д" >> $O/log.txt
      python3 -I burst.py 10000 60 8 $TAG-$N-D $O > $O/burst.txt 2>&1; burst_done=1
      echo "$(date +%T) лавина Д: $(tail -1 $O/burst.txt)" >> $O/log.txt
      ps0=$(cpu $SP); g0=$(cpu ${PIDS[@]}); t0=$(date +%s)
    fi
  done
  for ((j=0; j<k; j++)); do touch $L/out/$TAG-$N-p$j/.stop; done
  wait ${PIDS[@]} 2>/dev/null
  echo "$(date +%T) конец $N" >> $O/log.txt
done
cd ~/Work/stand && (nohup ./run-agent.sh >/dev/null 2>&1 &)
echo "План 86, ступени: готово, разбор" > $L/status.txt
