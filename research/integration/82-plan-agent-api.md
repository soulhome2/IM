# План 82. API агента по спецификации 0.5.1 — сервер и эмулятор

> **Для исполнителя:** скилл superpowers:subagent-driven-development (рекомендуется) или superpowers:executing-plans; шаги — чекбоксы `- [ ]`.

**Цель:** сервер МИ и эмулятор агента работают по спецификации `docs/agent-api/` 0.5.1: свой префикс `/api/v1/im-agent`, пинг, метка топологии, макрокоманды, команды длинным опросом, состояние устройств пачками, `422 error.event.unknown_source`.

**Архитектура:** методы агента — отдельный пакет `internal/im/handler/agentapi` со своим кодом из `docs/agent-api/agent.openapi.yaml`, как пакет оператора (ADR 002). Из `api/im/backend.openapi.yaml` методы агента убираются. Новая логика — `internal/im/appservice/agentlink/` (пинг, метка, макрокоманды, команды); хранение — новые миграции и файлы `storing/agent_link_queries.go`. Эмулятор переходит на новый клиент.

**Стек:** Go, gin, oapi-codegen v0.11.0 (`make gen-api-*`), Postgres, pgx; тесты — `internal/im/handler/test` на базе `IM_TEST_DB_URL`, стенд — сборка с тегом `imtest`.

**Спецификация:** `incident-manager-server/docs/agent-api/README.md` и `agent.openapi.yaml` (0.5.1). Номера пунктов ниже — пункты README.

## Решения (joynickray 2026-11-12)

- Работа — в отдельной рабочей копии: `git worktree add ../incident-manager-server-agent -b feature/im_agent_api feature/im_operator`. В `~/Work/incident-manager-server` идёт план 80, его не трогать. В конце — перенос на `feature/im_operator` (задача 9), только с согласия.
- Команду ставит **тестовый метод стенда** (сборка `imtest`). Шаг сценария и кнопка оператора — отдельная работа.
- Старые адреса агента под `/api/v1/im-backend` (`/sync/*`, `POST /events`) **убираются сразу**. `GET /events` (пользователь) и `GET /heartbeat` (жив ли сервер) в `backend` остаются.

## Решения плана (проверить при ревью)

- **D1. Шаг 4 (макрокоманды) обязателен для всех агентов**, у кого их нет — пустой список. Метка топологии сохраняется только после шага 4. Иначе сервер не знает, какой шаг последний (п. 6.2 говорит «3 или 4»). Правка README — в задаче 8.
- **D2. Метку стирает триггер базы**, а не код в каждом месте. Триггер на `source_types`, `source_event_types`, `sources`, `agent_macros` (INSERT/UPDATE/DELETE/TRUNCATE): если в транзакции не выставлено `SET LOCAL im.agent_sync = 'on'`, он обнуляет `agents.topology_etag` у заказчика. Сверки и `/sources/status` выставляют флаг. Так любая правка в обход агента — конфигуратор, восстановление копии, сброс стенда, ручной SQL — стирает метку, и ни одно место не забыто.
- **D3. `isOnline` из `/sources/status` метку не трогает**: метод выставляет флаг из D2.
- **D4. Длинный опрос без `LISTEN/NOTIFY`.** Каждый `GET /commands` один раз читает базу: так агент получает команды, накопленные, пока его не было, и команды, у которых кончилась аренда. Нет команд — запрос ждёт до `wait`, базу больше не читает. Новую команду `Enqueue` передаёт ждущему запросу внутри процесса (у сервера в памяти — список ждущих агентов). Обращений к базе — одно на запрос агента, раз в ~25 с. Ограничение: при нескольких экземплярах сервера команда, записанная не тем экземпляром, дойдёт только со следующим запросом (до 25 с), поэтому `LISTEN/NOTIFY` — **обязательное условие перед вторым экземпляром**, в техдолг.
- **D5. `429`/`503` сервер пока не отдаёт** — пределов нет (А-5). Эмулятор их уже понимает.
- **D6. Итог команды: первый побеждает.** Повтор любого итога после первого — `200` без изменений. Чужой или неизвестный `guid` — `404`.
- **D7. В контракте для генерации одна схема входа `Agent`**: генератор делает по мидлвару на схему, а `X-Dev-Agent` уже обрабатывается внутри мидлвара `Agent`. `DevAgent` остаётся в README, из `securitySchemes` уходит.

