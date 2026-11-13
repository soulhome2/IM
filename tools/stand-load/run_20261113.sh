#!/usr/bin/env bash
# Прогон 2026-11-13: повтор лавин 2026-11-12 на im-82 (после планов 79/80) + час долга под операторами (Н-8).
# 50 операторов, RELOAD=throttle, пачка раз в 5 с; 5 мин разогрева; лавины А–Д с паузой 10 мин; затем 60 мин долга.
# Поминутно (minutes.jsonl): окно операторов, просроченные, строки incident_journal (всего и эскалаций), RSS/CPU.
cd "$HOME/Work/stand/load" || exit 1
RUN=load-20261113; OUT=out/$RUN; mkdir -p $OUT; D=$OUT/driver.txt; BIN=im-82
C=$(docker ps --format '{{.Names}}' | grep '^ac_db'); LOGF=$HOME/Work/stand/im-server.log
say(){ echo "$(date '+%F %T') $*" | tee -a $D; }
q(){ docker exec $C psql -U im imdb -Atc "$1"; }
touch $OUT/.running
SRV=$BIN ./monitor.sh $OUT &
python3 -I sampler.py $OUT 5 $BIN &
RELOAD=throttle python3.12 -I load_ops.py 50 5 150 $RUN > $OUT/run.txt 2>&1 & LP=$!
say "старт: 50 операторов, пачка раз в 5 с, RELOAD=throttle, PID генератора $LP, сервер $(pgrep -f ^/home/slava/Work/stand/bin/$BIN)"
L0=$(wc -l <"$LOGF")
# поминутный сборщик и условия остановки
( bad=0; T0=$(date +%s); sleep 20; RSS0=$(python3 -c "import json;print(json.loads(open('$OUT/samples.jsonl').readline())['rss_kb'])")
  while [ -f $OUT/.running ]; do
    sleep 60; now=$(date +%s)
    w=$(python3 -I win.py $OUT $((now-60)) $now)
    j=$(q "select count(*)||'|'||count(*) filter (where transition in ('auto_escalate','escalation_ceiling'))||'|'||count(*) filter (where actor='dispatcher') from incident_journal")
    L1=$(wc -l <"$LOGF"); we=$(sed -n "$((L0+1)),${L1}p" $LOGF | grep -c '"level":"\(error\|fatal\|panic\)'); ww=$(sed -n "$((L0+1)),${L1}p" $LOGF | grep -c '"level":"warn')
    s=$(tail -1 $OUT/samples.jsonl)
    echo "{\"t\":$now,\"journal\":\"$j\",\"log_err\":$we,\"log_warn\":$ww,\"win\":$w,\"sample\":$s}" >> $OUT/minutes.jsonl
    p95=$(python3 -c "import json;print(json.loads('''$w''')['queue'][1] or 0)")
    [ "$p95" -gt 5000 ] && bad=$((bad+1)) || bad=0
    w10=$(python3 -I win.py $OUT $((now-600)) $now); es=$(python3 -c "import json;print(json.loads('''$w10''')['err_share'])")
    rss=$(python3 -c "import json;print(json.loads('''$s''')['rss_kb'])"); free=$(df -k / | awk 'NR==2{print $4}')
    why=""
    [ $bad -ge 10 ] && why="p95 очереди > 5 с 10 мин подряд"
    python3 -c "import sys;sys.exit(0 if $es>0.05 else 1)" && [ $((now-T0)) -ge 600 ] && why="ошибок $es за 10 мин"
    [ "$rss" -gt $((RSS0*2)) ] && why="RSS $rss КБ — вдвое от $RSS0"
    [ "$free" -lt 5000000 ] && why="на диске меньше 5 ГБ"
    if [ -n "$why" ]; then say "ОСТАНОВКА: $why"; touch $OUT/.stop $OUT/.abort; break; fi
  done ) &
sleep 300
for b in "А:500:30" "Б:1500:30" "В:3000:30" "Г:5000:60" "Д:10000:60"; do
  [ -f $OUT/.abort ] && break
  IFS=: read -r name n sec <<<"$b"
  now=$(date +%s); base=$(python3 -I win.py $OUT $((now-180)) $now)
  say "лавина $name: $n событий за $sec с; до: $base"
  echo "лавина $name ($n за $sec с)" > $OUT/step.txt
  res=$(python3 -I burst.py $n $sec 8 $RUN-$name $OUT); say "подача $name: $res"
  t1=$(python3 -c "import json;print(int(json.loads('''$res''')['t1']))")
  sleep 60
  during=$(python3 -I win.py $OUT $((t1-sec)) $((t1+60))); say "во время $name (+60 с): $during"
  echo "$name|$t1" >> $OUT/bursts.txt
  echo "пауза после лавины $name" > $OUT/step.txt
  bp95=$(python3 -c "import json;print(json.loads('''$base''')['queue'][1] or 0)")
  limit=$(python3 -c "
import json;r=json.loads('''$res''');d=json.loads('''$during''')
bad=r['events']-r['codes'].get('200',0); w=d['queue_worst_p95']; m=[]
if bad>0.05*r['events']: m.append('ошибок подачи %d из %d'%(bad,r['events']))
if d['err_share']>0.05: m.append('ошибок операторов %.1f %%'%(d['err_share']*100))
if w and w[1]>5000: m.append('p95 %s = %d мс'%(w[0],w[1]))
print('; '.join(m))")
  sleep 540
  ok=""
  for i in $(seq 0 10); do
    now=$(date +%s); aft=$(python3 -I win.py $OUT $((now-120)) $now)
    ok=$(python3 -c "import json;a=json.loads('''$aft''')['queue'][1] or 0;b=$bp95;print('ok' if a<=max(1.5*b,b+100) else '')")
    say "после $name, $((now-t1)) с: $aft ${ok:+норма}"
    [ -n "$ok" ] && break; [ $((now-t1)) -ge 900 ] && break; sleep 30
  done
  [ -z "$ok" ] && limit="${limit:+$limit; }нет нормы через 15 мин"
  if [ -n "$limit" ]; then say "ПРЕДЕЛ на лавине $name: $limit"; echo "$name|$limit" > $OUT/limit.txt; break; fi
done
TD=$(date +%s); say "долг под операторами: 60 мин"; echo "долг под операторами (Н-8), 60 мин" > $OUT/step.txt
while [ $(( $(date +%s)-TD )) -lt 3600 ] && [ ! -f $OUT/.abort ] && kill -0 $LP 2>/dev/null; do sleep 30; done
touch $OUT/.stop; wait $LP; sleep 70; rm -f $OUT/.running; sleep 6
cat $OUT/emit-burst.jsonl >> $OUT/emit.jsonl; cat $OUT/labels-burst.txt >> $OUT/labels.txt
say "конец прогона"; echo "конец" > $OUT/step.txt
