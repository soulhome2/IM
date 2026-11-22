#!/bin/bash
# План 99, 7б, замер (а)/(б): очередь одного оператора на спокойном стенде, три сборки по очереди, каждая на свежем откате базы.
#   quiet_all.sh <запросов на вид> <метка>
N=${1:-600}; TAG=${2:-quiet}; L=~/Work/stand/load; O=$L/out/$TAG; mkdir -p $O; cd ~/Work/stand
run() { # имя бинарник [VERIFY]
  local name=$1 bin=$2 ver=$3
  echo "План 99, 7б: тихий замер $name" > $L/status.txt
  systemctl --user stop im-stand-server im-stand-server-{0..9} 2>/dev/null; pkill -f "^$HOME/Work/stand/bin/im-"; sleep 1
  bash $L/plan90G/restore_dump.sh ~/Work/stand/backup/imdb-before-p99-stage1-2026-11-21.dump > $O/$name.restore.log 2>&1 || echo "$name: откат базы не удался" >> $O/starts.log
  : > im-server.log
  for try in 1 2 3; do
    if [ -n "$ver" ]; then IM_LIVE_SLICE_VERIFY=$ver IM_LOG_LEVEL=info ./run-im-cluster.sh $bin 1 >/dev/null; else IM_LOG_LEVEL=info ./run-im-cluster.sh $bin 1 >/dev/null; fi && break
    cp im-server.log $O/$name.startfail$try.log; echo "$name: запуск не удался (попытка $try)" >> $O/starts.log; sleep 5
  done
  sleep 20
  python3 -I $L/quiet_queue.py 5000 $N $name > $O/$name.json 2>$O/$name.err
  cp im-server.log $O/$name.server.log
}
run p98 im-p98-efaac98
run p99-verify0 im-p99-ff6b5f1 0
run p99-verify1m im-p99-ff6b5f1 1m
echo "$TAG готово" > $L/status.txt
