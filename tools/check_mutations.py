#!/usr/bin/env python3
"""Проверка «правила только в машине»: мутации машины состояний меняют поведение прототипа.

Для каждой мутации: в копии прототипа меняется одно правило в workflow_schema.v1.json, и проба
(tools/mutations/probe.js) через интерфейс проверяет, что прототип ведёт себя по-новому.
Затем та же проба запускается на исходной машине и должна упасть. Если поведение не
изменилось — правило продублировано в коде прототипа, а не берётся из машины.

Запуск из корня репозитория: python3 tools/check_mutations.py [имя ...]
Мутации идут одновременно в несколько потоков, у каждой своя копия прототипа: --jobs=N (по умолчанию три
четверти ядер), --shard=K/M — K-я из M частей (tools/parallel.py).
Нужен google-chrome. Код выхода 1, если хоть одна мутация не прошла.
"""
import copy
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import parallel  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MACHINE = os.path.join(ROOT, "Specification", "Workflow_machine", "workflow_schema.v1.json")
PROBE = os.path.join(ROOT, "tools", "mutations", "probe.js")


def transition(w, tid):
    return next(t for t in w["transitions"] if t["id"] == tid)


def reaction_override(w, priority):
    timer = next(t for t in w["timers"] if t["id"] == "reaction")
    return next(o for o in timer["overrides"] if o.get("priority") == priority)


def hold_without_pause(w):
    hold = transition(w, "hold")
    hold["effects"] = [e for e in hold["effects"] if e["fn"] != "pauseTimer"]


def no_grace(w):
    """Пробы с нормативом в секунды ждут срабатывания сразу: окно после дедлайна (RULE-63) — 0"""
    w["invariants"]["manualWinsOverTimer"]["graceSec"] = 0


def short_resolution(w):
    no_grace(w)
    timer = next(t for t in w["timers"] if t["id"] == "resolution")
    timer["byPriority"] = {k: 2 for k in timer["byPriority"]}
    timer["overrides"] = []


def reaction_ceiling(w):
    no_grace(w)
    timer = next(t for t in w["timers"] if t["id"] == "reaction")
    timer["overrides"] = [{"sec": 2}]
    w["escalation"]["maxLevel"] = 0


def short_hold(w):
    no_grace(w)
    for item in w["reasonCatalogs"]["hold"]["items"]:
        item["maxMinutes"] = 0.03


def transfer_to_self(w):
    form = next(f for f in w["forms"] if f["id"] == "transfer")
    target = next(f for f in form["fields"] if f["name"] == "targetId")
    target["excludes"].remove("self")
    transition(w, "transfer")["guards"] = [g for g in transition(w, "transfer")["guards"] if g["fn"] != "targetIsNotSelf"]


def transfer_without_placeholder(w):
    form = next(f for f in w["forms"] if f["id"] == "transfer")
    del next(f for f in form["fields"] if f["name"] == "targetId")["placeholderKey"]


def fast_reaction(w, sec=3):
    """Реакция новых — несколько секунд: подняться по ступеням можно только автоэскалацией —
    ручная передача уровень не меняет (RULE-76)."""
    no_grace(w)
    next(t for t in w["timers"] if t["id"] == "reaction")["overrides"] = [{"sec": sec}]


def escalate_to_my_group(w):
    fast_reaction(w)
    for lvl in w["escalation"]["levels"]:
        lvl["reactionSec"] = 2
    w["escalation"]["levels"][1]["targetRef"] = "group:grp-leads"


def close_without_placeholder(w):
    form = next(f for f in w["forms"] if f["id"] == "close")
    del next(f for f in form["fields"] if f["name"] == "resultId")["placeholderKey"]


# Подписи — ключами, тексты — в каталоге строк (§14.9): мутация подписи меняет строку каталога
# (w["$strings"] — каталоги по языкам; run_probe пишет их в strings.js копии)
def ru(w, key, text):
    for lang in w["$strings"].values():
        lang[key] = text


def group_badge(w):
    rule = next(r for r in w["badges"]["rules"] if r.get("when", {}).get("addressee") == "group")
    ru(w, rule["labelKey"], "Группе на принятие")


def hold_with_unknown_effect(w):
    hold = transition(w, "hold")
    hold["effects"].append({"kind": "transactional", "fn": "teleport"})


def without_manual_transitions(w):
    w["transitions"] = [t for t in w["transitions"] if t["trigger"] != "manual"]
    w["navActions"]["items"] = []


