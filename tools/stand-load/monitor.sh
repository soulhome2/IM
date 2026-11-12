#!/usr/bin/env bash
# Раз в минуту — снимок стенда в <каталог>/monitor.jsonl, пока есть файл <каталог>/.running.
# Сервер МИ, CPU и память (ps), соединения к imdb (pg_stat_activity), размер incidents/events, ошибки в im-server.log,
# CPU генератора нагрузки (load_ops.py) и средняя нагрузка машины.
OUT=$1; C=$(docker ps --format '{{.Names}}' | grep '^ac_db'); LOGF=$HOME/Work/stand/im-server.log
L0=$(wc -l <"$LOGF")
while [ -f "$OUT/.running" ]; do
  SP=$(pgrep -f "^/home/slava/Work/stand/bin/${SRV:-im-cond-type}" | head -1)
  srv=$(ps -o %cpu=,rss=,etimes= -p "$SP" 2>/dev/null | awk '{print $1","$2}')
  srvcpu=$(top -b -n1 -p "$SP" 2>/dev/null | awk -v p="$SP" '$1==p{print $9}')
  gen=$(top -b -n1 | awk '/python3/{s+=$9} END{print s+0}')
  # два отдельных psql: при двух запросах в одном -c psql печатает только последний
  conns=$(docker exec $C psql -U im imdb -Atc "select count(*)||','||count(*) filter (where state='active')||','||count(*) filter (where wait_event_type='Lock') from pg_stat_activity where datname='imdb'")
  db=$(docker exec $C psql -U im imdb -Atc "select pg_total_relation_size('incidents')||','||pg_total_relation_size('events')||','||(select count(*) from incidents)||','||(select count(*) from events)")
  dbcpu=$(docker stats --no-stream --format '{{.CPUPerc}}' $C)
  L1=$(wc -l <"$LOGF"); errs=$(sed -n "$((L0+1)),${L1}p" "$LOGF" | grep -c '"level":"\(error\|fatal\|panic\)"')
  echo "{\"t\":$(date +%s),\"srv_pid\":\"$SP\",\"srv_cpu_avg_rss\":\"$srv\",\"srv_cpu_now\":\"$srvcpu\",\"gen_cpu\":\"$gen\",\"conns_all_active_lock\":\"$conns\",\"db_sizes_counts\":\"$db\",\"db_cpu\":\"$dbcpu\",\"log_err_lines\":$errs,\"loadavg\":\"$(cut -d' ' -f1-3 /proc/loadavg)\"}" >>"$OUT/monitor.jsonl"
  for i in $(seq 60); do [ -f "$OUT/.running" ] || break; sleep 1; done
done
