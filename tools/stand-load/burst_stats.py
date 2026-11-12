#!/usr/bin/env python3
"""Разбор лавин части 1: python3 -I burst_stats.py <каталог>
По каждой лавине (burst-<метка>-<буква>.jsonl): приём (событий/с, коды, время ответа), инциденты лавины в базе,
поток SSE — задержка от подачи события до incident.created у оператора (p50/p95/p99/max), потери (оператор не получил
инцидент, который получил хоть один другой), повторы; время восстановления — первые 60 с после конца лавины, когда
p95 очереди за скользящие 60 с ≤ max(1,5 × до, до + 100 мс), и задержка потока фона ≤ max(1,5 × до, до + 500 мс);
планировщик — максимум просроченных реакций после лавины и через сколько секунд их снова 0 (samples.jsonl)."""
import glob, json, os, subprocess, sys
from collections import Counter, defaultdict
OUT = sys.argv[1]
C = subprocess.run("docker ps --format '{{.Names}}' | grep ^ac_db", shell=True, capture_output=True, text=True).stdout.strip()
pct = lambda a, p: round(a[min(len(a) - 1, int(len(a) * p))]) if a else None


def sql(q):
    return [l.split("|") for l in subprocess.run(["docker", "exec", C, "psql", "-U", "im", "imdb", "-AtF|", "-c", q],
                                                  capture_output=True, text=True).stdout.split("\n") if l]


log = [json.loads(l) for l in open(os.path.join(OUT, "log.jsonl")) if l.endswith("}\n")]
recv = [json.loads(l) for l in open(os.path.join(OUT, "stream.jsonl")) if l.endswith("}\n")]
ids = json.load(open(os.path.join(OUT, "ids.json")))
samples = [json.loads(l) for l in open(os.path.join(OUT, "samples.jsonl"))]
q = sorted((r["t"], r["ms"]) for r in log if r["who"].startswith("op") and r["op"].startswith("queue:"))
# все события прогона: фон (emit.jsonl без burst) — время подачи пачки; лавина — время каждого события
import uuid
fx = json.load(open("/mnt/hgfs/VmWareShared/soul2home/IM/Specification/Workflow_machine/fixtures/demo.json"))
base = sorted({i["eventGuid"] for i in fx["incidents"] if i.get("eventGuid")})
ev_t, ev_src = {}, {}
for e in (json.loads(l) for l in open(os.path.join(OUT, "emit.jsonl"))):
    if e.get("burst"): continue
    for g in base:
        x = str(uuid.uuid5(uuid.UUID(g), e["label"])); ev_t[x] = e["t0"]; ev_src[x] = "bg"
bursts = {}
for f in sorted(glob.glob(os.path.join(OUT, "burst-*.jsonl"))):
    tag = os.path.basename(f)[6:-6]
    rs = [json.loads(l) for l in open(f)]
    bursts[tag] = rs
    for r in rs: ev_t[r["guid"]] = r["t"]; ev_src[r["guid"]] = tag
inc_ev = {}
keys = list(ev_t)
for i in range(0, len(keys), 2000):
    for g, e in sql("select guid, event_guid from incidents where event_guid in (%s)" % ",".join("'%s'" % k for k in keys[i:i + 2000])):
        inc_ev[g] = e
lat = defaultdict(list); got = Counter()
for r in recv:
    e = inc_ev.get(r["inc"])
    if e is None: continue
    got[(r["who"], r["inc"])] += 1
    lat[ev_src[e]].append((ev_t[e], r["t"] - ev_t[e]))
seen = defaultdict(set)
for (w, i) in got: seen[i].add(w)


def window_p95(t1, t2):
    a = sorted(ms for t, ms in q if t1 <= t < t2)
    return pct(a, .95)


def bg_lat(t1, t2):
    a = sorted(l * 1000 for t, l in lat["bg"] if t1 <= t < t2)
    return pct(a, .95) if a else None


res = []
for tag, rs in bursts.items():
    t0 = min(r["t"] for r in rs); t1 = max(r["t"] + r["ms"] / 1000 for r in rs)
    codes = Counter(str(r["code"]) for r in rs)
    ms = sorted(r["ms"] for r in rs)
    incs = [i for i, e in inc_ev.items() if ev_src.get(e) == tag]
    vis = [i for i in incs if seen.get(i)]
    lost = sum(len(ids) - len(seen[i]) for i in vis)
    dups = sum(n - 1 for (w, i), n in got.items() if n > 1 and ev_src.get(inc_ev[i]) == tag)
    L = sorted(l * 1000 for _, l in lat[tag])
    b_q = window_p95(t0 - 180, t0); b_l = bg_lat(t0 - 180, t0)
    d_q = window_p95(t0, t1 + 60)
    rec_q = rec_l = None
    for s in range(0, 1800, 10):
        a = window_p95(t1 + s, t1 + s + 60)
        if a is not None and b_q is not None and a <= max(1.5 * b_q, b_q + 100):
            rec_q = s; break
    for s in range(0, 1800, 10):
        a = bg_lat(t1 + s, t1 + s + 60)
        if a is not None and b_l is not None and a <= max(1.5 * b_l, b_l + 500):
            rec_l = s; break
    # хвост доставки: когда последний инцидент лавины пришёл последнему оператору
    tail = round(max((t for _, l in lat[tag] for t in [_ + l]), default=t1) - t1, 1)
    sm = [s for s in samples if t0 - 30 <= s["t"] <= t1 + 1200 and "overdue" in s]
    od_max = max((s["overdue"] for s in sm), default=None)
    sm_after = [s for s in samples if s["t"] >= t1 and "overdue" in s]
    srv_cpu = max((s.get("cpu_cores") or 0 for s in sm if s["t"] <= t1 + 120), default=None)
    rss = max((s.get("rss_kb", 0) for s in sm), default=0) // 1024
    act = max((s.get("active", 0) for s in sm), default=None)
    lw = max((s.get("lockwait", 0) for s in sm), default=None)
    res.append({"burst": tag, "events": len(rs), "plan_eps": None, "real_s": round(t1 - t0, 1), "eps": round(len(rs) / (t1 - t0), 1),
                "codes": dict(codes), "post_ms": [pct(ms, .5), pct(ms, .95), pct(ms, .99), ms[-1]],
                "incidents": len(incs), "visible": len(vis), "deliveries": len(L), "lost": lost, "dups": dups,
                "lat_ms": [pct(L, .5), pct(L, .95), pct(L, .99), pct(L, 1)], "tail_after_end_s": tail,
                "queue_p95_before": b_q, "queue_p95_during": d_q, "bg_lat_p95_before": b_l,
                "recover_queue_s": rec_q, "recover_stream_s": rec_l,
                "overdue_max": od_max, "srv_cpu_max": srv_cpu, "srv_rss_max_mb": rss, "db_active_max": act, "lockwait_max": lw,
                "t0": t0, "t1": t1})
json.dump(res, open(os.path.join(OUT, "bursts.json"), "w"), ensure_ascii=False, indent=1)
for r in res:
    print(json.dumps({k: v for k, v in r.items() if k not in ("t0", "t1", "plan_eps")}, ensure_ascii=False))