## Общие требования

- Префикс `/api/v1/im-agent`, тот же порт.
- Пинг: `intervalSec` по умолчанию **30** (настройка `IM_AGENT_HEARTBEAT_SEC`), «не на связи» — нет запросов **3 интервала**.
- `wait` у `/commands`: по умолчанию **25**, максимум **30**.
- `/sources/status`: не больше **5000** записей (`400` при превышении).
- Метка: строка до **128** символов, сравнение только на равенство.
- Статусы итога: `done`, `failed`, `expired`, `interrupted`, `unknown_macro`.
- Ключ ошибки события: `error.event.unknown_source`, код `422`.
- Каждая правка сервера — с тестом в `internal/im/handler/test`; полный прогон — `make test` и `make test-imtest` (имена целей — по `Makefile`).
- Перед каждым коммитом — сборка и выкладка на стенд (память «Deploy to stand before commit»): только в задаче 9, промежуточные коммиты — в ветке `feature/im_agent_api`.
- Сообщения коммитов — по-русски: `План 82, задача N: …`.

## Что легко упустить (ревью)

1. **Обнулили конфигурацию, а метка жива** — агент не перешлёт топологию. Тест: удалить устройство через конфигуратор → `topologyEtag` в пинге `null` (задача 3).
2. **Две выдачи одной команды за время аренды** — висящий опрос и новый опрос получают одно и то же. Тест: два параллельных `GET /commands` → команда только в одном ответе (задача 6).
3. **Команда агенту без `macros`** — копится навсегда. Тест: тестовый метод отвечает `409` (задача 6).
4. **Событие от устройства, удалённого сверкой** — `422 unknown_source`, а не `500`, и ничего не записано (задача 2).
5. **Эмулятор после `422 unknown_source` теряет событие** — оно должно уйти после сверки. Тест эмулятора (задача 8).

---

### Задача 0. Рабочая копия и план

- [ ] Создать рабочую копию (см. «Решения»), убедиться: `git -C ../incident-manager-server-agent status` — чисто, ветка `feature/im_agent_api`.
- [ ] Замер до правок: `make test` в рабочей копии — записать в план, сколько тестов и все ли зелёные.
- [ ] Коммит плана в IM: `План 82, задача 0: план API агента`.

### Задача 1. Пакет агента, свой префикс, старые адреса убраны

**Файлы:**
- Изменить: `docs/agent-api/agent.openapi.yaml` (D7: одна схема `Agent`; `servers` — только `/api/v1/im-agent`)
- Изменить: `api/im/backend.openapi.yaml` — убрать `/sync/sources/types`, `/sync/sources/event-types`, `/sync/sources`, `post` у `/events`, схемы `event`, `sync*`
- Изменить: `Makefile` — цель `gen-api-agent`: `oapi-codegen -package agentgen -generate custom-gin,custom-strict-server|spec|types|client` из `docs/agent-api/agent.openapi.yaml` в `internal/im/handler/agentapi/generated/`
- Создать: `internal/im/handler/agentapi/handler.go` (`Handler`, `Register`), `auth.go` (HMAC и `X-Dev-Agent` — перенос `AgentAuthMiddleWare` и `devAgentAuth` из `v1/auth_middleware.go`), `sync.go`, `event.go` (перенос из `v1/sync.go`, `v1/event.go`)
- Изменить: `internal/im/model/common.go` — `AgentBasePath = "/api/v1/im-agent"`
- Изменить: `internal/im/handler/handler.go` — `agentapi.Register(ginEngine, …, model.AgentBasePath)`
- Изменить: тесты `internal/im/handler/test` (`helpers.go`, `dev_agent_auth_test.go`, `agent_test.go`, `intake*_test.go`, `event_type_pair_test.go` и др.) — агентские вызовы через клиент `agentgen`

