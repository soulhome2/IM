#!/usr/bin/env python3
"""Модель Quint (Specification/Workflow_machine/quint/im.qnt) не разошлась с машиной состояний.

Запуск из корня репозитория: python3 tools/check_quint.py
Проверяет: каждый переход машины либо смоделирован, либо назван в списке NOT_MODELED,
а у модели нет переходов, которых нет в машине; каждый смоделированный переход есть в step;
«откуда» и «куда» совпадают; условия перехода в модели — ровно условия машины, эффекты —
ровно эффекты машины (по таблицам GUARDS и EFFECTS ниже; журнал, уведомления и прочее,
чего модель не касается, — в IGNORED_*). Справочники: права, причины удержания, результаты
закрытия, уровни эскалации, состояния и таймеры. Условие или эффект, которого нет в
таблицах, — ошибка: таблицу надо дополнить, когда меняется машина.
Сам quint не запускает — это отдельно: quint test im_test.qnt; quint run im.qnt --invariant inv.
Код выхода 1, если есть расхождения.
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIR = os.path.join(ROOT, "Specification", "Workflow_machine")
MODEL = os.path.join(DIR, "quint", "im.qnt")

# Переходы машины, которых в модели пока нет
NOT_MODELED = {
    "system_hold_break", "system_hold_idle", "system_release_idle",
    "addressee_signed_out_to_group", "addressee_signed_out_to_queue", "owner_signed_out",
    "addressee_lost_access", "addressee_cannot_accept",
}
# Действия окружения в модели — не переходы машины
ENVIRONMENT = {"expire_reaction", "expire_resolution", "expire_hold", "expire_reopen_window",
               "scenario_answer"}  # ответ на шаг — не переход машины, права — scenarioEdit
NOT_MODELED_STATES = set()
NOT_MODELED_PERMS = {"incident:run_action", "incident:schema:admin", "agent:set_not_ready"}

STATES = {"New": "new", "Pending": "pending_acceptance", "InProgress": "in_progress",
          "OnHold": "on_hold", "Closed": "closed", "Linked": "linked"}

# Условия, которых модель не касается: все операторы ready
IGNORED_GUARDS = {"agentReady"}
# Эффекты, которых модель не касается
IGNORED_EFFECTS = {"appendLog", "notify", "externalCommand", "evictOpenCard", "returnToQueue", "setCursor"}
IGNORED_FLAGS = {"close_cause", "result"}

# Атомы условий в модели. Отрицание — раньше утверждения: re.finditer берёт первую подходящую альтернативу
ATOMS = [
    'not(cfg.escalationEnabled)', 'cfg.escalationEnabled',
    'not(escalationTargetAvailable(x, i))', 'escalationTargetAvailable(x, i)',
    'cfg.onResolutionOverdue == "alert"', 'cfg.onResolutionOverdue == "escalate"',
    'isDue(x.reaction)', 'isDue(x.resolution)', 'isDue(x.hold)',
    'transferPermitted(a, x)', 'withinActiveLimit(a, i)', 'withinHoldLimit(a, i)',
    'isTarget(a, x)', 'isMine(a, x)', 'ownership(a, x) != "owner"', 'ownership(a, x) != "target"',
    'not(isSelf(a, t))', 'hasAccess(t, i)', 'canAccept(t, i)',
    'closeResultAllowed(a, x, r, finished(x))', 'x.reopenOpen', 'sameScenarioAsPrimary(i, p)',
    'isOwnerOrUnowned(a, x)', 'mergePrimaryValid(a, i, p)', 'primaryEditable(a, x)', 'primaryClosed(x)',
    'primaryAddresseeLacksAccess(x, i)', 'targetHasAccessToLinked(t, i)',
]
ATOM_RE = re.compile(r'can\(a, "[^"]+"\)|' + "|".join(re.escape(a) for a in ATOMS))

FIELDS = {"owner", "group", "holdReason", "level", "closeResult", "closedBy", "reopenOpen",
          "transfers", "reaction", "resolution", "hold", "breaches", "linkedTo", "answered"}


def guard_atom(g):
    """Условие машины → атом модели; None — модель его не касается; KeyError — нет в таблице."""
    fn, args = g["fn"], g.get("args", [])
    if fn in IGNORED_GUARDS:
        return None
    if fn == "hasPermission":
        return f'can(a, "{args[0]}")'
    if fn == "settingEnabled" and args == ["escalation.enabled"]:
        return "cfg.escalationEnabled"
    if fn == "settingIs" and args == ["escalation.enabled", False]:
        return "not(cfg.escalationEnabled)"
    if fn == "settingIs" and args[0] == "escalation.onResolutionOverdue":
        return f'cfg.onResolutionOverdue == "{args[1]}"'
    if fn == "timerExpired":
        return f"isDue(x.{args[0]})"
    if fn == "primaryAddresseeHasAccess" and args == [False]:
        return "primaryAddresseeLacksAccess(x, i)"
    if fn == "escalationTargetAvailable":
        return "escalationTargetAvailable(x, i)" if args[0] else "not(escalationTargetAvailable(x, i))"
    return {
        "hasScopedPermission": "transferPermitted(a, x)",
        "withinActiveLimit": "withinActiveLimit(a, i)",
        "withinHoldLimit": "withinHoldLimit(a, i)",
        "isTarget": "isTarget(a, x)",
        "isOwner": "isMine(a, x)",
        "isNotOwner": 'ownership(a, x) != "owner"',
        "isNotTarget": 'ownership(a, x) != "target"',
        "targetIsNotSelf": "not(isSelf(a, t))",
        "targetHasAccess": "hasAccess(t, i)",
        "targetCanAccept": "canAccept(t, i)",
        "closeResultAllowed": "closeResultAllowed(a, x, r, finished(x))",
        "sameScenarioAsPrimary": "sameScenarioAsPrimary(i, p)",
        "withinReopenWindow": "x.reopenOpen",
        "isOwnerOrUnowned": "isOwnerOrUnowned(a, x)",
        "mergePrimaryValid": "mergePrimaryValid(a, i, p)",
        "primaryEditable": "primaryEditable(a, x)",
        "primaryClosed": "primaryClosed(x)",
        "targetHasAccessToLinked": "targetHasAccessToLinked(t, i)",
    }[fn]


def effect_token(e):
    """Эффект машины → (поле, начало присваивания в модели) или список таких; None — модель его не касается."""
    fn, args = e["fn"], e.get("args", [])
    if fn in IGNORED_EFFECTS:
        return None
    arg = args[0] if args else None
    if fn == "setOwner":
        if arg is None:
            return "owner", "owner: NOBODY"
        if arg == "actor":
            return "owner", "owner: a"
        if str(arg).endswith(".ifPerson"):
            return "owner", "owner: if (isGroup("
    if fn == "setAssignmentGroup":
        if arg is None:
            return "group", "group: NOBODY"
        if str(arg).endswith(".ifGroup"):
            return "group", "group: if (isGroup("
    if fn == "setHoldReason" and arg == "form.reasonId":
        return "holdReason", "holdReason: reason"
    if fn == "clearHoldReason":
        return "holdReason", "holdReason: NOBODY"
    if fn == "startTimer" and arg in ("reaction", "hold"):
        return arg, f"{arg}: startIfStopped(" if "ifStopped" in args else f"{arg}: startT("
    if fn == "stopTimer" and arg in ("reaction", "hold"):
        return arg, f"{arg}: stopT("
    if fn == "pauseTimer" and arg == "resolution":
        return arg, "resolution: pauseT("
    if fn == "resumeTimer" and args == ["resolution"]:
        return arg, "resolution: resumeT("
    if fn == "restartTimer" and arg == "resolution":
        return arg, "resolution: restartT("
    if fn == "recordBreach" and len(args) == 1:
        return "breaches", f'breaches: breach(x, "{arg}")'
    if fn in ("setLinkedTo", "relinkToPrimary"):
        return "linkedTo", "linkedTo: p"
    if fn == "clearLink":
        return "linkedTo", "linkedTo: NOBODY"
    # Срок группы (RULE-97): в абстрактном времени сжатие не видно — tightenT, но эффект на месте
    if fn == "tightenPrimaryDeadline" and arg == "resolution":
        return "resolution", "tightenT("
    if fn == "copyPrimaryDeadline" and arg == "resolution":
        return "resolution", "resolution: copyPrimaryT("
    if fn == "copyAnswersToPrimary":
        return "answered", "answered: mergedAnswers("
    if fn == "copyCloseFromPrimary":
        return [("closeResult", "closeResult: px.closeResult"), ("closedBy", "closedBy: px.closedBy")]
    if fn == "increment" and args == ["transfer_count"]:
        return "transfers", "transfers: x.transfers + 1"
    if fn == "setFlag":
        flag, val = args
        if flag in IGNORED_FLAGS:
            return None
        if flag == "escalation_level":
            return "level", "level: 0" if val == 0 else "level: l.level"
        if flag == "closed_by" and val == "actor":
            return "closedBy", "closedBy: a"
        if flag == "close_result":
            return "closeResult", "closeResult: r.id" if val == "form.resultId" else "closeResult: NOBODY"
        if flag == "closed_at":
            return "reopenOpen", "reopenOpen: true"
    raise KeyError(f"{fn} {args}")


def strip_comments(text):
    return re.sub(r"//[^\n]*", "", text)


def blocks(src, kind):
    """Определения верхнего уровня модуля: имя → текст до закрывающей «  }»."""
    out = {}
    for m in re.finditer(rf"^  {kind} (\w+)\b[^\n]*\{{\n(.*?)^  \}}\n", src, re.S | re.M):
        out[m.group(1)] = m.group(2)
    return out


def states_in(text):
    m = re.search(r"x\.state\.in\(Set\(([^)]*)\)\)", text)
    if m:
        return {STATES[s.strip()] for s in m.group(1).split(",")}
    m = re.search(r"x\.state == (\w+)", text)
    if m:
        return {STATES[m.group(1)]}
    return set()


def pure_set(src, name):
    m = re.search(rf"pure val {name} = Set\((.*?)\n?\s*\)\n", src, re.S)
    return set(re.findall(r'"([^"]+)"', m.group(1))) if m else set()


def check_transitions(w, src, err):
    machine = {t["id"]: t for t in w["transitions"]}
    actions = blocks(src, "action")
    defs = blocks(src, "def")
    step = actions.get("step", "")
    modeled = {}
    for name, body in actions.items():
        m = re.search(r'apply(?:All|Shared)?\("(\w+)"', body)
        if m and m.group(1) not in ENVIRONMENT:
            modeled[m.group(1)] = (name, body)

    for tid in sorted(set(machine) - set(modeled) - NOT_MODELED):
        err.append(f"переход {tid}: нет в модели и нет в NOT_MODELED")
    for tid in sorted(set(modeled) - set(machine)):
        err.append(f"модель: переход {tid} — нет в машине")
    for tid in sorted(NOT_MODELED - set(machine)):
        err.append(f"NOT_MODELED: {tid} — нет в машине")
    for tid in sorted(NOT_MODELED & set(modeled)):
        err.append(f"NOT_MODELED: {tid} уже смоделирован — убрать из списка")

    for tid, (name, body) in sorted(modeled.items()):
        if tid not in machine:
            continue
        t = machine[tid]
        if not re.search(rf"\b{name}\(", step):
            err.append(f"переход {tid}: действия {name} нет в step")
        guard = defs.get(f"{name}Ok")
        gtext = strip_comments(guard if guard is not None else body)
        # Откуда; у create — из «ещё не создан»
        frm = set() if "state == Absent" in gtext else states_in(gtext)
        if frm != set(t["from"]):
            err.append(f"переход {tid}: откуда в модели {sorted(frm)}, в машине {sorted(t['from'])}")
        # Куда
        to = re.search(r"(?:^|[{,])\s*state: (\w+)", body, re.M)
        to = STATES[to.group(1)] if to else None
        if to != t["to"]:
            err.append(f"переход {tid}: куда в модели {to}, в машине {t['to']}")
        # Условия — в обе стороны
        expected = set()
        for g in t.get("guards", []):
            try:
                a = guard_atom(g)
            except KeyError:
                err.append(f"переход {tid}: условию {g['fn']} {g.get('args', [])} нет соответствия в check_quint.py")
                continue
            if a:
                expected.add(a)
        found = set(ATOM_RE.findall(gtext))
        for a in sorted(expected - found):
            err.append(f"переход {tid}: в модели нет условия {a}")
        for a in sorted(found - expected):
            err.append(f"переход {tid}: в модели лишнее условие {a}")
        # Эффекты — в обе стороны
        ebody = strip_comments(body)
        covered = set()
        timer = next((g["args"][0] for g in t.get("guards", []) if g["fn"] == "timerExpired"), None)
        if timer:
            covered.add(timer)  # markFired — отметка сработавшего дедлайна
        for e in t.get("effects", []):
            try:
                tok = effect_token(e)
            except KeyError:
                err.append(f"переход {tid}: эффекту {e['fn']} {e.get('args', [])} нет соответствия в check_quint.py")
                continue
            if not tok:
                continue
            for field, text in tok if isinstance(tok, list) else [tok]:
                covered.add(field)
                if text not in ebody:
                    err.append(f"переход {tid}: в модели нет эффекта «{text}…» ({e['fn']} {e.get('args', [])})")
        # Видимость (§5, invariants.actorSeesIncident): ручное действие — только над видимым инцидентом
        if w.get("invariants", {}).get("actorSeesIncident") and t["trigger"] == "manual" and "sees(a, i)" not in gtext:
            err.append(f"переход {tid}: нет видимости sees(a, i) — invariants.actorSeesIncident")
        # Нарушение основного — и каждому открытому привязанному (recordBreach, RULE-97)
        if any(e["fn"] == "recordBreach" for e in t.get("effects", [])) and "applyShared(" not in ebody:
            err.append(f"переход {tid}: нарушение не записывается привязанным — нужен applyShared")
        assigned = set(re.findall(r"(?:^|[{,])\s*(\w+): ", ebody, re.M)) & FIELDS
        for f in sorted(assigned - covered):
            err.append(f"переход {tid}: модель меняет {f}, а в машине такого эффекта нет")


def check_scenario_edit(w, src, err):
    """Право отвечать на шаги (scenarioEdit машины) — условие answerOk модели."""
    body = strip_comments(blocks(src, "def").get("answerOk", ""))
    if not body:
        err.append("модель: нет answerOk — ответа на шаг сценария")
        return
    want = {"stateIs": lambda a: " or ".join(f"x.state == {k}" for k, v in STATES.items() if v in a[0]), "isOwner": lambda a: "isMine(a, x)"}
    for g in w["scenarioEdit"]["guards"]:
        if g["fn"] in IGNORED_GUARDS:
            continue
        if g["fn"] not in want:
            err.append(f"scenarioEdit: условию {g['fn']} нет соответствия в check_quint.py")
        elif want[g["fn"]](g.get("args", [])) not in body:
            err.append(f"scenarioEdit: в answerOk нет «{want[g['fn']](g.get('args', []))}» ({g['fn']})")


def check_catalogs(w, src, err):
    perms = {p["key"] for p in w["permissions"]} - NOT_MODELED_PERMS
    model = pure_set(src, "PERMS")
    if model != perms:
        err.append(f"права: в модели лишние {sorted(model - perms)}, нет {sorted(perms - model)}")

    hold = {i["id"] for i in w["reasonCatalogs"]["hold"]["items"] if i.get("setBy") == "operator"}
    model = pure_set(src, "HOLD_REASONS")
    if model != hold:
        err.append(f"причины удержания: в модели {sorted(model)}, в машине (setBy: operator) {sorted(hold)}")

    rows = {}
    for m in re.finditer(r'\{ id: "(\w+)", perm: "([^"]+)", from: Set\(([^)]*)\), ownerOnly: Set\(([^)]*)\), steps: (true|false) \}', src):
        conv = lambda s: {STATES[x.strip()] for x in s.split(",") if x.strip()}
        rows[m.group(1)] = (m.group(2), conv(m.group(3)), conv(m.group(4)), m.group(5) == "true")
    for item in w["reasonCatalogs"]["close_result"]["items"]:
        rid = item["id"]
        if rid not in rows:
            err.append(f"результат {rid}: нет в CLOSE_RESULTS модели")
            continue
        perm, frm, own, steps = rows.pop(rid)
        if perm != item["permission"]:
            err.append(f"результат {rid}: право в модели {perm}, в машине {item['permission']}")
        if frm != set(item["fromStates"]):
            err.append(f"результат {rid}: fromStates в модели {sorted(frm)}, в машине {sorted(item['fromStates'])}")
        if own != set(item["ownerOnlyInStates"]):
            err.append(f"результат {rid}: ownerOnlyInStates в модели {sorted(own)}, в машине {sorted(item['ownerOnlyInStates'])}")
        if steps != (item["requiredStepSet"] != "none"):
            err.append(f"результат {rid}: шаги в модели {steps}, в машине {item['requiredStepSet']}")
    for rid in rows:
        err.append(f"результат {rid}: есть в модели, нет в машине")

    esc = w["escalation"]
    m = re.search(r"pure val MAX_LEVEL = (\d+)", src)
    if not m or int(m.group(1)) != esc["maxLevel"]:
        err.append(f"эскалация: MAX_LEVEL в модели {m and m.group(1)}, maxLevel в машине {esc['maxLevel']}")
    levels = [int(x) for x in re.findall(r"\{ level: (\d+), target:", src)]
    if levels != [l["level"] for l in esc["levels"]]:
        err.append(f"эскалация: уровни в модели {levels}, в машине {[l['level'] for l in esc['levels']]}")

    m = re.search(r"type State = ([^\n]+)", src)
    model = {STATES[s.strip()] for s in m.group(1).split("|") if s.strip() != "Absent"} if m else set()
    machine = {s["id"] for s in w["states"]} - NOT_MODELED_STATES
    if model != machine:
        err.append(f"состояния: в модели {sorted(model)}, в машине {sorted(machine)}")
    for s in NOT_MODELED_STATES & model:
        err.append(f"NOT_MODELED_STATES: {s} уже смоделировано — убрать из списка")

    timers = {t["id"] for t in w["timers"]}
    model = set(re.findall(r"^\s+(reaction|resolution|hold): Timer,", src, re.M))
    if model != timers:
        err.append(f"таймеры: в модели {sorted(model)}, в машине {sorted(timers)}")


def main():
    with open(os.path.join(DIR, "workflow_schema.v1.json"), encoding="utf-8") as f:
        w = json.load(f)
    with open(MODEL, encoding="utf-8") as f:
        src = f.read()
    err = []
    check_transitions(w, src, err)
    check_scenario_edit(w, src, err)
    check_catalogs(w, src, err)
    for e in err:
        print(e)
    print(f"Расхождений модели Quint с машиной: {len(err)}")
    return 1 if err else 0


if __name__ == "__main__":
    sys.exit(main())
