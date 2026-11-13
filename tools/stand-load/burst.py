#!/usr/bin/env python3
"""Лавина событий: python3 -I burst.py <событий> <секунд> <процессов> <метка> [каталог]
События — демонабор (27 шт.), повторённый ceil(N/27) раз; пачка k имеет метку <метка>-<k>, guid = uuid5(eventGuid, метка),
как у replay_dev.py, поэтому verify_ops.py и stream_stats.py работают по labels.txt/emit.jsonl.
Событие i подаётся в момент start + i*секунд/N; процесс p шлёт события i % P == p, у каждого своё соединение
(общее HTTPS-соединение потоков давало SIGSEGV, 2026-11-11). Вход — X-Dev-Agent на 127.0.0.1:5000.
Журнал: <каталог>/burst-<метка>.jsonl — {i, guid, label, t (подача), ms, code}. Итог — строка JSON в stdout."""
import http.client, json, math, multiprocessing as mp, os, sys, time, uuid
FX = "/mnt/hgfs/VmWareShared/soul2home/IM/Specification/Workflow_machine/fixtures/demo.json"
AGENT = "01a18217-5af1-7948-a879-21acffd5fe93"
N, SEC, P, TAG = int(sys.argv[1]), float(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
OUT = sys.argv[5] if len(sys.argv) > 5 else os.path.expanduser("~/Work/stand/load/out/" + TAG)
os.makedirs(OUT, exist_ok=True)
fx = json.load(open(FX))
names = {d["id"]: d["name"] for d in fx["devices"]}
seen, base = set(), []
for inc in fx["incidents"]:
    g = inc.get("eventGuid")
    if g and inc.get("devices") and g not in seen:
        seen.add(g); base.append((inc["occurredAt"], g, inc))
base.sort(key=lambda x: (x[0], x[1]))
nb = math.ceil(N / len(base))
labels = [f"{TAG}-{k}" for k in range(nb)]
EV = [(labels[k], str(uuid.uuid5(uuid.UUID(g), labels[k])), inc) for k in range(nb) for _, g, inc in base]


def worker(p, start, q):
    c = http.client.HTTPConnection("127.0.0.1", 5000, timeout=60)
    recs = []
    for i in range(p, len(EV), P):
        lb, guid, inc = EV[i]
        at = start + i * SEC / len(EV)
        d = at - time.time()
        if d > 0:
            time.sleep(d)
        dev = inc["devices"][0]
        now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        body = {"guid": guid, "sourceUid": dev, "eventTypeUid": inc["eventType"]["id"],
                "payload": {"occurredAt": now, "deviceName": names.get(dev, ""), "text": inc.get("location", ""),
                            "site": inc.get("site", ""), "emulator": True}}
        t0 = time.time()
        try:
            c.request("POST", "/api/v1/im-agent/events", json.dumps(body),
                      {"Content-Type": "application/json", "X-Dev-Agent": AGENT})
            r = c.getresponse(); r.read(); code = r.status
        except Exception as e:
            code = -1
            try: c.close()
            except Exception: pass
            c = http.client.HTTPConnection("127.0.0.1", 5000, timeout=60)
        recs.append({"i": i, "guid": guid, "label": lb, "t": round(t0, 4), "ms": round((time.time() - t0) * 1000, 1), "code": code,
                     "late": round(t0 - at, 3)})
    q.put(recs)


if __name__ == "__main__":
    start = time.time() + 1.0
    q = mp.Queue()
    ps = [mp.Process(target=worker, args=(p, start, q)) for p in range(P)]
    [x.start() for x in ps]
    recs = []
    for _ in ps:
        recs += q.get()
    [x.join() for x in ps]
    recs.sort(key=lambda r: r["i"])
    with open(os.path.join(OUT, f"burst-{TAG}.jsonl"), "w") as f:
        for r in recs: f.write(json.dumps(r) + "\n")
    with open(os.path.join(OUT, "labels-burst.txt"), "a") as f:
        for lb in labels: f.write(lb + "\n")
    with open(os.path.join(OUT, "emit-burst.jsonl"), "a") as f:
        for lb in labels:
            ts = [r["t"] for r in recs if r["label"] == lb]
            f.write(json.dumps({"label": lb, "t0": min(ts), "ms": round((max(ts) - min(ts)) * 1000), "rc": 0, "burst": TAG}) + "\n")
    ms = sorted(r["ms"] for r in recs)
    pct = lambda p: ms[min(len(ms) - 1, int(len(ms) * p))]
    codes = {}
    for r in recs: codes[str(r["code"])] = codes.get(str(r["code"]), 0) + 1
    t0, t1 = min(r["t"] for r in recs), max(r["t"] + r["ms"] / 1000 for r in recs)
    print(json.dumps({"tag": TAG, "events": len(recs), "batches": nb, "plan_s": SEC, "real_s": round(t1 - t0, 1),
                      "eps": round(len(recs) / (t1 - t0), 1), "codes": codes, "ms": {"p50": pct(.5), "p95": pct(.95), "p99": pct(.99), "max": ms[-1]},
                      "late_max_s": max(r["late"] for r in recs), "t0": t0, "t1": t1}))
