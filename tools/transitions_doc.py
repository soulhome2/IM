"""Таблица переходов машины состояний для человека: Specification/State_machine/TRANSITIONS.md.

Собирается из workflow.v4.json скриптом tools/build_workflow.py. Каждое условие и эффект
машины переводится в фразу; функции без фразы — ошибка сборки, чтобы таблица не отставала
от машины молча. По ней правила (§6) сверяются с машиной глазами: что задумали — в правилах,
что сделано — здесь.
"""
import json

TRIGGER = {"manual": "кнопка", "timer": "таймер", "system": "система"}
SURFACE = {"queue": "очередь", "card": "карточка"}
WHO = {
    "actor": "я — кто выполнил",
    "previousOwner": "прежнему владельцу",
    "owner": "владельца",
    "newTarget": "новому адресату",
    "shift_lead": "старшему смены",
    "escalation.alertTarget": "ответственному из настроек эскалации",
}
BULK = {
    "same_type_new": "только новые одного типа, создаёт группу сценария",
    "each_allowed": "если доступно каждому отмеченному",
    "group": "только группа сценария",
    "group_or_each_allowed": "группа сценария или если доступно каждому отмеченному",
}


class Doc:
    def __init__(self, w):
        self.w = w
        self.states = {s["id"]: s["label"] for s in w["states"]}
        self.timers = {t["id"]: t["label"] for t in w["timers"]}
        self.forms = {f["id"]: f["title"] for f in w["forms"]}
        self.reasons = {i["id"]: i["label"] for c in w["reasonCatalogs"].values() for i in c.get("items", [])}
        self.agent = {s["id"]: s["label"] for s in w["session"]["states"]}

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

    def value(self, v):
        if v is None:
            return "очищается"
        if v == "actor":
            return "я — кто выполнил"
        if v == "now":
            return "сейчас"
        if isinstance(v, str) and v.startswith("form."):
            return f"из формы (`{v[5:]}`)"
        return f"`{v}`"

    def target(self, v, kind):
        if v is None:
            return "очищается"
        if v == "actor":
            return "я — кто выполнил"
        if v == "owner.dutyGroup":
            return "дежурная группа владельца"
        source = "адресат из формы" if v.startswith("form.") else "адресат уровня эскалации"
        return f"{source}, если это {kind}"

    def guard(self, g):
        fn, a = g["fn"], g.get("args") or []
        phrases = {
            "hasPermission": lambda: f"право `{a[0]}`",
            "hasScopedPermission": lambda: f"право `{a[0]}:own` — для своего, ничьего и адресованного мне; `{a[0]}:any` — для чужого",
            "isOwner": lambda: "я владелец",
            "isNotOwner": lambda: "я не владелец",
            "isOwnerInStates": lambda: f"я владелец, если состояние {self.st(a[0])}",
            "isTarget": lambda: "адресат — я или моя дежурная группа",
            "isNotTarget": lambda: "адресат — не я и не моя дежурная группа",
            "targetIsNotSelf": lambda: "адресат — не я и не моя дежурная группа",
            "agentReady": lambda: "я не на перерыве",
            "agentStateIs": lambda: f"состояние оператора — «{self.agent.get(a[0], a[0])}»",
            "ownerHasDutyGroup": lambda: "владелец состоит в дежурной группе" if a[0] else "владелец не состоит ни в одной дежурной группе",
            "agentIdleFor": lambda: f"оператор не присылает признак активности дольше {self.setting(a[0])} с",
            "withinActiveLimit": lambda: f"лимит активных не исчерпан ({self.setting('limits.maxActive')})",
            "withinHoldLimit": lambda: f"лимит отложенных не исчерпан ({self.setting('limits.maxOnHold')})",
            "withinReopenWindow": lambda: f"не истёк срок переоткрытия ({self.setting('limits.reopenWindowMin')} мин)",
            "requiredStepsFilled": lambda: f"заполнены обязательные шаги набора `{a[0]}`",
            "closeResultAllowed": lambda: "выбранный результат разрешён по справочнику результатов: право, состояние, владение, шаги",
            "timerExpired": lambda: f"истёк таймер {self.tm(a[0])}",
            "flagBelow": lambda: f"`{a[0]}` меньше {self.setting(a[1])}",
            "flagAtLeast": lambda: f"`{a[0]}` не меньше {self.setting(a[1])}",
            "holdReasonIn": lambda: "причина удержания — " + ", ".join(f"«{self.reasons.get(r, r)}»" for r in a[0]),
            "stateIs": lambda: f"состояние {self.st(a[0])}",
            "canReadDone": lambda: "я владелец, или закрыл его я, или есть право `incident:read:any`",
            "minSelected": lambda: f"выбрано не меньше {a[0]}",
            "settingEnabled": lambda: f"включена настройка {self.setting(a[0])}",
            "settingIs": lambda: f"настройка `{a[0]}` = {json.dumps(a[1], ensure_ascii=False)} (сейчас {json.dumps(self.lookup(a[0]), ensure_ascii=False)})",
        }
        if fn not in phrases:
            raise KeyError(f"Нет фразы для условия {fn}: добавьте её в tools/transitions_doc.py")
        return phrases[fn]()

    def effect(self, e):
        fn, a = e["fn"], e.get("args") or []
        phrases = {
            "setState": lambda: f"состояние = {self.st(a[0])}",
            "setOwner": lambda: f"владелец: {self.target(a[0], 'человек')}",
            "setAssignmentGroup": lambda: f"группа-адресат: {self.target(a[0], 'группа')}",
            "setHoldReason": lambda: "причина удержания: " + (self.value(a[0]) if str(a[0]).startswith("form.") else f"«{self.reasons.get(a[0], a[0])}»"),
            "clearHoldReason": lambda: "причина удержания очищается",
            "startTimer": lambda: f"запуск {self.tm(a[0])}"
            + ("" if len(a) < 2 else " по нормативу уровня эскалации" if a[1] in ("byEscalationLevel", "escalation.level.reactionSec") else f", норматив {self.setting(a[1])} с"),
            "stopTimer": lambda: f"остановка {self.tm(a[0])}",
            "pauseTimer": lambda: f"пауза {self.tm(a[0])}, остаток сохраняется",
            "resumeTimer": lambda: f"{self.tm(a[0])} продолжается с остатка, при первом запуске — с полного норматива",
            "restartTimer": lambda: f"{self.tm(a[0])} заново, без остатка; норматив {self.setting(a[1])}, не задан — обычный",
            "recordBreach": lambda: f"нарушение `{a[0]}` в `breaches`",
            "increment": lambda: f"`{a[0]}` +1",
            "setFlag": lambda: f"`{a[0]}`: {self.value(a[1])}",
            "appendLog": lambda: f"журнал: «{a[0]}»",
            "returnToQueue": lambda: "оператор возвращается к очереди",
            "evictOpenCard": lambda: f"открытая карточка ({WHO.get(a[0], a[0])}) — в режим просмотра",
            "setCursor": lambda: "сценарий открывается на первом незаполненном шаге" if a[0] == "firstOpenStep" else f"курсор сценария: `{a[0]}`",
            "clearGroup": lambda: "выходит из групповой обработки",
            "notify": lambda: f"уведомление {WHO.get(a[0], a[0])}",
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
        hotkey = f"; клавиша `{ui['hotkey']}`" if ui.get("hotkey") else ""
        return f"кнопка: {where}{hotkey}"

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
            "Собрано из [`workflow.v4.json`](workflow.v4.json) скриптом `tools/build_workflow.py`. Руками не править: правится машина, затем сборка. "
            "Это то, что машина делает на самом деле; что задумано — в правилах, §6. Строки правил ссылаются на переходы по идентификатору в первой колонке.",
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
                f"| `{t['id']}`<br>{t['label']} | {self.st(t['from'])} → {to} | {self.started(t)} "
                f"| {cell([self.guard(g) for g in t.get('guards', [])])} | {cell([self.effect(e) for e in t.get('effects', [])])} "
                f"| {form} | {self.bulk(t) or '—'} |"
            )
        out += ["", "## Какие переходы из какого состояния", "", "| Переход | " + " | ".join(self.states.values()) + " | Куда |", "|---|" + "---|" * (len(self.states) + 1)]
        for t in w["transitions"]:
            row = ["✓" if s in t["from"] else "" for s in self.states]
            to = f"`{t['to']}` {self.states.get(t['to'], '')}".rstrip() if t.get("to") else "не меняется"
            out.append(f"| `{t['id']}` {t['label']} | " + " | ".join(row) + f" | {to} |")
        out += ["", "## Действия без смены состояния", "", "| Действие | Где | Условия |", "|---|---|---|"]
        for n in w["navActions"]["items"]:
            where = ", ".join(SURFACE.get(s, s) for s in n.get("surface", []))
            out.append(f"| `{n['id']}`<br>{n['label']} | {where} | {cell([self.guard(g) for g in n.get('guards', [])])} |")
        return "\n".join(out) + "\n"


def render(w):
    return Doc(w).render()
