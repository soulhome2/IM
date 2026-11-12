#!/usr/bin/env python3
"""Пачка событий демонабора, как `agent-emulator replay --run <метка>`, но прямым входом X-Dev-Agent
(IM_AGENT_DEV_AUTH на стенде, запрос с 127.0.0.1). Причина: ключа HMAC эмулятора (~/.config/im-agent-emulator/key.json)
в базе нет (agent_api_keys пуста) — replay получает 401. Тело и guid событий — как в replay.go/main.go:send.
Время события (occurredAt) — сейчас, а не дата набора (октябрь): иначе инцидент с первой же секунды просрочен,
и сервер при любом переходе сперва догоняет таймеры эскалации — взять его нельзя (412, «Ожидает принятия»).
Запуск: python3 -I replay_dev.py <метка>. Печатает «отправлено N, пропущено 0», код 1 при первой ошибке."""
import http.client, json, sys, time, uuid
FX = "/mnt/hgfs/VmWareShared/soul2home/IM/Specification/Workflow_machine/fixtures/demo.json"
AGENT = "01a18217-5af1-7948-a879-21acffd5fe93"  # агент «Стенд: эмулятор» из таблицы agents
run = sys.argv[1]
fx = json.load(open(FX))
names = {d["id"]: d["name"] for d in fx["devices"]}
seen, evs = set(), []
for inc in fx["incidents"]:
    g = inc.get("eventGuid")
    if not g or not inc.get("devices") or g in seen:
        continue
    seen.add(g)
    evs.append((inc["occurredAt"], str(uuid.uuid5(uuid.UUID(g), run)), inc))
evs.sort(key=lambda x: (x[0], x[1]))  # occurredAt одного формата RFC3339 — порядок строк = порядок времени
c = http.client.HTTPConnection("127.0.0.1", 5000, timeout=30)
sent = 0
now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
for at, guid, inc in evs:
    dev = inc["devices"][0]
    body = {"guid": guid, "sourceUid": dev, "eventTypeUid": inc["eventType"]["id"],
            "payload": {"occurredAt": now, "deviceName": names.get(dev, ""), "text": inc.get("location", ""),
                        "site": inc.get("site", ""), "emulator": True}}
    c.request("POST", "/api/v1/im-backend/events", json.dumps(body), {"Content-Type": "application/json", "X-Dev-Agent": AGENT})
    r = c.getresponse(); raw = r.read()
    if r.status != 200:
        print("ошибка: событие %s: %d %s\nотправлено %d, пропущено 0" % (guid, r.status, raw[:200], sent)); sys.exit(1)
    sent += 1
print("отправлено %d, пропущено 0" % sent)
