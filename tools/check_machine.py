#!/usr/bin/env python3
"""Проверка машины состояний: workflow_schema.v1.json и openapi.json сходятся сами с собой и между собой.

Запуск из корня репозитория: python3 tools/check_machine.py
Проверяет, что всё из реестров условий и эффектов реализовано в prototype/engine.js;
что переходы ссылаются на существующие состояния, формы, условия, эффекты,
права и таймеры; что справочники и фильтры очереди ссылаются на то,
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

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fixture  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIR = os.path.join(ROOT, "Specification", "Workflow_machine")


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
        # «Продолжить, если уже шёл» исполнитель не знает (RULE-97): привязанный — на паузе, срок у группы
        if "resumesOnEnter" in t:
            err.append(f"таймер {t['id']}: resumesOnEnter не поддерживается")

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
            if g["fn"] == "hasScopedPermission":
                for key in g["args"]:
                    if key not in perms:
                        err.append(f"переход {tid}: нет права {key}")
        for e in t.get("effects", []):
            if e["fn"] not in effects:
                err.append(f"переход {tid}: эффект {e['fn']} не в реестре")
            if e["fn"].endswith("Timer") and e["args"][0] not in timers:
                err.append(f"переход {tid}: нет таймера {e['args'][0]}")

    # Коды ошибок условий — из перечня Problem.code контракта (ARCH-08 в9)
    known = set(load("openapi.json")["components"]["schemas"]["Problem"]["properties"]["code"]["enum"])
    for g in w["registries"]["guards"]:
        for c in [g.get("errorCode")] + list((g.get("errorCodes") or {}).values()):
            if c and c not in known:
                err.append(f"условие {g['fn']}: кода ошибки {c} нет в Problem.code контракта")
    # Порядок очереди — ключами машины: у каждого порядка из options — свои ключи (ARCH-08 в3)
    for o in w["queueSort"]["options"]:
        if not (w["queueSort"].get("keys") or {}).get(o):
            err.append(f"порядок очереди {o}: нет ключей queueSort.keys")
    # Массовое действие — от bulk.minItems отмеченных: одно — всегда как одиночное (§11, BUG-79)
    for t in w["transitions"]:
        b = t.get("bulk") or {}
        if b.get("allowed") and not (isinstance(b.get("minItems"), int) and b["minItems"] >= 2):
            err.append(f"переход {t['id']}: bulk.minItems — целое от 2")
    for f in w["forms"]:
        for field in f["fields"]:
            src = field.get("source", "")
            if src.startswith("reasonCatalog:") and src.split(":", 1)[1] not in catalogs:
                err.append(f"форма {f['id']}: нет справочника {src}")

    # Результат «Итога» (finish) — один и только с обязательными шагами: им закрывают пройденный сценарий (ARCH-08 в7)
    finishing = [i for i in w["reasonCatalogs"].get("close_result", {}).get("items", []) if i.get("finish")]
    if len(finishing) != 1 or finishing[0].get("requiredStepSet") in (None, "none"):
        err.append("результаты закрытия: finish — ровно у одного, и у него есть набор обязательных шагов")
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

    exit_rule = w["validation"]["claimWithoutExitPermission"]
    for x in exit_rule["requiresAnyOf"] + exit_rule.get("appliesTo", []) + exit_rule.get("disables", []):
        if x not in perms:
            err.append(f"проверка §10.3: нет права {x}")
    # Без выхода из карточки не действует ни одно право входа в работу — и взять, и принять (RULE-102)
    for x in sorted(set(exit_rule.get("appliesTo", [])) - set(exit_rule.get("disables", []))):
        err.append(f"проверка §10.3: без выхода из карточки право {x} должно гаснуть (disables)")
    for s in w["validation"].get("typicalPermissionSets", {}).get("items", []):
        for x in s["permissions"]:
            if x not in perms:
                err.append(f"типовой набор {s['id']}: нет права {x}")
    # Состояния и категории в выражениях бейджей, фильтров и форм — словами машины (CEL.md, «Правила интерфейса»)
    ui = [(f"фильтр {q['id']}", q.get("expr", "")) for q in w["queueFilters"]]
    ui += [(f"бейдж {i + 1}", b.get("expr", "")) for i, b in enumerate(w["badges"]["rules"])]
    ui += [(f"форма {f['id']}", json.dumps(f, ensure_ascii=False)) for f in w["forms"]]
    for where, text in ui:
        for x in re.findall(r"\.state (?:==|!=) '(\w+)'", text) + [y for l in re.findall(r"\.state in \[([^\]]*)\]", text) for y in re.findall(r"'(\w+)'", l)]:
            if x not in states:
                err.append(f"{where}: нет состояния {x}")
        for l in re.findall(r"inCategory\([^,]+, \[([^\]]*)\]\)", text):
            for x in re.findall(r"'(\w+)'", l):
                if x not in cats:
                    err.append(f"{where}: нет категории {x}")
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
    for i, b in enumerate(w["badges"]["rules"]):
        # Подпись бейджа — только ключом каталога (§14.9): текст без ключа исполнитель не покажет (BUG-51, PROC-25)
        if not b.get("labelKey") or "label" in b:
            err.append(f"бейдж {i + 1} ({b.get('expr')}): подпись — не ключом каталога labelKey (BUG-51)")


def check_engine(w, err):
    """Смысл каждого слова реестров — в машине (CEL.md, ARCH-07): у условия expr, у эффекта do. Исполнитель
    прототипа своих правил не держит — разбор и типы выражений проверяет node tools/check_cel.mjs."""
    for kind, key in (("guards", "expr"), ("effects", "do")):
        for item in w["registries"][kind]:
            if key not in item:
                err.append(f"{'условие' if kind == 'guards' else 'эффект'} {item['fn']}: нет {key} — смысла слова в машине нет (ARCH-07)")
    path = os.path.join(ROOT, "prototype", "engine.js")
    with open(path, encoding="utf-8") as f:
        src = f.read()
    for block in ("GUARDS", "EFFECTS"):
        if f"const {block} = {{" in src:
            err.append(f"prototype/engine.js: снова таблица {block} — смысл условий и эффектов только в машине (ARCH-07)")

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
    """Эталонный набор fixtures/demo.json с файлами сценариев (tools/fixture.py): время — UTC и не позже снимка,
    ссылки на людей, устройства, состояния, справочники и сценарии существуют, таймеры соответствуют состоянию."""
    fx = fixture.load()
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
    # Дежурные группы (§8.1): участники — люди с одной из ролей группы плюс названные отдельно
    for g in people["dutyGroups"]:
        if not g.get("roles") and not g.get("members"):
            err.append(f"эталон: дежурная группа {g['id']} — ни ролей, ни участников")
        for m in g.get("members", []):
            if m not in humans:
                err.append(f"эталон: дежурная группа {g['id']} — нет человека {m}")
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
    entities += [("сценарий", r.get("guid")) for r in fx["scenarios"]["rows"]]
    entities += [("группа доступа", a.get("id")) for a in fx.get("accessGroups", [])]
    entities += [("связь камер", l.get("id")) for l in fx.get("cameraLinks", [])]
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
    # Связи камер (§19.1, RULE-49, RULE-70): многие-ко-многим — у связи название, хотя бы одно устройство
    # и одна камера, устройства существуют, в cameras — только камеры набора, без повторов внутри связи;
    # у инцидента своих камер нет — они из связей его источника
    for link in fx.get("cameraLinks", []):
        name = link.get("name") or link.get("id")
        if not link.get("name"):
            err.append(f"эталон: связь камер {link.get('id')} — без названия")
        if not link.get("devices") or not link.get("cameras"):
            err.append(f"эталон: связь камер «{name}» — пустая: нужны хотя бы одно устройство и одна камера")
        for dev in link.get("devices", []):
            if dev not in devices:
                err.append(f"эталон: связь камер «{name}» — нет устройства {dev}")
        for cam in link.get("cameras", []):
            if cam not in devices or fx_devices[cam].get("type") != "camera":
                err.append(f"эталон: связь камер «{name}» — {cam} не камера набора")
        for key in ("devices", "cameras"):
            if len(set(link.get(key, []))) != len(link.get(key, [])):
                err.append(f"эталон: связь камер «{name}» — повтор в {key}")
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
    # Хранимое состояние: производное (RULE-99) не хранится
    agent_states = {st["id"] for st in w["session"]["states"] if not st.get("derived")}
    for o in people["operators"]:
        if o.get("agentState") not in agent_states:
            err.append(f"эталон: у человека {o['id']} состояние agentState «{o.get('agentState')}» — нет среди хранимых в session.states машины (§12.1, RULE-99)")
        needs_reason = any(st["id"] == o.get("agentState") and st.get("requiresReason") for st in w["session"]["states"])
        if needs_reason and o.get("reasonId") not in {r["id"] for r in w["session"]["breakReasons"]}:
            err.append(f"эталон: у человека {o['id']} на перерыве причина reasonId «{o.get('reasonId')}» — нет в session.breakReasons (§12.1)")
        if not needs_reason and o.get("reasonId") is not None:
            err.append(f"эталон: у человека {o['id']} причина reasonId без перерыва (§12.1)")
        if not isinstance(o.get("roles"), list) or not o["roles"]:
            err.append(f"эталон: у оператора {o['id']} нет ролей (roles) — ему ничего не видно (§5)")
    for kind, value in entities:
        if not isinstance(value, str) or not uuid.match(value):
            err.append(f"эталон: {kind} «{value}» — идентификатор не UUID")
    # Идентификатор связи камер — свой: не повторяется и не совпадает с другой сущностью набора
    link_ids = [l.get("id") for l in fx.get("cameraLinks", [])]
    others = {v for k, v in entities if k != "связь камер"}
    for lid in set(link_ids):
        if link_ids.count(lid) > 1 or lid in others:
            err.append(f"эталон: связь камер {lid} — идентификатор не уникален")
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
        # Сценарий и прохождение инцидента проверяет tools/check_scenarios.py (машина сценариев)
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
        # Норматив закрытия, однажды запущенный, у нового и ожидающего принятия стоит с остатком (§4, правило 6):
        # инцидент брали в работу и вернули или передали — он не идёт, а leftSec
        paused = st in ("new", "pending_acceptance") and "leftSec" in (t.get("resolution") or {})
        running = tuple(n for n in ("reaction", "resolution", "hold") if t.get(n) and not (n == "resolution" and paused))
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
            if limit is not None and n > limit:
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


def check_rules_example(w, err):
    """Пример строки схемы в §14.8 правил — точная копия перехода машины с тем же id (DOC-35):
    разработчик берёт его за образец. Сравниваются данные, а не текст."""
    path = os.path.join(ROOT, "Specification", "State_rules", "States rules IM.md")
    with open(path, encoding="utf-8") as f:
        text = f.read()
    section = text.split("### 14.8.", 1)[1].split("\n### ", 1)[0]
    found = re.search(r"```json\n(.*?)\n```", section, re.S)
    if not found:
        err.append("§14.8 правил: нет примера строки схемы в блоке ```json")
        return
    try:
        example = json.loads(found.group(1))
    except json.JSONDecodeError as e:
        err.append(f"§14.8 правил: пример — не JSON ({e})")
        return
    machine = next((t for t in w["transitions"] if t["id"] == example.get("id")), None)
    if machine is None:
        err.append(f"§14.8 правил: в машине нет перехода `{example.get('id')}` из примера")
    elif example != machine:
        diff = sorted(k for k in set(example) | set(machine) if example.get(k) != machine.get(k))
        err.append(f"§14.8 правил: пример `{example['id']}` расходится с машиной — {', '.join(diff)}")


def check_fixture_journal(w, err):
    """Записи журнала эталонного набора — те, что пишут машина и сервер (DATA-04, DATA-05): ключ
    записи журнала из машины (appendLog, messages, alerts.noRecipientLog) и ровно его подстановки
    по русской строке каталога (§14.9). История в наборе выглядит так, как её записала бы система."""
    with open(os.path.join(ROOT, "Specification", "Workflow_machine", "fixtures", "demo.json"), encoding="utf-8") as f:
        fx = json.load(f)
    with open(os.path.join(DIR, "strings", "ru.json"), encoding="utf-8") as f:
        ru = json.load(f)
    known = {e["args"][0] for t in w["transitions"] for e in t.get("effects", []) if e["fn"] == "appendLog"}
    known |= {k for k in w.get("messages", {}) if k.startswith("workflow.journal.")} | {w["alerts"]["noRecipientLog"]}
    for inc in fx["incidents"]:
        for entry in inc.get("journal", []):
            key = entry.get("template") or ""
            if key not in known:
                err.append(f"эталон: {inc['number']} — запись журнала «{key}», которой машина и сервер не пишут (DATA-05)")
                continue
            need = set(re.findall(r"\{\s*(\w+)\s*[,}]", ru.get(key, "")))
            if set(entry.get("vars") or {}) != need:
                err.append(f"эталон: {inc['number']} — у записи {key} подстановки {sorted(entry.get('vars') or {})}, а нужны {sorted(need)}")


def check_fixture_history(w, err):
    """Журнал каждого инцидента эталонного набора — цепочка переходов машины (DATA-06): первая
    запись — появление (`create` или текст источника), каждая запись перехода — из того состояния,
    где инцидент был, последняя приводит в его состояние; записи идут по времени, а у закрытого
    время закрытия — время записи «Закрыто». Число передач — transferCount, уровень эскалации без
    автоэскалации в журнале — 0 (RULE-76). Записи, которые не переходы (макрос, шаг сценария), не
    меняют состояние."""
    with open(os.path.join(ROOT, "Specification", "Workflow_machine", "fixtures", "demo.json"), encoding="utf-8") as f:
        fx = json.load(f)
    by_key = {}
    for t in w["transitions"]:
        for e in t.get("effects", []):
            if e["fn"] == "appendLog":
                by_key.setdefault(e["args"][0], []).append(t)
    appear = {"workflow.journal.create", "workflow.journal.source"}
    # «Закрыть» из состояния — по строке результата закрытия (fromStates), а не по from перехода
    close_from = {r["id"]: r["fromStates"] for r in w["reasonCatalogs"]["close_result"]["items"]}
    prefix = "workflow.catalog.close_result."
    for inc in fx["incidents"]:
        n, journal = inc["number"], inc.get("journal", [])
        if not journal or journal[0].get("template") not in appear:
            err.append(f"эталон: {n} — журнал начинается не с появления инцидента (DATA-06)")
            continue
        state, last, close_at = "new", journal[0]["at"], None
        for entry in journal[1:]:
            key = entry.get("template")
            if entry["at"] < last:
                err.append(f"эталон: {n} — запись {key} раньше предыдущей ({entry['at']} < {last})")
            last = entry["at"]
            if key in appear:
                err.append(f"эталон: {n} — второе появление в журнале ({key})")
                continue
            if key not in by_key:
                continue
            tr = next((t for t in by_key[key] if state in t["from"]), None)
            if not tr:
                err.append(f"эталон: {n} — запись {key}: переход {', '.join(t['id'] for t in by_key[key])} не идёт из «{state}» (DATA-06)")
                break
            if tr["id"] == "close":
                label = ((entry.get("vars") or {}).get("closeResultLabel") or [""])[0]
                result = label[len(prefix):] if label.startswith(prefix) else inc.get("closeResult")
                if state not in close_from.get(result, []):
                    err.append(f"эталон: {n} — закрыт «{result}» из «{state}», а этот результат — только из {close_from.get(result)} (DATA-06)")
                    break
            state = tr["to"] or state
            if state == "closed":
                close_at = entry["at"]
        else:
            if state != inc["state"]:
                err.append(f"эталон: {n} — журнал приводит в «{state}», а у инцидента «{inc['state']}» (DATA-06)")
            # Передачи считает transferCount; уровень меняет только автоэскалация (RULE-76)
            keys = [e.get("template") for e in journal]
            transfers = keys.count("workflow.journal.transfer")
            escalated = any(k in ("workflow.journal.auto_escalate", "workflow.journal.resolution_escalate") for k in keys)
            if (inc.get("transferCount") or 0) != transfers:
                err.append(f"эталон: {n} — transferCount {inc.get('transferCount') or 0}, а передач в журнале {transfers} (RULE-76)")
            if not escalated and inc.get("escalationLevel"):
                err.append(f"эталон: {n} — уровень эскалации {inc['escalationLevel']}, а автоэскалации в журнале нет: передача уровень не меняет (RULE-76)")
            elif state == "closed" and inc.get("closedAt") != close_at:
                err.append(f"эталон: {n} — время закрытия {inc.get('closedAt')}, а запись «Закрыто» — {close_at}")


def check_fixture_media(err):
    """Панели инцидента эталонного набора (`media`, в API `mediaKinds`, §19.1) сходятся с камерами
    и планом (DATA-07): камеры есть — видео не скрыто; карта — только если есть план. Камеры — из
    связей источника, план — тот, где стоит источник, устройство или камера события, иначе план
    площадки (как planOf сервера)."""
    with open(os.path.join(ROOT, "Specification", "Workflow_machine", "fixtures", "demo.json"), encoding="utf-8") as f:
        fx = json.load(f)
    devices = {d["id"]: d for d in fx["devices"]}
    for inc in fx["incidents"]:
        src = inc["devices"][0]
        cameras = [c for link in fx["cameraLinks"] if src in link["devices"] for c in link["cameras"]]
        placed = next((devices[i]["position"] for i in [*inc["devices"], *cameras] if (devices.get(i) or {}).get("position")), None)
        plan = next((p for p in fx["plans"] if (p["id"] == placed["plan"] if placed else p["site"] == inc["site"])), None)
        media = inc.get("media")
        if media not in ("video", "map", "both"):
            err.append(f"эталон: {inc['number']} — media «{media}», а нужно video, map или both (§19.1)")
        elif cameras and media == "map":
            err.append(f"эталон: {inc['number']} — видео скрыто (media «map»), а камер по связям источника {len(cameras)} (DATA-07)")
        elif not cameras and media != "map":
            err.append(f"эталон: {inc['number']} — media «{media}», а камер по связям источника нет")
        elif not plan and media != "video":
            err.append(f"эталон: {inc['number']} — media «{media}», а плана нет")


def check_doc_numbers(w, o, err):
    """Числа и версия правил в документах совпадают с машиной и контрактом (PROC-09). Фраза
    ищется по образцу; не нашлась — тоже ошибка, иначе проверка молча перестала бы работать."""
    words = {"одна": 1, "две": 2, "три": 3, "четыре": 4, "пять": 5, "шесть": 6}
    ops = [op for item in o["paths"].values() for m, op in item.items() if m in ("get", "post", "put", "patch", "delete")]
    test_ops = sum(1 for op in ops if "test-support" in (op.get("tags") or []))
    manual = sum(1 for t in w["transitions"] if t["trigger"] == "manual")
    with open(os.path.join(ROOT, "Specification", "State_rules", "States rules IM.md"), encoding="utf-8") as f:
        version = int(re.search(r"Версия: \*\*v(\d+)\*\*", f.read()).group(1))
    # Операции, которые тесты API не проверяют, — по выражению NOT_COVERED из tests/harness.js (DOC-38)
    with open(os.path.join(ROOT, "tests", "harness.js"), encoding="utf-8") as f:
        not_covered = re.compile(re.search(r"const NOT_COVERED = /(.+)/;", f.read()).group(1).replace("\\/", "/"))
    skipped = [f"{m.upper()} {path}" for path, item in o["paths"].items() for m in item if m in ("get", "post", "put", "patch", "delete")]
    skipped = [op for op in skipped if not_covered.search(op)]
    skipped_schemas = sum(1 for op in skipped if "/workflow/schemas" in op)
    skipped_priorities = sum(1 for op in skipped if "/admin/priorities" in op)

    def text(*parts):
        with open(os.path.join(ROOT, *parts), encoding="utf-8") as f:
            return f.read()

    docs = {
        "README машины": text("Specification", "Workflow_machine", "README.md"),
        "BACKEND.md": text("Specification", "Workflow_machine", "BACKEND.md"),
        "корневой README": text("README.md"),
        "машина ($comment)": w.get("$comment", ""),
        "контракт (info.description)": o["info"].get("description", ""),
    }
    num = lambda v: words.get(v, int(v) if v.isdigit() else -1)
    checks = [
        ("README машины", r"\*\*OpenAPI 3\.1\*\* — (\d+) адрес\w*, (\d+) операц\w*, (\d+) схем", [("адресов", len(o["paths"])), ("операций", len(ops)), ("схем", len(o["components"]["schemas"]))]),
        ("README машины", r"(\d+) переход\w* \((\d+) ручн\w* \+ (\d+) автоматическ\w* \+ появление\), (\d+) форм", [("переходов", len(w["transitions"])), ("ручных", manual), ("автоматических", len(automatic(w))), ("форм", len(w["forms"]))]),
        ("README машины", r"описывает (\w+) служебн\w+ операц", [("служебных операций", test_ops)]),
        ("README машины", r"Нужны (\w+) операции выше", [("служебных операций", test_ops)]),
        ("README машины", r"приведена к v(\d+)", [("версия правил", version)]),
        ("BACKEND.md", r"(\d+) операц\w*, плюс (\d+) служебн", [("операций", len(ops) - test_ops), ("служебных", test_ops)]),
        ("BACKEND.md", r"(\d+) состояни\w*, (\d+) переход\w*, (\d+) услови\w*, (\d+) эффект", [("состояний", len(w["states"])), ("переходов", len(w["transitions"])), ("условий", len(w["registries"]["guards"])), ("эффектов", len(w["registries"]["effects"]))]),
        ("BACKEND.md", r"нужны (\w+) служебные операции", [("служебных операций", test_ops)]),
        ("BACKEND.md", r"Тесты не проверяют (\d+) операц\w*: редактор схемы \(`[^`]+`, (\d+)\) и правку справочника приоритетов \(`[^`]+`, (\d+)\)", [("непроверяемых операций", len(skipped)), ("редактора схемы", skipped_schemas), ("правки приоритетов", skipped_priorities)]),
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


MANUAL_ONLY = ("form", "bulk", "requiredStepSet", "hintKey", "concurrency", "bypassesPermissions")


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


def check_registry_comments(w, err):
    """Функции сверх базового реестра §14.8 реализует бэкенд: у каждой — описание в $comment (DOC-26)."""
    for kind in ("guards", "effects"):
        for entry in w["registries"][kind]:
            if entry.get("extendsBaseRegistry") and not str(entry.get("$comment", "")).strip():
                err.append(f"реестр: {entry['fn']} сверх базового реестра без $comment — бэкенду нечего реализовать (DOC-26)")


STATE_OWNERS = ("none", "transfer_target", "operator", "closed_by")


def check_timer_declarations(w, err):
    """Описание таймеров против эффектов переходов, в обе стороны (RULE-51, DOC-25). Если таймер идёт
    в исходном состоянии, а по описанию в новом он запускается, останавливается или встаёт на паузу —
    эффекты перехода должны это делать; исключение — переходы из continuesOn: таймер продолжается
    (§8.1). И наоборот: эффект, который при смене
    состояния запускает, останавливает или ставит на паузу таймер, должен быть в описании. Переходы
    без смены состояния — нарушения — не в счёт."""
    timers = {t["id"]: t for t in w["timers"]}
    transitions = {t["id"] for t in w["transitions"]}
    start, stop, pause = {"startTimer", "restartTimer", "resumeTimer"}, {"stopTimer", "pauseTimer"}, {"pauseTimer"}

    def running(timer, state):
        return state in (timer.get("startsOnEnter") or []) and state not in (timer.get("pausedInStates") or [])

    for timer in timers.values():
        for tid in timer.get("continuesOn", []):
            if tid not in transitions:
                err.append(f"таймер {timer['id']}: в continuesOn нет перехода {tid}")
    for tr in w["transitions"]:
        if not tr.get("to"):
            continue
        done = {}
        for e in tr["effects"]:
            if e["fn"] == "resumeTimer" and len(e.get("args") or []) > 1:
                err.append(f"переход {tr['id']}: у resumeTimer один аргумент — таймер, {e['args'][1:]} исполнитель не знает")
            if e["fn"] in start | stop and e.get("args"):
                done.setdefault(e["args"][0], set()).add(e["fn"])
        for src in tr["from"]:
            for tid, timer in timers.items():
                if not running(timer, src):
                    continue
                got = done.get(tid, set())
                if tr["to"] in (timer.get("startsOnEnter") or []) and not got & start and tr["id"] not in timer.get("continuesOn", []):
                    err.append(f"таймер {tid}: по описанию запускается при входе в {tr['to']}, а {tr['id']} из {src} его не запускает и не указан в continuesOn (RULE-51)")
                if tr["to"] in (timer.get("stopsOnEnter") or []) and not got & stop:
                    err.append(f"таймер {tid}: по описанию останавливается при входе в {tr['to']}, а {tr['id']} из {src} его не останавливает (RULE-51)")
                if tr["to"] in (timer.get("pausedInStates") or []) and not got & pause:
                    err.append(f"таймер {tid}: по описанию на паузе в {tr['to']}, а {tr['id']} из {src} его не ставит на паузу (RULE-51)")
                if got & stop and tr["to"] not in (timer.get("stopsOnEnter") or []) + (timer.get("pausedInStates") or []):
                    err.append(f"таймер {tid}: {tr['id']} из {src} останавливает его при входе в {tr['to']}, а в описании этого нет (DOC-25)")
        # Запуск — в описании: вход в состояние из startsOnEnter
        for tid in done:
            if done[tid] & start and tid in timers and tr["to"] not in (timers[tid].get("startsOnEnter") or []):
                err.append(f"таймер {tid}: {tr['id']} запускает его при входе в {tr['to']}, а в описании этого нет (DOC-25)")


# Условия автоматических переходов как «переменная = значение» — для перебора настроек и карты
# пересечений (im-fsm). Новое условие у автоматического перехода нужно описать здесь. Это карта для чтения по
# именам: смысл условия — его expr в машине (ARCH-07), и «ровно один переход по истёкшему таймеру» на настоящих
# выражениях проверяет модель Quint — timerTransitionsExclusive и dueDeadlineHandled на всех сочетаниях
# настроек BRANCH_SETTINGS (PROC-43)
def guard_terms(g):
    fn, a = g["fn"], g.get("args", [])
    return {
        "timerExpired": lambda: ("timer", a[0]),
        "settingEnabled": lambda: (a[0], True),
        "settingIs": lambda: (a[0], a[1]),
        "escalationTargetAvailable": lambda: ("адресат уровня есть", a[0]),
        "agentStateIs": lambda: ("состояние оператора", a[0]),
        "agentIdleFor": lambda: ("молчание " + a[0], True),
        "ownerHasDutyGroup": lambda: ("у владельца есть дежурная группа", a[0]),
        "addresseeHasAccess": lambda: ("у адресата есть доступ", a[0]),
        "addresseeCanAccept": lambda: ("адресат может принять", a[0]),
        "holdReasonIn": lambda: ("причина удержания в " + ",".join(a[0]), True),
        "primaryClosed": lambda: ("основной закрыт", True),
        "primaryAddresseeHasAccess": lambda: ("у адресата основного есть доступ", a[0]),
    }.get(fn, lambda: None)()


def automatic(w):
    """Переходы планировщика (timer, system); появление (trigger: event) выполняет не он (RULE-61)."""
    return [t for t in w["transitions"] if t["trigger"] in ("timer", "system")]


def fsm_terms(w, err):
    """Переменные условий каждого автоматического перехода; неизвестное условие — ошибка."""
    out = {}
    for t in automatic(w):
        terms = []
        for g in t["guards"]:
            term = guard_terms(g)
            if term is None:
                err.append(f"переход {t['id']}: условие {g['fn']} не описано для перебора — добавьте его в guard_terms (im-fsm)")
            else:
                terms.append(term)
        out[t["id"]] = terms
    return out


def compatible(a, b):
    """Могут ли условия двух переходов выполняться одновременно: нет переменной с разными значениями.
    Доступа нет — значит и принять нельзя; доступ адресата основного — только у открытого основного."""
    va, vb = dict(a), dict(b)
    for k in set(va) & set(vb):
        if k != "timer" and va[k] != vb[k]:
            return False
    merged = {**va, **vb}
    if merged.get("у адресата есть доступ") is False and merged.get("адресат может принять") is True:
        return False
    # Доступ адресата основного проверяется только у открытого основного (primaryAddresseeHasAccess, PROC-38)
    if "у адресата основного есть доступ" in merged and merged.get("основной закрыт") is True:
        return False
    return True


def setting_domain(path, values, o):
    """Значения настройки: перечень из контракта, логическое — да и нет, иначе встреченные в машине."""
    prop = path.split(".")[-1]
    enum = next((s["properties"][prop].get("enum") for s in o["components"]["schemas"].values() if prop in s.get("properties", {}) and s["properties"][prop].get("enum")), None)
    if enum:
        return enum
    if all(isinstance(v, bool) for v in values):
        return [True, False]
    return sorted(set(values), key=str)


def check_settings_matrix(w, o, err, show=False):
    """Перебор настроек (im-fsm, RULE-40, RULE-45): для каждого состояния и таймера — при любом
    сочетании настроек и «адресат уровня есть / нет» срабатывает ровно один переход."""
    import itertools
    terms = fsm_terms(w, [])
    rows = []
    for state in [s["id"] for s in w["states"]]:
        groups = {}
        for t in automatic(w):
            if state in t["from"]:
                timer = dict(terms[t["id"]]).get("timer")
                if timer:
                    groups.setdefault(timer, []).append(t)
        for timer, group in groups.items():
            values = {}
            for t in group:
                for k, v in terms[t["id"]]:
                    if k != "timer":
                        values.setdefault(k, []).append(v)
            names = sorted(values)
            domains = [setting_domain(k, values[k], o) if "." in k else [True, False] for k in names]
            for combo in itertools.product(*domains):
                env = dict(zip(names, combo))
                fired = [t["id"] for t in group if all(k == "timer" or env.get(k) == v for k, v in terms[t["id"]])]
                rows.append((state, timer, env, fired))
                if len(fired) != 1:
                    err.append(f"перебор настроек: {state}, истёк {timer}, {env} — срабатывает {fired or 'ничего'}, нужен ровно один (im-fsm)")
    if show:
        print("\nПеребор настроек: состояние | таймер | сочетание | сработает")
        for state, timer, env, fired in rows:
            print(f"  {state} | {timer} | {env} | {', '.join(fired) or '—'}")


def show_overlaps(w):
    """Карта пересечений (im-fsm): пары автоматических переходов одного состояния, которые могут быть
    готовы одновременно. Первым по §14.3 выполняется тот, чьё условие наступило раньше; при равенстве —
    порядок в машине. Пары с разным итогом, где оба события наступают по времени, проверяют тесты «im-fsm:» (tests/api-fsm.js)."""
    terms = fsm_terms(w, [])
    order = {t["id"]: i for i, t in enumerate(w["transitions"])}
    kind = lambda t: "таймер" if dict(terms[t["id"]]).get("timer") else "молчание" if any(k.startswith("молчание") for k, _ in terms[t["id"]]) else "сразу"
    print("\nКарта пересечений: состояние | переход A (момент) | переход B (момент) | итог A / B | при равенстве первым")
    print("  момент таймера — дедлайн; окно после него ждёт только действия человека (§10.1, правило 5; RULE-67)")
    for state in [s["id"] for s in w["states"]]:
        auto = [t for t in automatic(w) if state in t["from"]]
        for a, b in itertools_pairs(auto):
            same_timer = dict(terms[a["id"]]).get("timer") and dict(terms[a["id"]]).get("timer") == dict(terms[b["id"]]).get("timer")
            if same_timer or not compatible(terms[a["id"]], terms[b["id"]]):
                continue
            first = a if order[a["id"]] < order[b["id"]] else b
            diff = "разный" if (a["to"] or state) != (b["to"] or state) else "одинаковый"
            print(f"  {state} | {a['id']} ({kind(a)}) | {b['id']} ({kind(b)}) | {a['to'] or '—'} / {b['to'] or '—'} ({diff}) | {first['id']}")


def continuing_in_window(w):
    """Ручные переходы, после которых таймер продолжается (continuesOn), из состояний, где по этому таймеру
    есть переход: в окне после дедлайна они срабатывание не отменяют (§10.1, правило 5; RULE-83). Список —
    (таймер, переход, из, в, переходы по таймеру до, после); сценарии — набор CONTINUING в tests/api-fsm.js."""
    by_timer = {}
    for t in w["transitions"]:
        g = next((g for g in t["guards"] if g["fn"] == "timerExpired"), None)
        if t["trigger"] == "timer" and g:
            by_timer.setdefault(g["args"][0], []).append(t)
    rows = []
    for timer in w["timers"]:
        for tid in timer.get("continuesOn", []):
            t = next((x for x in w["transitions"] if x["id"] == tid), None)
            if not t or t["trigger"] != "manual":
                continue
            for src in t["from"]:
                before = [x["id"] for x in by_timer.get(timer["id"], []) if src in x["from"]]
                if before:
                    dst = t["to"] or src
                    after = [x["id"] for x in by_timer.get(timer["id"], []) if dst in x["from"]]
                    rows.append((timer["id"], tid, src, dst, before, after))
    return rows


def show_continuing(w):
    print("\nРучные переходы в окне, после которых таймер продолжается (RULE-83): таймер | переход | из → в | по таймеру до / после")
    print("  срабатывание не отменяется — выполняется по окончании окна, из нового состояния; сценарии — CONTINUING в tests/api-fsm.js")
    for timer, tid, src, dst, before, after in continuing_in_window(w):
        print(f"  {timer} | {tid} | {src} → {dst} | {', '.join(before)} / {', '.join(after) or '—'}")


def itertools_pairs(items):
    import itertools
    return itertools.combinations(items, 2)


def check_work_rights(w, err):
    """В «В работе» — только по праву взятия или принятия; у типового набора прав с ними — выход
    из карточки (§10.3, RULE-36, RULE-38)."""
    enter = set(w["validation"]["claimWithoutExitPermission"]["appliesTo"])
    for t in w["transitions"]:
        if t["trigger"] == "manual" and t.get("to") == "in_progress":
            rights = {g["args"][0] for g in t["guards"] if g["fn"] == "hasPermission"}
            if not rights & enter:
                err.append(f"переход {t['id']}: ведёт в «В работе» без права взятия или принятия (§10.3)")
    exits = set(w["validation"]["claimWithoutExitPermission"]["requiresAnyOf"])
    for s in w["validation"].get("typicalPermissionSets", {}).get("items", []):
        if set(s["permissions"]) & enter and not set(s["permissions"]) & exits:
            err.append(f"типовой набор {s['id']}: может взять или принять, но выйти из карточки нечем (§10.3)")


def check_state_owners(w, err):
    """Владелец состояния — из перечня (DOC-23): ничей, адресат передачи, оператор, кто закрыл.
    Группа — только адресат передачи («Ожидает принятия»), у «Нового» её не бывает (§2.1, §8.1)."""
    timers = {t["id"] for t in w["timers"]}
    for s in w["states"]:
        if s.get("owner") not in STATE_OWNERS:
            err.append(f"состояние {s['id']}: owner «{s.get('owner')}» — одно из {', '.join(STATE_OWNERS)}")
        # Активный таймер — таймер машины или пусто (DOC-24)
        if s.get("activeTimer") is not None and s["activeTimer"] not in timers:
            err.append(f"состояние {s['id']}: activeTimer «{s['activeTimer']}» — не таймер машины ({', '.join(sorted(timers))})")


def check_priorities(w, o, err):
    """Приоритеты — справочник МИ, общий для всех схем (§2.5, RULE-68), в эталонном наборе: числа
    уникальны и в 0–100, у названия есть ru, цвет — из палитры PriorityColor контракта (BUG-39).
    Нормативы таймеров и инциденты набора ссылаются только на числа справочника; Priority в
    контракте — целое 0–100 без перечня: значения настраивает администратор."""
    with open(os.path.join(DIR, "fixtures", "demo.json"), encoding="utf-8") as f:
        fx = json.load(f)
    levels = fx.get("priorities") or []
    if not levels:
        err.append("приоритеты: в эталонном наборе нет справочника priorities (§2.5)")
        return
    values = [p.get("value") for p in levels]
    palette = o["components"]["schemas"]["PriorityColor"].get("enum", [])
    for p in levels:
        v = p.get("value")
        if not (isinstance(v, int) and not isinstance(v, bool) and 0 <= v <= 100):
            err.append(f"приоритеты: число «{v}» — не целое от 0 до 100 (§2.5)")
        if values.count(v) > 1:
            err.append(f"приоритеты: число {v} у нескольких уровней — числа уникальны (§2.5)")
        if not (p.get("name") or {}).get("ru"):
            err.append(f"приоритеты: у уровня {v} нет названия ru (§2.5)")
        if p.get("color") not in palette:
            err.append(f"приоритеты: у уровня {v} цвет «{p.get('color')}», которого нет в PriorityColor контракта (BUG-39)")
    for t in w["timers"]:
        used = [o_["priority"] for o_ in t.get("overrides") or [] if "priority" in o_] + [int(k) for k in (t.get("byPriority") or {})]
        for pr in used:
            if pr not in values:
                err.append(f"приоритеты: таймер {t['id']} — норматив для «{pr}», которого нет в справочнике (§2.5)")
    pr_schema = o["components"]["schemas"]["Priority"]
    if pr_schema.get("type") != "integer" or pr_schema.get("minimum") != 0 or pr_schema.get("maximum") != 100 or "enum" in pr_schema:
        err.append("приоритеты: Priority в контракте — целое 0–100 без перечня (§2.5)")
    for inc in fx["incidents"]:
        if inc["priority"] not in values:
            err.append(f"приоритеты: {inc['number']} — приоритет «{inc['priority']}», которого нет в справочнике (§2.5)")




LIMITS = ("maxActive", "maxOnHold", "maxBulk")


def check_limits(w, err):
    """Лимиты (§10.2, §11, RULE-69): целое от 1 или null — «без ограничения»; 0, отрицательное и дробное —
    ошибка. Поле записано явно: нет поля тоже значит «без ограничения», и опечатка в имени тихо сняла бы лимит. У их строк в настройках администратора есть nullKey: подпись пустого значения."""
    for k in LIMITS:
        if k not in w["limits"]:
            err.append(f"лимиты: limits.{k} не записан — нет поля значит «без ограничения»; записать явно числом или null (RULE-69)")
            continue
        v = w["limits"][k]
        if not (v is None or (isinstance(v, int) and not isinstance(v, bool) and v >= 1)):
            err.append(f"лимиты: limits.{k} = {v!r} — нужно целое от 1 или null, «без ограничения» (RULE-69)")
    items = {i["path"]: i for t in w["adminSettings"]["tabs"] for i in t.get("items", [])}
    for k in LIMITS:
        item = items.get(f"limits.{k}")
        if item is not None and not item.get("nullKey"):
            err.append(f"лимиты: у настройки limits.{k} нет nullKey — пустое значение покажется «—», а не «без ограничения» (RULE-69)")


# Уровень приоритета по имени или сравнение приоритета с числом в коде прототипа (§2.5, RULE-68)
PRIORITY_NAMES = re.compile(r'"(?:critical|high|medium|low)"')
PRIORITY_NUMBER = re.compile(r'priority\w*\s*(?:[!=]==?|[<>]=?)\s*\d|\d\s*(?:[!=]==?|[<>]=?)\s*[\w.]*priority\b|\bpriority\s*:\s*\d')


def check_priority_literals(err):
    """Код прототипа не знает уровни приоритета (§2.5, RULE-68): ни по имени («critical»), ни по числу
    (priority === 100) — уровни, их порядок и самый срочный берутся из справочника. Иначе после правки
    справочника администратором прототип тихо разойдётся с ним."""
    for src in ("engine.js", "server.js", "app.js", "colleagues.js"):
        with open(os.path.join(ROOT, "prototype", src), encoding="utf-8") as f:
            for n, line in enumerate(f, 1):
                code = line.split("//")[0]
                if PRIORITY_NAMES.search(code) or PRIORITY_NUMBER.search(code):
                    err.append(f"приоритеты: {src}:{n} — уровень приоритета в коде, а не из справочника (§2.5): {line.strip()[:90]}")


def check_strings(w, err):
    """Каталог строк (§14.9, RULE-66): во всех языках одни ключи и одни подстановки; каждый ключ,
    который упоминают машина (поля *Key) и код сервера и исполнителя, есть в каталоге; ключей,
    которых нигде нет, в каталоге нет."""
    folder = os.path.join(DIR, "strings")
    langs = {}
    for name in sorted(os.listdir(folder)):
        if name.endswith(".json"):
            with open(os.path.join(folder, name), encoding="utf-8") as f:
                langs[name[:-5]] = {k: v for k, v in json.load(f).items() if not k.startswith("$")}
    if "ru" not in langs:
        err.append("каталог строк: нет strings/ru.json (§14.9)")
        return
    args = lambda text: sorted(set(re.findall(r"\{\s*(\w+)\s*[,}]", text)))
    for lang, cat in langs.items():
        for key in sorted(set(langs["ru"]) ^ set(cat)):
            err.append(f"каталог строк: ключ {key} есть только в одном из языков ru, {lang} (§14.9)")
        for key in sorted(set(langs["ru"]) & set(cat)):
            if args(cat[key]) != args(langs["ru"][key]):
                err.append(f"каталог строк: {lang} {key} — подстановки {args(cat[key])}, а в ru {args(langs['ru'][key])} (§14.9)")
    used = set()
    # Ключ — любая строка вида workflow.<область>.… в машине: поля …Key, значения values и valueLabels
    def walk(node):
        if isinstance(node, dict):
            for v in node.values():
                walk(v)
        elif isinstance(node, list):
            for v in node:
                walk(v)
        elif isinstance(node, str) and re.fullmatch(r"workflow\.[\w.]+", node):
            used.add(node)
    walk(w)
    # Ключи записей журнала: аргументы appendLog, alerts.noRecipientLog, раздел messages
    used |= {e["args"][0] for t in w["transitions"] for e in t["effects"] if e["fn"] == "appendLog"}
    used |= {w["alerts"]["noRecipientLog"]} | {k for k in w.get("messages", {}) if k.startswith("workflow.")}
    for key, spec in w.get("messages", {}).items():
        if key.startswith("workflow.") and key in langs["ru"] and sorted(spec.get("vars", [])) != args(langs["ru"][key]):
            err.append(f"каталог строк: {key} — подстановки в машине {sorted(spec.get('vars', []))}, а в ru {args(langs['ru'][key])} (§14.9)")
    # Типы событий потока (workflow.schema_published) — не ключи каталога
    for src in ("engine.js", "server.js"):
        with open(os.path.join(ROOT, "prototype", src), encoding="utf-8") as f:
            used |= set(re.findall(r'(?<!emit\()"(workflow\.[\w.]+)"', f.read()))
    for key in sorted(used - set(langs["ru"])):
        err.append(f"каталог строк: ключа {key} нет в strings/ru.json (§14.9)")
    for key in sorted(set(langs["ru"]) - used):
        err.append(f"каталог строк: ключ {key} нигде не используется (§14.9)")


def check_fail_keys(w, err):
    """Причины недоступности (§14.9, DOC-28): у каждого условия реестра — ключи причин failKeys из
    раздела messages (или failFrom — поле машины с причиной); в коде исполнителя и сервера причины
    и ошибки — ключами, а не русскими фразами."""
    messages = w.get("messages", {})
    for g in w["registries"]["guards"]:
        keys = g.get("failKeys")
        if keys is None and not g.get("failFrom"):
            err.append(f"реестр: у условия {g['fn']} нет failKeys — какую причину оно даёт, неизвестно (DOC-28)")
        for key in keys or []:
            if key not in messages:
                err.append(f"реестр: {g['fn']} — причина {key}, которой нет в messages (DOC-28)")
    # Строки кода сервера и исполнителя — ключи каталога (§14.9): русский текст в строке допустим только
    # в данных, помеченных «// данные» (например, комментарий эмулированного коллеги)
    literal = re.compile(r"([\"'`])(?:(?!\1).)*[А-Яа-яЁё](?:(?!\1).)*\1")
    for src in ("engine.js", "server.js"):
        with open(os.path.join(ROOT, "prototype", src), encoding="utf-8") as f:
            for n, line in enumerate(f, 1):
                code = line.split("//")[0]
                if literal.search(code) and not line.rstrip().endswith("// данные"):
                    err.append(f"{src}:{n}: текст для человека русской фразой, а не ключом каталога (DOC-28, RULE-66)")
    # В машине русский текст — только в пояснениях для разработчика
    doc = lambda path: path[-1] in ("why", "meaning") or any(isinstance(x, str) and x.startswith("$") for x in path)
    def walk(node, path):
        if isinstance(node, dict):
            for k, v in node.items():
                walk(v, path + (k,))
        elif isinstance(node, list):
            for i, v in enumerate(node):
                walk(v, path + (i,))
        elif isinstance(node, str) and re.search("[А-Яа-яЁё]", node) and not doc(path):
            err.append(f"машина: {'.'.join(map(str, path))} — русский текст вместо ключа каталога (§14.9, RULE-66)")
    walk(w, ())


def check_observer_notice(w, err):
    """Уведомление наблюдателям о переходе (§9, RULE-60, BUG-32) — в машине: ключ workflow.notice.*,
    кому — observers или newAddressee. Клиент не знает переходы по именам."""
    for t in w["transitions"]:
        n = (t.get("ui") or {}).get("observerNotice")
        if not n:
            continue
        if n.get("audience") not in ("observers", "newAddressee"):
            err.append(f"переход {t['id']}: observerNotice.audience «{n.get('audience')}» — не observers и не newAddressee (RULE-60)")
        if not str(n.get("key", "")).startswith("workflow.notice."):
            err.append(f"переход {t['id']}: ключ уведомления «{n.get('key')}» не из области workflow.notice (RULE-60)")


# Параметры, которые встроенный сервер прототипа сознательно не учитывает, — с причиной (ARCH-04)
UNREAD_PARAMS = {
    ("/operator/workflow/active", "eventTypeGuid"): "у прототипа одна схема (§14.4)",
    ("/operator/workflow/active", "sourceGroupGuid"): "у прототипа одна схема (§14.4)",
    ("/operator/workflow/active", "priority"): "у прототипа одна схема (§14.4)",
}


def check_served(o, err):
    """Описано ли то, что делает сервер (ARCH-04). Параметры запросов: у каждого есть описание, и
    встроенный сервер читает его в своём маршруте (или в функции, куда передаёт параметры целиком);
    исключения — UNREAD_PARAMS с причиной. Поток событий: каждый тип, который шлёт сервер, есть в
    перечне контракта, и у каждого типа перечня есть строка в таблице событий."""
    with open(os.path.join(ROOT, "prototype", "server.js"), encoding="utf-8") as f:
        srv = f.read()
    start = re.compile(r'\[\s*"(GET|POST|PUT|PATCH|DELETE)",\s*"(/[^"]+)",')
    marks = [(m.start(), m.group(1), m.group(2)) for m in start.finditer(srv)]
    bodies = {(meth, path): srv[a:(marks[i + 1][0] if i + 1 < len(marks) else len(srv))] for i, (a, meth, path) in enumerate(marks)}

    def reads(text, name, seen):
        if re.search(r"\bq\.%s\b" % name, text):
            return True
        for fn in re.findall(r"\b(\w+)\(q\)", text):
            if fn in seen:
                continue
            seen.add(fn)
            m = re.search(r"function %s\(q\) \{" % fn, srv)
            if m and reads(srv[m.end():srv.find("\n    }\n", m.end())], name, seen):
                return True
        return False

    for path, item in o["paths"].items():
        for meth, op in item.items():
            if meth not in ("get", "post", "put", "patch", "delete"):
                continue
            body = bodies.get((meth.upper(), path))
            for p in item.get("parameters", []) + op.get("parameters", []):
                if "$ref" in p:
                    p = o["components"]["parameters"][p["$ref"].split("/")[-1]]
                if p.get("in") != "query":
                    continue
                if not str(p.get("description", "")).strip():
                    err.append(f"контракт: {meth.upper()} {path} — у параметра {p['name']} нет описания (ARCH-04)")
                if body is not None and (path, p["name"]) not in UNREAD_PARAMS and not reads(body, p["name"], set()):
                    err.append(f"встроенный сервер: {meth.upper()} {path} не читает параметр {p['name']} — сделать или записать в UNREAD_PARAMS с причиной (ARCH-04)")
    ev = o["components"]["schemas"]["IncidentStreamEvent"]
    enum = set(ev["properties"]["type"]["enum"])
    table = set(re.findall(r"^\| `([a-z_.]+)` \|", ev.get("description", ""), re.M))
    sent = set(re.findall(r'emit\("([a-z_.]+)"', srv)) | set(re.findall(r'send\(\{ type: "([a-z_.]+)"', srv))
    for t in sorted(sent - enum):
        err.append(f"поток событий: сервер шлёт {t}, а в перечне контракта его нет (ARCH-04)")
    for t in sorted(enum ^ table):
        err.append(f"поток событий: тип {t} — {'нет строки в таблице событий' if t in enum else 'в таблице, но не в перечне'} (ARCH-04)")


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


def check_session_machine(w, err):
    """Машина состояний оператора (§12, PROC-42): ссылки смен, одно начальное, производное состояние (RULE-99) —
    от хранимого и вне смен, всё достижимо из начального, из каждого хранимого есть выход; право и причина —
    только у состояния, куда есть смена."""
    states = {s["id"]: s for s in w["session"]["states"]}
    moves = w["session"]["transitions"]
    for kind, ids in (("состояний", [s["id"] for s in w["session"]["states"]]), ("смен", [t["id"] for t in moves])):
        for d in duplicates(ids):
            err.append(f"состояние оператора: повтор {kind} {d}")
    derived = {s for s in states if states[s].get("derived")}
    for s in derived:
        d = states[s]["derived"]
        if not isinstance(d, dict) or not isinstance(d.get("expr"), str):
            err.append(f"состояние оператора {s}: derived — запись с of и expr (RULE-99)")
        elif d.get("of") not in states or d["of"] in derived:
            err.append(f"состояние оператора {s}: derived.of «{d.get('of')}» — не хранимое состояние машины оператора (RULE-99)")
        for k in ("initial", "permission", "requiresReason", "readOnly"):
            if states[s].get(k):
                err.append(f"состояние оператора {s}: у производного не бывает {k} — оно не хранится и в сменах не участвует (RULE-99)")
    initial = [s for s in states if states[s].get("initial")]
    if len(initial) != 1:
        err.append(f"состояние оператора: начальных {len(initial)}, нужно ровно одно (initial: true, RULE-99)")
    edges = {}
    for t in moves:
        for src in t["from"] + [t["to"]]:
            if src not in states:
                err.append(f"смена состояния оператора {t['id']}: состояния {src} нет в session.states")
            elif src in derived:
                err.append(f"смена состояния оператора {t['id']}: {src} — производное, смены идут от хранимого (RULE-99)")
        for src in t["from"]:
            if src != t["to"]:
                edges.setdefault(src, set()).add(t["to"])
    if len(initial) == 1:
        seen, stack = {initial[0]}, [initial[0]]
        while stack:
            for nxt in edges.get(stack.pop(), ()):
                if nxt not in seen:
                    seen.add(nxt)
                    stack.append(nxt)
        for s in states:
            if s not in derived and s not in seen:
                err.append(f"состояние оператора {s}: недостижимо из начального {initial[0]}")
    targets = {t["to"] for t in moves}
    for s, st in states.items():
        if s not in derived and not edges.get(s):
            err.append(f"состояние оператора {s}: из него нет смены — оператор в нём застрянет")
        for k in ("permission", "requiresReason"):
            if st.get(k) and s not in targets:
                err.append(f"состояние оператора {s}: {k} — у состояния, куда нет смены, его никто не проверит")


def check_escalation_settings(w, o, err):
    """Настройки, от которых зависит, сработает ли хоть один переход по истёкшему нормативу (RULE-45):
    без них нарушение пропадает молча."""
    esc = w.get("escalation") or {}
    if not isinstance(esc.get("enabled"), bool):
        err.append("эскалация: escalation.enabled — true или false; иначе истёкшая реакция пропадёт молча (RULE-45)")
    allowed = o["components"]["schemas"]["EscalationPolicy"]["properties"]["onResolutionOverdue"]["enum"]
    if esc.get("onResolutionOverdue") not in allowed:
        err.append(f"эскалация: escalation.onResolutionOverdue — одно из {allowed}; иначе истёкший норматив закрытия пропадёт молча (RULE-45)")
    alerts = w.get("alerts") or {}
    if alerts.get("targetKind") not in ("user", "group") or not isinstance(alerts.get("target"), str) or not alerts["target"]:
        err.append("алерты: alerts.targetKind — user или group, alerts.target — id; иначе алерты некому отправить (RULE-43, RULE-45, ARCH-07 в7)")
    for lvl in esc.get("levels") or []:
        if lvl.get("targetKind") not in ("user", "group") or not lvl.get("target"):
            err.append(f"эскалация: уровень {lvl.get('level')} — targetKind user или group и target — id (§8.3, ARCH-07 в7)")


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
                    err.append(f"настройки, вкладка «{tab['id']}»: пути {item['path']} в машине нет")
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
                err.append(f"настройки, вкладка «{tab['id']}»: запроса {tab['source']} нет в контракте")
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
        w = load("workflow_schema.v1.json")
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
    check_rules_example(w, err)
    check_doc_numbers(w, o, err)
    check_served(o, err)
    check_fixture_journal(w, err)
    check_fixture_history(w, err)
    check_fixture_media(err)
    check_graph(w, err)
    check_session_machine(w, err)
    check_state_owners(w, err)
    check_priorities(w, o, err)
    check_priority_literals(err)
    check_limits(w, err)
    check_strings(w, err)
    check_fail_keys(w, err)
    check_observer_notice(w, err)
    check_timer_declarations(w, err)
    fsm_terms(w, err)
    check_settings_matrix(w, o, err, show="--fsm" in sys.argv)
    check_work_rights(w, err)
    if "--fsm" in sys.argv:
        show_overlaps(w)
        show_continuing(w)
    check_registry_used(w, err)
    check_registry_comments(w, err)
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
