#!/bin/bash
# План 99, задача 7: 100 операторов через nginx, как run_G.sh (один load_ops.py, RELOAD=stream, шаг 5 с, лавина Д на 10-й
# минуте), но сервер — один или несколько процессов (SRVPAT — шаблон имени бинарника для pgrep -f, процессор суммируется).
# Раз в минуту res.jsonl: процессор сервера (сумма), база, соединения imdb, живые. Раз в 3 с — «Сейчас» (now.jsonl, как в run_G.sh).
# База и сервер готовятся снаружи (restore_dump.sh, run-im-cluster.sh).
#   SRVPAT=im-p99-ff6b5f1 STEPMIN=12 run_p99.sh <метка>
set -u
TAG=$1; L=~/Work/stand/load; S=$L/plan90G; STEPMIN=${STEPMIN:-12}; BURSTMIN=${BURSTMIN:-10}
O=$L/out/$TAG; mkdir -p $O
C=$(docker ps --format '{{.Names}}' | grep '^ac_db')
q(){ docker exec $C psql -U postgres imdb -Atc "$1"; }
cpu(){ local s=0; for p in "$@"; do [ -r /proc/$p/stat ] && s=$((s + $(awk '{print $14+$15}' /proc/$p/stat))); done; echo $s; }
cd $L
SPS=$(pgrep -f "^/home/slava/Work/stand/bin/${SRVPAT:?SRVPAT}" | tr '\n' ' ')
OPBASE=0 NOEMIT=0 RELOAD=stream nohup python3 -I load_ops.py 100 5 $STEPMIN $TAG-p0 > $O/p0.out 2>&1 &
OPP=$!
( end=$(( $(date +%s) + STEPMIN*60 )); while [ $(date +%s) -lt $end ]; do
    python3 -I - "$S" >> $O/now.jsonl 2>/dev/null <<'PY'
import sys, json, time; sys.path.insert(0, sys.argv[1]); import stats_probe as p
a = p.get("/operator/supervisor/now", timeout=60)
print(json.dumps({"t": time.time(), "ms": a["ms"], "code": a["code"], "bytes": a["bytes"]}))
PY
    sleep 3; done ) &
NP=$!
echo "$(date +%T) старт $TAG: операторы $OPP, серверы $SPS" >> $O/log.txt
T0=$(date +%s); HZ=$(getconf CLK_TCK)
ps0=$(cpu $SPS); t0=$T0; burst_done=0
while [ $(( $(date +%s) - T0 )) -lt $((STEPMIN*60)) ]; do
  sleep 60
  now=$(date +%s); ps1=$(cpu $SPS); dt=$((now-t0))
  rss=0; for p in $SPS; do rss=$((rss + $(awk '/VmRSS/{print $2}' /proc/$p/status 2>/dev/null || echo 0))); done
  dbcpu=$(docker stats --no-stream --format '{{.CPUPerc}}' $C)
  conns=$(q "select count(*) from pg_stat_activity")
  conns_im=$(q "select count(*) from pg_stat_activity where datname='imdb'")
  live=$(q "select count(*) from incidents where state<>'closed' and deleted_at is null")
  echo "{\"t\": $now, \"srv_cpu\": $(( (ps1-ps0)*100/HZ/dt )), \"db_cpu\": \"$dbcpu\", \"srv_rss_mb\": $(( rss/1024 )), \"conns_all\": $conns, \"conns_imdb\": $conns_im, \"live\": $live, \"load1\": $(cut -d' ' -f1 /proc/loadavg)}" >> $O/res.jsonl
  ps0=$ps1; t0=$now
  echo "План 99, задача 7б: $TAG, $(( (now-T0)/60 )) мин из $STEPMIN; живых $live; соединений $conns" > $L/status.txt
  if [ $burst_done = 0 ] && [ $((now-T0)) -ge $((BURSTMIN*60)) ]; then
    echo "$(date +%T) лавина Д" >> $O/log.txt
    python3 -I burst.py 10000 60 8 $TAG-D $O > $O/burst.txt 2>&1; burst_done=1
    echo "$(date +%T) лавина Д: $(tail -1 $O/burst.txt)" >> $O/log.txt
    ps0=$(cpu $SPS); t0=$(date +%s)
  fi
done
touch $L/out/$TAG-p0/.stop
wait $OPP $NP 2>/dev/null
echo "$(date +%T) конец $TAG" >> $O/log.txt
