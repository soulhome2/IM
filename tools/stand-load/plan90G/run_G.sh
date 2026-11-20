#!/bin/bash
# План 90, часть Г: 100 операторов + поток событий как ступень 100 плана 86 (run_steps86.sh: один процесс load_ops.py
# со своим потоком событий и гонками, RELOAD=stream, 5 с, лавина Д burst 10000 60 8 на 10-й минуте), STEPMIN минут.
# SUP=k — ещё k «старших» гоняют «За период» 30 дней холодными запросами с паузой SUPPAUSE с (stats_probe.py loop).
# Всегда: «Сейчас» от test@ раз в 3 с (now.jsonl). Раз в минуту — res.jsonl как в run_steps86.sh.
# База и сервер готовятся снаружи (откат, перезапуск im-stand-server, эмулятор агента).
#   SUP=3 SUPPAUSE=7 STEPMIN=20 run_G.sh <метка>
# SRV — имя процесса сервера (по умолчанию im-90-B), STLABEL — начало строки status.txt.
set -u
TAG=$1; L=~/Work/stand/load; S=$(dirname "$(readlink -f "$0")"); STEPMIN=${STEPMIN:-20}; SUP=${SUP:-0}; SUPPAUSE=${SUPPAUSE:-7}
O=$L/out/$TAG; mkdir -p $O
C=$(docker ps --format '{{.Names}}' | grep '^ac_db')
q(){ docker exec $C psql -U postgres imdb -Atc "$1"; }
free_gb(){ df -BG / | awk 'NR==2{print $4+0}'; }
cpu(){ local s=0; for p in "$@"; do [ -r /proc/$p/stat ] && s=$((s + $(awk '{print $14+$15}' /proc/$p/stat))); done; echo $s; }
cd $L
SP=$(pgrep -x "${SRV:-im-90-B}" | head -1)
OPBASE=0 NOEMIT=0 RELOAD=stream nohup python3 -I load_ops.py 100 5 $STEPMIN $TAG-p0 > $O/p0.out 2>&1 &
OPP=$!
SPIDS=()
for ((j=0; j<SUP; j++)); do
  sleep 2; nohup python3 -I $S/stats_probe.py loop $O/sup$j.jsonl 30d $SUPPAUSE $((STEPMIN*60)) > $O/sup$j.out 2>&1 &
  SPIDS+=($!)
done
( end=$(( $(date +%s) + STEPMIN*60 )); while [ $(date +%s) -lt $end ]; do
    python3 -I - "$S" >> $O/now.jsonl 2>/dev/null <<'PY'
import sys, json, time; sys.path.insert(0, sys.argv[1]); import stats_probe as p
a = p.get("/operator/supervisor/now", timeout=60)
print(json.dumps({"t": time.time(), "ms": a["ms"], "code": a["code"], "bytes": a["bytes"]}))
PY
    sleep 3; done ) &
NP=$!
echo "$(date +%T) старт $TAG: операторы $OPP, старшие ${SPIDS[*]:-нет}, сервер $SP" >> $O/log.txt
T0=$(date +%s); HZ=$(getconf CLK_TCK)
ps0=$(cpu $SP); t0=$T0; burst_done=0
while [ $(( $(date +%s) - T0 )) -lt $((STEPMIN*60)) ]; do
  sleep 60
  now=$(date +%s); ps1=$(cpu $SP); dt=$((now-t0))
  rss=$(awk '/VmRSS/{print $2}' /proc/$SP/status 2>/dev/null)
  dbcpu=$(docker stats --no-stream --format '{{.CPUPerc}}' $C)
  conns=$(q "select count(*) from pg_stat_activity where datname='imdb'")
  live=$(q "select count(*) from incidents where state<>'closed' and deleted_at is null")
  echo "{\"t\": $now, \"srv_cpu\": $(( (ps1-ps0)*100/HZ/dt )), \"db_cpu\": \"$dbcpu\", \"srv_rss_mb\": $(( ${rss:-0}/1024 )), \"conns\": $conns, \"live\": $live, \"free_gb\": $(free_gb), \"load1\": $(cut -d' ' -f1 /proc/loadavg)}" >> $O/res.jsonl
  ps0=$ps1; t0=$now
  echo "${STLABEL:-План 90, часть Г}: $TAG, $(( (now-T0)/60 )) мин из $STEPMIN; живых $live" > $L/status.txt
  if [ $burst_done = 0 ] && [ $((now-T0)) -ge 600 ]; then
    echo "$(date +%T) лавина Д" >> $O/log.txt
    python3 -I burst.py 10000 60 8 $TAG-D $O > $O/burst.txt 2>&1; burst_done=1
    echo "$(date +%T) лавина Д: $(tail -1 $O/burst.txt)" >> $O/log.txt
    ps0=$(cpu $SP); t0=$(date +%s)
  fi
done
touch $L/out/$TAG-p0/.stop
wait $OPP ${SPIDS[@]} $NP 2>/dev/null
echo "$(date +%T) конец $TAG" >> $O/log.txt
