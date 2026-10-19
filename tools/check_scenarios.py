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
Формальная проверка (PROC-28): перебором ответов на шаги с выбором — правило или default, которые не срабатывают
ни при каком ответе, правило, заслонённое более ранним; условие на шаг, которого может не быть на пути. В примерах
это замечания исходнику (копия не правится), в сценариях набора — ошибки. --fsm — карта «ответ → исход» и циклы.
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

# --fsm: карта «ответ → исход» по шагам с правилами и циклы (для /im-fsm)
FSM = [] if "--fsm" in sys.argv else None

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


# ===== Формальная проверка: перебор ответов (PROC-28) =====
# Условия вычисляются так же, как json-logic-js 2.0.5 в исполнителе (prototype/vendor/json-logic-js):
# нестрогое == JavaScript, «истинность» JSONLogic (пустой массив — ложь), итог правила — Boolean() runner-web.

MISSING = object()  # шага нет в state: ответа не было или шаг выпал из пути
LIMIT = 50000  # больше сочетаний ответов — шаг не перебирается


def js_str(v):
    if v is None:
        return "null"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, list):
        return ",".join("" if x is None else js_str(x) for x in v)
    if isinstance(v, float) and v.is_integer():
        return str(int(v))
    return str(v)


def js_num(v):
    if v is None or v is False:
        return 0.0
    if v is True:
        return 1.0
    if isinstance(v, (int, float)):
        return float(v)
    try:
        t = js_str(v).strip()
        return float(t) if t else 0.0
    except ValueError:
        return float("nan")


def js_loose_eq(a, b):
    if a is None or b is None:
        return a is None and b is None
    if isinstance(a, list) and isinstance(b, list):
        return a is b
    if type(a) is type(b) and not isinstance(a, list):
        return a == b
    if isinstance(a, list):
        a = js_str(a)
    if isinstance(b, list):
        b = js_str(b)
    if isinstance(a, str) and isinstance(b, str):
        return a == b
    return js_num(a) == js_num(b)


def js_bool(v):
    return not (v is None or v is False or v == "" or (isinstance(v, (int, float)) and not isinstance(v, bool) and (v == 0 or v != v)))


def jl_truthy(v):
    return not (isinstance(v, list) and not v) and js_bool(v)


def js_compare(a, b, op):
    # Массив в сравнении — сначала строка (ToPrimitive), как в JavaScript
    a, b = (js_str(x) if isinstance(x, list) else x for x in (a, b))
    if isinstance(a, str) and isinstance(b, str):
        x, y = a, b
    else:
        x, y = js_num(a), js_num(b)
        if x != x or y != y:
            return False
    return {"<": x < y, "<=": x <= y, ">": x > y, ">=": x >= y}[op]


def jl_var(data, name, default=None):
    if name in ("", None):
        return data
    cur = data
    for part in str(name).split("."):
        if isinstance(cur, dict) and part in cur:
            cur = cur[part]
        elif isinstance(cur, list) and part.isdigit() and int(part) < len(cur):
            cur = cur[int(part)]
        else:
            return default
    return default if cur is MISSING else cur


def jl_apply(logic, data):
    if isinstance(logic, list):
        return [jl_apply(x, data) for x in logic]
    if not (isinstance(logic, dict) and len(logic) == 1):
        return logic
    (op, args), = logic.items()
    if not isinstance(args, list):
        args = [args]
    if op == "if":
        for i in range(0, len(args) - 1, 2):
            if jl_truthy(jl_apply(args[i], data)):
                return jl_apply(args[i + 1], data)
        return jl_apply(args[-1], data) if len(args) % 2 else None
    if op == "and":
        cur = None
        for a in args:
            cur = jl_apply(a, data)
            if not jl_truthy(cur):
                return cur
        return cur
    if op == "or":
        cur = None
        for a in args:
            cur = jl_apply(a, data)
            if jl_truthy(cur):
                return cur
        return cur
    if op in ("some", "all", "none"):
        items = jl_apply(args[0], data)
        items = items if isinstance(items, list) else []
        hits = [jl_truthy(jl_apply(args[1], x)) for x in items]
        return {"some": any(hits), "none": not any(hits), "all": bool(items) and all(hits)}[op]
    vals = [jl_apply(a, data) for a in args]
    if op == "var":
        return jl_var(data, vals[0] if vals else None, vals[1] if len(vals) > 1 else None)
    if op == "missing":
        keys = vals[0] if vals and isinstance(vals[0], list) else vals
        return [k for k in keys if jl_var(data, k) in (None, "")]
    if op == "missing_some":
        need, keys = vals[0], vals[1]
        miss = [k for k in keys if jl_var(data, k) in (None, "")]
        return [] if len(keys) - len(miss) >= need else miss
    if op == "==":
        return js_loose_eq(vals[0], vals[1])
    if op == "!=":
        return not js_loose_eq(vals[0], vals[1])
    if op == "!":
        return not jl_truthy(vals[0])
    if op in ("<", "<=") and len(vals) == 3:
        return js_compare(vals[0], vals[1], op) and js_compare(vals[1], vals[2], op)
    if op in ("<", "<=", ">", ">="):
        return js_compare(vals[0], vals[1], op)
    if op == "in":
        a, b = vals[0], vals[1]
        if isinstance(b, list):
            return any(type(x) is type(a) and x == a for x in b)
        if isinstance(b, str):
            return js_str(a) in b
        return False
    raise ValueError(op)