**Интерфейсы:**
- Даёт: `agentapi.NewHandler(appServices *appservice.AppServices, agentDevAuth bool) *Handler`; `agentapi.Register(e *gin.Engine, h *Handler, basePath string) error`; в тестах — `getAgentClient(h http.Handler) (*agentgen.ClientWithResponses, error)`.

- [ ] **Тест (красный):** `TestAgentRoutesMoved` — `POST /api/v1/im-agent/sync/sources/types` с `X-Dev-Agent` → `200`; `POST /api/v1/im-backend/sync/sources/types` → `404`; `POST /api/v1/im-backend/events` → `404` или `405`; `GET /api/v1/im-backend/events` с пользователем → `200`.
- [ ] `make test` по пакету — падает (нет маршрутов).
- [ ] Перенести код, сгенерировать (`make gen-api-agent gen-api-im`), подключить.
- [ ] `go build ./... && go vet ./...`; `TestAgentRoutesMoved` и все прежние тесты агента (`TestDevAgentAuth`, тесты сверки и приёма событий) — зелёные на новом клиенте.
- [ ] Коммит: `План 82, задача 1: методы агента в своём пакете и под /api/v1/im-agent`.

### Задача 2. Событие от неизвестного устройства — 422

**Файлы:**
- Изменить: `internal/util/apierror` — ключ `KeyEventUnknownSource = "error.event.unknown_source"`
- Изменить: `internal/im/appservice/event/event.go` — `ErrEntryNotFound` из `GetSourceByAgentAndUID` и `GetSourceEventTypeBySourceTypeAndUID` → `apierror.NewUnprocessable(KeyEventUnknownSource, …)`
- Тест: `internal/im/handler/test/agent_event_unknown_test.go`

- [ ] **Тест (красный):** `TestEventUnknownSource` — неизвестный `sourceUid` → `422`, `key == "error.event.unknown_source"`, в `events` нет строки с этим `guid`; известное устройство, неизвестный `eventTypeUid` → то же; устройство удалено сверкой → то же.
- [ ] Прогон — падает (`500`).
- [ ] Реализация.
- [ ] Прогон — зелёный; прежние тесты приёма событий зелёные.
- [ ] Коммит: `План 82, задача 2: событие от неизвестного устройства — 422 error.event.unknown_source`.

### Задача 3. Метка топологии и её стирание

**Файлы:**
- Создать: миграция `059_agent_link.sql` — `agents`: `topology_etag TEXT`, `last_seen_at TIMESTAMPTZ`, `capabilities TEXT[] NOT NULL DEFAULT '{}'`, `platform_online BOOLEAN`, `agent_version TEXT`, `queue_length INT`, `oldest_queued_at TIMESTAMPTZ`; функция и триггеры D2 на `source_types`, `source_event_types`, `sources` (на `agent_macros` — в задаче 5)
- Создать: `internal/im/service/storing/agent_link_queries.go` — `SetTopologyEtag(ctx, agentGUID uuid.UUID, etag *string) error`, `GetAgentLink(ctx, agentGUID) (*model.AgentLink, error)`, `MarkAgentSync(ctx) error` (выполняет `SET LOCAL im.agent_sync = 'on'` в текущей транзакции)
- Изменить: `internal/im/appservice/sync/*.go` — каждая сверка в одной транзакции (`transactor.DoInTx`) с `MarkAgentSync`; читает заголовок `Topology-Etag` (передаётся из обработчика параметром `etag *string`)
- Тест: `internal/im/handler/test/agent_etag_test.go`

**Интерфейсы:**
- Даёт: `model.AgentLink{TopologyEtag *string; LastSeenAt *time.Time; Capabilities []string; PlatformOnline *bool; AgentVersion string; QueueLength *int; OldestQueuedAt *time.Time}`.

