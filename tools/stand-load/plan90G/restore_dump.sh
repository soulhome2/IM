#!/usr/bin/env bash
# Откат imdb из дампа pg_dump -Fc (как restore_imdb.sh, но pg_restore): эмулятор агента стоп, соединения imdb закрыть,
# drop/create, pg_restore, pg_stat_statements, analyze. Сервер останавливать снаружи.
#   restore_dump.sh <файл.dump>
set -euo pipefail
DUMP=$1
C=$(docker ps --format '{{.Names}}' | grep '^ac_db')
pkill -f '[b]in/agent-emulator run' || true
for i in 1 2 3 4 5 6 7 8 9 10; do
  if docker exec $C psql -U postgres postgres -v ON_ERROR_STOP=1 -qc "select pg_terminate_backend(pid) from pg_stat_activity where datname='imdb' and pid<>pg_backend_pid()" -c "drop database imdb" >/dev/null 2>&1; then break; fi
  [ $i = 10 ] && { echo "imdb не удалось удалить" >&2; exit 1; }; sleep 0.3
done
docker exec $C psql -U postgres postgres -qc "create database imdb owner im"
docker exec -i $C pg_restore -U postgres -d imdb --exit-on-error < "$DUMP"
# pg_trgm (миграция 081, план 93): в старом дампе его нет, а im создать не может.
docker exec $C psql -U postgres imdb -qc "create extension if not exists pg_trgm" -c "create extension if not exists pg_stat_statements" -c "grant execute on function pg_stat_statements_reset() to im" -c "analyze"
docker exec $C psql -U im imdb -Atc "select 'инцидентов: '||count(*) from incidents"
