# Этап 1б встраивания в облако: одно событие — несколько инцидентов — план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Каждая задача — через superpowers:test-driven-development: сначала падающий тест, потом код.

**Goal:** Событие проходит через правила, и каждое подошедшее правило со сценарием создаёт свой инцидент: ключ «событие + сценарий», приоритет от правила, сквозной номер тревоги, соседи видят друг друга, при «Дубликате» — предупреждение о соседях, «Массовый сбой» на выборке закрывает только свой сценарий, уведомление о ложной тревоге соседа, фильтр и нормативы по сценарию.

**Architecture:** Пункт `ARCH-15` из девяти подзадач. Выбор правила — выражения CEL в машине (новый раздел `intake`, ARCH-07); прототип собирает данные и вызывает определения. Правила-фильтры — новый раздел `rules` эталонного набора по образцу `incident_rules` сервера МИ; события сервер прототипа собирает из `eventGuid` инцидентов. Состояний и переходов машина не получает: меняются `close`, форма закрытия, нормативы, реестры. Сначала ядро (15.1) и событие в модели Quint (15.2), затем независимые слои — нормативы, соседи в интерфейсе, фильтр, предупреждение у «Дубликата», выборка, уведомление; документы для бэкенда — в конце.

**Вне этапа (решение 2026-10-28):** цепочка эскалации по службе и адресация дежурной группе правила (М1) — открытые вопросы §15; вход и токены не трогаем; редактора правил нет — правила только в эталонном наборе.

**Tech Stack:** JSON машины, контракта и набора; CEL (`prototype/cel-runtime.js`); JavaScript прототипа; Python-проверки (`tools/check_*.py`); Quint; headless Chrome для самопроверки и тестов API.

**Spec:** [design-1b.md](design-1b.md) — проект и «Выбор проектировщика» В1…В17 и решения пользователя по В2, В4, В7, В8 (2026-10-28); основание — [41-multi-service.md](../../research/integration/41-multi-service.md), «Решение пользователя», и решения № 9, № 10 в [40-plan.md](../../research/integration/40-plan.md).

Ветка — `feature/im_operator`. Коммит — после каждой задачи, сообщение с номером подзадачи (`ARCH-15.1: …`); строка журнала правил — вторым коммитом с хэшем первого, как в этапе 1. Push — по просьбе.

## Global Constraints

- Источник истины — правила и машина. Правило меняется в `workflow_schema.v1.json` и `States rules IM.md`, а не в `prototype/*.js`; прототип только вызывает определения машины.
- `Specification/Workflow_machine/openapi.json` и `Specification/Workflow_machine/README.md` — в CRLF.
- Сгенерированные файлы руками не править: `prototype/workflow.js`, `openapi.js`, `fixture.js`, `strings.js`, `TRANSITIONS.md`, `SETTINGS.md`, `openapi.v30.json` — `python3 tools/build_workflow.py`; `quint/im.qnt` — `node tools/gen_quint.mjs`; `tools/mutations/MACHINE.md` — `python3 tools/mutation_table.py`.
- Быстрые проверки — после каждой задачи: `python3 tools/build_workflow.py --check`, `python3 tools/check_machine.py` и `--mutations`, `node tools/check_cel.mjs`, `node tools/gen_quint.mjs --check`, `python3 tools/check_links.py`. Самопроверка, тесты API и тесты сценариев — headless Chrome по `CLAUDE.md` (временные каталоги — в scratchpad).
- Выражения CEL — только то, что переводится в Quint (CEL.md, «Что из CEL можно»): строки только сравниваются на равенство, факты над инцидентами — только из условий, эффектов и правил интерфейса.
- Новые идентификаторы набора: события — `70000000-0000-4000-8000-00000000NNNN` (NNNN — цифры номера первого инцидента события), правила — `80000000-0000-4000-8000-00000000000N` (`…0001`–`…0008` базовые, `…0009` медпункт, `…000a` датчик дыма 2), сценарий медпункта — `60000000-0000-4000-8000-000000000009`. Префиксы `7` и `8` в наборе сейчас свободны — проверить перед вставкой.
- Строки машины — `Specification/Workflow_machine/strings/ru.json` и `en.json`; строки интерфейса — `t(…)` в `app.js` с переводом в `i18n-ui.js`; после правки — `python3 tools/check_i18n.py`, `python3 tools/check_guide.py`.
- Язык текстов, комментариев и сообщений коммитов — русский, простыми словами.

## Review Focus

1. **Старые тесты тихо меняют смысл.** Набор получает правила и соседа `INC-1853`, `/test/incidents` берёт приоритет правила вместо «самого низкого»: счётчики дерева, страницы очереди и нормативы в тестах могут поменяться. Тест — задача 15.1, шаг «полный прогон»: самопроверка, тесты API и сценариев зелёные, изменённые ожидания — только из списка в шаге.
2. **Второй инцидент одного сценария на событие** — от повтора или пересекающихся правил. Тест — 15.1, «Повтор события ничего не создаёт…» и «Пересекающиеся правила одного сценария — один инцидент…»; свойство в `api-properties.js`; инвариант Quint `eventScenarioUnique` — 15.2.
3. **Победитель не тот или его нет** — точность и приоритет перепутаны, равенство не разрешено. Тест — 15.1, «Ранжирование: вложенная группа точнее родителя…» и порча `intake-priority-first`.
4. **«Массовый сбой» закрывает чужой сценарий** — правило своего сценария есть только на панели, а прямой запрос `…/transitions/close/bulk` закрывает всех, или «свой» сценарий берётся не по основному §11.3. Тест — 15.7, «Массовый сбой на выборке: закрывает только сценарий основного…» (два случая: основной — новый пожар; основной — мой медпункт в работе) и порча `bulk-close-all-scenarios`.
5. **Уведомление о ложной тревоге уходит не тем** — себе, закрытым соседям, при другом результате, или не доходит группе. Тест — 15.8, «Ложная тревога у соседа…» с тремя отрицательными случаями и порча `sibling-notice-any-result`.

