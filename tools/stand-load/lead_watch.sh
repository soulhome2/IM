#!/bin/bash
# План 99, задача 7б: раз в секунду — кто держит замок лидера (pg_locks advisory → pid базы → порт клиента → процесс сервера),
# метка планировщика (scheduler_marks.tick_ms, возраст в мс) и число соединений imdb. Строка json в файл.
#   lead_watch.sh <файл> <секунд>
OUT=$1; SECS=${2:-600}; C=$(docker ps --format '{{.Names}}' | grep '^ac_db'); end=$(( $(date +%s) + SECS ))
while [ $(date +%s) -lt $end ]; do
  row=$(docker exec $C psql -U postgres imdb -Atc "select coalesce((select a.client_port::text from pg_locks l join pg_stat_activity a on a.pid=l.pid where l.locktype='advisory' and l.granted and a.datname='imdb' limit 1),'-'), coalesce((select (extract(epoch from now())*1000)::bigint - tick_ms from scheduler_marks order by tick_ms desc limit 1),-1), (select count(*) from pg_stat_activity where datname='imdb'), (select count(*) from pg_locks where locktype='advisory' and granted)" 2>/dev/null)
  IFS='|' read -r port age conns nlocks <<<"$row"
  srv='-'; if [ "$port" != "-" ]; then srv=$(ss -tnp 2>/dev/null | awk -v p=":$port" '$4 ~ p"$" || $5 ~ p"$"' | grep -o 'pid=[0-9]*' | head -1 | cut -d= -f2); fi
  echo "{\"t\": $(date +%s.%N | cut -c1-14), \"client_port\": \"$port\", \"server_pid\": \"${srv:--}\", \"tick_age_ms\": ${age:--1}, \"conns\": ${conns:-0}, \"adv_locks\": ${nlocks:-0}}" >> $OUT
  sleep 0.8
done
