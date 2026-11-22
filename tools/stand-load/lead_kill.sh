#!/bin/bash
# План 99, задача 7б, шаг 5: во время нагрузки остановить лидера такта, потом ещё одного.
#   lead_kill.sh <каталог прогона> <через сколько секунд первый> <через сколько секунд после первого второй> [первый порт=5001]
# Лидер — по логам: у процесса, чей последний «scheduler: this instance leads the tick» позже всех (и нет более позднего
# «does not lead»), файл ~/Work/stand/im-server-<порт>.log; порт → unit im-stand-server-<порт-первый>. Замок в pg_locks виден,
# но client_port базы — после NAT докера, с процессом не сопоставляется. Первый — SIGKILL (процесс пропал без Resign), второй —
# systemctl stop. События — events.log, epoch-секунды.
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
P1=$(leader_port); U1=im-stand-server-$((P1-FIRST)); echo "$(date +%s.%N) лидер 1: $U1 порт $P1 pid $(systemctl --user show -p MainPID --value $U1); SIGKILL" >> $EV
systemctl --user kill --signal=SIGKILL $U1
sleep $T2
P2=$(leader_port); echo "$(date +%s.%N) лидер 2 по логам: порт $P2 (лидерство 1 было на $P1)" >> $EV
U2=im-stand-server-$((P2-FIRST)); echo "$(date +%s.%N) останавливаю $U2 (systemctl stop)" >> $EV
systemctl --user stop $U2
echo "$(date +%s.%N) готово" >> $EV
