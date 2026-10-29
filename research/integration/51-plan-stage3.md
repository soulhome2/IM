# Этап 3: данные инцидента и «событие → инцидент» — план работ

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Сервер МИ превращает событие агента в инциденты по §14.5: инцидент на каждый сценарий подошедших правил, победитель — по ранжированию машины, номер INC-NNNN, номер тревоги, всё одной транзакцией; повтор события ничего не создаёт и не даёт 500.

**Architecture:** `POST /events` обрабатывает событие синхронно, в одной транзакции: запись события (`ON CONFLICT DO NOTHING` — повтор), выбор правил, номера из счётчика, инциденты (переход `create`: состояние `new`, версия 1, запись журнала), отметка «обработано» и номер тревоги. Ранжирование — чистый пакет `ruleselect`, точное зеркало определений машины (`conditionMatches` … `ruleFor`, `ruleOrder: guid`); его заменит исполнитель CEL этапа 4. Фоновый обработчик событий и кэш условий убираются.

**Tech Stack:** Go 1.27.1, gin 1.11, `gopkg.in/mgutz/dat.v1`, `sql-migrate`, PostgreSQL 9.6 (Docker), testify `require`, golangci-lint v2.14.0.

**Spec:** [40-plan.md, «3. Данные инцидента и «событие → инцидент»»](40-plan.md#3-данные-инцидента-и-событие--инцидент--сервер-ми-l) и таблица «Решения» там же (№ 5, 5б, 9, 10); требования — [BACKEND.md](../../Specification/Workflow_machine/BACKEND.md) («Одно событие — по инциденту на сценарий», «Арендатор», «Время события», «Тестовый стенд», п. 4); правила — [§14.5](../../Specification/State_rules/States%20rules%20IM.md#145-связь-со-сценарием-обработки); образец — `intakeEvent` / `newIncident` / `createIncident` в [prototype/server.js](../../prototype/server.js) и `intake()` в [prototype/engine.js](../../prototype/engine.js); тесты поведения — раздел «Одно событие — несколько инцидентов» в [tests/api-scenarios.js](../../tests/api-scenarios.js). Факты о сервере на `2db9f2f` — сверены 2026-10-29 (обзор этапа 3).

## Global Constraints

- Код — `~/Work/incident-manager-server`, ветка `feature/im_operator`, от `2db9f2f`. Пути ниже — от корня этого репозитория, если не сказано иное. Документы — репозиторий IM, ветка `feature/im_operator`.
- Только локально, на стенде из [30](30-local-stand.md). Push — только по просьбе пользователя. `~/Work/axxoncloudgo` не менять; если кажется, что нужна правка облака, — **стоп, спросить пользователя**.
- Вход отложен: тестовый пользователь `test@axxonnet.test`. Обработку токена (`internal/externalclient/cloud/client.go`, introspect, мемоизация) не менять.
- Тот же процесс `cmd/im`, тот же `gin.Engine`, `BasePath` = `/api/v1/im-backend`.
- `make gen` и `make gen-api-im` не запускать (сгенерированный `v1` отстал от `backend.openapi.yaml`). Значит, ответы API настройки не меняются: новых полей в `GET /incidents`, `GET /incidents/rules` нет. Копию контракта и машины (`api/im/operator/`, `SOURCE` = `afd30ea`) в этапе не обновлять.
- Перед любой командой `go` — `source ~/go/offline-env.sh`. Адрес `npm.itvgroup.ru` недоступен, не использовать. Docker — только через `sg docker -c "…"`.
- Тесты с базой — только контейнер `im-test-db` (`127.0.0.1:55432`): `make test-local` или `IM_TEST_DB_URL='postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable' go test …`. База стенда `imdb` — не для тестов.
- Тесты — testify `require`. Номера инцидентов в тестах с базой — относительные (база общая для всех тестов пакета): «следующий», «на 1 больше», не «INC-0001».
- Ошибки `POST /events` и прочих старых маршрутов — по-прежнему `{key, description}`, `application/json`.
- `golangci-lint run ./...` — 0 замечаний в каждой задаче (`funlen` 120 строк / 60 операторов, `dupl` 150, `gosec`, `errorlint`).
- Комментарии в коде и ADR — по-английски; документы IM — по-русски, простыми словами.
- Коммит — один на задачу, сообщение по-русски. Сообщение пишется инструментом записи файла в `.git/COMMIT_MSG_STAGE3` (без heredoc), последняя строка — `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`; затем `git commit -q -F .git/COMMIT_MSG_STAGE3`. Команды Bash — в одну строку.

**Решения пользователя (обязательны):**

- Каждое подошедшее правило со сценарием даёт свой инцидент; ключ уникальности — `(event_guid, scenario_guid)`; два правила одного сценария — один инцидент, победитель по ранжированию.
- Приоритет инцидента — от правила-победителя (`priority_guid` правила).
- Номер тревоги — номер первого созданного инцидента события; хранится у события (`events.alarm_number`). Событие без инцидентов номера тревоги не получает.
- Арендатор = установка: `customer_guid` — из настройки сервера `IM_CUSTOMER_GUID`, а не из `fakedata`.
- RULE-137 — как есть: не создаётся инцидент хоть одного подошедшего правила — не создаётся ничего; ни алерта, ни записи в журнал. Событие не записывается, повтор снова обрабатывается.

**Решения этого плана (обязательны для задач):**

- **Обработка — синхронно в `POST /events`, одной транзакцией** (обоснование — в конце, «Решения этого плана»). Порядок событий — порядок прихода («старое раньше»): агент шлёт по времени, номера раздаются в порядке фиксации счётчика. Ответ: новое событие и повтор — `200` (в контракте `POST /events` только 200/401/500); правило со сценарием без версии (RULE-137) — `422` `error.event.intake.failed`, ничего не записано; сбой базы — `500`, ничего не записано. Паника внутри обработки перехватывается и становится ошибкой `500`, транзакция откатывается.
- **Ранжирование — зеркало машины на Go**, пакет `internal/im/ruleselect`, с пометкой `STAGE4: replace with the CEL executor`. Сравнение типа события — по `id` типа (`source_event_types.uid`), не по guid (BACKEND.md). Тест сверяет хэш раздела `intake` машины и нужных определений: машина поменялась — тест падает. Ключ уникальности — не в коде, а из `intake.uniqueKey` копии машины (PROC-93; BACKEND.md в рабочей копии IM от 2026-10-29): `["eventGuid","scenario"]` — инцидент на сценарий, `["eventGuid"]` — один, первый по порядку создания; другое значение — сервер не стартует. Индекс `(event_guid, scenario_guid)` верен при обоих.
- **Состояние и статус:** истина — новый столбец `incidents.state` (состояния машины). `status_guid` остаётся для конфигуратора и выводится из состояния фиксированной таблицей `model.StatusCodeForState`: `new`, `pending_acceptance` → `open`; `in_progress`, `on_hold` → `in_progress`; `closed`, `linked` → `closed`. Пишутся вместе, одним кодом; в этапе 3 — только `new` + `open`. Старые маршруты статус инцидента не меняют (только `GET` и `DELETE`).
- **Уникальность и мягкое удаление:** частичный индекс `UNIQUE (event_guid, scenario_guid) WHERE deleted_at IS NULL`. Главная защита от повтора — первичный ключ `events.guid`: событие, которое уже есть, до выбора правил не доходит, поэтому снятый (мягко удалённый) инцидент заново не появится. Индекс — вторая линия; частичный — чтобы миграция могла снять дубли, уже лежащие в базе стенда (1 пара на 2026-10-29), мягким удалением, без потери строк.
- **Номер** — `incidents.number BIGINT`, вид `INC-%04d` (`model.FormatIncidentNumber`), сквозной на арендатора: счётчик-таблица `incident_counters` (`UPDATE … RETURNING` в той же транзакции — без дыр: откат события номера не тратит).
- **Схема в этапе 3 — только то, что пишет создание:** номер, версия, состояние, `rule_guid`, ключ уникальности, журнал (запись `create`), у события — номер тревоги и `occurred_at`, у правила — `created_at`, у сценария правила — `position`. Владелец, адресат, уровень эскалации — этап 4 (их значения при `create` — пусто и 0, столбцы с такими умолчаниями добавятся без потери данных). Норматив реакции (`startTimer reaction`) — этап 6: его срок зависит от уточнений по типу события, приоритету, группе и сценарию — это не «дёшево», это часть планировщика.

## Review Focus

1. **Агент повторил событие, не дождавшись ответа, — два одинаковых запроса одновременно.** Ждём: оба `200`, инциденты созданы один раз, не `500`. Тест — задача 6, `TestEventRepeatConcurrent`.
2. **Сценарий, на который ссылается правило, удалили в конфигураторе** (`DELETE /scenarios/{guid}` архивирует все версии; запрета нет). По RULE-137 каждое событие под это правило — `422`, не создаётся ничего, в том числе инциденты других правил; другие события — как обычно. Сейчас сервер такой сценарий молча пропускает — поведение меняется. Тест — задача 6, `TestEventAllOrNothing`.
3. **Правило или условие поменяли, удалили или добавили между событиями.** Ждём: следующее событие видит правила как есть, без паники и без старого кэша (сейчас удалённое правило в кэше даёт `nil` и панику). Тесты — задача 6, `TestEventAfterRuleDeletedNoPanic`, `TestEventSeesNewRuleImmediately`.
4. **Миграция на базе, где уже есть дубли и мягко удалённые инциденты** (база стенда). Ждём: миграция проходит, на пару «событие + сценарий» — один живой инцидент, номера есть у всех строк, счётчик продолжает после наибольшего. Проверка — задача 1, шаг «Миграция на копии базы стенда».
5. **`occurredAt` в теле события нет, или он кривой** (агенты разные). Ждём: событие принято, `occurred_at` = время приёма, не `400`. Тесты — задача 6, `TestOccurredAtFromPayload` и `TestEventOccurredAtFromPayload`.

---

## Структура файлов

| Файл | Что | Задача |
|---|---|---|
| `internal/im/service/storing/migrations/014_incident_intake.sql` | столбцы, индексы, счётчик, журнал, заполнение старых строк | 1 |
| `internal/im/model/{incident.go, event.go, incident_rule.go, journal.go, incident_state.go}` (+ тест) | новые поля, `JournalEntry`, `StateNew`, `StatusCodeForState`, `FormatIncidentNumber` | 1 |
| `internal/im/model/dbmodel/*`, `internal/im/service/storing/{event,incident,journal,incident_counter}_*.go` | DTO, конвертеры, запросы | 1 |
| `internal/im/model/config.go`, `internal/im/appservice/appservice.go`, `internal/im/handler/v1/{common.go, auth_middleware.go}`, `internal/im/appservice/agent/agent.go` | `IM_CUSTOMER_GUID` | 2 |
| `internal/im/service/storing/{incident_rule_scenarios_queries.go, incident_rule_scenarios_converters.go, intake_queries.go, source_group_membership_queries.go}`, `internal/im/model/intake.go` | порядок сценариев, правила для выбора, группы источника | 3 |
| `internal/im/ruleselect/{ruleselect.go, ruleselect_test.go, pin_test.go}` | зеркало определений машины | 4 |
| `internal/im/service/intake/{service.go, world.go, store.go, service_test.go}` | событие → инциденты в транзакции вызывающего | 5 |
| `internal/im/appservice/event/{event.go, event_test.go}`, `internal/im/handler/v1/event.go`, `internal/util/apierror/{common.go, keys.go}` | синхронный `POST /events`, 422 | 6 |
| `internal/im/appservice/incidentrulecondition/{processor.go, incident_rule_condition.go}`, `internal/im/appservice/sourcegroup/bl/service.go` | убрать фоновый обработчик и кэш | 6 |
| `internal/im/handler/test/{intake_store_test.go, intake_rules_test.go, intake_test.go, tenancy_test.go, permission_test.go}` | тесты с базой; без `time.Sleep(1s)` | 1, 2, 3, 6 |
| `tools/agent-emulator/{main.go, replay.go, democonfig.go, replay_test.go}` | повтор набора по событиям, загрузка правил демо | 7 |
| `docs/adr/003-event-intake.md` | решения этапа | 8 |
| `~/Work/stand/{load-demo.sh, check-demo-intake.sh}` | стенд, вне репозиториев | 8 |
| IM: `research/integration/30-local-stand.md`, `40-plan.md` | шаг 5 стенда, отметка этапа | 8 |

---

### Task 1: Миграция 014 и хранение новых полей

**Files:**
- Create: `internal/im/service/storing/migrations/014_incident_intake.sql`
- Create: `internal/im/model/journal.go`, `internal/im/model/incident_state.go`, `internal/im/model/incident_state_test.go`
- Modify: `internal/im/model/{incident.go, event.go, incident_rule.go}`, `internal/im/model/dbmodel/*` (DTO инцидента, события, правила, сценария правила), конвертеры в `internal/im/service/storing/`
- Modify: `internal/im/service/storing/{event_queries.go, incident_queries.go}`
- Create: `internal/im/service/storing/{journal_queries.go, incident_counter_queries.go}`
- Test: `internal/im/handler/test/intake_store_test.go`

**Interfaces:**
- Produces:
  - `model.Incident` + `Number int64`, `Version int64`, `State string`, `RuleGUID *uuid.UUID`;
  - `model.Event` + `AlarmNumber *int64`, `OccurredAt time.Time`; `model.IncidentRule` + `CreatedAt time.Time`;
  - `type JournalEntry struct { GUID, IncidentGUID, CustomerGUID uuid.UUID; At time.Time; Actor, Transition, TemplateKey string; Vars json.RawMessage }`;
  - `const StateNew = "new"`, `const ActorDispatcher = "dispatcher"`, `const TransitionCreate = "create"`, `const JournalCreate = "workflow.journal.create"`;
  - `func StatusCodeForState(state string) string` (таблица — Global Constraints; незнакомое → `""`); `func FormatIncidentNumber(n int64) string`;
  - `func (s *Store) InsertEventIfNew(ctx model.AppContext, e *model.Event) (bool, error)` — `INSERT … ON CONFLICT (guid) DO NOTHING RETURNING guid`; нет строки → `false, nil`;
  - `func (s *Store) GetEvent(ctx model.AppContext, guid uuid.UUID) (*model.Event, error)`;
  - `func (s *Store) MarkEventProcessed(ctx model.AppContext, guid uuid.UUID, alarmNumber *int64) error` — `processed = TRUE`, `alarm_number = $2`;
  - `func (s *Store) ReserveIncidentNumbers(ctx model.AppContext, customerGUID uuid.UUID, n int64) (first int64, err error)` — `INSERT INTO incident_counters VALUES ($1, $2) ON CONFLICT (customer_guid) DO UPDATE SET last_number = incident_counters.last_number + EXCLUDED.last_number RETURNING last_number`, `first = last − n + 1`;
  - `func (s *Store) InsertJournalEntries(ctx model.AppContext, entries []*model.JournalEntry) error`, `func (s *Store) GetJournalEntries(ctx model.AppContext, incidentGUID uuid.UUID) ([]*model.JournalEntry, error)` (по `at`);
  - `func (s *Store) GetIncidentsByEvent(ctx model.AppContext, eventGUID uuid.UUID) ([]*model.Incident, error)` — живые, по `number`;
  - `InsertIncident` пишет новые поля.

Миграция (столбцы — списком; `-- +migrate Up` / `Down`, как 009):

| Порядок | Что |
|---|---|
| 1 | Снять живые дубли: `ROW_NUMBER() OVER (PARTITION BY event_guid, scenario_guid ORDER BY created_at, guid)` > 1 → `deleted_at = NOW()` |
| 2 | `incidents`: `number BIGINT` (заполнить `ROW_NUMBER() OVER (PARTITION BY customer_guid ORDER BY created_at, guid)` по всем строкам, затем `NOT NULL`, `UNIQUE (customer_guid, number)`); `version BIGINT NOT NULL DEFAULT 1`; `state TEXT` (из `statuses.code`: `open`→`new`, `in_progress`→`in_progress`, `closed`→`closed`, прочее → `new`; затем `NOT NULL`, без `CHECK` — состояния задаёт машина); `rule_guid UUID REFERENCES incident_rules ON DELETE SET NULL` (старым — `NULL`; контракт: «правила уже нет — null») |
| 3 | `CREATE UNIQUE INDEX uq_incidents_event_scenario ON incidents (event_guid, scenario_guid) WHERE deleted_at IS NULL` |
| 4 | `incident_counters (customer_guid UUID PRIMARY KEY REFERENCES customers, last_number BIGINT NOT NULL)`; заполнить `MAX(number)` по арендатору |
| 5 | `events`: `alarm_number BIGINT` (старым — `MIN(number)` живых инцидентов события); `occurred_at TIMESTAMPTZ` (старым — `created_at`, затем `NOT NULL`) |
| 6 | `incident_rules.created_at TIMESTAMPTZ`: из UUID v7 (`substr(guid::text,15,1) = '7'` → `to_timestamp(('x' \|\| substr(replace(guid::text,'-',''),1,12))::bit(48)::bigint / 1000.0)`, проверено на PG 9.6), иначе `updated_at`; затем `NOT NULL DEFAULT NOW()` |
| 7 | `incident_rule_scenarios.position INT`: нынешний порядок API — `ROW_NUMBER() OVER (PARTITION BY rule_guid ORDER BY sa.name NULLS LAST, irs.guid) − 1` (`sa` — `scenarios_actual`, `LEFT JOIN`); затем `NOT NULL`. Без `UNIQUE (rule_guid, position)` |
| 8 | `incident_journal (guid UUID PK, incident_guid UUID NOT NULL REFERENCES incidents ON DELETE CASCADE, customer_guid UUID NOT NULL REFERENCES customers, at TIMESTAMPTZ NOT NULL, actor TEXT NOT NULL, transition TEXT, template_key TEXT NOT NULL, vars JSONB)`, индекс `(incident_guid, at)` |
| Down | обратно в обратном порядке; снятые дубли `Down` не возвращает — сказать в комментарии |

- [ ] **Step 1: Тесты модели**

```go
func TestStatusCodeForState(t *testing.T) {
	for state, code := range map[string]string{"new": "open", "pending_acceptance": "open", "in_progress": "in_progress",
		"on_hold": "in_progress", "closed": "closed", "linked": "closed", "nope": ""} {
		require.Equal(t, code, StatusCodeForState(state), state)
	}
}

func TestFormatIncidentNumber(t *testing.T) {
	require.Equal(t, "INC-0001", FormatIncidentNumber(1))
	require.Equal(t, "INC-1847", FormatIncidentNumber(1847))
	require.Equal(t, "INC-12345", FormatIncidentNumber(12345))
}
```

- [ ] **Step 2: Тесты хранения (с базой)**

Хранилище — `storing.NewStore(Config, logging.DefaultLogger)`, как `deleteAllSources`; событие, приоритет, сценарий — через API, как в `TestPermissions`.

```go
func TestInsertEventIfNew(t *testing.T)            // первый вызов true; тот же guid — false, nil; GetEvent: OccurredAt как передан, Processed false, AlarmNumber nil
func TestReserveIncidentNumbers(t *testing.T)      // a := Reserve(1); Reserve(3) == a+1; Reserve(1) == a+4
func TestIncidentEventScenarioUnique(t *testing.T) // второй живой инцидент той же пары — ошибка; после DeleteIncident первого — вставка без ошибки
func TestIncidentNewFieldsRoundTrip(t *testing.T)  // Number, Version 1, State "new", RuleGUID — как вставлены; GetIncidentsByEvent — по number
func TestMarkEventProcessedSetsAlarm(t *testing.T) // MarkEventProcessed(g, &n) → Processed true, *AlarmNumber == n; с nil — AlarmNumber nil
func TestJournalEntriesRoundTrip(t *testing.T)     // две записи → GetJournalEntries по at, поля и Vars те же
```

- [ ] **Step 3: Тесты падают**

Run: `cd ~/Work/incident-manager-server && source ~/go/offline-env.sh && go test ./internal/im/model/ 2>&1 | tail -5`
Expected: FAIL — не собирается (`StatusCodeForState` не объявлен).

- [ ] **Step 4: Миграция, модель, хранение**

- [ ] **Step 5: Тесты проходят**

Run: `go test ./internal/im/model/ && make test-local 2>&1 | tail -15`
Expected: PASS всех пакетов (миграция применилась к `im-test-db` при старте тестов).

- [ ] **Step 6: Миграция на копии базы стенда**

Копия — в `im-test-db`, отдельная база `imcopy`; стенд не трогаем.
Run: `sg docker -c "docker exec im-test-db psql -U postgres -c 'DROP DATABASE IF EXISTS imcopy' -c 'CREATE DATABASE imcopy' && docker exec \$(docker ps -qf name=ac_db) pg_dump -O -x -U im imdb | docker exec -i im-test-db psql -q -U postgres imcopy" && sed -n '/+migrate Up/,/+migrate Down/p' internal/im/service/storing/migrations/014_incident_intake.sql | sg docker -c "docker exec -i im-test-db psql -v ON_ERROR_STOP=1 -1 -q -U postgres imcopy" && sg docker -c "docker exec im-test-db psql -U postgres imcopy -tAc \"SELECT count(*) FROM (SELECT 1 FROM incidents WHERE deleted_at IS NULL GROUP BY event_guid, scenario_guid HAVING count(*) > 1) d; SELECT count(*) FROM incidents WHERE number IS NULL; SELECT last_number = (SELECT max(number) FROM incidents) FROM incident_counters\""`
Expected: миграция без ошибок; `0`, `0`, `t`. Затем `DROP DATABASE imcopy`.

- [ ] **Step 7: Commit**

Сообщение: «Этап 3: миграция 014 — номер, версия, состояние, правило и ключ «событие + сценарий» у инцидента, номер тревоги и время события, журнал».
Run: `git add internal/im && git commit -q -F .git/COMMIT_MSG_STAGE3`

---

### Task 2: Арендатор из настройки `IM_CUSTOMER_GUID`

**Files:**
- Modify: `internal/im/model/config.go`
- Modify: `internal/im/appservice/appservice.go` (`GetServices`: проверка арендатора до `Start`; доступ `CustomerGUID()`)
- Modify: `internal/im/handler/v1/common.go` (`Handler` хранит `customerGUID`), `internal/im/handler/v1/auth_middleware.go:56,114`
- Modify: `internal/im/appservice/agent/agent.go:71` (пользователь из `fakedata` получает арендатора настройки)
- Test: `internal/im/model/config_test.go`, `internal/im/handler/test/tenancy_test.go`

**Interfaces:**
- Produces:
  - `Config.CustomerGUID string \`envconfig:"IM_CUSTOMER_GUID" default:"019bbe9b-b1b8-7817-ade7-d283887bb551"\`` — умолчание равно нынешнему тестовому, стенду и тестам настройка не нужна;
  - `func (c *Config) Customer() (uuid.UUID, error)` — ошибка с именем `IM_CUSTOMER_GUID`, если не UUID;
  - `func (s *AppServices) CustomerGUID() uuid.UUID`;
  - `GetServices` возвращает ошибку `IM_CUSTOMER_GUID <guid>: no such customer`, если строки нет в `customers` (сервер не стартует; строку создаёт миграция 002 — сервер её не заводит сам).

- [ ] **Step 1: Тесты**

```go
func TestConfigCustomer(t *testing.T) // умолчание разбирается; "nope" → ошибка, в тексте "IM_CUSTOMER_GUID"

func TestUnknownCustomerStopsStart(t *testing.T) {
	// копия Config с CustomerGUID = uuid.NewString() → appservice.GetServices(...) ошибка, в тексте "no such customer"
}

func TestNoFakedataCustomerInServerCode(t *testing.T) {
	// обход internal/im, кроме *_test.go и handler/test: ни в одном файле нет "fakedata.TestData.GetCustomer"
}
```

- [ ] **Step 2: Тесты падают**

Run: `go test ./internal/im/model/ -run TestConfigCustomer 2>&1 | tail -3`
Expected: FAIL — не собирается.

- [ ] **Step 3: Реализация**

- [ ] **Step 4: Тесты проходят**

Run: `go test ./internal/im/model/ && make test-local 2>&1 | tail -10 && golangci-lint run ./...`
Expected: PASS; lint без замечаний.

- [ ] **Step 5: Commit**

Сообщение: «Этап 3: арендатор — установка, customer_guid из IM_CUSTOMER_GUID вместо fakedata».
Run: `git add internal/im && git commit -q -F .git/COMMIT_MSG_STAGE3`

---

### Task 3: Правила для выбора — порядок сценариев, время создания, группы источника

Сейчас сценарии правила отдаются по имени (`ORDER BY sca.name`), а `DeleteIncidentRuleScenarios` удаляет только сценарии с актуальной версией: связь с архивным сценарием переживает правку правила. Порядок сценариев правила задаёт порядок создания инцидентов (§14.5, п. 4), поэтому он хранится как прислал конфигуратор.

**Files:**
- Modify: `internal/im/service/storing/incident_rule_scenarios_converters.go` (`Position` = индекс в `Scenarios`), `incident_rule_scenarios_queries.go` (`ORDER BY irs.position`; удаление — `WHERE rule_guid = $1`), `incident_rule_queries.go` (`created_at` при вставке)
- Create: `internal/im/model/intake.go`, `internal/im/service/storing/intake_queries.go`
- Modify: `internal/im/service/storing/source_group_membership_queries.go`
- Test: `internal/im/handler/test/intake_rules_test.go`

**Interfaces:**
- Consumes: столбцы задачи 1.
- Produces:
  - `type IntakeRule struct { GUID uuid.UUID; Name string; PriorityGUID uuid.UUID; PriorityValue int64; CreatedAt time.Time; Scenarios []IntakeRuleScenario; Conditions []IntakeCondition }`;
  - `type IntakeRuleScenario struct { GUID uuid.UUID; Name string; Version *int64 }` — `Version == nil`: у сценария нет актуальной версии;
  - `type IntakeCondition struct { SourceGUID, SourceTypeGUID, GroupGUID *uuid.UUID; EventTypeUID *string }`;
  - `func (s *Store) LoadIntakeRules(ctx model.AppContext, customerGUID uuid.UUID) ([]*model.IntakeRule, error)` — три запроса (правила с `priorities.value`; сценарии `LEFT JOIN scenarios_actual` по `rule_guid, position`; условия `LEFT JOIN source_event_types` за `uid`), сборка в Go; порядок правил не важен (его задаёт `ruleselect`);
  - `func (s *Store) GetSourceGroupGUIDs(ctx model.AppContext, sourceGUID uuid.UUID) ([]uuid.UUID, error)` — прямые группы источника.

- [ ] **Step 1: Тесты (с базой)**

```go
func TestIncidentRuleScenariosKeepOrder(t *testing.T) {
	// создать правило со сценариями [s2, s1] → GetIncidentRule: [s2, s1];
	// UpdateIncidentRule ScenarioGUIDs [s1, s2] → [s1, s2]
}

func TestRuleUpdateDropsArchivedScenarioLink(t *testing.T) {
	// правило [s1, s2]; DeleteScenario(s2) (архив); UpdateIncidentRule ScenarioGUIDs [s1]
	// → LoadIntakeRules: у правила ровно [s1], без ошибки уникальности
}

func TestLoadIntakeRules(t *testing.T) {
	// правило: приоритет value 75, сценарии [s2 (архив), s1], условие {SourceEventTypeGUID: et}
	// → PriorityValue 75; CreatedAt в пределах минуты от now; Scenarios[0].GUID == s2 и Version == nil,
	//   Scenarios[1].Version == 1; Conditions[0].EventTypeUID == et.UID, остальные поля nil
}

func TestGetSourceGroupGUIDs(t *testing.T) // источник в двух группах → обе; источник без групп → пусто
```

- [ ] **Step 2: Тесты падают**

Run: `make test-local 2>&1 | grep -E 'FAIL|ok' | head`
Expected: FAIL — `LoadIntakeRules` не объявлен.

- [ ] **Step 3: Реализация**

- [ ] **Step 4: Тесты проходят**

Run: `make test-local 2>&1 | tail -10 && golangci-lint run ./...`
Expected: PASS всех пакетов (прежние тесты правил — тоже); lint без замечаний.

- [ ] **Step 5: Commit**

Сообщение: «Этап 3: сценарии правила — в порядке конфигуратора, время создания правила, правила и группы источника для выбора».
Run: `git add internal/im && git commit -q -F .git/COMMIT_MSG_STAGE3`

---

### Task 4: `ruleselect` — зеркало определений машины

Чистый пакет без базы. Каждая функция — одно определение `cel.definitions` машины, имена те же; комментарий пакета: `STAGE4: replace with the CEL executor over operatorapi.Machine (intake section)`. Поля условия — строки, `""` — поле не задано (`opt` пустой). Значения в адаптере (задача 5): `EventType` — `uid` типа события, `Device` — guid источника, `DeviceType` — guid типа источника, `Group` — guid группы, всё `uuid.String()`.

**Files:**
- Create: `internal/im/ruleselect/ruleselect.go`
- Test: `internal/im/ruleselect/ruleselect_test.go`, `internal/im/ruleselect/pin_test.go`

**Interfaces:**
- Consumes: `operatorapi.Machine` (только `pin_test.go`).
- Produces:
  - `type Event struct { GUID, EventType, Device, DeviceType string }`;
  - `type Condition struct { EventType, Device, DeviceType, Group string }`;
  - `type Rule struct { GUID string; Priority int64; CreatedAt int64 /* ms */; Scenarios []string; Conditions []Condition }`;
  - `type World interface { DeviceInGroup(device, group string) bool; GroupDepth(group string) int }`;
  - `type Pick struct { Scenario string; Rule *Rule }`;
  - `ConditionMatches(w World, c Condition, e Event) bool`, `ConditionRank(w World, c Condition) int` (3000 / 2000 / 1000 + глубина / 0), `RuleRank(w World, r *Rule, e Event) int` (−1, если не подошло ни одно), `RuleMatches(w World, r *Rule, e Event) bool`, `RuleBeats(w World, a, b *Rule, e Event) bool`, `RuleFor(w World, rules []*Rule, e Event, s string) []*Rule`;
  - `func OrderRules(rules []*Rule) []*Rule` — копия по `strings.ToLower(GUID)` по возрастанию (`intake.ruleOrder`);
  - `func Intake(w World, rules []*Rule, e Event) []Pick`;
  - `func ApplyUniqueKey(picks []Pick, key []string) ([]Pick, error)` — `["eventGuid","scenario"]` → как есть; `["eventGuid"]` → `picks[:1]` (пусто — пусто); иное — ошибка `unsupported intake.uniqueKey`;
  - `func UniqueKeyFromMachine(machine []byte) ([]string, error)` — `intake.uniqueKey` копии машины.

`Intake` — как `intake()` в `engine.js`: `ordered := OrderRules(rules)`; сценарии — по первому появлению в `ordered` среди подошедших (`RuleMatches`), без повторов; победитель сценария — `RuleFor(w, ordered, e, s)[0]`; порядок — `sort.SliceStable` с правилом: одно правило — по индексу сценария в его `Scenarios`; иначе `RuleBeats(x, y)` — раньше `x`, `RuleBeats(y, x)` — раньше `y`; иначе по индексу правила в `ordered`.

- [ ] **Step 1: Тесты по разделу «Одно событие — несколько инцидентов» `api-scenarios.js`**

Мир теста: группа `mall` (глубина 0) ⊃ `nested` (глубина 1) ∋ `S5`; `S2` вне групп. Правила как в наборе: `R1` {fire} P75 `createdAt` 2026-08-01 → [FIRE]; `R9` {fire, group mall} P100 → [MED]; `Ra` {fire, device S2} P100 2026-09-15 → [FIRE]; `R3` {sabotage} P50 → [SAB]. Событие `fireAt(d)` = {EventType "fire", Device d, DeviceType "smoke"}.

```go
func TestIntake_IncidentPerScenarioOfMatchedRules(t *testing.T) // fireAt(S5), [R1, R9, Ra] → [(MED, R9), (FIRE, R1)]
func TestIntake_OrderByWinnerRankNotPriority(t *testing.T)     // R9 с P25 → всё равно [(MED, R9), (FIRE, R1)]
func TestIntake_ScenariosOfOneRuleKeepListOrder(t *testing.T)  // Rb {fire} P50 [MED, FIRE] → [(MED,Rb),(FIRE,Rb)]; [FIRE, MED] → обратный порядок
func TestIntake_OverlappingRulesSameScenario(t *testing.T)     // fireAt(S2), [R1, Ra] → один Pick (FIRE, Ra); Ra с P25 — всё равно Ra
func TestRuleFor_NestedGroupBeatsParent(t *testing.T)          // {group mall} P100 против {group nested} P25, оба [FIRE] → nested
func TestRuleFor_EqualRankPriorityThenCreatedAt(t *testing.T)  // оба mall: P50 09-03 против P50 09-02 → 09-02; P75 09-03 против P50 09-02 → P75
func TestIntake_FullTieDecidedByGUID(t *testing.T)             // равные …0e и …0d [FIRE] в любом порядке входа → …0d;
                                                               // …0e [FIRE] и …0d [MED] → [(MED, …0d), (FIRE, …0e)]
func TestIntake_RuleWithoutScenarioIgnored(t *testing.T)       // {sabotage, device D} P100 без сценариев + R3 → [(SAB, R3)]
func TestIntake_NoMatchNoPicks(t *testing.T)                   // событие glass → len 0
func TestApplyUniqueKey(t *testing.T)                          // fireAt(S5): ключ событие+сценарий → [MED, FIRE]; ключ «только событие» → [MED]; ["scenario"] → ошибка
func TestConditionMatches(t *testing.T)                        // таблица: каждое поле мимо → false; все поля "" → true; группа — и вложенная
func TestConditionRank(t *testing.T)                           // device+group 3000; deviceType 2000; group nested 1001; group mall 1000; только тип 0
func TestRuleRank(t *testing.T)                                // максимум из подошедших; ни одного → −1
```

- [ ] **Step 2: Тест-замок на машину**

Канон: из `operatorapi.Machine` взять `intake` без `uniqueKey` (его читает сервер, задача 5), `cel.definitions` (`conditionMatches`, `conditionRank`, `ruleRank`, `ruleMatches`, `ruleBeats`, `ruleFor`), `cel.world` (`deviceInGroup`, `groupDepth`), `cel.types` (`Event`, `Rule`, `Condition`); рекурсивно убрать ключи, начинающиеся с `$`; `json.Marshal` (Go сортирует ключи); `sha256` в hex. Комментарии `$comment` в хэш не входят — правка текста не будит тест, правка выражения будит.

```go
const intakePinSHA256 = "c8f6476eebf34ebeb6ae0caae6b9b3bd5a3941d9266184ac39de679588cbd35b" // vendored afd30ea

func TestMachineIntakePinned(t *testing.T) {
	sum, canon := intakePin(t, operatorapi.Machine)
	require.Equal(t, intakePinSHA256, sum,
		"machine intake changed: update ruleselect (or switch to the CEL executor, stage 4) and this hash; canonical:\n%s", canon)
}

func TestMachineIntakeShape(t *testing.T) {
	// UniqueKeyFromMachine(operatorapi.Machine) == ["eventGuid","scenario"]; ruleOrder "guid", match "ruleMatches", winner "ruleFor", create "create";
	// переход create: from [], to "new", actor "dispatcher", эффекты содержат appendLog "workflow.journal.create" и startTimer "reaction"
}
```

Хэш посчитан этой процедурой на копии `afd30ea` и на рабочей копии IM 2026-10-29 — совпадает.

- [ ] **Step 3: Тесты падают**

Run: `go test ./internal/im/ruleselect/ 2>&1 | tail -3`
Expected: FAIL — не собирается.

- [ ] **Step 4: Реализация `ruleselect.go`**

- [ ] **Step 5: Тесты проходят**

Run: `go test ./internal/im/ruleselect/ -v 2>&1 | tail -20 && golangci-lint run ./...`
Expected: PASS; lint без замечаний.

- [ ] **Step 6: Commit**

Сообщение: «Этап 3: выбор правил по §14.5 — зеркало определений машины на Go, замок на раздел intake».
Run: `git add internal/im/ruleselect && git commit -q -F .git/COMMIT_MSG_STAGE3`

---

### Task 5: Сервис `intake` — событие → инциденты в транзакции вызывающего

Сервис ничего не открывает сам: вызывается внутри `DoInTx` (задача 6), так же его вызовет `POST /test/events` в этапе 7. Сначала всё проверяется, потом пишется: ошибка до записи не оставляет следов даже без отката.

**Files:**
- Create: `internal/im/service/intake/{store.go, world.go, service.go}`
- Modify: `internal/im/model/intake.go` (`IntakeEvent`, `IntakeResult`, ошибки)
- Test: `internal/im/service/intake/service_test.go` (без базы, поддельное хранилище и дерево)

**Interfaces:**
- Consumes: задачи 1, 3, 4; `sourcegroup.Service.Tree()` (`*tree.Index`).
- Produces:
  - `type Store interface { LoadIntakeRules(…); GetSourceGroupGUIDs(…); GetStatusByCode(ctx model.AppContext, code string) (*model.Status, error); ReserveIncidentNumbers(…); InsertIncident(…); InsertJournalEntries(…); MarkEventProcessed(…) }` — подписи из задач 1 и 3;
  - `type GroupTree interface { IsSelfOrAncestor(ancestor, guid uuid.UUID) bool; PathFromRoot(guid uuid.UUID) []uuid.UUID }`;
  - `type IntakeEvent struct { GUID, CustomerGUID, SourceGUID, SourceTypeGUID uuid.UUID; SourceName, EventTypeUID string }` и `type IntakeResult struct { AlarmNumber *int64; Incidents []*Incident }` — в `internal/im/model/intake.go`;
  - `var ErrIntakeScenarioUnavailable, ErrStatusNotConfigured error` — в `model`;
  - `func NewService(store Store, tree GroupTree, now func() time.Time, uniqueKey []string) (*Service, error)` — `uniqueKey` из `ruleselect.UniqueKeyFromMachine(operatorapi.Machine)` при сборке сервисов; неподдержанный — ошибка;
  - `func (s *Service) Process(ctx model.AppContext, ev *model.IntakeEvent) (*model.IntakeResult, error)`;
  - `func newTreeWorld(tree GroupTree, device uuid.UUID, groups []uuid.UUID) ruleselect.World` — `DeviceInGroup(d, g)`: `d` — это устройство события и `IsSelfOrAncestor(g, x)` для какой-то его группы `x`; `GroupDepth(g)` = `len(PathFromRoot(g)) − 1`, группы нет в дереве → 0 (и не подходит).

`Process` по шагам: правила (`LoadIntakeRules`) и группы источника → `ruleselect.Intake` → `ApplyUniqueKey` → нет выбора: `MarkEventProcessed(guid, nil)`, пустой результат. Иначе: у каждого выбранного сценария есть версия, иначе `fmt.Errorf("%w: rule %q, scenario %s", ErrIntakeScenarioUnavailable, …)`; статус — `GetStatusByCode(StatusCodeForState(StateNew))`, `ErrEntryNotFound` → `ErrStatusNotConfigured`; один `now()` на всё событие; `first := ReserveIncidentNumbers(customer, len)`; инциденты по порядку выбора: `Number first+k`, `State StateNew`, `Version 1`, `StatusGUID` статуса, `PriorityGUID`/`RuleGUID` победителя, сценарий и его версия, `EventGUID`, `CustomerGUID`, `CreatedAt now`, `Name` — прежний вид «правило сценарий источник»; запись журнала на каждый (`ActorDispatcher`, `TransitionCreate`, `JournalCreate`, `At now`, `Vars nil`); `MarkEventProcessed(guid, &first)`. Каждая функция — в пределах `funlen`.

- [ ] **Step 1: Тесты**

```go
func TestProcess_NoMatch(t *testing.T)                     // правил нет → MarkEventProcessed(g, nil); Reserve/Insert не вызывались; результат: AlarmNumber nil, 0 инцидентов
func TestProcess_CreatesInPickOrder(t *testing.T) {
	// правила как R1 и R9 задачи 4, источник в nested; Reserve отдаёт 41
	// → инциденты [MED (41), FIRE (42)]; у обоих State "new", Version 1, StatusGUID open, RuleGUID и PriorityGUID победителя,
	//   ScenarioVersion — актуальная; MarkEventProcessed(g, 41); журнал — 2 записи create, At == now, Actor "dispatcher"
}
func TestProcess_ScenarioWithoutVersionWritesNothing(t *testing.T) // errors.Is(err, ErrIntakeScenarioUnavailable); текст — имя правила и guid сценария; ни Reserve, ни Insert, ни Mark
func TestProcess_MissingOpenStatusWritesNothing(t *testing.T)      // GetStatusByCode → ErrEntryNotFound ⇒ errors.Is(err, ErrStatusNotConfigured); записей нет
func TestProcess_UniqueKeyEventOnly(t *testing.T)                 // NewService(…, ["eventGuid"]) и правила R1, R9 → 1 инцидент MED, alarm = его номер
func TestTreeWorld(t *testing.T)                                   // устройство во вложенной группе — в родителе тоже; глубины 0/1; чужое устройство — false; группы нет — false и 0
```

- [ ] **Step 2: Тесты падают**

Run: `go test ./internal/im/service/intake/ 2>&1 | tail -3`
Expected: FAIL — не собирается.

- [ ] **Step 3: Реализация**

- [ ] **Step 4: Тесты проходят**

Run: `go test ./internal/im/service/intake/ -v 2>&1 | tail -15 && golangci-lint run ./...`
Expected: PASS; lint без замечаний.

- [ ] **Step 5: Commit**

Сообщение: «Этап 3: сервис «событие → инциденты» — выбор правил, номера, переход create, журнал, отметка события».
Run: `git add internal/im && git commit -q -F .git/COMMIT_MSG_STAGE3`

---

### Task 6: Синхронный `POST /events`; фоновый обработчик убран

**Files:**
- Modify: `internal/im/handler/v1/event.go` (разбор `occurredAt`; `422`)
- Modify: `internal/im/appservice/event/event.go` (+ `bl` интерфейсы), `internal/im/service/event/service.go` (`InsertEventIfNew`)
- Modify: `internal/util/apierror/common.go` (`NewUnprocessable`), `keys.go` (`KeyEventIntakeFailed = "error.event.intake.failed"`)
- Modify: `internal/im/appservice/appservice.go` (сборка `intake.Service`; `Start`/`Stop` без обработчика)
- Delete/Modify: `internal/im/appservice/incidentrulecondition/processor.go` (обработчик, `run`, кэш условий и состава групп, `listenEvents` — удалить), `incident_rule_condition.go:125,158,179` (вызовы кэша), `internal/im/appservice/sourcegroup/bl/service.go:31` (`ReloadGroupMembers` и его вызовы); `GetUnprocessedEvents`, старый `MarkEventAsProcessed` — удалить
- Modify: `internal/im/handler/test/permission_test.go` — убрать `time.Sleep(1 * time.Second)` (строки 81, 173, 263)
- Test: `internal/im/appservice/event/event_test.go` (без базы), `internal/im/handler/test/intake_test.go` (с базой), `internal/im/model/event_test.go`

**Interfaces:**
- Consumes: задачи 1, 2, 5.
- Produces:
  - `model.EventReceived` + `OccurredAt *time.Time`; `func OccurredAtFromPayload(raw json.RawMessage) *time.Time` — `occurredAt` строкой RFC 3339, иначе `nil`;
  - `func (s *AppService) CreateEvent(ctx model.AppContext, creator *model.Agent, received *model.EventReceived) error` — подпись прежняя. Внутри: источник и тип события — как сейчас (вне транзакции, 404 как раньше); `transactor.DoInTx`: `InsertEventIfNew` (`OccurredAt` = из тела или время приёма) → `false` — повтор, `nil`; иначе `intake.Process`. Снаружи `DoInTx` — `defer recover()`: паника → лог со стеком и ошибка `500`. `ErrIntakeScenarioUnavailable` → `apierror.NewUnprocessable(KeyEventIntakeFailed, err.Error())`;
  - `func NewUnprocessable(key Key, description string) *APIError` — 422.

- [ ] **Step 1: Тесты без базы**

```go
func TestOccurredAtFromPayload(t *testing.T) // {"occurredAt":"2026-10-03T11:59:00Z"} → это время; нет поля, число, "вчера", не JSON → nil
func TestCreateEvent_PanicBecomesError(t *testing.T) // поддельный intake паникует → CreateEvent вернул ошибку, паники наружу нет
func TestCreateEvent_ScenarioUnavailableIs422(t *testing.T) // intake → ErrIntakeScenarioUnavailable ⇒ *apierror.APIError, Code 422, Key "error.event.intake.failed"
```

- [ ] **Step 2: Тесты с базой**

Помощники в `intake_test.go`: `newIntakeWorld(t)` — агент, тип источника, тип события, источники `D1`, `D2`, дерево групп `mall ⊃ nested ∋ D1`, приоритеты 25/50/75/100, сценарии; в начале — `deleteAllIncidentRuleConditions` (чужое условие без полей подошло бы любому событию); `send(t, guid, src) error`; `incidentsOf(t, guid)` и `eventOf(t, guid)` — через хранилище задачи 1. Все проверки — по инцидентам своего события.

```go
func TestEventRepeatCreatesNothing(t *testing.T)     // E → 1 инцидент; повтор E — NoError; инциденты E те же (guid, number); alarm прежний
func TestEventRepeatConcurrent(t *testing.T)         // 10 горутин шлют один новый guid → все NoError; у события 1 инцидент
func TestEventTwoConditionsOneRule(t *testing.T)     // правило с условиями {source D1} и {source type} → 1 инцидент
func TestEventTwoRulesSameScenario(t *testing.T)     // {event type} P100 и {source D1} P25, один сценарий → 1 инцидент; rule_guid — правила устройства, приоритет 25
func TestEventTwoScenariosOneRule(t *testing.T)      // правило [s2, s1] → инциденты s2, s1; номера n, n+1; alarm = n; правило одно
func TestEventRankingOrder(t *testing.T)             // {group mall} P25 [M] и {event type} P100 [F] → первым M; alarm = номер M
func TestEventNestedGroupBeatsParent(t *testing.T)   // {group mall} P100 и {group nested} P25, один сценарий → правило nested
func TestEventCreateFields(t *testing.T)             // State "new", Version 1, статус open, ScenarioVersion актуальная; журнал: 1 запись create; событие processed, alarm = первый номер
func TestEventNoMatch(t *testing.T)                  // правил под событие нет → NoError; processed true, alarm nil, инцидентов 0
func TestEventAllOrNothing(t *testing.T) {
	// A {event type} [sA], B {source D1} [sB]; DeleteScenario(sB) (архив)
	// → send от D1: ошибка с "status code: 422" и "error.event.intake.failed"; GetEvent → не найдено; инцидентов нет
	// повтор того же guid → снова 422; событие от D2 (подходит только A) → 1 инцидент sA
	// DeleteIncidentRule(B) → повтор первого события → NoError, 1 инцидент sA
}
func TestEventAfterRuleDeletedNoPanic(t *testing.T)  // правило с условием; DeleteIncidentRule; send → NoError, инцидентов 0
func TestEventSeesNewRuleImmediately(t *testing.T)   // E1 без правил → 0; создать правило и условие; E2 сразу → 1
func TestEventOccurredAtFromPayload(t *testing.T)    // тело с occurredAt → events.occurred_at он же; без поля и с "вчера" → не раньше времени отправки, NoError
func TestIncidentNumbersFollowEvents(t *testing.T)   // два события подряд → номер второго = номер первого + 1
```

`TestPermissions`, `TestOldIncidentRoutesPermissions`, `TestOldIncidentCardOutsideAccessLooksLikeMissing` — без `time.Sleep`: инцидент есть сразу после ответа `CreateEvent`.

- [ ] **Step 3: Тесты падают**

Run: `go test ./internal/im/model/ ./internal/im/appservice/event/ 2>&1 | tail -5 && make test-local 2>&1 | grep -E '^(--- FAIL|FAIL|ok)' | head -20`
Expected: FAIL — `OccurredAtFromPayload` не объявлен; после объявления — тесты с базой падают на повторе (500) и числе инцидентов.

- [ ] **Step 4: Реализация**

- [ ] **Step 5: Тесты проходят, гонок нет**

Run: `make test-local 2>&1 | tail -15 && go test -race ./internal/im/appservice/event/ ./internal/im/service/intake/ && golangci-lint run ./...`
Expected: PASS всех пакетов, без `DATA RACE`; `grep -rn 'time.Sleep(1 \* time.Second)' internal/im/handler/test/` пусто; lint без замечаний.

- [ ] **Step 6: Commit**

Сообщение: «Этап 3: POST /events — событие и его инциденты одной транзакцией, повтор — 200 без новых инцидентов, фоновый обработчик убран».
Run: `git add internal && git commit -q -F .git/COMMIT_MSG_STAGE3`

---

### Task 7: Агент-эмулятор — повтор по событиям набора и загрузка правил демо

Сейчас `replay` шлёт событие на каждый инцидент с новым guid, и `INC-1847` с `INC-1853` (одно событие) уходят двумя событиями; первое же 404 обрывает прогон. Правил, групп, сценариев и приоритетов демо на сервере нет.

**Files:**
- Modify: `tools/agent-emulator/main.go` (поля набора: `eventGuid`, `occurredAt`, `rules`, `sourceGroups`, `priorities`, `scenarios.keys`; команды)
- Create: `tools/agent-emulator/replay.go`, `tools/agent-emulator/democonfig.go`
- Test: `tools/agent-emulator/replay_test.go`

**Interfaces:**
- Produces:
  - `type replayEvent struct { GUID uuid.UUID; DeviceID, EventType, Site, Text string; OccurredAt time.Time }`;
  - `func replayEvents(fx *fixture, run string) []replayEvent` — по одному на разный `eventGuid`, по `occurredAt`, затем по guid; устройство — первое у первого инцидента события; `GUID` — `eventGuid` набора, при непустом `run` — `uuid.NewSHA1(eventGuid, []byte(run))` (то же, что `uuid5` в Python);
  - `replay [--limit N] [--run <метка>]` — `occurredAt` в теле — из набора; ответ 404 `error.source.event.type.not.found` → строка `пропущено: <guid> <тип> от <устройство> — у типа события на сервере другой тип устройства` и дальше; другие ошибки — стоп с кодом 1; в конце — `отправлено N, пропущено M`, код 0;
  - `demo-config --token <токен пользователя> [--replace-rules]` — через API настройки, повторный запуск безопасен: приоритеты набора (есть с таким `value` — взять, нет — создать «<ru> (<value>)»); дерево `sourceGroups` и состав (группа ищется по имени у того же родителя); сценарии — последний файл `fixtures/scenarios/<ключ>.v<N>.json` рядом с набором, имя `Демо: <scenario.name>`, `script` — файл целиком (есть с таким именем — взять); правила — имя `Демо: <name>`: прежние «Демо: …» удалить и создать заново в порядке `createdAt` набора (тогда `created_at` и guid v7 сервера идут в том же порядке), сценарии — в порядке набора, условия — `eventTypeId` → тип события по `uid`, `deviceGuid` → источник по `uid`, `deviceTypeId` → тип источника по `uid`, `sourceGroupGuid` → созданная группа. Есть правила не «Демо: …» — без `--replace-rules` стоп со списком имён, с ним — удалить.

- [ ] **Step 1: Тесты**

```go
func TestReplayEventsOnePerEventGuid(t *testing.T) {
	// demo.json: 28 инцидентов → 27 событий; …1847 — одно событие (INC-1847 и INC-1853), устройство 20000000-0002-4000-8000-000000000005
	// первое — …1826 (09:27:40Z), последнее — …1847 (11:59:00Z); OccurredAt из набора
}

func TestReplayRunGUID(t *testing.T) {
	// run "" → guid набора; run "r1" у 70000000-0000-4000-8000-000000001847 → a1c1daa5-90b3-590c-bcff-310213bb33be (uuid5 Python)
}
```

Набор — `--fixture` по умолчанию; тест пропускается (`t.Skip`), если файла нет.

- [ ] **Step 2: Тесты падают**

Run: `go test ./tools/agent-emulator/ 2>&1 | tail -3`
Expected: FAIL — `replayEvents` не объявлен.

- [ ] **Step 3: Реализация**

- [ ] **Step 4: Тесты проходят, сборка**

Run: `go test ./tools/agent-emulator/ -v 2>&1 | tail -8 && go build -o ~/Work/stand/bin/agent-emulator ./tools/agent-emulator && golangci-lint run ./...`
Expected: PASS; бинарник собран; lint без замечаний.

- [ ] **Step 5: Commit**

Сообщение: «Этап 3: агент-эмулятор — повтор набора по событиям с их guid и временем, загрузка правил, групп, сценариев и приоритетов демо».
Run: `git add tools/agent-emulator && git commit -q -F .git/COMMIT_MSG_STAGE3`

---

### Task 8: Проверка на стенде и документы

Критерий готовности ([40-plan.md](40-plan.md), этап 3): `agent-emulator replay` даёт очередь как в демо прототипа; повтор события не создаёт второй инцидент и не даёт 500.

**«Как в демо» — по правилам, а не по снимку.** Инциденты `demo.json` — снимок, собранный руками (`$commentRules`): он не следует §14.5. Ожидание ниже посчитано по правилам набора независимой проверкой на Python (ранжирование §14.5 заново, не через Go-код). Расхождения со снимком, о которых говорит `$commentRules`: у событий `…1847` и `…1851` первым идёт медпункт (условие по группе точнее), и номер тревоги — его; у `…1851` медпункт есть; у `…1838` побеждает правило датчика `…0a` (приоритет 100); приоритеты пожаров и проникновений — от правил, а не из снимка. Два события сервер не примет: у типа события на сервере один тип устройства (стенд, шаг 3) — `fire` от камеры (`…1834`) и `intrusion` от тревожной кнопки (`…1843`).

Ожидание: 25 событий → 27 инцидентов, по возрастанию `occurredAt`; «сценарий · приоритет · правило»; номер тревоги — номер первого в строке; номера внутри события подряд, между событиями растут.

| # | событие | тип | инциденты | | # | событие | тип | инциденты |
|---|---|---|---|---|---|---|---|---|
| 1 | `…1826` | intrusion | intrusion · 75 · `…02` | | 14 | `…1840` | sabotage | sabotage · 50 · `…03` |
| 2 | `…1827` | loiter | loiter · 25 · `…04` | | 15 | `…1841` | loiter | loiter · 25 · `…04` |
| 3 | `…1828` | fire | fire · 75 · `…01` | | 16 | `…1842` | fire | fire · 75 · `…01` |
| 4 | `…1829` | intrusion | intrusion · 75 · `…02` | | — | `…1843` | intrusion | пропуск (404) |
| 5 | `…1830` | sabotage | sabotage · 50 · `…03` | | 17 | `…1844` | loiter | loiter · 25 · `…04` |
| 6 | `…1831` | fire | fire · 75 · `…01` | | 18 | `…1845` | sabotage | sabotage · 50 · `…03` |
| 7 | `…1832` | intrusion | intrusion · 75 · `…02` | | 19 | `…1852` | abandoned | abandoned · 75 · `…08` |
| 8 | `…1833` | loiter | loiter · 25 · `…04` | | 20 | `…1848` | ppe | ppe · 50 · `…05` |
| — | `…1834` | fire | пропуск (404) | | 21 | `…1846` | intrusion | intrusion · 75 · `…02` |
| 9 | `…1835` | sabotage | sabotage · 50 · `…03` | | 22 | `…1849` | alcohol | alcohol · 75 · `…06` |
| 10 | `…1836` | intrusion | intrusion · 75 · `…02` | | 23 | `…1850` | glass | glass · 75 · `…07` |
| 11 | `…1837` | loiter | loiter · 25 · `…04` | | 24 | `…1851` | fire | medical · 100 · `…09`; fire · 75 · `…01` |
| 12 | `…1838` | fire | fire · 100 · `…0a` | | 25 | `…1847` | fire | medical · 100 · `…09`; fire · 75 · `…01` |
| 13 | `…1839` | intrusion | intrusion · 75 · `…02` | | | | | |

Событие — хвост `eventGuid` `70000000-0000-4000-8000-00000000XXXX`; правило — хвост guid правила набора `80000000-…-0000000000XX` (на сервере — правило «Демо: <имя>»); сценарий — ключ `scenarios.keys`.

**Files:**
- Create (вне репозиториев): `~/Work/stand/load-demo.sh`, `~/Work/stand/check-demo-intake.sh`
- Create: `docs/adr/003-event-intake.md` (сервер)
- Modify (IM): `research/integration/30-local-stand.md`, `research/integration/40-plan.md`, `research/integration/51-plan-stage3.md` (отметки)

**Interfaces:**
- Consumes: всё из задач 1–7.

- [ ] **Step 1: Копия базы стенда и сервер с миграцией 014**

Run: `mkdir -p ~/Work/stand/backup && sg docker -c "docker exec \$(docker ps -qf name=ac_db) pg_dump -U im imdb" > ~/Work/stand/backup/imdb-before-014.sql && source ~/go/offline-env.sh && go build -o ~/Work/stand/bin/im ./cmd/im && pkill -f '^/home/slava/Work/stand/bin/im$'; ~/Work/stand/run-im-server.sh >> ~/Work/stand/im-server.log 2>&1` (в фоне), через 10 с — `pgrep -f '^/home/slava/Work/stand/bin/im$' && sg docker -c "docker exec \$(docker ps -qf name=ac_db) psql -U im -d imdb -tAc \"SELECT id FROM im_db_migrations WHERE id LIKE '014%'\""`
Expected: процесс жив, строка `014_incident_intake.sql`; в `imdb` нет живых дублей пары «событие + сценарий» (запрос из задачи 1, шаг 6).

- [ ] **Step 2: Загрузка демо**

`load-demo.sh`: вход `test@axxonnet.test` (как `check-operator-api.sh`) → токен; `agent-emulator sync`; `agent-emulator demo-config --token "$TOKEN" "$@"`.
Run: `~/Work/stand/load-demo.sh --replace-rules`
Expected: удалено правило «Стенд: тревога в офисе»; создано 10 правил «Демо: …», 9 сценариев, группы набора; приоритеты 25/50/75/100 есть. Если сервер отверг `script` сценария набора — **стоп, спросить пользователя**.

- [ ] **Step 3: Скрипт проверки очереди**

`check-demo-intake.sh [метка]` (python внутри): guid событий — как `replayEvents` (`uuid5` от `eventGuid` при метке); запрос к `imdb` через `docker exec … psql -tA`: по каждому событию — `events.alarm_number`, `processed`, живые инциденты по `number` с ключом сценария (по имени «Демо: …» → `scenarios.keys`), `priorities.value`, именем правила. Сверка с таблицей выше: те же инциденты в том же порядке, те же приоритеты и правила, номер тревоги = номер первого, номера внутри события подряд, между событиями растут; пропущенные события — нет в `events`. Строки `OK|FAIL`, код выхода — число `FAIL`.

- [ ] **Step 4: Прогон и повтор**

Run: `M=demo-$(date +%s) && ~/Work/stand/bin/agent-emulator replay --run $M; ~/Work/stand/check-demo-intake.sh $M; N1=$(sg docker -c "docker exec \$(docker ps -qf name=ac_db) psql -U im -d imdb -tAc 'SELECT count(*) FROM incidents'"); ~/Work/stand/bin/agent-emulator replay --run $M; N2=$(sg docker -c "docker exec \$(docker ps -qf name=ac_db) psql -U im -d imdb -tAc 'SELECT count(*) FROM incidents'"); echo "$N1 $N2"; ~/Work/stand/bin/agent-emulator event --device 20000000-0001-4000-8000-000000000009 --type intrusion --guid $(python3 -c "import uuid;print(uuid.uuid5(uuid.UUID('70000000-0000-4000-8000-000000001826'),'$M'))") && echo repeat-ok`
Expected: первый `replay` — `отправлено 25, пропущено 2`; проверка — все `OK`, код 0; второй `replay` — без ошибок, `N1 = N2`; повтор одного события — `repeat-ok` (200, не 500); в `im-server.log` нет `panic`.

- [ ] **Step 5: ADR сервера**

`docs/adr/003-event-intake.md` (англ., по образцу ADR-002): синхронная обработка в `POST /events` и почему (транзакция события + инцидентов + отметки; повтор через `ON CONFLICT`; без опроса и кэша — нет `nil` от удалённого правила; тот же `Process` для `POST /test/events` этапа 7); `ruleselect` — зеркало определений, замок по хэшу, замена исполнителем CEL в этапе 4; RULE-137 как есть и `422` для агента; `state` — истина, `status_guid` — из таблицы для конфигуратора; номер из `incident_counters`; частичный уникальный индекс и снятие дублей миграцией; `occurred_at` из тела или время приёма; `IM_CUSTOMER_GUID`; что отложено на этапы 4–6.

- [ ] **Step 6: Документы IM**

Перед правкой — `git -C /mnt/hgfs/VmWareShared/soul2home/IM fetch`; есть новое — сказать пользователю.
- `30-local-stand.md`: «Шаг 5: событие → инцидент (этап 3)» — миграция 014 и копия базы, `load-demo.sh`, `replay --run`, `check-demo-intake.sh`, ожидание (25 → 27, 2 пропуска и почему), повтор; в «Временное на стенде» — `~/Work/stand/backup/`.
- `40-plan.md`: в «Что уже готово» строка «Событие → инцидент (этап 3)» со ссылкой на этот план.

Run: `cd /mnt/hgfs/VmWareShared/soul2home/IM && python3 tools/check_links.py`
Expected: без ошибок ссылок.

- [ ] **Step 7: Последний прогон**

Run: `cd ~/Work/incident-manager-server && source ~/go/offline-env.sh && make test-local 2>&1 | tail -15 && go vet ./... && golangci-lint run ./...`
Expected: все тесты PASS, `go vet` чисто, lint — 0 замечаний.

- [ ] **Step 8: Commit (два репозитория)**

Сервер — «Этап 3: ADR о событии → инциденте». Run: `git add docs/adr/003-event-intake.md && git commit -q -F .git/COMMIT_MSG_STAGE3`
IM — «Этап 3 встраивания: событие → инцидент на стенде». Run: `cd /mnt/hgfs/VmWareShared/soul2home/IM && git add research/integration/30-local-stand.md research/integration/40-plan.md research/integration/51-plan-stage3.md && git commit -q -F .git/COMMIT_MSG_STAGE3`

---

## Не в этом этапе

| Что | Когда |
|---|---|
| Исполнитель CEL вместо `ruleselect` (определения машины вычисляются, а не повторены в Go) | этап 4 |
| Владелец, адресат, дежурная группа, уровень эскалации, причины, результат закрытия, связи (`linked_to`, `linked_at`, `left_group`), число приоритета на инциденте (§2.5, переоткрытие) | этап 4 |
| Ключи идемпотентности в PostgreSQL и подключение к операциям | этап 4 |
| Лента событий потока (`incident.created`), сессии операторов, очередь `/operator/incidents` | этап 5 |
| Таймеры: норматив реакции (`startTimer reaction` перехода `create`), планировщик | этап 6 |
| `POST /test/events`, `POST /test/incidents` (вызовут `intake.Service.Process`) | этап 7 |
| Новые поля в ответах API настройки (`number`, `state`, `alarmNumber`) — нужна перегенерация `v1` | вне плана |

## Решения этого плана (на подтверждение)

1. **Синхронно, а не фоновый обработчик.** BACKEND.md требует одной транзакции на «все инциденты события и отметку события» и «повтор события ничего не создаёт». Синхронно это одна транзакция с самой записью события: повтор отсекает `ON CONFLICT` по первичному ключу, одновременный повтор ждёт первый на этом же ключе; нет очереди, нет порядка «новые раньше старых», нет кэша условий (удалённое правило не даёт `nil`), нет `time.Sleep` в тестах; тот же `Process` нужен `POST /test/events`, где ответ — сразу созданные инциденты. Цена — время ответа агенту (несколько запросов к базе) — для стенда несущественна; фоновых событий сейчас нет (`processed = false` в `imdb` — 0).
2. **RULE-137 для агента — `422` и событие не записано:** как прототип (`422`, повтор снова обрабатывается). Агент повторит событие, когда настройку поправят.
3. **`state` — истина, `status_guid` выводится** таблицей `StatusCodeForState`.
4. **Частичный уникальный индекс** (`WHERE deleted_at IS NULL`) и снятие дублей стенда мягким удалением в миграции.
5. **Номер — счётчик-таблица** без дыр, а не `SEQUENCE` (та тратит номера при откате, и она одна на всех арендаторов).
6. **`occurred_at`** — из `payload.occurredAt` (RFC 3339), иначе время приёма; кривое значение событие не отклоняет.
7. **`IM_CUSTOMER_GUID` с умолчанием = нынешний тестовый арендатор**; нет такой строки в `customers` — сервер не стартует.
8. **Норматив реакции — этап 6**, не этап 3.
9. **«Как в демо» — по правилам**, 25 событий / 27 инцидентов; два события набора стенд не примет (тип события привязан к одному типу устройства).
10. **Ключ уникальности — из копии машины** (`intake.uniqueKey`, PROC-93), ранжирование — повтор определений на Go до этапа 4 под замком-хэшем.

## Решения по открытым вопросам (2026-10-29)

- **Удаление используемого сценария — запретить** (решение пользователя): `DELETE /scenarios/{guid}` сценария, на который ссылается хоть одно правило, — `409` `{key, description}` со списком правил; сначала убрать сценарий из правил. Ловушка RULE-137 закрывается до события. Задача 9.
- **Тип события — по паре «тип устройства + `uid`»** (решение пользователя): синхронизация агента и поиск типа события при приёме — по паре; все события демо проходят. Задача 10. «Как в демо» — тогда без исключений.
- **`422` в контракте `POST /events`** (решение контролёра): дописать `422` в `backend.openapi.yaml` (только описание, без перегенерации `v1`) — в задаче 6.

### Task 9: Запрет удаления сценария, который используют правила

**Files:** `internal/im/appservice/scenario/*` (удаление), `internal/im/service/storing/*scenario*` (запрос «правила со сценарием»), `internal/util/apierror/keys.go` (ключ `error.scenario.in_use`), `api/im/backend.openapi.yaml` (ответ `409` у `DELETE /scenarios/{guid}`, только описание), тест в `internal/im/handler/test/`.

- [ ] **Step 1: Тест** `TestDeleteScenarioUsedByRule409`: правило ссылается на сценарий → `DELETE /scenarios/{guid}` → `409`, `key` = `error.scenario.in_use`, в `description` — имя правила; сценарий не архивирован; после удаления сценария из правила — `DELETE` проходит.
- [ ] **Step 2: Реализация** — проверка в той же транзакции, что и архивирование.
- [ ] **Step 3: Прогон** — тесты с базой, lint.
- [ ] **Step 4: Commit** «Этап 3: сценарий, который используют правила, не удаляется — 409».

### Task 10: Тип события — по паре «тип устройства + uid»

**Files:** синхронизация агента (`appservice/sync*` / `source_event_types`), приём события (`appservice/event/event.go` — поиск типа события по типу источника и `eventTypeUid`), миграция (уникальность `source_event_types` — по `(customer_guid, source_type_guid, uid)`, если сейчас по `uid`), `ruleselect` — сравнение типа события по `id` (`uid`) остаётся, тест.

- [ ] **Step 1: Тест** `TestSameEventTypeUidForTwoDeviceTypes`: синхронизация двух типов устройств с одинаковым `uid` типа события (`fire` у камеры и у датчика) → оба типа событий есть; события от обоих устройств принимаются (`200`), инциденты создаются по правилам.
- [ ] **Step 2: Реализация** — уникальность и поиск по паре; правила с условием `sourceEventTypeGuid` продолжают работать.
- [ ] **Step 3: Прогон** — тесты с базой, lint; `check-demo-intake.sh` (задача 8) — все события демо проходят.
- [ ] **Step 4: Commit** «Этап 3: тип события различается по типу устройства и uid».

Задачи 9 и 10 выполняются перед задачей 8 (стенд), порядок: 1–7, 9, 10, 8.
