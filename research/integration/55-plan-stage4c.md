# Этап 4в: операторский API — карточка, действия, переходы — план работ

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Оператор через настоящие маршруты `/operator/*` открывает карточку инцидента, видит доступные действия и формы и выполняет переходы — одиночные, на выборке, объединение, отсоединение — с версиями записи (`ETag`, `If-Match`, `expectedState`, `expectedVersions`), идемпотентностью и кодами ошибок, как у `server.js`. Заглушек становится на 12 меньше: 12 из 51 операции работают по-настоящему, ещё одна (`getOperatorSession`) уже работала.

**Architecture:** Ядро `transition` (4б) получает путь чтения без блокировок: действия, формы, бейдж, пояснение, выбор основного. Новый пакет `internal/im/appservice/operator` даёт обработчикам зависимости одной структурой `Deps` (ядро, хранилище, мир, часы, видимость) и держит то, чего облако не даёт: `Directory` — память о вошедших операторах — и мир этапа 4в. `internal/im/handler/operator` превращает запрос в вызов ядра, а итог и отказ — в ответ: отображение в HTTP — одна функция, виды карточки и сводки — отдельные файлы по образцу `summary` и `card` из `server.js`. Правил IM в обработчиках нет: только порядок проверок `server.js`. Проверка — тесты HTTP на настоящем маршрутизаторе, где каждый ответ сверяется с контрактом, и повтор векторов переходов через маршрут.

**Tech Stack:** Go 1.27.1, gin, oapi-codegen (пакет `operatorgen`, обычный `ServerInterface`), `mgutz/dat`, cel-go, PostgreSQL 9.6, testify `require`, kin-openapi v0.133.0 (`openapi3filter`, `routers/legacy`; только в тестах), golangci-lint v2.14.0.

**Spec:** [40-plan.md](40-plan.md), этап 4 и этапы 5–7; ADR-005 сервера (`docs/adr/005-transitions-in-transaction.md`), «Carried to 4c» и «Known limits»; ADR-002 (`docs/adr/002-operator-api-package.md`), решения 5–7, 9, 10; ADR-004; [53-plan-stage4b.md](53-plan-stage4b.md) и [54-plan-stage4b2.md](54-plan-stage4b2.md) — решения 1–41 (обязательны и здесь), «Не в этом этапе», «Открытые вопросы»; [14-im-backend-operator.md](14-im-backend-operator.md). Образец поведения — `prototype/server.js` (строки ниже по `68f5be5`): `actorRef` 116, `icu` 513, `render` 540, `timerState` 555, `holdTimerState` 569, `formView` 576, `actionsFor` 601, `badgeView` 626, `summary` 635, `journalView` 707, `noteView` 859, `card` 864, `alarmView` 887, `targets` 988, `problem` 1178, `guardProblem` 1188, `versionProblem` 1211, `runTransition` 1237, `changedSince` 1258, `mergeIncidents` 1265, `bulkScope` 1303, маршруты 1486–1720, `/test/clock` 1972, `handle` 2013; `prototype/engine.js`: `availability` 139, `form` 690, `badge` 723, `cardNote` 736, `mergeCheck` 780, `actions`. Сервер — `3f8a6be`, IM — `68f5be5`; ссылки плана сверены с ними 2026-10-30. Копия контракта и машины на сервере (`api/im/operator/SOURCE` = `53094d9`) побайтно равна IM: с `53094d9` в `Specification/Workflow_machine` менялся только `CEL.md`, поэтому `make vendor-operator-contract` в этапе не нужен.

## Критерий готовности: `tests/api.html` в этом этапе не пройдёт

Критерий из 40-plan.md — «`tests/api.html` проходит переходы (взять, приостановить, передать, закрыть)» — **в этапе 4в выполнить нельзя, и дело не только во входе**:

| Препятствие | Что видно в коде | Когда снимается |
|---|---|---|
| Клиент не шлёт `Authorization`, сервер отвечает 401 | `prototype/api.js`: `credentials: "include"`, заголовка нет; `IMApi.create` в `tests/harness.js` — тоже | вход отложен до слова пользователя |
| Каждый тест начинается с `POST /test/reset` с набором `demo` — 230 вызовов `makeEnv` | загрузка набора — этап 7; люди набора (`me`, `petrova`) со строковыми id, у облака — числовые | этап 7 |
| Тесты находят инциденты через очередь: `env.all`, `env.find`, `env.guidOf` — 174 вызова | `listIncidents` — этап 5 | этап 5 |
| `env.advance` (92 вызова) — сердцебиение и `/test/clock` с планировщиком | сессия — 5, планировщик — 6 | этапы 5–6 |
| Прогон падает, если какая-то операция контракта не покрыта; CORS не пускает `If-Match` и не показывает `ETag` | `tests/harness.js`, `CORSmw` в `cmd/im/main.go` | этап 7 |

**Что проверяем вместо него — четыре уровня:**

- **А. Потоки через настоящий маршрутизатор.** Тесты Go идут в `HTTPHandler` (весь обработчик, настоящие gin, разбор параметров и `Authenticate`) с `FakeCloudUsers` и базой `im-test-db`: взять → приостановить → возобновить → передать → принять → закрыть, отказы, каждый код условия из машины. Названия тестов из `tests/api-scenarios.js`, которым отвечает проверка, — в задаче 22.
- **Б. Векторы через маршрут.** `TestTransitionVectorsOverHTTP`: из 87 векторов `run`, `runAll`, `merge` 85 кладутся в базу и повторяются запросом HTTP с миром-лентой; ещё 2, оба синтетические, маршрут не выражает (`a177f82f53`, `e2d6b4a01a`). Сравнивается то, чего не видит тест ядра: статус, код, `journalEntries`, `externalEffects`, `canceledTimerTrigger`, прирост версии, выбранный основной, строки после вызова. Отказов условий у `run` в векторах нет: все 12 отказов `run` — формы; коды условий и `409` у `run` закрывает уровень А. Правки IM не нужны.
- **В. Контракт на каждом ответе.** Помощник тестов сверяет статус, заголовки и тело каждого ответа уровней А и Б со схемой `openapi.v30.json` (Go-аналог `IMContract.problems`). Исключения собраны в одном месте: коды сервера вне контракта (решение 62) и заведомо лишние статусы (решение 63).
- **Г. Стенд.** `~/Work/stand/check-operator-transitions.sh`: настоящий токен облака через шлюз, инцидент от `agent-emulator`, только HTTP, базы `imdb` и `ac_db` скриптом напрямую (SQL) не трогаются; единственное исключение — правило доступа через старый HTTP API (решение 60). Запускается руками, это не тест. Шаг передачи зависит от второго оператора: не вошёл — `SKIP` (решение 60).

**Что остаётся непроверенным до этапа 7:** полный `tests/api.html?api=…`. Часть сценариев там требует планировщика, сценариев и справочников и в 4в не воспроизводится в принципе. Уровни А–Г закрывают критерий по смыслу (переходы работают через HTTP на настоящем сервере), но не буквально. Строка 40-plan.md меняется на эти уровни в задаче 25.

## Global Constraints

- Сервер — `~/Work/incident-manager-server`, ветка `feature/im_operator`, от `3f8a6be`. IM — `/mnt/hgfs/VmWareShared/soul2home/IM`, ветка `feature/im_operator`, от `68f5be5`. Пути в задачах — от корня репозитория задачи. Все задачи — на сервере; задача 24 ещё и в `~/Work/stand`; задача 25 — на сервере и в IM.
- Только локально. Каждая задача — коммит, кроме задачи 24 (скрипт лежит вне репозитория); **push не делать никогда**. `~/Work/axxoncloudgo` не менять; кажется, что нужна правка облака, — **стоп, спросить пользователя**. В `ac_db` ничего не писать, пользователей облака не заводить (ни SQL, ни `CreateUser`): завести пользователя — решение пользователя.
- Вход отложен: `prototype/api.js` не меняется, новых способов подставить оператора в собранном сервере нет. Подмена оператора — только `Deps` в тестах.
- Тесты с базой — только `IM_TEST_DB_URL='postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable'`; база стенда `imdb` — никогда. На этой базе — только одна цепочка `make test-local` одновременно. Контейнер не запущен — `sg docker -c "make test-db-up"`. Пакеты без базы — `go test -race $(go list ./internal/im/... | grep -v /handler/test)`.
- Перед любой командой `go` — `source ~/go/offline-env.sh` в той же строке. Новых зависимостей нет; `go.mod` и `go.sum` не меняются (`openapi3filter` и `routers/legacy` собираются офлайн; `gorillamux` не брать — `gorilla/mux` нет в `go.mod`; `golang.org/x/text` — непрямая зависимость, не импортировать). Адрес `npm.itvgroup.ru` недоступен. Docker — только через `sg docker -c "…"`.
- `make gen` и `make gen-api-im` не запускать; `make gen-api-operator` — только в задаче 8, шаг 0, и только если после `make vendor-operator-contract` сгенерированный код изменился (контракт меняется один раз, коммит IM `9526a09`). Сгенерированное руками не править.
- `golangci-lint run ./...` — 0 замечаний в каждой задаче (`funlen` 120 строк / 60 операторов, `dupl` 150); `gofmt -l internal/im` — пусто.
- Тесты — testify `require`, под `-race`. Тесты 4б (`internal/im/service/transition/...`, `internal/im/handler/test`) проходят без правки, кроме названных в задачах. Комментарии в коде и ADR — по-английски; документы IM — по-русски, простыми словами. Новых миграций нет (последняя — `018_incident_machine.sql`).
- **Правила IM.** Правила меняются в машине, а не в `prototype/*.js`; машина, правила и прототип в этапе не меняются; контракт меняется один раз, в коммите IM `9526a09` (решение пользователя 2026-10-30: `INTERNAL_ERROR` и `NOT_IMPLEMENTED` в `Problem.code`, `412` у `detachLinked` и `detachAllLinked`), остальной этап его не меняет. Сгенерированные файлы IM собираются своим инструментом, руками не правятся (`CLAUDE.md` IM). `Specification/Workflow_machine/README.md` и `openapi.json` остаются в CRLF. Кажется, что нужна правка машины, контракта или вектора, — **стоп, спросить**. Перед правкой IM (задача 25) — `git -C /mnt/hgfs/VmWareShared/soul2home/IM fetch`; есть новое на GitHub — сказать пользователю.
- Быстрые проверки IM после задачи 25: `python3 tools/build_workflow.py --check && python3 tools/check_links.py` (меняются только документы `research/`).
- Векторы руками не правятся. Go расходится с вектором — правится Go.
- Временные файлы — в scratchpad сессии исполнителя; в командах ниже он `$S` (задать `S=…` в той же строке).
- Коммиты. Сервер — один на задачу, сообщение по-русски, начинается с «Этап 4в: », пишется инструментом записи файла в `.git/COMMIT_MSG_STAGE4C` (без heredoc), последняя строка — `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`; `git commit -q -F .git/COMMIT_MSG_STAGE4C`. IM — так же, файл `.superpowers/sdd/55-plan-stage4c/commit-msg.txt` (папка в `.gitignore`). Команды Bash — в одну строку. Журнал работ — `.superpowers/sdd/55-plan-stage4c/progress.md` в IM.

**Решения пользователя (обязательны):** те же, что в планах 53 и 54, плюс решения 2026-10-29: `404` раньше проверки `If-Match`; `manage` видит все инциденты только на старых маршрутах, операторский API применяет правила доступа; `UNAUTHENTICATED` и `BAD_REQUEST` внесены в `Problem.code` контракта (копия сервера уже их содержит). Вход отложен до слова пользователя. Отображение HTTP — из ADR-005 с тремя исключениями. AxxonData вне работы целиком.

**Решения этого плана (обязательны для задач; решения 1–41 — планов 53 и 54; обоснования новых — в конце):**

42. **Критерий готовности — уровни А–Г** (раздел выше). Полные записанные векторы HTTP из `server.handle` не делаются: этот набор и есть `tests/api.html` на этапе 7. Дополнять векторы переходов полем `expect.http` не надо: статус однозначно выводится из `expect` (задача 23).
43. **Зависимости обработчиков — одна структура `operator.Deps`** из `internal/im/appservice/operator`. Два мира: `World` — для ядра, `ViewWorld` — для чтения; в сборке это один и тот же мир, в тесте векторов — лента и `FactWorld` с заданными значениями (задача 23): лента записана только на вызов ядра, карточка после него дала бы промахи, а `NewWorld` там не годится — акторы векторов не числа (`me`, `op1`).
44. **Чтение ядра — без блокировок.** Новый метод `Repo.ReadFamily` — тот же запрос, что `LockFamily`, без блокировки строк и без транзакции. Ответ чтения может устареть; это нормально: переход проверяет всё заново под блокировкой, расхождение ловит `Expect`.
45. **Мир этапа 4в** (часть `rest` у `NewServerWorld`):
    - `Directory` — интерфейс; реализация `SeenDirectory` в памяти помнит каждого, кто прошёл `Authenticate` (`*model.User` целиком); миграции нет, после рестарта память пуста. Облако не даёт ни списка пользователей с правами, ни состава групп (исследование 12; BACKEND §15), поэтому другого источника нет.
    - `can(who, p)` и `access(who, x)` для другого человека — по записи `Directory`; `access` — тем же кодом, что для себя (`NewServerWorld` для этого человека); незнакомый — `false`.
    - `isOperator(id)` — есть в `Directory`; `transferTargets()` — id всех из `Directory`.
    - `isGroup` — `false`, `members` — `[]`, `dutyGroups` — `[]` (`STAGE7`). Передача группе в 4в есть только на ленте векторов.
    - `agentState(who)` — `ready` для знакомых, `offline` для незнакомых; `idleSec` — `0`; `lastTransferTarget` — `""` (все три `STAGE5`). `GET /operator/session` отдаёт ту же константу `ready` вместо `offline`: иначе ответ расходился бы с условием `agentReady`.
    - `stepsFilled` — `false`, `Progress` — `0, 0`, `StepNumber` — `0`, `SetCursor` — ничего, `ShareAnswers` — `0` (все `STAGE6`). Значит, закрыть можно только результатом с `requiredStepSet: none` (`false_alarm`, `duplicate`, `drill`, `impossible`), результат `processed` даёт `REQUIRED_STEPS_NOT_FILLED`.
    - `ActorName`: `dispatcher` — «Диспетчер», `system` — «Система», пустой id — `["workflow.label.unassigned"]`, знакомый — `user.Name`, незнакомый — сам id (отступление от `actorName` прототипа: человека нет в памяти после рестарта, журнал важнее пустоты).
46. **Видимость.** Инцидент виден, если у пользователя есть хоть одно право машины (`HasAnyMachinePermission`, как у старого `GetIncident`), `customer_guid` инцидента равен клиенту пользователя и `GetIncidentByUserGroupIDs` его отдаёт — для всех, `manage` без исключения. Новый метод `incident.AppService.Visible(ctx, user, guid) (bool, error)`; старый `GetIncident` не меняется. Не виден = `404 NOT_FOUND`, ключ `workflow.error.not_found`, как и нет такого. **Привязанные и соседи по событию проходят тот же фильтр:** `linkedCount`, `siblingCount`, `alarm.siblings` считаются только по видимым (`canSee` в `server.js:633`, 673, 675, 888). Исключение одно: `listTransferTargets` с невидимым `incidentGuid` — `200` и список как без параметра (`server.js:1672–1676`, у операции в контракте нет `404`).
47. **404 раньше `If-Match`.** `ParamErrorHandler` становится методом `(*Handler).paramError`. На ошибке `errIfMatchMissing` он берёт `c.Param("incidentGuid")` и пользователя из контекста и проверяет видимость: не виден — 404, виден — 428. То же даёт и `answerScenarioStep` (заглушка): та же обёртка, отдельной работы не требует.
48. **Отображение итога ядра в HTTP — одна функция `refusalProblem` и одна `errorProblem`** (`internal/im/handler/operator/mapping.go`). Порядок проверки `Refusal`:
    1. операция — объединение и отказ без `Guard`: `422 BULK_SELECTION_INVALID`, сообщение — ключ отказа (в том числе `wrong_state`; `server.js:1281`);
    2. `Key == transition.KeyUnknownAction`: `404 NOT_FOUND`, `workflow.error.unknown_action` (`server.js:1239`);
    3. `NotFrom`: `409 TRANSITION_NOT_ALLOWED_FROM_STATE`, поле `guard` нет;
    4. `Guard != ""`: `403`, код — `errorCodes[Key]` условия машины, иначе `errorCode` условия, иначе `GUARD_FAILED`; поле `guard` — имя условия;
    5. иначе `422`, код — `Refusal.Code`, а если пуст — `FORM_FIELD_REQUIRED`.

    Ошибки: `*VersionConflict`, `ErrFamilyChanged` — `412 VERSION_CONFLICT` с `current`; `ErrNotFound` — `404`; `ErrDuplicateID` — `400 BAD_REQUEST` (обработчик убирает повторы сам, код виден только при ошибке обработчика); остальное — `500`, код `INTERNAL_ERROR`, ключ `workflow.error.transition_failed` (решение 55).
