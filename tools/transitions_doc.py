"""Таблица переходов машины состояний для человека: Specification/Workflow_machine/TRANSITIONS.md.

Собирается из workflow_schema.v1.json скриптом tools/build_workflow.py. Каждое условие и эффект
машины переводится в фразу; функции без фразы — ошибка сборки, чтобы таблица не отставала
от машины молча. По ней правила (§6) сверяются с машиной глазами: что задумали — в правилах,
что сделано — здесь.
"""
import hashlib
import json
import os

# Тексты записей журнала — из русского каталога строк (§14.9): в машине только ключи
with open(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Specification", "Workflow_machine", "strings", "ru.json"), encoding="utf-8") as _f:
    RU = json.load(_f)


def lab(o, field="label"):
    """Подпись из машины по-русски: ключ поля (labelKey, titleKey, hintKey) — строка каталога (§14.9)."""
    key = o.get({"label": "labelKey", "title": "titleKey", "hint": "hintKey"}[field])
    return RU.get(key, key) if key else o.get(field, "")

TRIGGER = {"manual": "кнопка", "timer": "таймер", "system": "система", "event": "событие источника"}
SURFACE = {"queue": "очередь", "card": "карточка"}
WHO = {
    "actor": "я — кто выполнил",
    "previousOwner": "прежнему владельцу",
    "before.owner": "прежнему владельцу",
    "owner": "владельца",
    "newTarget": "новому адресату",
    "addressee(incident)": "новому адресату",
    "alerts.target": "получателю алертов (`alerts.target`; если на месте с доступом к объекту никого — запись в журнал)",
}
BULK = {
    "each_allowed": "если доступно каждому отмеченному",
    "merge": "«Взять в работу» на выборке — одним инцидентом (§11.3)",
}


# Отпечатки выражений условий (PROC-83): условие → первые 8 знаков SHA-256 его expr в registries.guards, при
# котором фразу в Doc.guard сверяли с выражением. Выражение сменилось — сборка падает: пересмотрите фразу и впишите новый
# отпечаток (его печатает ошибка)
REVIEWED = {
    "addresseeCanAccept": "b2d632c7",
    "addresseeHasAccess": "7b1e9f69",
    "agentIdleFor": "c3b2c0de",
    "agentReady": "9250fadd",
    "agentStateIs": "242bada0",
    "closeResultAllowed": "86e0c4f1",
    "escalationTargetAvailable": "86b1f72c",
    "hasPermission": "acc40cba",
    "hasScopedPermission": "37f2c5ee",
    "hasTransferTarget": "c4a40f6b",
    "holdReasonIn": "b035edcf",
    "holdReasonNotIn": "b3fd7191",
    "isNotOwner": "b6c86c3a",
    "isNotTarget": "3492cdaa",
    "isOwner": "be89ae13",
    "isOwnerOrUnowned": "84f16a52",
    "isTarget": "71cd9932",
    "mergePrimaryValid": "b4e339d8",
    "ownerHasDutyGroup": "04004c43",
    "primaryAddresseeHasAccess": "a22463d9",
    "primaryClosed": "ca2d9ec1",
    "primaryEditable": "b860780a",
    "requiredStepsFilled": "a5262918",
    "sameScenarioAsPrimary": "71d4ee41",
    "settingEnabled": "32d4661f",
    "settingIs": "dd447c1b",
    "stateIs": "e3b76ef9",
    "targetCanAccept": "5d23cbb9",
    "targetHasAccess": "54830cd7",
    "targetHasAccessToLinked": "3d51b722",
    "targetIsNotSelf": "38041044",
    "timerExpired": "a50f7ed6",
    "withinActiveLimit": "699f9d8a",
    "withinHoldLimit": "7947052b",
    "withinReopenWindow": "2aaee97b",
}


def fingerprint(expr):
    return hashlib.sha256(expr.encode("utf-8")).hexdigest()[:8]


class Doc:
    def __init__(self, w):
        self.w = w
        self.states = {s["id"]: lab(s) for s in w["states"]}
        self.timers = {t["id"]: lab(t) for t in w["timers"]}
        self.forms = {f["id"]: lab(f, "title") for f in w["forms"]}
        self.reasons = {i["id"]: lab(i) for c in w["reasonCatalogs"].values() for i in c.get("items", [])}
        self.agent = {s["id"]: lab(s) for s in w["session"]["states"]}
        self.exprs = {g["fn"]: g.get("expr", "") for g in w["registries"]["guards"]}

    def setting(self, path):
        """Путь к настройке машины → «`путь` = значение»."""
        value = self.w
        for key in path.split("."):
            value = value.get(key) if isinstance(value, dict) else None
        return f"`{path}` = {json.dumps(value, ensure_ascii=False)}" if value is not None else f"`{path}`"

    def lookup(self, path):
        value = self.w
        for key in path.split("."):
            value = value.get(key) if isinstance(value, dict) else None
        return value

    def st(self, ids):
        ids = ids if isinstance(ids, list) else [ids]
        return ", ".join(f"«{self.states.get(i, i)}»" for i in ids)

    def tm(self, t):
        return f"«{self.timers.get(t, t)}» (`{t}`)"

    # Аргументы эффектов — выражения CEL машины (CEL.md): пусто — '', строка — в кавычках
    @staticmethod
    def lit(v):
        return v[1:-1] if isinstance(v, str) and len(v) >= 2 and v[0] == v[-1] == "'" else v

    def value(self, v):
        if v in (None, "''"):
            return "очищается"
        if v == "actor":
            return "я — кто выполнил"
        if v == "now":
            return "сейчас"
        if v == "levelUpNumber(before)":
            return "номер найденного уровня эскалации"
        if isinstance(v, str) and v.startswith("form."):
            return f"из формы (`{v[5:]}`)"
        return f"`{self.lit(v)}`"

    def target(self, v, kind):
        if v in (None, "''"):
            return "очищается"
        if v == "actor":
            return "я — кто выполнил"
        if v == "dutyGroupOf(incident.owner)":
            return "дежурная группа владельца"
        source = "адресат из формы" if "form." in v else "адресат уровня эскалации"
        return f"{source}, если это {kind}"

    def guard(self, g):
        fn, a = g["fn"], g.get("args") or []
        phrases = {
            "hasPermission": lambda: f"право `{a[0]}`",
            "hasScopedPermission": lambda: f"право `{a[0]}` — для своего, ничьего и адресованного мне; `{a[1]}` — для чужого",
            "isOwner": lambda: "я владелец",
            "isNotOwner": lambda: "инцидент не мой (ожидающий моего принятия — не мой, а адресованный мне)",
            "isTarget": lambda: "адресат — я или моя дежурная группа",
            "isNotTarget": lambda: "адресат — не я и не моя дежурная группа",
            "targetIsNotSelf": lambda: "адресат — не я и не моя дежурная группа",
            "primaryAddresseeHasAccess": lambda: ("у адресата основного есть доступ к объекту" if a[0] else "у адресата основного нет доступа к объекту"),
            "addresseeHasAccess": lambda: ("у владельца или адресата есть доступ" if a[0] else "у владельца или адресата нет доступа")
            + " к объекту инцидента (группе-адресату хватает одного участника)",
            "addresseeCanAccept": lambda: ("владелец или адресат может принять — право `incident:accept` и доступ, у группы — хотя бы у одного участника" if a[0] else "владелец или адресат не может принять — нет права `incident:accept` или доступа, у группы — ни у одного участника"),
            "targetCanAccept": lambda: "адресат может принять: право `incident:accept` и доступ к объекту (группе — хотя бы у одного участника)",
            "targetHasAccess": lambda: "у адресата есть доступ к объекту инцидента (группе — хотя бы у одного участника)",
            "agentReady": lambda: "я не на перерыве и не вышел",
            "agentStateIs": lambda: f"состояние оператора — «{self.agent.get(a[0], a[0])}»",
            "ownerHasDutyGroup": lambda: "владелец состоит в дежурной группе" if a[0] else "владелец не состоит ни в одной дежурной группе",
            "agentIdleFor": lambda: f"оператор не присылает признак активности дольше {self.setting(a[0])} с",
            "withinActiveLimit": lambda: f"лимит активных не исчерпан ({self.setting('limits.maxActive')})",
            "withinHoldLimit": lambda: f"лимит отложенных не исчерпан ({self.setting('limits.maxOnHold')})",
            "withinReopenWindow": lambda: f"не истёк срок переоткрытия ({self.setting('limits.reopenWindowMin')} мин)",
            "requiredStepsFilled": lambda: f"заполнены обязательные шаги набора `{a[0]}`",
            "closeResultAllowed": lambda: "выбранный результат разрешён по справочнику результатов: право, состояние, владение, шаги",
            "timerExpired": lambda: f"истёк таймер {self.tm(a[0])}",
            "escalationTargetAvailable": lambda: ("есть следующий уровень" if a[0] else "нет следующего уровня")
            + f" эскалации не выше потолка ({self.setting('escalation.maxLevel')}), адресат которого может принять — право `incident:accept` и доступ к объекту — и не вышел из МИ (вышедшему — если в его дежурной группе кто-то не вышел и может принять); остальные уровни пропускаются",
            "holdReasonIn": lambda: "причина удержания — " + ", ".join(f"«{self.reasons.get(r, r)}»" for r in a[0]),
            "holdReasonNotIn": lambda: "причина удержания — не " + ", ".join(f"«{self.reasons.get(r, r)}»" for r in a[0]),
            "stateIs": lambda: f"состояние {self.st(a[0])}",
            "settingEnabled": lambda: f"включена настройка {self.setting(a[0])}",
            "settingIs": lambda: f"настройка `{a[0]}` = {json.dumps(a[1], ensure_ascii=False)} (сейчас {json.dumps(self.lookup(a[0]), ensure_ascii=False)})",
            "isOwnerOrUnowned": lambda: "инцидент ничей или мой",
            "mergePrimaryValid": lambda: "основной — другой открытый, не привязанный, виден мне; новый или мой в работе",
            "sameScenarioAsPrimary": lambda: "сценарий тот же, что у основного",
            "primaryEditable": lambda: "основной новый или мой",
            "primaryClosed": lambda: "основной закрыт",
            "targetHasAccessToLinked": lambda: "у адресата есть доступ к объектам всех привязанных инцидентов",
            "hasTransferTarget": lambda: "есть кому передать: хоть один адресат может принять и имеет доступ к объектам",
        }
        if fn not in phrases:
            raise KeyError(f"Нет фразы для условия {fn}: добавьте её в tools/transitions_doc.py")
        # Фраза — по выражению, при котором её сверяли (PROC-83): сменилось выражение — таблица отстала бы от машины молча
        got = fingerprint(self.exprs.get(fn, ""))
        if REVIEWED.get(fn) != got:
            raise KeyError(f"Выражение условия {fn} изменилось (отпечаток {got}, сверяли при {REVIEWED.get(fn)}): пересмотрите фразу в tools/transitions_doc.py и впишите отпечаток в REVIEWED")
        return phrases[fn]()

    def effect(self, e):
        fn, a = e["fn"], e.get("args") or []
        phrases = {
            "setOwner": lambda: f"владелец: {self.target(a[0], 'человек')}",
            "setAssignmentGroup": lambda: f"группа-адресат: {self.target(a[0], 'группа')}",
            "setHoldReason": lambda: "причина удержания: " + (self.value(a[0]) if str(a[0]).startswith("form.") else f"«{self.reasons.get(self.lit(a[0]), self.lit(a[0]))}»"),
            "clearHoldReason": lambda: "причина удержания очищается",
            "startTimer": lambda: f"запуск {self.tm(a[0])}"
            + ("" if len(a) < 2 else " по нормативу уровня эскалации" if a[1] in ("byEscalationLevel", "escalation.level.reactionSec") else f", норматив {self.setting(a[1])} с")
            + (" — если не идёт; идущий продолжается" if a[2:] == [True] else ""),
            "stopTimer": lambda: f"остановка {self.tm(a[0])}",
            "pauseTimer": lambda: f"пауза {self.tm(a[0])}, остаток сохраняется",
            "resumeTimer": lambda: f"{self.tm(a[0])} продолжается с остатка, при первом запуске — с полного норматива",
            "restartTimer": lambda: f"{self.tm(a[0])} заново, без остатка; норматив {self.setting(a[1])}, не задан — обычный",
            "recordBreach": lambda: f"нарушение `{a[0]}` в `breaches` — и каждому открытому привязанному",
            "increment": lambda: f"`{a[0]}` +1",
            "setFlag": lambda: f"`{a[0]}`: {self.value(a[1])}",
            "appendLog": lambda: f"журнал: «{RU.get(a[0], a[0])}»",
            "returnToQueue": lambda: "оператор возвращается к очереди",
            "evictOpenCard": lambda: f"открытая карточка ({WHO.get(a[0], a[0])}) — в режим просмотра",
            "setCursor": lambda: "сценарий открывается на первом незаполненном шаге" if a[0] == "firstOpenStep" else f"курсор сценария: `{a[0]}`",
            "clearGroup": lambda: "выходит из групповой обработки",
            "setLinkedTo": lambda: f"связан с основным: {self.value(a[0])}",
            "clearLink": lambda: "связь с основным снимается" + (" — если была, запись в журнал привязанного и основного" if a else ""),
            "relinkToPrimary": lambda: "открытые привязанные объединяемого — новому основному, запись в журнале каждого",
            "copyAnswersToPrimary": lambda: "заполненные шаги сценария — в незаполненные шаги основного, запись в журнале основного",
            "copyCloseFromPrimary": lambda: "результат, причина, комментарий и закрывший — от основного",
            "tightenPrimaryDeadline": lambda: f"срок основного по {self.tm(a[0])} — самый ранний из своего и остатка привязываемого",
            "copyPrimaryDeadline": lambda: f"{self.tm(a[0])} — остаток срока основного, на паузе",
            "notify": lambda: f"{'алерт' if a[1:] and a[1] is True else 'уведомление'} {WHO.get(a[0], a[0])}",
            "externalCommand": lambda: f"внешняя команда `{a[0]}`",
        }
        if fn not in phrases:
            raise KeyError(f"Нет фразы для эффекта {fn}: добавьте её в tools/transitions_doc.py")
        external = " (внешний эффект)" if e.get("kind") == "external" else ""
        return phrases[fn]() + external

    def started(self, t):
        if t["trigger"] != "manual":
            return TRIGGER[t["trigger"]]
        ui = t.get("ui", {})
        where = ", ".join(SURFACE.get(s, s) for s in ui.get("surface", []))
        # Кнопки в строке и карточке нет — только на панели выборки (§11)
        if not where and (t.get("bulk") or {}).get("allowed"):
            where = "панель выборки"
        return f"кнопка: {where}"

    def bulk(self, t):
        b = t.get("bulk") or {}
        if not b.get("allowed"):
            return "нет" if t["trigger"] == "manual" else ""
        return BULK.get(b.get("mode"), b.get("mode"))

    def render(self):
        w = self.w
        cell = lambda items: "<br>".join(items) if items else "—"
        out = [
            "# Переходы машины состояний",
            "",
            "Собрано из [`workflow_schema.v1.json`](workflow_schema.v1.json) скриптом `tools/build_workflow.py`. Руками не править: правится машина, затем сборка. "
            "Это то, что машина делает на самом деле; что задумано — в правилах, §6. Строки правил ссылаются на переходы по идентификатору в первой колонке. Фраза условия привязана к его выражению CEL отпечатком: выражение в машине сменилось, а фразу не пересмотрели — сборка падает (PROC-83).",
            "",
            "## Переходы",
            "",
            "| Переход | Откуда → куда | Запуск | Условия | Что происходит | Форма | На выборку |",
            "|---|---|---|---|---|---|---|",
        ]
        for t in w["transitions"]:
            to = self.st(t["to"]) if t.get("to") else "не меняется"
            form = self.forms.get(t.get("form"), "—") if t.get("form") else "—"
            steps = t.get("requiredStepSet")
            if steps and steps not in ("none", None):
                form += f"; шаги: {'по результату' if steps == 'byCloseResult' else steps}"
            out.append(
                f"| `{t['id']}`<br>{lab(t)} | {self.st(t['from']) or '—'} → {to} | {self.started(t)} "
                f"| {cell([self.guard(g) for g in t.get('guards', [])])} | {cell([self.effect(e) for e in t.get('effects', [])])} "
                f"| {form} | {self.bulk(t) or '—'} |"
            )
        out += ["", "## Какие переходы из какого состояния", "", "| Переход | " + " | ".join(self.states.values()) + " | Куда |", "|---|" + "---|" * (len(self.states) + 1)]
        for t in w["transitions"]:
            row = ["✓" if s in t["from"] else "" for s in self.states]
            to = f"`{t['to']}` {self.states.get(t['to'], '')}".rstrip() if t.get("to") else "не меняется"
            out.append(f"| `{t['id']}` {lab(t)} | " + " | ".join(row) + f" | {to} |")
        out += ["", "## Действия без смены состояния", "", "| Действие | Где | Условия |", "|---|---|---|"]
        for n in w["navActions"]["items"]:
            where = ", ".join(SURFACE.get(s, s) for s in n.get("surface", []))
            out.append(f"| `{n['id']}`<br>{lab(n)} | {where} | {cell([self.guard(g) for g in n.get('guards', [])])} |")
        out += [
            "",
            "## Права",
            "",
            "Каталог прав машины (`permissions`) и где каждое право проверяется. Формат ключа и смысл областей `own` и `any` — в правилах, §5.",
            "",
            "| Право | Что разрешает | Где проверяется |",
            "|---|---|---|",
        ]
        for p in w["permissions"]:
            used = self.permission_uses(p["key"])
            out.append(f"| `{p['key']}` | {lab(p)} | {cell(used)} |")
        return "\n".join(out) + "\n"

    def permission_uses(self, key):
        """Где машина проверяет право: условия переходов и действий, результаты закрытия,
        групповая обработка, состояния оператора."""
        w, uses = self.w, []

        def checks(guards):
            for g in guards or []:
                a = g.get("args") or []
                if g["fn"] == "hasPermission" and a and a[0] == key:
                    return True
                if g["fn"] == "hasScopedPermission" and key in a:
                    return True
            return False

        for t in w["transitions"]:
            if checks(t.get("guards")):
                uses.append(f"`{t['id']}` {lab(t)}")
        for n in w["navActions"]["items"]:
            if checks(n.get("guards")):
                uses.append(f"`{n['id']}` {lab(n)}")
        for item in w["reasonCatalogs"]["close_result"]["items"]:
            if item.get("permission") == key:
                uses.append(f"`close` с результатом «{lab(item)}»")
        # «Взять в работу» на выборке: новый основной берётся переходом grouping.takeWith — с его правами (DOC-57)
        take = (w.get("grouping") or {}).get("takeWith")
        merge = next((t for t in w["transitions"] if t["id"] == "merge"), None)
        if take and merge and any(checks(t.get("guards")) for t in w["transitions"] if t["id"] == take):
            uses.append(f"`merge` {lab(merge)} на выборке, если основной новый — переходом `{take}` (`grouping.takeWith`)")
        for s in w["session"]["states"]:
            if s.get("permission") == key:
                uses.append(f"состояние оператора «{lab(s)}» (`session`)")
        if key == "incident:schema:admin":
            uses.append("не в машине: операции редактора схемы `/operator/workflow/schemas…` (контракт)")
        return uses


def render(w):
    return Doc(w).render()