---

### Task 15.1: Событие через правила — инцидент на каждый сценарий

**Files:**
- Modify: `Specification/Workflow_machine/workflow_schema.v1.json` — `cel.types` (`Event`, `Condition`, `Rule`, `Incident.eventGuid`), `cel.world` (`deviceInGroup`, `groupDepth`, факт `siblingsOf`), `cel.definitions` (`conditionMatches`, `conditionRank`, `ruleRank`, `ruleMatches`, `ruleBeats`, `ruleFor`), новый раздел `intake`, `transitions.create.$comment`, `invariants.oneIncidentPerEventScenario`
- Modify: `Specification/Workflow_machine/fixtures/demo.json` — `rules`, `scenarios.keys` вместо `byEventType`, у инцидентов `eventGuid`, `alarmNumber`, `ruleGuid`, новый `INC-1853`
- Create: `Specification/Workflow_machine/fixtures/scenarios/medical.v1.json` — по образцу `alcohol.v1.json`, три шага: «Есть пострадавшие?» (да/нет), «Вызвать скорую» (кнопка), финальный «Итог по пострадавшим» (комментарий)
- Modify: `Specification/Workflow_machine/openapi.json` (CRLF) — `IncidentSummary` (`eventGuid`, `alarmNumber` обязательные; `ruleGuid`), `IncidentCard.ruleName`, `POST /test/events`, `TestEventRequest`, `TestEventResult`, `TestIncidentRequest.ruleGuid` и описание `priority`
- Modify: `prototype/server.js` (`load`, `createIncident`, новый `intakeEvent`, `summary`, `card`, маршруты), `prototype/engine.js` (`celIncident`, мир, `intake`)
- Modify: `tools/check_machine.py` (набор: правила и события; раздел `intake`), `tools/check_scenarios.py` (`keys`, сценарий инцидента — из его правила)
- Modify: `Specification/Workflow_machine/quint/src/world.qnt` — `deviceInGroup` = `false`, `groupDepth` = `0` (пустой инцидент и форму `gen_quint.mjs` собирает из типов сам)
- Modify: `tests/api-scenarios.js`, `tests/api-junction.js`, `tests/api-properties.js`, `prototype/selftest.js`
- Modify: `tools/mutations/machine.json`, `tools/mutations/probe.js`, `tools/mutations/api-killers.json`, `tools/mutations/quint-catchers.json`
- Modify: `Specification/State_rules/States rules IM.md` — §1, §2.2 (поля), §2.5, §6.2 (`create`), §14.5, §15, §17; `Specification/State_rules/CHANGELOG.md`
- Rebuild: всё из `build_workflow.py`, `quint/im.qnt`

**Interfaces:**
- Produces (машина): `conditionMatches(c: Condition, e: Event): bool`; `conditionRank(c: Condition): int` — устройство 3000, тип устройства 2000, группа 1000 + `groupDepth`, иначе 0; `ruleRank(r: Rule, e: Event): int` — наибольший ранг подошедших условий, нет — `-1`; `ruleMatches(r, e): bool` — `size(r.scenarios) > 0` и подошло условие; `ruleBeats(a, b, e): bool` — строго: ранг, затем `priority`, затем меньший `createdAt`; `ruleFor(rules: list<Rule>, e: Event, s: string): list<Rule>` — подошедшие со сценарием `s`, которых не бьёт никто. Ранжирование — правило (решение пользователя по В2), не «предложение». Раздел `intake: {uniqueKey: ["eventGuid", "scenario"], match: "ruleMatches", winner: "ruleFor", create: "create"}`. Факт `siblingsOf(x): list<Incident>`.
- Produces (набор): правило `{guid, name, priority, createdAt, scenarios: [guid], conditions: [{eventTypeId?, deviceGuid?, deviceTypeId?, sourceGroupGuid?}]}`; `scenarios.keys: {fire, intrusion, sabotage, loiter, ppe, alcohol, glass, abandoned, medical}`.
- Produces (прототип): `engine.intake(rules, event) -> [{scenario: string, rule: Rule}]` — по сценарию победитель; порядок создания — по `ruleBeats` победителей, сценарии одного правила — по его списку; номер тревоги — номер первого созданного; `server.intakeEvent(spec) -> {eventGuid, alarmNumber|null, created: Incident[], incidents: Incident[]}`.
- Produces (контракт): `POST /test/events` → `201`/`200` `TestEventResult {eventGuid, alarmNumber, created, incidents: IncidentCard[]}`; `POST /test/incidents` — `ruleGuid?`.