49. **Маршрут одного инцидента отказывает двум видам переходов одинаково:** `trigger != manual` и `bulk.mode == merge` — `404 NOT_FOUND`, `workflow.error.unknown_action`, до вызова ядра. `server.js` принимает объединение на этом маршруте, но интерфейс туда не приходит (`ui.surface: []`), а `Run` ядра даёт `ErrFamilyChanged` три раза (`TestProbeRunMergeSingle`), то есть вечный 412.
50. **`expectedVersions`.** Значение — строка десятичного числа; не число — `400 BAD_REQUEST`. Ядру в `Op.Expect` идут только ключи, которые есть в выборке (`changedSince` прототипа: чужой ключ не сравнивается), поэтому `ErrNotFound` ядра по ключу вне семьи сюда не доходит; строка ADR закрывается так. Нет ключа — версия не проверяется. Заголовок `If-Match` проверяется до ядра функцией `CheckIfMatch`, совпавшая версия идёт в `Op.Expect`: гонка между проверкой и блокировкой тоже даёт 412. «Не проверять» у `runOne` — `expect == nil`.
51. **Выборка — каждый инцидент своей транзакцией,** как `server.js` и BACKEND: один вызов `Run` на инцидент (ADR-005, решение 4), частичный успех, порядок — как в запросе. Со `scope` устаревшая выборка не выполняется целиком (412), основной выбирается заново, остальные — в `skipped`.
52. **Объединение** — один вызов `Merge` (всё или ничего). Основной — `Core.MergePrimary` по списку, отсортированному по номеру. **Дописывание версий после объединения** — отдельная функция `TouchAfterMerge` после фиксации и отдельная задача 19, чтобы другой ответ на открытый вопрос 1 стоил одной задачи: +1 тем инцидентам, кто в `server.js` попал бы в `touch`, **и кого ядро этим вызовом не записало** (иначе основной получил бы +2). `incident.updated` — этап 5.
53. **`/test/clock` работает только при `IM_TEST_SUPPORT=true`** (`model.Config`, по умолчанию `false`); иначе `404 NOT_FOUND`, вне контракта операции (решение 63). При включённом флаге на старте — `Warn` в журнал: двигать часы может любой вошедший; отдельного права нет, потому что на этапе 7 `tests/api.html` двигает часы из-под любой роли. Сдвиг прибавляется к часам `Deps.Now`; часы приёма событий не сдвигаются. Проверки — как `server.js` (`Number.isInteger`): тело разбирается с `UseNumber`, `1.0` — целое; не целое или нет поля — `422 FORM_FIELD_REQUIRED`, `workflow.error.test.clock_seconds`; отрицательное — `422`, `workflow.error.test.clock_backwards`. `runScheduler` и `serviceRestart` принимаются и ничего не делают (этап 6), `fired` — `[]`. Остальные `/test/*` — 501. Отдельный build tag — этап 7, вместе с остальными `/test/*`.
54. **Идемпотентность — `idempotency.MemoryStore` на `executeTransition`, `executeBulkTransition`, `mergeIncidents`.** Ключ — (`user.ID`, метод, `c.Request.URL.Path`, `idempotencyKey` тела); 10 минут по тем же часам, что `Deps.Now` (как `now()` у `answered` в `handle`: сдвиг `/test/clock` сокращает память); пустой ключ — без памяти; повтор отдаёт сохранённый ответ любого статуса ниже 500, с `ETag`. Повторы проверяются раньше 404 и `If-Match`, как `handle`, кроме 428 обёртки (она срабатывает до обработчика; расхождение записывается в ADR). Значит, повтор отдаёт сохранённый ответ и тому, кто потерял доступ (решение 65). Хранилище в PostgreSQL — этап 5, вместе с несколькими экземплярами сервера.
55. **Ошибка вычисления — `500 INTERNAL_ERROR`,** а не `422` прототипа (открытый вопрос 2 плана 53, ADR-005). Код `INTERNAL_ERROR` — в контракте с коммита IM `9526a09`, как и `NOT_IMPLEMENTED` (решение 62). В векторах таких случаев нет (`error` — 0 из 92).
56. **Карточка этапа 4в.** `scenario` — нет в ответе (необязательное поле, этап 6); `media` — `{"cameras": [], "map": null}`, `mediaKinds` — `[]` (этап 10); `site`, `siteType`, `location`, `description` — `null`; `export`, `matchedLinked` — нет в ответе; `scenarioProgress` — `{0, 0}` из мира; `readOnly` — по `scenarioEdit.guards`; `journal` — весь; `alarm`, `note`, `badge`, `source`, `sourceGroup`, `devices`, `ruleName`, `scenarioTitle`, `eventType` — настоящие. Откуда что: `eventType` — `GetSourceEventType(ctx, event.SourceEventType.GUID)`: `id` — `UID`, `name` — `Name` (`GetEvent` заполняет у связанных только `GUID`); `source` — `GetSource` и `GetSourceType`: `typeId` — `UID`, `typeLabel` — `Name`; `sourceGroup` — из `GetSourceGroupGUIDs(ctx, source.GUID)` самая глубокая по `tree.PathFromRoot` (`sourceGroupOf`, `server.js:193`), имя — `GetSourceGroup(ctx, guid)`, групп нет — `null`. Поле, не названное здесь, — как в `summary` и `card`.
57. **Язык ответов — константа `ru`** (`STAGE5`: настройки сессии). Строки — `operatorapi.StringsRU` и `StringsEN`; разбор ICU свой, только нужное: `{name}`, `{n, plural, …}` с `#`, вложенные `[ключ, подстановки]`, нет ключа в `en` — `ru`, нет нигде — сам ключ. В каталоге 14 строк с `plural` и ни одной с `select`. Правила множественного числа — как `Intl.PluralRules` для целых: `ru` — `one`, `few`, `many`, `en` — `one`, `other`; нет формы — `other`.
58. **`surface`.** На маршрутах переходов идёт в ядро как есть, пустой остаётся пустым (`body.surface` в `server.js`; вектор `transfer` с `surface: ""` это проверяет). У `getIncidentActions` по умолчанию `card`.
59. **`Result.After` в 4в никуда не идёт** (`notify`, `evict`, `touch` — этап 5), пишется в отладочный журнал. `facts` не используется. Отсутствие потока событий — известное ограничение: клиент после перехода перечитывает карточку.
60. **Второй оператор стенда — только `user@gmail.com`, если он может войти.** Он описан в 30-local-stand.md, шаг 9, живой вход не проверялся. В `ac_db` ничего не пишется, пользователи не заводятся, `CreateUser` облака не используется. Вход разрешён пользователем 2026-10-30 только на локальном стенде; пароль берётся из файла на стенде, не из чата и не из скрипта. Вход не удался, запрещён или нет права `incident:accept` — передача пропускается строкой `SKIP` с причиной; это не провал уровня Г (открытый вопрос 7). Правило доступа для `cloud-admin` через старый HTTP API разрешено только на стенде: скрипт печатает, что создал его, и как удалить.
61. **Контракт вызова ядра записывается:** один вызов `Run`, `RunAll` или `Merge` на транзакцию вызывающего, REPEATABLE READ не использовать (комментарий у `Core`, раздел ADR-005). Обработчики вызывают ядро вне своей транзакции.
62. **Коды `500` и `501` — в контракте.** `INTERNAL_ERROR` и `NOT_IMPLEMENTED` внесены в `Problem.code` (решение пользователя 2026-10-30, коммит IM `9526a09`); сервер даёт `CodeInternal = "INTERNAL_ERROR"` в `internal/im/handler/operator/problem.go` наравне с остальными кодами. Списка кодов вне контракта и подмены перечня в памяти нет.
63. **Ответы вне контракта операции — один случай.** `412` у `detachLinked` и `detachAllLinked` (`ErrFamilyChanged`) теперь в контракте (коммит IM `9526a09`), таблицы `contractExtraStatuses` нет. Запрос, который сам проверяет выход за контракт (`404` у `/test/clock` без флага), идёт через `operatorClient.raw` без сверки. Статусы 400, 401, 500, 501 контракт оговаривает общим правилом; если у операции их нет, тело сверяется со схемой `Problem` напрямую. Всё прочее вне контракта — провал теста.
64. **`TestEveryContractOperationIsRouted` переделывается один раз, в задаче 7, дальше его никто не трогает.** Он больше не вызывает обработчики: сверяет операции контракта с `engine.Routes()`, а ответ `501` проверяет отдельный `TestStubAnswers501` на операции, которая остаётся заглушкой весь этап (`GET /operator/incidents/counters`). Список `implementedOperations` удаляется. Это меньше правок, чем шаг в каждой из 12 задач, и обработчикам с пустыми `Deps` незачем выполняться. Число заглушек сверяется в задаче 25.
65. **Повтор отдаёт сохранённый ответ раньше проверки видимости** (решение 54, исключение из Review Focus 2). Потерявший доступ оператор с тем же ключом и тем же путём в течение 10 минут получит прежний ответ, в том числе карточку. Принято: ключ привязан к пользователю и пути, память живёт 10 минут, а чужому ответ не выдаётся. Записывается строкой в ADR-002 (задача 25).

## Review Focus

1. **Двойное нажатие и две вкладки.** `If-Match` прошёл у обоих, ядро пустило одного: второй получает `412` с `current`, а не `500` и не вторую запись журнала. Тест — задача 14: `TestConcurrentClaimOneWins`.
2. **Чужой инцидент виден по коду ответа.** Без доступа каждый маршрут инцидента отвечает `404`, а не `403`, `412`, `428` или `409`: без `If-Match`, со старым `If-Match`, с `manage`, по `linkedGuid`, в `failed` выборки, в объединении; счётчики и соседи его не выдают. Исключение одно: повтор с тем же ключом отдаёт сохранённый ответ (решение 65). Тесты: задача 15 — `TestInvisibleIncidentIsNotFoundEverywhere`; задача 17 — `TestBulkInvisibleGoesToFailed`; задача 18 — `TestMergeMissing`; задача 9 — `TestSummaryCountsVisibleOnly`; задача 10 — `TestAlarmHidesInvisibleSibling`.
3. **Повтор сети после успеха.** Тот же ключ с уже устаревшим `If-Match` отдаёт сохранённый `200`, новой записи журнала нет; тот же ключ другого пользователя — выполняется; после `500` — выполняется снова. Тесты — задача 16: `TestIdempotentRepeatReplaysAfterVersionMoved`, `TestIdempotencyKeyIsPerUser`, `TestServerErrorIsNotRemembered`.
4. **Смешанная выборка.** Один устарел, один чужой, один с отказом, один хороший, плюс повтор id: хороший выполнен и записан ровно один раз, остальные — каждый в `failed` со своей причиной, откатов соседа нет. Тест — задача 17: `TestBulkMixedSelection`.
5. **Версии после объединения.** Отказ не трогает никого; основной и присоединённые получают ровно +1; ранее привязанные открытые — +1, закрытые — нет; отказ `Touch` после фиксации не превращает успех в ошибку. Тесты — задача 19: `TestMergeTouchesOnlyUnwritten`, `TestMergeRefusalTouchesNothing`, `TestMergeTouchErrorKeepsSuccess`.

---

## Что входит

Сегодня из 51 операции работает одна (`getOperatorSession`), 50 — заглушки `stubs.go`.

| Операция | Почему входит |
|---|---|
| `getIncident` | карточка: `api.get(incPath(id))` в `app.js:935`, 3819, 3954; 21 прямой вызов в тестах и `env.card` — 248 |
| `getIncidentActions` | действия и формы; 4 прямых вызова, в остальном — через `actions` карточки |
| `executeTransition` | `env.act` — 290 вызовов, `app.js:1445` |
| `executeBulkTransition` | `app.js:1372`, 15 прямых вызовов |
| `mergeIncidents` | `app.js:3964`, 27 прямых вызовов |
| `listLinked`, `detachLinked`, `detachAllLinked` | `app.js:959`, 3451, 3463; 26 прямых вызовов |
| `getJournal` | 3 вызова; тот же журнал, что в карточке |
| `listTransferTargets` | форма «Передать», `app.js:4404`, 11 вызовов |
| `listReasons` | причины форм; данные уже в машине |
| `testClock` | минимум по ADR-005; нужен окну переоткрытия через HTTP |

Остальные 38 — в «Не в этом этапе».

## Структура файлов

| Файл | Что | Задача |
|---|---|---|
| `internal/im/service/transition/run.go`, `errors.go`, `core.go`, `merge.go`, `runall.go` | `KeyUnknownAction`, `ErrDuplicateID`, непустые карты итога, `Core.Machine`, контракт вызова | 1 |
| `internal/im/service/intake/service.go` | машина из ядра | 1 |
| `internal/im/service/transition/pgrepo.go`, `transitiontest/`, `internal/im/service/storing/incident_machine_queries.go` | `Repo.ReadFamily` | 2 |
| `internal/im/service/transition/view.go` | `Actions`, основной выборки, `CanEditScenario` | 2 |
| `internal/im/service/transition/view_form.go`, `internal/im/machine/formrefs.go` | `Form`, `FormRefs` | 3 |
| `internal/im/service/transition/view_card.go` | `Presentation`: бейдж, пояснение, отношение | 4 |
| `internal/im/service/catalog/catalog.go` | строки и ICU | 5 |
| `internal/im/appservice/operator/directory.go`, `world.go` | `Directory`, мир 4в | 6 |
| `internal/im/appservice/operator/deps.go`, `clock.go`, `internal/im/appservice/appservice.go`, `internal/im/handler/v1/common.go`, `internal/im/service/intake/service.go` | `Deps`, сборка, одно ядро, `CreateContext` | 7 |
| `internal/im/handler/handler.go`, `cmd/im/main.go`, `internal/im/handler/test/common.go` | новая подпись `GetHandler` | 7 |
| `internal/im/handler/operator/handler.go`, `handler_test.go`, `session.go`, `session_test.go` | `Deps` в обработчике, тест маршрутов | 7 |
| `internal/im/handler/operator/stubs.go` | снятие заглушек | 9–12, 14, 17, 18, 20, 21 |
| `internal/im/handler/operator/problem.go` | `CodeInternal` | 8 |
| `internal/im/handler/test/operator_helpers_test.go`, `operator_contract_test.go` | клиент оператора и сверка с контрактом | 8 |
| `internal/im/appservice/incident/incident.go`, `internal/im/appservice/operator/load.go` | видимость, чтение инцидента | 9 |
| `internal/im/handler/operator/view_summary.go`, `view_card.go`, `view_actions.go`, `view_journal.go` | виды ответов | 9–10 |
| `internal/im/handler/operator/incident.go`, `reply.go`, `reference.go`, `linked.go`, `testsupport.go` | маршруты чтения, ответ целиком | 9–12, 20, 21 |
| `internal/im/handler/operator/mapping.go`, `params.go` | отображение в HTTP, 404 раньше `If-Match` | 13, 15 |
| `internal/im/handler/operator/transition.go`, `bulk.go`, `merge.go` (идемпотентность — в `reply.go`) | маршруты записи и идемпотентность | 14, 16–18 |
| `internal/im/appservice/operator/touch.go`, `internal/im/service/storing/incident_machine_queries.go` | `TouchAfterMerge` | 19 |
| `internal/im/handler/test/operator_flows_test.go`, `operator_vectors_test.go` | уровни А и Б | 22, 23 |
| `~/Work/stand/check-operator-transitions.sh`, `check-operator-api.sh` | уровень Г | 24 |
| `docs/adr/002-…`, `005-…`, `40-plan.md`, `30-local-stand.md` | документы | 25 |

---

### Task 1: Хвосты ядра для HTTP

**Files:** Modify `internal/im/service/transition/{run.go,errors.go,core.go,runall.go,merge.go}`, `internal/im/service/intake/service.go`. Test: `internal/im/service/transition/core_contract_test.go`, `internal/im/service/intake/service_test.go`.

**Interfaces:**
- Consumes: `Core`, `Refusal`, `Result`.
- Produces: `const KeyUnknownAction = "workflow.error.unknown_action"` (вместо `keyUnknownAction`), `var ErrDuplicateID = errors.New("transition: duplicate incident id")`, `func (c *Core) Machine() *machine.Machine`.

- [ ] **Step 1: Failing test**

```go
func TestRunAllDuplicateIDIsErrDuplicateID(t *testing.T)  // RunAll с ["a","a"]: errors.Is(err, ErrDuplicateID)
func TestMergeDuplicateIDIsErrDuplicateID(t *testing.T)   // Merge с IDs ["a","a"] и с PrimaryID в IDs: errors.Is(err, ErrDuplicateID), ничего не записано
func TestUnknownActionKey(t *testing.T)                   // Run неизвестного перехода: Refusal.Key == KeyUnknownAction
func TestEmptyResultMapsAreNotNil(t *testing.T)           // RunAll с пустым IDs и Merge без присоединяемых: Journal, External, Facts, Canceled != nil, len 0; Incidents != nil
func TestCoreMachine(t *testing.T)                        // New(m).Machine() == m
// intake:
func TestNewServiceTakesMachineFromCore(t *testing.T)     // s.machine == core.Machine() (тот же указатель)
```

- [ ] **Step 2: Run** `source ~/go/offline-env.sh && go test -race ./internal/im/service/transition/ ./internal/im/service/intake/`. Expected: ошибки сборки или падение названных тестов.

