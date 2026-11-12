#!/usr/bin/env python3
"""Снимок раз в <сек> в <каталог>/samples.jsonl, пока есть <каталог>/.running:
сервер МИ (RSS, потоки, дескрипторы, CPU за интервал из /proc), база imdb (соединения, активные, ждущие блокировку,
pg_locks не выданные, живые инциденты, просроченные реакции, всего инцидентов/событий), активные запросы (первые 80 знаков).
python3 -I sampler.py <каталог> [сек=5] [имя бинарника=im-cond-type]"""
import json, os, subprocess, sys, time
OUT = sys.argv[1]; EVERY = float(sys.argv[2]) if len(sys.argv) > 2 else 5; BIN = sys.argv[3] if len(sys.argv) > 3 else "im-cond-type"
C = subprocess.run("docker ps --format '{{.Names}}' | grep ^ac_db", shell=True, capture_output=True, text=True).stdout.strip()
TCK = os.sysconf("SC_CLK_TCK")
Q = """select (select count(*) from pg_stat_activity where datname='imdb')||'|'||
(select count(*) from pg_stat_activity where datname='imdb' and state='active')||'|'||
(select count(*) from pg_stat_activity where datname='imdb' and wait_event_type='Lock')||'|'||
(select count(*) from pg_locks where not granted)||'|'||
(select count(*) from incidents where deleted_at is null and state<>'closed')||'|'||
(select count(*) from incidents where deleted_at is null and im_next_due(timers) <= (extract(epoch from now())*1000)::bigint)||'|'||
(select count(*) from incidents)||'|'||(select count(*) from events)||'|'||
coalesce((select string_agg(left(regexp_replace(query,'\\s+',' ','g'),80)||'~'||round(extract(epoch from now()-query_start)*1000),'^^')
 from pg_stat_activity where datname='imdb' and state='active' and pid<>pg_backend_pid()),'')"""


def srv():
    pid = subprocess.run(["pgrep", "-f", "^/home/slava/Work/stand/bin/" + BIN], capture_output=True, text=True).stdout.split()
    if not pid: return None, {}
    p = pid[0]
    st = open(f"/proc/{p}/status").read()
    g = lambda k: int([l for l in st.splitlines() if l.startswith(k)][0].split()[1])
    f = open(f"/proc/{p}/stat").read().rsplit(")", 1)[1].split()
    return p, {"rss_kb": g("VmRSS"), "threads": g("Threads"), "fd": len(os.listdir(f"/proc/{p}/fd")), "cpu_ticks": int(f[11]) + int(f[12])}


prev = None
with open(os.path.join(OUT, "samples.jsonl"), "a") as fo:
    while os.path.exists(os.path.join(OUT, ".running")):
        t = time.time()
        pid, s = srv()
        r = subprocess.run(["docker", "exec", C, "psql", "-U", "im", "imdb", "-Atc", Q], capture_output=True, text=True).stdout.strip()
        parts = r.split("|", 8)
        rec = {"t": round(t, 2), "pid": pid, **s}
        if prev and s and prev[1].get("cpu_ticks") is not None:
            rec["cpu_cores"] = round((s["cpu_ticks"] - prev[1]["cpu_ticks"]) / TCK / (t - prev[0]), 2)
        if len(parts) == 9:
            k = ["conns", "active", "lockwait", "locks_ungranted", "live", "overdue", "incidents", "events"]
            rec.update({a: int(b) for a, b in zip(k, parts[:8])})
            rec["queries"] = [x for x in parts[8].split("^^") if x]
        fo.write(json.dumps(rec, ensure_ascii=False) + "\n"); fo.flush()
        prev = (t, s)
        time.sleep(max(0, EVERY - (time.time() - t)))
