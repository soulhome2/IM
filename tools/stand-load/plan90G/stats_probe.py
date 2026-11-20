#!/usr/bin/env python3
"""План 90, часть Г: замер GET /operator/supervisor/stats через прокси облака от test@.

  stats_probe.py login                          — печатает только «ok», токен кладёт в файл TOKEN (scratchpad)
  stats_probe.py once  '<query>'                — один запрос, печатает код, время и начало ответа
  stats_probe.py run   <out.jsonl> <n> <span> '<name>=<query>' …
        span — 7d | 30d | 90d. Холодный запрос: from = начало периода, to = «сейчас» + уникальный сдвиг в мс
        (позже «сейчас» сервер обрезает до «сейчас»): ключ памяти на минуту каждый раз новый, а счёт тот же,
        что у period=7d|30d (7d/30d — с полуночи зоны смены, как сервер; 90d — «сейчас» минус 90 сут, сервер
        обрезает по сроку хранения). После каждого холодного — тот же запрос ещё раз: из памяти.
  stats_probe.py loop  <out.jsonl> <span> <pause_s> <секунд> — «старший»: холодные запросы с паузой (опыт влияния).
  stats_probe.py csv   <out.jsonl> <n> <span>     — stats.csv: время до первого байта, всего, размер.
"""
import json, os, ssl, sys, time, urllib.request, urllib.error, urllib.parse, random, datetime
from zoneinfo import ZoneInfo

S = os.path.dirname(os.path.abspath(__file__))
TOKF = os.path.join(S, "TOKEN")
CA = os.path.expanduser("~/Work/axxoncloudgo/tools/util/rootCA.axxonnet.test.pem")
API = "https://axxonnet.test/api/v1/im-backend"
CTX = ssl.create_default_context(cafile=CA)
CTX.verify_flags &= ~ssl.VERIFY_X509_STRICT
ZONE = ZoneInfo(os.environ.get("ZONE", "Europe/Moscow"))


def login():
    pw = open(os.path.expanduser("~/Work/stand/test-operator.pass")).read().rstrip("\n")
    body = json.dumps({"email": "test@axxonnet.test", "password": pw}).encode()
    r = urllib.request.urlopen(urllib.request.Request("https://axxonnet.test/api/v3/ac-backend/users/login", body,
                                                      {"Content-Type": "application/json"}), context=CTX, timeout=20)
    tok = json.load(r)["accessToken"]
    with open(TOKF, "w") as f:
        f.write(tok)
    os.chmod(TOKF, 0o600)
    return tok


def token():
    if os.path.exists(TOKF) and time.time() - os.path.getmtime(TOKF) < 600:
        return open(TOKF).read()
    return login()


def get(path, timeout=90):
    req = urllib.request.Request(API + path, headers={"Authorization": "Bearer " + token()})
    t0 = time.perf_counter()
    try:
        r = urllib.request.urlopen(req, context=CTX, timeout=timeout)
        code = r.status
        ttfb = time.perf_counter() - t0
        body = r.read()
    except urllib.error.HTTPError as e:
        code = e.code
        ttfb = time.perf_counter() - t0
        body = e.read()
    except Exception as e:  # сбой сети, тайм-аут
        return {"code": "net:" + type(e).__name__, "ms": round((time.perf_counter() - t0) * 1000, 1), "ttfb_ms": None, "bytes": 0, "body": b""}
    return {"code": code, "ms": round((time.perf_counter() - t0) * 1000, 1), "ttfb_ms": round(ttfb * 1000, 1), "bytes": len(body), "body": body}


def span_from(span):
    now = datetime.datetime.now(ZONE)
    if span == "90d":
        return now - datetime.timedelta(days=90)
    days = {"7d": 6, "30d": 29}[span]
    mid = now.replace(hour=0, minute=0, second=0, microsecond=0)
    return mid - datetime.timedelta(days=days)


def iso(t):
    return t.astimezone(datetime.timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def cold_query(span, extra, k):
    to = datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(hours=1, milliseconds=k)
    q = {"from": iso(span_from(span)), "to": iso(to)}
    if extra:
        q.update(dict(urllib.parse.parse_qsl(extra)))
    return "/operator/supervisor/stats?" + urllib.parse.urlencode(q)


def summary(body):
    try:
        d = json.loads(body)
    except Exception:
        return {"raw": body[:200].decode(errors="replace")}
    cur = d.get("current") or d.get("totals") or {}
    return {"incidents": cur.get("incidents"), "code_err": d.get("code")}


def run(out, n, span, variants):
    f = open(out, "a")
    seq = random.randint(0, 10**6)
    for v in variants:
        name, extra = v.split("=", 1) if "=" in v else (v, "")
        for i in range(n):
            seq += 1
            p = cold_query(span, extra, seq)
            a = get(p)
            b = get(p)  # тот же запрос сразу — из памяти
            rec = {"t": time.time(), "span": span, "variant": name, "i": i, "cold_ms": a["ms"], "cold_code": a["code"],
                   "warm_ms": b["ms"], "warm_code": b["code"], "bytes": a["bytes"], **summary(a["body"])}
            f.write(json.dumps(rec, ensure_ascii=False) + "\n"); f.flush()
            print(span, name, i, a["code"], a["ms"], b["ms"], rec.get("incidents"), flush=True)


def loop(out, span, pause, secs):
    f = open(out, "a")
    seq = random.randint(0, 10**9)
    end = time.time() + secs
    while time.time() < end:
        seq += 1
        a = get(cold_query(span, "", seq))
        f.write(json.dumps({"t": time.time(), "span": span, "ms": a["ms"], "code": a["code"], "bytes": a["bytes"],
                            **summary(a["body"])}, ensure_ascii=False) + "\n"); f.flush()
        time.sleep(pause)


def csv(out, n, span):
    f = open(out, "a")
    seq = random.randint(0, 10**6)
    for i in range(n):
        seq += 1
        p = cold_query(span, "", seq).replace("/stats?", "/stats.csv?")
        a = get(p, timeout=300)
        f.write(json.dumps({"t": time.time(), "span": span, "i": i, "code": a["code"], "ttfb_ms": a["ttfb_ms"], "ms": a["ms"],
                            "bytes": a["bytes"]}) + "\n"); f.flush()
        print(i, a["code"], a["ttfb_ms"], a["ms"], a["bytes"], flush=True)


if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "login":
        login(); print("ok")
    elif cmd == "once":
        a = get(sys.argv[2]); print(a["code"], a["ms"], a["bytes"]); print(a["body"][:int(os.environ.get("SHOW", "1500"))].decode(errors="replace"))
    elif cmd == "run":
        run(sys.argv[2], int(sys.argv[3]), sys.argv[4], sys.argv[5:])
    elif cmd == "loop":
        loop(sys.argv[2], sys.argv[3], float(sys.argv[4]), float(sys.argv[5]))
    elif cmd == "csv":
        csv(sys.argv[2], int(sys.argv[3]), sys.argv[4])
