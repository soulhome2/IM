#!/usr/bin/env python3
"""Проверка «правила только в машине»: мутации машины состояний меняют поведение прототипа.

Для каждой мутации: в копии прототипа меняется одно правило в workflow.v4.json, и проба
(tools/mutations/probe.js) через интерфейс проверяет, что прототип ведёт себя по-новому.
Затем та же проба запускается на исходной машине и должна упасть. Если поведение не
изменилось — правило продублировано в коде прототипа, а не берётся из машины.

Запуск из корня репозитория: python3 tools/check_mutations.py [имя ...]
Нужен google-chrome. Около полутора минут. Код выхода 1, если хоть одна мутация не прошла.
"""
import copy
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MACHINE = os.path.join(ROOT, "Specification", "State_machine", "workflow.v4.json")
PROBE = os.path.join(ROOT, "tools", "mutations", "probe.js")


def transition(w, tid):
    return next(t for t in w["transitions"] if t["id"] == tid)


def reaction_override(w, priority):
    timer = next(t for t in w["timers"] if t["id"] == "reaction")
    return next(o for o in timer["overrides"] if o.get("priority") == priority)


def hold_without_pause(w):
    hold = transition(w, "hold")
    hold["effects"] = [e for e in hold["effects"] if e["fn"] != "pauseTimer"]


def short_resolution(w):
    timer = next(t for t in w["timers"] if t["id"] == "resolution")
    timer["byPriority"] = {k: 2 for k in timer["byPriority"]}
    timer["overrides"] = []


def reaction_ceiling(w):
    timer = next(t for t in w["timers"] if t["id"] == "reaction")
    timer["overrides"] = [{"sec": 2}]
    w["escalation"]["maxLevel"] = 0


def short_hold(w):
    for item in w["reasonCatalogs"]["hold"]["items"]:
        item["maxMinutes"] = 0.03


def transfer_to_self(w):
    form = next(f for f in w["forms"] if f["id"] == "transfer")
    target = next(f for f in form["fields"] if f["name"] == "targetId")
    target["excludes"].remove("self")
    transition(w, "transfer")["guards"] = [g for g in transition(w, "transfer")["guards"] if g["fn"] != "targetIsNotSelf"]


def escalate_to_my_group(w):
    for lvl in w["escalation"]["levels"]:
        lvl["reactionSec"] = 2
    w["escalation"]["levels"][1]["targetRef"] = "group:grp-leads"


def hold_with_unknown_effect(w):
    hold = transition(w, "hold")
    hold["effects"].append({"kind": "transactional", "fn": "teleport"})


def without_manual_transitions(w):
    w["transitions"] = [t for t in w["transitions"] if t["trigger"] != "manual"]
    w["navActions"]["items"] = []