- [ ] **Step 3: Implement.** Экспорт `KeyUnknownAction`, замена всех вхождений. `ErrDuplicateID` оборачивается в сообщениях повтора (`fmt.Errorf("…: %w", ErrDuplicateID)`) в `runall.go` и `merge.go`. Пустой итог — одна функция `emptyResult()`; `Compare` и `Same` пустое и `nil` не различают — проверить, что тесты векторов проходят (Step 4: `TestTransitionVectors` без базы и `TestTransitionVectorsOnPostgres` с базой). `Core.Machine`. `intake.NewService` убирает свой `machine.Vendored()` и берёт `core.Machine()`; подпись `NewService` не меняется, `error` в ней остаётся (его дают проверки аргументов и `ApplyUniqueKey`), уходит только ветка ошибки загрузки машины. У типа `Core` — комментарий контракта вызова (решение 61).

- [ ] **Step 4: Run.** `source ~/go/offline-env.sh && go test -race $(go list ./internal/im/... | grep -v /handler/test) && TESTDB='postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable' && IM_TEST_DB_URL=$TESTDB go test -race ./internal/im/handler/test/ -run 'TestTransitionVectorsOnPostgres' && golangci-lint run ./... && gofmt -l internal/im`. Expected: зелёно, вывод `gofmt` пуст.

- [ ] **Step 5: Commit.** Сообщение: «Этап 4в: хвосты ядра — ключ неизвестного действия, ошибка повтора id, непустые карты итога, машина приёма из ядра». `git add internal/im/service`.

---

### Task 2: Чтение ядра: действия, основной выборки

**Files:** Create `internal/im/service/transition/view.go`, `view_test.go`. Modify `core.go` (`Repo`), `pgrepo.go`, `transitiontest/` (`MemRepo.ReadFamily`), запрос семьи в `internal/im/service/storing/incident_machine_queries.go`. Test: новый файл `internal/im/handler/test/transition_read_test.go`.

**Interfaces:**
- Consumes: `machine.Availability`, `machine.Definition`, `Scope`, `operation.refs`.
- Produces:

```go
// Repo gets:
ReadFamily(ctx model.AppContext, customer uuid.UUID, ids []string) ([]Row, error)

// ViewOp is who looks at what, for the read path of the core.
type ViewOp struct {
    Customer    uuid.UUID
    Me, Surface string
    Now         int64
}

// ActionView is one line of engine.actions.
type ActionView struct {
    ID, Kind, LabelKey, Style, Icon, FormID, Navigate string // Kind is "transition" or "nav"
    Enabled, BulkAllowed bool
    Hint  *machine.Fail // why not enabled
    Guard string
    Form  *FormView     // only when Enabled and the transition has a form (Task 3)
}

func (c *Core) Actions(ctx model.AppContext, repo Repo, w World, op ViewOp, incident map[string]any) ([]ActionView, error)
func (c *Core) CanEditScenario(ctx model.AppContext, repo Repo, w World, op ViewOp, incident map[string]any) (bool, error)
func (c *Core) MergePrimary(w World, me string, list []map[string]any) (string, error) // "" — нет основного
func (c *Core) BulkPrimary(w World, me string, list []map[string]any) (string, error)
func (c *Core) Transition(id string) (map[string]any, bool)
```

`FormView` в этой задаче — пустая структура, поле `Form` всегда `nil`; наполняется в задаче 3.

- [ ] **Step 1: Failing test**

```go
func TestMemReadFamilyEqualsLockFamily(t *testing.T) // на MemRepo: строки ReadFamily равны строкам LockFamily (блокировок у памяти нет, о них тест ничего не утверждает)
func TestActionsMirrorEngine(t *testing.T)         // new, свой оператор, card: claim, close, transfer; порядок — primary, затем nav, затем остальные; скрытые условием с onFail hide — нет
func TestActionsOfSurfaceOnly(t *testing.T)        // queue: нет hold (surface только card); merge нет ни на какой поверхности
func TestActionsDisabledHasHint(t *testing.T)      // нарушено условие без hide: Enabled false, Hint.Key — ключ условия, Guard — имя
func TestActionsNavOnlyEnabled(t *testing.T)       // действие навигации с невыполненным условием не попадает в список
func TestMergePrimaryAsMachine(t *testing.T)       // свой in_progress важнее new; затем приоритет, затем occurredAt; пустой список — ""
func TestBulkPrimaryOnlyClosable(t *testing.T)     // основной — среди тех, кого можно закрыть из queue
func TestCanEditScenario(t *testing.T)             // владелец в in_progress — true; чужой — false; on_hold — false
```

Плюс в `internal/im/handler/test/transition_read_test.go` (единственная проверка, что чтение не блокирует): `TestReadFamilyOnPostgres` — другая открытая транзакция держит `FOR UPDATE` на строке, `ReadFamily` возвращает строку без ожидания.

- [ ] **Step 2: Run** `source ~/go/offline-env.sh && go test -race ./internal/im/service/transition/`. Expected: FAIL (нет символов).

- [ ] **Step 3: Implement.** `Actions` — порядок и отбор `engine.actions`; ранг `primary` 0, навигация 1, остальное 2; стабильная сортировка. `Scope` — как `guardScope`: `Incidents` — `ReadFamily` по этому инциденту, `Refs` — через `Repo.Candidates` тем же кодом `operation.refs` (вынести так, чтобы чтение не создавало `operation`). `MergePrimary` и `BulkPrimary` — `Definition("mergePrimary"|"bulkPrimary", [list, me], w)`; `Definition` без списка инцидентов на факте с `ref` даёт ошибку — это и есть ожидаемое поведение, таких фактов у двух определений нет. Запрос `ReadFamily` — общий с `LockFamily`, отличается только суффиксом блокировки; вне транзакции.

- [ ] **Step 4: Run.** `source ~/go/offline-env.sh && go test -race $(go list ./internal/im/... | grep -v /handler/test) && TESTDB='postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable' && IM_TEST_DB_URL=$TESTDB go test -race ./internal/im/handler/test/ -run 'TestReadFamilyOnPostgres' && golangci-lint run ./...`. Expected: зелёно.

- [ ] **Step 5: Commit.** «Этап 4в: чтение ядра — действия, основной выборки, ReadFamily». `git add internal/im`.

---

### Task 3: Чтение ядра: форма

**Files:** Create `internal/im/service/transition/view_form.go`, `view_form_test.go`, `internal/im/machine/formrefs.go`, `formrefs_test.go`. Modify `view.go`, типы `formDef` и `fieldDef` в `form.go` (добавить `defaultExpr`, `warnings`, `enabledExpr`, `disabledKey`, `notes`, каких нет).

**Interfaces:**
- Consumes: `machine.UIRule`, `Scope.Option`, факт `transferTargets`.
- Produces:

```go
type OptionView struct {
    ID, LabelKey string
    Disabled     bool
    ReasonKey    string
    Warning      []any // [key, vars] or nil
}
type RuleView struct {
    Visible, Required bool
    DependsOn         string
    ByValue           map[string]RuleView
}
type FieldView struct {
    Name, Kind, LabelKey, Source string
    Options      []OptionView
    DefaultValue string
    Rules        RuleView
}
type FormView struct {
    ID, TitleKey, ConfirmKey, Style string
    Note   []any // [key, vars] or nil
    Fields []FieldView
}
func (c *Core) Form(ctx model.AppContext, repo Repo, w World, op ViewOp, formID string, incident map[string]any) (*FormView, error)
```

`Actions` заполняет `ActionView.Form` у доступных переходов с формой.

- [ ] **Step 1: Failing test**

```go
func TestFormOptionsByOptionExpr(t *testing.T)      // hold: только причины, которые ставит оператор (setBy), системных нет
func TestFormDisabledOptionHasReason(t *testing.T)  // close: вариант, не прошедший enabledExpr, — Disabled, ReasonKey == disabledKey
func TestFormWarningFirstTrue(t *testing.T)         // поле с warnings: первое истинное, подстановки посчитаны; ни одного — nil
func TestFormDefaultOnlyIfAvailable(t *testing.T)   // defaultExpr дал отключённый вариант — DefaultValue ""
func TestFormDependsOn(t *testing.T)                // close: comment зависит от resultId: DependsOn "resultId", ByValue по ""+варианты, верхний уровень равен ByValue[""]
func TestFormNoteVars(t *testing.T)                 // reopen или transfer: Note [key, vars] с ownerName, filledSteps, totalSteps, minutesSinceClose
func TestFormTransferTargets(t *testing.T)          // source transferTargets: варианты из факта, optionExpr убрал себя
func TestActionsCarryForm(t *testing.T)             // доступный transfer — Form != nil; недоступный — nil; claim без формы — nil
// internal/im/machine/formrefs_test.go:
func TestFormRefsParsed(t *testing.T)               // FormRefs("…requiredExpr") даёт имена form.* из разобранного выражения; подстрока в строковом литерале и в имени другого поля их не даёт; выражение без form.* — пусто
```

- [ ] **Step 2: Run** `source ~/go/offline-env.sh && go test -race ./internal/im/service/transition/ ./internal/im/machine/ -run 'TestForm|TestActionsCarryForm'`. Expected: FAIL.

- [ ] **Step 3: Implement** по `form` и `noteFor` из `engine.js:654–720`; пути правил — `forms.<id>.fields.<name>.<expr>`, как уже разбирает `machine.UIRule`. Зависимость `dep` — первое имя `form.*` в `requiredExpr` или `visibleExpr`: из `cel.formRefs` прототипа; в Go — новый метод `(*Machine).FormRefs(where string) []string` пакета `internal/im/machine` (не `service/transition`) по разобранному выражению, а не поиском подстроки. `Option` — через `Scope.Option`.

- [ ] **Step 4: Run.** `source ~/go/offline-env.sh && go test -race $(go list ./internal/im/... | grep -v /handler/test) && golangci-lint run ./...`. Expected: зелёно (в том числе `./internal/im/machine/`).

- [ ] **Step 5: Commit.** «Этап 4в: чтение ядра — форма перехода». `git add internal/im`.

---

### Task 4: Чтение ядра: бейдж, пояснение, отношение

**Files:** Create `internal/im/service/transition/view_card.go`, `view_card_test.go`.

**Interfaces:**
- Consumes: `machine.Definition`, `machine.UIRule`, разделы машины `badges`, `cardNotes`.
- Produces:

```go
type BadgeView struct {
    Label, Style, Template string
    Vars map[string]any
}
type NoteView struct {
    Key, Style string
    Vars map[string]any
}
type Presentation struct {
    Addressee, Ownership string
    IsDone, ClosedFalseAlarm bool
    Badge *BadgeView
    Note  *NoteView
}
func (c *Core) Present(ctx model.AppContext, repo Repo, w World, op ViewOp, incident map[string]any, enabled []string) (*Presentation, error)
```

- [ ] **Step 1: Failing test**

```go
func TestPresentOwnership(t *testing.T)       // мой, чужой, ничей — значения definition ownership
func TestPresentAddressee(t *testing.T)       // pending_acceptance человеку и группе; иначе ""
func TestPresentBadgeOwnerName(t *testing.T)  // чужой в работе: Template и Vars с именем владельца ключом каталога
func TestPresentNoteByCardNotes(t *testing.T) // первое истинное правило cardNotes; enabled влияет на actions в правиле
func TestPresentClosedFalseAlarm(t *testing.T)
```

- [ ] **Step 2: Run** `source ~/go/offline-env.sh && go test -race ./internal/im/service/transition/ -run TestPresent`. Expected: FAIL.

- [ ] **Step 3: Implement** по `badge` (`engine.js:723`), `cardNote` (736), `badgeView`, `noteView` (`server.js:626`, 859). `Scope.Actions` — `enabled`.

- [ ] **Step 4: Run.** `source ~/go/offline-env.sh && go test -race $(go list ./internal/im/... | grep -v /handler/test) && golangci-lint run ./...`. Expected: зелёно.

- [ ] **Step 5: Commit.** «Этап 4в: чтение ядра — бейдж, пояснение, отношение к инциденту». `git add internal/im`.

---

### Task 5: Каталог строк

**Files:** Create `internal/im/service/catalog/catalog.go`, `catalog_test.go`.

**Interfaces:**
- Consumes: `operatorapi.StringsRU`, `operatorapi.StringsEN`.
- Produces:

```go
const DefaultLocale = "ru"
type Catalog struct { /* … */ }
func New(ru, en []byte) (*Catalog, error)
func Vendored() (*Catalog, error)
func (c *Catalog) Text(locale, key string, vars map[string]any) string
```

- [ ] **Step 1: Failing test**

```go
func TestTextSubstitutes(t *testing.T)      // "{name}" и число как есть; нет подстановки — "{name}" остаётся, как icu прототипа
func TestPluralRu(t *testing.T)             // таблица n: 1, 21 — one; 2, 3, 4, 22 — few; 0, 5, 11, 12, 14, 25, 111 — many; нет формы many — other; # = n
func TestPluralEn(t *testing.T)             // 1 — one; 0, 2, 21 — other
func TestNestedKeyVar(t *testing.T)         // подстановка ["workflow.close.false_alarm"] и [ключ, {vars}] переводятся
func TestFallback(t *testing.T)             // нет в en — ru; нет нигде — сам ключ
func TestEveryPluralStringRenders(t *testing.T) // все строки каталога с plural на обоих языках, n 0, 1, 2, 5: нет "{" в итоге
```

- [ ] **Step 2: Run** `source ~/go/offline-env.sh && go test -race ./internal/im/service/catalog/`. Expected: FAIL.

- [ ] **Step 3: Implement** (решение 57). Разбор — по `icu` и `render` (`server.js:513`, 540). Вложенные скобки у `plural` считать по глубине.

- [ ] **Step 4: Run.** `source ~/go/offline-env.sh && go test -race ./internal/im/service/catalog/ && golangci-lint run ./...`. Expected: зелёно.

- [ ] **Step 5: Commit.** «Этап 4в: каталог строк и подстановки на сервере». `git add internal/im/service/catalog`.

---

### Task 6: Память об операторах и мир этапа 4в

**Files:** Create `internal/im/appservice/operator/{directory.go,world.go,directory_test.go,world_test.go}`. Modify `internal/im/handler/test/transition_world_test.go`.

**Interfaces:**
- Consumes: `transition.World`, `transition.NewServerWorld`, `transition.WorldStore`, `transition.GroupTree`, образец — `intakeRest` (`internal/im/service/intake/world.go`).
- Produces:

```go
type Directory interface {
    Remember(u *model.User)
    Person(id string) (*model.User, bool)
    People() []*model.User // in the order of the number User.ID (not of the string id: "9" before "10")
}
func NewSeenDirectory() *SeenDirectory

// NewWorld is the world of the operator routes of stage 4c (decision 45).
func NewWorld(ctx model.AppContext, store transition.WorldStore, tree transition.GroupTree, dir Directory, user *model.User) transition.World

const AgentStateNow = "ready" // STAGE5
```

- [ ] **Step 1: Failing test**

```go
func TestSeenDirectoryRemembers(t *testing.T)       // Remember дважды — одна запись, новое имя и права заменяют старые; People по числу `User.ID` (id 9 раньше 10, а не по строке); копия: правка входа после Remember не меняет запись
func TestSeenDirectoryConcurrent(t *testing.T)      // параллельные Remember и People под -race
func TestWorldOtherPerson(t *testing.T)             // can другого по его правам; незнакомый — false; isOperator — знакомый; transferTargets — все знакомые
func TestWorldAgentState(t *testing.T)              // знакомый — ready; незнакомый — offline; me — ready
func TestWorldStage7Facts(t *testing.T)             // isGroup false, members [], dutyGroups []
func TestWorldStage6Facts(t *testing.T)             // stepsFilled false, Progress 0 0, StepNumber 0, ShareAnswers 0, SetCursor nil
func TestWorldActorName(t *testing.T)               // dispatcher, system, "" — ["workflow.label.unassigned"], знакомый — Name, незнакомый — id
func TestWorldUnknownFactIsError(t *testing.T)      // неизвестный факт — ошибка, как intakeRest
```

И в `internal/im/handler/test/transition_world_test.go` по образцу `TestServerWorldOnDatabase` из этого файла: `TestWorldAccessOfOtherPerson` — у другого с группой правила `access` истинно, без группы — ложно.

- [ ] **Step 2: Run** `source ~/go/offline-env.sh && TESTDB='postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable' && go test -race ./internal/im/appservice/operator/ && IM_TEST_DB_URL=$TESTDB go test -race ./internal/im/handler/test/ -run 'TestWorldAccessOfOtherPerson'`. Expected: FAIL.

- [ ] **Step 3: Implement** (решение 45). Каждая заглушка — с тегом `STAGE5`, `STAGE6` или `STAGE7` в комментарии, как в `intakeRest`. `Remember` хранит копию `*model.User` с копией карт и срезов.

- [ ] **Step 4: Run.** `source ~/go/offline-env.sh && TESTDB='postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable' && go test -race ./internal/im/appservice/operator/ && IM_TEST_DB_URL=$TESTDB go test -race ./internal/im/handler/test/ -run 'TestWorldAccessOfOtherPerson' && golangci-lint run ./...`. Expected: зелёно.

- [ ] **Step 5: Commit.** «Этап 4в: память об операторах и мир операторских маршрутов». `git add internal/im/appservice/operator internal/im/handler/test`.

---

### Task 7: Зависимости и сборка

**Files:** Create `internal/im/appservice/operator/deps.go`, `clock.go`, `clock_test.go`. Modify `internal/im/appservice/appservice.go`, `internal/im/handler/handler.go`, `internal/im/handler/v1/common.go`, `internal/im/handler/operator/{handler.go,handler_test.go,auth.go,session.go,session_test.go}`, `internal/im/service/intake/service.go`, `cmd/im/main.go`, `internal/im/handler/test/common.go`, `internal/im/model/config.go`. Test: `internal/im/handler/test/operator_wiring_test.go`.

