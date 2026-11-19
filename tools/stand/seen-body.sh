# RULE-142: что видел оператор. seen_body <токен> <путь карточки> [тело-JSON] — печатает тело с expectedState,
# expectedAddressee, journalSeen по текущей карточке (GET). Нужны $API и $CA.
seen_body() {
  local tok=$1 path=$2 body=${3:-\{\} } card
  card=$(curl -s --max-time 20 --cacert "$CA" -H "Authorization: Bearer $tok" "$API$path")
  printf '%s' "$card" | jq -c --argjson b "$body" '$b + {expectedState: .state, expectedAddressee: (.addressee.id // ""), journalSeen: (.journalSeq // 0)}'
}