def check_evaluator(err):
    """Вычислитель условий на Python совпадает с json-logic-js на крайних случаях (tests/jsonlogic-cases.js)."""
    path = os.path.join(ROOT, "tests", "jsonlogic-cases.js")
    with open(path, encoding="utf-8") as f:
        text = f.read()
    cases = json.loads(text[text.index("= ") + 2:].rstrip().rstrip(";"))
    for c in cases:
        got = js_bool(jl_apply(c["when"], {"state": c["state"]}))
        if got != c["fires"]:
            err.append(f"вычислитель условий расходится с json-logic-js: {json.dumps(c['when'], ensure_ascii=False)} при {json.dumps(c['state'], ensure_ascii=False)}")
    return len(cases)


def var_steps(expr, item_scope=False):
    """Шаги, на ответы которых смотрит условие (var «state.<шаг>…»)."""
    found = set()
    if isinstance(expr, list):
        for x in expr:
            found |= var_steps(x, item_scope)
    elif isinstance(expr, dict):
        for op, args in expr.items():
            if op == "var" and not item_scope:
                name = args[0] if isinstance(args, list) and args else args
                parts = str(name).split(".")
                if parts[0] == "state" and len(parts) > 1:
                    found.add(parts[1])
            elif op in ("missing", "missing_some"):
                keys = args[-1] if op == "missing_some" and isinstance(args, list) else args
                for k in keys if isinstance(keys, list) else [keys]:
                    found |= var_steps({"var": k}, item_scope)
            elif op in ("some", "all", "none") and isinstance(args, list) and len(args) == 2:
                found |= var_steps(args[0], item_scope) | var_steps(args[1], True)
            else:
                found |= var_steps(args, item_scope)
    return found


def required(step):
    if step["type"] == "Button":
        return True
    v = step["view"].get("required")
    return v if v is not None else step["type"] in ("RadioButton", "Select", "Datetime")


def answers_of(step):
    """Все ответы шага с выбором (значения state.<шаг>.value) и пропуск; у остальных — None: не перебираются."""
    ids = [o["id"] for o in step["view"].get("options", [])]
    out = []
    if step["type"] in ("RadioButton", "Select"):
        out = list(ids)
    elif step["type"] == "Checkbox":
        if len(ids) > 12:
            return None
        lo = max(step["view"].get("minSelected", 0), 1 if required(step) else 0)
        hi = step["view"].get("maxSelected") or len(ids)
        out = [[ids[i] for i in range(len(ids)) if m >> i & 1] for m in range(1 << len(ids)) if lo <= bin(m).count("1") <= hi]
    elif step["type"] == "Button":
        out = [None]
    else:
        return None
    return [(v, False) for v in out] + ([(None, True)] if not required(step) else [])


def dominators(steps, edges, start):
    """Шаги, через которые проходит каждый путь от начального к шагу."""
    dom = {sid: set(steps) for sid in steps}
    dom[start] = {start}
    preds = {sid: [p for p in steps if sid in edges[p]] for sid in steps}
    changed = True
    while changed:
        changed = False
        for sid in steps:
            if sid == start:
                continue
            ps = [dom[p] for p in preds[sid]]
            new = ({sid} | set.intersection(*ps)) if ps else {sid}
            if new != dom[sid]:
                dom[sid], changed = new, True
    return dom