- [ ] **Step 1: Write the failing tests** — `tests/api-scenarios.js`, новый раздел «Одно событие — несколько инцидентов (§14.5, ARCH-15)»; `S5` — устройство `20000000-0002-4000-8000-000000000005` (торговый центр), `S2` — `…0002-…000000000002`:
  - «Событие через правила: инцидент на каждый сценарий подошедших правил, один номер тревоги, приоритет — от правила (§14.5, ARCH-15)»: `POST /test/events {eventTypeId: "fire", deviceIds: [S5], site: "Торговый центр"}` → `201`, `created == 2`; сценарии — `{keys.fire, keys.medical}`; у обоих `eventGuid` = ответа; первым создан медпункт (точнее условие): `incidents[0].number == "INC-1854"`, у обоих `alarmNumber == "INC-1854"`; пожар — `INC-1855`, приоритет 75, `ruleGuid` `80…0001`; медпункт — 100, `80…0009`; по событию `incident.created` на каждый.
  - «Пересекающиеся правила одного сценария — один инцидент; побеждает самое точное, даже с приоритетом ниже (§14.5, ARCH-15)»: событие пожара на `S2` → `created == 1`, `ruleGuid` `80…000a`, приоритет 100; с `fixturePatch`, где у `80…000a` приоритет 25, — снова `80…000a`, приоритет 25.
  - «Ранжирование: вложенная группа точнее родителя; при равной точности — выше приоритет, затем раньше созданное (§14.5, ARCH-15)»: `fixturePatch.rules` — два правила сценария пожара: группа «Торговый центр», приоритет 100, и её первая вложенная группа с `S5` (из `GET /operator/reference/source-groups`), приоритет 25 → победитель вложенная, приоритет 25; два правила с группой «Торговый центр» и приоритетом 50 — побеждает с меньшим `createdAt`.
  - «Повтор события ничего не создаёт: тот же eventGuid — 200, created 0, те же инциденты и номер тревоги (§14.5, ARCH-15)».
  - «Правило без сценария не участвует; не подошло ни одно — инцидентов и номера тревоги нет (§14.5, ARCH-15)»: правило без сценариев с условием «саботаж на этом устройстве», приоритет 100, — инцидент по базовому `80…0003`; набор без базового правила разбития стекла → событие `glass` → `200`, `created == 0`, `alarmNumber == null`, в очереди нового нет.
  - «Тестовый инцидент: по базовому правилу типа или по ruleGuid; приоритет — правила, priority в теле — подмена (§2.5, ARCH-15)»: пожар без `priority` → 75 и `80…0001`; с `ruleGuid` `80…0009` → сценарий медпункта, 100; с `priority: 83` → 75; неизвестный `ruleGuid` → `422`.
  - переписать «Приоритет от источника приводится к уровню справочника…» в «Приоритет тестового инцидента приводится к уровню справочника…; без числа — приоритет правила (§2.5)»: пара `[undefined, 75]` вместо `[undefined, lowest]`.
  - `tests/api-properties.js`, `invariants()`: у каждого инцидента есть `eventGuid` и `alarmNumber`; пара `(eventGuid, scenarioTitle)` не повторяется; у инцидентов одного `eventGuid` один `alarmNumber`, и это номер одного из них, у которого `alarmNumber == number`.
  - `prototype/selftest.js`, шаг «Событие через правила: инцидент на каждый сценарий, повтор ничего не создаёт (§14.5, ARCH-15)» — через стенд, те же утверждения, что первый и четвёртый тесты.
  - `tools/check_machine.py`, проверка набора `check_rules(fx, err)`: guid и `createdAt` правил уникальны, `createdAt` не позже `capturedAt`; сценарии правил есть в `scenarios.rows`; поля условий ссылаются на существующие типы событий, устройства, типы устройств, группы; в условии хоть одно поле; у каждого типа события инцидентов — ровно одно базовое правило; у инцидента `eventGuid`, `alarmNumber`, `ruleGuid`; у инцидентов одного события — один номер тревоги, одно устройство-источник, один тип и разные сценарии; номер тревоги — номер инцидента этого события, у которого номер тревоги свой; у разных событий — разные номера; сценарий инцидента — в сценариях его правила. Раздел `intake` машины ссылается на существующие определения и переход с `trigger: event`. Две порчи в `MUTATIONS` check_machine: соседу набора — сценарий соседа; соседу — другой номер тревоги.
