#!/usr/bin/env bash
# Запуск готового бинарника сервера МИ на машине против локального облака: без cd в репозиторий и без go build,
# чтобы стенд не зависел от того, что сейчас лежит в рабочей копии (этапы 6 и 7 работают параллельно).
# https://axxonnet.test проверяется по корневому сертификату стенда — только для этого процесса.
# Вывод сервера дописывается в ~/Work/stand/im-server.log.
#
#   run-im-binary.sh <путь к бинарнику> [аргументы сервера]
#
# IM_TEST_SUPPORT и IM_MACHINE_PATCH, заданные при запуске, сильнее im-server.env:
#   IM_MACHINE_PATCH=... run-im-binary.sh ~/Work/stand/bin/im
# Заданная при запуске пустой (IM_MACHINE_PATCH= run-im-binary.sh …) переменная снимается (unset),
# даже если im-server.env её задаёт: сервер её не видит вовсе. Не заданная при запуске — берётся из im-server.env.
# Так же — IM_SERVER_PORT (порт процесса; на стенде из нескольких процессов 5000, 5001, …), IM_DB_MAX_CONNS (пул соединений
# к базе) и IM_LIVE_SLICE_VERIFY (интервал сверки среза, 0 — выключена).
# Лог: IM_STAND_LOG, иначе порт 5000 — ~/Work/stand/im-server.log (как раньше), другой порт — ~/Work/stand/im-server-<порт>.log.
# Запускать только под замком стенда (~/Work/stand/lock-server).
set -euo pipefail
bin="${1:?путь к бинарнику сервера}"
shift
if [[ ! -x "$bin" ]]; then
	echo "run-im-binary.sh: $bin — не исполняемый файл" >&2
	exit 1
fi
declare -A given=()
for name in IM_TEST_SUPPORT IM_MACHINE_PATCH IM_SERVER_PORT IM_DB_MAX_CONNS IM_LIVE_SLICE_VERIFY IM_LOG_LEVEL; do
	if [[ -v $name ]]; then
		given[$name]="${!name}"
	fi
done
set -a; source "$HOME/Work/stand/im-server.env"; set +a
for name in "${!given[@]}"; do
	if [[ -z "${given[$name]}" ]]; then
		unset "$name"
	else
		export "$name=${given[$name]}"
	fi
done
export SSL_CERT_FILE="$HOME/Work/axxoncloudgo/tools/util/rootCA.axxonnet.test.pem"
port="${IM_SERVER_PORT:-5000}"
if [[ -n "${IM_STAND_LOG:-}" ]]; then
	log="$IM_STAND_LOG"
elif [[ "$port" == 5000 ]]; then
	log="$HOME/Work/stand/im-server.log"
else
	log="$HOME/Work/stand/im-server-$port.log"
fi
exec "$bin" "$@" >>"$log" 2>&1
