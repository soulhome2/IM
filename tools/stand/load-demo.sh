#!/usr/bin/env bash
# Локальный стенд: загрузка демо-настройки (этап 3) — типы и устройства агента, приоритеты, группы, сценарии, правила.
# Меняет ДАННЫЕ стенда (не код). Аргументы передаются в demo-config, например: load-demo.sh --replace-rules
# Нужен зарегистрированный агент: ~/.config/im-agent-emulator/key.json (agent-emulator enroll, см. 30-local-stand.md).
set -euo pipefail
STAND_DIR="${STAND_DIR:-$HOME/Work/stand}"
CLOUD_REPO="${CLOUD_REPO:-$HOME/Work/axxoncloudgo}"
HERE="$(dirname "$(readlink -f "$0")")"
CLOUD="${CLOUD:-https://axxonnet.test}"
CA="$CLOUD_REPO/tools/util/rootCA.axxonnet.test.pem"
source "$HERE/test-operator.sh"
EMU="$STAND_DIR/bin/agent-emulator"

operator_login || { echo "$OPERATOR_WHY" >&2; exit 1; }

"$EMU" sync
"$EMU" demo-config --token "$TOKEN" "$@"
