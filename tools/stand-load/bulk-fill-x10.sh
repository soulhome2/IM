#!/bin/bash
# Увеличение imdb стенда в 10 раз: дамп, 9 частей bulk-fill-x10.sql, ANALYZE. Журнал — в $1.
set -euo pipefail
C=$(sg docker -c "docker ps --format '{{.Names}}'" | grep '^ac_db\.')
log=${1:-/dev/stdout}
ts=$(date +%Y%m%d-%H%M)
echo "$(date +%T) дамп" >>"$log"
sg docker -c "docker exec $C pg_dump -U im imdb" | gzip -1 > ~/Work/stand/backup/imdb-before-x10-$ts.sql.gz
echo "$(date +%T) дамп готов: $(du -h ~/Work/stand/backup/imdb-before-x10-$ts.sql.gz | cut -f1)" >>"$log"
for n in 1 2 3 4 5 6 7 8 9; do
  sg docker -c "docker exec -i $C psql -U im -d imdb -q" < ~/Work/stand/load/bulk-fill-x10.sql >>"$log" 2>&1
  echo "$(date +%T) часть $n готова, свободно $(df -h / | awk 'NR==2{print $4}')" >>"$log"
done
sg docker -c "docker exec -i $C psql -U im -d imdb -tA" >>"$log" 2>&1 <<'Q'
ANALYZE events; ANALYZE incidents; ANALYZE incident_journal;
SELECT (SELECT count(*) FROM events) ev, (SELECT count(*) FROM incidents) inc, (SELECT count(*) FILTER (WHERE state <> 'closed') FROM incidents) live,
       (SELECT count(*) FROM incident_journal) jr, pg_size_pretty(pg_database_size('imdb')) size;
Q
echo "$(date +%T) готово" >>"$log"