- [ ] **Тест (красный):** `TestTopologyEtagStoredAfterLastStep` — шаги 1–3 с `Topology-Etag: e1` → в базе `NULL`; шаг 4 (пустой, после задачи 5 — здесь вызвать прямо `SetTopologyEtag` нельзя; до задачи 5 тест помечен `t.Skip("задача 5")` для шага 4) → `e1`.
  `TestTopologyEtagForgottenOnBypass` — метка `e1` выставлена; удалить устройство методом конфигуратора → `NULL`; снова `e1`, удалить тип устройства → `NULL`; снова `e1`, восстановить копию настроек → `NULL`; снова `e1`, сверка устройств (флаг выставлен) → метка не стёрта.
  `TestTopologyEtagTooLong` — 129 символов → `400`.
- [ ] Прогон — падает.
- [ ] Миграция, запросы, сверки в транзакции.
- [ ] Прогон — зелёный (кроме пропуска до задачи 5); `TestMigration*` и прежние тесты сверки зелёные.
- [ ] Коммит: `План 82, задача 3: метка топологии, стирание при правке в обход агента`.

### Задача 4. Пинг и «на связи»

**Файлы:**
- Создать: `internal/im/handler/agentapi/heartbeat.go`; `internal/im/appservice/agentlink/heartbeat.go` — `Heartbeat(ctx, agent *model.Agent, in model.HeartbeatIn) (model.HeartbeatOut, error)`
- Изменить: `agentapi/auth.go` — после успешного входа `TouchAgent(ctx, agentGUID)`: `UPDATE agents SET last_seen_at = now() WHERE guid = $1 AND (last_seen_at IS NULL OR last_seen_at < now() - interval '5 seconds')`
- Изменить: `internal/im/model/config.go` — `AgentHeartbeatSec int envconfig:"IM_AGENT_HEARTBEAT_SEC" default:"30"`
- Изменить: `api/im/backend.openapi.yaml` `GET /agents` — поля `lastSeenAt`, `online` (`online|offline|unknown`: `offline` — нет запросов `3 × интервал`; `unknown` — `platformOnline == false`), `capabilities`
- Тест: `internal/im/handler/test/agent_heartbeat_test.go`

- [ ] **Тест (красный):** `TestHeartbeat` — ответ `intervalSec == 30`, `topologyEtag == nil` до сверки; после шагов 1–4 с `e1` — `"e1"`; поля `capabilities`, `platformOnline`, `agentVersion`, `queueLength` сохранены. `TestAgentOnline` — `last_seen_at` сдвинут на 91 с назад → в `GET /agents` `online == "offline"`; пинг → `"online"`; пинг с `platformOnline: false` → `"unknown"`. `TestTouchThrottled` — два запроса подряд → одно обновление `last_seen_at` (счётчик SQL `sqlCounter`).
- [ ] Прогон — падает.
- [ ] Реализация.
- [ ] Прогон — зелёный.
- [ ] Коммит: `План 82, задача 4: пинг, время последнего запроса агента, состояние «на связи»`.

### Задача 5. Макрокоманды и состояние устройств

**Файлы:**
- Создать: миграция `060_agent_macros.sql` — `agent_macros(guid UUID PK, customer_guid, agent_guid REFERENCES agents, uid TEXT, name TEXT, deleted_at TIMESTAMPTZ, UNIQUE(agent_guid, uid) WHERE deleted_at IS NULL)`; триггер D2
- Создать: `internal/im/appservice/agentlink/macros.go` — `SyncMacros(ctx, agent, items []model.SyncMacro, etag *string) error` (как `SyncSources`: новое заводит, известное — имя, пропавшее — `deleted_at`; в конце `SetTopologyEtag`); `agentlink/status.go` — `PutSourcesStatus(ctx, agent, items []model.SourceStatus) error`
- Создать: `agentapi/macros.go`, `agentapi/status.go`
- Изменить: `appservice/sync/sync_source.go` — метка больше не пишется на шаге 3 (D1)
- Тест: `agent_macros_test.go`, `agent_status_test.go`; снять `t.Skip` из задачи 3

