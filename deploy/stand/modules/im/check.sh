#!/usr/bin/env bash
# Проверка стенда: облако, вход, сервер МИ напрямую и через шлюз, Vite. Код выхода — число FAIL.
MOD="$(cd "$(dirname "$0")" && pwd)"
source "$MOD/../../cloud/lib.sh"
load_module_env "$MOD" im
set +e
fail=0
ok()  { echo "OK   $*"; }
bad() { echo "FAIL $*"; fail=$((fail+1)); }
code() { curl -sk -o /dev/null -w '%{http_code}' --max-time 10 "$@"; }

[ "$(code "$CLOUD/")" = 200 ] && ok "облако $CLOUD/" || bad "облако $CLOUD/ не 200 (после перезагрузки — after-reboot.sh)"
( login ) >/dev/null 2>&1 && ok "вход $TEST_EMAIL" || bad "вход $TEST_EMAIL"
[ "$(code "http://127.0.0.1:$IM_SERVER_PORT/api/v1/im-backend/operator/session")" = 401 ] && ok "сервер МИ :$IM_SERVER_PORT" || bad "сервер МИ не отвечает (02-server.sh, журнал $STAND_DIR/im-server.log)"
if ( login ) >/dev/null 2>&1; then
  login
  c=$(code -H "Authorization: Bearer $TOKEN" "$CLOUD/api/v1/im-backend/operator/session")
  [ "$c" = 200 ] && ok "сервер МИ через шлюз, с токеном" || bad "через шлюз /operator/session → $c (шлюз: up.sh или cloud/04-gateway.sh; 403 — 04-permissions.sh)"
fi
c=$(code "$CLOUD/im/"); [ "$c" = 200 ] && ok "Vite через шлюз /im/" || bad "/im/ → $c (03-web.sh; 502 — Vite не запущен или фаервол)"
echo "итого FAIL: $fail"
exit $fail
