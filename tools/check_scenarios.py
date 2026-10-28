#!/usr/bin/env python3
"""Проверка машины сценариев: сценарии проходят схему и смысловые проверки, стык с машиной инцидента цел.

Запуск из корня репозитория: python3 tools/check_scenarios.py
Нужен пакет jsonschema (в CI ставится в checks.yml). Формат сценария — формат редактора продукта
(Specification/Scenario_machine/, спецификация и схема формата сценария v1). Проверяет:
- примеры Specification/Scenario_machine/examples/ — схему и смысл; отрицательные примеры A5 — что их
  отвергает то, что должно (README машины сценариев, «Примеры»);
- сценарии эталонного набора (fixtures/scenarios/<тип события>.v<версия>.json, имя — по scenario.id и version) —
  то же; scenario совпадает с guid и версией строки, у типа события — существующий сценарий, прохождения инцидентов
  ссылаются на сценарий своего типа события, существующую версию и её шаги;
- стык: наборы обязательных шагов, на которые ссылается workflow_schema.v1.json, есть в профиле МИ.
Смысл (спецификация, раздел 11, уровень 2) — проверки редактора продукта с его кодами (validation.ts): первый шаг,
id шагов и вариантов, goto, goto: null только у финального шага, хотя бы один финальный шаг, достижимость, границы
Checkbox, ссылки условий на варианты и списки. Сверх них — проверки МИ: правила только у RadioButton, Checkbox и
Select; операторы — из белого списка (раздел 7); var — только на ответ своего шага; значения по умолчанию — из
вариантов; из каждого достижимого шага можно дойти до конца.
Формальная проверка (PROC-28): перебором ответов своего шага — правило или default, которые не срабатывают ни при
каком ответе, правило, заслонённое более ранним; у финального шага макрос или правила — не исполнятся (RULE-96).
В примерах это замечания, в сценариях набора — ошибки.
--fsm — карта «ответ → исход» и циклы.
Код выхода 1, если есть ошибки.
"""
import json
import os
import sys
from collections import Counter
from itertools import product

try:
    import jsonschema
except ImportError:
    print("Нужен пакет jsonschema: pip install jsonschema")
    sys.exit(1)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MACHINE = os.path.join(ROOT, "Specification", "Scenario_machine")
EXAMPLES = os.path.join(MACHINE, "examples")
WORKFLOW = os.path.join(ROOT, "Specification", "Workflow_machine", "workflow_schema.v1.json")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fixture  # noqa: E402

# Белый список JSONLogic (спецификация, раздел 7)
OPERATORS = {"var", "==", "!=", ">", ">=", "<", "<=", "and", "or", "!", "if", "in", "none", "some", "all", "missing", "missing_some"}
ARRAY_OPERATORS = {"none", "some", "all"}
WITH_RULES = ("RadioButton", "Checkbox", "Select")
# Строки условия, которые редактор не сверяет с вариантами (validation.ts, isOperator)
NOT_OPTIONS = {"value", "selected", "accumulator", "current"}
# Наборы обязательных шагов профиля МИ (README машины сценариев, решение ARCH-06 в5); byCloseResult —
# не набор, а «по результату закрытия»: набор берётся из справочника результатов
PROFILE_SETS = {"closing", "none"}

# --fsm: карта «ответ → исход» по шагам с правилами и циклы (для /im-fsm)
FSM = [] if "--fsm" in sys.argv else None

# Чего ждать от примеров A5 (README машины сценариев, «Примеры»): schema — отвергает схема, meaning — смысловая проверка,
# formal — схему и смысл проходит, отвергает проверка исполнения (перебор, финальный шаг)
EXPECTED = {
    "architecture/A5-anti-patterns/bad-1-schema-broken-goto.json": "meaning",
    "architecture/A5-anti-patterns/bad-3-unknown-step-type.json": "schema",
    "architecture/A5-anti-patterns/bad-6-macro-on-finish-step.json": "formal",
}