- [ ] **Тест (красный):** `TestSyncMacros` — завёл две; вторая сверка без одной → она `deleted_at`; одинаковый `uid` у двух агентов — две строки; метка выставлена после шага 4. `TestSourcesStatus` — `[{cam-01,false}]` → `is_online == false`, метка не стёрта (D3); неизвестный `uid` пропущен, `200`; 5001 запись → `400`.
- [ ] Прогон — падает.
- [ ] Реализация.
- [ ] Прогон — зелёный, включая `TestTopologyEtagStoredAfterLastStep`.
- [ ] Коммит: `План 82, задача 5: макрокоманды агента и состояние устройств пачками`.

### Задача 6. Команды: очередь, длинный опрос, итог, тестовый метод

**Файлы:**
- Создать: миграция `061_agent_commands.sql` — `agent_commands(guid UUID PK, customer_guid, agent_guid, macro_guid REFERENCES agent_macros, created_at, expires_at, ttl_sec INT, lease_sec INT, lease_until TIMESTAMPTZ, status TEXT NOT NULL DEFAULT 'queued', message TEXT, result_at TIMESTAMPTZ, reason_incident_guid UUID)`, индекс `(agent_guid, status, created_at)`
- Создать: `agentlink/commands.go`:
  - `Enqueue(ctx, agentGUID uuid.UUID, macroUID string, ttlSec int, reasonIncident *uuid.UUID) (*model.Command, error)` — `409 error.command.no_macros`, если у агента нет `macros` в `capabilities`; `404`, если макрокоманды нет; будит опрос агента
  - `Take(ctx, agent, wait time.Duration) ([]*model.Command, error)` — `SELECT … WHERE status='queued' AND expires_at > now() AND (lease_until IS NULL OR lease_until < now()) ORDER BY created_at FOR UPDATE SKIP LOCKED`, выставляет `lease_until = now() + lease_sec`; пусто — ждёт до `wait` сигнала от `Enqueue` внутри процесса, базу больше не читает (D4)
  - `Result(ctx, agent, guid uuid.UUID, status string, message string) error` — D6
  - `ExpireSweep(ctx) (int, error)` — `queued` с `expires_at < now()` → `expired`; вызывается тикером раз в 10 с в `AppServices.Start`
- Создать: `agentapi/commands.go`
- Изменить (сборка `imtest`): стенд — `POST /test/agents/{guid}/commands` `{macroUid, ttlSec}` → `Enqueue`; `GET /test/commands/{guid}` → строка команды. По образцу `handler/operator/teststand.go`
- Тест: `agent_commands_test.go` (тег `imtest` для тестового метода)

Значения: `leaseSec` = 30, `ttlSec` по умолчанию 120.

- [ ] **Тест (красный):** `TestCommandDelivered` — опрос висит, `Enqueue` → ответ меньше чем за 1 с, одна команда, поля `ttlSec`, `leaseSec`, `expiresAt`. `TestCommandLease` — `Take` дважды подряд → второй пуст; через `lease_until` в прошлом → выдана снова. `TestCommandParallelPolls` — два `GET /commands` одновременно → команда ровно в одном ответе. `TestCommandResultFirstWins` — `done`, затем `failed` → `200`, в базе `done`; чужой `guid` → `404`. `TestCommandExpire` — `expires_at` в прошлом, `ExpireSweep` → `expired`, `Take` её не отдаёт. `TestEnqueueNoMacros` — агент без `macros` → `409`. `TestCommandWaitCap` — `wait=60` → `400`; пустой ответ через ~`wait`.
- [ ] Прогон — падает.
- [ ] Реализация.
- [ ] Прогон — зелёный, `go test -race`.
- [ ] Коммит: `План 82, задача 6: команды агенту — очередь, длинный опрос, аренда, итог; тестовый метод стенда`.

### Задача 7. Эмулятор по спецификации

