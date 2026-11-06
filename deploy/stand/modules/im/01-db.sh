#!/usr/bin/env bash
# МИ, шаг 1. Роль и база МИ в контейнере ac_db. Таблицы сервер МИ создаёт сам при старте (миграции).
MOD="$(cd "$(dirname "$0")" && pwd)"
source "$MOD/../../cloud/lib.sh"
load_module_env "$MOD" im
[ -n "$(db_container)" ] || die "ac_db не запущен"
if [ "$(echo "select count(*) from pg_roles where rolname='$IM_DB_USER'" | psql_root)" = 0 ]; then
  echo "CREATE ROLE $IM_DB_USER LOGIN PASSWORD '$IM_DB_PASS'" | psql_root; echo "роль $IM_DB_USER создана"
else echo "роль $IM_DB_USER уже есть"; fi
if [ "$(echo "select count(*) from pg_database where datname='$IM_DB_NAME'" | psql_root)" = 0 ]; then
  echo "CREATE DATABASE $IM_DB_NAME OWNER $IM_DB_USER" | psql_root; echo "база $IM_DB_NAME создана"
else echo "база $IM_DB_NAME уже есть"; fi
