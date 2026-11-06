#!/usr/bin/env bash
# Облако, шаг 1. Проверить программы, включить Docker Swarm, прописать axxonnet.test в /etc/hosts.
# Просит sudo для /etc/hosts. Повторный запуск безопасен.
source "$(dirname "$0")/lib.sh"

say "Программы"
miss=0
for c in docker go node npm jq python3 curl git make; do
  if command -v "$c" >/dev/null; then echo "  есть $c"; else echo "  НЕТ $c"; miss=1; fi
done
D docker compose version >/dev/null 2>&1 || { echo "  НЕТ docker compose"; miss=1; }
[ $miss = 0 ] || die "поставьте недостающее (Docker CE с buildx и compose, Go, Node 20+, jq)"
id -nG | grep -qw docker || echo "  Внимание: вас нет в группе docker: sudo usermod -aG docker $USER, затем перезайти"

say "Репозитории"
for d in "$CLOUD_DIR"; do
  [ -d "$d/.git" ] || die "нет клона $d"
  echo "  $d — $(git -C "$d" rev-parse --abbrev-ref HEAD) $(git -C "$d" rev-parse --short HEAD)"
done

say "Docker Swarm"
if [ "$(D docker info --format '{{.Swarm.LocalNodeState}}')" = active ]; then echo "  уже включён"
else D docker swarm init --advertise-addr 127.0.0.1; fi

say "/etc/hosts"
if grep -qE '^\s*127\.0\.0\.1\s.*\baxxonnet\.test\b' /etc/hosts; then echo "  уже есть"
else echo '127.0.0.1 axxonnet.test' | sudo tee -a /etc/hosts >/dev/null && echo "  добавлено"; fi

check_pass_file && echo "Файл пароля на месте"
echo "Готово."
