import json, collections
w = json.load(open("Specification/Workflow_machine/workflow_schema.v1.json", encoding="utf-8"))
words = collections.Counter(p for t in w["transitions"] for p in t["id"].split("_"))
print("Слова в идентификаторах переходов:", dict(words))
for t in w["transitions"]:
    guards = ", ".join(g["fn"] + (str(g["args"]) if g.get("args") else "") for g in t["guards"])
    logs = [e["args"][0] for e in t["effects"] if e["fn"] == "appendLog"]
    print(f"| {t['id']} | {guards} | {t.get('labelKey')} | {' / '.join(logs) or '—'} |")
print("Привязанные (§11.4): переход | меняет адресата | доступ к привязанным | связь")
LINK = ("clearLink", "setLinkedTo", "relinkToPrimary", "copyCloseFromPrimary")
for t in w["transitions"]:
    fns = [e["fn"] for e in t["effects"]]
    moves = "setOwner" in fns or "setAssignmentGroup" in fns
    if moves or "linked" in t["from"] + [t["to"]] or "closed" in t["from"] + [t["to"]]:
        access = "условие" if any(g["fn"] == "targetHasAccessToLinked" for g in t["guards"]) else "linked_lost_access" if moves else "—"
        print(f"| {t['id']} | {'да' if moves else 'нет'} | {access} | {', '.join(f for f in fns if f in LINK) or '—'} |")
import re
# Аргумент appendLog — ключ каталога строк (RULE-66): переменные ищутся в тексте записи, а не в ключе
ru = json.load(open("Specification/Workflow_machine/strings/ru.json", encoding="utf-8"))
CHANGES = {"targetName": {"setOwner", "setAssignmentGroup"}, "escalationLevel": {"increment:escalation_level", "setFlag:escalation_level"},
           "holdReasonLabel": {"setHoldReason", "clearHoldReason"}, "closeResultLabel": {"setFlag:close_result"}, "stepNumber": {"setCursor"},
           "previousOwnerName": {"setOwner"}}
# Значение, которое исполнитель снимает до перехода (engine.js, logVars), — эффекты до записи его не меняют
BEFORE = {"previousOwnerName": "исполнитель берёт до перехода"}
print("Запись журнала: переход | переменная | меняется в том же переходе до записи | текст записи")
for t in w["transitions"]:
    fx = [(e["fn"] + (":" + e["args"][0] if e["fn"] in ("setFlag", "increment") else ""),
           e["fn"].startswith("clear") or (e["fn"] in ("setFlag", "setOwner") and e["args"][-1] is None)) for e in t["effects"]]
    for i, e in enumerate(t["effects"]):
        text = ru.get(e["args"][0], e["args"][0]) if e["fn"] == "appendLog" else ""
        for v in re.findall(r"\{(\w+)", text):
            before = [f + ("→пусто" if empty else "") for f, empty in fx[:i] if f in CHANGES.get(v, ())]
            if before:
                print(f"| {t['id']} | {{{v}}} | {', '.join(before)}{' — ' + BEFORE[v] if v in BEFORE else ''} | {text} |")
fns = {g["fn"] for g in w["registries"]["guards"]} | {e["fn"] for e in w["registries"]["effects"]}
print("Правила вне §4, §6, §8.1: строка | раздел | функции реестра")
sec = ""
for n, l in enumerate(open("Specification/State_rules/States rules IM.md", encoding="utf-8"), 1):
    if l.startswith("#"):
        sec = l.strip("# \n").split(" ")[0]
    named = sorted(f for f in fns if f"`{f}" in l)
    if named and not sec.startswith(("4.", "6.", "8.1")):
        print(f"| {n} | §{sec} | {', '.join(named)} |")
print("Сверх базового реестра без $comment:", [e["fn"] for k in ("guards", "effects") for e in w["registries"][k] if e.get("extendsBaseRegistry") and not e.get("$comment")])
