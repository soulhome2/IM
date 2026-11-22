#!/usr/bin/env bash
# Локальный стенд: подменяет nginx.conf запущенного сервиса ac_nginx на копию из репозитория облака
# с дополнительными location для разработки МИ на машине:
#   /api/v1/im-backend/ -> сервер МИ  (host:5000)
#   /im/                -> Vite конфигуратора (host:5173, с WebSocket для HMR)
#   /im/operator/       -> тот же Vite, вторая страница (этап 8); absolute_redirect off, иначе 301 с адреса без слэша уходит на http://axxonnet.test:8082
# Файлы репозитория облака не меняются. Повторять после make deploy (stack deploy сбрасывает подмену).
#
#   apply-nginx-dev.sh [N]   N — число процессов сервера МИ (порты 5000…5000+N-1), по умолчанию 1 (план 99):
#   при N>1 запросы раздаются по очереди (upstream im-backend), при N=1 в нём один адрес, как до плана.
# Нужен проход из Docker-сетей к портам 5000/5173 машины (правило в vpn-killswitch, KS_IN).
set -euo pipefail
SRC="$HOME/Work/axxoncloudgo/tools/docker/nginx.anticonsul.conf"
OUT="${NGINX_OUT:-$HOME/Work/stand/nginx/nginx.conf}"
HOST_GW=$(sg docker -c "docker network inspect docker_gwbridge --format '{{(index .IPAM.Config 0).Gateway}}'")

N="${1:-1}"
python3 - "$SRC" "$OUT" "$HOST_GW" "$N" <<'PY'
import sys
src, out, gw, n = sys.argv[1:5]
n = int(n)
servers = ''.join(f'            server {gw}:{5000+k};\n' for k in range(n))
conf = open(src, encoding='utf-8').read()
anchor = "        location /api/ {\n"
assert conf.count(anchor) == 1, "не найден единственный location /api/"
block = f"""        # ===== МИ, разработка на машине (вставлено ~/Work/stand/apply-nginx-dev.sh) =====
        location /api/v1/im-backend/ {{
            proxy_pass http://im-backend;
            proxy_http_version 1.1;
            proxy_set_header Connection "";
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto https;
            proxy_buffering off;
            proxy_read_timeout 1h;
        }}
        location /im/ {{
            proxy_pass http://{gw}:5173;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection $connection_upgrade_im;
            proxy_set_header Host localhost:5173;
            proxy_read_timeout 1h;
            expires off;
            add_header Cache-Control "no-cache";
        }}
        location /im/operator/ {{
            proxy_pass http://{gw}:5173;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection $connection_upgrade_im;
            proxy_set_header Host localhost:5173;
            proxy_read_timeout 1h;
            expires off;
            add_header Cache-Control "no-cache";
            absolute_redirect off;
        }}
        # ===== конец вставки МИ =====

"""
conf = conf.replace(anchor, block + anchor)
http_anchor = "http {\n"
assert http_anchor in conf
up = f"    upstream im-backend {{\n{servers.replace('            ', '        ')}        keepalive 512;\n    }}\n"
conf = conf.replace(http_anchor, http_anchor + "    map $http_upgrade $connection_upgrade_im { default upgrade; '' close; }\n" + up, 1)
# План 99: у воркера 1024 дескриптора — под 100 операторами и несколькими серверами МИ nginx упирается в «No file descriptors
# available» (500/502 не от сервера). Поднять предел.
conf = conf.replace("worker_processes  1;\n", "worker_processes  1;\nworker_rlimit_nofile 16384;\n", 1)
conf = conf.replace("worker_connections  1024;", "worker_connections  8192;", 1)
open(out, 'w', encoding='utf-8').write(conf)
PY

NAME="ac-nginx-im-dev-$(sha1sum "$OUT" | cut -c1-10)"
D() { sg docker -c "$*"; }
D "docker config inspect $NAME >/dev/null 2>&1" || D "docker config create $NAME $OUT" >/dev/null
OLD=$(D "docker service inspect ac_nginx --format '{{range .Spec.TaskTemplate.ContainerSpec.Configs}}{{.ConfigName}} {{end}}'")
ARGS=""; for c in $OLD; do [ "$c" != "$NAME" ] && ARGS="$ARGS --config-rm $c"; done
case " $OLD " in
  *" $NAME "*) echo "ac_nginx: конфиг $NAME уже подключён" ;;
  *) D "docker service update --detach=false --quiet $ARGS --config-add source=$NAME,target=/etc/nginx/nginx.conf ac_nginx" ;;
esac
C=$(D "docker ps -q -f name=ac_nginx" | head -1)
D "docker exec $C nginx -t" 2>&1 | tail -1
echo "ac_nginx: конфиг $NAME"