# Имя пробы, что меняется в машине, сама мутация
MUTATIONS = [
    ("label", "название «Взять» → «Забрать»", lambda w: transition(w, "claim").update(label="Забрать")),
    ("from", "«Отложить» ни из какого состояния", lambda w: transition(w, "hold").update({"from": []})),
    ("limit", "лимит активных 1 → 2", lambda w: w["limits"].update(maxActive=2)),
    ("norm", "норматив реакции критического 4 → 10 мин", lambda w: reaction_override(w, "critical").update(sec=600)),
    (
        "surfaces",
        "«Ложная тревога» предлагается и из очереди",
        lambda w: next(i for i in w["reasonCatalogs"]["close_result"]["items"] if i["id"] == "false_alarm").update(
            surfaces=["queue", "card"]
        ),
    ),
    ("hotkey", "клавиша «Взять» N → M", lambda w: next(h for h in w["hotkeys"] if h["key"] == "N").update(key="M")),
    ("filter", "фильтр «Мои» включает закрытые", lambda w: next(q for q in w["queueFilters"] if q["id"] == "mine")["states"].append("closed")),
    ("badge", "бейдж «Новое» → «Свежее»", lambda w: next(b for b in w["badges"]["rules"] if b["state"] == "new").update(label="Свежее")),
    (
        "form",
        "причина «Вернуть в очередь» не обязательна",
        lambda w: next(f for f in next(f for f in w["forms"] if f["id"] == "release")["fields"] if f["name"] == "comment").update(
            required=False
        ),
    ),
    (
        "catalog",
        "новая причина удержания",
        lambda w: w["reasonCatalogs"]["hold"]["items"].append({"id": "probe", "label": "Проба", "maxMinutes": 5, "setBy": "operator"}),
    ),
    ("grouping", "группа сценария из разных типов событий", lambda w: w["grouping"]["createFrom"].update(sameEventType=False)),
    ("scenario", "править сценарий можно только в «Отложен»", lambda w: w["scenarioEdit"]["guards"].append({"fn": "stateIs", "args": [["on_hold"]]})),
    ("permission", "из каталога убрано право transfer:own", lambda w: w.update(permissions=[p for p in w["permissions"] if p["key"] != "incident:transfer:own"])),
    ("reopen", "срок переоткрытия 24 ч → 1 мин", lambda w: w["limits"].update(reopenWindowMin=1)),
    ("escalation", "норматив реакции уровня 1: 120 → 30 с", lambda w: w["escalation"]["levels"][0].update(reactionSec=30)),
    ("escape", "Esc без шага «к очереди»", lambda w: next(h for h in w["hotkeys"] if h["key"] == "Esc")["chain"].remove("back_to_queue")),
    ("breakReason", "новая причина перерыва", lambda w: w["session"]["breakReasons"].append({"id": "probe", "label": "Проба"})),
    ("effect", "«Отложить» не ставит норматив закрытия на паузу", hold_without_pause),
    ("empty", "убраны все ручные переходы и навигация", without_manual_transitions),
    ("ceiling", "норматив реакции 2 с, потолок эскалации 0 — нарушение реакции", reaction_ceiling),
    ("holdBreach", "предельный срок удержания ~2 с — нарушение удержания", short_hold),
    ("selfTarget", "передача себе и своей группе разрешена", transfer_to_self),
    ("groupTarget", "автоэскалация уровня 2 — на группу оператора: адресат — группа, принимает её участник", escalate_to_my_group),
    ("atomic", "у «Отложить» эффект, которого исполнитель не знает: переход не применяется целиком", hold_with_unknown_effect),
    ("breach", "норматив закрытия 2 с — нарушение записывается", short_resolution),
    (
        "autoEscalation",
        "норматив реакции уровней 2 с — автоэскалация, открытая карточка остаётся просмотром",
        lambda w: [lvl.update(reactionSec=2) for lvl in w["escalation"]["levels"]],
    ),
    ("reopenNorm", "норматив закрытия после переоткрытия 60 с", lambda w: w["limits"].update(reopenResolutionSec=60)),
    (
        "exclude",
        "исключение из группы без проверки лимита",
        lambda w: w["grouping"].update(excludeGuards=[g for g in w["grouping"]["excludeGuards"] if g["fn"] != "withinActiveLimit"]),
    ),
]


def run_probe(work, probe, workflow):
    """Собирает копию прототипа с данной машиной и пробой, возвращает строку результата пробы."""
    site = os.path.join(work, "prototype")
    shutil.rmtree(site, ignore_errors=True)
    shutil.copytree(os.path.join(ROOT, "prototype"), site)
    shutil.copy(PROBE, os.path.join(site, "probe.js"))
    page = os.path.join(site, "index.html")
    with open(page, encoding="utf-8") as f:
        html = f.read()
    html = html.replace('<script src="selftest.js"></script>', '<script src="selftest.js"></script>\n  <script src="probe.js"></script>')
    with open(page, "w", encoding="utf-8") as f:
        f.write(html)
    with open(os.path.join(site, "workflow.js"), "w", encoding="utf-8") as f:
        f.write("window.IM_WORKFLOW = " + json.dumps(workflow, ensure_ascii=False) + ";\n")
    profile = os.path.join(work, "chrome")
    shutil.rmtree(profile, ignore_errors=True)
    out = subprocess.run(
        [
            "google-chrome",
            "--headless=new",
            "--disable-gpu",
            "--no-sandbox",
            "--no-first-run",
            f"--user-data-dir={profile}",
            "--virtual-time-budget=8000",
            "--dump-dom",
            f"file://{page}?probe={probe}",
        ],
        capture_output=True,
        text=True,
    ).stdout
    m = re.search(r'<pre id="probe">(.*?)</pre>', out, re.S)
    return m.group(1) if m else "FAIL нет результата пробы"


def main():
    only = sys.argv[1:]
    with open(MACHINE, encoding="utf-8") as f:
        base = json.load(f)
    failed = 0
    total = 0
    with tempfile.TemporaryDirectory() as work:
        for probe, what, mutate in MUTATIONS:
            if only and probe not in only:
                continue
            total += 1
            mutated = copy.deepcopy(base)
            mutate(mutated)
            with_change = run_probe(work, probe, mutated)
            without = run_probe(work, probe, base)
            ok = with_change.startswith("PASS") and without.startswith("FAIL")
            failed += not ok
            print(f"{'OK ' if ok else 'BAD'} {what}")
            if not ok:
                print(f"    с мутацией: {with_change}")
                print(f"    на исходной машине: {without}")
    print(f"Мутаций, не изменивших поведение прототипа: {failed} из {total}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