def load(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def rules_of(step):
    """Правила, которые читает исполнитель: только у RadioButton, Checkbox и Select и не у финального шага."""
    return [] if step["finish"] or step["type"] not in WITH_RULES else step["transitions"].get("rules", [])


def targets(step):
    """Все исходы шага, как их видит редактор: default и правила."""
    return [step["transitions"]["default"]] + step["transitions"].get("rules", [])


def var_names(step):
    """Переменные, которые условие шага может читать (спецификация, раздел 7)."""
    if step["type"] == "RadioButton":
        return {"value"}
    if step["type"] == "Checkbox":
        return {"selected"}
    return {lst["id"] for lst in step["view"]["lists"]}


def option_ids(step):
    if step["type"] == "Select":
        return {o["id"] for lst in step["view"]["lists"] for o in lst["options"]}
    return {o["id"] for o in step["view"]["options"]}


def strings(x):
    """Все строки условия — как extractStringValues редактора."""
    if isinstance(x, str):
        return [x]
    if isinstance(x, list):
        return [s for i in x for s in strings(i)]
    if isinstance(x, dict):
        return [s for v in x.values() for s in strings(v)]
    return []


def var_refs(x):
    """Имена var строкой — как extractVarRefs редактора."""
    if not isinstance(x, dict):
        return []
    if isinstance(x.get("var"), str):
        return [x["var"]]
    return [r for v in x.values() for r in var_refs(v)]


def check_logic(expr, names, where, err, item_scope=False):
    """Операторы — из белого списка; var — на ответ своего шага (кроме var элемента внутри some/all/none)."""
    if isinstance(expr, list):
        for x in expr:
            check_logic(x, names, where, err, item_scope)
        return
    if not isinstance(expr, dict):
        return
    for op, args in expr.items():
        if op not in OPERATORS:
            err.append(f"{where}: оператор {op} не из белого списка")
            continue
        if op == "var":
            name = args[0] if isinstance(args, list) and args else args
            if not item_scope and name not in ("", None) and name not in names:
                err.append(f"{where}: var {name} — не ответ своего шага (можно: {', '.join(sorted(names))})")
            continue
        if op in ("missing", "missing_some"):
            keys = args[-1] if op == "missing_some" and isinstance(args, list) else args
            for key in keys if isinstance(keys, list) else [keys]:
                if isinstance(key, str):
                    check_logic({"var": key}, names, where, err, item_scope)
            continue
        if op in ARRAY_OPERATORS and isinstance(args, list) and len(args) == 2:
            check_logic(args[0], names, where, err, item_scope)
            check_logic(args[1], names, where, err, True)
            continue
        check_logic(args, names, where, err, item_scope)


def meaning(script, name):
    """Смысловые проверки сценария (спецификация, раздел 11, уровень 2): коды редактора продукта и проверки МИ."""
    err = []
    steps = {s["id"]: s for s in script["steps"]}
    initial = script["scenario"]["initialStep"]
    if not any(s["finish"] for s in script["steps"]):
        err.append(f"{name}: NO_FINISH_STEP — нет шага с finish: true")
    if not initial:
        err.append(f"{name}: EMPTY_INITIAL_STEP — первый шаг не задан")
    elif initial not in steps:
        err.append(f"{name}: INVALID_INITIAL_STEP — первого шага {initial} нет")
    for sid in [k for k, n in Counter(s["id"] for s in script["steps"]).items() if n > 1]:
        err.append(f"{name}: DUPLICATE_STEP_ID — шаг {sid} повторяется")
    for s in script["steps"]:
        where = f"{name}: шаг {s['id']}"
        if not s["id"]:
            err.append(f"{name}: EMPTY_STEP_ID — у шага нет id")
        if not s["title"].strip():
            err.append(f"{where}: EMPTY_STEP_TITLE — нет заголовка")
        for t in targets(s):
            if t["goto"] is not None and t["goto"] not in steps:
                err.append(f"{where}: INVALID_GOTO — переход на несуществующий шаг {t['goto']}")
            if t["goto"] is None and not s["finish"]:
                err.append(f"{where}: GOTO_NULL_WITHOUT_FINISH — goto: null у шага без finish")
        if s["transitions"].get("rules") and s["type"] not in WITH_RULES:
            err.append(f"{where}: правила у {s['type']} не читаются — только у RadioButton, Checkbox и Select")
        if s["type"] in ("RadioButton", "Checkbox"):
            ids = [o["id"] for o in s["view"]["options"]]
            for oid in [k for k, n in Counter(ids).items() if n > 1]:
                err.append(f"{where}: DUPLICATE_OPTION_ID — вариант {oid} повторяется")
            for i, r in enumerate(s["transitions"].get("rules", [])):
                for ref in strings(r["condition"]):
                    if ref and ref not in ids and ref not in NOT_OPTIONS:
                        err.append(f"{where}, правило {i + 1}: INVALID_CONDITION_OPTION_ID — варианта {ref} нет")
        if s["type"] == "Checkbox":
            n, lo, hi = len(s["view"]["options"]), s["view"]["minSelected"], s["view"]["maxSelected"]
            if lo > n:
                err.append(f"{where}: CHECKBOX_MIN_EXCEEDS_OPTIONS — минимум {lo} больше числа вариантов {n}")
            if hi is not None and hi < lo:
                err.append(f"{where}: CHECKBOX_MAX_LESS_THAN_MIN — максимум {hi} меньше минимума {lo}")
            if hi is not None and hi > n:
                err.append(f"{where}: CHECKBOX_MAX_EXCEEDS_OPTIONS — максимум {hi} больше числа вариантов {n}")
        if s["type"] == "RadioButton" and s["view"]["default"] is not None and s["view"]["default"] not in option_ids(s):
            err.append(f"{where}: значение по умолчанию {s['view']['default']} — не вариант шага")
        if s["type"] == "Select":
            lists = [lst["id"] for lst in s["view"]["lists"]]
            for lid in [k for k, n in Counter(lists).items() if n > 1]:
                err.append(f"{where}: список {lid} повторяется")
            for lst in s["view"]["lists"]:
                ids = [o["id"] for o in lst["options"]]
                for oid in [k for k, n in Counter(ids).items() if n > 1]:
                    err.append(f"{where}, список {lst['id']}: DUPLICATE_OPTION_ID — вариант {oid} повторяется")
                for d in lst.get("default", []):
                    if d not in ids:
                        err.append(f"{where}, список {lst['id']}: значение по умолчанию {d} — не вариант списка")
            for i, r in enumerate(s["transitions"].get("rules", [])):
                for ref in var_refs(r["condition"]):
                    if ref not in lists:
                        err.append(f"{where}, правило {i + 1}: INVALID_CONDITION_LIST_KEY — списка {ref} нет")
        if s["type"] in WITH_RULES:
            for i, r in enumerate(s["transitions"].get("rules", [])):
                check_logic(r["condition"], var_names(s), f"{where}, правило {i + 1}", err)
    if err or initial not in steps:
        return err
    # Достижимость — как в редакторе: по всем исходам от первого шага
    seen, queue = {initial}, [initial]
    while queue:
        for t in targets(steps[queue.pop()]):
            if t["goto"] in steps and t["goto"] not in seen:
                seen.add(t["goto"])
                queue.append(t["goto"])
    for sid in steps:
        if sid not in seen:
            err.append(f"{name}: STEP_NOT_REACHABLE — шаг {sid} недостижим из первого")
    # МИ: из каждого достижимого шага можно дойти до финального по исходам, которые читает исполнитель
    edges = {sid: {t["goto"] for t in [s["transitions"]["default"]] + rules_of(s) if t["goto"] in steps} if not s["finish"] else set()
             for sid, s in steps.items()}
    exits = {sid for sid, s in steps.items() if s["finish"]}
    changed = True
    while changed:
        changed = False
        for sid in steps:
            if sid not in exits and edges[sid] & exits:
                exits.add(sid)
                changed = True
    for sid in sorted(seen - exits):
        err.append(f"{name}: из шага {sid} не дойти до финального")
    return err


# ===== Вычислитель условий =====
# Так же, как исполнитель prototype/scenario.js: json-logic-js 2.0.5 (нестрогое == JavaScript, «истинность»
# JSONLogic: пустой массив — ложь) и операторы ==, !=, in над массивами — как в редакторе продукта (jsonLogic.ts).

LIMIT = 50000  # больше ответов — шаг не перебирается


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


def same_value_zero(a, b):
    """Array.prototype.includes: строгое равенство, без приведения типов."""
    if isinstance(a, bool) or isinstance(b, bool):
        return isinstance(a, bool) and isinstance(b, bool) and a == b
    if isinstance(a, (int, float)) and isinstance(b, (int, float)):
        return a == b or (a != a and b != b)
    if isinstance(a, (list, dict)) or isinstance(b, (list, dict)):
        return a is b
    return type(a) is type(b) and a == b


def includes(xs, v):
    return any(same_value_zero(x, v) for x in xs)


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
    return cur


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
    a, b = (vals + [None, None])[:2]
    if op == "==":
        if isinstance(a, list) and not isinstance(b, list):
            return includes(a, b)
        if isinstance(b, list) and not isinstance(a, list):
            return includes(b, a)
        return js_loose_eq(a, b)
    if op == "!=":
        if isinstance(a, list) and not isinstance(b, list):
            return not includes(a, b)
        if isinstance(b, list) and not isinstance(a, list):
            return not includes(b, a)
        return not js_loose_eq(a, b)
    if op == "!":
        return not jl_truthy(vals[0])
    if op in ("<", "<=") and len(vals) == 3:
        return js_compare(vals[0], vals[1], op) and js_compare(vals[1], vals[2], op)
    if op in ("<", "<=", ">", ">="):
        return js_compare(a, b, op)
    if op == "in":
        if isinstance(b, list):
            if isinstance(a, list):
                return bool(b) and bool(a) and all(includes(a, x) for x in b)
            return includes(b, a)
        if isinstance(b, str):
            if isinstance(a, list):
                return any(js_str(x) in b for x in a)
            return js_str(a) in b
        return False
    raise ValueError(op)


def fires(condition, context):
    """Срабатывает ли условие — как IMScenario.apply: пустое не срабатывает, ошибка — ложь."""
    if not isinstance(condition, dict) or not condition:
        return False
    try:
        return js_bool(jl_apply(condition, context))
    except (ValueError, TypeError, KeyError, IndexError):
        return False


def check_evaluator(err):
    """Вычислитель условий на Python совпадает с исполнителем на крайних случаях (tests/jsonlogic-cases.js)."""
    path = os.path.join(ROOT, "tests", "jsonlogic-cases.js")
    with open(path, encoding="utf-8") as f:
        text = f.read()
    cases = json.loads(text[text.index("= ") + 2:].rstrip().rstrip(";"))
    for c in cases:
        if fires(c["when"], c["data"]) != c["fires"]:
            err.append(f"вычислитель условий расходится с исполнителем: {json.dumps(c['when'], ensure_ascii=False)} при {json.dumps(c['data'], ensure_ascii=False)}")
    return len(cases)


# ===== Формальная проверка: перебор ответов своего шага (PROC-28) =====

def subsets(ids, lo, hi):
    if len(ids) > 12:
        return None
    return [[ids[i] for i in range(len(ids)) if m >> i & 1] for m in range(1 << len(ids)) if lo <= bin(m).count("1") <= hi]


def contexts(step):
    """Все контексты условия шага (спецификация, раздел 7): ответы и пропуск. Не перебирается — None."""
    v = step["view"]
    if step["type"] == "RadioButton":
        out = [{"value": o["id"]} for o in v["options"]]
        return out + ([] if v["required"] else [{"value": None}])
    if step["type"] == "Checkbox":
        ids = [o["id"] for o in v["options"]]
        picks = subsets(ids, v["minSelected"], v["maxSelected"] if v["maxSelected"] is not None else len(ids))
        return None if picks is None else [{"selected": p} for p in picks]
    lists = []
    for lst in v["lists"]:
        picks = subsets([o["id"] for o in lst["options"]], 1 if v["required"] else 0, len(lst["options"]))
        if picks is None:
            return None
        lists.append((lst["id"], picks))
    total = 1
    for _, picks in lists:
        total *= len(picks)
    if total > LIMIT:
        return None
    out = [dict(zip([k for k, _ in lists], combo)) for combo in product(*[p for _, p in lists])]
    return out + ([] if v["required"] else [{}])


def dominators(steps, edges, start):
    """Шаги, через которые проходит каждый путь от первого к шагу."""
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
    """Перебор ответов по шагам с правилами: правило, которое не срабатывает ни при каком ответе или заслонено
    более ранним; default, до которого не дойти. fsm — список строк карты для --fsm."""
    err = []
    steps = {s["id"]: s for s in script["steps"]}
    # RULE-96: у финального шага переходы не читаются — его макрос и правила не исполнятся, хотя формат их хранит
    for sid, step in steps.items():
        t = step["transitions"]
        if step["finish"] and (t["default"].get("macro") or t.get("rules")):
            what = ", ".join(x for x in ("макрос" if t["default"].get("macro") or any(r.get("macro") for r in t.get("rules", [])) else "",
                                         "правила" if t.get("rules") else "") if x)
            err.append(f"{name}: шаг {sid}: финальный — его переходы не читаются, не исполнятся: {what} (RULE-96)")
    for sid, step in steps.items():
        rules = rules_of(step)
        if not rules:
            continue
        where = f"{name}: шаг {sid}"
        domain = contexts(step)
        if domain is None:
            if fsm is not None:
                fsm.append(f"{where}: не перебирается — вариантов больше 12 или сочетаний больше {LIMIT}")
            continue
        first, ever, hits = Counter(), Counter(), {}
        for ctx in domain:
            fired = None
            for k, r in enumerate(rules):
                if fires(r["condition"], ctx):
                    ever[k] += 1
                    if fired is None:
                        fired = k
            first[fired] += 1
            hits.setdefault(fired, []).append(ctx)
        for k in range(len(rules)):
            if not ever[k]:
                err.append(f"{where}: правило {k + 1} не срабатывает ни при каком ответе")
            elif not first[k]:
                err.append(f"{where}: правило {k + 1} заслонено более ранним — срабатывает только вместе с ним")
        if not first[None]:
            err.append(f"{where}: default не срабатывает ни при каком ответе — по нему ({step['transitions']['default']['goto']}) не пройти")
        if fsm is not None:
            for k in list(range(len(rules))) + [None]:
                outcome = rules[k] if k is not None else step["transitions"]["default"]
                label = f"правило {k + 1}" if k is not None else "default"
                macro = f" + макрос «{outcome['macro']['name']}»" if outcome.get("macro") else ""
                fsm.append(f"{where}: {label} → {outcome['goto']}{macro}: {first[k]} из {len(domain)}" + (f", напр. {json.dumps(hits[k][0], ensure_ascii=False)}" if hits.get(k) else ""))
    if fsm is not None:
        # Циклы: переход на шаг, через который уже прошли (шаг доминирует над источником)
        edges = {sid: {t["goto"] for t in [s["transitions"]["default"]] + rules_of(s) if t["goto"] in steps} if not s["finish"] else set()
                 for sid, s in steps.items()}
        dom = dominators(steps, edges, script["scenario"]["initialStep"])
        for sid in steps:
            for to in edges[sid]:
                if to in dom[sid]:
                    fsm.append(f"{name}: цикл {sid} → {to}")
    return err


def verdict(validator, script, name):
    """Что не так со сценарием: (ошибки схемы, смысловые ошибки, находки перебора)."""
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
            elif expected == "formal" and (schema or sense or not found):
                err.append(f"examples/{name}: этот пример должна отвергать проверка исполнения, а не схема или смысл")
            elif not expected:
                err += schema + sense
                # Перебор ответов в примерах — замечания: примеры только показывают формат
                warn += found
            count += 1
    return count


def check_fixture(validator, err):
    """Сценарии эталонного набора — файлы fixtures/scenarios/ (строки как на сервере собирает tools/fixture.py) —
    и прохождения инцидентов. Имя файла — <ключ>.v<версия>.json по scenario.id и version (DATA-09), ключ — scenarios.keys.
    Сценарий инцидента — из сценариев его правила (rules, §14.5, ARCH-15)."""
    fx = fixture.load()
    rows = fx["scenarios"]["rows"]
    kind = {guid: k for k, guid in fx["scenarios"]["keys"].items()}
    for name, script in fixture.scenario_files():
        meta = script.get("scenario", {})
        want = f"{kind.get(meta.get('id'), '?')}.v{meta.get('version')}.json"
        if name != want:
            err.append(f"набор: файл сценария {name} — по scenario должен называться {want}")
    versions = {}
    for row in rows:
        name = f"набор: сценарий {row.get('guid')} v{row.get('version')}"
        script = row.get("script") or {}
        schema, sense, found = verdict(validator, script, name)
        err += schema + sense + found
        meta = script.get("scenario", {})
        if (meta.get("id"), meta.get("version")) != (row.get("guid"), row.get("version")):
            err.append(f"{name}: scenario.id и version не совпадают со строкой")
        key = (row.get("guid"), row.get("version"))
        if key in versions:
            err.append(f"{name}: версия повторяется")
        versions[key] = {s["id"] for s in script.get("steps", [])}
    for k, guid in fx["scenarios"]["keys"].items():
        if not any(g == guid for g, _ in versions):
            err.append(f"набор: у ключа {k} сценарий {guid}, которого нет")
    rules = {r.get("guid"): r for r in fx.get("rules", [])}
    for inc in fx.get("incidents", []):
        key = (inc.get("scenarioGuid"), inc.get("scenarioVersion"))
        if key[0] not in (rules.get(inc.get("ruleGuid")) or {}).get("scenarios", []):
            err.append(f"набор: инцидент {inc.get('number')} — сценарий не из сценариев его правила (§14.5)")
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
        err.append(f"workflow_schema.v1.json: набор {k} — в профиле МИ такого нет (README машины сценариев)")
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

    # cel — объявления типов выражений (requiredStepSet: string), не ссылки на наборы
    walk({k: v for k, v in w.items() if k not in ("registries", "cel")})
    for k in sorted(used - declared - {"byCloseResult"}):
        err.append(f"workflow_schema.v1.json: ссылка на набор {k}, которого нет в stepSets")


def main():
    err = []
    validator = jsonschema.Draft202012Validator(load(os.path.join(MACHINE, "scenario_schema.v1.json")), format_checker=jsonschema.FormatChecker())
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
