#!/usr/bin/env bash
# Запуск сервера МИ ($IM_SERVER_REPO) на машине против локального облака.
# https://axxonnet.test проверяется по корневому сертификату стенда — только для этого процесса.
set -euo pipefail
STAND_DIR="${STAND_DIR:-$HOME/Work/stand}"
CLOUD_REPO="${CLOUD_REPO:-$HOME/Work/axxoncloudgo}"
IM_SERVER_REPO="${IM_SERVER_REPO:-$HOME/Work/incident-manager-server}"
cd "$IM_SERVER_REPO"
# Go-модули без VPN: файл с GOPROXY на локальную копию модулей (30-local-stand.md, шаг 3); нет файла — обычный GOPROXY.
GO_ENV_FILE="${GO_ENV_FILE:-$HOME/go/offline-env.sh}"
if [ -f "$GO_ENV_FILE" ]; then source "$GO_ENV_FILE"; fi
set -a; source "$STAND_DIR/im-server.env"; set +a
export SSL_CERT_FILE="$CLOUD_REPO/tools/util/rootCA.axxonnet.test.pem"
mkdir -p "$STAND_DIR/bin"
go build -o "$STAND_DIR/bin/im" ./cmd/im
exec "$STAND_DIR/bin/im" "$@"
