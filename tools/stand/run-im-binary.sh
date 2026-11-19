#!/usr/bin/env bash
# Запуск готового бинарника сервера МИ на машине против локального облака: без cd в репозиторий и без go build,
# чтобы стенд не зависел от того, что сейчас лежит в рабочей копии (этапы 6 и 7 работают параллельно).
# https://axxonnet.test проверяется по корневому сертификату стенда — только для этого процесса.
# Вывод сервера дописывается в $STAND_DIR/im-server.log.
#
#   run-im-binary.sh <путь к бинарнику> [аргументы сервера]
#
# IM_TEST_SUPPORT и IM_MACHINE_PATCH, заданные при запуске, сильнее im-server.env:
#   IM_MACHINE_PATCH=... run-im-binary.sh $STAND_DIR/bin/im
# Заданная при запуске пустой (IM_MACHINE_PATCH= run-im-binary.sh …) переменная снимается (unset),
# даже если im-server.env её задаёт: сервер её не видит вовсе. Не заданная при запуске — берётся из im-server.env.
# Запускать только под замком стенда ($STAND_DIR/lock-server).
set -euo pipefail
STAND_DIR="${STAND_DIR:-$HOME/Work/stand}"
CLOUD_REPO="${CLOUD_REPO:-$HOME/Work/axxoncloudgo}"
bin="${1:?путь к бинарнику сервера}"
shift
if [[ ! -x "$bin" ]]; then
	echo "run-im-binary.sh: $bin — не исполняемый файл" >&2
	exit 1
fi
declare -A given=()
for name in IM_TEST_SUPPORT IM_MACHINE_PATCH; do
	if [[ -v $name ]]; then
		given[$name]="${!name}"
	fi
done
set -a; source "$STAND_DIR/im-server.env"; set +a
for name in "${!given[@]}"; do
	if [[ -z "${given[$name]}" ]]; then
		unset "$name"
	else
		export "$name=${given[$name]}"
	fi
done
export SSL_CERT_FILE="$CLOUD_REPO/tools/util/rootCA.axxonnet.test.pem"
exec "$bin" "$@" >>"$STAND_DIR/im-server.log" 2>&1