**Interfaces:**
- Consumes: `idempotency.NewMemoryStore`, `catalog.Vendored`, `transition.NewStoreRepo`, `NewWorld`.
- Produces:

```go
// package operator (internal/im/appservice/operator)
type Deps struct {
    Core        *transition.Core
    Repo        transition.Repo
    Store       Store // read side, narrow interface of this package
    Catalog     *catalog.Catalog
    Directory   Directory
    World       func(ctx model.AppContext, user *model.User) transition.World
    ViewWorld   func(ctx model.AppContext, user *model.User) transition.World
    Visible     func(ctx model.AppContext, user *model.User, guid uuid.UUID) (bool, error) // nil until Task 9 wires incident.AppService.Visible in appservice.go
    Context     func(c context.Context) model.AppContext // filled by GetHandler with v1.CreateContext
    Now         func() int64 // ms
    Actor       func(user *model.User) string
    Idempotency idempotency.Store
    Clock       *TestClock // nil unless IM_TEST_SUPPORT
}

// package operator, clock.go: the clock itself is made here, the flag, ClockFor and the route are Task 21
type TestClock struct { /* atomic offset, ms */ }
func NewTestClock() *TestClock
func (c *TestClock) Advance(sec int64) // offset starts at 0
func (c *TestClock) Now() int64        // time.Now().UnixMilli() plus the offset

// package handler
func GetHandler(handler *v1.Handler, deps opapp.Deps, logger logrus.FieldLogger) (http.Handler, error) // opapp — import alias of appservice/operator
// package handler/operator
func NewHandler(auth UserAuthenticator, deps opapp.Deps, logger logrus.FieldLogger) *Handler
// package v1: wrapper, createContext stays (about 18 files use it)
func CreateContext(c context.Context) model.AppContext
// package intake
func (s *Service) Core() *transition.Core
// package appservice
AppServices.Operator opapp.Deps
AppServices.Intake   *intake.Service
```

В `model.Config`: `TestSupport bool` `envconfig:"IM_TEST_SUPPORT" default:"false"`. `Authenticate` вызывает `deps.Directory.Remember(user)`, если `Directory != nil`. `Store` — только методы, которые нужны чтению, с нынешними подписями `storing`: `GetMachineIncidents`, `MachineIncidentsLinkedTo`, `MachineIncidentsOfEvent`, `GetJournalEntries`, `GetEvent`, `GetSource`, `GetSourceType`, `GetSourceEventType`, `GetPriority`, `GetIncidentRule`, `GetScenarioVersion`, `GetSourceGroupGUIDs`, `GetSourceGroup`.

- [ ] **Step 1: Failing test**

```go
// handler_test.go (решение 64): переделать один раз; следующие задачи этот тест не трогают
func TestEveryContractOperationIsRouted(t *testing.T) // для каждой операции контракта в engine.Routes() есть метод и путь testBasePath + op.path с :param; число операций = NumMethod ServerInterface; обработчики не вызываются; implementedOperations удалён
func TestStubAnswers501(t *testing.T)                 // GET /operator/incidents/counters: 501, NOT_IMPLEMENTED, details {method, route}
func TestAuthenticateRemembers(t *testing.T)          // newTestEngine с Deps{Directory}: после запроса с токеном Directory.Person(id) есть
// session_test.go
func TestSessionShowsMachinePermissions(t *testing.T) // ожидание agentState offline → ready (строка 78); остальное как было
// operator_wiring_test.go
func TestOneCoreForIntakeAndOperator(t *testing.T)    // require.Same(AppServices.Intake.Core(), AppServices.Operator.Core): одно ядро, а не только одна машина (machine.Vendored — общий объект)
// internal/im/appservice/operator/clock_test.go, без базы
func TestTestClockOffsetStartsAtZero(t *testing.T)    // Now() на новых часах — time.Now() с точностью до секунды; Advance(3600) сдвигает Now на час вперёд
```

- [ ] **Step 2: Run** `source ~/go/offline-env.sh && TESTDB='postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable' && go test -race ./internal/im/handler/operator/ ./internal/im/appservice/operator/ && IM_TEST_DB_URL=$TESTDB go test -race ./internal/im/handler/test/ -run 'TestOneCoreForIntakeAndOperator'`. Expected: FAIL (нет `Deps`, сборка не идёт).

- [ ] **Step 3: Implement.** Ядро и его машина создаются в `GetServices` до всех сервисов и передаются в `initEventAppService` как параметр (сейчас они внутри неё, `appservice.go:318–327`): одно ядро на приём событий и операторские маршруты (строка ADR-005 про машину приёма). `NewHandler` принимает пустые `Deps` — на этом стоят `newTestEngine` и `session_test.go`; все вызовы `NewHandler` в тестах (`handler_test.go:49`, 279, `session_test.go:105`) передают `opapp.Deps{}`. `v1.CreateContext` — обёртка над `createContext`, без переименования; `GetHandler` кладёт её в `deps.Context`, если поле пусто (`appservice` не может импортировать `v1`); обработчик передаёт `c` — `*gin.Context` и есть `context.Context`, как в `v1`. `Actor` — `strconv.FormatInt(user.ID, 10)`. `Now` — `Clock.Now()`, если часы есть, иначе `time.Now().UnixMilli()`; те же часы идут в `NewMemoryStore` (решение 54). `TestClock` с `NewTestClock`, `Now`, `Advance` пишется здесь, целиком (сдвиг 0 до первого `Advance`); в задаче 21 добавляются только флаг, `ClockFor`, маршрут и его тесты. `World` и `ViewWorld` — один `NewWorld`. `Visible` в сборке здесь не заполняется (`nil`): обработчики до задачи 9 его не зовут, `paramError` при `nil` ведёт себя как раньше (задача 15); подключение — в задаче 9.

- [ ] **Step 4: Run.** `source ~/go/offline-env.sh && go test -race $(go list ./internal/im/... | grep -v /handler/test) && make test-local 2>&1 | tail -15 && golangci-lint run ./...`. Expected: зелёно; заглушки по-прежнему 501.

- [ ] **Step 5: Commit.** «Этап 4в: зависимости операторских маршрутов, общая сборка, одно ядро». `git add cmd internal`.

---

### Task 8: Клиент тестов и сверка с контрактом

**Files:** Create `internal/im/handler/test/operator_helpers_test.go`, `operator_contract_test.go`. Modify `api/im/operator/` (новая копия контракта, шаг 0), `internal/im/handler/operator/problem.go`, `problem_test.go`, `internal/im/handler/test/common.go` (пакетная `V1Handler`).

**Interfaces:**
- Consumes: `operatorapi.Contract`, `openapi3filter`, `routers/legacy`, `HTTPHandler`, `FakeCloudUsers`, `operator.Register`.
- Produces:

```go
// package handler/operator, problem.go (решение 62)
const CodeInternal = "INTERNAL_ERROR" // typed as the other codes; in the contract since IM 9526a09

// tests
type operatorClient struct { /* t, token, user, handler */ }
// operator registers a user in FakeCloudUsers with the machine rights perms, its own user group and an access rule to f.source, and calls GET /operator/session once so that Directory knows him.
func (f *intakeFixture) operator(t *testing.T, id int64, perms ...string) *operatorClient
func (o *operatorClient) grant(t *testing.T, source *model.Source)   // rule to one more source
func (o *operatorClient) do(method, path string, body any, headers ...string) *apiReply  // with checkContract
func (o *operatorClient) raw(method, path string, body any, headers ...string) *apiReply // without it (decision 63)
type apiReply struct { Status int; Header http.Header; Body map[string]any; Raw []byte } // Body — UseNumber
func checkContract(method, path string, status int, header http.Header, raw []byte) error
// engine is a handler of its own over a copy of AppServices.Operator after edit; a client of it is o.on(h).
// It always builds Deps.Now and Deps.Idempotency (idempotency.NewMemoryStore) from one clock: the Deps.Clock the edit sets, else the real time (Tasks 16, 21, 22 rely on it).
func (f *intakeFixture) engine(t *testing.T, edit func(*opapp.Deps)) http.Handler
func (o *operatorClient) on(h http.Handler) *operatorClient
// patchedCore is a core over the vendored machine after patch (machine.Load, transition.New).
func patchedCore(t *testing.T, patch func(m map[string]any)) *transition.Core
// timedIncidents is newIncidents with Timers {"reaction":{"due":now+10 min}}: newIncidents lays no timers.
func (f *intakeFixture) timedIncidents(t *testing.T, n int, edit func(inc *model.Incident)) []*model.Incident
```

- [ ] **Step 0: Новая копия контракта** (решение 62, 63). В IM контракт уже поправлен коммитом `9526a09`: `INTERNAL_ERROR` и `NOT_IMPLEMENTED` в `Problem.code`, `412` у `detachLinked` и `detachAllLinked`. В сервере: `git -C /mnt/hgfs/VmWareShared/soul2home/IM status --porcelain -- Specification/Workflow_machine` — пусто, затем `make vendor-operator-contract && cat api/im/operator/SOURCE` — `SOURCE` называет `9526a09`. Сгенерированный код изменился (`git status -- api/im/operator`) — `source ~/go/offline-env.sh && PATH=$PATH:$HOME/go/bin make gen-api-operator`, затем `go build ./...`. Сюда же `TestMachineIntakePinned`, если он упал на новой копии: правится только отметка копии, определения те же. Коммит — вместе с шагом 5 этой задачи (`git add api/im/operator`).

- [ ] **Step 1: Failing test**

```go
func TestCheckContractAcceptsSession(t *testing.T)       // настоящий ответ GET /operator/session проходит
func TestCheckContractRejectsBadBody(t *testing.T)       // тот же ответ без обязательного поля — ошибка
func TestCheckContractRejectsUnknownStatus(t *testing.T) // 418 на getIncident — ошибка; 404 на /test/clock — ошибка
func TestCheckContractServerStatuses(t *testing.T)       // 400, 401, 500, 501 на операции, где их нет: тело Problem проходит, тело не Problem — ошибка
func TestCheckContractServerCodes(t *testing.T)          // 500 {INTERNAL_ERROR}, 501 {NOT_IMPLEMENTED} проходят по Problem.code самого контракта; 500 {code NOPE} — ошибка
func TestCheckContractDetach412(t *testing.T)         // 412 на detachLinked проходит с телом Problem по самому контракту; 412 на getIncident без объявления — ошибка
func TestCheckContractReadsProblemJSON(t *testing.T)     // application/problem+json разбирается
func TestCheckContractLeavesContractAlone(t *testing.T)  // operatorapi.Contract после загрузки — те же байты
func TestTimedIncidentHasReactionTimer(t *testing.T)     // ToMachine даёт timers.reaction.due
```

- [ ] **Step 2: Run** `source ~/go/offline-env.sh && TESTDB='postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable' && IM_TEST_DB_URL=$TESTDB go test -race ./internal/im/handler/test/ -run 'TestCheckContract|TestTimedIncident'`. Expected: FAIL.

- [ ] **Step 3: Implement.** `checkContract`: `openapi3.NewLoader().LoadFromData(operatorapi.Contract)`; перечень `Problem.code` не дополняется — контракт знает оба кода (решение 62); `legacy.NewRouter(doc)`; адрес запроса — без хоста, `model.BasePath + path` (`http://localhost/…` даёт «no matching operation»); `openapi3filter.ValidateResponse` с `Options: &openapi3filter.Options{IncludeResponseStatus: true}` (без него необъявленный статус проходит). `openapi3filter.RegisterBodyDecoder("application/problem+json", openapi3filter.JSONBodyDecoder)` — один раз в `init` тестового файла. Необъявленные у операции статусы — решение 63. `operatorClient.do` падает с телом ответа в сообщении. `FakeCloudClient.AuthUser` не менять: `AuthenticateUser` уже работает с копией (задача 7), а копия в подделке спрятала бы гонку от `TestParallelRequestsWithOneToken`. Правило доступа — через `IMClient`, чтобы дерево групп в `AppServices` его видело.

- [ ] **Step 4: Run.** `source ~/go/offline-env.sh && make test-local 2>&1 | tail -15 && golangci-lint run ./...`. Expected: зелёно.

- [ ] **Step 5: Commit.** «Этап 4в: новая копия контракта, клиент тестов со сверкой контракта». `git add api/im/operator internal`.

---

### Task 9: Видимость и `getIncident` — сводка

**Files:** Create `internal/im/appservice/operator/load.go`, `internal/im/handler/operator/incident.go`, `reply.go`, `view_summary.go`, `internal/im/handler/test/operator_card_test.go`. Modify `internal/im/appservice/incident/incident.go`, `internal/im/appservice/appservice.go` (`Deps.Visible` = `incident.AppService.Visible`), `stubs.go` (убрать `GetIncident`), `internal/im/handler/test/operator_wiring_test.go` (`require.Nil(deps.Visible)` становится `NotNil`).

**Interfaces:**
- Consumes: `GetIncidentByUserGroupIDs` и `ClosurePairs` — внутри `AppService.Visible` (в `Store` задачи 7 их нет и не нужно), `Deps.Visible`, `transition.ToMachine`, `Core.Present`, `Core.Actions`.
- Produces:

```go
func (s *AppService) Visible(ctx model.AppContext, user *model.User, guid uuid.UUID) (bool, error) // appservice/incident/incident.go

// Loaded is everything the views need of one incident.
type Loaded struct {
    Row          transition.Row
    Incident     *model.MachineIncident
    Event        *model.Event
    Priority     *model.Priority
    Rule         *model.IncidentRule   // nil — no rule
    ScenarioName string
    Source       *model.Source
    SourceType   *model.SourceType
    EventType    *model.SourceEventType
    SourceGroup  *model.SourceGroup    // nil — no group
    Linked       []*model.MachineIncident
    Siblings     []*model.MachineIncident
    Groups       []uuid.UUID
}
// Load reads the incident of user's customer and does not check that the incident itself is visible (the caller, h.find, calls Deps.Visible first); Linked and Siblings hold only what Visible passes for user. ErrEntryNotFound — нет такого.
func (d *Deps) Load(ctx model.AppContext, user *model.User, guid uuid.UUID) (*Loaded, error)

// package handler/operator
type reply struct { status int; etag string; body any } // a whole answer, ready to be written or remembered
func (h *Handler) viewer(c *gin.Context) *viewer
func (h *Handler) write(c *gin.Context, r reply)
// find writes nothing: nil reply — найден; иначе ответ 404 или 500 для write, для once и для failed выборки.
func (h *Handler) find(v *viewer, guid uuid.UUID) (*opapp.Loaded, *reply)
```

- [ ] **Step 1: Failing test**

```go
func TestGetIncidentCardBasics(t *testing.T)     // инцидент из f.timedIncidents: 200, контракт, ETag "\"1\"" равен version "1", number, state, eventGuid, alarmNumber, priority, eventType {id, name}, timer идёт, serverTime есть
func TestGetIncidentNotVisible(t *testing.T)     // оператор без правила доступа — 404 NOT_FOUND
func TestGetIncidentManagerNoBypass(t *testing.T)// manage без правила доступа — 404; тот же на старом GET /incidents/{guid} — 200
func TestGetIncidentNoMachineRights(t *testing.T)// без единого права машины, группа с правилом есть — 404
func TestGetIncidentOtherCustomer(t *testing.T)  // инцидент другого клиента при совпавшей группе — 404
func TestGetIncidentBadGuid(t *testing.T)        // /operator/incidents/xxx — 400 BAD_REQUEST
func TestSummaryLinkedAndSiblings(t *testing.T)  // linkedCount, siblingCount
func TestSummaryCountsVisibleOnly(t *testing.T)  // Review Focus 2: привязанный и сосед другого источника, вне доступа: в счётчиках их нет
func TestSummaryOwnerActorRef(t *testing.T)      // owner {id, kind operator, name, role ""}; пустой — null; неизвестный — id в name
func TestVisibleMissingIncident(t *testing.T)    // нет такого — false, nil
```

- [ ] **Step 2: Run** `source ~/go/offline-env.sh && TESTDB='postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable' && IM_TEST_DB_URL=$TESTDB go test -race ./internal/im/handler/test/ -run 'TestGetIncident|TestSummary|TestVisible'`. Expected: FAIL.

- [ ] **Step 3: Implement.** Ответ задачи — сводка без `actions`, `journal`, `alarm`: в контракте `IncidentCard` — это `IncidentSummary` плюс необязательные поля (`required` у карточки нет, у сводки — `guid`, `number`, `eventGuid`, `alarmNumber`, `state`, `version`; проверено по `openapi.json`), поэтому `TestGetIncidentCardBasics` проходит сверку с контрактом; остальное добавляет задача 10. Видимость самого инцидента проверяет `find`: сначала `Deps.Visible` (не виден — 404), потом `Load`; `Load` видимость основного не проверяет, а только отбирает видимых для `Linked` и `Siblings`. `Visible` — решение 46: сначала `HasAnyMachinePermission`, без проверки `IsManager`; проверка клиента — отдельным сравнением (`GetIncidentByUserGroupIDs` клиента не проверяет). `Load` — источники данных по решению 56; `Linked` и `Siblings` — по одной проверке `Deps.Visible` на строку. Удалённая ссылка (правило, сценарий) — поле `null`, не ошибка. `summary` — по `server.js:635–706`, поля решения 56; `version` — `strconv`; времена — `time.UnixMilli(...).UTC()`. Все ответы — через `viewer` (структура с `ctx`, `user`, `me`, `now`, `locale`, `world`); `ViewOp.Surface` у сводки — `queue`, у карточки — `card`.

