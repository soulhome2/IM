#!/usr/bin/env bash
# Проверка облака: портал отвечает, пользователь стенда входит. Код выхода — число FAIL.
source "$(dirname "$0")/lib.sh"
set +e; fail=0
ok()  { echo "OK   $*"; }
bad() { echo "FAIL $*"; fail=$((fail+1)); }
[ "$(curl -sk -o /dev/null -w '%{http_code}' --max-time 10 "$CLOUD/")" = 200 ] && ok "облако $CLOUD/" || bad "облако $CLOUD/ не 200 (после перезагрузки — after-reboot.sh)"
( login ) >/dev/null 2>&1 && ok "вход $TEST_EMAIL" || bad "вход $TEST_EMAIL (03-users.sh)"
[ "$(D docker service ls --format '{{.Replicas}}' | grep -c '^0/[1-9]')" -eq 0 ] && ok "сервисы стека ac" || bad "есть остановленные сервисы: docker service ls"
echo "итого FAIL: $fail"; exit $fail
