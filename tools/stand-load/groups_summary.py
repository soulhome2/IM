#!/usr/bin/env python3
"""План 99, замер правок групп: сводка прогона. python3 -I groups_summary.py <метка> …"""
import json, sys, os
L = os.path.expanduser("~/Work/stand/load/out")
def pc(a, p): a = sorted(a); return round(a[min(len(a)-1, int(len(a)*p))], 1) if a else None
for tag in sys.argv[1:]:
    recs = [json.loads(l) for l in open("%s/%s-p0/log.jsonl" % (L, tag))]
    by = {}
    for r in recs:
        by.setdefault(r["op"], []).append(r)
    def ms(*names, ok=True):
        return [r["ms"] for n in names for r in by.get(n, []) if (r["code"] < 400 or not ok)]
    queue = ms("queue:open", "queue:inbox", "queue:mine", "queue:foreign") or ms(*[k for k in by if k.startswith("queue:")])
    cnt = ms("counters", "reload:counters"); tree = ms("reload:tree")
    act = [r["ms"] for k, v in by.items() if k.startswith("transition:") for r in v if r["code"] == 200]
    err = sum(1 for r in recs if (r["code"] >= 500 or r["code"] < 0) and r["op"] not in ("outcome",) and not r["op"].startswith("stream:") and not (r["op"] == "card:media" and r["code"] == 501))
    samp = [json.loads(l) for l in open("%s/%s/samp.jsonl" % (L, tag))]
    conns = max(s["conns"] for s in samp)
    res = [json.loads(l) for l in open("%s/%s/res.jsonl" % (L, tag))]
    sc = [s["srv_cpu"] for s in res]; pcpu = [float(s["db_cpu"].rstrip("%")) for s in res]
    ed = []
    if os.path.exists("%s/%s/edits.jsonl" % (L, tag)):
        ed = [json.loads(l) for l in open("%s/%s/edits.jsonl" % (L, tag))]
    print("==", tag)
    print("queue n=%d p50=%s p95=%s p99=%s" % (len(queue), pc(queue, .5), pc(queue, .95), pc(queue, .99)))
    print("counters n=%d p95=%s p99=%s" % (len(cnt), pc(cnt, .95), pc(cnt, .99)))
    print("tree(reload) n=%d p50=%s p95=%s p99=%s max=%s" % (len(tree), pc(tree, .5), pc(tree, .95), pc(tree, .99), max(tree) if tree else None))
    print("actions(transitions 200) n=%d p50=%s p95=%s p99=%s" % (len(act), pc(act, .5), pc(act, .95), pc(act, .99)))
    print("5xx", err, "conns peak", conns, "srv cpu%% avg/max %s/%s" % (round(sum(sc)/len(sc)), max(sc)), "pg cpu%% avg/max %s/%s" % (round(sum(pcpu)/len(pcpu)), max(pcpu)))
    if ed:
        e = [x["ms"] for x in ed]; bad = [x for x in ed if x["code"] != 200]
        print("edits n=%d p50=%s p95=%s max=%s non200=%d" % (len(ed), pc(e, .5), pc(e, .95), max(e), len(bad)))
    for f in ("pgss-groups.txt", "feed-rows.txt", "nodes.txt"):
        p = "%s/%s/%s" % (L, tag, f)
        if os.path.exists(p): print(f, open(p).read().strip())
