#!/bin/bash
# План 99, этап 2: прогон на 5 процессах. run_5node.sh <метка> <бинарник> <минут> <режим: plain | fall>
# fall: ещё lead_watch, lead_kill2 (штатный stop лидера на 4-й минуте, через 150 с SIGKILL нового лидера) и repeat_storm (повторы ключей).
set -u
export IM_LOG_LEVEL=info
TAG=$1; BIN=$2; MIN=$3; MODE=$4
S=~/Work/stand; L=$S/load; O=$L/out/$TAG; mkdir -p $O
cd $S
systemctl --user stop im-stand-server im-stand-server-{0..9} 2>/dev/null; ./run-im-balancer.sh stop 2>/dev/null
bash load/plan90G/restore_dump.sh backup/imdb-before-p99-stage2-2026-11-22.dump 2>&1 | tail -1
for p in 5001 5002 5003 5004 5005; do : > im-server-$p.log; done
./run-im-cluster.sh $BIN 5 2>&1 | tail -1
sleep 25
cd $L
if [ $MODE = fall ]; then
  bash lead_watch.sh $O/lead.jsonl $((MIN*60+30)) &
  bash lead_kill2.sh $O 240 150 &
  ( sleep 60; python3 -I repeat_storm.py 127.0.0.1:5000 $(( (MIN-2)*60 )) 8 $O > $O/storm.txt 2>&1 ) &
fi
IDEMP=1 BURSTMIN=10 STEPMIN=$MIN SRVPAT=$BIN bash run_p99.sh $TAG
wait
for p in 5001 5002 5003 5004 5005; do cp $S/im-server-$p.log $O/; done
{
  echo "== verify_ops"; python3 -I verify_ops.py out/$TAG-p0 2>&1 | tail -15
  echo "== nodes_check"; python3 -I nodes_check.py 5001 5002 5003 5004 5005 2>&1 | tail -8
  echo "== differs"; for p in 5001 5002 5003 5004 5005; do echo $p $(grep -c 'differs from the base' $S/im-server-$p.log); done
  echo "== tick took long"; for p in 5001 5002 5003 5004 5005; do echo $p $(grep -c 'tick took long' $S/im-server-$p.log); done
  echo "== idempotency_keys"; docker exec 375f9250b4b1 psql -U postgres imdb -Atc "select count(*), count(*) filter (where state='running') from idempotency_keys"
} > $O/post.txt 2>&1
python3 -I - $TAG <<'PY'
import json,sys
t=sys.argv[1]; recs=[json.loads(l) for l in open("out/%s-p0/log.jsonl"%t)]
tr=sorted(r["ms"] for r in recs if r["op"].startswith("transition:") and r["code"]==200)
def pc(a,p): a=sorted(a); return a[min(len(a)-1,int(len(a)*p))] if a else None
out={"tag":t,"transitions_200":len(tr),"p50":pc(tr,.5),"p95":pc(tr,.95),"p99":pc(tr,.99)}
out["5xx"]=sum(1 for r in recs if (r["code"]>=500 or r["code"]<0) and not (r["op"]=="card:media" and r["code"]==501) and not r["op"].startswith("stream:"))
out["reqs"]=len(recs)
open("out/%s/idem.json"%t,"w").write(json.dumps(out,ensure_ascii=False,indent=1)); print(out)
PY
touch $O/done
