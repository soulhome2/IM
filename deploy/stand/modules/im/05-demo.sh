#!/usr/bin/env bash
# МИ, шаг 5 (по желанию). Демо-данные: агент-эмулятор регистрируется, отправляет устройства из demo.json,
# затем заводятся приоритеты, группы, сценарии и правила. Пишет в базу МИ стенда.
#   05-demo.sh                 — регистрация (если ещё нет) + устройства + настройка
#   05-demo.sh --replay        — ещё и события: по событию на каждый инцидент demo.json
MOD="$(cd "$(dirname "$0")" && pwd)"
source "$MOD/../../cloud/lib.sh"
load_module_env "$MOD" im
EMU="$STAND_DIR/bin/agent-emulator"
FIX="$(cd "$MOD/../../../.." && pwd)/Specification/Workflow_machine/fixtures/demo.json"
KEY="$HOME/.config/im-agent-emulator/key.json"
API="http://127.0.0.1:$IM_SERVER_PORT/api/v1/im-backend"

say "Сборка агента-эмулятора"
(cd "$IM_SERVER_DIR" && go_env && go build -o "$EMU" ./tools/agent-emulator)
login
if [ ! -f "$KEY" ]; then
  say "Регистрация агента"
  curl -sf -X POST -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{"count":1}' "$API/agents/tokens" -o /dev/null
  T=$(curl -sf -H "Authorization: Bearer $TOKEN" "$API/agents/tokens" | jq -r '.[0] // empty')
  [ -n "$T" ] || die "сервер не выдал токен регистрации"
  "$EMU" --fixture "$FIX" enroll --token "$T"
fi
say "Устройства и настройка"
"$EMU" --fixture "$FIX" sync
"$EMU" --fixture "$FIX" demo-config --token "$TOKEN"
[ "${1:-}" = --replay ] && { say "События"; "$EMU" --fixture "$FIX" replay; }
echo "Готово."
