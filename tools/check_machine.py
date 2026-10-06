#!/usr/bin/env python3
"""Проверка машины состояний: workflow.v4.json и openapi.json сходятся сами с собой и между собой.

Запуск из корня репозитория: python3 tools/check_machine.py
Проверяет, что всё из реестров условий и эффектов реализовано в prototype/engine.js;
что переходы ссылаются на существующие состояния, формы, условия, эффекты,
права и таймеры; что справочники, горячие клавиши и фильтры очереди ссылаются на то,
что есть в модели; что состояния, справочники и бейджи в API совпадают с моделью
и все $ref в API разрешаются; что интерфейс прототипа (app.js) говорит только с API
и не трогает исполнитель и демо-данные напрямую; что эталонный набор fixtures/demo.json ссылается
на то, что есть, а время в нём — UTC и не позже снимка. Смысл правил не проверяет — только целостность.
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


def check_fixture(w, err):
    """Эталонный набор fixtures/demo.json: время — UTC и не позже снимка, ссылки на людей,
    устройства, состояния, справочники и сценарии существуют, таймеры соответствуют состоянию."""
    path = os.path.join(ROOT, "Specification", "State_machine", "fixtures", "demo.json")
    with open(path, encoding="utf-8") as f:
        fx = json.load(f)
    utc = re.compile(r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$")
    captured = fx.get("capturedAt")
    if not captured or not utc.match(captured):
        err.append("эталон: capturedAt — время снимка в UTC, вида 2026-10-03T12:00:00Z")
        return

    def when(value, where):
        if value is None:
            return
        if not isinstance(value, str) or not utc.match(value):
            err.append(f"эталон: {where} — время в UTC вида 2026-10-03T12:00:00Z, а не «{value}»")
        elif value > captured:
            err.append(f"эталон: {where} позже снимка capturedAt")

    people = fx["people"]
    humans = {o["id"] for o in people["operators"]}
    groups = {g["id"] for g in people["dutyGroups"]}
    target = (fx.get("operatorPreferences") or {}).get("defaultTransferTargetId")
    # Дежурные группы (§8.1): участники — люди с одной из ролей группы плюс названные отдельно
    my_roles = next((o.get("roles", []) for o in people["operators"] if o["id"] == fx.get("operator")), [])
    own = {g["id"] for g in people["dutyGroups"] if fx.get("operator") in g.get("members", []) or set(my_roles) & set(g.get("roles", []))}
    for g in people["dutyGroups"]:
        if not g.get("roles") and not g.get("members"):
            err.append(f"эталон: дежурная группа {g['id']} — ни ролей, ни участников")
        for m in g.get("members", []):
            if m not in humans:
                err.append(f"эталон: дежурная группа {g['id']} — нет человека {m}")
    if target is not None and (target not in humans | groups or target == fx.get("operator") or target in own):
        err.append(f"эталон: operatorPreferences.defaultTransferTargetId «{target}» — нет такого адресата или это сам оператор и его группа (§10.1)")
    system = {a["id"] for a in people["system"]}
    devices = {d["id"] for d in fx["devices"]}
    fx_devices = {d["id"]: d for d in fx["devices"]}
    # Сущности МИ и Axxon — UUID, как в контракте; люди и группы людей — строки внешней системы (§5)
    uuid = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")

    def node_ids(gs):
        for g in gs:
            yield g["id"]
            yield from node_ids(g.get("groups", []))

    entities = [("инцидент", i["guid"]) for i in fx["incidents"]]
    entities += [("тип события", i["eventType"].get("guid")) for i in fx["incidents"]]
    entities += [("устройство", d["id"]) for d in fx["devices"]]
    entities += [("группа устройств", g) for g in node_ids(fx["sourceGroups"])]
    entities += [("план", p["id"]) for p in fx.get("plans", [])]
    entities += [("сценарий", v.get("guid")) for k, v in fx["scenarios"].items() if not k.startswith("$")]
    entities += [("группа доступа", a.get("id")) for a in fx.get("accessGroups", [])]
    # Группы доступа (§5): роли, группы устройств и устройства существуют
    group_ids = set(node_ids(fx["sourceGroups"]))
    for a in fx.get("accessGroups", []):
        if not a.get("roles"):
            err.append(f"эталон: группа доступа «{a.get('name')}» — не назначена ни одной роли")
        for g in a.get("sourceGroups", []):
            if g not in group_ids:
                err.append(f"эталон: группа доступа «{a.get('name')}» — нет группы устройств {g}")
        for d in a.get("devices", []):
            if d not in devices:
                err.append(f"эталон: группа доступа «{a.get('name')}» — нет устройства {d}")
    # Связи камер (§19.1, RULE-49): устройство и камеры существуют, в связи — только камеры, у
    # устройства связь одна; у инцидента своих камер нет — они из связи его источника
    linked = [l["device"] for l in fx.get("cameraLinks", [])]
    for link in fx.get("cameraLinks", []):
        if link["device"] not in devices:
            err.append(f"эталон: связь камер — нет устройства {link['device']}")
        for cam in link["cameras"]:
            if cam not in devices or fx_devices[cam].get("type") != "camera":
                err.append(f"эталон: связь камер устройства {link['device']} — {cam} не камера набора")
    for dev in set(linked):
        if linked.count(dev) > 1:
            err.append(f"эталон: у устройства {dev} несколько связей камер")
    for inc in fx["incidents"]:
        if "cameras" in inc:
            err.append(f"эталон: {inc['number']} — камеры инцидента берутся из связей источника (cameraLinks), а не задаются у инцидента")
    # Каталог ролей (§5, §8.1): права — из каталога машины; роли людей, групп доступа и дежурных групп — из каталога
    perms = {p["key"] for p in w["permissions"]}
    roles = {r["name"] for r in fx.get("roles", [])}
    for r in fx.get("roles", []):
        for p in r.get("permissions", []):
            if p not in perms:
                err.append(f"эталон: у роли «{r['name']}» право {p} — нет в каталоге прав машины")
    used = [(f"человек {o['id']}", r) for o in people["operators"] for r in o.get("roles", [])]
    used += [(f"группа доступа «{a.get('name')}»", r) for a in fx.get("accessGroups", []) for r in a.get("roles", [])]
    used += [(f"дежурная группа {g['id']}", r) for g in people["dutyGroups"] for r in g.get("roles", [])]
    for where, r in used:
        if r not in roles:
            err.append(f"эталон: {where} — роли «{r}» нет в каталоге ролей (roles)")
    agent_states = {st["id"] for st in w["session"]["states"]}
    for o in people["operators"]:
        if o.get("agentState") not in agent_states:
            err.append(f"эталон: у человека {o['id']} состояние agentState «{o.get('agentState')}» — нет в session.states машины (§12.1)")
        if not isinstance(o.get("roles"), list) or not o["roles"]:
            err.append(f"эталон: у оператора {o['id']} нет ролей (roles) — ему ничего не видно (§5)")
    for kind, value in entities:
        if not isinstance(value, str) or not uuid.match(value):
            err.append(f"эталон: {kind} «{value}» — идентификатор не UUID")
    plans = {p["id"] for p in fx.get("plans", [])}
    sites = {i.get("site") for i in fx["incidents"]}
    for p in fx.get("plans", []):
        if p.get("site") and p["site"] not in sites:
            err.append(f"эталон: план {p['id']} — площадки «{p['site']}» нет ни у одного инцидента")
    for d in fx["devices"]:
        pos = d.get("position")
        if pos and (pos.get("plan") not in plans or not all(isinstance(pos.get(k), (int, float)) for k in ("x", "y"))):
            err.append(f"эталон: устройство {d['id']} — положение на несуществующем плане или без x, y")
        if d.get("thumbnailUrl") and d.get("type") != "camera":
            err.append(f"эталон: устройство {d['id']} — картинка есть только у камеры")
    types = {t["id"] for t in fx["deviceTypes"]}
    states = {st["id"] for st in w["states"]}
    catalog = lambda name: {i["id"] for i in w["reasonCatalogs"][name]["items"]}
    if fx.get("operator") not in humans:
        err.append("эталон: operator — не оператор из people.operators")
    for d in fx["devices"]:
        if d["type"] not in types:
            err.append(f"эталон: у устройства {d['id']} неизвестный тип {d['type']}")

    def walk(nodes):
        for g in nodes:
            for dev in g.get("devices", []):
                if dev not in devices:
                    err.append(f"эталон: в группе {g['id']} неизвестное устройство {dev}")
            walk(g.get("groups", []))

    walk(fx["sourceGroups"])
    seen = set()
    for inc in fx["incidents"]:
        gid = inc["guid"]
        where = f"эталон: {gid}"
        if gid in seen:
            err.append(f"{where} встречается дважды")
        seen.add(gid)
        st = inc["state"]
        if st not in states:
            err.append(f"{where}: нет состояния {st}")
        scenario = fx["scenarios"].get(inc["eventType"]["id"])
        if not scenario:
            err.append(f"{where}: нет сценария для типа {inc['eventType']['id']}")
        else:
            ids = {s["id"] for s in scenario["steps"]}
            cursor = inc["scenario"].get("cursorStepId")
            if cursor is not None and cursor not in ids:
                err.append(f"{where}: в сценарии нет шага {cursor}")
            for key in inc["scenario"]["answers"]:
                if key not in ids:
                    err.append(f"{where}: ответ на несуществующий шаг {key}")
        for dev in inc["devices"]:
            if dev not in devices:
                err.append(f"{where}: неизвестное устройство {dev}")
        if inc["owner"] is not None and inc["owner"] not in humans:
            err.append(f"{where}: владелец {inc['owner']} — не оператор (owner — только человек, §8.1)")
        if inc["assignmentGroup"] is not None and inc["assignmentGroup"] not in groups:
            err.append(f"{where}: неизвестная дежурная группа {inc['assignmentGroup']}")
        if inc["closedBy"] is not None and inc["closedBy"] not in humans:
            err.append(f"{where}: закрыл неизвестный {inc['closedBy']}")
        if inc["holdReason"] is not None and inc["holdReason"] not in catalog("hold"):
            err.append(f"{where}: нет причины удержания {inc['holdReason']}")
        if inc["closeResult"] is not None and inc["closeResult"] not in catalog("close_result"):
            err.append(f"{where}: нет результата закрытия {inc['closeResult']}")
        if inc["closeCause"] is not None and inc["closeCause"] not in catalog("mass_fault"):
            err.append(f"{where}: нет причины сбоя {inc['closeCause']}")
        when(inc["occurredAt"], f"{gid}.occurredAt")
        when(inc["closedAt"], f"{gid}.closedAt")
        for b in inc.get("breaches", []):
            when(b.get("at"), f"{gid}.breaches[].at")
        times = []
        for j in inc["journal"]:
            when(j["at"], f"{gid}.journal[].at")
            times.append(j["at"])
            if j["actor"] is not None and j["actor"] not in humans | groups | system:
                err.append(f"{where}: в журнале неизвестный участник {j['actor']}")
        if times != sorted(times):
            err.append(f"{where}: журнал не по времени")
        t = inc["timers"]
        for name, timer in t.items():
            if timer and "startedAt" in timer:
                when(timer["startedAt"], f"{gid}.timers.{name}.startedAt")
        # Какие таймеры идут — по состоянию (§4); длительность в наборе не задаётся
        expect = {
            "new": ("reaction",),
            "pending_acceptance": ("reaction",),
            "in_progress": ("resolution",),
            "on_hold": ("resolution", "hold"),
            "closed": (),
        }.get(st, ())
        running = tuple(n for n in ("reaction", "resolution", "hold") if t.get(n))
        if running != expect:
            err.append(f"{where}: в состоянии {st} должны идти таймеры: {', '.join(expect) or 'никакие'}, а заданы: {', '.join(running) or 'никакие'}")
        if st == "on_hold" and "leftSec" not in (t.get("resolution") or {}):
            err.append(f"{where}: у отложенного норматив закрытия стоит — leftSec, а не startedAt")
    # Лимиты (§10.2) — у каждого оператора, не только у оператора стенда
    for state, limit, name in (("in_progress", w["limits"]["maxActive"], "в работе"), ("on_hold", w["limits"]["maxOnHold"], "отложено")):
        per = {}
        for inc in fx["incidents"]:
            if inc["state"] == state and inc["owner"]:
                per[inc["owner"]] = per.get(inc["owner"], 0) + 1
        for who, n in per.items():
            if n > limit:
                err.append(f"эталон: у {who} {name} {n}, лимит — {limit} (§10.2)")


def check_layers(err):
    """Интерфейс прототипа говорит только с API: не трогает исполнитель, демо-данные и сервер
    напрямую. Единственное место, где он их называет, — создание встроенного сервера."""
    path = os.path.join(ROOT, "prototype", "app.js")
    with open(path, encoding="utf-8") as f:
        lines = f.read().split("\n")
    forbidden = re.compile(r"\bIMEngine\b|\bengine\.|\bIM_FIXTURE\b|\bIM_COLLEAGUES\b|\bembedded\.(?!recorded)|\bserver\.handle\b")
    for n, line in enumerate(lines, 1):
        if "IMServer.create(" in line:
            continue
        if forbidden.search(line):
            err.append(f"app.js:{n}: интерфейс обращается к данным или исполнителю в обход API: {line.strip()[:80]}")


def check_literals(w, err):
    """Значения справочников машины (причины, результаты закрытия, причины перерыва) — данные:
    код прототипа их по имени не знает, иначе правило продублировано в коде и разойдётся с
    машиной при переименовании (BUG-22). Нужное свойство берётся из машины."""
    ids = set()
    for catalog in w["reasonCatalogs"].values():
        ids.update(item["id"] for item in catalog.get("items", []))
    ids.update(r["id"] for r in w["session"].get("breakReasons", []))
    for name in ("app.js", "server.js", "engine.js"):
        with open(os.path.join(ROOT, "prototype", name), encoding="utf-8") as f:
            for n, line in enumerate(f, 1):
                for found in sorted(i for i in ids if f'"{i}"' in line):
                    err.append(f"{name}:{n}: значение справочника машины «{found}» в коде — нужное свойство берётся из машины")


def check_rules_tables(w, err):
    """Таблицы §6.1–§6.3 правил ссылаются на машину колонкой «В машине» (PROC-08): каждый
    переход и действие машины есть в правилах, лишних нет, «Откуда» и «Куда» совпадают."""
    path = os.path.join(ROOT, "Specification", "State_rules", "States rules IM.md")
    with open(path, encoding="utf-8") as f:
        lines = f.read().split("\n")
    transitions = {t["id"]: t for t in w["transitions"]}
    nav = {n["id"] for n in w["navActions"]["items"]}
    states = {s["id"] for s in w["states"]}
    extra = {"grouping", "bulk.createsGroup"}

    def rows(title):
        i = lines.index(title)
        table = []
        for line in lines[i + 1 :]:
            if line.startswith("#"):
                break
            if line.startswith("|"):
                table.append([c.strip() for c in line.strip("|").split("|")])
        head = table[0]
        if "В машине" not in head:
            err.append(f"правила, {title[4:]}: нет колонки «В машине»")
            return []
        return [dict(zip(head, r)) for r in table[2:]]

    found = {"transition": set(), "nav": set()}
    for title, kind in (("### 6.1. Ручные переходы", "transition"), ("### 6.2. Автоматические переходы", "transition"), ("### 6.3. Действия без смены состояния", "nav")):
        for row in rows(title):
            name = re.sub(r"\*", "", next(iter(row.values())))
            ids = re.findall(r"`([^`]+)`", row["В машине"])
            known = transitions if kind == "transition" else nav
            for i in ids:
                if i in known:
                    found[kind].add(i)
                elif i not in extra:
                    err.append(f"правила, «{name}»: в колонке «В машине» `{i}` — такого в машине нет")
            mine = [i for i in ids if i in transitions]
            if kind != "transition" or len(mine) != 1:
                continue
            t = transitions[mine[0]]
            got_from = set(re.findall(r"`(\w+)`", row.get("Откуда", ""))) & states
            if got_from != set(t["from"]):
                err.append(f"правила, «{name}»: откуда {sorted(got_from)}, в машине `{t['id']}` — {sorted(t['from'])}")
            got_to = set(re.findall(r"`(\w+)`", row.get("Куда", ""))) & states
            if got_to != ({t["to"]} if t.get("to") else set()):
                err.append(f"правила, «{name}»: куда {sorted(got_to) or 'не меняется'}, в машине `{t['id']}` — {t.get('to') or 'не меняется'}")
    for i in sorted(set(transitions) - found["transition"]):
        err.append(f"переход машины `{i}` не упомянут в правилах (§6.1, §6.2, колонка «В машине»)")
    for i in sorted(nav - found["nav"]):
        err.append(f"действие машины `{i}` не упомянуто в правилах (§6.3, колонка «В машине»)")


def check_rules_diagram(w, err):
    """Диаграмма §3 правил показывает каждую смену состояния машины (RULE-35): для перехода с
    `to` — стрелка «откуда → куда». Переходы без смены состояния (нарушения, потолок) не рисуются."""
    path = os.path.join(ROOT, "Specification", "State_rules", "States rules IM.md")
    with open(path, encoding="utf-8") as f:
        text = f.read()
    block = text.split("```mermaid", 1)[1].split("```", 1)[0]
    drawn = set(re.findall(r"^\s*(\w+) --> (\w+)", block, re.M))
    initial = [s["id"] for s in w["states"] if s.get("initial")]
    starts = re.findall(r"^\s*\[\*\] --> (\w+)", block, re.M)
    if initial and starts != initial[:1]:
        err.append(f"диаграмма §3 правил: начало [*] ведёт в {starts}, а начальное состояние машины — {initial[0]} (RULE-46)")
    for t in w["transitions"]:
        if not t.get("to"):
            continue
        for src in t["from"]:
            if (src, t["to"]) not in drawn:
                err.append(f"диаграмма §3 правил: нет стрелки {src} → {t['to']} (переход `{t['id']}`)")


def check_fixture_journal(w, err):
    """Записи журнала эталонного набора — по шаблонам, которые пишет машина или сам сервер
    (DATA-04): история в наборе выглядит так, как её записала бы система."""
    with open(os.path.join(ROOT, "Specification", "State_machine", "fixtures", "demo.json"), encoding="utf-8") as f:
        fx = json.load(f)
    with open(os.path.join(ROOT, "prototype", "server.js"), encoding="utf-8") as f:
        server = f.read()
    known = {e["args"][0] for t in w["transitions"] for e in t.get("effects", []) if e["fn"] == "appendLog"}
    known |= set(re.findall(r'log\(ev, [^,]+, "([^"]+)"', server)) | set(re.findall(r'\bk: "([^"]+)"', server))
    for inc in fx["incidents"]:
        for entry in inc.get("journal", []):
            template = entry.get("template") or ""
            if "{" in template and template not in known:
                err.append(f"эталон: {inc['number']} — запись журнала по шаблону, которого нет ни в машине, ни в сервере: «{template}»")


def check_doc_numbers(w, o, err):
    """Числа и версия правил в документах совпадают с машиной и контрактом (PROC-09). Фраза
    ищется по образцу; не нашлась — тоже ошибка, иначе проверка молча перестала бы работать."""
    words = {"одна": 1, "две": 2, "три": 3, "четыре": 4, "пять": 5, "шесть": 6}
    ops = [op for item in o["paths"].values() for m, op in item.items() if m in ("get", "post", "put", "patch", "delete")]
    test_ops = sum(1 for op in ops if "test-support" in (op.get("tags") or []))
    manual = sum(1 for t in w["transitions"] if t["trigger"] == "manual")
    with open(os.path.join(ROOT, "Specification", "State_rules", "States rules IM.md"), encoding="utf-8") as f:
        version = int(re.search(r"Версия: \*\*v(\d+)\*\*", f.read()).group(1))

    def text(*parts):
        with open(os.path.join(ROOT, *parts), encoding="utf-8") as f:
            return f.read()

    docs = {
        "README машины": text("Specification", "State_machine", "README.md"),
        "BACKEND.md": text("Specification", "State_machine", "BACKEND.md"),
        "корневой README": text("README.md"),
        "машина ($comment)": w.get("$comment", ""),
        "контракт (info.description)": o["info"].get("description", ""),
    }
    num = lambda v: words.get(v, int(v) if v.isdigit() else -1)
    checks = [
        ("README машины", r"\*\*OpenAPI 3\.1\*\* — (\d+) адрес\w*, (\d+) операц\w*, (\d+) схем", [("адресов", len(o["paths"])), ("операций", len(ops)), ("схем", len(o["components"]["schemas"]))]),
        ("README машины", r"(\d+) переход\w* \((\d+) ручн\w* \+ (\d+) автоматическ\w*\), (\d+) форм", [("переходов", len(w["transitions"])), ("ручных", manual), ("автоматических", len(w["transitions"]) - manual), ("форм", len(w["forms"]))]),
        ("README машины", r"описывает (\w+) служебн\w+ операц", [("служебных операций", test_ops)]),
        ("README машины", r"Нужны (\w+) операции выше", [("служебных операций", test_ops)]),
        ("README машины", r"приведена к v(\d+)", [("версия правил", version)]),
        ("BACKEND.md", r"(\d+) операц\w*, плюс (\d+) служебн", [("операций", len(ops) - test_ops), ("служебных", test_ops)]),
        ("BACKEND.md", r"(\d+) состояни\w*, (\d+) переход\w*, (\d+) услови\w*, (\d+) эффект", [("состояний", len(w["states"])), ("переходов", len(w["transitions"])), ("условий", len(w["registries"]["guards"])), ("эффектов", len(w["registries"]["effects"]))]),
        ("BACKEND.md", r"нужны (\w+) служебные операции", [("служебных операций", test_ops)]),
        ("корневой README", r"сейчас версия (\d+)", [("версия правил", version)]),
        ("корневой README", r"Приведена к правилам v(\d+)", [("версия правил", version)]),
        ("машина ($comment)", r"версия v(\d+)", [("версия правил", version)]),
        ("контракт (info.description)", r"\(v(\d+) и изменения после неё", [("версия правил", version)]),
    ]
    for doc, pattern, expected in checks:
        found = re.findall(pattern, docs[doc])
        if len(found) != 1:
            err.append(f"{doc}: фраза с числами не найдена или повторяется ({pattern}) — обновите текст или проверку в check_doc_numbers")
            continue
        values = found[0] if isinstance(found[0], tuple) else (found[0],)
        for (name, real), got in zip(expected, values):
            if num(got) != real:
                err.append(f"{doc}: {name} — {got}, а на самом деле {real}")


_MISSING = object()


def setting_at(w, path):
    """Значение по пути настройки: ключи через точку, у списка — элемент по id."""
    cur = w
    for seg in path.split("."):
        if isinstance(cur, list):
            cur = next((x for x in cur if isinstance(x, dict) and x.get("id") == seg), _MISSING)
        elif isinstance(cur, dict):
            cur = cur.get(seg, _MISSING)
        else:
            return _MISSING
        if cur is _MISSING:
            return _MISSING
    return cur


MANUAL_ONLY = ("form", "bulk", "requiredStepSet", "labelKey", "hint", "concurrency", "bypassesPermissions")


def check_automatic_fields(w, err):
    """У автоматических переходов нет полей ручных (DOC-19): кнопок и форм у них нет, а «ручное
    выигрывает у таймера» и «права не участвуют» — общие правила (invariants, §6.2)."""
    for t in w["transitions"]:
        if t["trigger"] != "manual":
            for key in MANUAL_ONLY:
                if key in t:
                    err.append(f"переход {t['id']}: поле {key} у автоматического перехода не нужно — кнопок и форм у него нет, права не участвуют (DOC-19)")


def check_registry_used(w, err):
    """Каждая запись реестра где-то используется (DOC-17): иначе бэкенд реализует мёртвый код.
    Ищем по всей машине, кроме самого реестра; requiredStepsFilled вызывает поле requiredStepSet."""
    used = set()

    def walk(node):
        if isinstance(node, dict):
            if isinstance(node.get("fn"), str):
                used.add(node["fn"])
            if node.get("requiredStepSet") or node.get("requiredStepsFilled"):
                used.add("requiredStepsFilled")
            for v in node.values():
                walk(v)
        elif isinstance(node, list):
            for v in node:
                walk(v)

    walk({k: v for k, v in w.items() if k != "registries"})
    for kind in ("guards", "effects"):
        for entry in w["registries"][kind]:
            if entry["fn"] not in used:
                err.append(f"реестр: {entry['fn']} нигде в машине не используется — убрать или использовать (DOC-17)")


STATE_OWNERS = ("none", "transfer_target", "operator", "closed_by")


def check_state_owners(w, err):
    """Владелец состояния — из перечня (DOC-23): ничей, адресат передачи, оператор, кто закрыл.
    Группа — только адресат передачи («Ожидает принятия»), у «Нового» её не бывает (§2.1, §8.1)."""
    for s in w["states"]:
        if s.get("owner") not in STATE_OWNERS:
            err.append(f"состояние {s['id']}: owner «{s.get('owner')}» — одно из {', '.join(STATE_OWNERS)}")


def check_graph(w, err):
    """Граф состояний (RULE-46): ровно одно начальное, оно не терминальное; каждое состояние
    достижимо из него; у каждого нетерминального есть выход в другое состояние."""
    states = {s["id"]: s for s in w["states"]}
    initial = [s for s in states if states[s].get("initial")]
    if len(initial) != 1:
        err.append(f"граф: начальных состояний {len(initial)}, нужно ровно одно (initial: true)")
        return
    if states[initial[0]].get("terminal"):
        err.append(f"граф: начальное состояние {initial[0]} — терминальное")
    edges = {}
    for t in w["transitions"]:
        for src in t["from"]:
            if t.get("to") and t["to"] != src:
                edges.setdefault(src, set()).add(t["to"])
    seen, stack = {initial[0]}, [initial[0]]
    while stack:
        for nxt in edges.get(stack.pop(), ()):
            if nxt not in seen:
                seen.add(nxt)
                stack.append(nxt)
    for s in states:
        if s not in seen:
            err.append(f"граф: состояние {s} недостижимо из начального {initial[0]}")
        if not states[s].get("terminal") and not edges.get(s):
            err.append(f"граф: из нетерминального состояния {s} нет перехода в другое состояние — тупик")


def check_escalation_settings(w, o, err):
    """Настройки, от которых зависит, сработает ли хоть один переход по истёкшему нормативу (RULE-45):
    без них нарушение пропадает молча."""
    esc = w.get("escalation") or {}
    if not isinstance(esc.get("enabled"), bool):
        err.append("эскалация: escalation.enabled — true или false; иначе истёкшая реакция пропадёт молча (RULE-45)")
    allowed = o["components"]["schemas"]["EscalationPolicy"]["properties"]["onResolutionOverdue"]["enum"]
    if esc.get("onResolutionOverdue") not in allowed:
        err.append(f"эскалация: escalation.onResolutionOverdue — одно из {allowed}; иначе истёкший норматив закрытия пропадёт молча (RULE-45)")
    target = (w.get("alerts") or {}).get("target")
    if not isinstance(target, str) or not re.match(r"^(user|group):.+", target):
        err.append("алерты: alerts.target — user:… или group:…; иначе алерты некому отправить (RULE-43, RULE-45)")


def check_admin_settings(w, o, err):
    """Перечень настроек администратора (RULE-44): пути существуют, запросы есть в контракте,
    каждый ключ разделов-настроек — в перечне или в notSettings с причиной."""
    a = w.get("adminSettings")
    if not a:
        err.append("настройки: нет раздела adminSettings (RULE-44)")
        return
    paths = []
    for tab in a["tabs"]:
        if "items" in tab:
            for item in tab["items"]:
                paths.append(item["path"])
                current = setting_at(w, item["path"])
                if current is _MISSING:
                    err.append(f"настройки, вкладка «{tab['label']}»: пути {item['path']} в машине нет")
                # Подписи значений перечня (BUG-26): все значения из контракта, без лишних
                if "values" in item:
                    prop = item["path"].split(".")[-1]
                    enum = next((s["properties"][prop].get("enum") for s in o["components"]["schemas"].values() if prop in s.get("properties", {}) and s["properties"][prop].get("enum")), None)
                    if enum is not None and sorted(item["values"]) != sorted(enum):
                        err.append(f"настройки, {item['path']}: подписи значений {sorted(item['values'])}, а в контракте {sorted(enum)}")
                    elif current not in item["values"]:
                        err.append(f"настройки, {item['path']}: у значения «{current}» нет подписи")
        elif tab.get("source"):
            method, url = tab["source"].split(" ", 1)
            if method.lower() not in o["paths"].get(url, {}):
                err.append(f"настройки, вкладка «{tab['label']}»: запроса {tab['source']} нет в контракте")
    skipped = [n["path"] for n in a.get("notSettings", [])]
    for n in a.get("notSettings", []):
        if setting_at(w, n["path"]) is _MISSING:
            err.append(f"настройки: в notSettings пути {n['path']} в машине нет")
        if not n.get("why"):
            err.append(f"настройки: в notSettings у {n['path']} нет причины")
    for section in a["sections"]:
        value = w.get(section)
        if isinstance(value, list) and not all(isinstance(x, dict) and "id" in x for x in value):
            keys = [section]
        elif isinstance(value, list):
            keys = [f"{section}.{x['id']}" for x in value]
        else:
            keys = [f"{section}.{k}" for k in value if not k.startswith("$")]
        for key in keys:
            if not any(p == key or p.startswith(key + ".") or key.startswith(p + ".") for p in paths + skipped):
                err.append(f"настройки: {key} — ни в перечне adminSettings, ни в notSettings")


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
    check_layers(err)
    check_literals(w, err)
    check_rules_tables(w, err)
    check_rules_diagram(w, err)
    check_doc_numbers(w, o, err)
    check_fixture_journal(w, err)
    check_graph(w, err)
    check_state_owners(w, err)
    check_registry_used(w, err)
    check_automatic_fields(w, err)
    check_escalation_settings(w, o, err)
    check_admin_settings(w, o, err)
    check_fixture(w, err)
    check_api(w, o, err)
    for e in err:
        print(e)
    print(f"Ошибок в машине состояний: {len(err)}")
    return 1 if err else 0


if __name__ == "__main__":
    sys.exit(main())
