#!/usr/bin/env bash
# Балансировщик стенда из нескольких процессов сервера МИ (план 99, задача 7), когда Docker-сети закрыты к портам 5001+ машины
# (в vpn-killswitch открыт только 5000, править его без root нельзя). Свой nginx в сети машины (--net=host) слушает 5000 и
# раздаёт по очереди на 127.0.0.1:<5001…5000+N> — по loopback проход открыт. Облачный nginx (ac_nginx) по-прежнему ходит на один
# адрес, :5000. Те же настройки прокси, что в apply-nginx-dev.sh (keepalive 512, без буфера, чтение 1 ч).
#   run-im-balancer.sh <N>      — поднять (unit im-stand-lb); сначала снять прежний
#   run-im-balancer.sh stop     — остановить
#   run-im-balancer.sh <N|stop> [порт=5000] [первый порт серверов=5001] [имя=im-stand-lb] — другой балансировщик (тесты API, ниже)
set -euo pipefail
arg="${1:?N или stop}"; LISTEN="${2:-5000}"; FIRST="${3:-5001}"; NAME="${4:-im-stand-lb}"
systemctl --user stop "$NAME" 2>/dev/null || true
sg docker -c "docker rm -f $NAME" >/dev/null 2>&1 || true
[[ "$arg" == stop ]] && exit 0
n="$arg"; conf="$HOME/Work/stand/nginx/$NAME.conf"
{
	echo "worker_processes 2; worker_rlimit_nofile 16384; error_log /dev/stderr warn; pid /tmp/$NAME.pid;"
	echo "events { worker_connections 8192; }"
	echo "http {"
	if [[ -n "${LB_ACCESS:-}" ]]; then
		echo "  log_format lbf '\$time_iso8601 \$request_method \$uri \$status \$request_time up=\$upstream_addr ut=\$upstream_response_time'; access_log /dev/stdout lbf;"
	else
		echo "  access_log off;"
	fi
	echo "  upstream im-nodes {"
	[[ -n "${LB_STICKY:-}" ]] && echo "    ip_hash;"
	for k in $(seq 1 "$n"); do echo "    server 127.0.0.1:$((FIRST - 1 + k));"; done
	echo "    keepalive 512;"
	echo "  }"
	echo "  server { listen $LISTEN backlog=4096;"
	echo "    location / { proxy_pass http://im-nodes; proxy_http_version 1.1; proxy_set_header Connection \"\";"
	echo "      proxy_set_header Host \$host; proxy_set_header X-Real-IP \$remote_addr; proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;"
	echo "      proxy_set_header X-Forwarded-Proto https; proxy_buffering off; proxy_read_timeout 1h; }"
	echo "  }"
	echo "}"
} > "$conf"
systemd-run --user --collect --quiet --unit=$NAME sg docker -c "docker run --rm --name $NAME --net=host --entrypoint nginx -v $conf:/etc/nginx/nginx.conf:ro ac/nginx-anticonsul:latest -g 'daemon off;'"
for i in $(seq 1 40); do (exec 3<>/dev/tcp/127.0.0.1/$LISTEN) 2>/dev/null && { echo "балансировщик на :$LISTEN → $FIRST…$((FIRST - 1 + n))"; exit 0; }; sleep 0.5; done
echo "балансировщик не поднялся" >&2; exit 1
