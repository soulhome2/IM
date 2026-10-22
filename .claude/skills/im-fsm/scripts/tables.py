import json, collections
w = json.load(open("Specification/Workflow_machine/workflow_schema.v1.json", encoding="utf-8"))
ru = json.load(open("Specification/Workflow_machine/strings/ru.json", encoding="utf-8"))
for s in w["states"]:
    kind = "initial" if s.get("initial") else "terminal" if s.get("terminal") else "normal"
    print(f"| {s['id']} | {ru.get(s['labelKey'], s['labelKey'])} | {kind} |")
for t in w["transitions"]:
    event = t["id"] if t["trigger"] == "manual" else f"— ({t['trigger']})"
    guards = ", ".join(g["fn"] + (f"({', '.join(map(str, g.get('args', [])))})" if g.get("args") else "") for g in t["guards"])
    effects = ", ".join(e["fn"] for e in t["effects"])
    for src in t["from"]:
        print(f"| {src} | {event} | {guards} | {effects} | {t['to'] or src + ' (не меняется)'} |")
edges = collections.OrderedDict()
for t in w["transitions"]:
    mark = t["id"] + ("*" if t["trigger"] != "manual" else "") + ("°" if t["to"] is None else "")
    for src in t["from"]:
        edges.setdefault((src, t["to"] or src), []).append(mark)
start = next(s["id"] for s in w["states"] if s.get("initial"))
print("stateDiagram-v2\n    [*] --> " + start)
for (a, b), ids in edges.items():
    print(f"    {a} --> {b}: {', '.join(ids)}")
for s in w["states"]:
    if s.get("terminal"):
        print(f"    {s['id']} --> [*]")
