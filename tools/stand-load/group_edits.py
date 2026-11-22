#!/usr/bin/env python3
"""План 99, замер частых правок групп: админ test@ по кругу правит группы через балансировщик (:5000), каждая правка на следующий узел.
Круг из шести правок: переименовать группу, вернуть имя, убрать устройство из группы, вернуть, удалить правило доступа, создать заново.
  python3 -I group_edits.py <интервал_с> <секунд> <каталог>   (интервал 0 — только подготовка и выход)
Пишет <каталог>/edits.jsonl (время, вид, код, мс, ответ) и в конце возвращает имя, состав и правило."""
import http.client, json, os, subprocess, sys, time
sys.argv = [sys.argv[0], "5000", "5000", "/tmp/x", "только=none"] + sys.argv[1:]
IV, DUR, ODIR = float(sys.argv[5]), float(sys.argv[6]), sys.argv[7]
src = open(__file__.replace("group_edits.py", "cross_node.py")).read().split("ADMIN = cloud_login")[0]
exec(src)
os.makedirs(ODIR, exist_ok=True)
N = Node(5000, "lb")
tok, tok_at = None, 0
def T():
    global tok, tok_at
    if time.time() - tok_at > 240:
        tok, tok_at = cloud_login("test@axxonnet.test", test_pass()), time.time()
    return tok
# выбор: лист-группа с устройством; правило группы 1
row = sql("""select g.guid, g.name, m.source_guid from source_groups g join source_group_memberships m on m.group_guid=g.guid
             where g.name not like '%~%' order by (select count(*) from source_group_memberships x where x.group_guid=g.guid) limit 1""")
G, GNAME, S = row.split("|")
code, groups, _, _ = N.call("GET", "/access-rules", T())
rule = next(r for g in groups if g["id"] == 1 for r in g["rules"] if r.get("sourceGroup"))
RGUID, RSG = rule["guid"], rule["sourceGroup"]["guid"]
print("группа", G, GNAME, "устройство", S[:8], "правило", RGUID[:8], flush=True)
if IV <= 0:
    sys.exit(0)
f = open(os.path.join(ODIR, "edits.jsonl"), "a")
state = {"renamed": False, "removed": False, "ruledel": False}
def do(kind, method, path, body):
    t0 = time.time(); c, js, ms, _ = N.call(method, path, T(), body)
    f.write(json.dumps({"t": t0, "kind": kind, "code": c, "ms": ms, "resp": (js if isinstance(js, (dict, list)) and len(json.dumps(js)) < 200 else str(js)[:100])}, ensure_ascii=False) + "\n"); f.flush()
    return c
def step(i):
    global RGUID
    k = i % 6
    if k == 0: do("rename", "PATCH", "/sources/groups/" + G, {"name": GNAME + " ~"}); state["renamed"] = True
    elif k == 1: do("rename-back", "PATCH", "/sources/groups/" + G, {"name": GNAME}); state["renamed"] = False
    elif k == 2: do("member-del", "DELETE", "/sources/groups/%s/memberships" % G, {"sourceGuids": [S]}); state["removed"] = True
    elif k == 3: do("member-add", "POST", "/sources/groups/%s/memberships" % G, {"sourceGuids": [S]}); state["removed"] = False
    elif k == 4: do("rule-del", "DELETE", "/access-rules", [RGUID]); state["ruledel"] = True
    else:
        c = do("rule-add", "POST", "/access-rules", {"userGroupID": 1, "rules": [{"sourceGroupGuid": RSG}]}); state["ruledel"] = False
        _, gs, _, _ = N.call("GET", "/access-rules", T())
        RGUID = next(r["guid"] for g in gs if g["id"] == 1 for r in g["rules"] if r.get("sourceGroup", {}).get("guid") == RSG)
t_end = time.time() + DUR; i = 0; nxt = time.time()
while time.time() < t_end:
    step(i); i += 1; nxt += IV
    time.sleep(max(0, nxt - time.time()))
# довести круг до целого
while i % 6: step(i); i += 1
print("правок", i, flush=True)
