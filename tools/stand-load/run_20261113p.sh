#!/usr/bin/env bash
# Замер узкого места 2026-11-13: 50 операторов RELOAD=throttle, пачка раз в 5 с; через 3 мин лавины Г и Д подряд;
# раз в 5 мин: топ pg_stat_statements за 5 мин (со сбросом), EXPLAIN счётчиков и страниц очереди, видимых оператору, просроченные.
cd "$HOME/Work/stand/load" || exit 1
RUN=loadP-20261113; OUT=out/$RUN; mkdir -p $OUT/pgss $OUT/plans; D=$OUT/driver.txt; BIN=im-82
C=$(docker ps --format '{{.Names}}' | grep '^ac_db')
say(){ echo "$(date '+%F %T') $*" | tee -a $D; }
q(){ docker exec $C psql -U im imdb -Atc "$1"; }
snap(){
  q "select round(total_time)::bigint||'|'||calls||'|'||round(mean_time::numeric,1)||'|'||rows||'|'||left(regexp_replace(query,'\s+',' ','g'),140) from pg_stat_statements order by total_time desc limit 20" > $OUT/pgss/$1.txt
  q "select pg_stat_statements_reset()" >/dev/null
  for w in counters page_prio_oldest page_reaction; do python3 -I explain_queue.py $w | docker exec -i $C psql -U im imdb -At > $OUT/plans/$1-$w.txt 2>&1; done
  vis=$(timeout 60 python3.12 -I opcheck.py 1 1 | head -1)
  ov=$(q "select count(*)||'|'||count(*) filter (where state<>'closed')||'|'||count(*) filter (where im_next_due(timers) <= (extract(epoch from now())*1000)::bigint) from incidents where deleted_at is null")
  st=$(q "select state||':'||escalation_level||'='||count(*) from incidents where deleted_at is null and state<>'closed' group by 1,escalation_level order by 1,2" | paste -sd' ')
  now=$(date +%s); say "срез $1: всего|живых|просроч. $ov; оператор: $vis; состояния: $st; окно 2 мин: $(python3 -I win.py $OUT $((now-120)) $now)"
}
touch $OUT/.running
SRV=$BIN ./monitor.sh $OUT &
python3 -I sampler.py $OUT 2 $BIN &
q "select pg_stat_statements_reset()" >/dev/null
RELOAD=throttle python3.12 -I load_ops.py 50 5 36 $RUN > $OUT/run.txt 2>&1 & LP=$!
say "старт, PID $LP"
sleep 180; snap 03
res=$(python3 -I burst.py 5000 60 8 $RUN-G $OUT); say "лавина Г: $res"
res=$(python3 -I burst.py 10000 60 8 $RUN-D $OUT); say "лавина Д: $res"
for k in 1 2 3 4 5; do sleep 240; snap s$k; done
touch $OUT/.stop; wait $LP; sleep 5; rm -f $OUT/.running; sleep 3
cat $OUT/emit-burst.jsonl >> $OUT/emit.jsonl; cat $OUT/labels-burst.txt >> $OUT/labels.txt
say "конец"
