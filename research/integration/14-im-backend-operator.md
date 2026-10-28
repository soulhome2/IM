# Бэкенд МИ для оператора: где строить, агенты, контракт

- Тема: операторский API, машина (CEL), исполнитель сценариев и поток событий в бэкенде МИ; агенты МИ и поля события; связь устройства с камерой облака; один инцидент на событие; OpenAPI 3.1 против 3.0; статусы и тестовый стенд; макросы.
- Дата: 2026-10-28 (второй круг).
- Снимки:
  - `NEW/incident-manager-server` — `develop` `b743797a38daeb3beaa44ef901b26c3ce924290f`, локальная копия `../incident-manager-server` (рабочее дерево чистое, `git log -1` проверен);
  - `PROJ/incident-manager` (конфигуратор) — `master` `1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0`, локально;
  - IM (прототип) — `main` `d891125`: [`openapi.json`](../../Specification/Workflow_machine/openapi.json), [`BACKEND.md`](../../Specification/Workflow_machine/BACKEND.md), [`workflow_schema.v1.json`](../../Specification/Workflow_machine/workflow_schema.v1.json), [`CEL.md`](../../Specification/Workflow_machine/CEL.md), [правила](../../Specification/State_rules/States%20rules%20IM.md);
  - `PROJ/oapi-codegen` (форк генератора) — `master` `d7822d9560caffb66099da7f9e2cc31960a6f3c0`, Bitbucket MCP;
  - `IT/axxoncloud-deploy` (деплой облака) — ветка по умолчанию `91d1e6d25f3e5ff4273fc1277bf109970a8fcaec`, Bitbucket MCP (найден поиском, в первом круге не смотрели).
- Поиск агентов: Bitbucket `search` по всем проектам (ищет только ветки по умолчанию), список всех 386 доступных репозиториев, Jira (проект CLOUD).

Обозначения: без пометки — факт со ссылкой; **Вывод:** — следует из фактов; **Предположение:** — не проверено. Найденное в первом круге не повторяю — ссылаюсь на [03](03-im-server.md).

## Коротко