- [ ] **Step 4: Run** ту же команду и `golangci-lint run ./...`. Expected: зелёно.

- [ ] **Step 5: Commit.** «Этап 4в: видимость инцидента и сводка карточки». `git add internal/im`.

---

### Task 10: Карточка целиком

**Files:** Create `internal/im/handler/operator/view_card.go`, `view_actions.go`, `view_journal.go`. Modify `view_summary.go`, `incident.go`, `operator_card_test.go`.

**Interfaces:**
- Consumes: `Core.Actions`, `Core.Present`, `Core.CanEditScenario`, `Store.GetJournalEntries`, `catalog.Text`.
- Produces: `func (v *viewer) card(l *opapp.Loaded) (*operatorgen.IncidentCard, error)` (`view_card.go`; дополняет сводку задачи 9), `func (v *viewer) actions(l *opapp.Loaded, surface string) ([]operatorgen.AvailableAction, error)` (`view_actions.go`; его же берёт задача 11), `func (v *viewer) journal(lines []*model.JournalEntry) []operatorgen.JournalEntry` (`view_journal.go`), `func journalRows(customer uuid.UUID, lines []transition.JournalEntry) ([]*model.JournalEntry, error)` — новые строки из `Result.Journal` через `transition.JournalRow`, тот же вид в карточке и в `journalEntries`.

- [ ] **Step 1: Failing test**

```go
func TestCardAlarm(t *testing.T)         // два инцидента одного события: alarm.siblings, status, allFalseAlarm; у одного — siblings []
func TestAlarmHidesInvisibleSibling(t *testing.T) // Review Focus 2: сосед вне доступа не попал в alarm.siblings: ни номера, ни владельца
func TestCardNoteFromMachine(t *testing.T) // пояснение чужого в работе: note.key, text отрендерен, vars
func TestCardActions(t *testing.T)       // new у оператора с правами: actions — claim, transfer, close; у close есть fieldOptions, fieldRules
func TestCardReadOnly(t *testing.T)      // владелец в in_progress — false; чужой — true
func TestCardJournalRendered(t *testing.T) // text по-русски, vars-ключ переведён, actor dispatcher — «Диспетчер», kind
func TestCardStage4cFields(t *testing.T) // scenario нет; media {cameras [], map null}; site null; scenarioProgress {0,0}
func TestCardDevices(t *testing.T)       // source, devices, sourceGroup {guid, name}
func TestCardJSONHasNoNilArrays(t *testing.T) // actions, journal, siblings — [] а не null
```

- [ ] **Step 2: Run** `source ~/go/offline-env.sh && TESTDB='postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable' && IM_TEST_DB_URL=$TESTDB go test -race ./internal/im/handler/test/ -run 'TestCard|TestAlarmHides'`. Expected: FAIL.

- [ ] **Step 3: Implement** по `card` (864), `alarmView` (887), `journalView` (707), `actionsFor` (601), `formView` (576), `timerState` (555), `holdTimerState` (569). Журнал — `model.JournalKindOf`, текст — `catalog.Text(locale, TemplateKey, Vars)`. `reason` действия — `catalog.Text` по `Hint`. `fieldOptions` — варианты с `label`, у `transferTargets` дополнительно `role`, `available`, `availabilityLabel` из `Directory` (`OptionView` из ядра их не несёт, обработчик берёт их из `Directory` по `ID`).

- [ ] **Step 4: Run** ту же команду и `golangci-lint run ./...`. Expected: зелёно.

- [ ] **Step 5: Commit.** «Этап 4в: карточка инцидента целиком». `git add internal/im`.

---

### Task 11: `getIncidentActions` и `getJournal`

**Files:** Modify `internal/im/handler/operator/incident.go`, `stubs.go`, `operator_card_test.go`.

**Interfaces:**
- Consumes: `viewer.actions`, `viewer.journal`.
- Produces: `GetIncidentActions`, `GetJournal` как методы `ServerInterface`.

- [ ] **Step 1: Failing test**

```go
func TestActionsDefaultSurfaceCard(t *testing.T) // без surface — как ?surface=card; hold есть у владельца
func TestActionsQueue(t *testing.T)              // ?surface=queue — hold нет
func TestActionsUnknownSurface(t *testing.T)     // ?surface=xxx — 200, переходов нет (как engine.actions: фильтр по поверхности)
func TestActionsNotVisible(t *testing.T)         // 404
func TestJournalWhole(t *testing.T)              // без pageSize — весь журнал, total, порядок at, guid
func TestJournalPage(t *testing.T)               // page=2&pageSize=1 — одна запись, total весь; pageSize больше длины; page за концом — items []
```

- [ ] **Step 2: Run** `source ~/go/offline-env.sh && TESTDB='postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable' && IM_TEST_DB_URL=$TESTDB go test -race ./internal/im/handler/test/ -run 'TestActions|TestJournal'`. Expected: FAIL.

- [ ] **Step 3: Implement.** Постраничность журнала — как маршрут `server.js:1649`. Пустой список — `[]`.

- [ ] **Step 4: Run** ту же команду и `golangci-lint run ./...`. Expected: зелёно.

- [ ] **Step 5: Commit.** «Этап 4в: действия инцидента и журнал». `git add internal/im`.

---

### Task 12: `listReasons` и `listTransferTargets`

**Files:** Create `internal/im/handler/operator/reference.go`, `internal/im/handler/test/operator_reference_test.go`. Modify `stubs.go`.

**Interfaces:**
- Consumes: `machine.Data` (`reasonCatalogs`), `Directory.People`, `Core.Form` (только с инцидентом: `Form(ctx, repo, w, op, formID, incident)` инцидент требует).
- Produces: `ListReasons`, `ListTransferTargets`; для вызова без `incidentGuid` — функция обработчика `func (v *viewer) allTargets() []operatorgen.TransferTarget`: все из `Directory.People()`, кроме себя, без вызова ядра и без инцидента (как `targets().filter(!isSelf)` прототипа). С видимым `incidentGuid` — `Core.Form` формы, у которой есть поле `source == transferTargets`; невидимый или несуществующий — `allTargets()`.

- [ ] **Step 1: Failing test**

```go
func TestReasonsHold(t *testing.T)            // 200, items машины, label по-русски
func TestReasonsUnknownCatalog(t *testing.T)  // 404 NOT_FOUND, workflow.error.catalog_not_found
func TestTargetsWithoutIncident(t *testing.T) // не вызывает Core.Form; второй оператор есть, себя нет; kind operator, name, available true (Directory общий на HTTPHandler: Contains, а не Equal)
func TestTargetsWithIncident(t *testing.T)    // без текущего адресата и владельца по optionExpr
func TestTargetsInvisibleIncident(t *testing.T) // невидимый и несуществующий incidentGuid: 200, ответ побайтно равен ответу без параметра, ничего об инциденте не выдаёт (решение 46)
func TestTargetsAfterRestartEmpty(t *testing.T) // новый Directory знает только вошедшего: [] (через Deps теста)
func TestTargetsHasNoLabelField(t *testing.T)   // как server.js: поле label не отдаётся
```

- [ ] **Step 2: Run** `source ~/go/offline-env.sh && TESTDB='postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable' && IM_TEST_DB_URL=$TESTDB go test -race ./internal/im/handler/test/ -run 'TestReasons|TestTargets'`. Expected: FAIL.

- [ ] **Step 3: Implement** по маршрутам `server.js:1670`, 1718, `targets` (988). Параметр `incidentGuid` разбирается обёрткой. `role`, `available`, `availabilityLabel` — из `Directory`, как в задаче 10.

- [ ] **Step 4: Run** ту же команду и `golangci-lint run ./...`. Expected: зелёно.

- [ ] **Step 5: Commit.** «Этап 4в: причины и адресаты передачи». `git add internal/im`.

---

### Task 13: Отображение итога ядра в HTTP

**Files:** Create `internal/im/handler/operator/mapping.go`, `mapping_test.go`. Modify `problem.go`.

**Interfaces:**
- Consumes: `transition.Refusal`, `transition.KeyUnknownAction`, `ErrFamilyChanged`, `ErrNotFound`, `ErrDuplicateID`, `*VersionConflict`, `catalog.Text`.
- Produces:

```go
type opKind int
const (opRun opKind = iota; opMerge)
type problemReply struct { Status int; Body operatorgen.Problem; Current bool /* add the card as current */; ConflictID string }
func refusalProblem(m *machine.Machine, cat *catalog.Catalog, kind opKind, r *transition.Refusal) problemReply
func errorProblem(cat *catalog.Catalog, err error) problemReply
```

- [ ] **Step 1: Failing test**

Таблица по решению 48; значения кодов читает из машины, а не из литералов там, где это код условия.

```go
func TestRefusalGuardCodesFromMachine(t *testing.T) // для каждого условия с errorCode или errorCodes в машине: 403 и этот код; guard заполнен
func TestRefusalGuardFailedDefault(t *testing.T)    // условие без кода — GUARD_FAILED
func TestRefusalAgentNotReady(t *testing.T)         // agentReady — 403 AGENT_NOT_READY (настоящий мир 4в всегда ready; на ленте вектор runAll fee20 даёт этот ответ через HTTP, задача 23)
func TestRefusalNotFrom(t *testing.T)               // 409 TRANSITION_NOT_ALLOWED_FROM_STATE, guard пуст
func TestRefusalForm(t *testing.T)                  // Code FORM_FIELD_INVALID — 422 он же; Code пуст — 422 FORM_FIELD_REQUIRED
func TestRefusalUnknownAction(t *testing.T)         // 404 NOT_FOUND
func TestRefusalMergeWrongState(t *testing.T)       // opMerge, NotFrom, без Guard — 422 BULK_SELECTION_INVALID, не 409
func TestRefusalMergeGuard(t *testing.T)            // opMerge с Guard — 403 по коду условия
func TestErrorConflict(t *testing.T)                // *VersionConflict и ErrFamilyChanged, в том числе обёрнутые — 412 VERSION_CONFLICT, Current true, ConflictID у VersionConflict — его ID
func TestErrorNotFound(t *testing.T)                // ErrNotFound — 404
func TestErrorDuplicateID(t *testing.T)             // ErrDuplicateID — 400 BAD_REQUEST
func TestErrorOther(t *testing.T)                   // fmt.Errorf — 500 INTERNAL_ERROR, текст ошибки не попал в тело
```

- [ ] **Step 2: Run** `source ~/go/offline-env.sh && go test -race ./internal/im/handler/operator/ -run 'TestRefusal|TestError'`. Expected: FAIL.

- [ ] **Step 3: Implement** (решения 48, 55). Текст сообщения — `catalog.Text`; `messageKey`, `messageVars` — из отказа. `ErrorCodes` условий — из `machine.Data`, по `Refusal.Guard` и `Refusal.Key`.

- [ ] **Step 4: Run** ту же команду и `golangci-lint run ./...`. Expected: зелёно.

- [ ] **Step 5: Commit.** «Этап 4в: отображение отказов и ошибок ядра в HTTP». `git add internal/im/handler/operator`.

---

### Task 14: `executeTransition`

**Files:** Create `internal/im/handler/operator/transition.go`, `internal/im/handler/test/operator_transition_test.go`. Modify `stubs.go`.

**Interfaces:**
- Consumes: `h.find`, `CheckIfMatch`, `Core.Run`, `Core.Transition`, `refusalProblem`, `errorProblem`, `viewer.card`.
- Produces:

```go
// transitionBody is the body of both transition routes, decoded with UseNumber: FormValues of the generated type would turn a non-string value into 400; values go through machine.Canon as in transitiontest.
type transitionBody struct {
    ExpectedState, IdempotencyKey, Surface string
    FormValues map[string]any
    // bulk only:
    IncidentGuids    []string
    ExpectedVersions *map[string]string
}
// transitionOp builds the Op of the core; surface stays as given (decision 58).
func transitionOp(customer uuid.UUID, id, transitionID, me string, now int64, form map[string]any, surface string, expect *int64) transition.Op
// runOne refuses a transition that is unknown, not manual or with bulk.mode merge (decision 49), then calls Core.Run. Shared by the single route and the selection: the selection must not reach Run with merge either.
func (h *Handler) runOne(c *gin.Context, l *opapp.Loaded, transitionID string, form map[string]any, surface string, expect *int64) (*transition.Result, reply, bool) // bool — успех; expect nil — версия не проверяется
func (h *Handler) ExecuteTransition(c *gin.Context, incidentGuid operatorgen.IncidentGuid, transitionId operatorgen.TransitionId, params operatorgen.ExecuteTransitionParams)
```

Порядок: разбор тела (плохой JSON — `400 BAD_REQUEST`; пустое тело — как `{}`) → `find` (404) → `CheckIfMatch` (428, 412 с `current`) → `expectedState` (412 с `current`, `workflow.error.version_conflict {state: [labelKey]}`) → `runOne`: проверка перехода (404 `unknown_action`), `Core.Run` с `Expect: {id: version}` → ответ.

- [ ] **Step 1: Failing test**

```go
func TestClaim(t *testing.T)                   // 200, контракт, incident.state in_progress, owner — я, ETag на 1 больше, journalEntries — claim, externalEffects [], canceledTimerTrigger null, navigate card
func TestTransitionMissingIfMatch(t *testing.T)// 428 PRECONDITION_REQUIRED
func TestTransitionOldIfMatch(t *testing.T)    // 412 VERSION_CONFLICT, current — карточка, ETag не менялся, журнал не менялся
func TestTransitionIfMatchStar(t *testing.T)   // * проходит
func TestTransitionIfMatchList(t *testing.T)   // "\"9\", \"1\"" проходит; W/"1" проходит
func TestExpectedStateMismatch(t *testing.T)   // 412, current
func TestUnknownTransition(t *testing.T)       // 404 NOT_FOUND, workflow.error.unknown_action
func TestAutomaticTransitionRefused(t *testing.T) // trigger не manual (из машины) — 404 unknown_action, ничего не записано
func TestMergeOnSingleRouteRefused(t *testing.T)  // 404 unknown_action, не 412
func TestWrongState(t *testing.T)              // resume у new — 409 TRANSITION_NOT_ALLOWED_FROM_STATE
func TestFormRequired(t *testing.T)            // hold без reasonId — 422 FORM_FIELD_REQUIRED; без изменений
func TestBadJSON(t *testing.T)                 // 400 BAD_REQUEST
func TestFormValueNotStringInSelect(t *testing.T) // hold, `reasonId: 5` и `reasonId: ["a"]`: оба — ровно 422 FORM_FIELD_INVALID (поле с источником; `offered` не строку не принимает), не 400; ничего не записано
func TestFormValueNotStringInText(t *testing.T)   // hold с верной причиной и `comment: 5`: ровно 200 (поле text без источника, значение непустое), не 400
func TestConcurrentClaimOneWins(t *testing.T)  // Review Focus 1: 8 горутин с одним If-Match: ровно один 200, остальные 412 с current; 500 нет; запись claim одна; версия +1
```

Плюс в пакете `operator`, без базы: `TestTransitionOpKeepsEmptySurface` — `transitionOp` с `surface` `""` даёт `Op.Surface == ""`, `expect` nil — `Op.Expect` без ключа.

- [ ] **Step 2: Run** `source ~/go/offline-env.sh && TESTDB='postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable' && IM_TEST_DB_URL=$TESTDB go test -race ./internal/im/handler/test/ ./internal/im/handler/operator/ -run 'TestClaim|TestTransition|TestExpectedState|TestUnknownTransition|TestAutomatic|TestMergeOnSingle|TestWrongState|TestFormRequired|TestFormValueNotString|TestTransitionOpKeepsEmptySurface|TestBadJSON|TestConcurrentClaim'`. Expected: FAIL.

- [ ] **Step 3: Implement.** Тело — `transitionBody`, а не сгенерированный тип. `journalEntries` — `Result.Journal[id]` через `journalRows` и `viewer.journal`; `externalEffects` — `Result.External[id]` со `status: "queued"`, пустой — `[]`; `canceledTimerTrigger` — `Result.Canceled[id]` или `null`; `navigate` — `ui.navigate` перехода; карточка — заново `Load` после фиксации; ошибка чтения после фиксации — 500, но журнал ошибок содержит слово `committed` (переход уже выполнен). `Result.After` — решение 59. `current` у 412 — свежий `Load` и `viewer.card`; инцидент исчез — 404.

- [ ] **Step 4: Run** ту же команду и `golangci-lint run ./...`. Expected: зелёно.

- [ ] **Step 5: Commit.** «Этап 4в: переход одного инцидента — версии, ожидаемое состояние, отказы». `git add internal/im`.

---

### Task 15: 404 раньше `If-Match`

**Files:** Modify `internal/im/handler/operator/params.go`, `handler.go`, `handler_test.go` (`newTestEngine` получает `Deps.Visible`, `TestMissingIfMatchGives428`, `TestParamErrorHandlerKeeps400WhenIfMatchIsPresent`); `internal/im/handler/test/operator_transition_test.go`.

**Interfaces:**
- Consumes: `userFromContext`, `Deps.Visible` (подключён в задаче 9; до неё `nil`).
- Produces: `func (h *Handler) paramError(c *gin.Context, err error, status int)`; свободная функция `ParamErrorHandler` удаляется, `Register` передаёт метод.

