# Прототип операторской части: что нужно от окружения

Коммит IM `d891125`, дата 2026-10-28. Только чтение; ссылки ведут на файлы этого коммита, строки — `путь:строка`.

Обозначения: без пометки — факт, видно в файле; **Вывод:** — следует из фактов; **Предположение:** — не проверено.

## Коротко

- Операторская часть — тонкий клиент. Правила живут в машине [`workflow_schema.v1.json`](../../Specification/Workflow_machine/workflow_schema.v1.json), её исполняет сервер. Клиент берёт кнопки, формы, бейджи и тексты из ответов API ([FRONTEND.md:23](../../Specification/Workflow_machine/FRONTEND.md?plain=1#L23)).
- Контракт — [`openapi.json`](../../Specification/Workflow_machine/openapi.json), OpenAPI 3.1, `0.1.0-draft`, база `/api/v1/im-backend`. В нём 48 операций: 44 рабочие и 4 для тестового стенда ([openapi.json:5](../../Specification/Workflow_machine/openapi.json#L5), [:15](../../Specification/Workflow_machine/openapi.json#L15); [BACKEND.md:9](../../Specification/Workflow_machine/BACKEND.md?plain=1#L9)).
- Реальное время — обязательный поток SSE `GET /operator/stream` с досылкой по `Last-Event-ID`. WebSocket допустим как замена. Опрос не годится ([openapi.json:1557](../../Specification/Workflow_machine/openapi.json#L1557)).
- Собственного окружения у прототипа нет. Вход, права, люди, устройства, камеры, планы, события и макросы берутся из эталонного набора [`fixtures/demo.json`](../../Specification/Workflow_machine/fixtures/demo.json). Его отдаёт встроенный сервер [`server.js`](../../prototype/server.js) в той же вкладке.
- С `?api=https://…` клиент [`api.js`](../../prototype/api.js) ходит на настоящий бэкенд: `fetch` и `EventSource` с куками. Заголовок `Authorization` клиент не шлёт, а контракт объявляет Bearer JWT. Это главный разрыв для облака.
- Чистый JS без сборки и без фреймворка. Две вендорные библиотеки (`cel-js`, `json-logic-js`) нужны только серверной части прототипа. Шрифты и значки грузятся с Google Fonts.
- Открыты: схема входа, получение прав и ролей всех пользователей, источник событий и выбор одного сценария, видео и карта, исполнение макросов.

## Контракт API

Общие договорённости ([BACKEND.md:23–28](../../Specification/Workflow_machine/BACKEND.md?plain=1#L23), [README машины:400](../../Specification/Workflow_machine/README.md?plain=1#L400)):

- **Вход.** `securitySchemes.bearerAuth` — HTTP Bearer, JWT, «портальный JWT из `localStorage.accessToken`, как в остальных вызовах im-backend» ([openapi.json:2167](../../Specification/Workflow_machine/openapi.json#L2167)). Требуется глобально ([:23](../../Specification/Workflow_machine/openapi.json#L23)).
- **Версия записи.** Карточка отдаёт `ETag` — это `version` в кавычках. Переход и ответ сценария требуют `If-Match`: без заголовка — `428`, версия не совпала — `412` с актуальной карточкой в теле ([openapi.json:2203](../../Specification/Workflow_machine/openapi.json#L2203)). Схема workflow кэшируется по `ETag` и отвечает `304` ([:117](../../Specification/Workflow_machine/openapi.json#L117), [:133](../../Specification/Workflow_machine/openapi.json#L133)).
- **Идемпотентность.** У перехода, массового перехода и объединения есть `idempotencyKey`: сервер помнит его 10 минут и на повтор отдаёт прежний ответ. У массовых операций ещё `expectedVersions` ([openapi.json:4592](../../Specification/Workflow_machine/openapi.json#L4592), [:4698](../../Specification/Workflow_machine/openapi.json#L4698), [:6257](../../Specification/Workflow_machine/openapi.json#L6257)). Клиент делает новый ключ `crypto.randomUUID()` на каждое действие ([app.js:1314](../../prototype/app.js#L1314)). У ответа на шаг сценария (`ScenarioAnswerRequest`: `stepId`, `value`, `skip`, `attachments`) ключа нет, его защищает только `If-Match`.
- **Ошибки.** Ответ — `application/problem+json`, схема `Problem` ([openapi.json:2321](../../Specification/Workflow_machine/openapi.json#L2321)): машинный `code` из 22 значений, `message`, `messageKey`, `messageVars`, `guard`, `details`. Конфликт версии приходит как `VersionConflictProblem` с полем `current`.
- **Версии.** Версия контракта — `info.version` `0.1.0-draft`, путь `/api/v1/…`. Версия машины — `schema.version` (сейчас 4); `OperatorSession.workflowSchemaVersion` и `IncidentSummary.schemaVersion` — по какой версии схемы живёт инцидент. Версия сценария — `IncidentScenario.scenarioVersion`. Версии формата сценария нет — открытый вопрос §15.
- **Тексты.** Записи журнала, причины и ошибки приходят ключом и подстановками. Каталог строк в ICU MessageFormat — `GET /operator/strings` (§14.9).

### Операции

| Тег | Метод и путь | Назначение | Строка |
|---|---|---|---|
| workflow-schema | `GET /operator/workflow/active` | Активная схема для контекста (тип события, группа, приоритет), `ETag`/`304` | [77](../../Specification/Workflow_machine/openapi.json#L77) |
| workflow-schema | `GET`, `POST /operator/workflow/schemas`; `GET`, `PUT …/{schemaGuid}`; `POST …/validate`, `…/publish`, `…/simulate` | Редактор схемы: список, черновик, проверка, публикация, симулятор прав (7 операций, экрана нет) | [142](../../Specification/Workflow_machine/openapi.json#L142)–[348](../../Specification/Workflow_machine/openapi.json#L348) |
| session | `GET /operator/session` | Кто я, права, лимиты, состояние оператора, настройки | [388](../../Specification/Workflow_machine/openapi.json#L388) |
| session | `PUT /operator/session/agent-state` | Готов / перерыв / выход | [413](../../Specification/Workflow_machine/openapi.json#L413) |
| session | `POST /operator/session/heartbeat` | Признак активности, какая карточка открыта | [461](../../Specification/Workflow_machine/openapi.json#L461) |
| session | `PATCH /operator/session/preferences` | Язык, тема, порядок очереди, панели | [489](../../Specification/Workflow_machine/openapi.json#L489) |
| queue | `GET /operator/incidents` | Очередь: фильтр, поиск, группа, тип события и устройства, приоритет, страницы | [524](../../Specification/Workflow_machine/openapi.json#L524) |
| queue | `GET /operator/incidents/counters` | Счётчики фильтров | [674](../../Specification/Workflow_machine/openapi.json#L674) |
| queue | `POST /operator/incidents/selection` | Выборка для массового действия: доступность и версии | [699](../../Specification/Workflow_machine/openapi.json#L699) |
| queue | `POST /operator/incidents/filter` | «Выделить по фильтру» из дерева | [2127](../../Specification/Workflow_machine/openapi.json#L2127) |
| incident | `GET /operator/incidents/{guid}` | Карточка, `ETag` | [737](../../Specification/Workflow_machine/openapi.json#L737) |
| incident | `GET …/{guid}/actions` | Доступные действия (`surface`) | [776](../../Specification/Workflow_machine/openapi.json#L776) |
| transitions | `POST …/{guid}/transitions/{transitionId}` | Любой переход, атомарно, `If-Match` | [827](../../Specification/Workflow_machine/openapi.json#L827) |
| transitions | `POST /operator/incidents/transitions/{transitionId}/bulk` | Переход на выборке, частичный успех | [913](../../Specification/Workflow_machine/openapi.json#L913) |
| transitions | `POST /operator/incidents/merge` | «Взять в работу» одним инцидентом, всё или ничего | [1920](../../Specification/Workflow_machine/openapi.json#L1920) |
| incident | `GET`, `DELETE …/{guid}/linked`; `DELETE …/linked/{linkedGuid}` | Привязанные постранично, отсоединить все или один | [1971](../../Specification/Workflow_machine/openapi.json#L1971), [2072](../../Specification/Workflow_machine/openapi.json#L2072) |
| scenario | `GET …/{guid}/scenario` | Сценарий версии инцидента, прохождение, путь, курсор, прогресс | [953](../../Specification/Workflow_machine/openapi.json#L953) |
| scenario | `POST …/{guid}/scenario/answer` | Ответ на один шаг, `If-Match` | [986](../../Specification/Workflow_machine/openapi.json#L986) |
| scenario | `PUT …/{guid}/scenario/cursor` | Показать шаг пути | [1069](../../Specification/Workflow_machine/openapi.json#L1069) |
| journal | `GET …/{guid}/journal` | Журнал инцидента постранично | [1122](../../Specification/Workflow_machine/openapi.json#L1122) |
| media | `GET …/{guid}/media` | Камеры (архив, онлайн, кадр) и план с маркерами | [1178](../../Specification/Workflow_machine/openapi.json#L1178) |
| reference | `GET /operator/transfer-targets` | Адресаты передачи: люди и дежурные группы, кто на месте | [1211](../../Specification/Workflow_machine/openapi.json#L1211) |
| reference | `GET /operator/reference/reasons/{catalogId}` | Справочники причин | [1250](../../Specification/Workflow_machine/openapi.json#L1250) |
| reference | `GET …/reference/event-types`, `…/device-types`, `…/priorities` | Типы событий, типы устройств, приоритеты | [1296](../../Specification/Workflow_machine/openapi.json#L1296), [1592](../../Specification/Workflow_machine/openapi.json#L1592), [1436](../../Specification/Workflow_machine/openapi.json#L1436) |
| reference | `GET /operator/reference/source-groups` | Дерево групп устройств, со счётчиками | [1324](../../Specification/Workflow_machine/openapi.json#L1324) |
| reference | `GET /operator/reference/help-links` | Справочные ссылки: общие и площадки | [1363](../../Specification/Workflow_machine/openapi.json#L1363) |
| reference | `GET /operator/strings` | Каталог строк языка | [1401](../../Specification/Workflow_machine/openapi.json#L1401) |
| admin | `GET /operator/admin/access-groups`, `…/duty-groups`, `…/camera-links` | Группы доступа, дежурные группы, связи камер — только чтение, право `incident:schema:admin` | [1464](../../Specification/Workflow_machine/openapi.json#L1464)–[1526](../../Specification/Workflow_machine/openapi.json#L1526) |
| admin | `POST /operator/admin/priorities`; `PUT`, `DELETE …/{value}` | Правка справочника приоритетов (экрана нет) | [1771](../../Specification/Workflow_machine/openapi.json#L1771), [1822](../../Specification/Workflow_machine/openapi.json#L1822) |
| stream | `GET /operator/stream` | Поток событий SSE | [1557](../../Specification/Workflow_machine/openapi.json#L1557) |
| test-support | `POST /test/reset`, `/test/clock`, `/test/incidents`; `PUT /test/operators/{id}/roles` | Только стенд: эталонный набор, часы, появление инцидента, смена ролей. В боевой сборке их нет | [1620](../../Specification/Workflow_machine/openapi.json#L1620)–[1736](../../Specification/Workflow_machine/openapi.json#L1736) |

### Сущности

| Сущность | Схема | Главное | Откуда данные в продукте |
|---|---|---|---|
| Сессия оператора | `OperatorSession` [3559](../../Specification/Workflow_machine/openapi.json#L3559) | `operator {guid, name, role, dutyGroupGuids}`, `permissions[]` ключами `ресурс:действие[:область]`, `agentState` (`ready`/`not_ready`/`offline`, производное `busy`), `limits`, `usage`, `preferences`, `lastTransferTargetId`, `permissionIssues` | человек и права — внешняя система (§5); остальное — бэкенд МИ |
| Настройки оператора | `OperatorPreferences` [3669](../../Specification/Workflow_machine/openapi.json#L3669) | `locale` (BCP 47), `theme` (`light`/`dark`), `queueSort`, `panels` | бэкенд МИ |
| Инцидент (строка очереди) | `IncidentSummary` [3798](../../Specification/Workflow_machine/openapi.json#L3798) | `guid`, `number`, `occurredAt`/`createdAt`, `eventType`, `priority` 0–100, `sourceGroup`, `sourceDeviceTypeId`, `site`, `location`, `state`, `owner`/`assignmentGroup`/`addressee`, `badge`, `timer`, `breaches`, `scenarioProgress`, `mediaKinds`, `linkedTo`/`linkedCount`, `version`, `actions[]` | событие источника + машина |
| Карточка | `IncidentCard` [4347](../../Specification/Workflow_machine/openapi.json#L4347) | сверх строки: `source` и `devices` (`DeviceRef`), `scenario`, `journal`, `media`, `note`, `readOnly`, `export {target, status, attempts}` | бэкенд МИ + VMS |
| Участник | `ActorRef` [4173](../../Specification/Workflow_machine/openapi.json#L4173) | `id` (строка внешней системы; `null` — система), `kind`, `name`, `role` | внешняя система |
| Журнал | `JournalEntry` [5102](../../Specification/Workflow_machine/openapi.json#L5102) | `at`, `actor`, `kind`, `transitionId`, `templateKey` + `vars`, `text` | бэкенд МИ |
| Сценарий и прохождение | `IncidentScenario` [4775](../../Specification/Workflow_machine/openapi.json#L4775), `ScenarioResult` [4868](../../Specification/Workflow_machine/openapi.json#L4868) | `scenarioGuid`, `scenarioVersion`, `script` (формат редактора `incident-manager`), `result` (ответы, история, вложения, текущий шаг), `path`, `ahead`, `cursorStepId`, `progress`, `requiredStepsFilled` | сценарий — редактор/конфигуратор МИ; прохождение — бэкенд МИ |
| Вложение шага | `ScenarioAttachment` [4999](../../Specification/Workflow_machine/openapi.json#L4999) | `source` camera/map/operator/fixed, `mime`, `sha256`, `dataBase64` или `storage {kind: s3 \| url}` | хранилище файлов — не решено |
| Медиа | `IncidentMedia` [5150](../../Specification/Workflow_machine/openapi.json#L5150) | `cameras[] {guid, name, isSource, archiveUrl, liveUrl, archiveStartAt, thumbnailUrl}`, `map {planGuid, planName, imageUrl, markers[{deviceGuid, x, y, isSource}]}` | VMS и картоподсистема |
| Устройства и группы | `DeviceRef` [4464](../../Specification/Workflow_machine/openapi.json#L4464), `SourceGroupNode` [5603](../../Specification/Workflow_machine/openapi.json#L5603), `DeviceType` [5833](../../Specification/Workflow_machine/openapi.json#L5833) | устройство: `guid`, `name`, `typeId`; дерево групп с вложенностью и счётчиками | устройства — VMS/облако; группы хранит МИ (§19.1) |
| Группа доступа | `AccessGroup` [5240](../../Specification/Workflow_machine/openapi.json#L5240) | роли основной системы → группы устройств и устройства | МИ, роли — внешняя система |
| Дежурная группа | `DutyGroup` [5307](../../Specification/Workflow_machine/openapi.json#L5307) | `roles`, `members`, `memberIds` — состав сейчас | МИ, роли и люди — внешняя система |
| Адресат передачи | `TransferTarget` [5453](../../Specification/Workflow_machine/openapi.json#L5453) | `id`, `kind`, `name`, `role`, `available`, `availabilityLabel`, `memberIds` | МИ по ролям и правам всех пользователей |
| Связь камер | `CameraLink` [5347](../../Specification/Workflow_machine/openapi.json#L5347) | `name`, `devices[]`, `cameras[]`, многие-ко-многим | МИ, камеры — VMS |
| Справочники | `EventType` [5575](../../Specification/Workflow_machine/openapi.json#L5575), `PriorityRef` [5681](../../Specification/Workflow_machine/openapi.json#L5681), `Reason` [5497](../../Specification/Workflow_machine/openapi.json#L5497), `HelpLink` [5409](../../Specification/Workflow_machine/openapi.json#L5409) | типы событий с нормативом, уровни приоритета с цветом, причины, ссылки площадок | типы событий — источники/правила МИ; остальное — МИ |
| Схема workflow | `WorkflowDefinition` [2394](../../Specification/Workflow_machine/openapi.json#L2394), `AdminSettings` [3202](../../Specification/Workflow_machine/openapi.json#L3202) | состояния, переходы, формы, таймеры, лимиты, эскалация, CEL | конфигурация МИ |
| Событие потока | `IncidentStreamEvent` [5704](../../Specification/Workflow_machine/openapi.json#L5704) | `id`, `type`, `at`, `incidentGuid`, `actor`, `incident`, `payload` | бэкенд МИ |

Идентификаторы: у инцидентов, устройств, групп устройств, типов событий, планов и сценариев — UUID. У людей и дежурных групп — строки внешней системы ([BACKEND.md:31](../../Specification/Workflow_machine/BACKEND.md?plain=1#L31)).

## Реальное время

- **Канал.** SSE `GET /operator/stream`, `text/event-stream`. Сообщения идут без строки `event:`, тип лежит в `data.type`, в `id:` — номер события. При переподключении клиент шлёт `Last-Event-ID`, сервер досылает пропущенное. Хранить нужно не меньше 500 событий и не меньше чем за 10 минут. Если истории нет — сервер шлёт `stream.reset`, клиент перечитывает очередь, карточку и сессию. «WebSocket допустим как альтернатива», опрос не годится: при уводе карточки её нужно немедленно перевести в просмотр ([openapi.json:1557](../../Specification/Workflow_machine/openapi.json#L1557)).
- **Типы событий (12):** `incident.created`, `incident.transitioned`, `incident.updated`, `incident.card_evicted`, `incident.access_lost`, `incident.alert`, `journal.appended`, `macro.completed`, `session.agent_state_changed`, `workflow.schema_published`, `reference.priorities_changed`, `stream.reset`. Таблица «когда, кому, payload» — в описании схемы ([openapi.json:5704](../../Specification/Workflow_machine/openapi.json#L5704)). События об инциденте получает только тот, кому инцидент виден по группам доступа. Исключение — `incident.access_lost`: оно приходит без данных, только с номером.
- **Клиент.** `new EventSource(base + "/operator/stream", { withCredentials: true })`. После обрыва — `onReconnect` и полное перечитывание ([api.js:31–42](../../prototype/api.js#L31); [app.js:4305](../../prototype/app.js#L4305)).
- **Признак активности.** `POST /operator/session/heartbeat` раз в `session.heartbeatSec` (сейчас 30 с) с открытой карточкой ([app.js:973](../../prototype/app.js#L973), [:4277](../../prototype/app.js#L4277)). Если его нет `idleHoldSec` (5 мин), инциденты уходят в «Отложен — нет связи», через `idleReleaseSec` (20 мин) — в очередь ([SETTINGS.md:60](../../Specification/Workflow_machine/SETTINGS.md?plain=1#L60)).
- **Время.** Таймеры исполняет планировщик сервера. Клиент только рисует отсчёт от `dueAt` с поправкой на `serverTime` ([app.js:716](../../prototype/app.js#L716); [FRONTEND.md:79](../../Specification/Workflow_machine/FRONTEND.md?plain=1#L79)). Встроенный сервер «тикает» раз в секунду ([server.js:1982](../../prototype/server.js#L1982)).
- **Вывод:** облаку нужен долгоживущий push-канал через шлюз: SSE или WebSocket, с прохождением авторизации и без обрыва по таймауту прокси. Ещё нужна история событий на сервере для досылки.

## Что нужно от окружения

| Потребность | Где в прототипе | Чем заменено в прототипе | Вопрос к облаку / бэкенду |
|---|---|---|---|
| **Вход, личность оператора** | `GET /operator/session` при старте; клиент API [api.js:13–44](../../prototype/api.js#L13) | входа нет: оператор всегда `me` из набора ([server.js:38](../../prototype/server.js#L38); `demo.json` → `operator`, `people.operators`). §17: «входа нет: у оператора стенда все права» ([правила:834](../../Specification/State_rules/States%20rules%20IM.md?plain=1#L834)) | Кто выдаёт пользователя и его `guid`? Портал облака (Keycloak/свой IdP)? Совпадает ли `guid` с id в журналах и `ActorRef.id`? |
| **Передача токена** | внешний режим: `fetch(..., {credentials: "include"})` и `EventSource({withCredentials: true})`, заголовка `Authorization` нет ([api.js:20](../../prototype/api.js#L20), [:32](../../prototype/api.js#L32)) | — | Контракт требует Bearer JWT из `localStorage.accessToken` ([openapi.json:2167](../../Specification/Workflow_machine/openapi.json#L2167)), клиент шлёт только куки. Что даёт облако: куку сессии (`SameSite=None; Secure`), токен в адресе потока или шлюз, который меняет куку на токен? ([README машины:451](../../Specification/Workflow_machine/README.md?plain=1#L451)) |
| **Права** (каталог МИ, 14 ключей) | `session.permissions`; кнопки и отказы считает сервер | роли и права из набора: `demo.json` → `roles[].permissions`; смена ролей — `PUT /test/operators/{id}/roles` | Где облако привязывает права МИ к ролям? Как МИ узнаёт права — в токене, запросом с кэшем или токеном плюс событие «права изменились» (§15, [правила:774](../../Specification/State_rules/States%20rules%20IM.md?plain=1#L774))? |
| **Роли и права всех пользователей** | адресаты передачи, дежурные группы, получатели алертов; CEL-факты `can`, `access`, `members` ([workflow_schema.v1.json:1394](../../Specification/Workflow_machine/workflow_schema.v1.json#L1394)) | `people.operators`, `people.dutyGroups` набора; коллег эмулирует [`colleagues.js`](../../prototype/colleagues.js) | Есть ли в облаке API «список пользователей с ролями» и событие смены ролей? Нужно, чтобы передавать только тому, кто может принять (§8.1), и проверять потерю доступа (§5) |
| **Состояние «на месте»** других людей | `TransferTarget.available`, `availabilityLabel` | `agentState` коллег из набора | Только из МИ (вошёл / перерыв / вышел)? Связано ли с присутствием в портале облака? |
| **Группы доступа** (роль → группы устройств) | видимость очереди, карточки и потока; `GET /operator/admin/access-groups` | `demo.json` → `accessGroups` | Хранит МИ (§5). Совпадают ли названия ролей с ролями облака? Нет ли в облаке своего ACL на устройства, который надо учитывать или который заменяет группы доступа? |
| **Источник событий → инцидент** | переход машины `create`; событие `incident.created` | инциденты набора + `POST /test/incidents` (`eventTypeId`, `priority` 0–100, `deviceIds[]`, первое — источник, `site`, `location`, `occurredAt`) ([openapi.json:1736](../../Specification/Workflow_machine/openapi.json#L1736)) | Откуда события в облаке (тревоги VMS, axxoncloudgo)? Кто создаёт инцидент — бэкенд МИ по правилам? Как выбрать один сценарий, если правил или сценариев несколько ([BACKEND.md:82](../../Specification/Workflow_machine/BACKEND.md?plain=1#L82))? Где берутся `site`, `location`, приоритет-число? |
| **Устройства, типы устройств, группы** | дерево групп, фильтр «Тип устройства», `DeviceRef` | `demo.json` → `devices`, `deviceTypes`, `sourceGroups` ([server.js:354–373](../../prototype/server.js#L354)) | Откуда список устройств и их UUID (облако, VMS)? Группы устройств хранит МИ (§19.1): как они синхронизируются при удалении или переименовании устройства? |
| **Видео: архив и онлайн** | `GET …/media` → `cameras[].archiveUrl`, `liveUrl`, `archiveStartAt`, `thumbnailUrl`; панель «Архив/Online» | рисованные кадры `demo:scene/…`. `archiveUrl`/`liveUrl` сервер отдаёт `null` ([server.js:851–852](../../prototype/server.js#L851)), клиент их не читает — только `thumbnailUrl` ([app.js:2601–2666](../../prototype/app.js#L2601)) | Какой плеер облака встраивается (компонент axxoncloud-ui или URL)? Нужны ли подписанные URL, какой формат (HLS, WebRTC)? Первая версия — до 4 камер одновременно ([FRONTEND.md:65](../../Specification/Workflow_machine/FRONTEND.md?plain=1#L65)) |
| **Связи камер** | камеры инцидента — из связей источника | `demo.json` → `cameraLinks` | Хранит МИ (§19.1). Есть ли похожий объект в облаке? |
| **Карта, планы объектов** | `media.map {imageUrl, markers}`, `mediaKinds` | `demo:plan/…` — SVG-заглушки; позиции устройств в `devices[].position` набора | Есть ли в облаке планы и координаты устройств? Кто отдаёт картинку плана? |
| **Снимок с камеры или карты в шаге сценария; файлы оператора** | `ScenarioAttachment` | снимок — пустая заглушка; файл — `dataBase64` в самом прохождении (§17) | Хранилище файлов (S3 облака?) и как брать кадр из VMS |
| **Макросы, команды ТСО** | внешний эффект; `macro.completed` в потоке | исполнения нет: макрос сразу `delivered` ([server.js:234–254](../../prototype/server.js#L234)) | Кто исполняет макрос по имени из сценария (VMS, облако)? Как приходит результат? Очередь исходящих с повторами — §14.2 |
| **Уведомления и алерты** | эффект `notify`; `incident.alert` в потоке | только внутри вкладки, без звука (§17) | Достаточно канала МИ (§8.1) или нужны уведомления облака (центр уведомлений, push)? |
| **Сценарии обработки** | `IncidentScenario.script` — формат редактора продукта | файлы `fixtures/scenarios/*.json`, выбор по типу события (`scenarios.byEventType`) (§14.5) | Сценарии из `incident-manager-server` (`scenarios.script`, версия растёт при сохранении): тот же сервер обслуживает и оператора? |
| **Справочники МИ: типы событий, приоритеты, причины, справочные ссылки** | `/operator/reference/…` | из набора и схемы; правки нет | Правку делает конфигуратор МИ? Типы событий — из облака или из МИ? |
| **Настройки администратора** | меню пользователя → «Настройки администратора», только просмотр; перечень — [SETTINGS.md](../../Specification/Workflow_machine/SETTINGS.md) | значения из машины и набора | Где экран правки — в конфигураторе МИ (`/im/` портала)? Запросы правки групп доступа, дежурных групп, ссылок, связей камер бэкенд описывает сам ([BACKEND.md:53](../../Specification/Workflow_machine/BACKEND.md?plain=1#L53)) |
| **Локализация** | системные тексты — ключами каталога `GET /operator/strings` ([app.js:4285](../../prototype/app.js#L4285)); язык — `PATCH preferences {locale}` ([app.js:829](../../prototype/app.js#L829)) | каталоги `strings/ru.json`, `en.json`. Тексты интерфейса — словари `i18n-ui.js`, `i18n-html.js` с русским текстом вместо ключа. Названия из набора переводит `i18n-data.js` — только демо | По §14.9 список языков задаёт облако, а каталог хранит бэкенд МИ. Как облако сообщает язык пользователя и список языков? Совпадают ли коды BCP 47? |
| **Тема и оформление** | `data-theme` light/dark; переменные [`theme/one-psim.css`](../../theme/one-psim.css) через [`bridge.css`](../../prototype/bridge.css) | тема — `localStorage["im-theme"]` ([app.js:738](../../prototype/app.js#L738)), не `preferences.theme`; раскладка панелей — `localStorage["im-layout"]` ([app.js:3032](../../prototype/app.js#L3032)), не `preferences.panels` | Берёт ли модуль тему облака (переключатель портала)? Совпадает ли ONE PSIM с дизайн-системой axxoncloud-ui? |
| **Шрифты и значки** | Inter и Material Symbols с `fonts.googleapis.com` ([index.html:7–8](../../prototype/index.html#L7)) | CDN | Разрешён ли внешний CDN в облаке (CSP) или нужны свои копии? |
| **CORS / один источник** | внешний режим — со страницы на другой адрес; тестовая страница с диска — `Origin: null` ([BACKEND.md:63](../../Specification/Workflow_machine/BACKEND.md?plain=1#L63)) | петля Service Worker в тестах | Модуль живёт в том же источнике, что и шлюз облака (тогда CORS не нужен)? |
| **Журнал действий оператора** (§12.4) | — | не хранится, только журнал по инцидентам (§17) | Общий аудит облака или свой в МИ? |

## Технология и что переносится

**Факты.**

- Чистый JS без сборки и модулей: обычные `<script>` в фиксированном порядке ([index.html:513–531](../../prototype/index.html#L513)). Страница открывается с диска (`file://`). Поэтому машина, контракт, набор и строки собираются в JS-файлы `tools/build_workflow.py` ([README прототипа](../../prototype/README.md)).
- Фреймворка нет: интерфейс [`app.js`](../../prototype/app.js) (4310 строк) рисует HTML строками. Стили — [`styles.css`](../../prototype/styles.css) + [`bridge.css`](../../prototype/bridge.css) поверх словаря ONE PSIM.
- Вендорные библиотеки в [`prototype/vendor`](../../prototype/vendor/cel-js/ORIGIN.md):
  - `@marcbachmann/cel-js` 8.0.0, MIT, собран esbuild в IIFE — выражения CEL машины;
  - `json-logic-js` 2.0.5, MIT — условия сценариев ([ORIGIN.md:85–96](../../Specification/Scenario_machine/ORIGIN.md?plain=1#L85)).
  Обе нужны только встроенному серверу (`engine.js`, `cel-runtime.js`, `scenario.js`), не интерфейсу.
- Слои ([README прототипа](../../prototype/README.md)): `app.js` → `api.js` → `server.js` → `engine.js` → `cel-runtime.js`; `scenario.js` — исполнитель сценариев.

**Что переносится — требование** ([FRONTEND.md:35–49](../../Specification/Workflow_machine/FRONTEND.md?plain=1#L35)):

- поведение и вид: кнопки видны всегда, цвета действий, две кнопки закрытия, поле «Кому передать», выборка, привязанные, раскладка карточки, клавиатура без горячих клавиш, контраст 4,5:1, телефон 360 px, две темы ONE PSIM;
- принцип «у клиента нет своей модели»: кнопки, формы, бейджи, тексты — из ответов сервера ([FRONTEND.md:23–31](../../Specification/Workflow_machine/FRONTEND.md?plain=1#L23));
- протокол работы с сервером: `If-Match`/`412`, `idempotencyKey`, `expectedVersions`, SSE с перечитыванием, heartbeat, поправка часов ([FRONTEND.md:71–79](../../Specification/Workflow_machine/FRONTEND.md?plain=1#L71));
- шаги самопроверки [`selftest.js`](../../prototype/selftest.js) — список сценариев приёмки нового клиента.

**Что только образец** ([FRONTEND.md:51–60](../../Specification/Workflow_machine/FRONTEND.md?plain=1#L51)): встроенный сервер и исполнитель (`server.js`, `engine.js`) — пример для бэкенда; эмуляция коллег; перевод введённых названий; рисованные кадры и планы `demo:*`; механизм самопроверки; собранные `workflow.js`, `openapi.js`, `fixture.js`, `strings.js`.

**Не сделано** ([FRONTEND.md:62–69](../../Specification/Workflow_machine/FRONTEND.md?plain=1#L62); [BACKEND.md:74–84](../../Specification/Workflow_machine/BACKEND.md?plain=1#L74)):

- тексты интерфейса в каталог строк (PROC-15);
- видео до 4 камер;
- схема входа;
- экраны администратора (правка);
- редактор схемы;
- журнал действий оператора;
- перестановка панелей, расписание перерывов;
- тесты не покрывают 10 операций: редактор схемы и правку приоритетов.

**Готовность бэкенда** ([BACKEND.md](../../Specification/Workflow_machine/BACKEND.md)): все тесты `tests/api.html?api=https://стенд` зелёные, прототип `index.html?api=https://адрес` работает с ним. Для этого нужны 4 операции `/test/*` и CORS со стенда.

**Выводы:**

- В облако переносится не код, а контракт, поведение и тесты. Код `app.js` годится как образец экрана; продуктовый клиент, вероятно, пишется заново на стеке axxoncloud-ui или конфигуратора МИ.
- Тесты API (`tests/api.html?api=…`) — готовый приёмочный набор для бэкенда в облаке, если стенд даст `/test/*` и вход для оператора `me`.

## Связь с `incident-manager` и `incident-manager-server` (что уже известно)

- Машина сценариев перенесена в IM 2026-10-19. Формат сценария — тот, что сохраняет редактор продукта `incident-manager` (`src/shared/schema/scenario.zod.ts`, коммит `1fcfa25`). Сверены `jsonLogic.ts`, `validation.ts`, `playerEngine.ts` ([ORIGIN.md:63–71](../../Specification/Scenario_machine/ORIGIN.md?plain=1#L63)). Формат прохождения задаёт МИ (§14.5).
- Из `incident-manager-server` (`b743797`, `api/im/backend.openapi.yaml`) взяты только идентичность и версия сценария, ссылка инцидента на версию и `scenarioResult` ([ORIGIN.md:11](../../Specification/Scenario_machine/ORIGIN.md?plain=1#L11)).
- Ревью 2026-10-19 ([review.md:58–63](../../reviews/2026-10-19/review.md?plain=1#L58)):
  - редактор пишет сценарий в `script` сервера (`imBackendScenarios.dto.ts:65`);
  - на сервере `script` непрозрачен, `guid` назначает сервер, `version` растёт при каждом сохранении;
  - инцидент ссылается на `(scenario_guid, scenario_version)` внешним ключом, снимка нет (`001_initial_scheme.sql:198–205`);
  - у правила инцидента — список сценариев.
- [BACKEND.md:82](../../Specification/Workflow_machine/BACKEND.md?plain=1#L82): сервер сейчас создаёт по инциденту на каждый сценарий каждого подошедшего условия (`incidentrulecondition/processor.go`, `incident.Service.CreateIncidents`). Правило без сценария инцидента не создаёт. Правило МИ — «одно событие — один инцидент» (решение 2026-10-19).
- Контракт `openapi.json` — «предложение фронтенда бэкенду по задаче CLOUD-23465». База `/api/v1/im-backend` и JWT из `localStorage.accessToken` записаны «как в остальных вызовах im-backend» ([openapi.json:15](../../Specification/Workflow_machine/openapi.json#L15), [:2168](../../Specification/Workflow_machine/openapi.json#L2168)). **Вывод:** операторская часть задумана как часть того же `im-backend`, что обслуживает конфигуратор МИ в портале. **Предположение:** токен в `localStorage.accessToken` кладёт портал облака — сверить с 02/06.

## Видение: сервер, облако, видео, карта, интеграции

- [Vision](../../Specification/Axxon%20Incident%20Manager%20Vision.md):
  - внешнее ПО (AxxonNext, Intellect) — через API с плагинами (стр. 5);
  - HTTPS и безопасная аутентификация (стр. 7);
  - собственная система прав (стр. 13) — решено иначе: права МИ, роли во внешней системе;
  - «Диспетчер событий создаётся в ITV DataCenter», фильтры событий, удалённый выбор серверов-источников, таймеры и автоэскалация (стр. 43–47);
  - веб-плеер: архив и онлайн, несколько камер, камеры региона (стр. 59–60);
  - карта с местом инцидента (стр. 64);
  - отчёты, журнал действий оператора (стр. 70–83).
- Слова «облако» в Vision нет. В правилах: «МИ встраивается в стороннее облако. Список языков… настраивается снаружи, в облаке. Каталог строк… в бэкенде МИ» (§14.9, [правила:758](../../Specification/State_rules/States%20rules%20IM.md?plain=1#L758)).
- [Vision coverage](../../Specification/Vision%20coverage.md) помечает «вне репозитория»:
  - плагины к внешнему ПО;
  - HTTPS и вход;
  - диспетчер событий;
  - отчёты.
  
  «Частично»:
  - несколько камер — одна с переключением, первая версия — до 4;
  - группировка — экран групп позже;
  - журнал оператора.
  
  Карта — «есть, автоматически».

## Открытые вопросы

К облаку (axxoncloudgo, axxoncloud-ui):

1. Вход: какой IdP и токен; как модуль получает токен (куки, `localStorage.accessToken`, обёртка портала); как авторизуется поток SSE или WebSocket — `EventSource` не шлёт `Authorization`. Нужно согласовать контракт (Bearer) и клиента (куки).
2. Где привязываются права МИ (14 ключей §5) к ролям. Есть ли API «все пользователи с ролями и правами» и событие смены ролей.
3. Push-канал через шлюз облака: SSE или WebSocket, таймауты, история для досылки по `Last-Event-ID`.
4. Источник тревог: из какого сервиса облака приходят события VMS. Как они попадают в бэкенд МИ, с какими полями (устройство-источник, тип события, площадка, приоритет-число).
5. Устройства и их UUID, типы устройств: единый реестр облака? Как МИ узнаёт об удалении или переименовании?
6. Видео: какой плеер и формат URL (архив с момента, онлайн); подписанные ссылки; до 4 камер; кадр для шага сценария.
7. Карта и планы: есть ли в облаке планы с координатами устройств.
8. ACL облака на устройства и группы доступа МИ: кто главный, не дублируются ли.
9. Макросы и команды ТСО по имени из сценария: кто исполняет, как возвращается результат.
10. Язык и тема пользователя: откуда их берёт модуль. Список языков облака. Дизайн-система ONE PSIM против дизайн-системы axxoncloud-ui. Внешние шрифты и значки (CSP).
11. Хранилище вложений (S3?) и уведомления вне МИ.

К бэкенду МИ (incident-manager-server):

12. Будет ли бэкенд реализовывать `openapi.json` как есть, под `/api/v1/im-backend/operator/…`, вместе с исполнением машины (CEL) и машины сценариев.
13. Один инцидент на событие и выбор одного сценария; снимок сценария или ссылка на версию.
14. Тестовый стенд: `/test/*` и CORS на стенде — для приёмки тестами `tests/api.html`.
15. Номер версии формата сценария (§15). Где хранятся группы доступа, дежурные группы, группы устройств, связи камер, справочные ссылки, и чьи экраны их правят (конфигуратор МИ?).
16. Журнал действий оператора (§12.4): пишет ли бэкенд с первой версии.

Расхождения внутри прототипа, которые стоит учесть:

- контракт объявляет Bearer, а `api.js` шлёт куки;
- тема и раскладка хранятся в `localStorage`, а не в `preferences.theme` / `panels`;
- `liveUrl` и `archiveUrl` клиент не использует.
