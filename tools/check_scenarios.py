#!/usr/bin/env python3
"""Проверка машины сценариев: сценарии проходят схему DSL v1 и смысловые проверки, стык с машиной
инцидента цел.

Запуск из корня репозитория: python3 tools/check_scenarios.py
Нужен пакет jsonschema (в CI ставится в checks.yml). Проверяет:
- примеры Specification/Scenario_machine/examples/ — схему и смысл; отрицательные примеры A5 — что их
  отвергает то, что должно (README машины сценариев, «Примеры»);
- сценарии эталонного набора (fixtures/demo.json → scenarios.rows) — то же и профиль МИ: нет escalate и assign,
  metadata совпадает с guid и версией строки, у типа события — существующий сценарий, прогоны инцидентов ссылаются
  на сценарий своего типа события, существующую версию и её шаги;
- стык: наборы обязательных шагов, на которые ссылается workflow.v4.json, есть в профиле МИ.
Смысл (спецификация, раздел 11, уровень 2): initialStepId и goto ведут на существующие шаги, у каждого шага
есть переходы, id шагов и вариантов не повторяются, нет недостижимых шагов и шагов, откуда не дойти до finish,
в условиях — только операторы из белого списка (раздел 7), var — на существующие шаги.
Код выхода 1, если есть ошибки.
"""
import json
import os
import sys
from collections import Counter

try:
    import jsonschema
except ImportError:
    print("Нужен пакет jsonschema: pip install jsonschema")
    sys.exit(1)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MACHINE = os.path.join(ROOT, "Specification", "Scenario_machine")
EXAMPLES = os.path.join(MACHINE, "examples")
WORKFLOW = os.path.join(ROOT, "Specification", "State_machine", "workflow.v4.json")
FIXTURE = os.path.join(ROOT, "Specification", "State_machine", "fixtures", "demo.json")

# Белый список JSONLogic (спецификация, раздел 7)
OPERATORS = {"var", "==", "!=", ">", ">=", "<", "<=", "and", "or", "!", "if", "in", "none", "some", "all", "missing", "missing_some"}
ARRAY_OPERATORS = {"none", "some", "all"}
STATE_FIELDS = {"value", "answeredAt", "by", "skipped"}
# Наборы обязательных шагов профиля МИ (README машины сценариев, решение ARCH-06 в5); byCloseResult —
# не набор, а «по результату закрытия»: набор берётся из справочника результатов
PROFILE_SETS = {"closing", "none"}
NOT_EXECUTED = {"escalate", "assign"}

# Чего ждать от примеров A5 (README машины сценариев, «Примеры»): schema — отвергает схема, meaning — смысловая проверка
EXPECTED = {
    "architecture/A5-anti-patterns/bad-1-schema-broken-goto.json": "meaning",
    "architecture/A5-anti-patterns/bad-3-unknown-action.json": "schema",
}


