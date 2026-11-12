#!/usr/bin/env python3
"""Цифры окна журнала load_ops: python3 -I win.py <каталог> <t1> <t2>  (unix-время)
Печатает JSON: p50/p95/p99 всех queue:* вместе, худший p95 отдельной queue:*, counters, card; ошибки 5xx/сеть у операторов;
задержка потока для инцидентов фоновых пачек, поданных в окне (по emit.jsonl, без лавин)."""
import json, os, sys
OUT, T1, T2 = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
pct = lambda a, p: round(a[min(len(a) - 1, int(len(a) * p))]) if a else None
q, cnt, crd, by, n, err = [], [], [], {}, 0, 0
for l in open(os.path.join(OUT, "log.jsonl")):
    if not l.endswith("}\n"): continue
    r = json.loads(l)
    if not (T1 <= r["t"] < T2) or not r["who"].startswith("op") or r["op"] == "outcome" or r["op"].startswith("stream:"): continue
    n += 1
    if (r["code"] >= 500 or r["code"] < 0) and not (r["op"] == "card:media" and r["code"] == 501): err += 1
    if r["op"].startswith("queue:"): q.append(r["ms"]); by.setdefault(r["op"], []).append(r["ms"])
    elif r["op"] == "counters": cnt.append(r["ms"])
    elif r["op"] == "card": crd.append(r["ms"])
for a in [q, cnt, crd] + list(by.values()): a.sort()
worst = max(((k, pct(v, .95)) for k, v in by.items() if len(v) >= 10), key=lambda x: x[1], default=None)
print(json.dumps({"n": n, "err": err, "err_share": round(err / max(1, n), 4),
                  "queue": [pct(q, .5), pct(q, .95), pct(q, .99), len(q)], "queue_worst_p95": worst,
                  "counters": [pct(cnt, .5), pct(cnt, .95), pct(cnt, .99)], "card": [pct(crd, .5), pct(crd, .95), pct(crd, .99)]}))