def formal(script, name, fsm=None):
    """Перебор ответов по шагам с правилами: правило, которое не срабатывает ни при каком ответе или
    заслонено более ранним; условие на шаг, которого может не быть на пути. fsm — список строк карты для --fsm."""
    err = []
    steps = {s["id"]: s for s in script["steps"]}
    edges = {sid: {o["goto"] for o in outcomes(s) if o.get("goto") and o["goto"] != sid and not has_finish(o)} for sid, s in steps.items()}
    dom = dominators(steps, edges, script["initialStepId"])
    for sid, step in steps.items():
        rules = (step.get("transitions") or {}).get("rules", [])
        if not rules:
            continue
        where = f"{name}: шаг {sid}"
        refs = set().union(*(var_steps(r["when"]) for r in rules))
        for ref in sorted(refs - {sid}):
            if ref in steps and ref not in dom[sid]:
                err.append(f"{where}: условие смотрит на шаг {ref}, которого может не быть на пути к этому шагу")
        domains = {}
        for ref in sorted(refs | {sid}):
            if ref not in steps:
                continue
            a = answers_of(steps[ref])
            if a is None:
                domains = None
                break
            # Шаг, не стоящий на каждом пути, может быть без ответа
            domains[ref] = a + ([MISSING] if ref != sid and ref not in dom[sid] else [])
        total = 1
        for d in (domains or {}).values():
            total *= len(d)
        if domains is None or total > LIMIT:
            if fsm is not None:
                fsm.append(f"{where}: не перебирается — условие смотрит на ответ без конечного выбора или сочетаний больше {LIMIT}")
            continue
        first = Counter()
        ever = Counter()
        hits = {}
        keys = list(domains)
        def walk(i, state):
            if i == len(keys):
                fired = None
                for k, r in enumerate(rules):
                    if js_bool(jl_apply(r["when"], {"state": state})):
                        ever[k] += 1
                        if fired is None:
                            fired = k
                first[fired] += 1
                hits.setdefault(fired, []).append({x: (state[x]["value"] if x in state else "—") for x in keys})
                return
            for v in domains[keys[i]]:
                nxt = dict(state)
                if v is not MISSING:
                    value, skipped = v
                    nxt[keys[i]] = dict({"value": value, "answeredAt": "2026-01-01T00:00:00Z", "by": None}, **({"skipped": True} if skipped else {}))
                walk(i + 1, nxt)
        walk(0, {})
        for k in range(len(rules)):
            if not ever[k]:
                err.append(f"{where}: правило {k} не срабатывает ни при каком ответе")
            elif not first[k]:
                err.append(f"{where}: правило {k} заслонено более ранним — срабатывает только вместе с ним")
        if not first[None]:
            to = step["transitions"]["default"].get("goto") or "finish"
            err.append(f"{where}: default не срабатывает ни при каком ответе — по нему ({to}) не пройти")
        if fsm is not None:
            for k in list(range(len(rules))) + [None]:
                outcome = rules[k] if k is not None else step["transitions"]["default"]
                to = "finish" if has_finish(outcome) else outcome.get("goto") or "остаться"
                label = f"правило {k}" if k is not None else "default"
                fsm.append(f"{where}: {label} → {to}: {first[k]} из {total}" + (f", напр. {hits[k][0]}" if hits.get(k) else ""))
    if fsm is not None:
        # Циклы: переход на шаг, через который уже прошли (шаг доминирует над источником)
        for sid in steps:
            for to in edges[sid]:
                if to in dom[sid]:
                    fsm.append(f"{name}: цикл {sid} → {to}")
    return err


def verdict(validator, script, name):
    """Что не так со сценарием: (ошибки схемы, смысловые ошибки)."""
    schema = [f"{name}: {'/'.join(map(str, e.absolute_path)) or '(корень)'}: {e.message[:160]}" for e in validator.iter_errors(script)]
    sense = [] if schema else meaning(script, name)
    return schema, sense, (formal(script, name, FSM) if not schema and not sense else [])


def check_examples(validator, err, warn):
    count = 0
    for base, dirs, files in os.walk(EXAMPLES):
        dirs.sort()
        for file in sorted(files):
            if not file.endswith(".json"):
                continue
            name = os.path.relpath(os.path.join(base, file), EXAMPLES).replace(os.sep, "/")
            schema, sense, found = verdict(validator, load(os.path.join(base, file)), f"examples/{name}")
            expected = EXPECTED.get(name)
            if expected == "schema" and not schema:
                err.append(f"examples/{name}: схема должна отвергать этот пример")
            elif expected == "meaning" and (schema or not sense):
                err.append(f"examples/{name}: этот пример должна отвергать смысловая проверка, а не схема")
            elif not expected:
                err += schema + sense
                # Перебор ответов в примерах — замечания исходнику: копия не правится (ORIGIN.md)
                warn += found
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
        schema, sense, found = verdict(validator, script, name)
        err += schema + sense + found
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
    warn = []
    check_evaluator(err)
    count = check_examples(validator, err, warn)
    check_fixture(validator, err)
    check_junction(err)
    if FSM is not None:
        print("Карта перебора ответов и циклы:")
        for line in FSM:
            print("  " + line)
    for w in warn:
        print(f"ЗАМЕЧАНИЕ {w}")
    for e in err:
        print(e)
    print(f"Примеров: {count}. Замечаний к примерам: {len(warn)}. Ошибок в машине сценариев: {len(err)}")
    return 1 if err else 0


if __name__ == "__main__":
    sys.exit(main())
