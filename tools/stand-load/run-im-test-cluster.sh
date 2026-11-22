#!/usr/bin/env bash
# План 99, задача 7, шаг 2: тестовая сборка сервера МИ (тег imtest) в N процессов на одной тестовой базе im_stand_api7
# (контейнер im-test-db-7, 127.0.0.1:55437) — для tests/api.html. Не трогает imdb и стенд на 5000.
#   run-im-test-cluster.sh <бинарник imtest> <N>   — поднять; API — http://127.0.0.1:5010/api/v1/im-backend (балансировщик),
#                                                    процессы на 5011…; страница — http://127.0.0.1:8707/tests/api.html
#   run-im-test-cluster.sh stop
# Только systemd-run --user. Тестовая сборка облако не спрашивает (решение 186 плана 61).
set -euo pipefail
S="$HOME/Work/stand"; IMDIR=/mnt/hgfs/VmWareShared/soul2home/IM; DB=im_stand_api7
stop_all() {
	systemctl --user stop im-test-page im-test-api-{0..9} 2>/dev/null || true
	"$S/run-im-balancer.sh" stop 5010 5011 im-test-lb || true
}
stop_all
[[ "${1:?бинарник или stop}" == stop ]] && exit 0
bin="$1"; n="${2:-1}"; [[ "$bin" == /* ]] || bin="$S/bin/$bin"
docker exec im-test-db-7 psql -U postgres -c "select pg_terminate_backend(pid) from pg_stat_activity where datname='$DB' and pid<>pg_backend_pid()" >/dev/null
start() {
	systemd-run --user --collect --quiet --unit="im-test-api-$1" \
		--setenv="IM_DB_URL=postgresql://postgres:postgres@127.0.0.1:55437/$DB?sslmode=disable" --setenv="IM_SERVER_PORT=$((5011 + $1))" \
		--setenv=IM_TEST_SUPPORT=true --setenv=IM_AGENT_DEV_AUTH=${IM_AGENT_DEV_AUTH:-false} --setenv=IM_CLOUD_URL=http://127.0.0.1:9/stand-cloud-not-used --setenv=IM_S2S_CLOUD_URL=http://127.0.0.1:9/stand-cloud-not-used \
		--setenv=IM_CUSTOMER_GUID=b440ee0d-1ccd-456e-b25f-6ad0c8e398db --setenv=IM_LOG_LEVEL=info --setenv="IM_DB_MAX_CONNS=$([[ $n -gt 1 ]] && echo 10 || echo 16)" \
		bash -c "exec '$bin' >>'$S/im-test-api-$1.log' 2>&1"
}
wait_up() { for i in $(seq 1 120); do [[ "$(curl -s -o /dev/null -w '%{http_code}' -X POST "http://127.0.0.1:$1/api/v1/im-backend/test/reset" -d '{}' || true)" == 200 ]] && return 0; sleep 0.5; done; echo "порт $1: /test/reset не ответил 200" >&2; return 1; }
: > "$S/im-test-api-0.log"
start 0; wait_up 5011
for k in $(seq 1 $((n - 1))); do start "$k"; done
for k in $(seq 1 $((n - 1))); do wait_up $((5011 + k)); done
"$S/run-im-balancer.sh" "$n" 5010 5011 im-test-lb
systemd-run --user --collect --quiet --unit=im-test-page python3 -m http.server 8707 --bind 127.0.0.1 --directory "$IMDIR"
echo "тестовых процессов: $n; API http://127.0.0.1:5010/api/v1/im-backend; страница http://127.0.0.1:8707/tests/api.html"
