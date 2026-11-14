#!/bin/bash
# Отчёты в Telegram в :00, :15, :30, :45 из status.txt рядом — только пока идёт работа.
# Работа идёт, если status.txt менялся за последние 20 мин. Работа встала — ничего не шлётся; снова пошла —
# «Skynet работу возобновил.». Файл done рядом — итоговое сообщение и выход.
#   PLAN="План 86" nohup bash tg-loop.sh >tg.log 2>&1 &
S=$(dirname "$(readlink -f "$0")"); N=~/Work/stand/notify.sh; P=${PLAN:-План}
tail_(){ echo "<b>Чистое время проекта генерации ИИ: $(bash ~/Work/stand/active-time.sh)</b>
<b>Расход ИИ: $(bash ~/Work/stand/ai-cost.sh)</b>"; }
active(){ [ -f $S/status.txt ] && [ $(( $(date +%s) - $(stat -c %Y $S/status.txt) )) -lt 1200 ]; }
was=0
while [ ! -f $S/done ]; do
  if active; then
    if [ $was = 0 ]; then $N "Skynet работу возобновил. $P: $(cat $S/status.txt)
$(tail_)" html; was=1; fi
  else
    was=0
  fi
  sleep 50; m=$(date +%M)
  if [[ $m == 00 || $m == 15 || $m == 30 || $m == 45 ]] && active; then $N "$P: $(cat $S/status.txt)
$(tail_)" html; sleep 60; fi
done
$N "Работа завершена, больше задач нет." html
