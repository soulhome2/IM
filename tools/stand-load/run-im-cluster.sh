#!/usr/bin/env bash
# Стенд из N процессов сервера МИ на одной базе (план 99, задача 7). Раздача по очереди — в nginx (apply-nginx-dev.sh N).
#   run-im-cluster.sh <бинарник> [N=1]
# N=1 — unit im-stand-server, порт 5000, как до плана 99 (пул соединений из im-server.env/по умолчанию).
# N>1 — units im-stand-server-0…N-1, IM_DB_MAX_CONNS=10 у каждого. Порты: если Docker-сети открыты к 5001+ (CLUSTER_LB=0),
# то 5000…5000+N-1 и раздача — в ac_nginx (apply-nginx-dev.sh N). Иначе (по умолчанию, CLUSTER_LB=1: в vpn-killswitch открыт
# только 5000) процессы на 5001…5000+N, а на :5000 свой nginx-балансировщик (run-im-balancer.sh), ac_nginx — на один адрес.
# Остальные переменные (IM_LIVE_SLICE_VERIFY, IM_TEST_SUPPORT, IM_MACHINE_PATCH …) берутся из окружения запуска и
# передаются в unit. Сначала старый процесс останавливается; при N>1 первый процесс поднимается один до ответа порта
# (миграции), потом остальные. Под замком стенда. Только systemd-run, никогда setsid/nohup.
set -euo pipefail
bin="${1:?путь к бинарнику сервера}"; n="${2:-1}"
[[ "$bin" == /* ]] || bin="$HOME/Work/stand/bin/$bin"
if [[ "${CLUSTER_LOCKED:-}" != 1 ]]; then
	exec env CLUSTER_LOCKED=1 flock -o -w 30 "$HOME/Work/stand/lock-server" "$0" "$bin" "$n"
fi
LB="${CLUSTER_LB:-1}"
pkill -f "^$HOME/Work/stand/bin/im-" || true
"$HOME/Work/stand/run-im-balancer.sh" stop || true
systemctl --user stop im-stand-server im-stand-server-{0..9} 2>/dev/null || true
systemctl --user reset-failed 'im-stand-server*' 2>/dev/null || true
for i in $(seq 1 20); do pgrep -f "^$HOME/Work/stand/bin/im-" >/dev/null || break; sleep 0.5; done
envs=()
for v in IM_LIVE_SLICE_VERIFY IM_LOG_LEVEL IM_TEST_SUPPORT IM_MACHINE_PATCH; do
	[[ -v $v ]] && envs+=("--setenv=$v=${!v}")
done
start() { # unit порт
	local unit=$1 port=$2 extra=()
	[[ "$n" -gt 1 ]] && extra+=("--setenv=IM_DB_MAX_CONNS=${IM_DB_MAX_CONNS:-10}")
	[[ "$n" -eq 1 && -n "${IM_DB_MAX_CONNS:-}" ]] && extra+=("--setenv=IM_DB_MAX_CONNS=$IM_DB_MAX_CONNS")
	# unit с таким именем может ещё доживать после stop — подождать и повторить
	local try
	for try in 1 2 3 4 5 6 7 8 9 10; do
		systemd-run --user --collect --quiet --unit="$unit" "${envs[@]}" "${extra[@]}" --setenv="IM_SERVER_PORT=$port" \
			"$HOME/Work/stand/run-im-binary.sh" "$bin" && return 0
		sleep 1
	done
	echo "unit $unit не запустился" >&2; return 1
}
wait_port() { for i in $(seq 1 120); do (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null && return 0; sleep 0.5; done; echo "порт $1 не ответил" >&2; return 1; }
if [[ "$n" -eq 1 ]]; then
	start im-stand-server 5000; wait_port 5000
else
	base=5000; [[ "$LB" == 1 ]] && base=5001
	start im-stand-server-0 $base; wait_port $base
	for k in $(seq 1 $((n-1))); do start "im-stand-server-$k" $((base+k)); done
	for k in $(seq 1 $((n-1))); do wait_port $((base+k)); done
	[[ "$LB" == 1 ]] && "$HOME/Work/stand/run-im-balancer.sh" "$n"
fi
echo "запущено процессов: $n, бинарник $bin"
