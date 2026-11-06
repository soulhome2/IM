#!/usr/bin/env bash
# Облако, шаг 2. Собрать и запустить облако (стек ac): образы, интерфейс, make deploy. Около 15 минут в первый раз.
#   02-build-deploy.sh            — всё
#   02-build-deploy.sh --no-build — без пересборки образов (только интерфейс и deploy)
source "$(dirname "$0")/lib.sh"
BUILD=1; [ "${1:-}" = --no-build ] && BUILD=0
cd "$CLOUD_DIR"

if [ $BUILD = 1 ]; then
  say "Подмена debian:bullseye (Debian 11 переехал в archive.debian.org)"
  if D docker image inspect debian:bullseye --format '{{index .Config.Labels "local.override"}}' 2>/dev/null | grep -q archive; then
    echo "  уже есть"
  else
    tmp=$(mktemp -d); cp "$CLOUD_KIT/bullseye-archive.Dockerfile" "$tmp/Dockerfile"
    D docker build -t debian:bullseye "$tmp"; rm -rf "$tmp"
  fi

  say "Go-модули"
  go_env; go mod download && go mod verify

  say "Образы облака (make build-all, ~10 мин)"
  if docker info >/dev/null 2>&1; then make build-all
  else sg docker -c "$( [ -n "${GO_ENV_FILE:-}" ] && echo "source '$GO_ENV_FILE' &&" ) make build-all"; fi
  rm -f arpagent_with_cover axxonrp/main/arpagent/pkgs.txt   # мусор сборки arpagent

  if [ -n "${UPLOADER_IMG:-}" ] && [ -f "$UPLOADER_IMG" ]; then
    say "Образ uploader"; D docker load -i "$UPLOADER_IMG"
  fi
fi

say "Интерфейс облака → tools/compose/ui"
UI="$CLOUD_DIR/tools/compose/ui"
if [ -d "$UI" ]; then tar -czf "$STAND_DIR/backup/ui-$(date +%Y%m%d-%H%M%S).tgz" -C "$CLOUD_DIR/tools/compose" ui; fi
rm -rf "$UI"; mkdir -p "$UI"
if [ -n "${UI_BUILD_DIR:-}" ]; then cp -a "$UI_BUILD_DIR"/. "$UI"/; echo "  из $UI_BUILD_DIR"
else [ -f "$UI_ZIP" ] || die "нет $UI_ZIP"; unzip -q "$UI_ZIP" -d "$UI"; echo "  из $UI_ZIP"
     # архив бывает с вложенной папкой — поднять содержимое
     [ -f "$UI/index.html" ] || { sub=$(dirname "$(find "$UI" -maxdepth 3 -name index.html | head -1)"); [ -n "$sub" ] && mv "$sub"/* "$UI"/; }
fi

say "make deploy (стек ac)"
D make deploy
D docker service scale ac_uploader=0 >/dev/null 2>&1 || true   # без хранилища uploader падает, МИ он не нужен

say "Ждём https://axxonnet.test/"
wait_http "$CLOUD/" 300 && echo "  облако отвечает" || die "облако не ответило за 5 минут: docker service ls"

# Шлюз сбросился на конфиг репозитория — вернуть куски модулей, если они есть
[ -n "$(ls -A "$GATEWAY_D" 2>/dev/null)" ] && "$CLOUD_KIT/04-gateway.sh" || true
