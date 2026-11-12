#!/usr/bin/env python3
"""summary.json по log.jsonl, если load_ops.py не дописал его сам (генератор упал). python3 -I summarize.py <каталог>"""
import json, os, statistics, sys
OUT = sys.argv[1]
recs = [json.loads(l) for l in open(os.path.join(OUT, "log.jsonl")) if l.strip().endswith("}")]
ids = json.load(open(os.path.join(OUT, "ids.json")))
by = {}
for r in recs:
    if r["op"] in ("outcome", "race:verdict"): continue
    by.setdefault(r["op"], []).append(r)
ops = {}
for op, rs in sorted(by.items()):
    ms = sorted(r["ms"] for r in rs); codes = {}
    for r in rs:
        k = str(r["code"]) + ("/" + str(r.get("err"))[:60] if r.get("err") else ""); codes[k] = codes.get(k, 0) + 1
    pct = lambda p: ms[min(len(ms) - 1, int(len(ms) * p))]
    ops[op] = {"n": len(rs), "p50": pct(.5), "p95": pct(.95), "p99": pct(.99), "max": ms[-1], "codes": codes,
               "bytes_avg": round(statistics.mean(r.get("bytes", 0) for r in rs))}
reqs = [r for r in recs if r["who"] in ids and r["op"] != "outcome" and not r["op"].startswith("stream:")]
known = lambda r: r["op"] == "card:media" and r["code"] == 501
errs = sum(1 for r in reqs if (r["code"] >= 500 or r["code"] < 0) and not known(r))
t = [r["t"] for r in recs]
s = {"run": os.path.basename(OUT.rstrip("/")), "operators": len(ids), "duration_min": round((max(t) - min(t)) / 60, 2),
     "requests": len(reqs), "rps": round(len(reqs) / max(1, max(t) - min(t)), 1), "errors_5xx_net": errs,
     "err_share": round(errs / max(1, len(reqs)), 5), "media_501": sum(1 for r in reqs if known(r)),
     "err_4xx_unexpected": sum(1 for r in reqs if 400 <= r["code"] < 500 and r["code"] not in (409, 412, 422) and not known(r)),
     "retries": sum(1 for r in reqs if r.get("retry")),
     "transitions_ok": sum(1 for r in recs if r["op"] == "outcome" and r["code"] == 200), "ops": ops,
     "note": "" if os.path.exists(os.path.join(OUT, "summary.json")) else "пересчитано summarize.py: генератор упал до конца"}
json.dump(s, open(os.path.join(OUT, "summary2.json"), "w"), ensure_ascii=False, indent=1)
print(json.dumps({k: v for k, v in s.items() if k != "ops"}, ensure_ascii=False))