- [ ] **Step 2: Run tests to verify they fail** — тесты API: новые падают на `404` у `/test/events`; `python3 tools/check_machine.py` — «нет раздела rules» и «нет раздела intake».
- [ ] **Step 3: Implement the machine** — типы, мир, определения и раздел `intake` по Interfaces; `create.$comment` — «по правилу; приоритет — правила; все инциденты события — одной транзакцией с отметкой события (§14.5)»; `invariants.oneIncidentPerEventScenario: true` с `$comment`. Модель Quint — только заглушки в `world.qnt`, чтобы `im.qnt` собрался.
- [ ] **Step 4: Implement the fixture** — правила по design-1b.md, раздел 2, номер тревоги у 27 инцидентов — свой номер (базовые приоритеты: пожар 75, проникновение 75, саботаж 50, праздношатание 25, СИЗ 50, алкоголь 75, стекло 75, оставленный предмет 75); `INC-1853` — «Медпомощь при пожаре», `new`, приоритет 100, событие и тревога `INC-1847`, устройства как у `INC-1847`, журнал — запись появления; `byEventType` → `keys` и правка потребителей (`selftest.js` четыре места, `api-junction.js`, `check_scenarios.py`).
- [ ] **Step 5: Implement the server** — `load()`: правила, события из инцидентов; `engine.intake` через `W.intake.match` и `W.intake.winner`, мир `deviceInGroup` — по дереву (`inGroup`), `groupDepth` — число предков узла; `intakeEvent(spec)` по design-1b.md, раздел 3, всё или ничего, номер тревоги — номер первого созданного; `createIncident(spec)` — правило из `ruleGuid` или базовое, приоритет правила или подмена из тела; поля `eventGuid`, `alarmNumber`, `ruleGuid` в `summary()`, `ruleName` в `card()`; маршрут `POST /test/events`; ошибка — `422` `workflow.error.test.bad_event`.
- [ ] **Step 6: Contract and rules** — контракт по Interfaces; правила: §1 («Событие», «Инцидент», новые «Правило», «Тревога», «Соседние инциденты»; `event_guid`, `alarm_number`, `rule_guid` в технических именах), §2.2 (поля), §2.5 («У инцидента» — от правила; приведение — при переоткрытии и подмене на стенде; удалять уровень нельзя, пока на него ссылается правило), §6.2 (`create`), §14.5 (алгоритм design-1b.md, раздел 3), §15 (вопросы о приоритете и о ранжировании — в решённые: «правило», «§14.5, решение 2026-10-28»), §17 (правила — из набора, редактора нет). CHANGELOG — строка «ARCH-15.1: событие проходит через правила — инцидент на каждый сценарий; приоритет от правила; ранжирование правил; номер тревоги — номер первого инцидента (решения 2026-10-28, 41-multi-service.md)».
- [ ] **Step 7: Mutation** — `intake-priority-first`: в `ruleBeats` приоритет сравнивается раньше ранга; проба — событие на `S2` при приоритете `80…000a` 25 даёт приоритет 75; ловит тест «Пересекающиеся правила…»; в `quint-catchers.json` пометка «вне модели: выбор правила по событию». `python3 tools/check_mutations.py intake-priority-first`, `python3 tools/check_code_mutations.py intake-priority-first`, `python3 tools/mutation_table.py`.
- [ ] **Step 8: Full run** — `python3 tools/build_workflow.py`, `node tools/gen_quint.mjs`, быстрые проверки, `python3 tools/check_scenarios.py`, самопроверка, тесты API, `tests/scenario.html`, `quint test …/im_test.qnt`. Ожидаемые правки старых тестов — только: приоритет тестового инцидента без числа (выше; следствие решения № 9 «приоритет задаёт правило»), счётчики устройства `S5` и группы «Торговый центр» (+1 от `INC-1853`), число инцидентов набора 27 → 28. Любое другое падение — разобрать, а не подгонять.
- [ ] **Step 9: Commit** — `ARCH-15.1: событие проходит через правила — инцидент на каждый сценарий`; вторым коммитом — хэш в CHANGELOG.

### Task 15.2: Модель Quint — событие в появлении инцидента

**Files:**
- Modify: `Specification/Workflow_machine/quint/src/core.qnt` — `create(i, ev, sc, prio)` с условием «нет инцидента с той же парой `eventGuid` + `scenario`»; `createAny` выбирает событие из `Set("ev1", "ev2")`
- Modify: `quint/src/invariants.qnt` — `eventScenarioUnique`, `siblingsNotLinked` (у привязанного событие другое, чем у основного), оба в `inv`
- Modify: `quint/src/replay.qnt`, `tools/check_quint_replay.mjs` — событие инцидента в повторе
- Modify: `quint/im_test.qnt` — `siblingsTwoScenariosTest`; `Specification/Workflow_machine/quint/README.md` — инварианты
- Rebuild: `quint/im.qnt`

**Interfaces:**
- Consumes: `Incident.eventGuid` из 15.1.

- [ ] **Step 1: Write the failing test** — `siblingsTwoScenariosTest`: `create("i1", "ev1", "sc1", 100)` и `create("i2", "ev1", "sc2", 75)` проходят, `create("i3", "ev1", "sc1", 100)` — нет; `merge` `i2` к `i1` не проходит (разные сценарии).
- [ ] **Step 2: Run test to verify it fails** — `quint test` — неверное число аргументов `create`.
- [ ] **Step 3: Implement** — по Files.
- [ ] **Step 4: Run tests to verify they pass** — `node tools/gen_quint.mjs` и `--check`, `quint test …/im_test.qnt`, `quint run …/im.qnt --invariant inv`, `node tools/check_quint_replay.mjs`, `node tools/check_quint_mutations.mjs scenario-ignored`.
- [ ] **Step 5: Commit** — `ARCH-15.2: модель Quint — событие, соседи, инварианты уникальности`.

### Task 15.3: Нормативы по сценарию

**Files:**
- Modify: `workflow_schema.v1.json` — `cel.types.Override.scenario: opt<string>`; `overrideKeys`, `overrideMatches`, `overrideAllowed` — с `scenario`; `timers` `reaction` и `resolution` — `overridesBy` + `"scenario"`; `$comment` таймеров
- Modify: `tools/check_machine.py` — `scenario` в строке `overrides` — guid сценария из набора
- Modify: `States rules IM.md` §4, правило 2; CHANGELOG; `tests/api-scenarios.js`; `prototype/selftest.js`; `tools/mutations/*`
- Rebuild: `SETTINGS.md`, `TRANSITIONS.md`, `workflow.js`, `im.qnt`

**Interfaces:**
- Consumes: `Incident.scenario`, сосед `INC-1853` и `/test/events` из 15.1.
- Produces: строка уточнения `{scenario?, eventType?, priority?, sourceGroup?, sec}`; точность — число заданных ключей.