- [ ] **Step 1: Failing test**

```go
func TestMissingIfMatchOnUnknownIncident(t *testing.T)  // случайный UUID без If-Match — 404, не 428
func TestMissingIfMatchOnVisible(t *testing.T)          // виден — 428
func TestMissingIfMatchNoToken(t *testing.T)            // без токена — 401 раньше всего
func TestMissingIfMatchOnScenarioAnswer(t *testing.T)   // answer на чужом — 404; на своём без заголовка — 428
func TestBadGuidWithoutIfMatch(t *testing.T)            // 400 BAD_REQUEST
// в handler_test.go (пакет operator, без базы):
func TestMissingIfMatchGives428(t *testing.T)           // Deps.Visible да — 428; нет — 404 (заменяет прежний тест: случайный UUID без проверки видимости); Deps.Visible == nil (пустые Deps, как в session_test.go) — 428, как раньше
// в handler/test/operator_transition_test.go (база, f.operator):
func TestInvisibleIncidentIsNotFoundEverywhere(t *testing.T) // Review Focus 2: инцидент вне доступа, у оператора с manage и без: GET карточка, actions, journal, linked; POST transition без If-Match, со старым, с верным; DELETE linked и linked/{guid}; всюду 404, тело одно и то же
```

- [ ] **Step 2: Run** `source ~/go/offline-env.sh && TESTDB='postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable' && IM_TEST_DB_URL=$TESTDB go test -race ./internal/im/handler/test/ ./internal/im/handler/operator/ -run 'TestMissingIfMatch|TestBadGuidWithoutIfMatch|TestParamErrorHandlerKeeps|TestInvisibleIncident'`. Expected: FAIL. `TestInvisibleIncidentIsNotFoundEverywhere` включается целиком только после задачи 20: до неё маршруты linked — 501; пока он с `t.Skip("task 20")`, а задача 20 убирает пропуск.

- [ ] **Step 3: Implement** (решение 47). Ошибка `Visible` — 500. `Deps.Visible == nil` (пустые `Deps` в тестах пакета) — вести себя как раньше, то есть 428; записать это в комментарии к `paramError`. Прочие ошибки параметров — 400, как раньше. Тесты пакета, которые зовут `ParamErrorHandler`, переходят на метод. ADR-002, решение 7 — закрывается в задаче 25.

- [ ] **Step 4: Run** ту же команду и `golangci-lint run ./...`. Expected: зелёно.

- [ ] **Step 5: Commit.** «Этап 4в: 404 раньше проверки If-Match». `git add internal/im`.

---

### Task 16: Идемпотентность

**Files:** Modify `internal/im/handler/operator/reply.go`, `transition.go`. Test: `internal/im/handler/test/operator_idempotency_test.go`.

**Interfaces:**
- Consumes: `idempotency.Store.Do`, `idempotency.Key`, `idempotency.Response`.
- Produces: `func (h *Handler) once(c *gin.Context, key string, run func() reply)` — пустой `key` просто выполняет `run` и пишет ответ. Подключение `executeTransition`: разбор тела — до `once`, всё остальное — внутри.

- [ ] **Step 1: Failing test**

```go
func TestIdempotentRepeatReplays(t *testing.T)                 // два раза с одним ключом: оба 200, тела и ETag равны, запись claim одна
func TestIdempotentRepeatReplaysAfterVersionMoved(t *testing.T)// Review Focus 3: после успеха второй раз со старым If-Match — сохранённый 200, не 412
func TestIdempotentRefusalReplays(t *testing.T)                // 422 запомнен, повтор — тот же 422, хотя поле теперь заполнено
func TestIdempotencyKeyIsPerUser(t *testing.T)                 // тот же ключ другого пользователя — своё выполнение
func TestIdempotencyKeyIsPerPath(t *testing.T)                 // тот же ключ на другом инциденте — своё выполнение
func TestNoKeyNoMemory(t *testing.T)                           // без ключа второй запрос — 412
func TestServerErrorIsNotRemembered(t *testing.T)              // обработчик f.engine с Deps.World, который первый раз даёт ошибку факта: 500 INTERNAL_ERROR (контракт — решение 62); второй раз с тем же ключом — 200
func TestConcurrentSameKeyRunsOnce(t *testing.T)               // 4 горутины с одним ключом: все 200, запись одна
```

- [ ] **Step 2: Run** `source ~/go/offline-env.sh && TESTDB='postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable' && IM_TEST_DB_URL=$TESTDB go test -race ./internal/im/handler/test/ -run 'Idempoten|TestNoKeyNoMemory|TestServerErrorIsNot|TestConcurrentSameKey'`. Expected: FAIL.

- [ ] **Step 3: Implement** (решения 54, 65: повтор отдаёт сохранённый ответ раньше проверки видимости). Тело ответа маршалится в `run`, в `Response` — `Status`, `Header` (`ETag`, `Content-Type`), `Body`. `idempotency.ErrAborted` — 500. Отмена контекста клиента не отменяет выполнение: как `Do` уже делает, проверить чтением `memory.go`.

- [ ] **Step 4: Run** ту же команду и `golangci-lint run ./...`. Expected: зелёно.

- [ ] **Step 5: Commit.** «Этап 4в: идемпотентность перехода». `git add internal/im`.

---

### Task 17: `executeBulkTransition`

**Files:** Create `internal/im/handler/operator/bulk.go`, `internal/im/handler/test/operator_bulk_test.go`. Modify `stubs.go`.

**Interfaces:**
- Consumes: `h.runOne`, `h.once`, `Core.BulkPrimary`, `parseExpected`.
- Produces:

```go
// parseExpected turns expectedVersions into versions; a value that is not a number is an error (400).
func parseExpected(m *map[string]string) (map[string]int64, error)
func (h *Handler) ExecuteBulkTransition(c *gin.Context, transitionId operatorgen.TransitionId)
```

Порядок проверок — `server.js:1486–1525`, с одним отступлением: повторы в `incidentGuids` убираются первым делом и длина считается после этого (`server.js` считает `maxBulk` и `selection_too_small` по исходной длине); ядро всё равно отвергает повтор (`ErrDuplicateID`). Отступление записывается в ADR-005 (задача 25).

- [ ] **Step 1: Failing test**

```go
func TestBulkTransfer(t *testing.T)             // два своих в in_progress передаются второму оператору: succeeded два, failed [], skipped [], navigate queue
func TestBulkEmpty(t *testing.T)                // [] и все невидимые — 422 BULK_SELECTION_INVALID, selection_empty
func TestBulkNotAllowed(t *testing.T)           // claim — 422, selection_unavailable
func TestBulkUnknownTransition(t *testing.T)    // как server.js: bulkTr нет, каждый инцидент — в failed с unknown_action
func TestBulkMergeTransitionRefused(t *testing.T) // transitions/merge/bulk (у merge bulk.allowed true): 200, оба в failed с unknown_action, никто не изменился, запросов Run нет
func TestBulkTooSmall(t *testing.T)             // при minItems 2 из машины — проверка на f.engine с patchedCore, minItems 3: 422, selection_too_small {n}
func TestBulkOneIsLikeSingle(t *testing.T)      // один id при minItems 2 — выполняется
func TestBulkTooLarge(t *testing.T)             // patchedCore с maxBulk 1: 422, selection_too_large {n}
func TestBulkInvisibleGoesToFailed(t *testing.T)// чужой — в failed, NOT_FOUND; свой выполнен
func TestBulkBadExpectedVersion(t *testing.T)   // "abc" — 400 BAD_REQUEST
func TestBulkScopeStaleWhole412(t *testing.T)   // close со scope, один устарел — 412, current, ничего не выполнено
func TestBulkScopeSkipsOtherScenario(t *testing.T) // другой сценарий — в skipped {incidentGuid, number, reasonKey}, версия не менялась
func TestBulkExpectedKeyOutsideSelection(t *testing.T) // лишний ключ в expectedVersions — не ошибка
func TestBulkMixedSelection(t *testing.T)       // Review Focus 4: хороший, устаревший, чужой, с отказом, повтор хорошего: succeeded — 1 (запись журнала одна), failed — 3 со своими кодами, у устаревшего VERSION_CONFLICT и без поля current (в `failed` его нет, даже у конфликта версии)
func TestBulkErrorOfOneIsFailed(t *testing.T)   // мир, давший ошибку факта на одном инциденте: он в failed с INTERNAL_ERROR, остальные выполнены
func TestBulkDuplicatesAtMaxBulk(t *testing.T)  // отступление от server.js: patchedCore с maxBulk 2, ids [a, a, b] — длина 2 после снятия повтора, выполняется (по server.js было бы selection_too_large)
func TestBulkIdempotent(t *testing.T)           // повтор с ключом — тот же ответ, переходы не повторяются
```

- [ ] **Step 2: Run** `source ~/go/offline-env.sh && TESTDB='postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable' && IM_TEST_DB_URL=$TESTDB go test -race ./internal/im/handler/test/ -run TestBulk`. Expected: FAIL.

- [ ] **Step 3: Implement** (решения 50, 51). `failed[].problem` — тело `problemReply`, но `Current` в `failed` игнорируется: `current` в тело не кладётся никогда, даже у `*VersionConflict` (у `conflict(ev)` в `server.js` его нет). `succeeded` — сводка `queue`. Порядок `succeeded` — как в запросе. Ошибка `500` одного инцидента — запись в `failed` с кодом `INTERNAL_ERROR`, остальные идут дальше; `TestBulkMixedSelection` это не закрывает, проверяется отдельной подстановкой мира в `TestBulkErrorOfOneIsFailed`: в `failed` код `INTERNAL_ERROR` (сверка контракта знает его по решению 62). Выборке `expect` — `nil`, если ключа нет.

- [ ] **Step 4: Run** ту же команду и `golangci-lint run ./...`. Expected: зелёно.

- [ ] **Step 5: Commit.** «Этап 4в: переход на выборке». `git add internal/im`.

---

### Task 18: `mergeIncidents`

**Files:** Create `internal/im/handler/operator/merge.go`, `internal/im/handler/test/operator_merge_test.go`. Modify `stubs.go`.

**Interfaces:**
- Consumes: `Core.Merge`, `Core.MergePrimary`, `h.once`, `parseExpected`, `refusalProblem(opMerge)`.
- Produces: `func (h *Handler) MergeIncidents(c *gin.Context)`, `func (h *Handler) pickPrimary(v *viewer, list []*opapp.Loaded) (*opapp.Loaded, error)`.

Порядок — `server.js:1265–1302`: повторы убрать; все `find` (нет одного — 404 целиком); устаревший — 412 с `current`; пусто — 422 `workflow.error.merge.too_few`; больше `maxBulk` — 422; `1 < n < minItems` — 422; основной — по списку, отсортированному по номеру; нет — 422 `workflow.guard.merge_primary`; `Core.Merge` с `Expect`. Переход — тот, у кого `bulk.mode == merge`; `Op.Transition`, `Form`, `Surface` пусты, как требует `Merge`.

- [ ] **Step 1: Failing test**

```go
func TestMergeTwoNew(t *testing.T)            // основной взят мной, второй linked, 200 {incident: карточка основного}, linkedCount 1, запись merged_in; заголовка ETag нет ни у server.js, ни в контракте, не проверять
func TestMergeMyInProgressIsPrimary(t *testing.T) // мой в работе важнее нового с большим приоритетом
func TestMergeOneIsTake(t *testing.T)         // один new — «Взять», без merged_in; один чужой в работе — нет основного: 422
func TestMergeMissing(t *testing.T)           // один невидимый — 404 целиком, никто не изменился
func TestMergeStale(t *testing.T)             // устаревший — 412, current — он
func TestMergeEmpty(t *testing.T)             // 422 workflow.error.merge.too_few
func TestMergeWrongStateIs422(t *testing.T)   // закрытый в выборке — 422 BULK_SELECTION_INVALID, не 409
func TestMergeGuardIs403(t *testing.T)        // сценарий другой или чужой владелец — 403 с кодом условия
func TestMergeDuplicateIDs(t *testing.T)      // повтор id — как без него
func TestMergeIdempotent(t *testing.T)        // повтор с ключом — тот же ответ, merged_in один
func TestMergeNoRightsIs403(t *testing.T)     // нет права — PERMISSION_DENIED
```

- [ ] **Step 2: Run** `source ~/go/offline-env.sh && TESTDB='postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable' && IM_TEST_DB_URL=$TESTDB go test -race ./internal/im/handler/test/ -run TestMerge`. Expected: FAIL.

- [ ] **Step 3: Implement** (решение 52, без дописывания версий). Сортировка по номеру — `Row.Order`. Перед вызовом ядра основной убирается из `IDs` (решение 38). Отказ без `Guard` — через `opMerge`. `TestMergeWrongStateIs422` закрывает случай ADR-005 «handler checks merge first».

- [ ] **Step 4: Run** ту же команду и `golangci-lint run ./...`. Expected: зелёно.

- [ ] **Step 5: Commit.** «Этап 4в: объединение». `git add internal/im`.

---

### Task 19: Дописывание версий после объединения

Отдельная задача: другой ответ на открытый вопрос 1 меняет только её.

**Files:** Create `internal/im/appservice/operator/touch.go`. Modify `internal/im/service/storing/incident_machine_queries.go`, `Store` в `deps.go`, `internal/im/handler/operator/merge.go`, `operator_merge_test.go`.

**Interfaces:**
- Consumes: `Store.MachineIncidentsLinkedTo`, `transition.Result.Incidents`, определение `isDone`.
- Produces:

```go
// TouchAfterMerge raises by one the version of the incidents server.js touches after a merge and the core did not write: the open incidents linked to primary before the merge; the primary, when nothing was joined and it was not taken. No journal, no other column.
func (d *Deps) TouchAfterMerge(ctx model.AppContext, customer, primary uuid.UUID, r *transition.Result, me string) error
// in storing: does not open a transaction itself, MUST be called inside one (like the lock query noted in scenario_queries.go)
TouchIncidents(ctx model.AppContext, customer uuid.UUID, guids []uuid.UUID) error
```

`TouchIncidents` добавляется в интерфейс `Store` (`deps.go`). Транзакцию открывает `TouchAfterMerge` тем же способом, что ядро: `d.Repo.DoInTx(ctx, func() error { return d.Store.TouchIncidents(ctx, customer, guids) })` (`Repo.DoInTx` из `transition.Repo` уже есть, поверх `Store.DoInTx`; нового помощника для транзакции нет).

- [ ] **Step 1: Failing test**

```go
func TestMergeTouchesOnlyUnwritten(t *testing.T)     // Review Focus 5: у основного уже были привязанные A (открытый) и B (закрытый); объединение с C: основной +1, C +1, A +1, B без изменений
func TestMergeTouchesUntakenPrimary(t *testing.T)    // основной уже в работе у меня, присоединять некого: +1, журнал без изменений
func TestMergeTakenPrimaryOnce(t *testing.T)         // основной взят этим объединением: ровно +1
func TestMergeRefusalTouchesNothing(t *testing.T)    // отказ: версии всех без изменений
func TestMergeTouchErrorKeepsSuccess(t *testing.T)   // Deps с Store, у которого TouchIncidents даёт ошибку: 200, ошибка в журнале; карточка отражает зафиксированное
func TestTouchIncidentsOnlyVersion(t *testing.T)     // только version; другие столбцы равны; чужой клиент не затронут
func TestTouchIncidentsWithMergeNoDeadlock(t *testing.T) // 20 кругов параллельно: TouchAfterMerge по двум инцидентам и Merge по ним же, обе стороны берут строки по номеру: ни одного 40P01 (тест ловит нарушение порядка блокировок, а не доказывает его отсутствие; при мигании — порядок в `TouchIncidents` проверить по коду, не ослаблять тест)
```

- [ ] **Step 2: Run** `source ~/go/offline-env.sh && TESTDB='postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable' && IM_TEST_DB_URL=$TESTDB go test -race ./internal/im/handler/test/ -run 'TestMergeTouch|TestMergeTaken|TestMergeRefusalTouches|TestTouchIncidents'`. Expected: FAIL.

- [ ] **Step 3: Implement** (решение 52, по `server.js:1290–1300`). Вызов — после возврата `Merge`, отдельной транзакцией, вне транзакции ядра; ошибка не отменяет ответ. `TouchIncidents` (внутри `Repo.DoInTx`, см. Interfaces) сначала блокирует строки `SELECT … ORDER BY number FOR UPDATE`, потом обновляет: порядок тот же, что у `LockFamily`, один общий `UPDATE` мог бы взять строки в другом порядке. Ответ карточки читается после `Touch`. Множество — ровно как в `server.js`, минус записанные ядром (`Result.Incidents`); своей логики «нужно ли повышать» здесь нет.

- [ ] **Step 4: Run** ту же команду и `golangci-lint run ./...`. Expected: зелёно.

- [ ] **Step 5: Commit.** «Этап 4в: версии после объединения — по умолчанию до ответа на открытый вопрос». `git add internal/im`.

---

### Task 20: `listLinked`, `detachLinked`, `detachAllLinked`

**Files:** Create `internal/im/handler/operator/linked.go`, `internal/im/handler/test/operator_linked_test.go`. Modify `stubs.go`, `operator_transition_test.go` (убрать `t.Skip` из `TestInvisibleIncidentIsNotFoundEverywhere`).

