#!/usr/bin/env bash
# Модуль «Менеджер инцидентов» поверх уже поднятого облака (сначала cloud/up.sh).
#   up.sh            — база, маршруты в шлюзе, сервер, интерфейс, права, проверка
#   up.sh --demo     — плюс демо-данные (05-demo.sh)
#   up.sh --restart  — только перезапустить сервер (без сборки) и Vite, например после перезагрузки
set -euo pipefail
MOD="$(cd "$(dirname "$0")" && pwd)"
source "$MOD/../../cloud/lib.sh"
load_module_env "$MOD" im
DEMO=0; RESTART=0
for a in "$@"; do case $a in --demo) DEMO=1;; --restart) RESTART=1;; esac; done

"$CLOUD_KIT/check.sh" >/dev/null || die "облако не готово — сначала cloud/up.sh (или cloud/after-reboot.sh) и cloud/check.sh"

if [ $RESTART = 1 ]; then
  "$MOD/02-server.sh" --no-build
  "$MOD/03-web.sh"
else
  for d in "$IM_SERVER_DIR" "$IM_WEB_DIR"; do [ -d "$d/.git" ] || die "нет клона $d"; done
  "$MOD/01-db.sh"
  say "Маршруты МИ в шлюзе облака"
  sed -e "s/@HOST@:5000/@HOST@:$IM_SERVER_PORT/; s/@HOST@:5173/@HOST@:$IM_VITE_PORT/; s/localhost:5173/localhost:$IM_VITE_PORT/" \
    "$MOD/nginx.conf" > "$GATEWAY_D/im.conf"
  "$CLOUD_KIT/04-gateway.sh"
  "$MOD/02-server.sh"
  "$MOD/03-web.sh"
  "$MOD/04-permissions.sh"
  [ $DEMO = 1 ] && "$MOD/05-demo.sh"
fi
"$MOD/check.sh" || true
cat <<TXT

Менеджер инцидентов:
  настройки (под шапкой облака)  https://axxonnet.test/dev-login.html?to=/incident-manager/
  настройки (напрямую)           https://axxonnet.test/dev-login.html?to=/im/
  место оператора                https://axxonnet.test/dev-login.html?to=/im/operator/
TXT
