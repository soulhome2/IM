#!/bin/bash
# Замер «За период» на спокойном стенде: 7d и 30d — по 20 холодных на каждый вариант фильтра; 90d — 20 без фильтра,
# по 5 на фильтр (все упираются в предел 20 с). Затем stats.csv 30 дней ×5.
S=$(dirname "$(readlink -f "$0")"); O=${1:-$S/G-stats}; mkdir -p $O; cd $S
V=(none= "duty=dutyGroup=grp-01a1aae6-cbe6-74a4-8693-8456bb7e91e1" "sgroup=sourceGroup=01a18699-b09e-744a-9ae3-ffb24483c2d9"
   "source=source=01a18217-5b18-795d-9dcd-750b78157a57" "etype=eventType=fire" "operator=operator=5" "result=result=false_alarm"
   "maint=maintenance=include")
python3 -I stats_probe.py run $O/stats.jsonl 20 7d "${V[@]}" > $O/7d.out 2>&1
python3 -I stats_probe.py run $O/stats.jsonl 20 30d "${V[@]}" > $O/30d.out 2>&1
python3 -I stats_probe.py run $O/stats.jsonl 20 90d none= > $O/90d.out 2>&1
python3 -I stats_probe.py run $O/stats.jsonl 5 90d "${V[@]:1}" >> $O/90d.out 2>&1
python3 -I stats_probe.py csv $O/csv.jsonl 5 30d > $O/csv.out 2>&1
echo done > $O/done