**Файлы:**
- Изменить: `tools/agent-emulator/run.go`, `main.go`, `replay.go`, `data.go` — клиент `agentgen`, префикс из ключа `-prefix` (по умолчанию `/api/v1/im-agent`); прежние команды (`enroll`, `sync`, `event`, `replay`) — тоже на новый клиент
- Создать: `tools/agent-emulator/link.go` — пинг, метка, команды:
  - метка = SHA-256 от JSON `{sourceTypes, eventTypes, sources без isOnline, macros}`, списки отсортированы по `uid`; `Topology-Etag` во всех сверках; шаг 4 всегда (D1)
  - пинг раз в `intervalSec` из ответа; `capabilities: ["macros","status"]`, `platformOnline: true`; метка не совпала — сверка
  - опрос `GET /commands?wait=25`; команда → журнал `<state-dir>/commands.jsonl` («начал» до, итог после); печать `Агент выполняет макрокоманду «<name>» (<uid>)`; `failMacros` из файла — `failed`; просрочка по `ttlSec` от получения — `expired`; «начал» без итога после перезапуска — `interrupted`; неизвестная макрокоманда — `unknown_macro` и сверка
  - событие: `422 unknown_source` → сверка, затем повтор того же `guid`; `429`/`503` — пауза `Retry-After`, иначе 1, 2, 4 … 60 с
- Изменить: `testdata/agent-emulator.json` — `macros: [{uid,name}]`, `failMacros: []`; `README.md` эмулятора
- Тест: `tools/agent-emulator/link_test.go` (на `httptest.Server` с подменным сервером)

- [ ] **Тест (красный):** `TestEtagStable` — тот же файл → та же метка; другой `isOnline` → та же; другое имя → другая. `TestCommandOnce` — сервер отдаёт одну команду дважды → выполнена один раз, итог отправлен дважды. `TestInterruptedAfterRestart` — журнал с «начал» без итога → `interrupted`, не выполнена. `TestFailMacros` — `failed`. `TestUnknownSourceResync` — первое событие `422 unknown_source` → сверки 1–4, затем то же событие с тем же `guid`. `TestRetryAfter` — `503` + `Retry-After: 2` → повтор не раньше 2 с.
- [ ] Прогон — падает.
- [ ] Реализация.
- [ ] Прогон — зелёный; `go test ./tools/agent-emulator/...`.
- [ ] Ручная проверка на стенде из задачи 9 — там же.
- [ ] Коммит: `План 82, задача 7: эмулятор — новый адрес, пинг, метка, макрокоманды и команды`.

### Задача 8. Спецификация и техдолг

**Файлы:**
- Изменить: `docs/agent-api/README.md` — раздел 2 (всё «работает», кроме `429/503`), разделы 5 (адрес — сделан), 6.1 (D1: шаг 4 обязателен, пустой список), 6.6 (D4: база читается раз на запрос; несколько экземпляров — только после `LISTEN/NOTIFY`), 9.1 (снять пп. 1, 5), 9.2 (оставить вход, `429/503`, `LISTEN/NOTIFY`), 10 (эмулятор умеет пинг, метку, команды, повтор после `422`); `agent.openapi.yaml` — снять `x-status: planned`; `CHANGELOG.md` — 0.6.0
- Изменить (репозиторий IM): `research/integration/TECH-DEBT.md` — А-1 и А-6 закрыты с хэшами; новые строки: `LISTEN/NOTIFY` для нескольких экземпляров (D4), пределы и `429/503` (D5, к А-5)

- [ ] Правки; `npx @redocly/cli@1.25.0 lint docs/agent-api/agent.openapi.yaml` — без ошибок; `python3 tools/check_links.py` в IM — 0 нерабочих.
- [ ] Коммит в сервер: `План 82, задача 8: спецификация 0.6.0 — сделанное отмечено`; в IM: `План 82: техдолг агента обновлён`.

### Задача 9. Стенд, полный прогон, перенос

- [ ] `make test` и тесты с тегом `imtest` — все зелёные; сравнить с замером задачи 0.
- [ ] Собрать сервер, выложить на стенд (как в памяти «Stand serves built IM» / `deploy/README.md`), сервер с `IM_AGENT_DEV_AUTH=true`.
- [ ] На стенде эмулятором пройти проверки README раздела 8: T1–T15, T20–T29, T22b–T22d. Итог — таблицей в этот план.
- [ ] Показать joynickray стенд и итог; после согласия — `git rebase feature/im_operator` в рабочей копии, затем в основной копии `git merge --ff-only feature/im_agent_api` (когда план 80 закоммичен); удалить рабочую копию.
- [ ] Отметить план выполненным.
