#!/usr/bin/env bash
# Облако, шаг 4. Шлюз облака (сервис ac_nginx) с маршрутами модулей, которые работают на машине.
#
# Модуль кладёт кусок конфига nginx в $STAND_DIR/gateway.d/<модуль>.conf (location-блоки).
# В куске вместо адреса машины пишется @HOST@, например:  proxy_pass http://@HOST@:5000;
# Скрипт вставляет все куски перед `location /api/` конфига облака и подменяет конфиг запущенного сервиса.
# Файлы репозитория облака не меняются. Повторять после каждого make deploy (02-build-deploy.sh делает это сам).
# Без кусков — возвращает чистый конфиг облака.
source "$(dirname "$0")/lib.sh"
SRC="$CLOUD_DIR/tools/docker/nginx.anticonsul.conf"
OUT="$STAND_DIR/nginx.conf"
GW=$(D docker network inspect docker_gwbridge --format '{{(index .IPAM.Config 0).Gateway}}')
shopt -s nullglob; PARTS=("$GATEWAY_D"/*.conf); shopt -u nullglob
echo "модули в шлюзе: ${PARTS[*]:-нет}"

# Порты машины, к которым ходит шлюз — для фаервола
PORTS=$(cat "${PARTS[@]}" /dev/null | grep -o '@HOST@:[0-9]\+' | cut -d: -f2 | sort -u | paste -sd, -)

# Фаервол с цепочкой KS_IN (vpn-killswitch) режет вход из Docker — пропустить к портам модулей
if [ -n "$PORTS" ] && sudo iptables -L KS_IN -n >/dev/null 2>&1; then
  sudo iptables -C KS_IN -s 172.16.0.0/12 -p tcp -m multiport --dports "$PORTS" -j ACCEPT 2>/dev/null \
    || sudo iptables -I KS_IN 1 -s 172.16.0.0/12 -p tcp -m multiport --dports "$PORTS" -j ACCEPT
  echo "фаервол KS_IN: из Docker открыт проход к портам $PORTS"
fi

python3 - "$SRC" "$OUT" "$GW" "${PARTS[@]}" <<'PY'
import sys, os
src, out, gw, *parts = sys.argv[1:]
conf = open(src, encoding='utf-8').read()
anchor = "        location /api/ {\n"
assert conf.count(anchor) == 1, "в конфиге облака не найден единственный location /api/"
block = ""
for p in parts:
    body = open(p, encoding='utf-8').read().replace("@HOST@", gw)
    block += f"        # ===== модуль {os.path.basename(p)} (deploy/stand/cloud/04-gateway.sh) =====\n{body}\n"
conf = conf.replace(anchor, block + anchor)
# общий map для WebSocket (HMR Vite и т. п.)
conf = conf.replace("http {\n", "http {\n    map $http_upgrade $connection_upgrade_dev { default upgrade; '' close; }\n", 1)
open(out, 'w', encoding='utf-8').write(conf)
PY

NAME="ac-nginx-dev-$(sha1sum "$OUT" | cut -c1-10)"
D docker config inspect "$NAME" >/dev/null 2>&1 || D docker config create "$NAME" "$OUT" >/dev/null
ARGS=()
for c in $(D docker service inspect ac_nginx --format '{{range .Spec.TaskTemplate.ContainerSpec.Configs}}{{.ConfigName}} {{end}}'); do
  [ "$c" != "$NAME" ] && ARGS+=(--config-rm "$c")
done
D docker service update --detach=false --quiet "${ARGS[@]}" --config-add "source=$NAME,target=/etc/nginx/nginx.conf" ac_nginx
D docker exec "$(D docker ps -q -f name=ac_nginx | head -1)" nginx -t 2>&1 | tail -1
echo "ac_nginx: конфиг $NAME"