1. **Где строить.** В `incident-manager-server`, отдельным пакетом `internal/im/operator/…` и вторым сгенерированным сервером под `/operator/…` и `/test/…`. Переиспользуется немного: вход через облако, источники, группы устройств, правила доступа, сценарии с версиями, приоритеты, приём событий. Заново — почти всё операторское: данные инцидента под машину, исполнитель CEL (`cel-go`), JSONLogic (свой маленький вычислитель на 1007 готовых примерах), планировщик, журнал, поток событий. Шина не обязательна: ленту событий и пробуждение можно сделать на PostgreSQL. Главный риск — порядок номеров ленты при параллельных транзакциях. Оценка — в таблице «Объём работ».
2. **Агенты МИ.** Их кода нет ни в одном репозитории на ветке по умолчанию: искал по заголовкам HMAC, путям `/sync/sources…`, полям `sourceUid` и `eventTypeUid`, именам `im-agent` и `incident-manager-agent`. Событие несёт только `guid`, `sourceUid`, `eventTypeUid` и произвольный `payload`. Время события, площадки, места, приоритета, описания и снимка нет. Для карточки не хватает.
3. **Устройство → камера и домен облака.** Связи нет нигде — ни в сервере, ни в конфигураторе. У агента только имя и арендатор, у источника — `uid`, имя, тип, агент и `is_online`.
4. **Один инцидент на событие.** Код: цикл по всем условиям в [processor.go#86](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/appservice/incidentrulecondition/processor.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#86), внутри — цикл по сценариям правила в [service.go#29](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/service/incident/service.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#29). Дубли получаются ещё и от двух подошедших условий одного правила. Есть и попутные дефекты: события берутся с конца (LIFO), без `SKIP LOCKED`, отметка «обработано» — вне транзакции инцидента. После миграции 010 инцидент не помнит своего правила.
5. **OpenAPI.** Форк `oapi-codegen` 3.1 не понимает: он на `kin-openapi v0.117.0`, где `Schema.Type` — строка. В `openapi.json` 109 мест только из 3.1, не 77: 77 `type: [x, "null"]`, 15 `{type: "null"}` в `anyOf`/`oneOf`, 5 `enum` с `null`, 10 `examples` в схемах, 1 `if`/`const` и 1 `$ref` с соседним полем. Рекомендую держать источником 3.1 и собирать из него 3.0 нашим скриптом. Ошибки: на `/operator/*` — `problem+json`, а `{key, description}` оставить API настройки.
6. **Статусы и `incident_actions`** заменить состоянием машины. Конфигуратор `/statuses` не вызывает. Тестовый стенд — по флагу сборки `teststand`: часы через интерфейс (25 вызовов `time.Now()`, 20 `DEFAULT NOW()` в SQL), подменный клиент облака уже есть.
7. **Макросы.** Их никто не исполняет. В конфигураторе `macro` — свободный текст, в машине — внешний эффект после транзакции (§14.2). Канала «сервер → агент» нет. `multitasking` и `report` для оператора ничего не значат: на экране редактора их нет, машина сценариев их не исполняет.

## 1. Где делать операторский API, машину, сценарии и поток событий

### Ответ

**Что в сервере сейчас и что из этого берём** (устройство сервера — [03, «Устройство и запуск»](03-im-server.md#устройство-и-запуск)):

| Слой сервера | Что есть | Для оператора |
|---|---|---|
| `handler/v1` + `generated/` (strict-server форка) | один контракт `backend.openapi.yaml`, вход `User`/`Agent` через промежуточные слои | **Переиспользуем** вход (`UserAuthMiddleWare`), `createContext`, `getUserFromGinCtx`. Операторский контракт генерировать **отдельным пакетом** (`-package operatorapi`) в свой каталог и регистрировать на том же gin. Два файла контракта, коллизий имён нет |
| `appservice/*` | проверка прав, транзакции (`Transactor.DoInTx`), фоновые процессы (`Start` → `StartProcessing`, [appservice.go#528](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/appservice/appservice.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#528)) | **Новые** appservice: `operator/session`, `operator/queue`, `operator/transition`, `operator/scenario`, `operator/stream`, `operator/scheduler`, `operator/reference`, `operator/workflowschema`, `testsupport` |
| `service/*`, `service/storing` | SQL на `mgutz/dat`, миграции `go:embed` | Переиспользуем store-слой и миграции. Новые таблицы — миграциями 014+ |
| `infrastructure/eventbus` | шина в памяти, два сигнала, при переполнении теряет ([eventbus.go#26](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/infrastructure/eventbus/eventbus.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#26)) | Для потока оператора **не годится**: нужна лента с досылкой, общая для экземпляров |
| `incidentrulecondition/processor.go` | опрос `events` раз в секунду, создание инцидентов | **Переделать** (раздел 4): создание инцидента = переход машины `create` |

**Переиспользуется как есть или с малой правкой:** вход и права через облако; источники, типы и типы событий; дерево групп устройств (для `inSourceGroup` и дерева с счётчиками); правила доступа (основа `access(who, x)`); сценарии с версиями и привязка инцидента к версии (`scenario_guid + scenario_version`, `scenario_result jsonb`); приоритеты (`value` уникален по клиенту, миграция 013); приём событий от агентов.

**Строится заново** (по [`BACKEND.md`](../../Specification/Workflow_machine/BACKEND.md)):

- **Исполнитель машины на CEL.** Библиотека — `github.com/google/cel-go`. Подмножество CEL машины ([CEL.md, «Что из CEL можно»](../../Specification/Workflow_machine/CEL.md)) — стандартные операторы и макросы `exists/all/filter/map`. Плюс `cel.bind`: в cel-go это расширение `ext.Bindings()`. Типы машины (`cel.types`) — Go-структуры через `ext.NativeTypes` или словари `map<string, dyn>`. Статическую проверку типов уже делает `tools/check_cel.mjs` при сборке машины. Факты мира (`can`, `access`, `members`, `agentState`, `idleSec`, `stepsFilled`…) — Go-функции (`cel.Function`). Факты над множеством инцидентов (`incidentById`, `linkedOf`, `countMine`, `mineOf`, `groupMembersAt`) — SQL-запросы по индексам, которые видят изменения своей транзакции. Отдельно, не CEL: интерпретатор операций эффектов (`do`) и ядро исполнения — порядок проверки, `onFail`, всё-или-ничего, `bulk`/`merge`, окно `manualWinsOverTimer`. Образец — `prototype/engine.js` (802 строки) и `cel-runtime.js` (474), их не переносят, а повторяют.
  - Расхождения, за которыми следить. В cel-js целые — `BigInt`, в cel-go — `int64`. Отсутствующий ключ словаря в cel-go — ошибка, а машина считает пусто как `''`/`0`. Значит, мост данных обязан заполнять все поля.
  - **Вывод:** нужен набор эталонных векторов «выражение + мир → результат», выгруженный из прототипа. В IM такого инструмента нет; tests/api.html проверит только итог через HTTP.
- **JSONLogic для сценариев.** Редактор пишет только `var`, `==`, `!=`, `in`, `!`, `and`, `or` ([conditionBuilderLogic.ts#81](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/features/editor/lib/conditionBuilderLogic.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#81)). Операторы `in`, `==`, `!=` переопределены для массивов ([jsonLogic.ts#34](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/shared/lib/jsonLogic.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#34), [#53](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/shared/lib/jsonLogic.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#53), [#59](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/shared/lib/jsonLogic.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#59)). Остальное — нестрогое сравнение JS (`a == b`), его тоже надо повторить.
  - В IM уже есть 1007 крайних случаев на 13 операторах ([`tests/jsonlogic-cases.js`](../../tests/jsonlogic-cases.js): `== var != in ! or missing > some all none missing_some and`) и второй вычислитель на Python — около 110 строк ([`tools/check_scenarios.py#303`](../../tools/check_scenarios.py)), сверенный с ними.
  - **Вывод:** надёжнее свой вычислитель на Go по образцу Python-версии, проверенный этими 1007 случаями, чем готовая библиотека: правила сравнения JS и переопределения у неё всё равно придётся подгонять.
  - **Предположение:** `github.com/diegoholiveira/jsonlogic/v3` позволяет регистрировать свои операторы. Если брать его, прогнать те же 1007 случаев.
  - Остальное исполнителя сценариев — путь, курсор, прогресс «N из M», `ahead`, переответ, `requiredStepsFilled` — по `prototype/scenario.js` (357 строк). Проверка при публикации — как `check_scenarios.py`.
- **Таймеры и автопереходы.** Это единый планировщик (§14.3). Дедлайны хранятся метками в БД. Порядок — общий для всех инцидентов: по моменту наступления, при равенстве — по порядку в машине. Перед любым меняющим запросом оператора сервер догоняет автопереходы этого инцидента в той же транзакции (§14.3, ARCH-10). При нескольких экземплярах планировщик должен быть один: лидер через `pg_try_advisory_lock`. Иначе два экземпляра выполнят один дедлайн дважды или нарушат общий порядок. Сейчас фоновый обработчик берёт события без блокировки строк ([event_queries.go#46](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/service/storing/event_queries.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#46)) — для нескольких экземпляров он уже сейчас небезопасен (раздел 4).
- **Журнал.** Новая таблица `incident_journal (incident_guid, at, actor, template_key, vars jsonb)` пишется в транзакции перехода. Таблица `incident_activities` с колонками «старое/новое значение» формату `templateKey + vars` не подходит ([001#211](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/service/storing/migrations/001_initial_scheme.sql?at=b743797a38daeb3beaa44ef901b26c3ce924290f#211)).
- **Поток SSE с досылкой по `Last-Event-ID`.**
  - Лента — таблица `operator_stream (id bigserial, customer_guid, incident_guid, type, payload jsonb, created_at)`. Её пишет транзакция перехода (outbox), очистка — «не меньше 500 событий и не меньше 10 минут».
  - Каждый экземпляр держит свои SSE-соединения и дочитывает ленту с `id > последнего`. Будит его `LISTEN/NOTIFY` PostgreSQL (pgx умеет), запасной путь — опрос.
  - Видимость (§5) проверяется при отправке под каждого зрителя.
  - **Шина не обязательна:** БД общая, она и есть шина. NATS облака ([04](04-axxoncloudgo.md#коротко)) можно подключить позже за тем же интерфейсом.
  - **Подводный камень:** `bigserial` выдаёт номер при вставке, а видна строка после коммита. Параллельные транзакции могут закоммититься не по порядку номеров, и клиент, дочитавший до 105, навсегда пропустит 104, закоммиченный позже. Варианты: сериализовать запись ленты по арендатору (`pg_advisory_xact_lock(customer)`), отдавать только номера ниже самой старой незавершённой транзакции, или назначать номер отдельным писателем после коммита.
  - Ответ потока должен идти без буферизации: заголовок `X-Accel-Buffering: no`. Шлюз деплоя включает gzip на `/api/v1/im-backend` ([nginx.conf.ctmpl.j2#358](https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/ansible-hc/config/bezeq/common/nginx/nginx.conf.ctmpl.j2?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec#358)), и для `text/event-stream` это надо проверить.
  - SSE писать обычным gin-обработчиком, не через strict-server: тот рассчитан на ответ целиком.
- **Несколько экземпляров — уже сейчас проблема.** Деплой собирает upstream `im-backend` из всех экземпляров сервиса `imbackend` в Consul ([nginx.conf.ctmpl.j2#147](https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/ansible-hc/config/bezeq/common/nginx/nginx.conf.ctmpl.j2?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec#147)). А условия правил и состав групп живут в памяти и при правке меняются только на своём экземпляре ([incident_rule_condition.go#125](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/appservice/incidentrulecondition/incident_rule_condition.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#125)). **Вывод:** до второго экземпляра нужна общая лента изменений; она же нужна для потока оператора.

### Объём работ (крупные блоки)

S — небольшая доработка; M — заметный модуль; L — большой модуль с собственной сложной логикой. Сроков не даю.

| Блок | Объём | Что внутри | От чего зависит |
|---|---|---|---|
| Контракт и генерация | M | скрипт 3.1 → 3.0, второй сгенерированный пакет, `problem+json`, `ETag`/`If-Match`/`428`/`412`, идемпотентность 10 минут | решение по OpenAPI (раздел 5) |
| Данные под машину | L | у инцидента: `number` (последовательность по арендатору), `state`, `version`, владелец/адресат/дежурная группа, таймеры, причины, результат закрытия, `linked_to`/`linked_at`/`left_group`, нарушения; таблицы: сессии, схемы workflow с версиями, журнал, лента, ключи идемпотентности, дежурные группы, связи камер, справочные ссылки, причины | — |
| Исполнитель CEL и ядро | L | `cel-go`, факты мира, факты над инцидентами SQL, интерпретатор `do`, `bulk`/`merge`, эталонные векторы | права и состав групп из облака ([03](03-im-server.md#открытые-вопросы)) |
| Планировщик и автопереходы | M | лидер, порядок по дедлайну, догон, молчание оператора, догон в запросе | исполнитель CEL |
| Исполнитель сценариев | M | JSONLogic (S сам по себе), путь, курсор, прогресс, ответы, проверка при публикации | — |
| Сессия оператора | S | состояния, heartbeat, предпочтения, `busy` как производное | — |
| Очередь и выборки | M | страницы, фильтры-выражения, поиск, сортировка, счётчики, `selection`/`filter` | исполнитель CEL (бейджи, фильтры) |
| Поток событий | M | лента, LISTEN/NOTIFY, досылка, видимость, `stream.reset`, вход для `EventSource` | решение по входу ([00, вопросы](00-summary.md#вопросы)) |
| Справочники и админка | M | типы событий/устройств, дерево групп с устройствами и счётчиками, приоритеты, группы доступа, дежурные группы, связи камер, ссылки, каталог строк | — |
| Медиа (камеры, карта) | M | ссылки на видео облака | раздел 3 — блокирует |
| Схемы workflow (8 операций) | M–L | хранение, версии, сопоставление состояний, проверка как `check_machine.py`, симулятор | — |
| Событие → инцидент | S | раздел 4 | — |
| Тестовый стенд | M | `/test/*`, часы, загрузка эталонного набора, смена ролей | раздел 6 |
| Макросы | M | outbox внешних эффектов, канал к исполнителю | раздел 7 — исполнителя нет |

**Вывод:** крупнее всего — данные инцидента и исполнитель CEL с ядром. Остальное строится вокруг них. Сценарии, сессия и событие → инцидент — небольшие и почти независимые.

### Альтернатива — отдельный сервис

| | Плюсы | Минусы |
|---|---|---|
| Отдельный сервис (свой репозиторий) | свой цикл выпусков; долгие соединения SSE и планировщик не мешают API настройки; масштабируется отдельно; свободен от форка генератора (можно генератор с 3.1) | данные общие: источники, группы, правила доступа, сценарии, правила — либо общая БД без границ, либо запросы по сети с кэшем и инвалидацией; создание инцидента из событий — в сервере МИ, нужна передача (очередь или outbox); второй вход через облако и вторая регистрация прав; второй ansible-роль и маршрут в nginx (`/api/v1/im-backend/operator/` — отдельно) |
| **Средний путь** | тот же репозиторий и БД, второй бинарник `cmd/im-operator` с общими `internal/…`: SSE и планировщик живут отдельно, код и миграции — общие | два процесса в деплое; миграции всё равно одни |

**Вывод:** начинать в `incident-manager-server` одним бинарником, но держать операторскую часть отдельным пакетом. Тогда вынести её во второй бинарник — правка `cmd/`, а не переписывание.

### Уверенность

Устройство сервера, шина, обработчик и деплой — подтверждено кодом. Оценки объёма, выбор библиотек и вывод о шине — выводы. Поведение cel-go (`ext.Bindings`, `ext.NativeTypes`) — по документации библиотеки, в коде сервера не проверено: cel-go в зависимостях нет.

### Что спросить у людей

- Команде бэкенда МИ: «Кто делает операторскую часть и в каком виде — пакет в `incident-manager-server` или второй бинарник? Планируется ли больше одного экземпляра `imbackend` в бою?»
- Ей же: «Согласны ли на ленту событий в PostgreSQL с `LISTEN/NOTIFY` вместо NATS для первой версии?»
- Владельцам IM (joynickray): «Нужен ли инструмент выгрузки эталонных векторов CEL (выражение + мир → результат) из прототипа для сверки исполнителя на Go?»

## 2. Агенты МИ: где код и какие поля приходят

### Ответ

**Где код агентов — не найден.** Искал по всем проектам Bitbucket (поиск видит только ветки по умолчанию):

- `X-Access-Key-Id`, `"X-Signature" "X-Date"` — только сторонние SDK (AWS, Aliyun) в чужих репозиториях;
- `sync/sources/event-types`, `im-backend/events`, `eventTypeUid`, `enrollmentToken` — 0 совпадений;
- `incident-manager-agent`, `im-agent` (по имени файла) — только `PROJECT.md` конфигуратора и прототип в личном репозитории, агента нет;
- `imbackend` — только деплой `IT/axxoncloud-deploy`.

В списке всех 386 доступных репозиториев имён с `agent` или `incident` для МИ нет. Есть `ONE/cammeta-agent`, `NEW/updateagent`, `NEW/ad-webapp-agent` — они не про МИ. Личный `~V.BRATISHCHEV/psim-sdk` — SDK плагинов «PSIM-платформы» на gRPC (`PullEvents`), о МИ и `im-backend` в нём ничего нет ([CLAUDE.md](https://src.axxonsoft.dev/bitbucket/projects/~V.BRATISHCHEV/repos/psim-sdk/browse/CLAUDE.md)). В самом сервере агент есть только как подписывающий клиент тестов ([event_client.go](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/handler/v1/event_client.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#13)). **Предположение:** агент ещё не написан, лежит в ветке или в репозитории, к которому нет доступа; либо роль агента будет играть плагин PSIM-платформы.

**Что приходит — по контракту сервера.**

| Откуда | Поля | Ссылка |
|---|---|---|
| `POST /events` (`event`) | `guid` (uuid, от агента, первичный ключ), `sourceUid`, `eventTypeUid`, `payload` (произвольный объект) | [backend.openapi.yaml#2215](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/api/im/backend.openapi.yaml?at=b743797a38daeb3beaa44ef901b26c3ce924290f#2215) |
| `POST /sync/sources` (`syncSource`) | `uid`, `name`, `typeUid`, `isOnline` | [#2556](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/api/im/backend.openapi.yaml?at=b743797a38daeb3beaa44ef901b26c3ce924290f#2556) |
| `/sync/sources/types`, `/sync/sources/event-types` | `uid`, `name` (+ `sourceTypeUid` у типа события) | там же |
| Сервер сам | время события = **время приёма** `time.Now()` ([event/service.go#29](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/service/event/service.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#29)); агент и арендатор — из ключа HMAC; приоритет — от правила | [event.go#59](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/appservice/event/event.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#59) |

Состав `payload` нигде не описан, в тестах он `{"test": 1}`. Повтор события с тем же `guid` — ошибка вставки по первичному ключу. **Вывод:** агент при повторе получит 500, а не «уже принято»; идемпотентности на приёме нет.

**Хватает ли для карточки `IncidentCard`** (`IncidentSummary` + карточка в [`openapi.json`](../../Specification/Workflow_machine/openapi.json)):

| Поле контракта | Есть ли источник | Чего не хватает |
|---|---|---|
| `occurredAt` (время события) | нет: сервер пишет время приёма | поле времени события от агента |
| `createdAt` (появление в МИ) | да — момент перехода `create` | — |
| `eventType {guid, id, name, defaultReactionSec}` | частично: тип события `uid`/`name`, привязан к типу устройства | общий код (`fire`) не зависит от типа устройства; `defaultReactionSec` — данные МИ |
| `priority` (0–100) | да — от правила (`priority_guid` → `value`) | значение от источника (`BACKEND.md`: «от источника — число») агент не передаёт |
| `source: DeviceRef {guid, name, typeId, typeLabel}` | да — из `sources` и `source_types` | — |
| `sourceGroup`, `sourceDeviceTypeId` | да — дерево групп, тип источника | — |
| `site`, `siteType`, `location` | **нет** | ни в событии, ни в устройстве; **предложение:** брать из пути группы устройств (верхний уровень — площадка) или добавить поля к устройству |
| `description` | нет | текст от агента или из `payload` |
| `devices` | частично — только источник | связанные устройства — из связей камер (данные МИ) |
| `media.cameras` (видео, `thumbnailUrl`), `media.map` | **нет** | раздел 3; снимка в событии нет |
| `scenario`, `scenarioTitle`, `scenarioProgress` | да — сценарий версии правила | — |
| `state`, `owner`, таймеры, журнал, `version`, `number`… | нет — это машина | раздел 1 |

**Вывод:** для карточки агенту нужно передавать хотя бы время события, а лучше и описание, ссылку на снимок или камеру и приоритет источника. Площадку и место проще вести в МИ на устройстве или группе, чем ждать от агента. Это расширение `event`/`syncSource` и договорённость о `payload`.

### Уверенность

Поля событий и синхронизации — подтверждено кодом и контрактом. Отсутствие кода агентов — не найдено (где искал — выше); поиск Bitbucket не видит нестандартные ветки и личные репозитории без доступа.

### Что спросить у людей

- Команде бэкенда МИ (Asker Shogenov — автор схемы) и Viacheslav Bratishchev: «Где код агента МИ (`POST /agents`, `/sync/*`, `POST /events` с HMAC)? Кто его пишет и на какой стороне он стоит — на сервере VMS (Axxon One, Интеллект), отдельной службой, плагином PSIM-платформы?»
- Им же: «Какой состав `payload` события? Будут ли в событии время события на устройстве, описание, приоритет источника, снимок?»

## 3. Связь устройства агента с камерой облака и доменом

### Ответ

- **В сервере связи нет.** У `agents` — `name`, `creator_user_id`, `customer_guid` ([001#12](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/service/storing/migrations/001_initial_scheme.sql?at=b743797a38daeb3beaa44ef901b26c3ce924290f#12)). У `sources` — `uid`, `name`, `type_guid`, `agent_guid`, `customer_guid` ([#59](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/service/storing/migrations/001_initial_scheme.sql?at=b743797a38daeb3beaa44ef901b26c3ce924290f#59)) и `is_online` (миграция 012). Поиск `domain|camera|accessPoint|vms` по Go, SQL и YAML сервера находит только тестовые данные.
- **В конфигураторе связи нет.** Поиск `domainId|accessPoint|configsync|vmsUid|webclient` в `src/` пуст; «камера» есть только как источник картинки шага `Image.source = 'camera'` ([scenario.ts#49](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/shared/types/scenario.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#49)).
- **Что нужно с другой стороны** ([04](04-axxoncloudgo.md#устройства-видео-события)). Камера облака — запись `configsync` с `accessPoint`, `vmsUid`, `displayId`, координатами. Видео — `/arpserver/<domainId>_<n>/webclient/…` или `embedded.html` с `accessPoint`. У домена есть `vms_uid`.
- **Что в контракте IM.** `IncidentMedia.cameras[] {guid, name, isSource, liveUrl, archiveUrl, archiveStartAt, thumbnailUrl}`, связи камер `CameraLink` — устройства ↔ камеры по `guid`.

**Чего не хватает — и предложение (Вывод):**

1. У агента — домен облака (`cloud_domain_id`). Его задаёт администратор при выпуске токена регистрации. Или агент сообщает `vms_uid`, а МИ находит домен по нему. **Предположение:** S2S `/ac/v1/domains` отдаёт `vms_uid` — не проверено.
2. У устройства — внешняя ссылка `external_ref jsonb`, например `{kind: "axxon-camera", accessPoint, vmsUid}`. Она приходит в `syncSource` для устройств, которые сами камеры. Для датчиков — пусто, камеры к ним дают связи камер.
3. Справочник камер для связей: либо камеры — тоже устройства агента (тогда пункт 2), либо выбор из `configsync` облака по домену. Во втором случае в `CameraLink.cameras[].guid` нужно хранить облачный ключ (`domainId` + `accessPoint`), а не UUID МИ — **ломающее изменение контракта**.
4. Номер агента `<n>` в адресе `arpserver` — из S2S `/ac/v1/arp/domains/:domainId` ([04](04-axxoncloudgo.md#устройства-видео-события)). Либо видео открывается через `embedded.html` вебклиента домена, и адрес строит клиент.
5. Доступ: облако знает права только до домена ([04](04-axxoncloudgo.md#права-и-acl)), группы доступа МИ — по устройствам. Оператор с доступом к устройству в МИ может не иметь `domains.domain.webclient.use` в облаке, и видео не откроется.

### Уверенность

Отсутствие связи в сервере и конфигураторе — подтверждено поиском по коду. Предложение — вывод. Поля облака — по [04](04-axxoncloudgo.md).

### Что спросить у людей

- Команде бэкенда МИ: «Как агент узнаёт и сообщает, к какому домену облака и какой камере VMS относится устройство (`vms_uid`, `accessPoint`)? Будет ли это поле в `syncSource`?»
- Команде облака: «Отдаёт ли S2S `/ac/v1/domains` поле `vms_uid` для поиска домена по VMS? Есть ли S2S-способ получить камеру `configsync` по `domainId + accessPoint`?»
- Владельцам IM: «Камеры в связях камер — устройства агента или камеры облака из `configsync`?»

## 4. Один инцидент на событие и выбор одного сценария (§14.5)

### Ответ

**Как сейчас (точный код):**

1. Раз в секунду `processPendingEvents` берёт 10 необработанных событий **с конца** — `ORDER BY created_at DESC LIMIT 10` ([event_queries.go#54](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/service/storing/event_queries.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#54)) — без блокировки строк ([processor.go#64](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/appservice/incidentrulecondition/processor.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#64)).
2. `processEvent` идёт **по всем условиям всех правил** ([processor.go#86](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/appservice/incidentrulecondition/processor.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#86)). На каждое подошедшее условие читает правило, устройство и статус по умолчанию, ошибки отбрасывая (`rule, _ :=` — [#89](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/appservice/incidentrulecondition/processor.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#89)–91). Затем вызывает `CreateIncidents` в отдельной транзакции.
3. `CreateIncidents` создаёт **по инциденту на каждый сценарий правила** ([incident/service.go#29](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/service/incident/service.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#29)). Сценарии правила — актуальные версии, по имени: `JOIN scenarios_actual … ORDER BY sca.name` ([incident_rule_scenarios_queries.go#38](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/service/storing/incident_rule_scenarios_queries.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#38)).
4. Отметка «обработано» — отдельным запросом **после** цикла и вне транзакции инцидентов ([processor.go#74](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/appservice/incidentrulecondition/processor.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#74)).

**Отсюда дубли и сбои** (подтверждено кодом, последствия — вывод):

- событие × подошедшие правила × **подошедшие условия одного правила** × сценарии правила. Два условия одного правила, оба подошедшие, дают двойной набор;
- правило без сценариев — инцидента нет;
- падение между созданием и отметкой — инцидент создастся повторно; уникального индекса на `incidents.event_guid` нет;
- два экземпляра сервиса берут одни и те же события — дубли;
- при потоке больше 10 событий в секунду старые события ждут бесконечно (LIFO);
- удалено правило или нет статуса по умолчанию — `rule`/`defaultStatus` равны `nil`, обработчик упадёт на `rule.CustomerGUID` или `defaultStatus.GUID` ([#91](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/appservice/incidentrulecondition/processor.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#91)–98);
- миграция 010 удалила `incidents.incident_rule_guid` ([010](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/service/storing/migrations/010_drop_incidents_incident_rule_guid.sql?at=b743797a38daeb3beaa44ef901b26c3ce924290f#1)). Инцидент не знает, по какому правилу создан, а §14.5 и выбор схемы (§14.4) это знание используют.

**Что поменять (Вывод).** Правила (§14.5, §15): решение 2026-10-19 — «одно событие — один инцидент, у правила по договорённости один сценарий»; редактор правил не меняется.

1. Собрать **все** подошедшие условия события и выбрать **одно правило** детерминированно. Предложение — по специфичности, как схема в §14.4: условие с устройством > с группой (глубже — специфичнее) > с типом события и типом устройства > только с типом. При равенстве — по большему приоритету правила, затем по меньшему `guid`.
2. У правила взять **один сценарий**: первый по договорённости. Сохранение правила с несколькими сценариями — предупреждение в API настройки. Порядок «по имени» как правило выбора — случайный для пользователя, лучше ввести явный порядок.
3. Правило без сценария — инцидент **создаётся** без сценария, набор шагов «без шагов». Иначе событие теряется молча. Это решение продукта, см. вопрос ниже.
4. Создание — переход машины `create` в **одной транзакции** с отметкой события. Выборка — `ORDER BY created_at ASC … FOR UPDATE SKIP LOCKED`. Уникальный индекс на `incidents(event_guid)`. Ошибки чтения не отбрасывать.
5. Вернуть в `incidents` ссылку на правило (`incident_rule_guid`) и сохранить, какое условие сработало, — для журнала и разбора.

### Уверенность

Код и последствия для дублей — подтверждено кодом. Правило выбора — предложение.

### Что спросить у людей

- Команде бэкенда МИ: «Согласны ли на выбор одного правила по специфичности условия (устройство > группа > тип события/устройства), затем по приоритету правила? Почему миграция 010 убрала `incident_rule_guid`?»
- Владельцам IM: «Правило без сценария — создавать инцидент без сценария или не создавать вовсе?»

## 5. OpenAPI 3.1 против 3.0, ошибки, CORS

### Ответ

**Генератор.** `Makefile` ставит `src.axxonsoft.dev/bitbucket/proj/oapi-codegen@v0.11.0` ([Makefile#30](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/Makefile?at=b743797a38daeb3beaa44ef901b26c3ce924290f#30)); генераторы — `custom-gin`, `custom-strict-server`, `spec`, `types`, `client`.

- Форк `PROJ/oapi-codegen` — копия `deepmap/oapi-codegen` v1, последняя правка 2024-05.
- Он собран на `github.com/getkin/kin-openapi v0.117.0` ([go.mod#7](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/oapi-codegen/browse/go.mod?at=d7822d9560caffb66099da7f9e2cc31960a6f3c0#7)). В нём `Schema.Type` — строка: код сравнивает `s1.Type != ""` ([merge_schemas.go#128](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/oapi-codegen/browse/pkg/codegen/merge_schemas.go?at=d7822d9560caffb66099da7f9e2cc31960a6f3c0#128)). `nullable` — поле 3.0 ([schema.go#403](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/oapi-codegen/browse/pkg/codegen/schema.go?at=d7822d9560caffb66099da7f9e2cc31960a6f3c0#403)).
- **Вывод:** `type: ["string", "null"]` загрузчик не разберёт — массив в строку. Контракт 3.1 форк не примет.
- Сам сервер в `go.mod` держит `kin-openapi v0.133.0` — только для встроенной спецификации.
- Фильтр по тегам у форка есть (`-include-tags`/`-exclude-tags`, [oapi-codegen.go#95](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/oapi-codegen/browse/cmd/oapi-codegen/oapi-codegen.go?at=d7822d9560caffb66099da7f9e2cc31960a6f3c0#95)). Это пригодится для тестового стенда.

**Сколько мест затронет** (подсчёт скриптом по `openapi.json`, 48 операций, `openapi: 3.1.0`):

| Конструкция 3.1 | Мест | Во что в 3.0 |
|---|---|---|
| `type: [T, "null"]` (string 62, integer 9, array 3, object 3) | 77 | `type: T` + `nullable: true` |
| `{type: "null"}` в `anyOf` (14) и `oneOf` (1) — «ссылка или null» | 15 | `allOf: [{$ref}]` + `nullable: true` (так уже делает сервер для `updatedUser`, [yaml#2100](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/api/im/backend.openapi.yaml?at=b743797a38daeb3beaa44ef901b26c3ce924290f#2100)) |
| `enum` с `null` (`navigate` ×4, `breach`) | 5 | оставить `null` в `enum` + `nullable: true` |
| `examples: [..]` у схемы | 10 | `example: …` |
| `if`/`const` (`SelectionRequest`) | 1 | убрать в описание, проверять в коде |
| `$ref` с соседним `description` (`TransitionRequest.expectedState`) | 1 | обернуть в `allOf` или потерять описание |
| **Итого** | **109** | затронуто 34 схемы с `null` (больше всего — `IncidentSummary`, 18) |

**Варианты.**

- **А (рекомендую).** Источник остаётся 3.1: по нему прототип и `tests/api.html` сверяют ответы. Сборка `tools/build_workflow.py` дополнительно выпускает `openapi.v30.json` механической заменой по таблице. Оба файла проверяются в CI, руками 3.0 не правится. Генератор сервера берёт 3.0.
- **Б.** Перевести сам контракт на 3.0. Тогда проверка ответов в прототипе потеряет `if`/`const` и 3.1-семантику `null`.
- **В.** Новый генератор с 3.1 для операторского пакета. Свои шаблоны `custom-gin`/`custom-strict-server` форка (вход `User`/`Agent`) пришлось бы повторить. **Предположение:** ни upstream `oapi-codegen` v2, ни kin-openapi полностью 3.1 не поддерживают — проверить на момент работ.

**Ошибки.** Сервер: `{key, description}` (+ `values` в схеме) с `application/json` ([apierror/common.go#46](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/util/apierror/common.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#46), [yaml#1942](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/api/im/backend.openapi.yaml?at=b743797a38daeb3beaa44ef901b26c3ce924290f#1942)). Контракт: `Problem {code, message, guard, details, messageKey, messageVars}`, 22 кода в `Problem.code`, `application/problem+json` в 89 ответах. **Вывод:** конфигуратор разбирает `key`, поэтому для API настройки оставить старый формат, для `/operator/*` — `problem+json`. Это два обработчика ошибок по префиксу пути.

**Версия записи.** У сценариев `If-Match` — целое число (`type: integer`, [yaml#980](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/api/im/backend.openapi.yaml?at=b743797a38daeb3beaa44ef901b26c3ce924290f#980), [scenario.go#186](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/handler/v1/scenario.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#186)). В контракте `ETag`/`If-Match` — строка в кавычках `"12"`, плюс `428`/`412`. Для операторского пакета — строка, сценарии конфигуратора не трогать.

**CORS.** `CORSmw` ([main.go#84](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/cmd/im/main.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#84)) отдаёт `Origin *`, заголовки `Content-Type, Authorization, X-Requested-With`. Нет `If-Match`, нет `Access-Control-Expose-Headers: ETag`, нет `credentials` — а с `*` их и нельзя. В бою страница и API в одном origin (`/im` и `/api/v1/im-backend` на одном nginx — [nginx.conf.ctmpl.j2#358](https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/ansible-hc/config/bezeq/common/nginx/nginx.conf.ctmpl.j2?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec#358)), CORS не нужен. Для тестового стенда (`Origin: null` с диска, [BACKEND.md](../../Specification/Workflow_machine/BACKEND.md), «Тестовый стенд», п. 5) — отражать `Origin`, разрешать `If-Match`, `credentials` и открывать `ETag` только в сборке стенда.

### Уверенность

Версия форка, его kin-openapi, тип `Schema.Type`, ошибки и CORS — подтверждено кодом. Число мест — подсчитано скриптом. Что версия v0.11.0 совпадает с `master` `d7822d9` — предположение: тегов не смотрел, но других веток с кодом генератора, кроме `gen-client` и `add-auth-middleware`, нет.

### Что спросить у людей

- Команде бэкенда МИ: «Готовы ли генерировать операторский пакет из 3.0-копии, которую собирает IM, или хотите обновить форк на kin-openapi с массивами типов?»
- Владельцам IM: «Делаем `openapi.v30.json` в `build_workflow.py` (вариант А)?»

## 6. Статусы и `incident_actions` против машины; тестовый стенд

### Ответ

**Статусы.**

- `statuses` (`open`, `in_progress`, `closed` — [002](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/service/storing/migrations/002_add_initial_data.sql?at=b743797a38daeb3beaa44ef901b26c3ce924290f#4)) используются в одном месте: статус по умолчанию при создании инцидента ([processor.go#91](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/appservice/incidentrulecondition/processor.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#91)).
- В ответе `GET /incidents` статуса нет ([yaml#1957](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/api/im/backend.openapi.yaml?at=b743797a38daeb3beaa44ef901b26c3ce924290f#1957)).
- Конфигуратор `/statuses` не вызывает: из справочников ему нужны только `/priorities` ([imBackendIncidentRules.ts#34](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/features/incident-rules/api/imBackendIncidentRules.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#34)).
- `statuses.code` уникален глобально, а не по клиенту ([001#163](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/service/storing/migrations/001_initial_scheme.sql?at=b743797a38daeb3beaa44ef901b26c3ce924290f#163)): второму арендатору свои `open`/`closed` не завести.

**`incident_actions` / `incident_action_transitions`** ([001#243](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/service/storing/migrations/001_initial_scheme.sql?at=b743797a38daeb3beaa44ef901b26c3ce924290f#243)) — только таблицы и DTO, кода нет. Это «действие переводит из статуса в статус», без условий и эффектов.

**Что убрать или переложить (Вывод):**

| В сервере | Чем заменить |
|---|---|
| `incidents.status_guid` → `statuses` | `incidents.state text` (id состояния машины) + `schema_version`; категория — из схемы |
| `statuses` + API `/statuses` (5 операций) | убрать, либо оставить только чтением как переводимые подписи. Подписи состояний — ключи каталога строк машины (§14.6, §14.9) |
| `incident_actions`, `incident_action_transitions` | убрать миграцией. Переходы — в схеме workflow (таблица версий схем, JSON машины) |
| `incidents.escalated*`, `assignee*`, `assigned*` | поля машины: `owner`, `assignment_group`, `escalation_level`, `transfer_count`, таймеры, нарушения |
| `incident_activities` (старое/новое значение) | журнал `template_key + vars` (раздел 1) |
| `incident_rule_user_group_assignments` | кодом не используется (поиск по Go пуст), назначения правил группам заменены `access_rules` — убрать |

**Тестовый стенд** ([BACKEND.md](../../Specification/Workflow_machine/BACKEND.md), «Тестовый стенд»: «в боевой сборке их быть не должно»).

- **Флаг сборки, а не только окружения.** Файлы `testsupport` с `//go:build teststand`. Операции `/test/*` (тег `test-support`) генерировать отдельным пакетом через `-include-tags test-support`, а боевой пакет — с `-exclude-tags test-support`. В боевом бинарнике их нет физически. Включение в стендовой сборке — дополнительно `IM_TEST_SUPPORT=1`.
- **Часы.** Интерфейс `Clock` в `model` и внедрение во все места времени: 25 вызовов `time.Now()` в Go и 20 `DEFAULT NOW()`/`now()` в SQL. Время машины БД брать не должна, только приложение. В боевой сборке — системные часы, в стендовой — управляемые: `POST /test/clock` сдвигает и сразу запускает планировщик синхронно.
- **Люди и роли.** В демо-режиме уже есть подменный клиент облака с зашитыми пользователями ([main.go#47](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/cmd/im/main.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#47), [fake_cloud_client.go](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/handler/test/fake_cloud_client.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#23)). Стенду нужен изменяемый вариант: `PUT /test/operators/{id}/roles` и загрузка людей из эталонного набора.
  - **Подводный камень:** в наборе id людей — строки (`"me"`, `"petrova"`, [`fixtures/demo.json`](../../Specification/Workflow_machine/fixtures/demo.json)), в сервере — `int64`. **Вывод:** в новых операторских таблицах хранить id людей строкой (`text`), как требует контракт, а id облака переводить в строку на входе.
- **`POST /test/reset`.** Загрузчик эталонного набора: устройства, группы, сценарии строками `scenarios.rows`, инциденты со сдвигом времени. Арендатор — тот же тестовый `customer`.
- **`POST /test/incidents`.** Синхронный переход `create`, без очереди событий и HMAC.

### Уверенность

Использование статусов и таблиц — подтверждено кодом. Счёт мест времени — `grep` по Go и SQL. Схема сборки — вывод.

### Что спросить у людей

- Команде бэкенда МИ: «Убираем `statuses` и `incident_actions` в пользу состояний машины? Нужен ли кому-то API `/statuses`?»
- Ей же: «Стенд как отдельная сборка с тегом `teststand` и отдельным образом в Bamboo — подходит?»

## 7. Макросы и флаги `multitasking`, `report`

### Ответ

**В конфигураторе** — `macro {name, args}` на исходе перехода ([scenario.ts#85](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/shared/types/scenario.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#85)). В редакторе это свободное текстовое поле «Макрос (опционально)»; `args` только показываются, не редактируются ([MacroField.tsx#11](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/features/editor/components/transitions/MacroField.tsx?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#11)). Справочника макросов нет, проигрыватель их не исполняет ([02](02-im-configurator.md#данные-которые-нужны-оператору)).

**В машине IM** — макрос исхода запускается при ответе на шаг. Это внешний эффект: запись `workflow.journal.macro.launched` в журнал и событие `macro.completed` в потоке. Условия запуска — у кнопки `run_macro`: право `incident:run_action`, владелец, `agentReady`, состояние `in_progress` ([workflow_schema.v1.json](../../Specification/Workflow_machine/workflow_schema.v1.json), `navActions`). Внешние эффекты (§14.2) — «через очередь исходящих сообщений с повторами и идемпотентными ключами; переход не откатывается», неуспех — в журнал. Прототип только записывает эффект `macro`, исполнения нет ([`scenario.js#175`](../../prototype/scenario.js), `StreamMacroPayload.status`: «в прототипе исполнения нет — delivered»).

**В сервере** — ничего: ни очереди исходящих, ни команды агенту. Агент только синхронизирует и шлёт события, обратного канала нет ([03, API](03-im-server.md#api)).

**Кто исполняет — не решено.**

- **Вывод:** нужен исполнитель имени макроса на объекте.
- **Предположение:** макрос — это макрос VMS (Axxon One или Интеллект) того объекта, откуда пришло событие. Тогда варианты такие:
  - (а) команда агенту — агент забирает команды запросом с HMAC, сервер держит outbox;
  - (б) вызов VMS через облако — gRPC-прокси `arpserver` к NativeBL (`/axxonsoft.bl.*`, право `domains.domain.nativebl.use`, [04](04-axxoncloudgo.md#устройства-видео-события)). Нужна связь устройства с доменом (раздел 3).
- Оба варианта требуют справочника макросов на объекте, чтобы редактор предлагал имена, а не свободный текст.

**`multitasking`** — в редакторе подпись закомментирована: «Step is available in parallel with other tasks» ([StepBasicTab.tsx#21](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/features/editor/components/StepBasicTab.tsx?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#21)). На экране редактора флага нет, новый шаг получает `false`.

**`report`** — флаг отчёта. В исходном формате ПСИМ «Интеллект» это `is_report=1` ([`scenario_spec.v1.md`](../../Specification/Scenario_machine/scenario_spec.v1.md), раздел 2). На экране редактора его нет, новый шаг получает `true`.

Для оператора оба флага ничего не значат: машина сценариев IM их не исполняет ([README машины сценариев](../../Specification/Scenario_machine/README.md), профиль МИ). **Предположение:** `report` — «ответ шага попадает в отчёт по инциденту»; отчётов в первой версии нет.

### Уверенность

Код конфигуратора и записи машины — подтверждено. Исполнитель макросов — не найден: в сервере, конфигураторе и поиске по Bitbucket его нет. Смысл `report` — предположение по исходному формату.

### Что спросить у людей

- Команде конфигуратора и продукту: «Что такое макрос в сценарии — макрос VMS объекта, команда агенту, что-то третье? Откуда взять список имён для редактора?»
- Команде бэкенда МИ: «Будет ли у агента канал команд (outbox → агент) для внешних эффектов: макросы, шлагбаум, вызов наряда?»
- Продукту: «Что задумано под `report` — отчёт по инциденту? Нужен ли `multitasking` вообще?»

## Попутно: деплой МИ в облаке (ответ на вопрос итога о боевом шлюзе)

Нашёлся деплой бэкенда МИ — `IT/axxoncloud-deploy`. Задача [CLOUD-21726](https://support.axxonsoft.dev/jira/browse/CLOUD-21726) «Создание деплой-плана для бэкенда менеджера инцидентов» закрыта.

- Ansible-роль `incidentmanager`: образ `im/backend`, сервис `imbackend` в Consul, порт 5000, проверка `api/v1/im-backend/heartbeat` ([main.yml](https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/ansible-hc/roles/incidentmanager/tasks/main.yml?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec#17)). План Bamboo — [bamboo-specs/IncidentManager.yaml](https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/bamboo-specs/IncidentManager.yaml?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec).
- Шлюз: `location /api/v1/im-backend` → upstream `im-backend` с gzip ([#358](https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/ansible-hc/config/bezeq/common/nginx/nginx.conf.ctmpl.j2?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec#358)) и `location /im` с `try_files $uri $uri/ /im/index.html` ([#453](https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/ansible-hc/config/bezeq/common/nginx/nginx.conf.ctmpl.j2?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec#453)). Тайм-аутов для долгих соединений в блоке нет.
- Окружения: `bezeq/pos1` — с настоящим облаком (`IM_CLOUD_URL=bezeq-pos1.axxoncloud.com`, [imbackend.env](https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/ansible-hc/config/bezeq/pos1/docker/imbackend.env?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec#2)); `bezeq/stage2` — `IM_CLOUD_URL=demo`.
- В обоих файлах `IM_AES_ENCRYPTION_KEY` и пароль БД лежат в репозитории открытым текстом — ключ шифрования секретов агентов.

**Предположение:** раз `pos1` работает не в демо-режиме, облако `bezeq-pos1` принимает `PUT /ac/v1/global-permissions/catalog`, то есть собрано из ветки с этим маршрутом. Не проверено.

## Поправки к первому кругу

- **03, «Сквозные расхождения», версия OpenAPI.** Было: «Предположение: форк `oapi-codegen` 3.1 не понимает». Подтверждено кодом: форк на `kin-openapi v0.117.0`, `Schema.Type` — строка ([merge_schemas.go#128](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/oapi-codegen/browse/pkg/codegen/merge_schemas.go?at=d7822d9560caffb66099da7f9e2cc31960a6f3c0#128)). Число «77 раз `type: [..., "null"]`» верно, но мест только из 3.1 — 109 (раздел 5). То же в [00, «Сквозные расхождения»](00-summary.md#бэкенд-где-исполнять-машину-и-сценарии).
- **03, «Источник инцидентов…».** «На каждое подошедшее условие создаётся по инциденту на каждый сценарий правила» — верно. Стоит добавить, что дублирует и второе подошедшее условие того же правила, что события берутся с конца без `SKIP LOCKED`, что отметка «обработано» идёт вне транзакции и что после миграции 010 у инцидента нет ссылки на правило (раздел 4).
- **03, «Модель данных», строка «Инциденты».** У `incidents` нет `incident_rule_guid` — его удалила миграция 010; таблица 03 этого поля и не называет, но схема 001 по ссылке его содержит. Нужно учесть при чтении. Кроме того, `statuses.code` уникален глобально, а не по клиенту.
- **03, «Деплой».** «Helm-чартов и манифестов Kubernetes нет» — в репозитории сервера да. Но деплой есть в `IT/axxoncloud-deploy` (ansible + Consul + docker, см. «Попутно»). Это же частично отвечает на вопрос [00](00-summary.md#вопросы) «Где боевой конфиг шлюза»: маршруты `/api/v1/im-backend` и `/im` с fallback на `index.html` уже есть.
- **03, «Предположение: агент — коннектор на стороне объекта…; какой у него код… не видно».** После поиска по всем проектам — кода агента нет на ветках по умолчанию (раздел 2). Вопрос остаётся открытым, его нужно адресовать людям, а не коду.
- **03, «Реальное время».** «При нескольких экземплярах понадобится общая шина или лента событий в БД». Уточнение: несколько экземпляров деплой уже допускает (upstream из Consul). Уже сейчас при втором экземпляре расходятся условия правил в памяти и дублируются инциденты. Ленту в БД с `LISTEN/NOTIFY` можно сделать без шины, но с оговоркой о порядке номеров (раздел 1).
