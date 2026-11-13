#!/usr/bin/env bash
# Откат imdb к копии перед замером (план 84): остановить эмулятор агента, закрыть соединения imdb, drop/create, залить копию, analyze.
# Postgres 9.6: drop … with (force) нет, поэтому pg_terminate_backend и сразу drop, с повтором. ac_db не перезапускать.
#   restore_imdb.sh [копия=~/Work/stand/backup/imdb-before-load-2026-11-13.sql]
set -euo pipefail
DUMP=${1:-$HOME/Work/stand/backup/imdb-before-load-2026-11-13.sql}
C=$(docker ps --format '{{.Names}}' | grep '^ac_db')
pkill -f '[b]in/agent-emulator run' || true
for i in 1 2 3 4 5 6 7 8 9 10; do
  if docker exec $C psql -U postgres postgres -v ON_ERROR_STOP=1 -qc "select pg_terminate_backend(pid) from pg_stat_activity where datname='imdb' and pid<>pg_backend_pid()" -c "drop database imdb" >/dev/null 2>&1; then break; fi
  [ $i = 10 ] && { echo "imdb не удалось удалить" >&2; exit 1; }; sleep 0.3
done
docker exec $C psql -U postgres postgres -qc "create database imdb owner im"
docker exec -i $C psql -U im -q imdb < "$DUMP" >/dev/null
docker exec $C psql -U postgres imdb -qc "create extension if not exists pg_stat_statements" -c "grant execute on function pg_stat_statements_reset() to im" -c "analyze"
docker exec $C psql -U im imdb -Atc "select 'инцидентов: '||count(*) from incidents"