- [ ] **Step 1: Write the failing test** — «Норматив по сценарию: строка со scenario даёт свой срок; строка из двух ключей точнее строки по приоритету (§4, правило 2; ARCH-15)»: `workflowPatch` реакции — прежние строки плюс `{scenario: MED, sec: 120}` и `{scenario: MED, priority: 100, sec: 90}`; событие пожара на `S5` → у медпункта `dueAt − createdAt = 90 с`, у пожара (75) — 420 с; с `overridesBy` без `"scenario"` — у медпункта 240 с. Шаг самопроверки «Норматив реакции по сценарию: у медпункта свой срок в заголовке карточки (§4, ARCH-15)».
- [ ] **Step 2: Run test to verify it fails** — у медпункта 240 с.
- [ ] **Step 3: Implement** — машина по Files; `check_machine.py`: неизвестный сценарий в `overrides` — ошибка `таймер <id>, overrides[i]: сценария <guid> нет в наборе`; правило §4, правило 2: «на тип события, приоритет, группу устройств и сценарий»; CHANGELOG.
- [ ] **Step 4: Mutation** — `override-scenario-ignored`: из `overrideMatches` убрано условие по сценарию; ловит тест выше; Quint — «мир модели: нормативы по сценарию в модели не различаются».
- [ ] **Step 5: Run tests to verify they pass** — сборка, быстрые проверки, тест и шаг самопроверки, `check_mutations.py override-scenario-ignored`, `check_code_mutations.py override-scenario-ignored`.
- [ ] **Step 6: Commit** — `ARCH-15.3: нормативы реакции и закрытия по сценарию`.

### Task 15.4: Тревога и соседи в очереди и карточке

**Files:**
- Modify: `openapi.json` — `IncidentSummary.siblingCount`; `IncidentCard.alarm`, `AlarmSibling`; описание поиска — и по номеру тревоги
- Modify: `prototype/server.js` (`summary`, `card`, поиск), `prototype/app.js` (`eventRowHtml`, новый `siblingChip(e)`, `renderScenario` — блок `alarmBlock(ev)`), `prototype/styles.css`, `prototype/i18n-ui.js`
- Modify: `prototype/selftest.js`, `tests/api-scenarios.js`, `tools/check_ui.py` (экран «карточка с соседями»)
- Modify: `States rules IM.md` §5, §7, §19.1; CHANGELOG

**Interfaces:**
- Consumes: `eventGuid`, `alarmNumber` из 15.1.
- Produces: `siblingCount: int` — видимые незакрытые соседи; `alarm: {eventGuid, number, status: "open"|"closed", allFalseAlarm: bool, siblings: AlarmSibling[]}`; `AlarmSibling {guid, number, scenarioTitle, state, badge, owner, closeResultLabel}` — все видимые соседи, по номеру.

- [ ] **Step 1: Write the failing tests** — «Соседи: siblingCount — видимые незакрытые, в карточке — все соседи и статус тревоги (§5, §7, ARCH-15)»: у `INC-1847` `siblingCount == 1`, `alarm.number == "INC-1847"`, `alarm.siblings` — `[INC-1853]`, `status == "open"`; взять и закрыть `INC-1853` «Ложной тревогой» → у `INC-1847` `siblingCount == 0`, в `siblings` — `INC-1853` с `state == "closed"`; закрыть `INC-1847` «Ложной тревогой» → `status == "closed"`, `allFalseAlarm == true`; у инцидента без соседей `siblings == []`, `siblingCount == 0`. «Поиск находит инциденты по номеру тревоги (§7, ARCH-15)»: `search=INC-1847` → `INC-1847` и `INC-1853`. Шаг самопроверки «Тревога в очереди и карточке: номер тревоги, «событие: ещё 1», блок «По этому событию» (§7, ARCH-15)»: строка `INC-1853` — «тревога INC-1847», строка `INC-1847` — без неё (номер тревоги свой, В17), у обеих чип `[data-siblings]` «событие: ещё 1»; в карточке блок `#alarmBlock` с «INC-1853 — Медпомощь при пожаре»; нажатие на номер открывает `INC-1853` на просмотр.
- [ ] **Step 2: Run tests to verify they fail** — полей нет.
- [ ] **Step 3: Implement** — сервер: соседи — `events` с тем же `eventGuid`, без себя, `canSee`; статус — по ним и себе. Интерфейс: «тревога INC-…» — в `event-sub` после номера инцидента, только если номер тревоги не свой; чип — не `.chip.linked`, свой значок, подсказка — номера и бейджи соседей; блок над шагами: «Тревога INC-1847 · открыта», строки соседей без кнопок действий, номер — действие `view`. Правила: §5 — соседи, число и статус — по видимым; §7 — строка очереди и блок; §19.1 — счётчики считают инциденты, не тревоги. CHANGELOG.
- [ ] **Step 4: Run tests to verify they pass** — тесты, самопроверка, `python3 tools/check_ui.py`, `check_i18n.py`, `check_guide.py`, быстрые проверки.
- [ ] **Step 5: Commit** — `ARCH-15.4: номер тревоги и соседи в очереди и карточке`.

### Task 15.5: Фильтр очереди по сценарию

**Files:**
- Modify: `openapi.json` — параметр `scenarioGuid` у `GET /operator/incidents`, `GET …/counters`, `SelectionRequest`; `GET /operator/reference/scenarios`, `ScenarioRef`
- Modify: `prototype/server.js` (фильтр очереди, счётчики, выборка, справочник), `prototype/app.js` (`state.scenarios`, `queueQuery`, список «Сценарий» в «Фильтры»), `i18n-ui.js`
- Modify: `tests/api-scenarios.js`, `prototype/selftest.js`, `tools/check_ui.py` (панель «Фильтры» с тремя списками)
- Modify: `States rules IM.md` §19.2; CHANGELOG

**Interfaces:**
- Produces: `scenarioGuid` — один или несколько guid через запятую, как `eventTypeGuid`; `ScenarioRef {guid, name}` — сценарии правил и открытых инцидентов, по названию.