**Interfaces:**
- Consumes: `Store.MachineIncidentsLinkedTo`, `Core.Run`, `Core.RunAll`, `viewer.summary`, `viewer.card`.
- Produces: `ListLinked`, `DetachLinked`, `DetachAllLinked`; переход отсоединения — ручной, с `linked` в `from`: `func (d *Deps) DetachTransition() string`.

- [ ] **Step 1: Failing test**

```go
func TestListLinkedDefaults(t *testing.T)       // pageSize 8, page 1, total, focusPage; закрытые привязанные — тоже; сводка card
func TestListLinkedPageSizeCap(t *testing.T)    // pageSize 500 — 200; 0 — 8 (как max(1, …||8))
func TestListLinkedFocus(t *testing.T)          // focusGuid на 2-й странице — focusPage 2, page запрошенная
func TestListLinkedHidesInvisible(t *testing.T) // привязанный вне доступа не считается и не показывается (Loaded.Linked)
func TestDetachLinked(t *testing.T)             // 200, тело — карточка основного; отсоединённый new; журнал; linkedCount -1
func TestDetachNotLinked(t *testing.T)          // не привязан к этому основному или не в linked — 404
func TestDetachLinkedInvisibleGuid(t *testing.T)// 404
func TestDetachRefusal(t *testing.T)            // основной в работе у другого (primaryEditable) — 403 GUARD_FAILED: своего кода у условия нет
func TestDetachAll(t *testing.T)                // оба отсоединены одной транзакцией; 200 карточка
func TestDetachAllEmpty(t *testing.T)           // без привязанных — 200 (решение 38; tests/api-scenarios.js:3513)
func TestDetachAllRefusalChangesNothing(t *testing.T) // основной в работе у другого — 403 GUARD_FAILED, ни один не изменился; 409 здесь нет: маршрут берёт только linked, контракт его не объявляет
```

- [ ] **Step 2: Run** `source ~/go/offline-env.sh && TESTDB='postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable' && IM_TEST_DB_URL=$TESTDB go test -race ./internal/im/handler/test/ -run 'TestListLinked|TestDetach|TestInvisibleIncident'`. Expected: FAIL.

- [ ] **Step 3: Implement** по `server.js:1560–1609`. Поверхность — `card`. Без `If-Match`: контракт его здесь не требует. Отказ `RunAll` — через `refusalProblem(opRun)`; `r.Refusal.ID` называет инцидент. `412` по `ErrFamilyChanged` возможен и объявлен в контракте — он в контракте с коммита IM `9526a09` (решение 63).

- [ ] **Step 4: Run** ту же команду и `golangci-lint run ./...`. Expected: зелёно.

- [ ] **Step 5: Commit.** «Этап 4в: привязанные и отсоединение». `git add internal/im`.

---

### Task 21: `/test/clock`

**Files:** Create `internal/im/handler/operator/testsupport.go`, `internal/im/handler/test/operator_clock_test.go`. Modify `internal/im/appservice/operator/clock.go` (тип часов — из задачи 7), `stubs.go`, `internal/im/appservice/appservice.go`.

**Interfaces:**
- Consumes: `Config.TestSupport`.
- Produces:

```go
// TestClock, NewTestClock, Advance and Now are made in Task 7; this task adds:
// ClockFor is nil when the flag is off; on, it logs a Warn: any signed-in user can move the clock.
func ClockFor(cfg *model.Config, logger logrus.FieldLogger) *TestClock
func (h *Handler) TestClock(c *gin.Context)
```

- [ ] **Step 1: Failing test**

```go
func TestClockOffByDefault(t *testing.T)        // обычная сборка (HTTPHandler), через o.raw (решение 63): 404 NOT_FOUND
func TestClockAdvance(t *testing.T)             // f.engine с Deps.Clock: advanceSec 3600 — now на час вперёд, fired []; advanceSec 1.0 — целое, 200
func TestClockFractional(t *testing.T)          // 1.5 или нет поля — 422 FORM_FIELD_REQUIRED, workflow.error.test.clock_seconds
func TestClockBackwards(t *testing.T)           // -1 — 422, workflow.error.test.clock_backwards
func TestClockFlagsAccepted(t *testing.T)       // runScheduler false, serviceRestart true — 200, fired []
func TestClockMovesWindow(t *testing.T)         // закрыт, сдвиг на reopenWindowMin + 1 — reopen даёт 403 REOPEN_WINDOW_EXPIRED; до сдвига — 200
func TestClockConcurrent(t *testing.T)          // Advance и Now параллельно под -race
func TestClockShortensIdempotency(t *testing.T) // ключ запомнен, сдвиг на 11 минут — запрос выполняется заново (решение 54)
func TestClockForWarns(t *testing.T)            // в пакете appservice/operator, без базы: TestSupport false — nil, журнал пуст; true — часы и одна запись Warn (logrus test hook)
```

- [ ] **Step 2: Run** `source ~/go/offline-env.sh && TESTDB='postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable' && IM_TEST_DB_URL=$TESTDB go test -race ./internal/im/appservice/operator/ -run TestClockFor && IM_TEST_DB_URL=$TESTDB go test -race ./internal/im/handler/test/ -run TestClock`. Expected: FAIL.

- [ ] **Step 3: Implement** (решение 53). Тело разбирается с `UseNumber` в карту, а не в `TestClockRequest`: дробное число в `int` дало бы 400 вместо 422; целое — `Float64() == Trunc`. Маршрут остаётся под `Authenticate`. `/test/reset` и прочие — 501. `Deps.Clock` и тип `TestClock` сделаны в задаче 7; `appservice.go` берёт часы из `ClockFor` и отдаёт те же часы `Deps.Now` и `NewMemoryStore`. `f.engine` (задача 8) уже собирает `Now` и `Idempotency` от одних часов, здесь он не меняется.

- [ ] **Step 4: Run** ту же команду и `golangci-lint run ./...`. Expected: зелёно.

- [ ] **Step 5: Commit.** «Этап 4в: часы тестового стенда под флагом». `git add internal/im`.

---

### Task 22: Потоки и коды условий через HTTP (уровень А)

**Files:** Create `internal/im/handler/test/operator_flows_test.go`.

**Interfaces:**
- Consumes: `operatorClient`, `f.newIncidents`, `FakeCloudUsers`, вся работа задач 9–21.
- Produces: тесты; комментарий над каждым называет тест `tests/api-scenarios.js`.

- [ ] **Step 1: Write tests**

Правки кода не ожидаются; это проверка собранного. Значения полей форм — из машины: `hold` — `reasonId`, `comment`; `transfer` — `targetId`, `comment`; `close` — `resultId`, `causeId`, `comment`; `reject`, `release`, `reopen` — `comment`. Результаты закрытия, кроме `mass`, только на поверхности карточки: запрос шлёт `surface: "card"`. Инциденты — из `f.timedIncidents`, иначе нет таймера реакции и проверять нечего.

```go
// «Взять: в работе у меня, норматив реакции снят, норматив закрытия идёт, запись в журнале» (:39)
func TestFlowClaim(t *testing.T)
// «Отложить: причина обязательна, норматив закрытия на паузе, срок удержания идёт» (:133); «Возобновить: норматив закрытия продолжается с остатка, причина удержания снята» (:152)
func TestFlowHoldResume(t *testing.T)            // timer: remainingMs на паузе, dueAt после; holdTimer; hold без reasonId — 422
// «Вернуть в очередь: ничей, норматив закрытия не обнуляется при повторном взятии» (:184)
func TestFlowRelease(t *testing.T)
// «Передать человеку: ожидает принятия, адресат в owner, уровень не меняется, передач +1, норматив закрытия…» (:302); «Отклонить: инцидент снова новый, ничей…» (:693)
func TestFlowTransferAcceptReject(t *testing.T)  // два оператора; второй открывает карточку до «Принять»; accept; вторая передача; reject
// «Передать себе и своей дежурной группе нельзя: нет в вариантах и отказ сервера» (:318)
func TestFlowTransferToSelf(t *testing.T)        // себя нет в fieldOptions; запрос — 403 TRANSFER_TO_SELF_FORBIDDEN
// «Закрыть» и «Переоткрыть» забывают остаток реакции (:253)
func TestFlowCloseReopen(t *testing.T)           // close false_alarm, surface card, comment; state closed; closeResultLabel; reopen
func TestFlowCloseProcessedNeedsSteps(t *testing.T) // resultId processed — 403 REQUIRED_STEPS_NOT_FILLED (решение 45)
// «Устаревшее состояние в запросе» (:91); «Версия записи»: (:100); «Переход не из этого состояния» (:125)
func TestFlowConflicts(t *testing.T)
// «Закрытие основного»: привязанные остаются linked до этапа 6
// Закрепляет известный предел, а не желаемое поведение: в комментарии над ожиданием — маркер `STAGE6: сменить ожидание, когда появится close_linked`
func TestFlowCloseLinkedStaysUntilStage6(t *testing.T)
func TestFlowFullLifecycle(t *testing.T)         // критерий: взять, приостановить, возобновить, передать, принять, закрыть; после каждого шага GET карточки равен incident ответа; журнал на каждый шаг, версия растёт на 1
// Коды условий: таблица строится по guards машины.
func TestGuardCodesOverHTTP(t *testing.T)
```

`TestGuardCodesOverHTTP`: у каждого условия из `registries.guards` с `errorCode` или `errorCodes` — строка таблицы, которая его вызывает, либо запись в `unreachableIn4c` с причиной. Тест падает, если условие с кодом есть в машине, но нет ни там, ни там. Подготовка — своя у каждой строки, каждый оператор со своей группой; новый фикстур, потому что `Directory` общий на весь `HTTPHandler`, а `access` чужих фикстур не проходит:

| Условие | Подготовка | Ответ |
|---|---|---|
| `hasPermission` | у оператора нет `incident:claim` (ключ — из условия перехода `claim`) | `403 PERMISSION_DENIED` |
| `hasScopedPermission` | передача чужого инцидента в работе, есть `incident:transfer:own`, нет `:any` | `403 PERMISSION_DENIED` |
| `hasTransferTarget` | других операторов с доступом к этому источнику нет | `403 TARGET_CANNOT_ACCEPT` |
| `targetIsNotSelf` | `op2` с доступом есть, `targetId` — я | `403 TRANSFER_TO_SELF_FORBIDDEN` |
| `targetHasAccess` | `op2` с доступом есть; цель — `op3` без правила к источнику | `403 TARGET_NO_ACCESS` |
| `targetHasAccessToLinked` | у инцидента привязанный другого источника; у `op2` оба правила, у цели `op3` — только основной | `403 TARGET_NO_ACCESS` |
| `targetCanAccept` | `op2` с доступом есть; цель — `op3` с доступом, без `incident:accept` | `403 TARGET_CANNOT_ACCEPT` |
| `closeResultAllowed` | `resultId: processed`, `surface: card` | `403 REQUIRED_STEPS_NOT_FILLED` |
| `closeResultAllowed`, другой ключ | `resultId: false_alarm`, `surface: queue`: вариант не на этой поверхности, ключа нет в `errorCodes` | `403 GUARD_FAILED` |
| `withinHoldLimit` | пять своих `on_hold`, шестой `hold` при `maxOnHold` 5 | `403 LIMIT_EXCEEDED` |
| `withinActiveLimit` | обработчик `f.engine` с `patchedCore`, `limits.maxActive` 1, второе «Взять» (`tests/api-scenarios.js:76`) | `403 LIMIT_EXCEEDED` |
| `withinReopenWindow` | обработчик `f.engine` с `Deps.Clock`, сдвиг больше `reopenWindowMin` | `403 REOPEN_WINDOW_EXPIRED` |

`unreachableIn4c`: `requiredStepsFilled` — есть только в реестре, ни один переход его не использует (закрытие идёт через `closeResultAllowed`); `agentReady` — настоящий мир всегда `ready`, отображение закрывает `TestRefusalAgentNotReady`, через HTTP — вектор `fee20…` (задача 23).

- [ ] **Step 2: Run** `source ~/go/offline-env.sh && TESTDB='postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable' && IM_TEST_DB_URL=$TESTDB go test -race ./internal/im/handler/test/ -run 'TestFlow|TestGuardCodes' -v 2>&1 | tail -40`. Expected: все PASS. Падение сначала разобрать: неверная подготовка — поправить тест; ошибка обработчика — чинить в коде задачи, которой он принадлежит, в этом же коммите; кажется, что не правы машина, контракт или прототип, — **стоп, спросить**.

- [ ] **Step 3: Commit.** «Этап 4в: потоки переходов и коды условий через HTTP». `git add internal/im`.

---

### Task 23: Векторы переходов через маршрут (уровень Б)

**Files:** Create `internal/im/handler/test/operator_vectors_test.go`.

**Interfaces:**
- Consumes: `transitionVectors`, `f.seedVector`, `f.inRolledBackTx`, `transitiontest.NewTape`, `Tape.Misses`, `transition.NewStoreRepo`, `operator.NewHandler`, `operator.Register`.
- Produces: `func TestTransitionVectorsOverHTTP(t *testing.T)`; помощник `expectedHTTP(v *transitiontest.TransitionVector) (status int, code string)`.

Для каждого вектора `run`, `runAll`, `merge` — новый `gin`-обработчик из `f.engine(t, edit)` (задача 8): `Deps` — копия `AppServices.Operator`, поэтому `Catalog`, `Core`, `Idempotency`, `Store`, `Directory` остаются как в сборке; `edit` меняет только перечисленное: `Context` возвращает `ctx` откатываемой транзакции, `World` — лента `NewTape(m, v.World)`, `Repo` — `countingRepo`, встраивающий `transition.Repo` от `NewStoreRepo` (чтобы остальные методы, в том числе `ReadFamily`, были у обёртки) и считающий `LockFamily`, `ViewWorld` — `readWorld()`, `Visible` — всегда `true`, `Now` — `v.Now`, `Actor` — `v.Me`, а `UserAuthenticator` — пользователь с `CustomerGUID` вектора.

`readWorld()` — `transitiontest.DefaultWorld()` (`can`, `access` — да; `agentState` — `ready`; `isGroup` — нет; `members` — `[]`; `ActorName`, `Progress`, `StepNumber` — его) плюс факты: `isOperator` — да; `transferTargets`, `dutyGroups` — `[]`; `stepsFilled`, `inSourceGroup`, `deviceInGroup` — нет; `lastTransferTarget` — `""`; `idleSec`, `groupDepth` — `0`. Факты с `ref` отвечает ядро через `Repo.Candidates`. Строки после вызова — `f.storedOf`. Ответ разбирается с `UseNumber`, подстановки сравниваются правилами `Compare` (решение 41): `json.Number` и `int64` — одно, `closeResultLabel` `[""]` = `""`, `vars` `nil` = `{}`.

| `op` | Запрос |
|---|---|
| `run` | `POST …/{target.id}/transitions/{name}`, `If-Match: "1"`, `formValues` — `v.Form`, `surface` — `v.Surface`, пустой не посылается |
| `runAll` | `DELETE …/{primary}/linked`; основной — `linkedTo` первого из `target.ids`, у пустого списка — первый инцидент пула не в `linked` |
| `merge` | `POST /operator/incidents/merge`, `incidentGuids` — `target.ids` + `target.primaryId` |

`expectedHTTP`:

| `expect` | Статус и код |
|---|---|
| `ok` | `200` |
| `refusal` у `merge` с `guard` | `403`, код условия |
| `refusal` у `merge` без `guard` | `422 BULK_SELECTION_INVALID` |
| `refusal.notFrom` | `409 TRANSITION_NOT_ALLOWED_FROM_STATE` |
| `refusal.guard` | `403`, код условия |
| `refusal.code` или ни того ни другого | `422`, `code` или `FORM_FIELD_REQUIRED` |

- [ ] **Step 1: Write the failing test**

```go
func TestExpectedHTTPTable(t *testing.T)        // таблица выше на придуманных векторах, без базы
func TestTransitionVectorsOverHTTP(t *testing.T)
// на каждый вектор:
//   статус и code равны expectedHTTP; каждый ответ проходит checkContract;
//   Tape.Misses() пуст (иначе в ядро ушёл не тот Op);
//   countingRepo.LockFamily >= 1: ядро выполнялось (кроме runAll с пустым списком, решение 38);
// при ok:
//   run: journalEntries = expect.ok.journal[id] без server, по порядку: actor.id, kind, templateKey, vars;
//        externalEffects = expect.ok.external[id] со status queued;
//        canceledTimerTrigger = expect.ok.canceled[id] или null;
//        state карточки = expect.ok.incidents[id].state, если он там есть;
//        version = 1 + (id есть в expect.ok.incidents или в expect.ok.journal ? 1 : 0) (решение 16 плана 53);
//   merge: incident.guid = target.primaryId (основной выбран как в записи); журнал основного содержит merged_in*, если он есть в expect;
//   runAll: 200, тело — карточка основного;
//   все op: у каждого инцидента из expect.ok.incidents строка базы (f.storedOf) имеет те же state, owner, linkedTo.
// при refusal: версии и журнал пула не менялись.
// В конце:
//   t.Logf("http vectors %d, noRoute %d (…)", n, noRoute)
//   require.Equal(t, 87, n + noRoute)
//   require.LessOrEqual(t, noRoute, 2)
//   у записанных векторов (без case) noRoute == 0
```

Какие строки `expectedHTTP` реально работают: у `merge` — 3 с условием и 2 `wrong_state`; у `runAll` — `fee20…` даёт `403 AGENT_NOT_READY` с ленты; `refusal.notFrom` и `refusal.guard` у `run` векторов нет, их проверяет только `TestExpectedHTTPTable`, а по существу — уровень А.

