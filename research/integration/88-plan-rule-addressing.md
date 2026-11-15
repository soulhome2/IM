# План 88: адресация инцидента дежурной группе из правила (М1)

> **Для агентов-исполнителей:** обязательный навык — superpowers:subagent-driven-development (рекомендуется) или superpowers:executing-plans. Шаги — чекбоксы `- [ ]`. Сервер и конфигуратор — по superpowers:test-driven-development: сначала тест, он падает, потом код.

**Цель:** у правила создания инцидентов есть необязательное поле «Дежурная группа». Если поле задано и в группе есть кому принять, инцидент сразу создаётся «Ожидает принятия» у этой группы. Если принять некому, инцидент создаётся «Новым» в общей очереди, а получатель оповещений получает оповещение. «Почему?» показывает, как был адресован инцидент.

**Архитектура:**
- **Три перехода появления** (`trigger: event`), у каждого одна цель, условия взаимоисключающие:
  - `create` → `new` — у правила нет группы. Переход прежний, к его условиям добавляется одно;
  - `create_to_group` → `pending_acceptance` — группа есть и может принять;
  - `rule_group_cannot_accept` → `new` — группа есть, но принять некому. С оповещением `alerts.target`.

  Id третьего перехода — это и есть имя оповещения: поток шлёт оповещение `incident.alert` с `transitionId`. Сервер и прототип выполняют `intake.create` — список из трёх переходов. Условия должны пройти ровно у одного, иначе ошибка.
- **Группа правила** — новое поле инцидента `ruleDutyGroup`: снимок при приёме, известен до создания, как `scenario`. «Есть кому принять» — существующее определение `canAcceptNow(g, x, '')`: хотя бы один участник вошёл, видит устройство и имеет `incident:accept`. Новое определение `ruleAddressing(x)` возвращает `'none' | 'group' | 'queue'`.
- **Данные intake.** Сервер подаёт в приём факты мира `isGroup`, `members`, `dutyGroups`, `agentState`, `can`, `access`, `isOperator` и имена групп. Это тот же код, что у мира планировщика (`operator.NewSchedulerWorld`), в транзакции приёма. Строки сессий участников группы блокируются `FOR SHARE`.
- **Итог «Почему?»** сохраняется с инцидентом при приёме: `intake_addressing`, группа и её название. Потом он не пересчитывается — как итог окна работ.
- **Удаление группы,** на которую ссылается правило, — `409 DUTY_GROUP_IN_USE` со списком правил в `details.rules`. Внешний ключ — страховка.

**Спецификация:** [88-rule-addressing.md](88-rule-addressing.md). Решения там приняты 2026-11-15, им следовать буквально. Правила — [States rules IM.md](../../Specification/State_rules/States%20rules%20IM.md): §8.1 «Адресация из правила», §3, §5, §6.2, §9, §12.4, §12.5, §14.5. Строится поверх [87a-plan-address.md](87a-plan-address.md): он меняет `IncidentSummary` и `HelpLink*`, миграция 072. IM-уровень М1 начинать **только после коммита IM-уровня адреса** (задачи 1–3 плана 87а). Сервер М1 начинать после миграции 072.

**Где:** IM — `/mnt/hgfs/VmWareShared/soul2home/IM`; сервер — `~/Work/incident-manager-server`; конфигуратор — `~/Work/incident-manager`. Ветка везде `feature/im_operator`.

## Общие ограничения

