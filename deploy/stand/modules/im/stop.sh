#!/usr/bin/env bash
# Остановить сервер МИ и Vite. --remove — ещё и убрать маршруты МИ из шлюза облака. Облако не трогается.
MOD="$(cd "$(dirname "$0")" && pwd)"
source "$MOD/../../cloud/lib.sh"
"$MOD/02-server.sh" stop
"$MOD/03-web.sh" stop
if [ "${1:-}" = --remove ]; then rm -f "$GATEWAY_D/im.conf"; "$CLOUD_KIT/04-gateway.sh"; fi