`noRoute` — вектор, который маршрут не воспроизводит по устройству; сейчас таких два, оба синтетические: `runAll` «[9001 привязан к 9003, 9002 new]» (маршрут берёт только `linked`) и `merge` с основным, которого `mergePrimary` не выбирает. Признак считается по самому вектору (целевой не в `linked`; `Core.MergePrimary` по списку дал другого) и попадает в лог с `id`.

- [ ] **Step 2: Run** `source ~/go/offline-env.sh && TESTDB='postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable' && IM_TEST_DB_URL=$TESTDB go test -race ./internal/im/handler/test/ -run 'TestExpectedHTTPTable|TestTransitionVectorsOverHTTP' -v 2>&1 | grep -E 'http vectors|^(---|FAIL|ok)' | tail -20`. Expected: сначала FAIL, пока нет файла.

- [ ] **Step 3: Implement** тест; расхождения — в коде обработчиков (задачи 14, 18, 20). Откатываемая транзакция: `DoInTx` ядра идёт точкой сохранения (ADR-005, решение 4). `Deps.Store` читает из `ctx`, поэтому видит положенное `seedVector`.

- [ ] **Step 4: Run** ту же команду и `golangci-lint run ./...`. Expected: PASS, в логе `http vectors 85, noRoute 2`. Другие числа — разобраться и записать в журнал работ.

- [ ] **Step 5: Commit.** «Этап 4в: векторы переходов через маршрут». `git add internal/im`.

---

### Task 24: Проверка на стенде (уровень Г)

**Files:** Create `~/Work/stand/check-operator-transitions.sh`. Modify `~/Work/stand/check-operator-api.sh`. Эти файлы вне git и вне репозитория сервера: коммита у задачи нет.

**Interfaces:**
- Consumes: вход `POST $CLOUD/api/v3/ac-backend/users/login`, помощники `req`, `check`, `jq_is`, `is_problem` из `check-operator-api.sh`; `run-im-server.sh`; `~/Work/stand/bin/agent-emulator replay --limit 1 --run <метка>`; `GET`, `POST`, `DELETE /access-rules` старого API.
- Produces: строки `OK|FAIL|SKIP <что>`, код выхода — число `FAIL`.

Запреты шага: в `ac_db` не писать и не читать (строки чтения из `check-demo-intake.sh` не копировать), `imdb` скриптом напрямую (SQL) не трогать — правило доступа через старый HTTP API разрешено как исключение решения 60, — пользователей не заводить; пароль второго оператора в чат, журнал и вывод скрипта не попадает.

- [ ] **Step 1: Обновить `check-operator-api.sh`.** `agentState` — `ready`; `GET /operator/incidents` — по-прежнему 501; запрос `transitions/take` со случайным UUID без `If-Match` — заменить на `transitions/claim` (в самом запросе и в тексте проверки: имя перехода здесь не проверяется, проверяется, что инцидента нет) и ждать теперь **404** (решение 47); `/operator/me` — 404.

- [ ] **Step 2: Написать `check-operator-transitions.sh`.** Шаги:
  1. Вход `test@axxonnet.test`. Вход второго оператора — `user@gmail.com` (`SECOND_EMAIL`), только на локальном стенде, с разрешения пользователя 2026-10-30. Пароль — из файла на стенде (`SECOND_PASS_FILE`, по умолчанию `~/Work/stand/second-operator.pass`, права `600`, вне git); из чата и из текста скрипта он не берётся, скрипт его не печатает. Нет файла, вход не удался или запрещён, токена нет или в `GET /operator/session` нет `incident:accept` — `SECOND=` пусто и строка `SKIP второй оператор: <причина>; передача не проверяется, см. открытый вопрос 7 плана 55`.
  2. `GET /access-rules`: у группы 1 (`cloud-admin`) нет правила — создать через `POST /access-rules` на корневую группу источников. Только на стенде. Скрипт печатает отдельной строкой, что создал правило, его `guid` и готовую команду удаления (`DELETE /access-rules`); иначе — ничего не меняет.
  3. Оба делают `GET /operator/session` (`Directory` узнаёт их).
  4. `agent-emulator replay --limit 1 --run <метка от времени>`: один инцидент, а не 30. Его `guid` — самый новый `state: new` из старого `GET /incidents`.
  5. `GET` карточки; `claim` с `If-Match`; повтор со старым — 412; `hold` — `reasonId` из `GET /operator/reference/reasons/hold` (первый с `setBy: operator`) и `comment`; `resume`; `transfer` второму с `comment` (все переходы — по именам машины: `claim`, `hold`, `resume`, `transfer`, `accept`, `close`; `take` нет); `accept` вторым; `close` — `resultId: false_alarm`, `comment`, `surface: card`. Второго нет — `SKIP` передачи и принятия, закрывает первый.
  6. На каждом шаге — `check` статуса и `state`.

- [ ] **Step 3: Run.** `~/Work/stand/run-im-server.sh` (после сборки), затем `bash ~/Work/stand/check-operator-api.sh; bash ~/Work/stand/check-operator-transitions.sh`. Expected: `FAIL` нет, `SKIP` — только про второго оператора. Вход второго оператора система разрешений может запретить: не обходить, это тот же `SKIP`. Вывод — в журнал работ. Стенд не поднимается — записать причину в журнал работ и сказать ведущему; уровни А–В от этого не зависят.

- [ ] **Step 4: Коммита нет:** `~/Work/stand` вне git. Запись о выполнении — в журнале работ.

---

### Task 25: ADR, документы, итоговый прогон

**Files:** Modify сервер: `docs/adr/002-operator-api-package.md`, `docs/adr/005-transitions-in-transaction.md`. IM: `research/integration/40-plan.md`, `research/integration/30-local-stand.md`, `research/integration/55-plan-stage4c.md`.

**Interfaces:** нет новых.

- [ ] **Step 1: ADR-002.** Решение 7: расхождение закрыто, вариант (b), `paramError`. Решение 6: строгий обработчик по-прежнему не используется, свой писатель `problem+json`. Решение 10: подключено к трём операциям, хранилище в PostgreSQL — этап 5; 428 обёртки раньше повтора. «Consequences»: `agentState` — `ready`; работает 13 из 51 операции. Новый код `INTERNAL_ERROR` — в решении 5; он и `NOT_IMPLEMENTED` теперь в контракте (IM `9526a09`), `412` у отсоединения — тоже; кодов вне контракта нет. Отдельной строкой — решение 65 плана: повтор с ключом отдаёт сохранённый ответ раньше проверки видимости, в том числе потерявшему доступ (исключение из правила «чужой инцидент — 404»; 10 минут, тот же пользователь и путь).

- [ ] **Step 2: ADR-005.** Раздел «Carried to 4c» — разобрать полностью: выполненное убрать со ссылкой на решения плана, оставшееся перенести в «Carried to stages 5–7» (нотификации, вытеснение, поток; векторы планировщика; `shareAnswers`). Контракт вызова — в разделе «Consequences» (решение 61). «Known limits»: `countMine` вне блокировки, порядок списка, инциденты без таймера реакции — без изменений. Отступление от `server.js` на выборке: повторы id убираются до подсчёта длины (`maxBulk`, `selection_too_small`) — задача 17.

- [ ] **Step 3: IM.** `40-plan.md`: строка «Что уже готово»; раздел этапа 4 — итог и подмена критерия уровнями А–Г; этап 7 — «критерий `tests/api.html` этапа 4 проверяется здесь». `30-local-stand.md`: `check-operator-transitions.sh`, второй оператор `user@gmail.com` (вошёл или `SKIP`; пароль — в файле на стенде, `SECOND_PASS_FILE`), правило доступа, если скрипт его создал, и как удалить, `IM_TEST_SUPPORT`. В этом плане — отметить `[x]` и дописать «Итог» с числами векторов и хэшами.

- [ ] **Step 4: Итоговый прогон.**

Сервер: `source ~/go/offline-env.sh && go test -race $(go list ./internal/im/... | grep -v /handler/test) && make test-local 2>&1 | tail -15 && go vet ./... && gofmt -l internal/im && golangci-lint run ./...`. Expected: зелёно, вывод `gofmt` пуст.

Проверить, что заглушек ровно 38: `grep -c '^func (h \*Handler) [A-Z]' internal/im/handler/operator/stubs.go` (только экспортируемые методы `ServerInterface`; вспомогательные начинаются со строчной буквы и не считаются). Сверка по контракту: 51 операция минус 13, которые отвечают не `501` (`getOperatorSession` и 12 из этого этапа), равно 38.

IM: `python3 tools/build_workflow.py --check && python3 tools/check_links.py`. Expected: зелёно.

- [ ] **Step 5: Commit.** Сервер: «Этап 4в: ADR — итог операторского API». `git add docs`. IM: «Этап 4в: итог — план, этапы, стенд». `git add research/integration`; `git commit -q -F .superpowers/sdd/55-plan-stage4c/commit-msg.txt`.

---

## Не в этом этапе

| Что | Когда |
|---|---|
| `listIncidents`, `getQueueCounters`, `filterIncidents`, `resolveSelection`, `openEventStream` | 5 |
| `setAgentState`, `sessionHeartbeat`, `updatePreferences`; настоящие `agentState`, `idleSec`, `lastTransferTarget`, `countMine`, язык ответа | 5 |
| `Result.After`: уведомления, вытеснение, поток; `touch` как `journal.appended`; `incident.updated` после объединения | 5 |
| Идемпотентность в PostgreSQL, несколько экземпляров сервера, общая память `Directory` | 5 |
| `getIncidentScenario`, `answerScenarioStep`, `setScenarioCursor`, исполнитель сценариев, `stepsFilled`, настоящие `Progress`, `StepNumber`, `SetCursor`, `ShareAnswers` (в том числе `shareAnswers` без `logKey`, версия +1), карточка `scenario`, макросы | 6 |
| Планировщик: переходы по таймеру, догон до и после действия, `close_linked`, `transitions` `dispatcher`; векторы планировщика; настоящие `fired` и `runScheduler` | 6 |
| Справочники: `listAccessGroups`, `listCameraLinks`, `listDutyGroups`, приоритеты, `listDeviceTypes`, `listEventTypes`, `listHelpLinks`, `listPriorities`, `listScenarios`, `listSourceGroups`, `getStrings`; дежурные группы и передача группе на настоящих данных | 7 |
| Схемы машины: 8 операций `workflow` | 7 |
| Остальные `/test/*`: `testReset`, `testIntakeEvent`, `testCreateIncident`, `testColleagueTransition`, `testSetOperatorRoles`; отдельный build tag; CORS для тестов | 7 |
| `tests/api.html?api=…` зелёный | 7 |
| Вход, токены, `Authorization` в `prototype/api.js` | по слову пользователя |
| `getIncidentMedia`, карта, видео, `media` в карточке; звук | 10 / вне работы |
| Порядок списка инцидентов в прототипе (ADR-005, Known limits) | IM, по открытому вопросу 4 плана 54 |
| Остальное из «Known limits» ADR-005 — остаётся как есть, этап его не меняет: `countMine` вне блокировки, версия +1 шире `server.js`, цена запроса семьи, `Candidates` на каждое вычисление, миграция 018 на 9.6, инциденты до 018 без таймера реакции (33 из 63 на стенде), запись вне семьи, блокировки неудачных попыток | по мере нагрузки; `countMine` — 5 |
| AxxonData | вне работы |

## Решения этого плана — обоснования

- **42.** Буквальный критерий упирается не только во вход: 230 тестов требуют набор `demo`, 174 вызова — очередь. Подмена оператора в тестах сервера ничего бы не дала: `tests/api.html` всё равно не запустился бы. Уровень Б закрывает то, что отличает HTTP от ядра; уровень В — форму ответов; уровень Г — настоящий токен.
- **43.** Лента — точный список вызовов одного прохода ядра; любой лишний вызов мира дал бы промах. Два поля проще, чем запись векторов HTTP заново.
- **44.** Чтение под блокировкой держало бы строки на время построения карточки и списка действий; `Refs` уже читают через `Candidates` без блокировки.
- **45.** Облако не отдаёт права и группы произвольного пользователя (исследование 12). `Directory` за интерфейсом заменяется позже без правки мира. `agentState` `ready` — иначе условие `agentReady` закрыло бы все переходы: `offline` у машины `readOnly`.
- **46.** Решение пользователя 2026-10-29. Проверка клиента отдельная: запрос `GetIncidentByUserGroupIDs` её не делает. Без фильтра соседей номера, состояния и владельцы чужих инцидентов ушли бы в карточку. Исключение `listTransferTargets` — как прототип и контракт; ответ ничего не говорит об инциденте.
- **47.** Вариант (b) ADR-002: не нужно менять шаблоны генератора.
- **48.** Порядок проверок записан в ADR-005; одна функция — иначе три маршрута разошлись бы.
- **49.** `404` — для клиента такого действия на этом маршруте нет; код `412` был бы ложным, а `422` намекал бы на правку формы.
- **50.** Как `changedSince`: ключ вне выборки не сравнивается.
- **51.** BACKEND и `server.js`: частичный успех. Одна транзакция на все дала бы «всё или ничего» и нарушила бы решение 4 ADR-005.
- **52.** Вопрос открыт, поведение по умолчанию задано заданием. Вне транзакции: дописывание не должно откатить зафиксированный переход; цена — кратко устаревшая версия соседа, которую клиент увидит как 412 и перечитает.
- **53.** Настоящие часы, управляемые по сети, нельзя отдавать в сборку без флага.
- **54.** Механизм готов с этапа 2; 10 минут и ключ — ADR-002, решение 10.
- **55.** `422` у ошибки вычисления говорил бы клиенту «поправьте форму»; это сбой сервера.
- **56.** Все названные поля необязательны по контракту, проверено `checkContract`.
- **57.** `plural` у `x/text` потребовал бы правки `go.mod` (прямая зависимость); правила целых чисел для двух языков умещаются в несколько строк. `select` в каталоге нет.
- **58.** Подмена `surface` на `card` изменила бы варианты формы и порвала бы вектор.
- **59.** Поток — этап 5; ядро уже возвращает `After`, поэтому потом правится только обработчик.
- **60.** Передача требует двух людей с настоящими токенами. Завести человека в облаке — решение пользователя, поэтому план берёт только того, кто уже есть, и не проваливает уровень Г, если его нет.
- **61.** ADR-005 несёт это как обязательство вызывающего; вызывающий появился только теперь.
- **62.** `Problem.code` — закрытый перечень, сверка отвергла бы и `500`, и `501`; правка контракта — решение пользователя (открытый вопрос 2). Один список и тест на него убирают обход, как только контракт догонит.
- **63.** Без явного списка лишний статус либо пропустила бы сверка, либо тест пришлось бы ослаблять целиком.
- **64.** Тест проверяет маршруты, а не тела операций; связанный с `501`, он ломался бы на первой настоящей операции и задевал бы 12 задач.
- **65.** Проверка видимости перед повтором заставила бы читать инцидент на каждый повтор и разошлась бы с `handle` прототипа; риск ограничен 10 минутами и тем же пользователем.

## Открытые вопросы

Работу не задерживают: исполнитель идёт по ответам плана. Пользователь ответил 2026-10-30 на вопросы 1, 2, 5 (кроме источника на этапе 7) и 7, а также подтвердил критерий этапа (уровни А–Г; `tests/api.html` — критерий этапа 7).

1. **Версии при объединении — отвечено 2026-10-30: как в плане.** (вопрос 7 плана 54). `server.js` повышает версию и шлёт `incident.updated` у ранее привязанных открытых инцидентов основного и у основного без взятия, когда присоединять некого. По умолчанию обработчик дописывает версии после фиксации (решение 52, задача 19); `incident.updated` — этап 5. Задача 19 остаётся как есть.
2. **Код `500` в контракте — отвечено 2026-10-30: контракт меняется.** `INTERNAL_ERROR` и `NOT_IMPLEMENTED` внесены в `Problem.code`, `412` — в `detachLinked` и `detachAllLinked`; коммит IM `9526a09`, `500` и `412` остаются на сервере (решения 62, 63; задача 8, шаг 0).
3. **Объединение через маршрут одного инцидента.** Сервер отказывает, `server.js` принимает. Поменять прототип (пункт ревью) или оставить расхождение.
4. **Вопросы 2–6 плана 53 и 1–7 плана 54** с их значениями по умолчанию; подтверждения не было, в том числе `MERGED_IN_SHOWN`, тип события по `uid` или паре, удалённый основной, `closeResultLabel`. `transition_failed` этим планом решён как `500`.
5. **Источник людей — отвечено 2026-10-30 частично.** Адресаты передачи сейчас — те, кто вошёл с момента старта сервера, в памяти процесса. **Остаётся открытым:** настоящий источник (API облака, которого нет) — выбирается на этапе 7 (BACKEND §15), решает пользователь.
6. **Ограничения для запуска оператором.** Пока нет этапов 5–6: закрыть можно только результатом без шагов; привязанные после закрытия основного остаются `linked`; таймеры не срабатывают.
7. **Второй оператор на стенде — отвечено 2026-10-30.** Пробуем `user@gmail.com`, входим только на локальном стенде, база облака не меняется. Вход не удался или запрещён — шаг передачи `SKIP`. Пароль неизвестен — пользователь кладёт его в файл на стенде, не в чат и не в скрипт (задача 24).
