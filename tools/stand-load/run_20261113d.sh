#!/usr/bin/env bash
# Лавина Д 2026-11-13 на откаченной базе: 50 операторов (RELOAD=throttle, пачка раз в 5 с), 5 мин разогрева,
# burst.py 10000 60 8, затем 10 мин. Цель — приём ~170 событий/с и ожидание блокировок (incident_counters, Н-10).
cd "$HOME/Work/stand/load" || exit 1
RUN=loadD-20261113; OUT=out/$RUN; mkdir -p $OUT; D=$OUT/driver.txt; BIN=im-82
say(){ echo "$(date '+%F %T') $*" | tee -a $D; }
touch $OUT/.running
SRV=$BIN ./monitor.sh $OUT &
python3 -I sampler.py $OUT 1 $BIN &
RELOAD=throttle python3.12 -I load_ops.py 50 5 18 $RUN > $OUT/run.txt 2>&1 & LP=$!
say "старт: 50 операторов, PID $LP"
sleep 300
now=$(date +%s); say "лавина Д: до: $(python3 -I win.py $OUT $((now-180)) $now)"
res=$(python3 -I burst.py 10000 60 8 $RUN-Д $OUT); say "подача Д: $res"
t1=$(python3 -c "import json;print(int(json.loads('''$res''')['t1']))"); echo "Д|$t1" >> $OUT/bursts.txt
sleep 60; say "во время Д (+60 с): $(python3 -I win.py $OUT $((t1-60)) $((t1+60)))"
sleep 540; now=$(date +%s); say "после Д: $(python3 -I win.py $OUT $((now-120)) $now)"
touch $OUT/.stop; wait $LP; sleep 5; rm -f $OUT/.running; sleep 3
cat $OUT/emit-burst.jsonl >> $OUT/emit.jsonl; cat $OUT/labels-burst.txt >> $OUT/labels.txt
say "конец"
