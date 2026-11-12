#!/usr/bin/env python3
"""Сверка после прогона load_ops.py (N операторов, расширение verify.py): что видели операторы (log.jsonl) против базы стенда (imdb).

Запуск: python3 -I verify_ops.py <каталог прогона>. Строки "OK|FAIL <что>", код выхода — число FAIL.
Проверяет:
 1. Ни одного 5xx и сетевого сбоя у запросов операторов.
 2. Гонки: ни разу не было двух успехов на один и тот же переход одного инцидента.
 3. Приём событий: check-demo-intake.sh по каждой пачке (27 событий → 30 инцидентов, без дублей).
 4. Каждый успешный переход оператора есть в журнале инцидента ровно столько раз, сколько он прошёл.
 5. Состояние и владелец согласованы: new — без владельца, in_progress/on_hold — с владельцем,
    closed — closed_by и closed_at есть; каждый закрытый оператором — закрыт в базе им же.
"""
import json, os, subprocess, sys
from collections import Counter

OUT = sys.argv[1]
STAND = os.path.expanduser("~/Work/stand")
fails = 0


def check(what, ok):
    global fails
    print(("OK   " if ok else "FAIL ") + what)
    if not ok:
        fails += 1


def sql(q):
    c = subprocess.run(["docker", "ps", "-qf", "name=ac_db"], capture_output=True, text=True).stdout.split()[0]
    # запрос — через stdin: длинный список guid не помещается в аргументы (E2BIG, 2026-11-12)
    r = subprocess.run(["docker", "exec", "-i", c, "psql", "-U", "im", "-d", "imdb", "-AtF", "|"], input=q + ";",
                       capture_output=True, text=True)
    return [l.split("|") for l in r.stdout.strip().splitlines() if l]


ids = json.load(open(os.path.join(OUT, "ids.json")))
recs = [json.loads(l) for l in open(os.path.join(OUT, "log.jsonl"))]
T0 = min(r["t"] for r in recs) - 5
T1 = max(r["t"] for r in recs) + 5  # верхняя граница: следующий прогон теми же операторами не попадает в сверку
ops = [r for r in recs if r["who"] in ids and r["op"] != "outcome" and not r["op"].startswith("stream:")]
outs = [r for r in recs if r["op"] == "outcome"]


bad = [r for r in ops if (r["code"] >= 500 or r["code"] < 0) and not (r["op"] == "card:media" and r["code"] == 501)]
check(f"  (501 NOT_IMPLEMENTED у card:media — заглушка сервера, не считается: {sum(1 for r in ops if r['op'] == 'card:media' and r['code'] == 501)})", True)
check(f"запросов операторов {len(ops)}, 5xx и сбоев сети: {len(bad)} {Counter(r['op'] for r in bad).most_common(5)}", not bad)
unexpected = Counter((r["op"], r["code"], r.get("err")) for r in ops if 400 <= r["code"] < 500 and r["code"] not in (409, 412, 422)
                     and not (r["op"] == "race:close" and r["code"] == 403 and r.get("err") == "GUARD_FAILED"))
check(f"4xx кроме 409/412/422: {dict(unexpected)}", not unexpected)

# 2. Двойные успехи: один и тот же переход (tid) одного инцидента из одного состояния прошёл у двух операторов.
wins = Counter()
for r in outs:
    if r["code"] == 200:
        wins[(r["inc"], r["tid"], r["from"], r["who"])] += 1
pairs = Counter((i, t, f) for (i, t, f, w) in wins)
double = [k for k, n in pairs.items() if n > 1 and k[1] in ("claim", "close")]
check(f"двойной успех claim/close у двух операторов: {len(double)} {double[:3]}", not double)
rv = [r for r in recs if r["op"] in ("race:verdict", "race:close-verdict")]
check(f"гонок {len(rv)}, с двумя победителями: {sum(r['code'] for r in rv)}", rv and not sum(r["code"] for r in rv))
check(f"  гонок claim с ровно одним победителем: {sum(1 for r in rv if r['op']=='race:verdict' and r.get('wins')==1)}"
      f" из {sum(1 for r in rv if r['op']=='race:verdict')}", True)

