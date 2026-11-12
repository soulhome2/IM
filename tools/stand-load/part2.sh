#!/usr/bin/env bash
# Часть 2 «Долгая смена» 2026-11-12: 50 операторов, пачка раз в 5 с, 6 часов. monitor.sh раз в минуту, sampler раз в 15 с,
# раз в 30 мин — EXPLAIN (ANALYZE, BUFFERS) счётчиков и страницы очереди, размеры таблиц, ошибки и размер лога.
# Остановка раньше: ошибок > 5 % за 10 мин, p95 очереди > 5 с 10 мин подряд, RSS вдвое от начала, диска < 5 ГБ.
cd "$HOME/Work/stand/load" || exit 1
RUN=soak-20261112; OUT=out/$RUN; mkdir -p $OUT/plans; D=$OUT/driver.txt
C=$(docker ps --format '{{.Names}}' | grep '^ac_db'); LOGF=$HOME/Work/stand/im-server.log
say(){ echo "$(date '+%F %T') $*" | tee -a $D; }
snap(){ # $1 — номер среза
  for w in counters page_prio_oldest page_reaction; do
    python3 -I explain_queue.py $w | docker exec -i $C psql -U im imdb -At > $OUT/plans/$1-$w.txt 2>&1
  done
  docker exec $C psql -U im imdb -Atc "select relname||'|'||pg_total_relation_size(c.oid)||'|'||pg_relation_size(c.oid)||'|'||pg_indexes_size(c.oid) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r' order by pg_total_relation_size(c.oid) desc limit 12" > $OUT/plans/$1-sizes.txt
  L1=$(wc -l <"$LOGF")
  echo "{\"slice\":$1,\"t\":$(date +%s),\"log_bytes\":$(stat -c %s $LOGF),\"log_lines\":$L1,\"warn\":$(sed -n "$((L0+1)),${L1}p" $LOGF | grep -c '"level":"warn'),\"error\":$(sed -n "$((L0+1)),${L1}p" $LOGF | grep -c '"level":"\(error\|fatal\|panic\)'),\"disk_free_kb\":$(df -k / | awk 'NR==2{print $4}')}" >> $OUT/slices.jsonl
  sed -n "$((L0+1)),${L1}p" $LOGF | grep '"level":"\(warn\|error\|fatal\|panic\)' | cut -c1-400 >> $OUT/log-warn-error.txt
  L0=$L1
}
L0=$(wc -l <"$LOGF")
touch $OUT/.running
SRV=im-cond-type ./monitor.sh $OUT &
python3 -I sampler.py $OUT 15 im-cond-type &
python3.12 -I load_ops.py 50 5 360 $RUN > $OUT/run.txt 2>&1 & LP=$!
T0=$(date +%s); say "старт: 50 операторов, пачка раз в 5 с, 360 мин, PID генератора $LP"
snap 0
RSS0=$(python3 -c "import json;print(json.loads(open('$OUT/samples.jsonl').readline())['rss_kb'])" 2>/dev/null)
k=0; bad=0
while kill -0 $LP 2>/dev/null; do
  sleep 60; now=$(date +%s); el=$(( (now-T0)/60 ))
  w=$(python3 -I win.py $OUT $((now-60)) $now); echo "$now $w" >> $OUT/minutes.txt
  p95=$(python3 -c "import json;print(json.loads('''$w''')['queue'][1] or 0)")
  [ "$p95" -gt 5000 ] && bad=$((bad+1)) || bad=0
  w10=$(python3 -I win.py $OUT $((now-600)) $now); es=$(python3 -c "import json;print(json.loads('''$w10''')['err_share'])")
  rss=$(python3 -c "import json;print(json.loads(open('$OUT/samples.jsonl').readlines()[-1])['rss_kb'])")
  free=$(df -k / | awk 'NR==2{print $4}')
  why=""
  [ $bad -ge 10 ] && why="p95 очереди > 5 с 10 мин подряд"
  python3 -c "import sys;sys.exit(0 if $es>0.05 else 1)" && [ $el -ge 10 ] && why="ошибок $es за 10 мин"
  [ -n "$RSS0" ] && [ "$rss" -gt $((RSS0*2)) ] && why="RSS $rss КБ — вдвое от $RSS0"
  [ "$free" -lt 5000000 ] && why="на диске меньше 5 ГБ"
  if [ -n "$why" ]; then say "ОСТАНОВКА на $el мин: $why"; touch $OUT/.stop; break; fi
  if [ $((el/30)) -gt $k ]; then k=$((el/30)); snap $k; say "срез $k ($el мин): $w"; fi
done
wait $LP; rm -f $OUT/.running; sleep 16; snap end
say "конец части 2"
