#!/bin/bash
# План 99, этап 2, шаг 5: во время нагрузки остановить лидера такта штатно (systemctl stop), потом ещё один узел — нового лидера — SIGKILL.
#   lead_kill2.sh <каталог прогона> <через сколько секунд первый> <через сколько секунд после первого второй> [первый порт=5001]
# Лидер — как в lead_kill.sh (по логам). События — events.log, epoch-секунды.
D=$1; T1=$2; T2=$3; FIRST=${4:-5001}; EV=$D/events.log; S=~/Work/stand
leader_port() {
  local best="" bp="" p t l
  for p in $(seq $FIRST $((FIRST+9))); do
    [ -f $S/im-server-$p.log ] || continue
    l=$(grep -E 'this instance (leads|does not lead) the tick' $S/im-server-$p.log | tail -1)
    [ -z "$l" ] && continue
    echo "$l" | grep -q "does not lead" && continue
    t=$(echo "$l" | grep -o '"time":"[^"]*"' | cut -d'"' -f4)
    [[ "$t" > "$best" ]] && { best=$t; bp=$p; }
  done
  [ -n "$bp" ] && echo $bp
}
sleep $T1
P1=$(leader_port); U1=im-stand-server-$((P1-FIRST)); echo "$(date +%s.%N) лидер 1: $U1 порт $P1; systemctl stop (штатно)" >> $EV
systemctl --user stop $U1
echo "$(date +%s.%N) $U1 остановлен" >> $EV
sleep $T2
P2=$(leader_port); U2=im-stand-server-$((P2-FIRST)); echo "$(date +%s.%N) лидер 2 по логам: порт $P2 (лидерство 1 было на $P1); SIGKILL $U2" >> $EV
systemctl --user kill --signal=SIGKILL $U2
echo "$(date +%s.%N) готово" >> $EV
