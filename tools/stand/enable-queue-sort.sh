#!/usr/bin/env bash
# Включить «Оператор может менять порядок» в «Настройках поста» организации стенда. Пишет в imdb — перед запуском дамп.
set -uo pipefail
CLOUD_REPO="${CLOUD_REPO:-$HOME/Work/axxoncloudgo}"
HERE="$(dirname "$(readlink -f "$0")")"
API="https://axxonnet.test/api/v1/im-backend"; CLOUD="https://axxonnet.test"; CA="$CLOUD_REPO/tools/util/rootCA.axxonnet.test.pem"
source "$HERE/test-operator.sh"; TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
operator_login || { echo "SKIP вход: $OPERATOR_WHY"; exit 2; }
r() { local m=$1 p=$2 f=${3:-}; local a=(-s --cacert "$CA" -X "$m" -o "$TMP/body" -w '%{http_code}' -H "Authorization: Bearer $TOKEN"); [ -n "$f" ] && a+=(-H 'Content-Type: application/json' --data-binary "@$f"); CODE=$(curl "${a[@]}" "$API$p"); }
r GET /operator/workflow/active; echo "сейчас: $(jq -c .queueSort "$TMP/body")"
[ "$(jq -r .queueSort.operatorMayChange "$TMP/body")" = true ] && { echo "уже включено"; exit 0; }
jq '.queueSort.operatorMayChange = true' "$TMP/body" > "$TMP/d.json"
r POST /operator/workflow/schemas "$TMP/d.json"; G=$(jq -r '.schema.guid // .schema.schemaGuid // empty' "$TMP/body"); echo "черновик $CODE $G"
r POST "/operator/workflow/schemas/$G/validate"; echo "проверка $CODE $(jq -c .valid "$TMP/body")"
r POST "/operator/workflow/schemas/$G/publish"; echo "публикация $CODE $(jq -r .schema.status "$TMP/body")"
r GET /operator/workflow/active; echo "теперь: $(jq -c .queueSort "$TMP/body")"
