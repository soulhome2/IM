#!/usr/bin/env python3
"""Разбор замера сброса (план 86): приём событий по журналу сервера и ответы операторов по журналу нагрузки — до, во время и после сброса.
   python3 -I reset_stats.py <каталог прогона> [журнал сервера]"""
import json, sys, os, collections, datetime
O = sys.argv[1]; LOG = sys.argv[2] if len(sys.argv) > 2 else os.path.expanduser("~/Work/stand/im-server.log")
r = json.load(open(os.path.join(O, "reset.json"))); t0, t1 = r["t0"], float(os.environ.get("T1", r["t1"]))  # T1 — конец сброса на сервере, если прокси оборвал ответ
def win(t): return "до" if t < t0 else ("во время" if t <= t1 else "после")
def took(s):
    for u, k in (("ms", 1), ("µs", 1e-3), ("s", 1e3), ("m", 6e4)):
        if s.endswith(u):
            try: return float(s[:-len(u)]) * k
            except ValueError: pass
    return None
ev = collections.defaultdict(list); codes = collections.defaultdict(collections.Counter)
lo, hi = t0 - 120, t1 + 180
with open(LOG, errors="replace") as f:
    f.seek(max(0, os.path.getsize(LOG) - 400_000_000))
    for line in f:
        if "im-agent/events" not in line or "completed" not in line: continue
        try: x = json.loads(line)
        except ValueError: continue
        t = datetime.datetime.fromisoformat(x["time"]).timestamp()
        if not lo <= t <= hi: continue
        w = win(t); codes[w][x["status"]] += 1; ev[w].append(took(x["took"]) or 0)
def pct(v, p): v = sorted(v); return round(v[min(len(v) - 1, int(len(v) * p))]) if v else None
print("сброс:", r["code"], round(r["ms"] / 1000, 1), "с")
for w in ("до", "во время", "после"):
    print(f"приём {w}: коды {dict(codes[w])}, p50 {pct(ev[w], .5)} мс, p95 {pct(ev[w], .95)} мс, макс {pct(ev[w], 1)} мс")
ops = collections.defaultdict(list); oc = collections.defaultdict(collections.Counter)
p = os.path.abspath(O).rstrip("/") + "-ops/log.jsonl"
for line in open(p):
    try: x = json.loads(line)
    except ValueError: continue
    if "t" not in x or "ms" not in x: continue
    w = win(x["t"]); ops[w].append(x["ms"]); oc[w][x["code"]] += 1
for w in ("до", "во время", "после"):
    print(f"операторы {w}: запросов {len(ops[w])}, коды {dict(oc[w])}, p50 {pct(ops[w], .5)} мс, p95 {pct(ops[w], .95)} мс, макс {pct(ops[w], 1)} мс")
locks, buf = [], ""
for l in open(os.path.join(O, "locks.jsonl")):  # старые снимки — запись на нескольких строках
    if l.startswith('{"t"') and buf:
        try: locks.append(json.JSONDecoder().raw_decode(buf.strip().replace(']}, "waiting"', '], "waiting"'))[0])
        except ValueError: pass
        buf = ""
    buf += l.rstrip("\n") + " "
if buf:
    try: locks.append(json.JSONDecoder().raw_decode(buf.strip().replace(']}, "waiting"', '], "waiting"'))[0])
    except ValueError: pass
print("снимков блокировок:", len(locks), "макс. ждущих запросов:", max((l["waiting"] for l in locks), default=0),
      "мин. свободно ГБ:", min((l["free_gb"] for l in locks), default=None))
slow = collections.Counter()
for line in open(p):
    try: x = json.loads(line)
    except ValueError: continue
    if x.get("ms", 0) > 2000 and x.get("t", 0) >= t0 - 1: slow[(x["op"], x["code"])] += 1
print("операторы, ответы дольше 2 с от начала сброса:", dict(slow))
ok = [l for l in locks if t0 <= l["t"] <= t1]
rel = collections.Counter(k["relname"] for l in ok for k in l["locks"] if not k["granted"])
print("ждали замок во время сброса (снимков, по таблице):", dict(rel.most_common(8)))
