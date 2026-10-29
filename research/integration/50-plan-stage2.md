# Этап 2: каркас операторского API — план работ

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Сервер МИ отдаёт все 50 операций контракта оператора на том же gin, что и API настройки: вход через облако, ошибки `problem+json`, 501 на нереализованном и настоящий `GET /operator/session` с 14 правами машины.

**Architecture:** Второй пакет `operatorgen` генерируется тем же форком `oapi-codegen` v0.11.0 из копии контракта `api/im/operator/openapi.v30.json` и регистрируется в `handler.GetHandler` рядом с `v1` под `/api/v1/im-backend`. Рукописный пакет `internal/im/handler/operator` реализует `ServerInterface` (не strict): вход — через `v1.Handler.AuthenticateUser`, ошибки параметров — свой `ErrorHandler` (400/428), заглушки — 501. Каталог прав сервера становится ровно 14 правами машины; старые маршруты инцидентов пускают по любому из них.

**Tech Stack:** Go 1.27.1, gin 1.11, форк `src.axxonsoft.dev/bitbucket/proj/oapi-codegen` v0.11.0, testify `require`, PostgreSQL 9.6 (Docker), golangci-lint v2.14.0.

**Spec:** [40-plan.md, «2. Каркас операторского API»](40-plan.md#2-каркас-операторского-api--сервер-ми-m) и таблица «Решения» там же; требования к серверу — [BACKEND.md](../../Specification/Workflow_machine/BACKEND.md); контракт — [openapi.v30.json](../../Specification/Workflow_machine/openapi.v30.json); факты о сервере — [03](03-im-server.md), [10, п. 6–7](10-permissions.md), [14, п. 5](14-im-backend-operator.md), [20, разд. 9](20-decisions.md), стенд — [30](30-local-stand.md).

## Global Constraints

- Код — `~/Work/incident-manager-server`, ветка `feature/im_operator`. Пути ниже — от корня этого репозитория, если не сказано иное. Документы — репозиторий IM, ветка `feature/im_operator`.
- Только локально, на стенде из [30](30-local-stand.md). Push — только по просьбе пользователя. `~/Work/axxoncloudgo` не менять; если кажется, что нужна правка облака, — **стоп, спросить пользователя**.
- Вход отложен: тестовый пользователь `test@axxonnet.test`. «Принимать только access-токен» **не делать**, обработку токена (`internal/externalclient/cloud/client.go`, introspect, мемоизация) не менять.
- Тот же процесс `cmd/im`, тот же `gin.Engine`, `BasePath` = `/api/v1/im-backend` (`model.BasePath`).
- Генератор — только форк `src.axxonsoft.dev/bitbucket/proj/oapi-codegen@v0.11.0`; сгенерированные файлы руками не править. `make gen` и `make gen-api-im` не запускать: сгенерированный код `v1` отстал от `backend.openapi.yaml` (ответы 400), перегенерация поменяет `v1` — вне этапа.
- Перед любой командой `go` — `source ~/go/offline-env.sh`. Адрес `npm.itvgroup.ru` недоступен, не использовать.
- Docker — только через `sg docker -c "…"` (пользователь не в группе `docker` в этой сессии).
- Ошибки новых маршрутов (`/operator/*`, `/test/*`) — `Content-Type: application/problem+json`, тело `Problem` контракта (`code`, `message`, по возможности `messageKey`). Старые маршруты — по-прежнему `{key, description}` с `application/json`.
- Коды ошибок — из `Problem.code` контракта. Кодов для 401, 400 и 501 в контракте нет; сервер использует свои: `UNAUTHENTICATED` (401), `BAD_REQUEST` (400), `NOT_IMPLEMENTED` (501) — открытый вопрос, см. конец.
- Версия записи: `ETag` = версия в кавычках (`"12"`); нет `If-Match` → `428 PRECONDITION_REQUIRED` (`messageKey` `workflow.error.precondition_required`); не совпала → `412 VERSION_CONFLICT` (`workflow.error.version_conflict`) с полем `current`. Разбор `If-Match` — как `versionProblem` в `prototype/server.js`: список через запятую, `W/` отбрасывается, `*` подходит.
- Нереализованные операции → `501` `problem+json` `NOT_IMPLEMENTED`. Настоящая в этом этапе одна — `GET /operator/session`. `/test/*` наследуют `bearerAuth` и тоже отвечают 501.
- Числа операций в плане (49 заглушек, 50 маршрутов) — по контракту до ARCH-15.10. ARCH-15.10 добавила шестую операцию стенда `POST /test/operators/{operatorId}/incidents/{incidentGuid}/transitions/{transitionId}`. Брать число из копии контракта на момент копирования (задача 2), тесты считают операции по сгенерированному интерфейсу, а не по числу из плана.
- Каталог прав — ровно 14 имён из `permissions[].cloud` машины. UUID прежних прав не менять; `incident_manager.incidents.assign` → `incident_manager.incidents.assign.own` **с тем же UUID** `019f93e1-2f6a-7d8b-4c9a-3e7f6b1a8d2c`; `incidents.filter.edit` и `incidents.track` убрать (решение №2, BACKEND.md «Каталог прав»). `manage` — не надмножество операторских прав (решение №3).
- Идемпотентность: ключ — поле тела `idempotencyKey`, хранить 10 минут. В этапе 2 — только механизм (интерфейс + хранилище в памяти + тесты); подключение к операциям — этап 4.
- Код — в рамках `.golangci.yml`: `funlen` 120 строк / 60 операторов, `dupl` 150, `gosec`, `errorlint` (`errors.Is`/`errors.As`). Если golangci-lint поставился (задача 1) — `golangci-lint run ./...` в каждой задаче; иначе `go vet ./...` и пометка «lint — в CI».
- Тесты — testify `require`. Новые тесты пакета `operator` — в процессе (`httptest` + gin), без базы. Тесты с базой — через локальный Postgres из задачи 1.
- Комментарии в коде и ADR — по-английски, как в репозитории; документы IM — по-русски, простыми словами.
- Коммит — один на задачу, сообщение по-русски. Сообщение пишется инструментом записи файла в `.git/COMMIT_MSG_STAGE2` (без heredoc), последняя строка — `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`; затем `git commit -q -F .git/COMMIT_MSG_STAGE2`. Команды Bash — в одну строку.

## Review Focus

1. **Запрос без токена на `/operator/*`, у которого к тому же нет `If-Match` или кривой `incidentGuid`,** должен получить 401, а не 428/400: вход раньше разбора параметров. Тест — задача 5, `TestAuthRunsBeforeParams`.
2. **Конфигуратор разбирает `key` в ошибках старых маршрутов.** 401 на `GET /incidents` и 404 на неизвестный путь вне `/operator` должны остаться прежними, не `problem+json`. Тесты — задача 5, `TestUnknownPathOutsideOperatorKeepsGinDefault` и `TestOldRoutesKeepKeyErrors`.
3. **Сессия у пользователя без прав МИ или только с `manage`:** `permissions` — `[]`, а не `null` (схема требует массив); только `manage` → только `incident:schema:admin`; чужие имена (`core.*`, убранные `track`) не попадают. Тесты — задача 6.
4. **Облако отвергло каталог → сервер не стартует** (регистрация при старте обязательна): имя не по правилам облака, повтор UUID, UUID убранного права. Тест — задача 3, `TestCatalogNamesFollowCloudRules`, `TestPermissionUUIDs`.
5. **Двойное нажатие — два одновременных запроса с одним ключом:** действие выполняется один раз, второй получает тот же ответ; ответ 5xx не запоминается. Тесты — задача 8.

---

## Структура файлов

| Файл | Что | Задача |
|---|---|---|
| `Makefile` | `test-db-up`, `test-db-down`, `test-local`; `IM_REPO`, `GEN_GOPROXY`, `OAPI_CODEGEN`; `vendor-operator-contract`, `gen-api-operator` | 1, 2 |
| `internal/im/handler/test/common.go` | `IM_TEST_DB_URL` поверх `testing.env`; общий `http.Handler` для новых тестов | 1, 5 |
| `api/im/operator/{openapi.v30.json, workflow_schema.v1.json, strings/en.json, strings/ru.json, SOURCE}` | копия контракта, машины и строк из IM | 2 |
| `api/im/operator/embed.go` | пакет `operatorapi`: файлы копии через `go:embed` | 2 |
| `internal/im/handler/operator/generated/{server,spec,types,client}.go` | сгенерировано, пакет `operatorgen` | 2 |
| `internal/im/handler/operator/generated/auth_adapter.go` | рукописный адаптер `bearerAuth` | 2 |
| `internal/im/handler/operator/generated/contract_test.go` | встроенная спецификация = копия | 2 |
| `internal/im/model/permission.go`, `permissions_info.go`, `permission_catalog.go` (+ тесты) | 14 прав, таблица «ключ машины ↔ имя облака», дерево каталога; `Has` без надмножества | 3, 6, 7 |
| `internal/im/handler/operator/problem.go`, `version.go` (+ тесты) | запись `Problem`, `ETag`, `If-Match`, 412/428 | 4 |
| `internal/im/handler/operator/{handler.go, auth.go, params.go, notfound.go, stubs.go, session.go}` (+ тесты) | пакет оператора | 5, 6 |
| `internal/im/handler/v1/auth_middleware.go` | `AuthenticateUser` для обоих пакетов | 5 |
| `internal/im/handler/handler.go` | регистрация `operator` и `NoRoute` | 5 |
| `.golangci.yml` | `dupl` не проверяет `stubs.go` | 5 |
| `internal/im/appservice/incident/incident.go`, `internal/im/handler/v1/incident_client.go` | права старых маршрутов | 7 |
| `internal/im/handler/operator/idempotency/{store.go, memory.go, memory_test.go}` | ключи повтора | 8 |
| `docs/adr/002-operator-api-package.md` | решения этапа | 9 |
| `~/Work/stand/{sync-im-proto.sh, grant-im-permissions.sh, check-operator-api.sh}` | стенд, вне репозиториев | 9 |
| IM: `research/integration/30-local-stand.md`, `40-plan.md` | шаг 4 стенда, отметка этапа | 9 |

---

### Task 1: Локальный прогон тестов сервера

Сейчас тесты обработчиков ищут Postgres на хосте `db` (`internal/im/tools/env/testing.env`), а загрузчик настроек перезаписывает переменные окружения значениями из файла (`addVarsFromFileToEnvironment` — `os.Setenv`), так что подменить адрес снаружи нельзя. Базу стенда (`imdb` в `ac_db`) для тестов не брать: тесты чистят таблицы.

**Files:**
- Modify: `internal/im/handler/test/common.go` (`setupTesting`)
- Modify: `Makefile`

**Interfaces:**
- Produces: `IM_TEST_DB_URL` — если задана, `Config.DBURL` берётся из неё. Цели `make test-db-up`, `make test-db-down`, `make test-local`. Переменные Makefile: `TEST_DB_CONTAINER ?= im-test-db`, `TEST_DB_PORT ?= 55432`, `TEST_DB_URL ?= postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable`.

- [x] **Step 1: Убедиться, что тесты с базой сейчас не идут**

Run: `cd ~/Work/incident-manager-server && source ~/go/offline-env.sh && go test ./internal/im/handler/test/ 2>&1 | tail -5`
Expected: FAIL — ошибка подключения к `db:5432` (хост не найден).

- [x] **Step 2: Подмена адреса базы в `setupTesting`**

После `configuring.GetConfig(...)`: если `os.Getenv("IM_TEST_DB_URL") != ""` — `Config.DBURL` = это значение. Остальное не трогать.

- [x] **Step 3: Цели Makefile**

- `test-db-up`: `docker start $(TEST_DB_CONTAINER)` или, если контейнера нет, `docker run -d --name $(TEST_DB_CONTAINER) -e POSTGRES_HOST_AUTH_METHOD=trust -p 127.0.0.1:$(TEST_DB_PORT):5432 postgres:9.6` (как `prepare-test`, образ уже загружен; порт только на `127.0.0.1` — машина видна в домашней сети); затем ждать `docker exec $(TEST_DB_CONTAINER) pg_isready -U postgres` (до 30 с).
- `test-db-down`: `docker rm -f $(TEST_DB_CONTAINER)`.
- `test-local`: `IM_TEST_DB_URL='$(TEST_DB_URL)' go test ./...` — без `GOPROXY` из Makefile; окружение Go — от вызывающего.

- [x] **Step 4: Прогнать все тесты — исходная точка**

Run: `cd ~/Work/incident-manager-server && sg docker -c "make test-db-up" && source ~/go/offline-env.sh && make test-local 2>&1 | tail -30`
Expected: PASS всех пакетов. Если какой-то тест падает и без наших правок — **не чинить**: записать имя и причину в отчёт задачи и спросить пользователя, идти ли дальше.

- [x] **Step 5: golangci-lint из модулей**

Run: `cd ~/Work/incident-manager-server && source ~/go/offline-env.sh && GOTOOLCHAIN=go1.27.1 go install github.com/golangci/golangci-lint/v2/cmd/golangci-lint@v2.14.0 && golangci-lint version && golangci-lint run ./... 2>&1 | tail -5`
Expected: версия 2.14.0, собранная go1.27.1; `golangci-lint run` — без замечаний (или записать замечания, которые были до нас). Не поставился (нет сети до proxy.golang.org) — дальше `go vet ./...`, lint — в CI; так и записать в отчёт.

- [x] **Step 6: Commit**

Сообщение: «Этап 2: тесты сервера локально — Postgres 9.6 в Docker и IM_TEST_DB_URL».
Run: `git add Makefile internal/im/handler/test/common.go && git commit -q -F .git/COMMIT_MSG_STAGE2`

---

### Task 2: Копия контракта и офлайн-генерация пакета `operatorgen`

Решение по `bearerAuth`: **рукописный адаптер в каталоге сгенерированного пакета.** Генератор из схемы `bearerAuth` делает неэкспортируемый метод `bearerAuthAuthMiddleWare` в интерфейсе `AuthMiddleWares` — реализовать его может только тип из того же пакета. Адаптер — пять строк, копия контракта остаётся байт в байт как в IM (обновление — простое копирование, проверка — сравнение), встроенная спецификация совпадает с контрактом. Переименование схемы в производной копии добавило бы шаг преобразования и расхождение с IM; правка самого контракта IM ради генератора не нужна.

**Files:**
- Modify: `Makefile`
- Create: `api/im/operator/openapi.v30.json`, `workflow_schema.v1.json`, `strings/en.json`, `strings/ru.json`, `SOURCE` (создаёт `make vendor-operator-contract`)
- Create: `api/im/operator/embed.go`
- Create: `internal/im/handler/operator/generated/{server,spec,types,client}.go` (создаёт `make gen-api-operator`)
- Create: `internal/im/handler/operator/generated/auth_adapter.go`
- Test: `internal/im/handler/operator/generated/contract_test.go`

**Interfaces:**
- Produces:
  - пакет `operatorapi` (`api/im/operator`): `var Contract, Machine, StringsEN, StringsRU []byte` (`//go:embed`);
  - пакет `operatorgen`: всё, что генерирует форк (`ServerInterface`, `RegisterHandlersWithOptions(router gin.IRouter, auth AuthMiddleWares, si ServerInterface, opts GinServerOptions)`, `GinServerOptions{BaseURL, Middlewares, ErrorHandler}`, `Problem`, `ProblemCode*`, `OperatorSession`, `OperatorSessionAgentStateOffline`, …);
  - `type BearerAuth gin.HandlerFunc` с методом `bearerAuthAuthMiddleWare(c *gin.Context)` — вызывает саму функцию.

- [x] **Step 1: Переменные и цели Makefile**

- `IM_REPO ?= /mnt/hgfs/VmWareShared/soul2home/IM`, `GEN_GOPROXY ?= http://npm.itvgroup.ru:3000`, `OAPI_CODEGEN ?= oapi-codegen`, `OP_GEN_DIR := internal/im/handler/operator/generated`.
- `get-generator`: `$(OAPI_CODEGEN) --version || GOSUMDB=off GOPROXY=$(GEN_GOPROXY) go install src.axxonsoft.dev/bitbucket/proj/oapi-codegen/cmd/oapi-codegen@v0.11.0`. Локально: `make get-generator GEN_GOPROXY="$GOPROXY"` после `source ~/go/offline-env.sh` (проверено: ставится из `~/go/offline-proxy` без сети).
- `vendor-operator-contract`: `install -m 644` четырёх файлов из `$(IM_REPO)/Specification/Workflow_machine/` в `api/im/operator/` (строки — в `strings/`); в `SOURCE` — строка `git -C $(IM_REPO) rev-parse --short HEAD` и `dirty`, если `git -C $(IM_REPO) status --porcelain -- Specification/Workflow_machine` не пуст.
- `gen-api-operator`: `rm -f` ровно четырёх файлов `$(OP_GEN_DIR)/{server,spec,types,client}.go` (не `*.go` — иначе пропадут адаптер и тест), затем четыре вызова `$(OAPI_CODEGEN) -package operatorgen` с теми же `-generate`, что у `gen-api-im` (`custom-gin,custom-strict-server` → `server.go`; `spec`; `types`; `client`), источник `api/im/operator/openapi.v30.json`.
- `gen: get-generator gen-api-im gen-api-operator`.

- [x] **Step 2: Копия и генерация**

Run: `cd ~/Work/incident-manager-server && source ~/go/offline-env.sh && make get-generator GEN_GOPROXY="$GOPROXY" && make vendor-operator-contract && make gen-api-operator && cat api/im/operator/SOURCE`
Expected: четыре файла в `$(OP_GEN_DIR)` с `package operatorgen`, в `SOURCE` — короткий хэш IM.

- [x] **Step 3: `embed.go` и `auth_adapter.go`**

`embed.go`: `package operatorapi`, четыре `//go:embed`. `auth_adapter.go`: шапка «Hand-written, not generated: gen-api-operator removes only server/spec/types/client.go», тип `BearerAuth` и метод. 

- [x] **Step 4: Тест копии**

```go
// operations — отсортированные "METHOD /path" из JSON контракта
func TestEmbeddedSpecMatchesVendoredContract(t *testing.T) {
	raw, err := decodeSpec()
	require.NoError(t, err)
	require.Equal(t, operations(t, operatorapi.Contract), operations(t, raw))
	require.Len(t, operations(t, raw), 50)
}

func TestBearerAuthAdapterCallsHandler(t *testing.T) {
	called := false
	var mw AuthMiddleWares = BearerAuth(func(*gin.Context) { called = true })
	mw.bearerAuthAuthMiddleWare(&gin.Context{})
	require.True(t, called)
}
```

- [x] **Step 5: Тест проходит, генерация повторяема**

Run: `go test ./internal/im/handler/operator/generated/ && go build ./... && sha256sum internal/im/handler/operator/generated/*.go > .git/gen.sha256 && make gen-api-operator && sha256sum -c --quiet .git/gen.sha256 && echo same`
Expected: PASS, сборка без ошибок, `same` (повторная генерация даёт те же файлы, адаптер и тест на месте).

- [x] **Step 6: Commit**

Сообщение: «Этап 2: копия контракта оператора из IM и пакет operatorgen, генерация без сети».
Run: `git add Makefile api/im/operator internal/im/handler/operator/generated && git commit -q -F .git/COMMIT_MSG_STAGE2`

---

### Task 3: Каталог прав — 14 прав машины

**Files:**
- Modify: `internal/im/model/permission.go`, `permissions_info.go`, `permission_catalog.go`
- Modify: `internal/im/model/permission_catalog_test.go`
- Create: `internal/im/model/permission_machine_test.go`

**Interfaces:**
- Consumes: `operatorapi.Machine`, `operatorapi.StringsEN`, `operatorapi.StringsRU` (задача 2) — только в тестах.
- Produces:
  - константы: прежние `PermManage`, `PermIncidentsTakeOwn`, `PermIncidentsTakeAny`, `PermIncidentsClose`, `PermIncidentsSuspend`, `PermIncidentsProcess`; `PermIncidentsAssign` → `PermIncidentsAssignOwn`; новые `PermIncidentsAssignAny`, `PermIncidentsReleaseUse`, `PermIncidentsUnprocessedClose`, `PermIncidentsReopenUse`, `PermIncidentsBulkUse`, `PermIncidentsActionsRun`, `PermAgentNotReadyUse`; убрать `PermIncidentsFilterEdit`, `PermIncidentsTrack` (в коде не используются — проверено);
  - `type MachinePermission struct { Key string; Cloud Permission }` и `var MachinePermissions []MachinePermission` — 14 пар в порядке `permissions[]` машины (от `incident:claim` до `agent:set_not_ready`);
  - `CatalogI18nText` получает `Description string \`json:"description,omitempty"\`` (облако принимает `title` и `description`, `validateI18n` в `axxoncloudgo/model/permissions/methods.go`).

Значения:

| Имя облака | UUID | Заголовок en / ru |
|---|---|---|
| `incident_manager.manage` | прежний `019f93c7-2e0e-7705-8936-3520b96beca8` | прежний |
| `…incidents.take.own` | прежний `019f93d2-4a1b-7e3c-9d45-8f2a1c6b3e7d` | прежний |
| `…incidents.take.any` | прежний `019f93d5-7b2c-7f4d-8e56-9a3b2d7c4f8e` | прежний |
| `…incidents.close` | прежний `019f93d8-9c3d-7a5e-7f67-0b4c3e8d5a9f` | прежний |
| `…incidents.suspend` | прежний `019f93e4-3a7b-7e9c-3d0b-4f8a7c2b9e3d` | прежний |
| `…incidents.process` | прежний `019f93e7-4b8c-7f0d-2e1c-5a9b8d3c0f4e` | прежний |
| `…incidents.assign.own` | **от `assign`** `019f93e1-2f6a-7d8b-4c9a-3e7f6b1a8d2c` | Transfer own incidents / Передавать свои |
| `…incidents.assign.any` | `01a1849a-1893-711a-a931-8449f76a9418` | Transfer any incidents / Передавать чужие |
| `…incidents.release.use` | `01a1849a-1893-711a-a931-844a3ec58d28` | Return to queue / Возвращать в очередь |
| `…incidents.unprocessed.close` | `01a1849a-1893-711a-a931-844ba4085de5` | Close as mass failure / Закрывать массовым сбоем |
| `…incidents.reopen.use` | `01a1849a-1893-711a-a931-844c947935fb` | Reopen incidents / Переоткрывать |
| `…incidents.bulk.use` | `01a1849a-1893-711a-a931-844dc48286de` | Handle several as one / Обрабатывать несколько как один |
| `…incidents.actions.run` | `01a1849a-1893-711a-a931-844efe63553d` | Run macros and commands / Запускать макросы и команды |
| `…agent.not_ready.use` | `01a1849a-1893-711a-a931-844fa4b5c3ce` | Take a break / Уходить на перерыв |

Дерево: `incident_manager` → `incident_manager.administration` (`manage`), `incident_manager.incidents` (12 прав `incidents.*` в порядке машины), новая группа `incident_manager.agent` — «Operator state» / «Состояние оператора» (`agent.not_ready.use`). У каждого права `i18n.<lang>.description` — текст `labelKey` права машины из `strings/<lang>.json` (BACKEND.md «Каталог прав»: подпись из каталога строк); `title` — короткий, из таблицы, чтобы список прав в ролях облака читался.

- [x] **Step 1: Тесты против копии машины и правил облака**

```go
func TestCatalogMatchesMachinePermissions(t *testing.T) {
	// имена прав в дереве каталога == множество permissions[].cloud из operatorapi.Machine, 14 штук
	require.ElementsMatch(t, machineCloudNames(t), catalogPermissionNames(PermissionCatalog()))
	require.Len(t, AllPermissionsInfo, 14)
}

func TestMachinePermissionsTable(t *testing.T) {
	// MachinePermissions == permissions[] машины: те же пары key/cloud в том же порядке
	require.Equal(t, machinePairs(t), MachinePermissions)
}

func TestPermissionUUIDs(t *testing.T) {
	// шесть прежних — литералами из таблицы выше; assign.own == "019f93e1-2f6a-7d8b-4c9a-3e7f6b1a8d2c";
	// все 14 разбираются uuid.Parse и различны; ни один не равен UUID убранных:
	// filter.edit "019f93db-0d4e-7b6f-6a78-1c5d4f9e6b0a", track "019f93de-1e5f-7c7a-5b89-2d6e5a0f7c1b",
	// старое view "019f93cb-094a-74c1-9687-6caeb286c4d8" — иначе облако вернуло бы им прежние назначения
}

func TestCatalogNamesFollowCloudRules(t *testing.T) {
	// копия правил облака (axxoncloudgo e51bd55, model/permissions/methods.go:16,20 и permissions.go:282-310):
	// права ^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*){1,}$, последний сегмент — действие из actionsMap,
	// или область own/any после действия; группы ^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)*$;
	// корень — "incident_manager"; у каждого узла непустой i18n en и ru (title или description)
}

func TestCatalogDescriptionsFromMachineStrings(t *testing.T) {
	// для каждого права: I18n["en"].Description == StringsEN[labelKey], I18n["ru"].Description == StringsRU[labelKey]
}

func TestParseExternalPermissionsDropsUnknown(t *testing.T) {
	got := ParseExternalPermissions([]string{"incident_manager.incidents.track", "incident_manager.incidents.assign.own", "core.users.user.view"})
	require.Equal(t, Permissions{PermIncidentsAssignOwn}, got)
}
```

В `TestPermissionCatalog`: групп 3, в `administration` 1 право, в `incidents` 12, в `agent` 1.

- [x] **Step 2: Тесты падают**

Run: `go test ./internal/im/model/ -run 'Catalog|Machine|UUID|ParseExternal' -v 2>&1 | tail -20`
Expected: FAIL — не собирается (`MachinePermissions`, `PermIncidentsAssignOwn` не объявлены).

- [x] **Step 3: Константы, `AllPermissionsInfo`, `MachinePermissions`, дерево и `Description` по таблице**

Описания `PermissionInfo.Description` (англ., коротко, как сейчас) — для новых прав по смыслу `labelKey`. Тексты `i18n.description` — дословно из `strings/en.json` и `strings/ru.json` копии.

- [x] **Step 4: Тесты проходят**

Run: `go test ./internal/im/model/ -v 2>&1 | tail -20 && go build ./...`
Expected: PASS; сборка без ошибок (`PermIncidentsAssign` больше нигде не используется).

- [x] **Step 5: Commit**

Сообщение: «Этап 2: каталог прав сервера — 14 прав машины, assign.own с прежним UUID, без filter.edit и track».
Run: `git add internal/im/model && git commit -q -F .git/COMMIT_MSG_STAGE2`

---

### Task 4: `problem+json` и версия записи

Чистые помощники без маршрутов: их используют обработчик ошибок параметров (задача 5) и переходы (этап 4).

**Files:**
- Create: `internal/im/handler/operator/problem.go`, `internal/im/handler/operator/version.go`
- Test: `internal/im/handler/operator/problem_test.go`, `version_test.go`

**Interfaces:**
- Consumes: `operatorgen.Problem`, `operatorgen.ProblemCode`, константы `ProblemCode*` (задача 2).
- Produces:
  - `const ContentTypeProblem = "application/problem+json"`;
  - `const CodeUnauthenticated, CodeBadRequest, CodeNotImplemented operatorgen.ProblemCode = "UNAUTHENTICATED", "BAD_REQUEST", "NOT_IMPLEMENTED"`;
  - `func WriteProblem(c *gin.Context, status int, p operatorgen.Problem)` — пишет JSON с `ContentTypeProblem`, `c.Abort()`; ошибку записи — в `_ =` (gosec G104);
  - `func ETag(version int64) string`;
  - `var ErrPreconditionRequired, ErrVersionConflict error`;
  - `func CheckIfMatch(header string, version int64) error`;
  - `func WritePreconditionRequired(c *gin.Context)` — 428, `PRECONDITION_REQUIRED`, `messageKey` `workflow.error.precondition_required`;
  - `func WriteVersionConflict(c *gin.Context, current any)` — 412, `VERSION_CONFLICT`, `messageKey` `workflow.error.version_conflict`, поле `current`.

- [x] **Step 1: Тесты**

```go
func TestCheckIfMatch(t *testing.T) {
	cases := []struct {
		header string
		want   error
	}{
		{"", ErrPreconditionRequired},
		{`"7"`, nil},
		{`  "7"  `, nil},
		{`W/"7"`, nil}, // как prototype/server.js: W/ отбрасывается
		{`*`, nil},
		{`"5", "7"`, nil},
		{`"6"`, ErrVersionConflict},
		{`7`, ErrVersionConflict},    // без кавычек
		{`"07"`, ErrVersionConflict}, // строка, а не число
	}
	for _, tc := range cases {
		require.ErrorIs(t, CheckIfMatch(tc.header, 7), tc.want, tc.header) // errors.Is(nil, nil) == true
	}
}

func TestETag(t *testing.T) { require.Equal(t, `"12"`, ETag(12)) }

func TestWriteProblem(t *testing.T) {
	// httptest + gin.CreateTestContext: статус как передан, Content-Type == "application/problem+json",
	// тело разбирается в operatorgen.Problem с тем же code и message, c.IsAborted()
}

func TestWritePreconditionRequired(t *testing.T) {
	// 428, code "PRECONDITION_REQUIRED", messageKey "workflow.error.precondition_required"
}

func TestWriteVersionConflict(t *testing.T) {
	// 412, code "VERSION_CONFLICT", messageKey "workflow.error.version_conflict",
	// body["current"] == map{"guid": "x", "version": 8}, переданная как current
}
```

- [x] **Step 2: Тесты падают**

Run: `go test ./internal/im/handler/operator/ -v 2>&1 | tail -10`
Expected: FAIL — не собирается.

- [x] **Step 3: Реализация `problem.go` и `version.go`**

`CheckIfMatch`: пустая строка после `TrimSpace` → `ErrPreconditionRequired`; иначе части через `,`, у каждой `TrimSpace` и `TrimPrefix("W/")`; `*` или `ETag(version)` → `nil`; иначе `ErrVersionConflict`. `message` — короткий англ. текст (язык оператора — этап 5).

- [x] **Step 4: Тесты проходят**

Run: `go test ./internal/im/handler/operator/ -v 2>&1 | tail -10`
Expected: PASS.

- [x] **Step 5: Commit**

Сообщение: «Этап 2: ошибки problem+json и версия записи — ETag, If-Match, 412 и 428».
Run: `git add internal/im/handler/operator/*.go && git commit -q -F .git/COMMIT_MSG_STAGE2`

---

### Task 5: Пакет оператора на общем gin — вход, 501, 400/428, 404

Strict-обработчик (`NewStrictHandler`) в этапе 2 **не используется**: шаблон форка при ошибке разбора тела жёстко пишет `{"key":"error.bad.request",…}` — это не `problem+json`. Пакет реализует обычный `operatorgen.ServerInterface` и тело не читает. Когда в этапах 3–4 появятся настоящие тела — либо свой шаблон через флаг форка `-templates`, либо разбор тела в обработчике (записать в ADR, задача 9).

Порядок в сгенерированном коде: `bearerAuthAuthMiddleWare` → разбор параметров пути и заголовков (ошибка → `ErrorHandler`, обязательный `If-Match` без заголовка — тоже сюда, со статусом 400 и текстом `Header parameter If-Match is required, but not found`) → `Middlewares` → обработчик. Поэтому вход всегда раньше 400/428.

**Files:**
- Create: `internal/im/handler/operator/handler.go`, `auth.go`, `params.go`, `notfound.go`, `stubs.go`, `session.go`
- Modify: `internal/im/handler/v1/auth_middleware.go`
- Modify: `internal/im/handler/handler.go`
- Modify: `internal/im/handler/test/common.go` (пакетная переменная `HTTPHandler http.Handler` = результат `handler.GetHandler`)
- Modify: `.golangci.yml` — в `exclusions.rules` правило `path: "internal/im/handler/operator/stubs\\.go"`, `linters: [dupl]` (49 одинаковых однострочных методов)
- Test: `internal/im/handler/operator/handler_test.go` (без базы), `internal/im/handler/test/operator_test.go` (с базой)

**Interfaces:**
- Consumes: задачи 2 и 4.
- Produces:
  - `func (h *v1.Handler) AuthenticateUser(c *gin.Context) (*model.User, error)` — тот же путь, что сейчас в `UserAuthMiddleWare` (`authByUserToken` + `CustomerGUID` из `fakedata`), без записи ответа; `UserAuthMiddleWare` вызывает его и пишет ошибку по-старому — поведение `v1` не меняется;
  - `type UserAuthenticator interface { AuthenticateUser(c *gin.Context) (*model.User, error) }`;
  - `type Handler struct{…}`, `func NewHandler(auth UserAuthenticator, logger logrus.FieldLogger) *Handler`, `var _ operatorgen.ServerInterface = (*Handler)(nil)`;
  - `func Register(router gin.IRouter, h *Handler, basePath string)` — `operatorgen.RegisterHandlersWithOptions(router, operatorgen.BearerAuth(h.Authenticate), h, operatorgen.GinServerOptions{BaseURL: basePath, ErrorHandler: ParamErrorHandler})`;
  - `func (h *Handler) Authenticate(c *gin.Context)` — ошибка входа → лог + `WriteProblem(401, UNAUTHENTICATED)`; успех → `c.Set("user", u)`;
  - `func userFromContext(c *gin.Context) (*model.User, bool)`;
  - `func ParamErrorHandler(c *gin.Context, err error, status int)` — заголовка `If-Match` в `c.Request.Header` нет, а `err` упоминает `If-Match` → `WritePreconditionRequired`; иначе 400 `BAD_REQUEST`, `message` = `err.Error()`;
  - `func NoRoute(basePath string) gin.HandlerFunc` — путь начинается с `basePath+"/operator/"` или `basePath+"/test/"` → 404 `NOT_FOUND` `problem+json`; иначе ничего не пишет (gin сам отдаст прежний `404 page not found`);
  - `func (h *Handler) notImplemented(c *gin.Context)` — 501 `NOT_IMPLEMENTED`, `details` = `{"method": c.Request.Method, "route": c.FullPath()}`; все методы `ServerInterface`, включая `GetOperatorSession`, пока вызывают его;
  - `handler.GetHandler(handler *v1.Handler, logger)` — подпись прежняя; внутри: `operator.Register(engine, operator.NewHandler(handler, logger), model.BasePath)` и `engine.NoRoute(operator.NoRoute(model.BasePath))`.

- [x] **Step 1: Тесты в процессе (без базы)**

Помощник: `newTestEngine(t, users map[string]*model.User) *gin.Engine` — `gin.New()`, `Register(engine, NewHandler(fakeAuth{users}, logrus.New()), "/api/v1/im-backend")`, `engine.NoRoute(NoRoute(...))`; `fakeAuth` берёт токен из `Authorization: Bearer <t>`, нет такого — ошибка. `do(engine, method, path, token, ifMatch, body) *httptest.ResponseRecorder`.

```go
func TestEveryContractOperationIsRouted(t *testing.T) {
	// по каждой операции operatorapi.Contract: параметры пути — *Guid: uuid.NewString(), transitionId "take",
	// catalogId "hold", operatorId "me", value "50"; токен есть, If-Match `"1"`, тело `{}`.
	// ждём 501, Content-Type "application/problem+json", code "NOT_IMPLEMENTED"; операций — 50
}

func TestNoTokenGives401Problem(t *testing.T) {
	// GET /operator/incidents и POST /test/reset без Authorization → 401, problem+json, code "UNAUTHENTICATED"
}

func TestAuthRunsBeforeParams(t *testing.T) {
	// POST /operator/incidents/not-a-uuid/transitions/take без токена и без If-Match → 401
}

func TestMissingIfMatchGives428(t *testing.T) {
	// с токеном, верный uuid, без If-Match: POST …/transitions/take и POST …/scenario/answer
	// → 428, code "PRECONDITION_REQUIRED", messageKey "workflow.error.precondition_required"
}

func TestBadPathParamGives400Problem(t *testing.T) {
	// с токеном GET /operator/incidents/not-a-uuid → 400, problem+json, code "BAD_REQUEST"
}

func TestUnknownOperatorPathGives404Problem(t *testing.T) {
	// GET /api/v1/im-backend/operator/me → 404, problem+json, code "NOT_FOUND"
}

func TestUnknownPathOutsideOperatorKeepsGinDefault(t *testing.T) {
	// GET /api/v1/im-backend/nope → 404, тело "404 page not found", Content-Type не problem+json
}
```

- [x] **Step 2: Тест с базой — оба пакета на одном gin**

```go
func TestOperatorRoutesMountedNextToV1(t *testing.T) {
	// через HTTPHandler (util.NewTransport): GET /api/v1/im-backend/operator/incidents с "Bearer 1" → 501;
	// без токена → 401 problem+json
}

func TestOldRoutesKeepKeyErrors(t *testing.T) {
	// GET /api/v1/im-backend/incidents без токена → 401, Content-Type начинается с "application/json",
	// в теле есть поле "key"
}
```

- [x] **Step 3: Тесты падают**

Run: `go test ./internal/im/handler/operator/ 2>&1 | tail -5`
Expected: FAIL — не собирается (`Register`, `NewHandler` не объявлены).

- [x] **Step 4: Реализация**

Файлы и подписи — по Interfaces. Методы `stubs.go` — с подписями ровно как в `operatorgen.ServerInterface` (параметры пути и `…Params` не используются). `cmd/im/main.go` не меняется.

- [x] **Step 5: Тесты проходят**

Run: `go test ./internal/im/handler/operator/... -v 2>&1 | tail -20 && IM_TEST_DB_URL='postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable' go test ./internal/im/handler/test/ 2>&1 | tail -5 && go vet ./...`
Expected: PASS; старые тесты обработчиков тоже PASS. Если golangci-lint есть — `golangci-lint run ./...` без замечаний.

- [x] **Step 6: Commit**

Сообщение: «Этап 2: операторский API на общем gin — вход через облако, 501, ошибки параметров 400 и 428, 404 problem+json».
Run: `git add .golangci.yml internal/im/handler && git commit -q -F .git/COMMIT_MSG_STAGE2`

---

### Task 6: `GET /operator/session` — права машины

Единственная настоящая операция этапа: всё для неё уже есть без данных этапа 3. Схема `OperatorSession` требует `operator`, `permissions`, `agentState`. Права — ключи машины (`incident:claim`…), а не имена облака. `agentState` — `offline`: начальное состояние оператора в машине («ещё не вошёл», README машины, `PUT /operator/session/agent-state`); хранения состояния до этапа 5 нет. Необязательные поля (`limits`, `usage`, `preferences`, `permissionIssues` §10.3, `dutyGroupGuids`, `role`, `workflowSchemaVersion`) — этап 5.

**Files:**
- Modify: `internal/im/model/permission.go`
- Modify: `internal/im/handler/operator/session.go`, `stubs.go` (убрать заглушку сессии)
- Test: `internal/im/model/permission_machine_test.go`, `internal/im/handler/operator/session_test.go`, `handler_test.go` (сессия — 200)

**Interfaces:**
- Consumes: `MachinePermissions` (задача 3), `userFromContext` (задача 5).
- Produces: `func (p Permissions) MachineKeys() []string` — ключи машины в порядке `MachinePermissions`, повторы один раз, незнакомые пропускаются, результат не `nil`; `func (h *Handler) GetOperatorSession(c *gin.Context)` — 200, `application/json`, `operatorgen.OperatorSession{Operator.Guid: strconv.FormatInt(user.ID, 10), Operator.Name: user.Name (если не пусто), Permissions: user.Permissions.MachineKeys(), AgentState: OperatorSessionAgentStateOffline}`.

- [x] **Step 1: Тесты**

```go
func TestMachineKeys(t *testing.T) {
	all := Permissions{}
	for _, mp := range MachinePermissions {
		all = append(all, mp.Cloud)
	}
	keys := all.MachineKeys()
	require.Len(t, keys, 14)
	require.Equal(t, "incident:claim", keys[0])
	require.Equal(t, "agent:set_not_ready", keys[13])
	require.Equal(t, []string{"incident:schema:admin"}, Permissions{PermManage}.MachineKeys())
	require.NotNil(t, Permissions(nil).MachineKeys())
	require.Empty(t, Permissions(nil).MachineKeys())
	require.Equal(t, []string{"incident:hold"}, Permissions{PermIncidentsSuspend, PermIncidentsSuspend}.MachineKeys())
}

func TestSessionShowsMachinePermissions(t *testing.T) {
	// пользователь ID 42, Name "Тест", все 14 прав → 200, Content-Type application/json,
	// permissions — 14 ключей в порядке машины, agentState "offline", operator.guid "42", operator.name "Тест"
}

func TestSessionWithoutRightsHasEmptyList(t *testing.T) {
	// пользователь без прав → в сыром теле есть `"permissions":[]`
}

func TestSessionManageOnly(t *testing.T) {
	// только PermManage → permissions == ["incident:schema:admin"]
}
```

В `TestEveryContractOperationIsRouted`: `GET /operator/session` → 200, остальные 49 → 501.

- [x] **Step 2: Тесты падают**

Run: `go test ./internal/im/model/ ./internal/im/handler/operator/ -run 'MachineKeys|Session|EveryContract' 2>&1 | tail -10`
Expected: FAIL — `MachineKeys` не объявлен.

- [x] **Step 3: `MachineKeys` и `GetOperatorSession`**

- [x] **Step 4: Тесты проходят**

Run: `go test ./internal/im/model/ ./internal/im/handler/operator/... 2>&1 | tail -5`
Expected: PASS.

- [x] **Step 5: Commit**

Сообщение: «Этап 2: GET /operator/session — права пользователя ключами машины».
Run: `git add internal/im/model internal/im/handler/operator && git commit -q -F .git/COMMIT_MSG_STAGE2`

---

### Task 7: Старые маршруты `GET /incidents` и `GET /incidents/{guid}`; `Has` без надмножества

Сейчас список требует `take.any` (это перехват, `incident:reassign`), карточка — `manage`, а ветка с правилами доступа в `GetIncident` недостижима ([10, п. 7](10-permissions.md#7-get-incidentsguid-только-для-manage)). Пользователь варианта не выбрал. **Выбранное правило** — вариант 1 из [10, п. 7], одинаково для списка и карточки:

1. допуск — хотя бы одно из 14 прав машины (включая `manage`); нет ни одного → 403 (`ErrNoPermission`, формат `{key}` прежний);
2. выборка — у `manage` все инциденты (так задумано веткой `IsManager`, конфигуратору нужна полная картина); у остальных — только через `access_rules` (`…ByUserGroupIDs`); карточка вне доступа → 404 (`KeyIncidentNotFound`), как требует §5: «вне них инцидент не виден никак».

Почему не право `incidents.view`: его нет в машине и в правилах (§5 — отдельного права «видеть» нет), а «наблюдателя» решили не вводить (решение №2). `DELETE /incidents/{guid}` не меняется (`manage`).

`Permissions.Has` перестаёт считать `manage` любым правом (решение №3): все прочие проверки и так спрашивают ровно `PermManage`, поэтому для них ничего не меняется.

**Files:**
- Modify: `internal/im/model/permission.go`
- Modify: `internal/im/appservice/incident/incident.go:55-81`
- Modify: `internal/im/handler/v1/incident_client.go` — клиент для тестов
- Test: `internal/im/model/permission_machine_test.go`, `internal/im/handler/test/permission_test.go`

**Interfaces:**
- Consumes: `MachinePermissions` (задача 3).
- Produces: `Has(perm)` — точное совпадение; `func (p Permissions) HasAnyMachinePermission() bool`; `func (c *Client) GetIncident(ctx context.Context, authToken string, guid uuid.UUID) (*model.Incident, error)` — порядок аргументов как у `GetIncidentRule`.

- [x] **Step 1: Тесты модели**

```go
func TestHasIsExact(t *testing.T) {
	require.False(t, Permissions{PermManage}.Has(PermIncidentsTakeOwn))
	require.True(t, Permissions{PermManage}.Has(PermManage))
	require.True(t, Permissions{PermIncidentsTakeOwn}.Has(PermIncidentsTakeOwn))
}

func TestHasAnyMachinePermission(t *testing.T) {
	require.False(t, Permissions{}.HasAnyMachinePermission())
	require.True(t, Permissions{PermIncidentsSuspend}.HasAnyMachinePermission())
	require.True(t, Permissions{PermManage}.HasAnyMachinePermission())
}
```

- [x] **Step 2: Тест маршрутов (с базой)**

`TestOldIncidentRoutesPermissions` — подготовка как в `TestPermissions` (агент, тип, источник, сценарий, приоритет, правило с условием на источник, событие → один инцидент, правило доступа группы 1 на источник). Пользователи в `FakeCloudUsers` (ID, не занятые другими тестами):

| Пользователь | Права, группы | `GetIncidents` | `GetIncident` |
|---|---|---|---|
| 1 (admin) | `manage` | 1 инцидент | 200 |
| 12 | `take.own`, группа 1 | 1 инцидент | 200 |
| 13 | `suspend`, группа 9 (без доступа) | 0 | ошибка с `status code: 404` |
| 14 | нет прав МИ, группа 1 | ошибка с `status code: 403` | ошибка с `status code: 403` |

Прежний `TestPermissions` (оператор с `take.any`) должен проходить без правок.

- [x] **Step 3: Тесты падают**

Run: `go test ./internal/im/model/ -run 'HasIsExact|HasAny' 2>&1 | tail -5 && IM_TEST_DB_URL='postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable' go test ./internal/im/handler/test/ -run TestOldIncidentRoutesPermissions 2>&1 | tail -10`
Expected: FAIL — `HasAnyMachinePermission` не объявлен; после объявления заглушкой — пользователь 12 получает 403.

- [x] **Step 4: Реализация**

`Has` — `slices.Contains(p, perm)`. `HasAnyMachinePermission` — есть ли среди `p` хоть одно `MachinePermissions[i].Cloud`. В `GetIncidents` и `GetIncident` первая проверка — `HasAnyMachinePermission`, дальше прежний код (`IsManager` → всё, иначе ACL).

- [x] **Step 5: Тесты проходят**

Run: `source ~/go/offline-env.sh && make test-local 2>&1 | tail -15` (контейнер `im-test-db` из задачи 1 запущен)
Expected: PASS всех пакетов.

- [x] **Step 6: Commit**

Сообщение: «Этап 2: права старых маршрутов инцидентов — любое право МИ и правила доступа; manage не надмножество».
Run: `git add internal/im/model internal/im/appservice/incident internal/im/handler/v1/incident_client.go internal/im/handler/test/permission_test.go && git commit -q -F .git/COMMIT_MSG_STAGE2`

---

### Task 8: Хранилище ключей идемпотентности

В этапе 2 все изменяющие операции отвечают 501 — повторять нечего. Поэтому только механизм: интерфейс и хранилище в памяти с тестами. Подключение к операциям (ключ — поле тела `idempotencyKey`, обёртка обработчика) и хранилище в PostgreSQL — этапы 3–4.

Смысл — как у встроенного сервера (`prototype/server.js`, «Ключ повтора»): ответ на запрос с ключом помнится 10 минут, повтор получает его же и ничего не выполняет. Отличия, выбранные для сервера: ключ ещё и по пользователю (у встроенного сервера пользователь один); одновременный повтор ждёт первый запрос и получает его ответ; ответы 5xx не запоминаются (иначе сбой базы на 10 минут закрыл бы повтор); срок считается от готового ответа по переданным часам (этап 7 подставит часы стенда).

**Files:**
- Create: `internal/im/handler/operator/idempotency/store.go`, `memory.go`
- Test: `internal/im/handler/operator/idempotency/memory_test.go`

**Interfaces:**
- Produces:
  - `const DefaultTTL = 10 * time.Minute`;
  - `type Key struct { UserID int64; Method, Path, Value string }`;
  - `type Response struct { Status int; Header http.Header; Body []byte }`;
  - `type Store interface { Do(ctx context.Context, key Key, run func() Response) (res Response, replayed bool, err error) }`;
  - `var ErrAborted error` — первый запрос с этим ключом упал с паникой;
  - `func NewMemoryStore(ttl time.Duration, now func() time.Time) *MemoryStore`.

Правила `Do`: пустой `key.Value` — `run` без запоминания; ключ уже есть и не истёк — копия ответа, `replayed = true`, `run` не вызывается; ключ сейчас выполняется — ждать конца (или `ctx.Done()` → `ctx.Err()`); `Status >= 500` — не запоминать; паника в `run` — ключ освобождается, ждущие получают `ErrAborted`, паника идёт дальше; при каждом вызове истёкшие записи удаляются; наружу — копии (`Header.Clone()`, копия `Body`).

- [x] **Step 1: Тесты**

Часы — `fakeClock` с `Advance(d)`; `run` считает вызовы.

```go
func TestDo_RepeatWithinTTLReplays(t *testing.T)        // 2 вызова: run 1 раз, второй replayed, тот же Status/Header/Body
func TestDo_AfterTTLRunsAgain(t *testing.T)            // +9m59s → replayed; +10m → run снова
func TestDo_KeyScopedByUserMethodPathValue(t *testing.T) // смена любого из четырёх полей → run снова
func TestDo_ConcurrentSameKeyRunsOnce(t *testing.T)    // 20 горутин, run ждёт канал: run 1 раз, у всех один ответ
func TestDo_ServerErrorNotStored(t *testing.T)         // Status 500 → второй вызов снова run
func TestDo_EmptyValueNeverStored(t *testing.T)        // Value "" → run каждый раз
func TestDo_PanicReleasesKey(t *testing.T)             // первый run паникует (recover в тесте), ждущий → ErrAborted, следующий вызов → run
func TestDo_WaiterContextCanceled(t *testing.T)        // ждущий с отменённым ctx → context.Canceled
func TestDo_ReturnedCopyIsIndependent(t *testing.T)    // правка Body/Header возвращённого не меняет повтор
func TestDo_ExpiredEntriesSwept(t *testing.T)          // после +10m и любого Do во внутренней карте нет старого ключа
```

- [x] **Step 2: Тесты падают**

Run: `go test ./internal/im/handler/operator/idempotency/ 2>&1 | tail -5`
Expected: FAIL — не собирается.

- [x] **Step 3: Реализация `MemoryStore`**

Карта `map[Key]*entry` под `sync.Mutex`; `entry` — готовый ответ со сроком или канал `done` для ждущих.

- [x] **Step 4: Тесты проходят, гонок нет**

Run: `go test -race -count=3 ./internal/im/handler/operator/idempotency/ -v 2>&1 | tail -15`
Expected: PASS, без `DATA RACE`.

- [x] **Step 5: Commit**

Сообщение: «Этап 2: хранилище ключей повтора в памяти — 10 минут, один запуск на ключ; подключение — этап 4».
Run: `git add internal/im/handler/operator/idempotency && git commit -q -F .git/COMMIT_MSG_STAGE2`

---

### Task 9: Проверка на стенде и документы

Критерий готовности этапа ([40-plan.md](40-plan.md), этап 2): `tests/api.html` против стенда проходит вход и получает 501; в сессии видны 14 прав. `tests/api.html` первым делом шлёт `POST /test/reset` и при ответе не 200 останавливается с одной строкой `FAIL  Тестовый стенд доступен — POST /test/reset → <код>` (`tests/harness.js`). Значит, на стенде этапа 2 ожидается именно `→ 501`; `→ 401` — вход не прошёл.

**Предусловие для `api.html`:** `prototype/api.js` шлёт `Authorization: Bearer <localStorage.accessToken>` (этап 1). Сейчас в IM этого ещё нет — `api.js` ходит с cookie (`credentials: "include"`). Если этап 1 не сделан, проверка `api.html` покажет `→ 401`; тогда критерий закрывает скрипт `check-operator-api.sh` (шаг 4), а прогон `api.html` переносится на конец этапа 1 — записать это в 30-local-stand.md.

Страница тестов открывается с того же адреса `https://axxonnet.test`: тогда видно `localStorage.accessToken` от `dev-login.html` и CORS не участвует. Для этого прототип копируется в `~/Work/axxoncloudgo/tools/compose/ui/im-proto/` — каталог `ui` в `.gitignore` облака, nginx стенда раздаёт его как есть (`location /` с `try_files $uri`), так же лежит `dev-login.html`. Репозиторий облака не меняется.

**Files:**
- Create (вне репозиториев): `~/Work/stand/sync-im-proto.sh`, `~/Work/stand/grant-im-permissions.sh`, `~/Work/stand/check-operator-api.sh`
- Create: `docs/adr/002-operator-api-package.md` (сервер)
- Modify (IM): `research/integration/30-local-stand.md`, `research/integration/40-plan.md`

**Interfaces:**
- Consumes: всё из задач 2–8.

- [x] **Step 1: Сервер с новым каталогом**

Run: `pkill -f '^/home/slava/Work/stand/bin/im$'; ~/Work/stand/run-im-server.sh >> ~/Work/stand/im-server.log 2>&1` (в фоне, `run_in_background`), через 10 с — `pgrep -f '^/home/slava/Work/stand/bin/im$' && curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:5000/api/v1/im-backend/operator/session`
Expected: процесс жив — значит, облако приняло каталог (иначе сервер выходит при старте; причина — в конце `im-server.log`); без токена — `401`.

- [x] **Step 2: 14 прав группе `cloud-admin`**

`grant-im-permissions.sh` (python внутри скрипта): вход `test@axxonnet.test` (`POST /api/v3/ac-backend/users/login`), `GET /api/v3/ac-backend/roles/global`, у роли `cloud-admin` — список прав без `incident_manager.*` плюс 14 имён из `api/im/operator/workflow_schema.v1.json` (`permissions[].cloud`), `PATCH /api/v3/ac-backend/roles/global` — массив ролей целиком (список прав заменяется, [30, шаг 2.4](30-local-stand.md#шаг-2-сервер-ми-на-стенде)).
Run: `~/Work/stand/grant-im-permissions.sh`
Expected: `PATCH` → 200; `GET /api/v3/ac-backend/me` с токеном показывает в `incident_manager` все 14 прав и не показывает `filter.edit` и `track`.

- [x] **Step 3: Скрипт проверки API**

`check-operator-api.sh`: токен — входом, как выше; каждая проверка — строка `OK|FAIL <что>`, код выхода — число FAIL.

| Запрос | Ожидание |
|---|---|
| `GET /operator/session` без токена | 401, `application/problem+json`, `code` `UNAUTHENTICATED` |
| `GET /operator/session` | 200, `.permissions \| length` = 14, `.agentState` = `offline` |
| `POST /test/reset` | 501, `code` `NOT_IMPLEMENTED` |
| `GET /operator/incidents` | 501 |
| `POST /operator/incidents/<uuid>/transitions/take` без `If-Match` | 428, `PRECONDITION_REQUIRED` |
| `GET /operator/me` | 404, `problem+json` |
| `GET /incidents` (старый) | 200 |
| `GET /incidents` без токена | 401, в теле `key` |

Run: `~/Work/stand/check-operator-api.sh`
Expected: все строки `OK`, код выхода 0.

- [x] **Step 4: `tests/api.html` против стенда**

`sync-im-proto.sh`: `rsync -a --delete` каталогов `prototype/` и `tests/` из `/mnt/hgfs/VmWareShared/soul2home/IM` в `~/Work/axxoncloudgo/tools/compose/ui/im-proto/`, права `644`/`755`.
Run: `~/Work/stand/sync-im-proto.sh && D=$(mktemp -d) && google-chrome --headless=new --disable-gpu --no-first-run --ignore-certificate-errors --user-data-dir=$D --virtual-time-budget=60000 --dump-dom "https://axxonnet.test/dev-login.html?to=/im-proto/tests/api.html?api=https://axxonnet.test/api/v1/im-backend" | grep -o 'Тестовый стенд доступен — [^<]*'`
Expected (этап 1 сделан): `Тестовый стенд доступен — POST /test/reset → 501: на сервере нет служебных операций тестового стенда`. Если `→ 401` — этап 1 ещё не сделан (см. предусловие). Если `сервер не ответил` — страница не на том адресе или сервер не запущен.

Ручная проверка (то же глазами): открыть в браузере `https://axxonnet.test/dev-login.html?to=/im-proto/tests/api.html?api=https://axxonnet.test/api/v1/im-backend` — на странице одна строка FAIL с `→ 501`.

- [x] **Step 5: ADR сервера**

`docs/adr/002-operator-api-package.md` (англ., по образцу ADR-001): второй пакет из копии контракта IM в том же процессе; `vendor-operator-contract` и `gen-api-operator`, офлайн-генератор (`GEN_GOPROXY`); адаптер `bearerAuth` и почему не переименование схемы; `problem+json` только на `/operator/*` и `/test/*`, свои коды 401/400/501; strict-обработчик не используется до настоящих тел (`-templates`); 412/428; каталог = 14 прав машины, UUID; правило старых маршрутов; идемпотентность — механизм сейчас, подключение в этапе 4.

- [x] **Step 6: Документы IM**

Перед правкой — `git -C /mnt/hgfs/VmWareShared/soul2home/IM fetch`; есть новое — сказать пользователю.
- `30-local-stand.md`: новый раздел «Шаг 4: операторский API (этап 2)» — тесты сервера локально (`make test-db-up`, `make test-local`), `make vendor-operator-contract` / `gen-api-operator`, три скрипта стенда и что они проверяют, команда `api.html`; в «Временное на стенде» — копия прототипа `tools/compose/ui/im-proto/` и контейнер `im-test-db`.
- `40-plan.md`: в «Что уже готово» строка «Каркас операторского API (этап 2)» со ссылкой на этот план; если `api.html` ждёт этап 1 — так и написать.

Run: `cd /mnt/hgfs/VmWareShared/soul2home/IM && python3 tools/check_links.py`
Expected: без ошибок ссылок.

- [x] **Step 7: Последний прогон**

Run: `cd ~/Work/incident-manager-server && source ~/go/offline-env.sh && make test-local 2>&1 | tail -15 && go vet ./... && (golangci-lint run ./... || true)`
Expected: все тесты PASS, `go vet` чисто; lint — без новых замечаний (или «lint — в CI», если не поставился).

- [x] **Step 8: Commit (два репозитория)**

Сервер — сообщение «Этап 2: ADR о пакете операторского API». Run: `git add docs/adr/002-operator-api-package.md && git commit -q -F .git/COMMIT_MSG_STAGE2`
IM — сообщение «Этап 2 встраивания: проверка операторского API на стенде». Run: `cd /mnt/hgfs/VmWareShared/soul2home/IM && git add research/integration/30-local-stand.md research/integration/40-plan.md research/integration/50-plan-stage2.md && git commit -q -F .git/COMMIT_MSG_STAGE2`

---

## Не в этом этапе

| Что | Когда |
|---|---|
| Принимать только access-токен; проверка `AuthData` на `nil` (`client.go:60`); вопросы introspect | отложено пользователем |
| CORS для страницы тестов с диска (`If-Match`, `Access-Control-Expose-Headers: ETag`, `credentials`, `Origin: null`) — сейчас `*` | этап 7 (сборка стенда); в этапе 2 проверка идёт с того же адреса |
| Ошибки разбора тела в `problem+json` (strict-обработчик, `-templates`) | этапы 3–4, с первыми настоящими телами |
| Подключение идемпотентности к операциям, хранилище в PostgreSQL | этапы 3–4 |
| 412 с настоящей карточкой и версией инцидента | этап 4 |
| Сессия целиком: хранимое состояние, `limits`, `usage`, `preferences`, `permissionIssues` §10.3, дежурные группы | этап 5 |
| Поток `/operator/stream` (SSE; генератор делает копирование `io.Reader`) | этап 5 |
| `/test/*` по-настоящему, отдельный тег сборки | этап 7 |
| Устаревший сгенерированный код `v1` (ответы 400 из yaml) | вне плана |

## Решения этого плана (на подтверждение)

1. `bearerAuth` — рукописный адаптер `auth_adapter.go` в каталоге `operatorgen`; контракт IM не меняется.
2. Каталог — ровно 14 прав: `filter.edit` и `track` убираются (решение №2 и BACKEND.md), хотя в поручении было «оставить 9 прав». Из 9 остаются 7: 6 как есть и `assign` → `assign.own` с тем же UUID.
3. У права в каталоге `title` — короткий (таблица задачи 3), `description` — текст `labelKey` машины на en/ru.
4. Старые `GET /incidents` и `/incidents/{guid}`: допуск — любое из 14 прав, `manage` видит всё, остальные — по правилам доступа, чужая карточка — 404.
5. Свои коды ошибок вне контракта: `UNAUTHENTICATED` (401), `BAD_REQUEST` (400), `NOT_IMPLEMENTED` (501).
6. Идемпотентность — ключ ещё и по пользователю, одновременный повтор ждёт первый, 5xx не запоминается.
7. Тесты с базой — отдельный контейнер `postgres:9.6` на `127.0.0.1:55432`, не база стенда.
8. `api.html` — с того же адреса через копию прототипа в `tools/compose/ui/im-proto/`.

## Открытые вопросы

- Добавить в `Problem.code` контракта IM коды для 401 и 400 (а 501 — временный и в контракт не нужен)? Сейчас ответ 401 контракта ссылается на `Problem`, а подходящего кода в перечне нет.
- Этап 1 в IM не закончен: `prototype/api.js` не шлёт `Authorization`. Пока его нет, критерий «`api.html` проходит вход» на стенде не выполнить — только скриптом.

## Итог выполнения (2026-10-29)

| Задача | Коммиты сервера |
|---|---|
| 1. Локальный прогон тестов | e95febc |
| 2. Копия контракта и генерация | ab51c7e, 8687637 |
| 3. Каталог прав | db39786 |
| 4. problem+json и версия записи | 227ff76 |
| 5. Пакет оператора на общем gin | 04d6f90, ccca263 |
| 6. GET /operator/session | f1e944c |
| 7. Старые маршруты, Has без надмножества | c4bf418 |
| 8. Хранилище ключей идемпотентности | 285d3b6, 2f0715f |
| 9. Проверка на стенде и документы | 57ce47e, 7a43659 (IM: ba1cd66) |

Итоговый просмотр — исправления: d247713 (сервер), IM — коммит этого же изменения.