def load(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def outcomes(step):
    t = step.get("transitions")
    if not t:
        return []
    return list(t.get("rules", [])) + ([t["default"]] if "default" in t else [])


def has_finish(outcome):
    return any(a.get("type") == "finish" for a in outcome.get("actions", []))


def check_logic(expr, steps, where, err, item_scope=False):
    """Операторы — из белого списка; var — на шаги сценария (кроме var элемента внутри some/all/none)."""
    if isinstance(expr, list):
        for x in expr:
            check_logic(x, steps, where, err, item_scope)
        return
    if not isinstance(expr, dict):
        return
    for op, args in expr.items():
        if op not in OPERATORS:
            err.append(f"{where}: оператор {op} не из белого списка")
            continue
        if op == "var":
            name = args[0] if isinstance(args, list) and args else args
            if item_scope or name in ("", None):
                continue
            parts = str(name).split(".")
            if parts[0] != "state" or len(parts) < 2 or parts[1] not in steps or (len(parts) > 2 and parts[2] not in STATE_FIELDS):
                err.append(f"{where}: var {name} — не ответ на шаг сценария")
            continue
        if op in ("missing", "missing_some"):
            keys = args[-1] if op == "missing_some" and isinstance(args, list) else args
            for key in keys if isinstance(keys, list) else [keys]:
                if isinstance(key, str):
                    check_logic({"var": key}, steps, where, err, item_scope)
            continue
        if op in ARRAY_OPERATORS and isinstance(args, list) and len(args) == 2:
            check_logic(args[0], steps, where, err, item_scope)
            check_logic(args[1], steps, where, err, True)
            continue
        check_logic(args, steps, where, err, item_scope)


def meaning(script, name):
    """Смысловые проверки сценария (спецификация, раздел 11, уровень 2)."""
    err = []
    steps = {s["id"]: s for s in script["steps"]}
    for sid in [k for k, n in Counter(s["id"] for s in script["steps"]).items() if n > 1]:
        err.append(f"{name}: шаг {sid} повторяется")
    if script["initialStepId"] not in steps:
        err.append(f"{name}: начального шага {script['initialStepId']} нет")
    for s in script["steps"]:
        where = f"{name}: шаг {s['id']}"
        ids = [o["id"] for o in s["view"].get("options", [])]
        for oid in [k for k, n in Counter(ids).items() if n > 1]:
            err.append(f"{where}: вариант {oid} повторяется")
        if "transitions" not in s:
            err.append(f"{where}: нет переходов")
        for i, o in enumerate(outcomes(s)):
            if o.get("goto") and o["goto"] not in steps:
                err.append(f"{where}: переход на несуществующий шаг {o['goto']}")
            if "when" in o:
                check_logic(o["when"], steps, f"{where}, правило {i}", err)
    if err or script["initialStepId"] not in steps:
        return err
    # Достижимость из начального и выход к finish из каждого достижимого
    edges = {sid: {o["goto"] for o in outcomes(s) if o.get("goto") and o["goto"] != sid and not has_finish(o)} for sid, s in steps.items()}
    finishing = {sid for sid, s in steps.items() if any(has_finish(o) for o in outcomes(s))}
    seen, queue = {script["initialStepId"]}, [script["initialStepId"]]
    while queue:
        for nxt in edges[queue.pop()]:
            if nxt not in seen:
                seen.add(nxt)
                queue.append(nxt)
    for sid in steps:
        if sid not in seen:
            err.append(f"{name}: шаг {sid} недостижим из начального")
    exits = set(finishing)
    changed = True
    while changed:
        changed = False
        for sid in steps:
            if sid not in exits and edges[sid] & exits:
                exits.add(sid)
                changed = True
    for sid in sorted(seen - exits):
        err.append(f"{name}: из шага {sid} не дойти до finish")
    return err


def verdict(validator, script, name):
    """Что не так со сценарием: (ошибки схемы, смысловые ошибки)."""
    schema = [f"{name}: {'/'.join(map(str, e.absolute_path)) or '(корень)'}: {e.message[:160]}" for e in validator.iter_errors(script)]
    return schema, ([] if schema else meaning(script, name))


def check_examples(validator, err):
    count = 0
    for base, dirs, files in os.walk(EXAMPLES):
        dirs.sort()
        for file in sorted(files):
            if not file.endswith(".json"):
                continue
            name = os.path.relpath(os.path.join(base, file), EXAMPLES).replace(os.sep, "/")
            schema, sense = verdict(validator, load(os.path.join(base, file)), f"examples/{name}")
            expected = EXPECTED.get(name)
            if expected == "schema" and not schema:
                err.append(f"examples/{name}: схема должна отвергать этот пример")
            elif expected == "meaning" and (schema or not sense):
                err.append(f"examples/{name}: этот пример должна отвергать смысловая проверка, а не схема")
            elif not expected:
                err += schema + sense
            count += 1
    return count


def check_fixture(validator, err):
    """Сценарии эталонного набора (scenarios.rows — строки как на сервере) и прогоны инцидентов."""
    fx = load(FIXTURE)
    rows = fx["scenarios"]["rows"]
    versions = {}
    for row in rows:
        name = f"набор: сценарий {row.get('guid')} v{row.get('version')}"
        script = row.get("script") or {}
        schema, sense = verdict(validator, script, name)
        err += schema + sense
        meta = script.get("metadata", {})
        if (meta.get("scenarioGuid"), meta.get("version")) != (row.get("guid"), row.get("version")):
            err.append(f"{name}: metadata.scenarioGuid и version не совпадают со строкой")
        for s in script.get("steps", []):
            for o in outcomes(s):
                for a in o.get("actions", []):
                    if a.get("type") in NOT_EXECUTED:
                        err.append(f"{name}: шаг {s['id']} — действие {a['type']} в МИ не исполняется (профиль МИ)")
        key = (row.get("guid"), row.get("version"))
        if key in versions:
            err.append(f"{name}: версия повторяется")
        versions[key] = {s["id"] for s in script.get("steps", [])}
    by_type = fx["scenarios"]["byEventType"]
    for type_id, guid in by_type.items():
        if not any(g == guid for g, _ in versions):
            err.append(f"набор: у типа события {type_id} сценарий {guid}, которого нет")
    for inc in fx.get("incidents", []):
        key = (inc.get("scenarioGuid"), inc.get("scenarioVersion"))
        if by_type.get(inc["eventType"]["id"]) != key[0]:
            err.append(f"набор: инцидент {inc.get('number')} — сценарий не тот, что у его типа события")
        if key not in versions:
            err.append(f"набор: инцидент {inc.get('number')} — нет сценария {key[0]} версии {key[1]}")
            continue
        result = inc.get("scenarioResult") or {}
        for sid in result.get("state", {}):
            if sid not in versions[key]:
                err.append(f"набор: инцидент {inc.get('number')} — ответ на шаг {sid}, которого нет в его версии")
        current = result.get("currentStepId")
        if current is not None and current not in versions[key]:
            err.append(f"набор: инцидент {inc.get('number')} — текущий шаг {current} не из его версии")


def check_junction(err):
    """Наборы обязательных шагов, на которые ссылается машина инцидента, есть в профиле МИ."""
    w = load(WORKFLOW)
    declared = {k for k in w["stepSets"] if not k.startswith("$")}
    for k in declared - PROFILE_SETS:
        err.append(f"workflow.v4.json: набор {k} — в профиле МИ такого нет (README машины сценариев)")
    used = set()

    def walk(node):
        if isinstance(node, dict):
            for k, v in node.items():
                if k in ("requiredStepSet", "requiredStepsFilled") and isinstance(v, str):
                    used.add(v)
                walk(v)
        elif isinstance(node, list):
            for v in node:
                walk(v)

    walk({k: v for k, v in w.items() if k != "registries"})
    for k in sorted(used - declared - {"byCloseResult"}):
        err.append(f"workflow.v4.json: ссылка на набор {k}, которого нет в stepSets")


def main():
    err = []
    validator = jsonschema.Draft202012Validator(load(os.path.join(MACHINE, "dsl-v1-schema.json")), format_checker=jsonschema.FormatChecker())
    count = check_examples(validator, err)
    check_fixture(validator, err)
    check_junction(err)
    for e in err:
        print(e)
    print(f"Примеров: {count}. Ошибок в машине сценариев: {len(err)}")
    return 1 if err else 0


if __name__ == "__main__":
    sys.exit(main())