- [ ] **Step 1: Write the failing tests** — «Фильтр очереди по сценарию: в очереди, счётчиках и выборке «Все в фильтре» — только инциденты сценария (§19.2, ARCH-15)»: `filter=all&scenarioGuid=MED` → только `INC-1853`; счётчики с тем же параметром → `open == 1`; `selection {mode: "all_in_filter", scenarioGuid: MED}` → один guid. «Справочник сценариев: сценарии правил и открытых инцидентов, по названию (§19.2, ARCH-15)»: есть `MED` и сценарий пожара, порядок по `name`. Шаг самопроверки «Фильтр «Сценарий»: в очереди только инциденты выбранного сценария (§19.2, ARCH-15)».
- [ ] **Step 2: Run tests to verify they fail** — `404` справочника, параметр не действует.
- [ ] **Step 3: Implement** — по Files; правило §19.2: «тип события, тип устройства и сценарий»; у соседей совпадает всё, кроме сценария, — фильтр разделяет службы. CHANGELOG.
- [ ] **Step 4: Run tests to verify they pass** — тесты, самопроверка, `check_ui.py`, `check_i18n.py`, быстрые проверки.
- [ ] **Step 5: Commit** — `ARCH-15.5: фильтр очереди по сценарию`.

### Task 15.6: «Дубликат» — предупреждение о соседях

Решение пользователя 2026-10-28 (В7): только предупреждение — нового поля нет, сервер закрытие не отклоняет.

**Files:**
- Modify: `workflow_schema.v1.json` — у поля `resultId` формы `close` новый ключ `warnings: [{expr, textKey, vars}]`; `strings/ru.json`, `en.json` — `workflow.form.close.warn.duplicate_siblings` «У этого события есть ещё инциденты ({n}) — это другие службы той же тревоги, а не дубликаты. Закрыть можно, их это не закроет»
- Modify: `prototype/cel-runtime.js` и `tools/check_cel.mjs` — выражения `warnings[].expr` и `vars` проверяются как правила интерфейса; `Specification/Workflow_machine/CEL.md`, «Правила интерфейса» — строка о `warnings`
- Modify: `prototype/engine.js` (`form()` — предупреждение у варианта), `prototype/server.js` (`formView` — `warning` в `fieldOptions`), `prototype/app.js` (под полем `[data-warning]` — предупреждение выбранного варианта), `i18n-ui.js` при новых строках интерфейса
- Modify: `openapi.json` — `FieldOption.warning` — `{key, text, vars}` или null
- Modify: `States rules IM.md` §2.2 (строка «Дубликат»), §6.1 (`close`), §7 (форма); CHANGELOG; `tests/api-scenarios.js`; `prototype/selftest.js`; `tools/mutations/*`

**Interfaces:**
- Produces: предупреждение варианта — `{expr: "option == 'duplicate' && size(siblingsOf(incident).filter(s, hasAccess(me, s))) > 0", textKey: "workflow.form.close.warn.duplicate_siblings", vars: {n: "size(siblingsOf(incident).filter(s, hasAccess(me, s)))"}}`; `FieldOption.warning` — первое подходящее предупреждение варианта, нет — null.

- [ ] **Step 1: Write the failing tests** — «Дубликат при соседях: предупреждение у варианта, закрытие не запрещено; без соседей — без предупреждения (§2.2, §7, ARCH-15)»: взять `INC-1847`; в форме закрытия у варианта `duplicate` — `warning.key == "workflow.form.close.warn.duplicate_siblings"`, `warning.vars.n == 1`; у остальных вариантов `warning == null`; закрыть «Дубликатом» с комментарием → `200`, `closed`, `INC-1853` по-прежнему `new`; взять `INC-1851` (соседей нет) — у `duplicate` `warning == null`. Шаг самопроверки «Дубликат при соседях: предупреждение под списком результатов, закрыть можно (§2.2, ARCH-15)»: в форме `INC-1847` выбрать «Дубликат» — виден `[data-warning]` с «другие службы той же тревоги»; у `INC-1851` — не виден.
- [ ] **Step 2: Run tests to verify they fail** — `warning` нет.
- [ ] **Step 3: Implement** — по Files и Interfaces; правила: §2.2 «Дубликат» — «Та же тревога уже разбирается в другом инциденте; инцидент того же события другой службы — не дубликат: при соседях форма предупреждает, закрыть можно»; §7 — предупреждение в форме «Закрыть без обработки»; CHANGELOG.
- [ ] **Step 4: Mutation** — `duplicate-warning-off`: условие предупреждения — `false`; ловит тест выше; Quint — «вне модели: правило интерфейса».
- [ ] **Step 5: Run tests to verify they pass** — сборка, быстрые проверки, тесты, самопроверка, `check_mutations.py duplicate-warning-off`, `check_code_mutations.py duplicate-warning-off`, `check_ui.py`, `check_i18n.py`, `check_guide.py`.
- [ ] **Step 6: Commit** — `ARCH-15.6: предупреждение о соседях при «Дубликате»`.

### Task 15.7: «Массовый сбой» на выборке — только свой сценарий

Решение пользователя 2026-10-28 (В8): действие остаётся доступным, инциденты других сценариев пропускаются. Свой сценарий — сценарий основного выборки (design-1b.md, раздел 5).

