#!/usr/bin/env bash
# Vite конфигуратора/места оператора ($IM_CONFIGURATOR_REPO) для стенда: открывать через https://axxonnet.test/im/...
# VITE_API_URL — на локальное облако, иначе прокси Vite по умолчанию смотрит в боевое bezeq-pos1.axxoncloud.com.
set -euo pipefail
IM_CONFIGURATOR_REPO="${IM_CONFIGURATOR_REPO:-$HOME/Work/incident-manager}"
cd "$IM_CONFIGURATOR_REPO"
export VITE_API_URL=https://axxonnet.test NODE_TLS_REJECT_UNAUTHORIZED=0
exec npx vite --host 0.0.0.0 --port 5173 --strictPort