# Имя пробы, что меняется в машине, сама мутация
MUTATIONS = [
    ("label", "название «Взять» → «Забрать»", lambda w: ru(w, transition(w, "claim")["labelKey"], "Забрать")),
    ("from", "«Отложить» ни из какого состояния", lambda w: transition(w, "hold").update({"from": []})),
    ("limit", "лимит активных: без ограничения → 1", lambda w: w["limits"].update(maxActive=1)),
    ("norm", "норматив реакции критического 4 → 10 мин", lambda w: reaction_override(w, 100).update(sec=600)),
    (
        "surfaces",
        "«Ложная тревога» предлагается и из очереди",
        lambda w: next(i for i in w["reasonCatalogs"]["close_result"]["items"] if i["id"] == "false_alarm").update(
            surfaces=["queue", "card"]
        ),
    ),
    ("filter", "фильтр «Мои» включает закрытые", lambda w: next(q for q in w["queueFilters"] if q["id"] == "mine")["states"].append("closed")),
    ("badge", "бейдж «Новое» → «Свежее»", lambda w: ru(w, next(b for b in w["badges"]["rules"] if b["state"] == "new")["labelKey"], "Свежее")),
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
        lambda w: (w["reasonCatalogs"]["hold"]["items"].append({"id": "probe", "labelKey": "workflow.catalog.hold.probe", "maxMinutes": 5, "setBy": "operator"}), ru(w, "workflow.catalog.hold.probe", "Проба")),
    ),
    ("merge_hides", "связанные события в списках не показываются", lambda w: next(s for s in w["states"] if s["id"] == "linked").update(category="pending")),
    ("merge_relink", "связанные прежнего основного не переходят к новому", lambda w: transition(w, "merge").update(effects=[e for e in transition(w, "merge")["effects"] if e["fn"] != "relinkToPrimary"])),
    ("merge_answers", "ответы сценария связанного основному не переносятся", lambda w: transition(w, "merge").update(effects=[e for e in transition(w, "merge")["effects"] if e["fn"] != "copyAnswersToPrimary"])),
    ("merge_no_tighten", "срок группы не сжимается: у основного остаётся свой", lambda w: transition(w, "merge").update(effects=[e for e in transition(w, "merge")["effects"] if e["fn"] != "tightenPrimaryDeadline"])),
    ("detach_own_deadline", "отсоединённый — со своим прежним сроком, а не с остатком группы", lambda w: transition(w, "detach").update(effects=[{"kind": "transactional", "fn": "pauseTimer", "args": ["resolution"]} if e["fn"] == "copyPrimaryDeadline" else e for e in transition(w, "detach")["effects"]])),
    ("merge_nav", "после «Взять в работу» на выборке — к очереди, а не в карточку", lambda w: transition(w, "merge")["ui"].update(navigate="queue")),
    ("merge_foreign", "объединить можно только ничьё или своё", lambda w: transition(w, "merge").update(guards=[g for g in transition(w, "merge")["guards"] if g["fn"] != "isOwnerOrUnowned"])),
    ("reopen_cursor", "«Переоткрыть» не ставит курсор сценария на текущий шаг", lambda w: transition(w, "reopen").update(effects=[e for e in transition(w, "reopen")["effects"] if e["fn"] != "setCursor"])),
    ("scenario", "править сценарий можно только в «Отложен»", lambda w: w["scenarioEdit"]["guards"].append({"fn": "stateIs", "args": [["on_hold"]]})),
    ("permission", "из каталога убрано право transfer:own", lambda w: w.update(permissions=[p for p in w["permissions"] if p["key"] != "incident:transfer:own"])),
    ("reopen", "срок переоткрытия 24 ч → 1 мин", lambda w: w["limits"].update(reopenWindowMin=1)),
    ("escalation", "реакция 3 с, норматив уровня 1: 120 → 30 с — после автоэскалации отсчёт по уровню", lambda w: (fast_reaction(w), w["escalation"]["levels"][0].update(reactionSec=30))),
    ("breakReason", "новая причина перерыва", lambda w: (w["session"]["breakReasons"].append({"id": "probe", "labelKey": "workflow.session.break.probe"}), ru(w, "workflow.session.break.probe", "Проба"))),
    ("effect", "«Отложить» не ставит норматив закрытия на паузу", hold_without_pause),
    ("empty", "убраны все ручные переходы и навигация", without_manual_transitions),
    ("ceiling", "норматив реакции 2 с, потолок эскалации 0 — нарушение реакции", reaction_ceiling),
    ("holdBreach", "предельный срок удержания ~2 с — нарушение удержания", short_hold),
    ("selfTarget", "передача себе и своей группе разрешена", transfer_to_self),
    ("groupTarget", "автоэскалация уровня 2 — на группу оператора: адресат — группа, принимает её участник", escalate_to_my_group),
    ("transferEmpty", "у адресата передачи нет placeholder — форма выбирает первого сама", transfer_without_placeholder),
    ("closeEmpty", "у результата закрытия нет placeholder — форма выбирает первый результат сама", close_without_placeholder),
    ("groupBadge", "бейдж передачи группе → «Группе на принятие»", group_badge),
    ("takeoverTarget", "«Перехватить» и адресату: переданное моей группе можно перехватить", lambda w: transition(w, "takeover").update(guards=[g for g in transition(w, "takeover")["guards"] if g["fn"] != "isNotTarget"])),
    ("readonlyTarget", "«Посмотреть» не адресату: переданное мне не посмотреть до «Принять»", lambda w: next(n for n in w["navActions"]["items"] if n["id"] == "view")["guards"].append({"fn": "isNotTarget"})),
    ("viewNew", "«Посмотреть» не у нового: новый не посмотреть, не взяв", lambda w: next(n for n in w["navActions"]["items"] if n["id"] == "view")["guards"][0]["args"][0].remove("new")),
    ("transferLevel", "«Передать» снова поднимает уровень эскалации", lambda w: transition(w, "transfer")["effects"].append({"kind": "transactional", "fn": "increment", "args": ["escalation_level"]})),
    ("transferRestarts", "«Передать» нового снова начинает реакцию заново: без ifStopped", lambda w: transition(w, "transfer")["effects"][[e["fn"] for e in transition(w, "transfer")["effects"]].index("startTimer")].update(args=["reaction", "byEscalationLevel"])),
    ("rejectRestarts", "«Отклонить» снова начинает реакцию заново", lambda w: (transition(w, "reject")["effects"].insert(0, {"kind": "transactional", "fn": "startTimer", "args": ["reaction"]}), next(t for t in w["timers"] if t["id"] == "reaction")["continuesOn"].remove("reject"))),
    ("atomic", "у «Отложить» эффект, которого исполнитель не знает: переход не применяется целиком", hold_with_unknown_effect),
    ("breach", "норматив закрытия 2 с — нарушение записывается", short_resolution),
    (
        "autoEscalation",
        "реакция 3 с, уровней 2 с — автоэскалация, открытая на просмотр карточка остаётся открытой",
        lambda w: (fast_reaction(w), [lvl.update(reactionSec=2) for lvl in w["escalation"]["levels"]]),
    ),
    ("reopenNorm", "норматив закрытия после переоткрытия 60 с", lambda w: w["limits"].update(reopenResolutionSec=60)),
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
    workflow = dict(workflow)
    strings = workflow.pop("$strings")
    with open(os.path.join(site, "workflow.js"), "w", encoding="utf-8") as f:
        f.write("window.IM_WORKFLOW = " + json.dumps(workflow, ensure_ascii=False) + ";\n")
    with open(os.path.join(site, "strings.js"), "w", encoding="utf-8") as f:
        f.write("window.IM_STRINGS = " + json.dumps(strings, ensure_ascii=False) + ";\n")
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
    only, jobs, shard, shards = parallel.options()
    with open(MACHINE, encoding="utf-8") as f:
        base = json.load(f)
    folder = os.path.join(os.path.dirname(MACHINE), "strings")
    base["$strings"] = {}
    for name in sorted(os.listdir(folder)):
        if name.endswith(".json"):
            with open(os.path.join(folder, name), encoding="utf-8") as f:
                base["$strings"][name[:-5]] = {k: v for k, v in json.load(f).items() if not k.startswith("$")}
    todo = parallel.part([m for m in MUTATIONS if not only or m[0] in only], shard, shards)
    with tempfile.TemporaryDirectory() as work:

        def check(n_mutation):
            # Своя папка на мутацию: копия прототипа и профиль Chrome не пересекаются с соседними потоками
            n, (probe, what, mutate) = n_mutation
            own = os.path.join(work, str(n))
            os.makedirs(own)
            mutated = copy.deepcopy(base)
            mutate(mutated)
            with_change = run_probe(own, probe, mutated)
            without = run_probe(own, probe, base)
            return what, with_change, without

        failed = 0
        with ThreadPoolExecutor(max_workers=jobs) as pool:
            # Результаты — в порядке списка мутаций, по мере готовности
            for what, with_change, without in pool.map(check, enumerate(todo)):
                ok = with_change.startswith("PASS") and without.startswith("FAIL")
                failed += not ok
                print(f"{'OK ' if ok else 'BAD'} {what}", flush=True)
                if not ok:
                    print(f"    с мутацией: {with_change}")
                    print(f"    на исходной машине: {without}")
    part = f" (часть {shard} из {shards})" if shards > 1 else ""
    print(f"Мутаций, не изменивших поведение прототипа: {failed} из {len(todo)}{part}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
