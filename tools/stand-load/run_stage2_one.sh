#!/bin/bash
# План 99, этап 2: один прогон 100 операторов с idempotencyKey на переходах: откат imdb из копии этапа 2, сервер N процессов, run_p99.sh.
#   run_stage2_one.sh <метка> <бинарник> <N> [минут=10]   (лавина выключена: BURSTMIN=999, если не задан)
set -u
TAG=$1; BIN=$2; N=$3; MIN=${4:-10}
cd ~/Work/stand
systemctl --user stop im-stand-server im-stand-server-{0..9} 2>/dev/null; ./run-im-balancer.sh stop 2>/dev/null
bash load/plan90G/restore_dump.sh backup/imdb-before-p99-stage2-2026-11-22.dump 2>&1 | tail -1
./run-im-cluster.sh $BIN $N 2>&1 | tail -1
sleep 20
cd load
IDEMP=1 BURSTMIN=${BURSTMIN:-999} STEPMIN=$MIN SRVPAT=$BIN bash run_p99.sh $TAG
python3 -I - $TAG <<'PY'
import json,sys
t=sys.argv[1]; recs=[json.loads(l) for l in open("out/%s-p0/log.jsonl"%t)]
tr=sorted(r["ms"] for r in recs if r["op"].startswith("transition:") and r["code"]==200)
by={}
for r in recs:
    if r["op"].startswith("transition:"): by.setdefault(r["op"],[]).append(r)
def pc(a,p): a=sorted(a); return a[min(len(a)-1,int(len(a)*p))] if a else None
out={"tag":t,"transitions_200":len(tr),"p50":pc(tr,.5),"p95":pc(tr,.95),"p99":pc(tr,.99)}
out["by_op"]={k:{"n":len(v),"p50":pc([r["ms"] for r in v if r["code"]==200],.5),"p95":pc([r["ms"] for r in v if r["code"]==200],.95)} for k,v in sorted(by.items())}
out["5xx"]=sum(1 for r in recs if (r["code"]>=500 or r["code"]<0) and not (r["op"]=="card:media" and r["code"]==501) and not r["op"].startswith("stream:"))
print(json.dumps(out,ensure_ascii=False))
open("out/%s/idem.json"%t,"w").write(json.dumps(out,ensure_ascii=False,indent=1))
PY