- Перед началом — `git fetch` в трёх репозиториях; есть новое — `git pull --ff-only`, не выходит — остановиться. Планы 87б и 87в идут параллельно и М1 не трогают (87б, строка 23), но правят `openapi.json`, `CHANGELOG.md`, правила. Перед каждым коммитом — `git fetch`, слить по месту, пересобрать.
- IM: прототип своей логики правил не держит, сгенерированные файлы руками не править (CLAUDE.md). `openapi.json` и `Workflow_machine/README.md` — CRLF: `git diff --stat` не должен показывать файл, переписанный целиком.
- Сервер: в каждом новом запросе `customer_guid = $N`. Тесты — только на `im-test-db` (`sg docker -c "make test-db-up"`, `make test-local`), не на `imdb`. Номер миграции — **073**: перед началом `ls internal/im/service/storing/migrations | tail -3`. Должно быть `072_device_address.sql` последним; занят 073 — взять следующий свободный и поправить план. Postgres стенда — 9.6: новые колонки `incidents` — `NULL` без `DEFAULT`, чтобы не переписывать таблицу.
- Скорость приёма (план 84): у правила без группы ни одного нового запроса. Условия проверяются по очереди, `ruleAddressing` при пустом `ruleDutyGroup` фактов не спрашивает.
- Коммиты — локальные, без push, по-русски, префикс `М1: …`, трейлер `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Фокус ревью — 5 опасных входов

1. **Гонка с выходом последнего участника во время приёма.** Сессии участников читаются под `FOR SHARE` в транзакции приёма. Выход ждёт commit. После этого инцидент у группы ведёт себя так же, как переданный группе вручную (решение исполнителя 5). Взаимной блокировки с `incident_counters` нет: блокировки берутся в порядке «сессии → счётчик». Тест — две транзакции.
2. **Группа другого заказчика.** Правило с `dutyGroupId` чужого заказчика даёт 422. Внешний ключ составной `(customer_guid, duty_group_id)`. Факт `members` берёт людей только своего заказчика. Человек другого заказчика с тем же id группы не считается тем, кто может принять.
3. **Группы нет.** Удаление группы из правила — 409 со списком правил. Гонка «удаление группы ↔ правка правила» снимается блокировкой `LockDutyGroups` в обоих путях, нарушение внешнего ключа (23503) — тоже 409. Если всё же оказалось `isGroup = false`, итог — `queue` с оповещением, а не ошибка приёма.
4. **Несколько правил на одно событие.** Каждый инцидент берёт группу у своего правила-победителя (§14.5). Один инцидент может уйти к группе, а сосед — в очередь. «Почему?» показывает итог по каждому инциденту. Всё одной транзакцией. Номера остаются в конце (план 84).
5. **Окно работ.** В режиме `mark` адресация действует: инцидент с окном и низшим приоритетом всё равно у группы. В режиме `suppress` инцидентов нет, адресации нет, итога адресации нет. Повтор события отвечает прежними инцидентами и ничего не пересчитывает.

## Интерфейсы (общие для всех задач)

**Машина (`workflow_schema.v1.json`):**

| Где | Что |
|---|---|
| `cel.types.Incident` | `ruleDutyGroup: string`. Дежурная группа правила-победителя на момент приёма, `''` — у правила нет группы. Не меняется ни одним эффектом |
| `cel.definitions.ruleAddressing` | `(x: Incident) → string`: `x.ruleDutyGroup == '' ? 'none' : canAcceptNow(x.ruleDutyGroup, x, '') ? 'group' : 'queue'` |
| `registries.guards` | `ruleAddressingIs(expected: string)`: `ruleAddressing(incident) == expected`, `onFail: hide`, `failKeys: [workflow.guard.rule_addressing]`, `extendsBaseRegistry: true` |
| `transitions.create` | `guards: [ruleAddressingIs('none')]`. Эффекты прежние |
| `transitions.create_to_group` (новый) | `from: []`, `to: pending_acceptance`, `trigger: event`, `actor: dispatcher`, `guards: [ruleAddressingIs('group')]`. Эффекты: `setOwner('')`, `setAssignmentGroup(incident.ruleDutyGroup)`, `setFlag(escalationLevel, 0)`, `startTimer(reaction)`, `appendLog(workflow.journal.create_to_group)`, `notify(addressee(incident))` — как у `transfer` |
| `transitions.rule_group_cannot_accept` (новый) | `to: new`, `guards: [ruleAddressingIs('queue')]`. Эффекты те же, что у `create`, плюс `appendLog(workflow.journal.rule_group_cannot_accept)` вместо `workflow.journal.create`, плюс `notify(alerts.target, true)` |
| `intake.create` | строка → список `["create", "create_to_group", "rule_group_cannot_accept"]`. Добавить `$commentAddressing`: какие факты мира даёт сервер и что сессии под `FOR SHARE` |
| подстановки `appendLog` | новая `{ruleGroupName}` — название `incident.ruleDutyGroup`. Описать в README машины, таблица на строке ~237 |
| `uniqueKey` | без изменений: `ruleDutyGroup` в ключ не входит |

**Строки (`strings/ru.json`, `en.json`):**
- `workflow.transition.create_to_group`: «Появился у группы правила» / “Created for the rule duty group”;
- `workflow.transition.rule_group_cannot_accept`: «Группа правила не может принять» / “Rule duty group cannot accept”;
- `workflow.journal.create_to_group`: «Появился — адресован группе {targetName}»;
- `workflow.journal.rule_group_cannot_accept`: «Появился — группа {ruleGroupName} не может принять, поставлен в очередь»;
- `workflow.guard.rule_addressing`;
- `workflow.error.duty_group_in_rules`: «Группа указана в правилах: {rules}. Сначала уберите её из правил».

**Контракт IM (`openapi.json`, CRLF):**

| Схема / запрос | Изменение |
|---|---|
| `IncidentRule` | `dutyGroupId`: строка или `null`, необязательное, id дежурной группы; описание — §8.1 и что делает |
| `DELETE /operator/admin/duty-groups/{id}` | 409 `DUTY_GROUP_IN_USE` — и когда на группу ссылаются правила. `details.rules: [{guid, name}]`, `messageKey` `workflow.error.duty_group_in_rules` |
| `EventExplanation` | `addressing`: массив `EventAddressing`, пусто — ни у одного инцидента нет группы правила |
| `EventAddressing` (новая) | `incident: EventIncidentRef`, `rule: EventRef`, `dutyGroupId: string`, `dutyGroupName: string` (снимок при приёме), `outcome: enum [group, queue]`; `additionalProperties: false` |
| `StreamTransitionIdPayload` | `groupName`: строка, необязательное. Есть только у `incident.alert` перехода `rule_group_cannot_accept` |
| `POST /test/events`, `/test/incidents` | в описание: инцидент может прийти `pending_acceptance` (§8.1, М1) |
| `BackupFile`, раздел `rules` | `dutyGroupId` ссылается на группу файла или базы, иначе 422 |

**База сервера (`073_rule_duty_group.sql`):**
- `incident_rules.duty_group_id TEXT NULL`; `FOREIGN KEY (customer_guid, duty_group_id) REFERENCES duty_groups(customer_guid, id) DEFERRABLE INITIALLY DEFERRED`. Отложенный — потому что резервная копия вставляет `rules` раньше `dutyGroups` (`service/backup/tables.go:91/104`). Индекс `(customer_guid, duty_group_id) WHERE duty_group_id IS NOT NULL`.
- `incidents.rule_duty_group TEXT NULL` (поле машины `ruleDutyGroup`); `incidents.intake_addressing TEXT NULL CHECK (intake_addressing IN ('group','queue'))`; `incidents.intake_duty_group_name TEXT NULL`.
- Down — обратно.

**Модель Go:**
- `model.IncidentRule.DutyGroupID *string`; `IncidentRuleCreateParams.DutyGroupID *string`; `IncidentRuleUpdateParams.DutyGroupID *string` (`nil` — не меняется, `""` — убрать);
- `model.IntakeRule.DutyGroupID string`;
- `model.Incident.RuleDutyGroup string`, `IntakeAddressing string`, `IntakeDutyGroupName string`;
- `model.IntakeAddressing{IncidentGUID, Number, RuleGUID, RuleName, DutyGroupID, DutyGroupName, Outcome}`.

**API конфигуратора сервера (`api/im/backend.openapi.yaml`, `make gen-api-im`):** `incidentRule.dutyGroupId` (nullable), `incidentRuleCreateParams.dutyGroupId`, `incidentRuleUpdateParams.dutyGroupId` (пустая строка — убрать). Неизвестная или чужая группа — 422 по образцу неизвестного `priorityGuid`.

## Задача 1. IM: правила и журнал правил

**Репозиторий:** IM. **Модель:** opus. **Ревью:** полное. **Файлы:** `Specification/State_rules/States rules IM.md`, `CHANGELOG.md`.

- [ ] **§8.1, «Адресация из правила».** Снять «в машине ещё нет». Назвать переходы `create_to_group` и `rule_group_cannot_accept`, определение `ruleAddressing`. Абзац о выходе участников: адресат-группа, где все вышли, ждёт норматива реакции и автоэскалации (§9), как при ручной передаче группе. `addressee_signed_out_to_queue` — только для лично адресованного (решение исполнителя 5).
- [ ] **§3:** на диаграмме `[*] --> pending_acceptance: Появился у группы правила (create_to_group)`; подпись `create` — «Появился (правило без группы или группа не может принять)».
- [ ] **§6.2:** строка `create` — «у правила нет группы». Новые строки `create_to_group` и `rule_group_cannot_accept`: условие, эффекты, журнал, оповещение.
- [ ] **§14.5:** в п. 3 — группа правила-победителя. В п. 4 — каждый инцидент проходит одним из переходов `intake.create`. В п. 6 — при `mark` адресация как обычно. В «Объяснении отбора» — адресация из сохранённого итога, по каждому инциденту.
- [ ] **§12.5:** «Почему?» — строки «Правило «…» → дежурная группа «…»» и «Группа «…» не может принять → общая очередь».
- [ ] **§5:** право на поле — как у правки правил. **§12.4:** изменение поля — запись `incident_rule/update`. **§8.1, удаление группы:** 409 со списком правил.
- [ ] **§17, «Отступления»:** правила в прототипе не правятся — поле задаётся набором, самопроверка задаёт его через `fixturePatch`.
- [ ] **CHANGELOG.md:** строка в «Изменения после v10». Основание — «решение М1 2026-11-15, research/integration/88-rule-addressing.md, план 88». Коммит вписать после коммита.
- [ ] **Проверка:** `python3 tools/check_links.py` — без ошибок.

## Задача 2. IM: машина, строки, контракт, сборка

**Репозиторий:** IM. **Модель:** opus. **Ревью:** полное (машина и контракт). **Зависит от:** задачи 1.

**Файлы:**
- `Specification/Workflow_machine/workflow_schema.v1.json` — по таблице «Машина»; `$comment` у `create` — «единственный» убрать;
- `strings/ru.json`, `en.json`;
- `openapi.json`;
- `README.md` (CRLF) — подстановки и `intake.create`; `CEL.md` и `BACKEND.md` — поле `ruleDutyGroup` и факты intake, если там перечислены поля;
- **`tools/check_machine.py`:** проверка на строке ~616. Каждый id `intake.create` — переход с `trigger: event`, `from: []`. Все переходы `trigger: event` — в списке. У каждого ровно одно условие `ruleAddressingIs`, значения `none`, `group`, `queue` покрыты по одному разу. Ещё переход планировщика (~1296) не берёт `event`;
- **`tools/gen_quint.mjs`, `tools/check_quint_replay.mjs`:** `intake.create` теперь список, `ofTrigger("event")` даёт три перехода.

- [ ] **Сначала тест:** в `tools/check_machine.py` — проверка выше. На нынешней машине она падает: `intake.create` — строка. Затем правка машины, и проверка проходит.
- [ ] `python3 tools/build_workflow.py`, затем все быстрые проверки CLAUDE.md: `--check`, `check_machine.py` и `--mutations`, `test_openapi30.py`, `check_cel.mjs`, `test_cel.mjs`, `cel_vectors.mjs --check`, `gen_quint.mjs --check` (после `node tools/gen_quint.mjs`), `check_links.py`; `check_i18n.py`, `check_guide.py`.
- [ ] **Ожидаемо:** все зелёные, кроме `cel_vectors.mjs --check`, если векторы переходов расходятся из-за новых переходов. Его чинит задача 4.

## Задача 3. IM: прототип, самопроверка, тест API

**Репозиторий:** IM. **Модель:** opus. **Ревью:** полное. **Зависит от:** задачи 2.

**Файлы:**
- `prototype/engine.js:524` — `create(ev)`: переход — первый из `W.intake.create`, у которого `firstFail(ev, tr.guards)` пусто; если проходят не ровно один — `{ok: false, why: ["workflow.error.unknown_action"]}`. Подстановка `ruleGroupName` в `vars()` журнала;
- `prototype/server.js`. `newIncident` (~2380–2422) — `ruleDutyGroup: rule.dutyGroupId || ''`. Результат `engine.create` — не только `ok`: действия мира `notify` выполнить так же, как у других переходов (найти, где сервер прототипа превращает `notify` с `alert` в `emit("incident.alert", …)`). Плюс `groupName` в payload для `rule_group_cannot_accept`. `commitEvent` сохраняет итог адресации у события, по инциденту — для полноты, «Почему?» прототип не отдаёт;
- `prototype/app.js:4762` — тост оповещения: есть `payload.groupName` — «Оповещение: {id} — {what}: «{group}»». Строка в `i18n-*.js`;
- `prototype/selftest.js` — новый шаг;
- `tests/api-scenarios.js` (или соседний `tests/api-*.js`) — случай `POST /test/events` с группой правила. Он же даёт запись векторов `create` для задачи 4.

- [ ] **Сначала тест.** Шаг самопроверки `rule-addressing: адресация из правила`. Через `/test/reset` с `fixturePatch` правило базового типа события получает `dutyGroupId` группы из набора. Проверки:
  - участник группы на месте, с доступом и `incident:accept`: событие даёт `pending_acceptance`, `assignmentGroup` — группа, владельца нет, `escalationLevel` 0, `transferCount` 0, первая запись журнала «Появился — адресован группе …». Инцидент в блоке «Мне на принятие» участника;
  - все участники `offline` (через `fixturePatch` состояний коллег): `new`, оповещение `alerts.target` с названием группы, журнал «группа … не может принять»;
  - участник на перерыве считается: инцидент у группы;
  - у участника нет доступа к устройству: очередь;
  - правило без группы: `new`, журнал прежний.

  Прогнать — шаг падает.
- [ ] Правки, `python3 tools/build_workflow.py`.
- [ ] **Проверки:** selftest (180000) — `data-selftest="pass"`; `tests/api.html` (120000) — `pass`; `tests/scenario.html` (20000); `python3 tools/check_ui.py` (~2 мин); `check_guide.py`, `check_i18n.py`; быстрые проверки. Полные порчи кода — только предложить.

## Задача 4. IM: векторы, мутации машины, Quint; коммиты IM

**Репозиторий:** IM. **Модель:** opus. **Ревью:** полное. **Зависит от:** задачи 3.

**Файлы:**
- `tests/cel-vectors.js` — `ruleAddressing`: `none`; `group` (вошёл, доступ, право); `queue` по каждой из трёх причин — вышел, нет доступа, нет права; перерыв — `group`; не группа — `queue`;
- `tools/mutations/machine.json` — новые порчи:
  - `rule-group-ignored`: `ruleAddressing` всегда `'none'`;
  - `rule-group-signed-out`: `canAcceptNow` → `canAccept`;
  - `rule-group-no-access`: без `access` — замена на `can(m, 'incident:accept')`, найти подстроку по месту;
  - `rule-group-cannot-accept-silent`: убран `notify(alerts.target, true)` у `rule_group_cannot_accept`;
  - `rule-group-level`: у `create_to_group` `escalationLevel` не 0.

  Затем `python3 tools/mutation_table.py`;
- **`quint/src/core.qnt`.** `born` (:89) получает `ruleDutyGroup` (nondet из `""` и групп модели). `create` (:96) берёт переход из `intake.create` с выполненными условиями, а не `ofTrigger("event")[0]`. `createAny` (:389) выбирает группу;
- **`quint/src/invariants.qnt`:** инцидент `pending_acceptance` с `escalationLevel == 0` и `transferCount == 0`, рождённый `create_to_group`, имеет `assignmentGroup == ruleDutyGroup`; `ruleDutyGroup` не меняется после рождения;
- **`quint/im_test.qnt`:** три теста появления — `none`, `group`, `queue`.

- [ ] `node tools/cel_vectors.mjs --update --tmp=<scratchpad>` (~6 мин), затем `--check`; `node tools/scenario_vectors.mjs --check`.
- [ ] `python3 tools/check_mutations.py rule-group-ignored rule-group-signed-out rule-group-no-access rule-group-cannot-accept-silent rule-group-level` — все убиты. Плюс прежние, где менялся текст: `level-signed-out`, `level-group-owner`, `intake-*`.
- [ ] `node tools/gen_quint.mjs`, `quint test im_test.qnt`, `quint run im.qnt --invariant inv` — зелёные (README модели).
- [ ] Все быстрые проверки CLAUDE.md.
- [ ] **Коммиты IM:**
  - «М1: правила, машина и контракт — адресация дежурной группе из правила» (задачи 1–2);
  - «М1: прототип, самопроверка, векторы и Quint» (задачи 3–4);
  - отдельно — хэш в `CHANGELOG.md`.

## Задача 5. Сервер: миграция 073, поле правила, запрет удаления группы

**Репозиторий:** сервер. **Модель:** opus. **Ревью:** полное (миграция, доступ). **Зависит от:** задача 2 (имена); 072 уже в ветке.

**Файлы:**
- `internal/im/service/storing/migrations/073_rule_duty_group.sql`;
- `model/incident_rule.go`, `model/intake.go`, `model/incident.go`;
- `storing/incident_rule_queries.go`: `InsertIncidentRule`:14, `GetAllIncidentRules`:31, `GetIncidentRule`:51, `UpdateIncidentRule`:68 — колонка `duty_group_id`. Новое `RulesUsingDutyGroup(ctx, customer, id) ([]model.RuleRef, error)`, по имени;
- `storing/intake_queries.go:40` `LoadIntakeRules` — `DutyGroupID`;
- `api/im/backend.openapi.yaml` (incidentRule ~2187), `make gen-api-im`; `handler/v1/incident_rule.go`: `convertGeneratedToIncidentRule`:36, `convertIncidentRuleToGenerated`:75, Update:92;
- `appservice/incidentrule/incident_rule.go`: Create:62 и Update:136 — в транзакции `Store.LockDutyGroups` (`reference_queries.go:462`), затем проверка группы `customer_guid = $1 AND id = $2`. Иначе 422. Журнал — прежний `writeAudit`:168: `before`/`after` с `dutyGroupId`. Копия правила передаёт группу;
- `handler/operator/duty_groups.go:177` `DeleteDutyGroup`: после `machineNamesGroup` — `RulesUsingDutyGroup`. Непусто — 409 `DUTY_GROUP_IN_USE`, `details.rules`, ключ `workflow.error.duty_group_in_rules`, `{rules}` — названия через запятую. Ошибка 23503 при commit — тоже 409;
- **`service/backup/`:** проверка `dutyGroupId` правил при применении — группа есть в файле или в базе, иначе 422 по образцу соседних проверок ссылок. Версия формата — 1;
- `service/reset/steps.go` — порядок `incident_rules` раньше `duty_groups` уже верный, проверить тестом.

- [ ] **Сначала тесты** (`handler/test/`, PostgreSQL):
  - `incident_rule_duty_group_test.go`:
    - `TestRuleDutyGroupSetClear` — PUT с группой, ответ и GET с `dutyGroupId`; `""` — `null`; поля нет — не меняется;
    - `TestRuleDutyGroupForeign` — группа другого заказчика и несуществующая — 422;
    - `TestRuleDutyGroupAudit` — запись `incident_rule/update`, before/after `dutyGroupId`;
    - `TestRuleDutyGroupRights` — без права правки правил — 403;
  - `operator_duty_groups_admin_test.go`:
    - `TestDeleteDutyGroupUsedByRules` — 409, `details.rules` с двумя правилами, группа на месте; после очистки правил — 204;
    - `TestDeleteDutyGroupRuleRace` — параллельно удаление и правка правила: одно из двух 409/422, в базе нет правила на удалённую группу;
  - `backup_test.go`: `TestRestoreRuleWithDutyGroup` — файл с группой и правилом восстанавливается; правило с неизвестной группой — 422;
  - сброс заказчика с правилом на группу проходит.
- [ ] **Проверка:** `make test-local` — зелёное, `go vet ./...`, `make check-no-stand`.

## Задача 6. Сервер: приём события — адресация в транзакции

**Репозиторий:** сервер. **Модель:** opus. **Ревью:** полное, с мутациями: это приём событий и доступ. **Зависит от:** задачи 4 (машина и векторы вендорятся) и 5.

**Файлы:**
- `make vendor-operator-contract && make gen-api-operator`; в `api/im/operator/SOURCE` — хэш коммита IM задачи 4. `vectors_test.go` прогоняет новые векторы на Go;
- **`service/transition/create.go`.** `createTransition` (:15) → список из `Machine().Intake…` (`intake.create`). `Create`/`createOne` проверяют условия каждого перехода так же, как `Run` для системных: проходит ровно один, иначе ошибка. Убрать «единственный» из комментариев;
- `service/transition/row.go:57`, `row_from.go:77/123` — `ruleDutyGroup` ↔ `RuleDutyGroup`, неизменяемое поле;
- `service/transition/journal.go:247` `logVars` — `ruleGroupName`: имя группы через `ActorName` мира;
- **`service/intake/world.go`.** `intakeRest.Fact` (:37) и `ActorName` (:41): неизвестный факт берётся у мира людей. Новое поле `Service.People func(ctx model.AppContext, customer uuid.UUID, now int64) transition.World` — в `appservice.go` после `initOperatorDeps` (~:405): `opapp.NewSchedulerWorld(ctx, deps.Store, deps.Tree, deps.Directory, customer, now, WithAccessCache(…))`, тот же кэш доступа, что у планировщика. `People == nil` — прежнее поведение: факт — ошибка;
- **`service/intake/service.go`:**
  - в `create` (:426) — `mi.Incident.RuleDutyGroup = p.rule.DutyGroupID`;
  - перед `core.Create` — если у плана есть группы: `Store.LockGroupSessions(ctx, customer, groupIDs)`, `SELECT … FROM operator_sessions … FOR SHARE` по участникам групп;
  - проверка `rows[k].State != model.StateNew` (:494) → допустимы `new` и `pending_acceptance`; статус берётся по состоянию;
  - `To: model.StateNew` (:539) → состояние строки;
  - ограничение «нет After/External» (:483) ослабить: допустим только `notify`. Оповещения (`Alert`) пишутся строками потока `stream.TypeAlert` в той же транзакции, рядом с `feedCreated`, по образцу `notifyRows` (`appservice/operator/feed.go:261`), payload `{transitionId, groupName}`;
  - итог: `IntakeAddressing` = `group | queue` по сработавшему переходу, `IntakeDutyGroupName` — имя на момент приёма;
- `storing/incident_queries.go:13` `InsertIncident` — три новые колонки;
- `model/operator_action.go:38` — новые переходы не трогать: по умолчанию `auto`. Проверить тестом;
- `internal/im/stand/intake.go` и `CreateOne` (:370) — тот же путь, отдельно ничего.

- [ ] **Сначала тесты:**
  - `service/transition/create_test.go`: `TestCreatePicksByRuleAddressing` (`none`/`group`/`queue` на заглушке мира); `TestCreateTwoPassIsError`;
  - `handler/test/intake_rule_group_test.go`:
    - `TestIntakeToGroupSignedIn` — участник `ready`, доступ, право: `pending_acceptance`, `assignment_group`, `owner` пусто, уровень 0, передач 0, `reaction` от `created_at`, журнал `create_to_group`, строка потока `incident.created`;
    - `TestIntakeToGroupOnBreak` — перерыв считается;
    - `TestIntakeGroupAllOffline` — `new`, оповещение `incident.alert` с `rule_group_cannot_accept` и `groupName` получателю `alerts.target`, журнал `rule_group_cannot_accept`;
    - `TestIntakeGroupNoAccess` — участник не видит устройство: очередь;
    - `TestIntakeGroupNoAcceptRight` — нет `incident:accept`: очередь;
    - `TestIntakeGroupOtherCustomer` — человек другого заказчика в группе с тем же id не считается;
    - `TestIntakeTwoRulesTwoGroups` — два сценария, два правила: один у группы, другой в очереди, номера подряд;
    - `TestIntakeMarkWindowAddressed` — окно `mark`: у группы, с окном и низшим приоритетом;
    - `TestIntakeSuppressNoAddressing`;
    - `TestIntakeRepeatEventKeeps` — повтор отвечает прежними;
    - `TestIntakeLastSignOutRace` — транзакция приёма держит `FOR SHARE`, выход ждёт commit, без взаимной блокировки (`lock_timeout`);
    - `TestIntakeNoGroupNoExtraQueries` — у правила без группы нет запросов к сессиям (счётчик запросов заглушки).
- [ ] **Мутации на ревью** (вручную, каждая должна уронить тест): убрать `FOR SHARE`; `canAcceptNow` → `canAccept` в вендоренной машине; убрать `customer_guid` в чтении участников; принять `pending_acceptance` без группы; потерять `notify` оповещения.
- [ ] **Проверка:** `make test-local`, `make test-stand` (`go test -tags imtest ./internal/im/stand/...`), `make check-no-stand`.

## Задача 7. Сервер: «Почему?» и прочее

**Репозиторий:** сервер. **Модель:** opus. **Ревью:** полное (контракт). **Зависит от:** задачи 6.

**Файлы:**
- `storing/maintenance_queries.go:242` (рядом) — `EventAddressing(ctx, customer, event) ([]model.IntakeAddressing, error)`: инциденты события с `intake_addressing IS NOT NULL`, по номеру, `customer_guid`;
- `handler/operator/events.go:204–209` — `withAddressing(x, kept)` по образцу `withMaintenance`:215 → `EventExplanation.Addressing`. Название группы — снимок, правило — по `rule_guid` с текущим названием (`EventRef`);
- `appservice/operator/feed.go` — тип payload оповещения с `GroupName,omitempty` для обычных переходов не меняется.

- [ ] **Сначала тесты:** `event_explain_test.go`:
  - `TestExplainAddressingGroup` и `TestExplainAddressingQueue`;
  - `TestExplainAddressingKeptAfterRename` — группу переименовали, правило очистили: итог прежний;
  - `TestExplainNoAddressing` — пустой список;
  - чужое событие — 404, как было.
- [ ] **Проверка:** `make test-local` — зелёное. Коммиты сервера — в задаче 9.

## Задача 8. Конфигуратор

**Репозиторий:** конфигуратор. **Модель:** sonnet. **Ревью:** короткое. **Зависит от:** задачи 2 (контракт). Сервер не нужен: Vitest на заглушках. **Идёт параллельно с задачами 5–7.**

**Файлы:**
- `src/operator/testing/openapi.json` и `workflow_schema.v1.json` — копии из IM через `tr -d '\r'`, хэш — в `tests/operator-fake-contract.test.ts`;
- `src/features/incident-rules/api/imBackendIncidentRules.dto.ts` (:80, :118) — `dutyGroupId: z.string().nullish()`; create и update;
- `api/useAutoSaveRuleForm.ts:134`, `lib/hydrateRuleForm.ts:52`, `api/page/useRuleCreateDialog.ts` (копия передаёт группу);
- `components/RuleEditorForm.tsx` (~:138, рядом с приоритетом) — выбор «Дежурная группа» из `useDutyGroups` (`features/duty-groups/api/useDutyGroups.ts`). Первый пункт — «Не задана — общая очередь», по умолчанию он. Подсказка: «Инцидент сразу ждёт принятия у группы; если в ней некому принять — общая очередь и оповещение»;
- `components/IncidentRulesTable.tsx:108–113` — столбец `sortHeader('dutyGroup', …)` после приоритета. `components/RuleRow.tsx` — название группы или «—»;
- `lib/sortRules.ts` — ключ `'dutyGroup'`, по названию группы через `label`. Пустое — `''`, как у `updatedBy`;
- `src/features/duty-groups/lib/dutyGroupForm.ts:81` и `DutyGroupsPage.tsx`: при 409 с `details.rules` — «Группа указана в правилах: …» со списком названий; без `details.rules` — прежний текст;
- `src/features/events/api/eventsApi.ts:104–115` — `addressing`; `components/WhyDialog.tsx` — блок «Адресация»: по инциденту «Правило «…» → дежурная группа «…»» или «Группа «…» не может принять → общая очередь»;
- `src/operator/shell/useServerEvents.ts:114` — `noticeAlert` с `groupName`, если есть; `src/operator/api/contract.ts` — поле payload;
- `src/features/audit/components/DiffView.tsx:57` — подпись поля `dutyGroupId` у `incident_rule`;
- локали `incidentRules`, `dutyGroups`, `events`, `operator`, `audit`: ru и en, остальные — английским текстом, как принято.

- [ ] **Сначала тесты:**
  - `RuleEditorForm` или `useAutoSaveRuleForm.test.ts`: «duty group select saves dutyGroupId», «empty option clears with empty string»;
  - `RulesSort.test.tsx`: «sorts by duty group name»;
  - `DutyGroupsPage.test.tsx`: «409 with rules lists the rules»;
  - `WhyDialog.test.tsx`: «shows addressing group and queue»;
  - `useServerEvents` — «alert with group name»;
  - разбор DTO без поля — `null`.
- [ ] **Проверка:** `npm run test:run`, `npm run lint`, `npm run build:ts` — зелёные; `tests/operator-locale-keys.test.ts`.

## Задача 9. Стенд и коммиты

**Модель:** sonnet. **Ревью:** короткое. **Зависит от:** задачи 7 и 8.

- [ ] Блокировка `~/Work/stand/lock-server` по правилам стенда.
- [ ] Дамп: `pg_dump -U im imdb > ~/Work/stand/backup/imdb-before-rule-group-2026-11-16.sql`.
- [ ] **Сервер:** бинарник без `imtest` в `~/Work/stand/bin/`, перезапуск юнитом `im-stand-server`. В логе — 073 применена.
- [ ] **Конфигуратор:** `npm run build && rsync -a --delete dist/ ~/Work/stand/im-dist/`.
- [ ] **Глазами на стенде:**
  - правилу «Пожар» задать группу, в ней вошедший оператор: событие эмулятора — инцидент сразу в «Мне на принятие» у оператора и в счётчике группы;
  - все вышли — инцидент «Новый», у получателя оповещений тост с названием группы;
  - «Почему?» в журнале событий показывает обе строки;
  - удаление группы — отказ со списком правил;
  - журнал настроек — запись правки правила;
  - столбец и сортировка в списке правил.
- [ ] `~/Work/stand/check-operator-api.sh`, `check-operator-filter.sh` — не хуже, чем до задачи. Снять блокировку.
- [ ] **Коммиты, локально, без push:**
  - сервер: «М1: миграция 073 — дежурная группа у правила, запрет удаления группы»; «М1: приём события — адресация группе правила в транзакции»; «М1: «Почему?» — итог адресации»;
  - конфигуратор: «М1: поле «Дежурная группа» в правиле, столбец, отказ удаления, «Почему?»».

**Параллельность:** 1 → 2 → 3 → 4 по порядку. После 2: сервер (5 → 6 → 7; 6 ждёт коммита задачи 4) и конфигуратор (8) параллельно. 9 — последней.

## Решения исполнителя (ночь 2026-11-15)

Пользователь спал. Выбран самый осторожный вариант, совместимый с правилами:

1. **Три перехода появления вместо условной цели `create`.** В схеме у перехода одна цель `to`, условной цели нет. Добавить её значило бы переделать проверки, Quint и оба исполнителя. Три перехода с взаимоисключающими условиями — тот же приём, что у пары `addressee_signed_out_to_group` и `addressee_signed_out_to_queue`. «Без новых переходов» в решении относится к жизни инцидента после появления: там ничего нового нет.
2. **Оповещение `rule_group_cannot_accept`** — это id перехода: поток уже определяет оповещения по `transitionId`. Название группы — новым необязательным полем `groupName` в `StreamTransitionIdPayload`. Без него «с названием группы» не выполнить.
3. **Группа — поле инцидента `ruleDutyGroup`,** снимок правила при приёме. В тип `Rule` машины она не добавляется: определениям отбора она не нужна.
4. **«Есть кому принять»** = существующее `canAcceptNow(g, x, '')`: вошёл (перерыв считается), доступ, право. Вторую копию условия не писали.
5. **Вышел последний из группы.** В решении сказано «в очередь (`addressee_signed_out_to_queue`)». Но в машине этот переход только для лично адресованного (условие `ownerHasDutyGroup(false)`, `scope: incidents_owned_by_agent`). У адресата-группы, где все вышли, перехода в очередь нет: инцидент ждёт норматива реакции и уходит автоэскалацией (§9, §8.3), как при ручной передаче группе. По решению «без новых переходов» оставлено так и записано в §8.1. **Пользователю — проверить:** если нужно «в очередь сразу», это новый системный переход, отдельная задача.
6. **Гонка входа и выхода** снимается `FOR SHARE` на сессиях участников в транзакции приёма. Порядок блокировок — сессии, потом счётчик номеров.
7. **Итог адресации — в колонках `incidents`,** а не события: у одного события несколько инцидентов с разными группами. Колонки `NULL` без `DEFAULT` — Postgres 9.6 стенда не переписывает таблицу.
8. **409 — прежний код `DUTY_GROUP_IN_USE`** с `details.rules` и новым `messageKey`. Конфигуратор этот код уже разбирает, новый код сломал бы старых клиентов.
9. **Внешний ключ — составной и отложенный:** резервная копия вставляет правила раньше групп. Основная защита — проверка под `LockDutyGroups`.
10. **Правка поля:** нет поля — не меняется, `""` — убрать. Так нет неоднозначности `null` в генераторе Go.
11. **«Почему?»** показывает только итог при приёме. «Что было бы сейчас» адресацию не считает: присутствие людей — не настройка, пересчёт ничего бы не объяснил.
12. **Уведомление и звук** у группы-адресата делает план 87б по `incident.created` (`ownership: target`). М1 `observerNotice` не добавляет.
13. **Прототип:** `demo.json` не меняется. Самопроверка задаёт группу правилу через `fixturePatch`, иначе сдвинулись бы прежние шаги и векторы.
14. **Резервная копия:** правило с группой, которой нет ни в файле, ни в базе, — 422. Молча обнулять поле не стали.
