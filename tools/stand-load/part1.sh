#!/usr/bin/env bash
# Часть 1 «Лавина» 2026-11-12: 50 операторов, фон — пачка раз в 10 с; разогрев 5 мин; лавины А–Г, пауза ≥ 10 мин.
# Предел: > 5 % ошибок подачи, p95 queue:* в окне лавины > 5 с, или нет нормы через 15 мин — дальше не подавать.
# Норма: p95 очереди за последние 2 мин ≤ max(1,5 × до лавины, до лавины + 100 мс).
cd "$HOME/Work/stand/load" || exit 1
RUN=burst-20261112; OUT=out/$RUN; mkdir -p $OUT; D=$OUT/driver.txt
ST=${STATUS:-/dev/null}
say(){ echo "$(date '+%F %T') $*" | tee -a $D; }
touch $OUT/.running
SRV=im-cond-type ./monitor.sh $OUT &
python3 -I sampler.py $OUT 5 im-cond-type &
python3.12 -I load_ops.py 50 10 180 $RUN > $OUT/run.txt 2>&1 & LP=$!
say "старт: 50 операторов, пачка раз в 10 с, PID генератора $LP"
sleep 300
for b in "А:500:30" "Б:1500:30" "В:3000:30" "Г:5000:60"; do
  IFS=: read -r name n sec <<<"$b"
  now=$(date +%s); base=$(python3 -I win.py $OUT $((now-180)) $now)
  say "лавина $name: $n событий за $sec с; до: $base"
  echo "Часть 1, лавина $name ($n за $sec с) подаётся" > $OUT/step.txt
  res=$(python3 -I burst.py $n $sec 8 $RUN-$name $OUT); say "подача $name: $res"
  t1=$(python3 -c "import json;print(int(json.loads('''$res''')['t1']))")
  during=$(python3 -I win.py $OUT $((t1-sec)) $((t1+60))); say "во время $name (+60 с): $during"
  echo "$name|$t1" >> $OUT/bursts.txt
  echo "Часть 1, после лавины $name — пауза" > $OUT/step.txt
  bp95=$(python3 -c "import json;print(json.loads('''$base''')['queue'][1] or 0)")
  limit=$(python3 -c "
import json;r=json.loads('''$res''');d=json.loads('''$during''')
bad=r['events']-r['codes'].get('200',0)
w=d['queue_worst_p95']
m=[]
if bad>0.05*r['events']: m.append('ошибок подачи %d из %d'%(bad,r['events']))
if d['err_share']>0.05: m.append('ошибок операторов %.1f %%'%(d['err_share']*100))
if w and w[1]>5000: m.append('p95 %s = %d мс'%(w[0],w[1]))
print('; '.join(m))")
  sleep 600
  ok=""
  for i in $(seq 0 10); do
    now=$(date +%s); aft=$(python3 -I win.py $OUT $((now-120)) $now)
    ok=$(python3 -c "import json;a=json.loads('''$aft''')['queue'][1] or 0;b=$bp95;print('ok' if a<=max(1.5*b,b+100) else '')")
    say "после $name, $((now-t1)) с: $aft ${ok:+норма}"
    [ -n "$ok" ] && break
    [ $((now-t1)) -ge 900 ] && break
    sleep 30
  done
  [ -z "$ok" ] && limit="${limit:+$limit; }нет нормы через 15 мин"
  if [ -n "$limit" ]; then say "ПРЕДЕЛ на лавине $name: $limit"; echo "$name|$limit" > $OUT/limit.txt; break; fi
done
sleep 120
touch $OUT/.stop; wait $LP; rm -f $OUT/.running; sleep 6
say "конец части 1"