# 3. Приём событий по пачкам: у каждого события набора — свои инциденты (2 у 1834, 1847, 1851, иначе 1),
# ровно одна запись create на инцидент, номер тревоги — первый номер, событие обработано, нет дублей событие+сценарий.
# (check-demo-intake.sh тут не годится: он ждёт инциденты нетронутыми — state new, версия 1.)
import uuid
fx = json.load(open("/mnt/hgfs/VmWareShared/soul2home/IM/Specification/Workflow_machine/fixtures/demo.json"))
evs = sorted({inc["eventGuid"] for inc in fx["incidents"]})
TWO = {"1834", "1847", "1851"}
labels = [l.strip() for l in open(os.path.join(OUT, "labels.txt")) if l.strip()]
intake_bad = []
# Сколько инцидентов даёт каждое событие, зависит от нынешних правил стенда (набор 1834/1847/1851 устарел):
# ожидание — одинаковое число у одного события во всех пачках прогона (мода по пачкам), без дублей.
per = {}
detail = []
for lb in labels:
    gl = {str(uuid.uuid5(uuid.UUID(g), lb)): g for g in evs}
    inl = ",".join("'%s'" % g for g in gl)
    ev = {g: (a, p) for g, a, p in sql(f"select guid, coalesce(alarm_number::text,''), processed from events "
                                        f"where guid in ({inl}) and deleted_at is null")}
    inc = sql(f"select i.event_guid, i.number, i.scenario_guid, (select count(*) from incident_journal j "
              f"where j.incident_guid=i.guid and j.transition='create') from incidents i "
              f"where i.event_guid in ({inl}) and i.deleted_at is null order by i.number")
    by = {}
    for e, n, sc, c in inc:
        by.setdefault(e, []).append((int(n), sc, int(c)))
    for g, base in gl.items():
        rows = by.get(g, [])
        per.setdefault(base, Counter())[len(rows)] += 1
        detail.append((lb, g, base, rows, ev.get(g)))
mode = {b: c.most_common(1)[0][0] for b, c in per.items()}
for lb, g, base, rows, e in detail:
    why = []
    if e is None: why.append("нет события")
    elif e[1] != "t": why.append("не обработано")
    if len(rows) != mode[base]: why.append(f"инцидентов {len(rows)}, у этого события в других пачках {mode[base]}")
    if any(c != 1 for _, _, c in rows): why.append("create не один")
    if len({sc for _, sc, _ in rows}) != len(rows): why.append("дубль сценария")
    if rows and e and e[0] != str(rows[0][0]): why.append(f"тревога {e[0]} ≠ номер {rows[0][0]}")
    if why: intake_bad.append((lb, g[-4:], why))
print(f"     на пачку инцидентов: {sum(mode.values())} (событий без инцидента: {sum(1 for v in mode.values() if v == 0)}, с двумя: {sum(1 for v in mode.values() if v == 2)})")
check(f"приём событий: пачек {len(labels)}, событий {len(labels)*len(evs)}, ошибок {len(intake_bad)} {intake_bad[:3]}",
      not intake_bad)
nums = [int(n) for (n,) in sql("select number from incidents where deleted_at is null")]
check(f"номера инцидентов не повторяются ({len(nums)})", len(nums) == len(set(nums)))

# 4. Журнал против успешных переходов.
incs = sorted({r["inc"] for r in outs})
if incs:
    inlist = ",".join("'%s'" % g for g in incs)
    jr = sql(f"select incident_guid, transition, count(*) from incident_journal where kind='transition' "
             f"and template_key <> 'workflow.journal.sibling_closed' and at >= to_timestamp({T0}) and at <= to_timestamp({T1}) and actor in ({','.join("'%s'" % v for v in ids.values())}) and incident_guid in ({inlist}) group by 1,2")
    journal = {(g, t): int(n) for g, t, n in jr}
    mine = Counter((r["inc"], r["tid"]) for r in outs if r["code"] == 200)
    diff = [(k, mine.get(k, 0), journal.get(k, 0)) for k in set(mine) | set(journal) if mine.get(k, 0) != journal.get(k, 0)]
    check(f"успешных переходов {sum(mine.values())} по {len(incs)} инцидентам, расхождений с журналом: {len(diff)} {diff[:3]}",
          not diff)

    # 5–6. Состояние, владелец, версия.
    rows = {g: (st, own, cb, ca, int(v)) for g, st, own, cb, ca, v in
            sql(f"select guid, state, coalesce(owner,''), coalesce(closed_by,''), coalesce(closed_at::text,''), version "
                f"from incidents where guid in ({inlist})")}
    wrong = []
    for g, (st, own, cb, ca, v) in rows.items():
        if st == "new" and own: wrong.append((g, st, "владелец есть"))
        if st in ("in_progress", "on_hold") and not own: wrong.append((g, st, "без владельца"))
        if st == "closed" and not (cb and ca): wrong.append((g, st, "нет closed_by/closed_at"))
    check(f"состояние и владелец согласованы ({len(rows)} инцидентов): ошибок {len(wrong)} {wrong[:3]}", not wrong)
    closed_by = {}
    for r in outs:
        if r["code"] == 200 and r["tid"] == "close":
            closed_by[r["inc"]] = ids[r["who"]]
    mism = [(g, w, rows.get(g)) for g, w in closed_by.items() if not rows.get(g) or rows[g][0] != "closed" or rows[g][2] != w]
    check(f"закрытых операторами {len(closed_by)}: в базе закрыты ими же — расхождений {len(mism)} {mism[:3]}", not mism)
    states = Counter(v[0] for v in rows.values())
    print("     состояния затронутых инцидентов:", dict(states))

print(f"итого FAIL: {fails}")
sys.exit(fails)
