#!/usr/bin/env python3
"""Поток событий после прогона load_ops.py: задержка от подачи пачки эмулятором до incident.created у каждого оператора,
потерянные и повторные. Запуск: python3 -I stream_stats.py <каталог прогона>. Итог — stream.json рядом и строка в stdout.
Инциденты пачки — из imdb по event_guid = uuid5(eventGuid набора, метка). Последние 15 с прогона не считаются потерянными."""
import json, os, subprocess, sys, uuid
from collections import Counter
OUT = sys.argv[1]
fx = json.load(open("/mnt/hgfs/VmWareShared/soul2home/IM/Specification/Workflow_machine/fixtures/demo.json"))
evs = sorted({i["eventGuid"] for i in fx["incidents"]})
C = subprocess.run("docker ps --format '{{.Names}}' | grep ^ac_db", shell=True, capture_output=True, text=True).stdout.strip()
emits = [json.loads(l) for l in open(os.path.join(OUT, "emit.jsonl"))]
ids = json.load(open(os.path.join(OUT, "ids.json")))
recv = [json.loads(l) for l in open(os.path.join(OUT, "stream.jsonl"))]
log = [json.loads(l) for l in open(os.path.join(OUT, "log.jsonl"))]
t_end = max(r["t"] for r in log)
inc2t = {}
for e in emits:
    g = {str(uuid.uuid5(uuid.UUID(x), e["label"])) for x in evs}
    q = "select guid from incidents where event_guid in (%s)" % ",".join("'%s'" % x for x in g)
    rows = subprocess.run(["docker", "exec", C, "psql", "-U", "im", "imdb", "-Atc", q], capture_output=True, text=True).stdout.split()
    for r in rows:
        inc2t[r] = e["t0"]
got = Counter((r["who"], r["inc"]) for r in recv)
lat = sorted(r["t"] - inc2t[r["inc"]] for r in recv if r["inc"] in inc2t)
first = {}
for r in recv:
    if r["inc"] in inc2t:
        first.setdefault(r["inc"], []).append(r["t"] - inc2t[r["inc"]])
# Видимость: операторам load-op (группа cloud-user) по правилам доступа видна часть инцидентов (§5) —
# ожидаемые = инциденты пачек, которые пришли хотя бы одному оператору.
seen_any = {r["inc"] for r in recv}
expected = [i for i, t in inc2t.items() if t < t_end - 15 and i in seen_any]
lost = [(w, i) for w in ids for i in expected if (w, i) not in got]
dups = sum(n - 1 for n in got.values() if n > 1)
pct = lambda a, p: round(a[min(len(a) - 1, int(len(a) * p))] * 1000) if a else None
s = {"batches": len(emits), "incidents": len(inc2t), "operators": len(ids), "deliveries": len(lat),
     "visible": len(seen_any & set(inc2t)), "expected": len(expected) * len(ids), "lost": len(lost), "lost_by_op": dict(Counter(w for w, _ in lost)),
     "dups": dups, "lat_ms": {"p50": pct(lat, .5), "p95": pct(lat, .95), "p99": pct(lat, .99), "max": pct(lat, 1)},
     "foreign_created": sum(1 for r in recv if r["inc"] not in inc2t),
     "resets": sum(1 for r in log if r["op"] == "stream:reset"), "drops": sum(1 for r in log if r["op"] == "stream:drop"),
     "reconnects": sum(1 for r in log if r["op"] == "stream:reconnect")}
json.dump(s, open(os.path.join(OUT, "stream.json"), "w"), ensure_ascii=False, indent=1)
print(json.dumps(s, ensure_ascii=False))
