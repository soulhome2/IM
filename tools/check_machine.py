#!/usr/bin/env python3
"""Проверка машины состояний: workflow.v4.json и openapi.json сходятся сами с собой и между собой.

Запуск из корня репозитория: python3 tools/check_machine.py
Проверяет, что всё из реестров условий и эффектов реализовано в prototype/engine.js;
что переходы ссылаются на существующие состояния, формы, условия, эффекты,
права и таймеры; что справочники, горячие клавиши и фильтры очереди ссылаются на то,
что есть в модели; что состояния, справочники и бейджи в API совпадают с моделью
и все $ref в API разрешаются. Смысл правил не проверяет — только целостность.
Код выхода 1, если есть ошибки.
"""
import json
import os
import re
import sys
from collections import Counter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIR = os.path.join(ROOT, "Specification", "State_machine")


def load(name):
    with open(os.path.join(DIR, name), encoding="utf-8") as f:
        return json.load(f)


def duplicates(items):
    return [k for k, n in Counter(items).items() if n > 1]


def check_workflow(w, err):
    states = {s["id"] for s in w["states"]}
    cats = {c["id"] for c in w["stateCategories"]}
    forms = {f["id"] for f in w["forms"]}
    guards = {g["fn"] for g in w["registries"]["guards"]}
    effects = {e["fn"] for e in w["registries"]["effects"]}
    perms = {p["key"] for p in w["permissions"]}
    timers = {t["id"] for t in w["timers"]}
    catalogs = set(w["reasonCatalogs"])
    step_sets = {k for k in w["stepSets"] if not k.startswith("$")}
    transitions = {t["id"] for t in w["transitions"]}

    for name, ids in [
        ("состояния", [s["id"] for s in w["states"]]),
        ("переходы", [t["id"] for t in w["transitions"]]),
        ("формы", [f["id"] for f in w["forms"]]),
        ("права", [p["key"] for p in w["permissions"]]),
        ("горячие клавиши", [h["key"] for h in w["hotkeys"]]),
    ]:
        for d in duplicates(ids):
            err.append(f"дубль: {name} — {d}")

    for s in w["states"]:
        if s["category"] not in cats:
            err.append(f"состояние {s['id']}: нет категории {s['category']}")
    for t in w["timers"]:
        for key in ("startsOnEnter", "stopsOnEnter", "pausedInStates"):
            for x in t.get(key, []):
                if x not in states:
                    err.append(f"таймер {t['id']}.{key}: нет состояния {x}")

    for t in w["transitions"]:
        tid = t["id"]
        for x in t["from"]:
            if x not in states:
                err.append(f"переход {tid}: нет исходного состояния {x}")
        if t["to"] is not None and t["to"] not in states:
            err.append(f"переход {tid}: нет целевого состояния {t['to']}")
        if t.get("form") and t["form"] not in forms:
            err.append(f"переход {tid}: нет формы {t['form']}")
        for g in t.get("guards", []):
            if g["fn"] not in guards:
                err.append(f"переход {tid}: условие {g['fn']} не в реестре")
            if g["fn"] == "hasPermission" and g["args"][0] not in perms:
                err.append(f"переход {tid}: нет права {g['args'][0]}")
            if g["fn"] == "hasScopedPermission" and not any(p.startswith(g["args"][0] + ":") for p in perms):
                err.append(f"переход {tid}: нет прав {g['args'][0]}:*")
        for e in t.get("effects", []):
            if e["fn"] not in effects:
                err.append(f"переход {tid}: эффект {e['fn']} не в реестре")
            if e["fn"].endswith("Timer") and e["args"][0] not in timers:
                err.append(f"переход {tid}: нет таймера {e['args'][0]}")

    for f in w["forms"]:
        for field in f["fields"]:
            src = field.get("source", "")
            if src.startswith("reasonCatalog:") and src.split(":", 1)[1] not in catalogs:
                err.append(f"форма {f['id']}: нет справочника {src}")

    for item in w["reasonCatalogs"].get("close_result", {}).get("items", []):
        rid = item["id"]
        if item["permission"] not in perms:
            err.append(f"результат {rid}: нет права {item['permission']}")
        for x in item["fromStates"] + item["ownerOnlyInStates"]:
            if x not in states:
                err.append(f"результат {rid}: нет состояния {x}")
        if item["requiredStepSet"] not in step_sets:
            err.append(f"результат {rid}: нет набора шагов {item['requiredStepSet']}")
        if item.get("causeCatalog") and item["causeCatalog"] not in catalogs:
            err.append(f"результат {rid}: нет справочника {item['causeCatalog']}")

    keys = [h["key"] for h in w["hotkeys"]]
    for key in sorted({k for k in keys if keys.count(k) > 1}):
        err.append(f"клавиша {key} назначена дважды (§13, правило 5)")
    for h in w["hotkeys"]:
        if h["key"].startswith("Ctrl+"):
            err.append(f"клавиша {h['key']}: сочетания с Ctrl занимает браузер (§13, правило 5)")
        action = h["action"]
        if action.startswith("transition:") and action.split(":", 1)[1] not in transitions:
            err.append(f"клавиша {h['key']}: нет перехода {action}")
    for x in w["validation"]["claimWithoutExitPermission"]["requiresAnyOf"]:
        if x not in perms:
            err.append(f"проверка §10.3: нет права {x}")
    for s in w["validation"].get("typicalPermissionSets", {}).get("items", []):
        for x in s["permissions"]:
            if x not in perms:
                err.append(f"типовой набор {s['id']}: нет права {x}")
    for x in w["escalation"]["fromStates"]:
        if x not in states:
            err.append(f"автоэскалация: нет состояния {x}")
    for q in w["queueFilters"]:
        for x in q.get("states", []):
            if x not in states:
                err.append(f"фильтр {q['id']}: нет состояния {x}")
        for x in q.get("stateCategories", []):
            if x not in cats:
                err.append(f"фильтр {q['id']}: нет категории {x}")
    guarded = w["navActions"]["items"] + [
        dict(w["scenarioEdit"], id="scenarioEdit"),
        {"id": "grouping.excludeGuards", "guards": w["grouping"].get("excludeGuards", [])},
    ]
    for item in guarded:
        for g in item.get("guards", []):
            if g["fn"] not in guards:
                err.append(f"{item['id']}: условие {g['fn']} не в реестре")
    for s in w["session"]["states"]:
        if s.get("permission") and s["permission"] not in perms:
            err.append(f"состояние оператора {s['id']}: нет права {s['permission']}")
    for b in w["badges"]["rules"]:
        if b["state"] not in states:
            err.append(f"бейдж: нет состояния {b['state']}")


