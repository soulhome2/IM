#!/usr/bin/env bash
# Ступени нагрузки 2026-11-11: по 10 мин, пауза 1 мин, после каждой — stream_stats.py и verify_ops.py.
# load_ops.py — под python3.12: под python3.14.4 генератор падал SIGSEGV (/var/crash, 2026-11-11 14:45).
# Предел: >5 % ошибок (5xx, сеть) или p95 любой queue:* > 3000 мс — следующую ступень не запускать.
cd "$HOME/Work/stand/load" || exit 1
MIN=${MIN:-10}
STAGES=${STAGES:-"1:5:10 2:10:10 3:25:10 4:50:10 5:50:2"}
LOGD=out/stages-20261111; mkdir -p $LOGD
for st in $STAGES; do
  IFS=: read -r k n every <<<"$st"
  run="ops-20261111-s$k"
  out=out/$run; mkdir -p $out
  { echo "== ступень $k: $n операторов, пачка раз в $every с, $(date '+%F %T')"
    echo "до старта: loadavg $(cut -d' ' -f1-3 /proc/loadavg); CPU idle $(top -bn1 | awk '/Cpu\(s\)/{print $8}') %"; } | tee -a $LOGD/driver.txt
  touch $out/.running; ./monitor.sh $out & MON=$!
  python3.12 -I load_ops.py $n $every $MIN $run > $out/run.txt 2>&1
  rm -f $out/.running; wait $MON
  python3 -I stream_stats.py $out > $out/stream.txt 2>&1
  python3 -I verify_ops.py $out > $out/verify.txt 2>&1
  head -1 $out/run.txt | tee -a $LOGD/driver.txt; sed -n 2p $out/run.txt | tee -a $LOGD/driver.txt
  tail -1 $out/stream.txt | tee -a $LOGD/driver.txt; grep -E '^(FAIL|итого)' $out/verify.txt | tee -a $LOGD/driver.txt
  stop=$(python3 -c "
import json;s=json.load(open('$out/summary.json'))
bad=[(k,v['p95']) for k,v in s['ops'].items() if k.startswith('queue:') and v['p95']>3000]
print('предел: ошибок %.2f %%, queue p95>3с: %s'%(s['err_share']*100,bad) if s['err_share']>0.05 or bad else '')")
  if [ -n "$stop" ]; then echo "$stop — ступени дальше не запускаются" | tee -a $LOGD/driver.txt; break; fi
  sleep 60
done
echo "== конец $(date '+%F %T')" | tee -a $LOGD/driver.txt