**Files:**
- Modify: `workflow_schema.v1.json` — определение `bulkPrimary(xs: list<Incident>, who: string): list<Incident>`; `transitions.close.bulk.scope: "primaryScenario"` с `$comment`; `strings/*.json` — `workflow.form.close.bulk.note.scenario` «Закроются инциденты сценария «{scenario}»: {n} из {total}. Других сценариев — {skipped}, они останутся открытыми», `workflow.error.selection.other_scenario` «другой сценарий»
- Modify: `prototype/engine.js` (`bulkPrimary` для сервера), `prototype/server.js` (`selectionActions`, `sharedForm`, маршрут `…/transitions/{transitionId}/bulk`), `prototype/app.js` (уведомление «Не закрыты — другой сценарий: …»), `i18n-ui.js`
- Modify: `openapi.json` — `BulkTransitionResult.skipped[]` `{incidentGuid, number, reasonKey}`; описание bulk и общей формы выборки
- Modify: `tools/check_machine.py` (`bulk.scope` — только `primaryScenario` и только при `mode: each_allowed`)
- Modify: `States rules IM.md` §11.1 («Формы», «Результат»); CHANGELOG; `tests/api-scenarios.js`; `prototype/selftest.js`; `tools/mutations/*`

**Interfaces:**
- Produces: `bulkPrimary(xs, who)` = `mergePrimary(xs, who)`, а если он пуст — из всех `xs` самый срочный, у равных — появившийся раньше, у совсем равных — первый по порядку выборки (по возрастанию номера, как у `mergePrimary`). При `bulk.scope: "primaryScenario"` переход применяется к отмеченным со сценарием основного; доступность — по ним же; остальные — в `skipped` с `reasonKey: "workflow.error.selection.other_scenario"`, не меняются.

- [ ] **Step 1: Write the failing tests** — «Массовый сбой на выборке: закрывает только сценарий основного, другие пропускает и называет (§11.1, ARCH-15)»: выборка `[INC-1847, INC-1851, INC-1853]` (все новые, приоритет 100; основной — `INC-1851`: появился раньше всех, 11:58:43 против 11:59:00; сценарий — пожар) — `close` `enabled == true`, `formNote.key == "workflow.form.close.bulk.note.scenario"`, `vars` `{n: 2, total: 3, skipped: 1}`; `POST …/transitions/close/bulk` с «Массовым сбоем» → `200`, `succeeded` — `INC-1847`, `INC-1851`; `skipped == [{number: "INC-1853", reasonKey: "workflow.error.selection.other_scenario", …}]`; `INC-1853` — `new`, версия прежняя. Второй случай: взять `INC-1853` — основной он (свой «В работе»), выборка `[INC-1847, INC-1853]` → закрыт `INC-1853`, `INC-1847` пропущен. Шаг самопроверки «Массовый сбой на выборке двух сценариев: закрыт свой сценарий, о пропущенных — уведомление (§11.1, ARCH-15)».
- [ ] **Step 2: Run tests to verify they fail** — закрываются все три, `skipped` нет.
- [ ] **Step 3: Implement** — по Files и Interfaces; правило §11.1: «Закрыть без обработки на выборке закрывает только инциденты сценария основного (§11.3; нет основного — самый срочный, затем появившийся раньше); остальные пропускаются и перечислены в форме и в уведомлении: массовый сбой одной службы не закрывает инциденты другой»; CHANGELOG.
- [ ] **Step 4: Mutation** — `bulk-close-all-scenarios`: без `bulk.scope`; ловит тест выше; Quint — «вне модели: выборки в модели нет».
- [ ] **Step 5: Run tests to verify they pass** — сборка, быстрые проверки, тесты, самопроверка, `check_mutations.py bulk-close-all-scenarios`, `check_code_mutations.py bulk-close-all-scenarios`, `check_ui.py`, `check_i18n.py`.
- [ ] **Step 6: Commit** — `ARCH-15.7: «Массовый сбой» на выборке — только сценарий основного`.

### Task 15.8: Уведомление соседям о ложной тревоге

**Files:**
- Modify: `workflow_schema.v1.json` — эффект `notifySiblings(results: list<string>, key: string)` в реестре: `if form.resultId in results` → `forEach s in siblingsOf(incident).filter(x, !isDone(x))`: `log` в `s` с `key` и подстановками `number` (`incident.number`), `result` (ключ подписи результата), `notify` в `s` для `addressee(s)` — если он не пустой и не `actor`, с `recipients(addressee(s), s)`, `alert: false`, `about: incident`; в `close` — `notifySiblings(['false_alarm'], 'workflow.journal.sibling_closed')`; `strings/*.json` — `workflow.journal.sibling_closed` «{number} того же события закрыт: {result}»
- Modify: `prototype/engine.js` (операция мира `notify` — `about`), `prototype/server.js` (`deliver` — событие `incident.sibling_closed`, если оператор стенда среди получателей), `prototype/app.js` (уведомление «{n} того же события закрыт: {result}»)
- Modify: `openapi.json` — тип потока `incident.sibling_closed`, `StreamSiblingClosedPayload {siblingGuid, siblingNumber, closeResultId}`, строка в таблице потока
- Modify: `States rules IM.md` §6.1 (`close`), §14.10; CHANGELOG; `tests/api-scenarios.js`; `prototype/selftest.js`; `tools/mutations/*`

**Interfaces:**
- Consumes: факт `siblingsOf` из 15.1, `recipients` и `addressee` машины.
- Produces: событие потока `incident.sibling_closed` — `incident` получателя, `payload` — закрытый сосед.