def check_engine(w, err):
    """Всё, что есть в реестрах машины, умеет исполнитель прототипа (BUG-06)."""
    path = os.path.join(ROOT, "prototype", "engine.js")
    with open(path, encoding="utf-8") as f:
        src = f.read()

    def names(block):
        body = src.split(f"const {block} = {{", 1)[1].split("\n    };", 1)[0]
        return set(re.findall(r"^      (\w+): ", body, re.M))

    for kind, block in (("guards", "GUARDS"), ("effects", "EFFECTS")):
        implemented = names(block)
        for item in w["registries"][kind]:
            if item["fn"] not in implemented:
                err.append(f"{'условие' if kind == 'guards' else 'эффект'} {item['fn']} есть в реестре, но не реализован в prototype/engine.js")


def check_api(w, o, err):
    schemas = o["components"]["schemas"]
    states = {s["id"] for s in w["states"]}
    api_states = set(schemas["StateId"]["enum"])
    if api_states != states:
        err.append(f"API StateId {sorted(api_states)} не совпадает с моделью {sorted(states)}")

    styles = {b["style"] for b in w["badges"]["rules"]}
    api_styles = set(schemas["Badge"]["properties"]["style"]["enum"])
    for x in styles - api_styles:
        err.append(f"API Badge.style: нет стиля {x}")

    catalogs = set(w["reasonCatalogs"])
    reasons = o["paths"].get("/operator/reference/reasons/{catalogId}", {})
    for p in reasons.get("parameters", []):
        enum = p.get("schema", {}).get("enum")
        if p.get("name") == "catalogId" and enum and set(enum) != catalogs:
            err.append(f"API catalogId {sorted(enum)} не совпадает со справочниками {sorted(catalogs)}")

    for name in set(re.findall(r'"\$ref": "#/components/schemas/([^"]+)"', json.dumps(o))):
        if name not in schemas:
            err.append(f"API: $ref на несуществующую схему {name}")


def main():
    err = []
    try:
        w = load("workflow.v4.json")
        o = load("openapi.json")
    except (OSError, json.JSONDecodeError) as e:
        print(f"Не читается: {e}")
        return 1
    check_workflow(w, err)
    check_engine(w, err)
    check_api(w, o, err)
    for e in err:
        print(e)
    print(f"Ошибок в машине состояний: {len(err)}")
    return 1 if err else 0


if __name__ == "__main__":
    sys.exit(main())
