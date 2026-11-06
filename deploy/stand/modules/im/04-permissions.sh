#!/usr/bin/env bash
# МИ, шаг 4. Выдать группе cloud-admin права incident_manager.* из машины МИ.
# Сервер МИ должен быть запущен (он регистрирует каталог прав). Повторный запуск безопасен.
MOD="$(cd "$(dirname "$0")" && pwd)"
source "$MOD/../../cloud/lib.sh"
load_module_env "$MOD" im
login
SCHEMA="$IM_SERVER_DIR/api/im/operator/workflow_schema.v1.json"
[ -f "$SCHEMA" ] || die "нет $SCHEMA"
WANT=$(jq -c '[.permissions[].cloud]' "$SCHEMA")
API="$CLOUD/api/v3/ac-backend"
ROLES=$(curl -sf --cacert "$CA" -H "Authorization: Bearer $TOKEN" "$API/roles/global")
echo "$ROLES" | jq -e 'any(.[]; .name=="cloud-admin")' >/dev/null || die "роль cloud-admin не найдена"
echo "$ROLES" | jq --argjson w "$WANT" \
  'map(if .name=="cloud-admin" then .permissions = ([.permissions[] | select(startswith("incident_manager.")|not)] + $w) else . end)' \
  | curl -sf --cacert "$CA" -X PATCH -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d @- "$API/roles/global" -o /dev/null \
  && echo "PATCH /roles/global: OK"
login   # новый токен — с новыми правами
N=$(curl -sf --cacert "$CA" -H "Authorization: Bearer $TOKEN" "$API/me" \
  | jq '[.capabilities.incident_manager // {} | to_entries[] | .value.actions | to_entries[] | (.value.scopes // [""]) | if length==0 then [""] else . end | .[]] | length')
echo "в /me прав incident_manager: $N (ожидается $(echo "$WANT" | jq length))"
