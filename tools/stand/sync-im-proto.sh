#!/usr/bin/env bash
# Локальный стенд: копия prototype/, tests/ и theme/ из репозитория IM в каталог интерфейса облака,
# чтобы tests/api.html открывался с того же адреса https://axxonnet.test/im-proto/.
# Каталог ui в .gitignore облака, репозиторий облака не меняется.
set -euo pipefail
CLOUD_REPO="${CLOUD_REPO:-$HOME/Work/axxoncloudgo}"
HERE="$(dirname "$(readlink -f "$0")")"
IM_REPO="${IM_REPO:-$(cd "$HERE/../.." && pwd)}"
SRC=$IM_REPO
DST="$CLOUD_REPO/tools/compose/ui/im-proto"
mkdir -p "$DST"
rsync -a --delete --chmod=D755,F644 "$SRC/prototype" "$SRC/tests" "$SRC/theme" "$DST/"
echo "Скопировано в $DST (https://axxonnet.test/im-proto/tests/api.html)"