- [ ] **Step 1: Write the failing tests** — «Ложная тревога у соседа: запись в журнал открытых соседей и уведомление их адресату; себе, закрытым и при другом результате — нет (§6.1, ARCH-15)»: `workflowPatch` — уровень 1 эскалации — группа `grp-leads` (в ней оператор стенда), 120 с; взять `INC-1847`, часы вперёд шагами с признаком активности за реакцию `INC-1853` (240 с и окно) → он «Ожидает принятия» у `grp-leads`; закрыть `INC-1847` «Ложной тревогой» → у `INC-1853` последняя запись журнала `workflow.journal.sibling_closed` с `number == "INC-1847"`, в потоке — `incident.sibling_closed` с `incidentGuid == INC-1853`, `payload.siblingNumber == "INC-1847"`. Отрицательные: закрытие «Плановой проверкой» — записи и события нет; сосед уже закрыт — записи нет; оба инцидента мои в работе — запись есть, события потока нет (себе не уведомляется). Шаг самопроверки «Ложная тревога у соседа — уведомление адресату соседа (§6.1, ARCH-15)»: всплывающее «INC-1847 того же события закрыт: Ложная тревога».
- [ ] **Step 2: Run tests to verify they fail** — записи нет.
- [ ] **Step 3: Implement** — по Files; правило §6.1, «Закрыть»: «закрыт ложной тревогой — запись в журнал открытых соседей и уведомление их адресату; соседи не закрываются»; §14.10 — новое событие потока. CHANGELOG.
- [ ] **Step 4: Mutation** — `sibling-notice-any-result`: в `close` — `notifySiblings` со всеми результатами; ловит отрицательный случай «Плановая проверка»; Quint — «мир модели: уведомления модель не меняют».
- [ ] **Step 5: Run tests to verify they pass** — сборка, быстрые проверки, тесты, самопроверка, `check_mutations.py sibling-notice-any-result`, `check_code_mutations.py sibling-notice-any-result`, `check_ui.py`, `check_i18n.py`, `check_guide.py`.
- [ ] **Step 6: Commit** — `ARCH-15.8: уведомление соседям о ложной тревоге`.

### Task 15.9: Звук, открытые вопросы и документы для бэкенда

**Files:**
- Modify: `States rules IM.md` — §8.1 («Уведомление адресату») и §9 (`alerts.target`): один звук на тревогу; §15 — новые вопросы; CHANGELOG
- Modify: `openapi.json` — в таблице `IncidentStreamEvent` правило звука по `eventGuid`
- Modify: `Specification/Workflow_machine/README.md` (CRLF) — «Тестовый стенд»: пять операций, `POST /test/events`, правила в наборе, `eventGuid`, `alarmNumber`, `ruleGuid`, `scenarios.keys`, 28 инцидентов
- Modify: `Specification/Workflow_machine/BACKEND.md` — требования и «Что ещё не решено»

**Interfaces:** нет новых.

- [ ] **Step 1: Write the failing test** — `python3 tools/check_machine.py`: проверка `check_open_questions` — в §15 есть строки со словами «цепочка эскалации по службе» и «дежурной группе правила»; нет — `правила, §15: нет вопроса «…» (ARCH-15)`.
- [ ] **Step 2: Run test to verify it fails.**
- [ ] **Step 3: Implement** —
  - §8.1, §9: «Уведомления и алерты по инцидентам одной тревоги, пришедшие одному человеку за 10 секунд, — один звук; уведомления остаются отдельными. Звука у появления инцидента нет». §17 — звука в прототипе нет (как было).
  - §15, новые строки (кто решает — joynickray; срок — до этапа 3 встраивания, адресация — до второго шага): цепочка эскалации по службе (сценарию); адресация инцидента дежурной группе правила (М1) и «в группе никто не может принять»; доступ по правилу или службе; повторная тревога с новым `event_guid`; координатор тревоги и общий итог; звук на появление инцидента; предупреждение о пересечении правил одного сценария при сохранении правила.
  - `BACKEND.md`: все инциденты события и отметка «обработано» — одна транзакция; `UNIQUE(event_guid, scenario_guid)`; номер тревоги — номер первого созданного инцидента события, хранится на событии, только при созданных инцидентах; у правила нужен `created_at` (сейчас только `updated_at`); у инцидента — `event_guid`, `rule_guid` (вернуть ссылку, убранную миграцией 010); ранжирование — правило §14.5, исполнять определениями `intake` машины; «Массовый сбой» на выборке — по `bulk.scope`, ответ со `skipped`; служебные операции — пять; из «Что ещё не решено» убрать вопросы о приоритете и о ранжировании.
  - README машины — «Тестовый стенд» и «Эталонный набор» по Files.
- [ ] **Step 4: Run tests to verify they pass** — `check_machine.py` и `--mutations`, `check_links.py`, `check_guide.py`.
- [ ] **Step 5: Commit** — `ARCH-15.9: один звук на тревогу, вопросы §15, документы для бэкенда`; вторым — хэши в CHANGELOG.

### После этапа

- [ ] `/im-fsm` — формальная проверка машины после ARCH-15: `close` (эффект `notifySiblings`, `bulk.scope`), предупреждение формы, раздел `intake`; находки — проходом в `reviews/2026-10-28/`.
- [ ] Полные проверки из `CLAUDE.md`: быстрые, самопроверка, тесты API, `tests/scenario.html`, `check_scenarios.py`, `node tools/check_scenario_states.mjs`, `check_i18n.py`, `check_guide.py`, `check_ui.py` (менялись `app.js` и `styles.css`), `quint test`, `quint run --invariant inv`, `python3 tools/check_loopback.py`.
- [ ] Полные мутации кода (`check_code_mutations.py`) — предложить: менялись `server.js`, `engine.js`, `app.js`; по умолчанию их гоняет CI.
- [ ] Итоговый просмотр ветки свежим агентом (superpowers:requesting-code-review).
- [ ] Строка в [reviews/README.md](../README.md): «2026-10-28 — этап 1б (ARCH-15): одно событие — несколько инцидентов».
