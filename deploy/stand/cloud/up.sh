#!/usr/bin/env bash
# Облако целиком: шаги 1–4 и проверка. Модули ставятся после, своими up.sh.
#   up.sh             — с нуля
#   up.sh --no-build  — без пересборки образов облака
set -euo pipefail
H="$(cd "$(dirname "$0")" && pwd)"
"$H/01-prereq.sh"
"$H/02-build-deploy.sh" "$@"
"$H/03-users.sh"
"$H/04-gateway.sh"
"$H/check.sh"
echo; echo "Облако: https://axxonnet.test/   вход без пароля: https://axxonnet.test/dev-login.html"
