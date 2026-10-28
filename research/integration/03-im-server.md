# Бэкенд МИ: incident-manager-server

- Репозиторий: `NEW/incident-manager-server` (Bitbucket `src.axxonsoft.dev`)
- Ветка: `develop`, коммит `b743797a38daeb3beaa44ef901b26c3ce924290f` («Pull request #55: feat(permissions): add permissions catalog», 2026-10-13)
- Дата изучения: 2026-10-28
- Как читали: локальная копия `../incident-manager-server` на этом коммите (`git log -1` проверен, рабочее дерево чистое); ветки сверены через Bitbucket MCP — `develop` = `b743797`, `db-schema-design` = `f59b55d`, `master` = `f52af7c` (init). Сервер не запускали, тесты не гоняли.

Обозначения: «Вывод:» — наше заключение из фактов; «Предположение:» — кодом не проверено. Ссылки на код ведут на коммит выше; на файлы IM — относительные.

С чем сверяли: контракт операторской части [`openapi.json`](../../Specification/Workflow_machine/openapi.json) (48 операций: 44 + 4 тестового стенда), машина [`workflow_schema.v1.json`](../../Specification/Workflow_machine/workflow_schema.v1.json), памятка [`BACKEND.md`](../../Specification/Workflow_machine/BACKEND.md).

## Коротко

- **Что это.** Go-сервис (Go 1.27.1, gin, PostgreSQL, миграции внутри бинарника). REST по своему OpenAPI 3.0 `api/im/backend.openapi.yaml`, код сервера и клиента генерируется форком `oapi-codegen` AxxonSoft. Базовый путь — `/api/v1/im-backend`, тот же, что в контракте прототипа.
- **Что умеет.** Конфигурационная часть МИ: агенты-источники (вход по HMAC), синхронизация устройств, типов и типов событий, приём событий, правила и условия создания инцидентов, сценарии с версиями, дерево групп устройств, приоритеты, статусы, правила доступа групп пользователей облака. Инциденты создаются фоновым обработчиком событий; для пользователя — только чтение списка, чтение одного и удаление.
- **Чего нет для оператора.** Машины состояний и переходов, таймеров и планировщика, сессии оператора, журнала (таблица есть, код не пишет), исполнителя сценариев, передачи, объединения, потока событий (SSE/WebSocket), `ETag`/`If-Match` у инцидентов, `problem+json`.
- **Облако.** Пользователь входит с JWT облака; сервер не проверяет его сам, а отправляет в облако на `POST /api/v1/auth/introspect-user-token` и получает id, имя, группы пользователей и права. По сервисному каналу без авторизации берёт группы пользователей и карточку пользователя, а при старте регистрирует в облаке свой каталог прав.
- **Арендность — заглушка.** Во всех таблицах есть `customer_guid`, но клиент всегда один, тестовый, зашитый в код (`fakedata`); из токена облака арендатор не берётся.
- **Покрытие контракта операторской части:** полностью — 0 из 48 операций, частично (данные или похожая операция есть, форма другая) — 12, нет — 36. Подробно — в таблице ниже.

## Устройство и запуск

**Язык и зависимости.** Go 1.27.1, модуль `src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server` ([go.mod](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/go.mod?at=b743797a38daeb3beaa44ef901b26c3ce924290f#1)). HTTP — gin; БД — pgx v5 + `mgutz/dat` (query builder); миграции — `rubenv/sql-migrate`; конфигурация — `envconfig`; логи — logrus. Две частные зависимости: `src.axxonsoft.dev/bitbucket/proj/go-util` и форк `oapi-codegen` v0.11.0; модули тянутся через частный прокси `GOPROXY=http://npm.itvgroup.ru:3000` ([Makefile#24](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/Makefile?at=b743797a38daeb3beaa44ef901b26c3ce924290f#24)).

**Слои.**

| Каталог | Что там |
|---|---|
| `cmd/im/main.go` | Точка входа: конфигурация, инфраструктура, сервисы, HTTP-сервер с CORS `*` ([main.go#84](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/cmd/im/main.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#84)) |
| `api/im/backend.openapi.yaml` | Единственный контракт, OpenAPI 3.0.1 |
| `internal/im/handler/v1` | Обработчики HTTP поверх сгенерированного `generated/` (strict-server), промежуточные слои входа ([auth_middleware.go](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/handler/v1/auth_middleware.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#24)); `*_client.go` — обёртки клиента для тестов |
| `internal/im/appservice/*` | Сценарии использования: проверка прав, транзакции, фоновые процессы ([appservice.go#528](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/appservice/appservice.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#528)) |
| `internal/im/service/*` | Бизнес-логика по сущностям и интерфейсы хранилища; `service/storing` — SQL и миграции |
| `internal/im/model` | Доменные модели, права, конфигурация; `model/dbmodel` — DTO таблиц |
| `internal/externalclient/cloud` | HTTP-клиент облака ([client.go](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/externalclient/cloud/client.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#39)) |
| `internal/im/infrastructure` | Хранилище, шина событий в памяти, клиент облака |
| `internal/im/handler/test` | Интеграционные тесты API (нужна живая PostgreSQL) и подменный клиент облака |
| `internal/im/tools` | `env/testing.env`, тестовый веб-интерфейс `test_gui/gui-client.html` (вкладки: правила, инциденты, назначение групп, сценарии, группы устройств), SQL с демо-группами и устройствами |
| `docs/adr` | Один ADR: [001 — дерево групп устройств в памяти](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/docs/adr/001-source-group-inmemory-tree.md?at=b743797a38daeb3beaa44ef901b26c3ce924290f) |

**Хранилище.** PostgreSQL; образ в Makefile и docker-stack — `postgres:9.6` ([Makefile#21](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/Makefile?at=b743797a38daeb3beaa44ef901b26c3ce924290f#21)). Миграции вшиты в бинарник (`go:embed`) и применяются при старте под блокировкой таблицы `im_db_migration_lock`, журнал — `im_db_migrations` ([common.go#90](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/service/storing/common.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#90)). Миграций 13, схема — в разделе «Модель данных».

**Очереди и шины.** Внешних нет. Есть шина в памяти процесса ([eventbus.go](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/infrastructure/eventbus/eventbus.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#1)) с двумя сигналами: дерево групп изменилось, состав групп изменился ([model/eventbus.go](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/model/eventbus.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#1)). В ADR-001 сказано: «NATS/JetStream later behind the same interface». События устройств хранятся в таблице `events` с флагом `processed`; обработчик опрашивает её раз в секунду пачками по 10 ([processor.go#50](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/appservice/incidentrulecondition/processor.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#50)).

**Конфигурация** — переменные окружения с префиксом `IM_` ([config.go](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/model/config.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#3)): `IM_DB_URL` (обязательна), `IM_SERVER_PORT` (5000), `IM_LOG_DIR`, `IM_LOG_LEVEL`, `IM_APP_NAME`, `IM_APP_VERSION`, `IM_AES_ENCRYPTION_KEY` (по умолчанию ключ зашит в код — им шифруются секреты агентов), `IM_CLOUD_URL` и `IM_S2S_CLOUD_URL` (обе обязательны). Переменные можно дать файлом: `-pathToEnv=<файл>` ([configuring/config.go#51](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/util/configuring/config.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#51)).

**Деплой.** `deployments/dockerfiles`: образ-сборщик (golang + golangci-lint), образ сервиса на `alpine:3.5` ([im-backend.Dockerfile](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/deployments/dockerfiles/im-backend.Dockerfile?at=b743797a38daeb3beaa44ef901b26c3ce924290f#1)), docker-stack с PostgreSQL и сервисом на порту 5000 ([im.docker-stack.yml#17](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/deployments/dockerfiles/im.docker-stack.yml?at=b743797a38daeb3beaa44ef901b26c3ce924290f#17)). Сборка и тесты — цели Bamboo (`bs-*` в Makefile). Helm-чартов и манифестов Kubernetes нет. В docker-stack не заданы обязательные `IM_CLOUD_URL` и `IM_S2S_CLOUD_URL` — Вывод: в таком виде сервис не стартует.

> Поправка (второй круг, 2026-10-28): «Helm-чартов и манифестов нет» — верно для репозитория сервера. Деплой есть в `IT/axxoncloud-deploy`: роль `incidentmanager` (образ `im/backend`, сервис Consul `imbackend`, порт 5000), Bamboo `ASIP-IM`; у Bezeq POS1 — не демо-режим. Пароль БД и ключ шифрования лежат там открытым текстом. См. [14, деплой](14-im-backend-operator.md#попутно-деплой-ми-в-облаке-ответ-на-вопрос-итога-о-боевом-шлюзе), [15, п. 1](15-deploy-configurator.md#1-боевой-конфиг-шлюза-где-apiv1monitoring-есть-ли-im-и-apiv1im-backend).

**Локальный запуск** (по коду, сами не запускали):
1. Поднять PostgreSQL, задать `IM_DB_URL`.
2. `IM_CLOUD_URL=demo` включает демо-режим: вместо облака подменный клиент, пользователи 1–4 с разными правами и группами зашиты в `main.go` ([main.go#47](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/cmd/im/main.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#47), [#99](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/cmd/im/main.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#99)). `IM_S2S_CLOUD_URL` всё равно обязателен — любое значение.
3. `go run ./cmd/im -pathToEnv=…` (нужен доступ к частному прокси модулей).
4. Запросы — с `Authorization: Bearer <id пользователя>`: подменный клиент принимает номер пользователя вместо токена ([fake_cloud_client.go#23](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/handler/test/fake_cloud_client.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#23)). Так работает и тестовый интерфейс `gui-client.html`.

Не в демо-режиме сервис при старте регистрирует каталог прав в облаке; облако недоступно — сервис не поднимется ([appservice.go#528](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/appservice/appservice.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#528)).

Тесты: `make test` — интеграционные тесты в `handler/test`, им нужна PostgreSQL по адресу `db:5432` ([testing.env](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/tools/env/testing.env?at=b743797a38daeb3beaa44ef901b26c3ce924290f#1)); в CI её поднимает `make bs-test`. Облако в тестах подменено.

## API

**Транспорт** — только REST/JSON поверх HTTP, gRPC нет. Один контракт [`api/im/backend.openapi.yaml`](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/api/im/backend.openapi.yaml?at=b743797a38daeb3beaa44ef901b26c3ce924290f#1), OpenAPI **3.0.1**, базовый путь `/api/v1/im-backend` ([common.go#5](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/model/common.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#5)).

**Генерация кода** — `make gen` ([Makefile#32](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/Makefile?at=b743797a38daeb3beaa44ef901b26c3ce924290f#32)): форк `src.axxonsoft.dev/bitbucket/proj/oapi-codegen@v0.11.0` с генераторами `custom-gin`, `custom-strict-server`, `spec`, `types`, `client` в `internal/im/handler/v1/generated/`. Схемы безопасности контракта превращаются в вызовы `UserAuthMiddleWare` и `AgentAuthMiddleWare` ([generated/server.go#225](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/handler/v1/generated/server.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#225)).

**Вход** ([securitySchemes](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/api/im/backend.openapi.yaml?at=b743797a38daeb3beaa44ef901b26c3ce924290f#1886)): `User` — заголовок `Authorization: Bearer <JWT>`; `Agent` — HMAC-SHA256 по строке `method\npath\ntimestamp\nbodyHash`, заголовки `X-Access-Key-Id`, `X-Date`, `X-Signature`, расхождение времени до 15 минут ([hmac_signature.go#13](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/util/crypto/hmac_signature.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#13)).

**Ошибки** — `{"key", "description"}` с `application/json` ([apierror/common.go#46](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/util/apierror/common.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#46)), не `application/problem+json`.

**Операции** (65; вход: U — пользователь, A — агент, — без входа):

| Группа | Операции | Вход | Права |
|---|---|---|---|
| События | `POST /events` (событие от агента), `GET /events` | A / U | чтение — `manage` |
| Инциденты | `GET /incidents`, `GET /incidents/{guid}`, `DELETE /incidents/{guid}` | U | список — `incidents.take.any`; один и удаление — `manage` |
| Правила | `/incidents/rules` — CRUD (5) | U | `manage` |
| Условия правил | `/incidents/conditions` — CRUD (5) | U | `manage` |
| Агенты | `POST /agents` (регистрация по одноразовому токену, без входа), `GET/PATCH/DELETE /agents…`, `/agents/tokens` — создать, список, удалить | — / U | `manage` |
| Устройства | `GET /sources`, `GET /sources/{guid}` (с группами и путями), `/sources/types` — список, один, удалить; `/sources/event-types` — список, один, удалить | U | `manage` |
| Синхронизация | `POST /sync/sources/types`, `/sync/sources/event-types`, `/sync/sources` | A | — |
| Сценарии | `/scenarios` — CRUD (5), `GET /scenarios/{guid}/versions`, `GET …/versions/{version}`; изменение — с `If-Match: <число>` ([yaml#980](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/api/im/backend.openapi.yaml?at=b743797a38daeb3beaa44ef901b26c3ce924290f#980)) | U | `manage` |
| Группы устройств | `POST /sources/groups`, `PATCH/DELETE /sources/groups/{guid}`, `GET /sources/groups/tree?parentGroupGuid=` (один уровень), `GET /sources/groups/tree/search?query=`, членство — добавить, убрать, перенести | U | `manage` |
| Приоритеты | `/priorities` — CRUD (5), ключ — `guid` | U | `manage` |
| Статусы | `/statuses` — CRUD (5) | U | `manage` |
| Доступ | `GET /user-groups` (из облака), `GET/POST/DELETE /access-rules`, `PUT /access-rules/{guid}` | U | `manage` |
| Служебное | `GET /heartbeat` | — | — |

Вывод: это API конфигуратора и источников событий, а не операторского места. Пути прототипа (`/operator/…`, `/test/…`) с ним не пересекаются, оба контракта можно держать под одним базовым путём в одном сервисе.

## Авторизация, арендность, связь с облаком

**Чей JWT и как проверяется.** Пользовательский токен — токен облака (портала). Сервер его не разбирает и подпись не проверяет — ни JWKS, ни Keycloak в коде нет. Токен уходит в облако: `POST https://<IM_CLOUD_URL>/api/v1/auth/introspect-user-token?withUserGroups=true` с телом `{"token": …}` ([client.go#90](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/externalclient/cloud/client.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#90)). Ответ: `status`, `accessData.authData.{userId, userName, userGroupIds, permissions[].name}` ([model.go](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/externalclient/cloud/model.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#1)). Результат кэшируется в памяти на 30 секунд по строке токена ([client.go#32](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/externalclient/cloud/client.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#32)). Из прав облака остаются только известные МИ имена ([permission.go#74](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/model/permission.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#74)).

> Поправка (второй круг, 2026-10-28): introspect не проверяет сессию и блокировку и принимает refresh- и share-токены; сервер МИ `tokenType` не смотрит. Отозванный доступ работает не «до 30 с», а до срока токена. См. [12, поправки](12-tenancy-users.md#поправки-к-первому-кругу), [12, п. 5](12-tenancy-users.md#5-безопасность-служебных-api).

**Сервисные вызовы облака** — по `http://<IM_S2S_CLOUD_URL>`, без заголовков авторизации и без указания арендатора:

| Вызов | Зачем | Где |
|---|---|---|
| `GET /ac/v1/user-groups` | все группы пользователей — для правил доступа | [client.go#121](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/externalclient/cloud/client.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#121) |
| `GET /ac/v1/users/{id}?params=name&params=email&params=surname` | имя и почта автора изменений; кэш 5 минут | [client.go#177](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/externalclient/cloud/client.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#177) |
| `PUT /ac/v1/global-permissions/catalog` | при старте — регистрация каталога прав МИ | [client.go#144](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/externalclient/cloud/client.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#144) |

> Поправка (второй круг, 2026-10-28): маршрут есть только на ветке облака `epic/CLOUD-23284-perms-i18n`; с `develop` сервер вне демо-режима не стартует. Сам `PUT …/catalog` в облаке без входа — любой в сети может переписать каталог. См. [10, п. 1](10-permissions.md#1-маршрут-put-acv1global-permissionscatalog-и-сверка-с-сервером-ми), [12, п. 5](12-tenancy-users.md#5-безопасность-служебных-api).

Интерфейс клиента — 4 метода ([infra.go#17](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/model/infra.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#17)). Списка пользователей группы, ролей, прав чужого пользователя, присутствия — нет.

**Мультиарендность.** Таблицы несут `customer_guid` (ссылка на `customers`), а миграция 002 создаёт одного клиента `TestCustomer` ([002#3](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/service/storing/migrations/002_add_initial_data.sql?at=b743797a38daeb3beaa44ef901b26c3ce924290f#3)). Пользователю и агенту клиент назначается из заглушки `fakedata` ([auth_middleware.go#96](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/handler/v1/auth_middleware.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#96), [#56](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/handler/v1/auth_middleware.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#56)). Регистрация агента тоже берёт пользователя из заглушки ([agent.go#71](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/appservice/agent/agent.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#71)). Запросы к инцидентам, сценариям и правилам доступа по `customer_guid` не фильтруют ([incident_queries.go#94](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/service/storing/incident_queries.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#94)). Дерево групп в памяти отдаёт пары «предок—потомок» сразу по всем клиентам ([tree/index.go#216](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/service/sourcegroup/tree/index.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#216)). Понятий «домен» и «организация» облака в коде нет. Вывод: арендность только заложена в схеме; как арендатор облака сопоставляется с `customer_guid`, не решено.

**Пользователи и группы** — только из облака: id пользователя — `int64`, группы — `int64` (`external_user_group_id`). В БД МИ пользователей нет, только их id в полях `*_user_id`.

**Источник инцидентов — агенты, не облако.** Администратор выпускает одноразовые токены регистрации (`POST /agents/tokens`). Агент регистрируется (`POST /agents`) и получает ключ HMAC; секрет хранится зашифрованным AES ([003](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/service/storing/migrations/003_add_agent_api_keys.sql?at=b743797a38daeb3beaa44ef901b26c3ce924290f#3)). Дальше агент синхронизирует типы устройств, типы событий и устройства (`/sync/*`, [sync_source.go#60](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/appservice/sync/sync_source.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#60)) и шлёт события `POST /events` с `sourceUid`, `eventTypeUid` и произвольным `payload` ([event.go#59](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/appservice/event/event.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#59)). Обработчик раз в секунду сверяет новые события с условиями правил в памяти: тип устройства, устройство, тип события, группа с вложенными ([processor.go#113](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/appservice/incidentrulecondition/processor.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#113)). На каждое подошедшее условие создаётся по инциденту на каждый сценарий правила ([incident/service.go#28](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/service/incident/service.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#28)) — об этом же пишет [`BACKEND.md`](../../Specification/Workflow_machine/BACKEND.md), «Что ещё не решено». Ошибки чтения правила, устройства и статуса в обработчике не проверяются ([processor.go#89](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/appservice/incidentrulecondition/processor.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#89)). Вызовов сервисов тревог и устройств облака нет. Предположение: агент — коннектор на стороне объекта (Axxon One и др.); какой у него код и где он живёт, по этому репозиторию не видно.

> Поправка (второй круг, 2026-10-28): дублирует и второе подошедшее условие того же правила; события берутся с конца (LIFO) без `SKIP LOCKED`; отметка «обработано» — вне транзакции; повтор события — 500; после миграции 010 у инцидента нет ссылки на правило. Кода агентов не найдено ни в одном репозитории. См. [14, п. 4](14-im-backend-operator.md#4-один-инцидент-на-событие-и-выбор-одного-сценария-145), [14, п. 2](14-im-backend-operator.md#2-агенты-ми-где-код-и-какие-поля-приходят).

## Права

**Каталог** (коммит «permissions catalog», CLOUD-23650) — 9 прав в пространстве `incident_manager`, с UUID и подписями на английском и русском ([permission_catalog.go#18](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/model/permission_catalog.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#18), [permissions_info.go](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/model/permissions_info.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#1)). При старте сервер отправляет каталог в облако (`PUT /ac/v1/global-permissions/catalog`); облако назначает права и возвращает их по имени в ответе на проверку токена. Вывод: права МИ живут в общей системе прав облака, сам МИ ролей не хранит.

> Поправка (второй круг, 2026-10-28): облако права не назначает: оно хранит каталог, назначает администратор (права → глобальная роль → группа пользователей). Регистрация работает только с облаком ветки прав. См. [10, поправки](10-permissions.md#поправки-к-первому-кругу), [10, п. 5](10-permissions.md#5-глобальные-или-доменные-права-как-назначаются).

| Право сервера | Подпись | Где проверяется в коде | Ближайшее право машины (наше сопоставление) |
|---|---|---|---|
| `incident_manager.manage` | Управление менеджером инцидентов | все операции настройки; `Has()` считает его надмножеством любого права ([permission.go#68](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/model/permission.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#68)) | `incident:schema:admin` (и вся настройка) |
| `incident_manager.incidents.take.own` | Брать в работу | нигде | `incident:claim` |
| `incident_manager.incidents.take.any` | Забирать любую | `GET /incidents` ([incident.go#55](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/appservice/incident/incident.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#55)) | `incident:reassign` |
| `incident_manager.incidents.close` | Закрывать | нигде | `incident:close` |
| `incident_manager.incidents.filter.edit` | Изменять фильтр | нигде | нет (вкладки-фильтры из контракта убраны) |
| `incident_manager.incidents.track` | Отслеживать обработку | нигде | нет |
| `incident_manager.incidents.assign` | Передавать | нигде | `incident:transfer:own` / `incident:transfer:any` |
| `incident_manager.incidents.suspend` | Приостанавливать | нигде | `incident:hold` |
| `incident_manager.incidents.process` | Работать с переданными | нигде | `incident:accept` |

> Поправка (второй круг, 2026-10-28): проверка `take.any` в `GET /incidents` по смыслу ошибка: это право перехвата, оператор без него не увидит очередь. См. [10, п. 7](10-permissions.md#7-get-incidentsguid-только-для-manage).

В машине прав 14, в формате `ресурс:действие[:область]` ([`workflow_schema.v1.json`](../../Specification/Workflow_machine/workflow_schema.v1.json), `permissions`). В каталоге сервера нет аналогов для `incident:release`, `incident:close:unprocessed`, `incident:reopen`, `incident:bulk`, `incident:run_action`, `agent:set_not_ready`, нет и раздельных `transfer:own` и `transfer:any`. У сервера нет пары машине для `filter.edit` и `track`.

Замечание по коду: `GET /incidents/{guid}` требует `manage`, а затем для не-менеджера ветка с фильтром по доступу недостижима ([incident.go#70](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/appservice/incident/incident.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#70)). Вывод: оператор без `manage` открыть карточку не может; похоже на ошибку.

**Доступ к объектам** — правила доступа: группа пользователей облака → устройство, тип устройства, тип события или группа устройств (с вложенными); хотя бы одно поле заполнено ([007](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/service/storing/migrations/007_add_access_rules.sql?at=b743797a38daeb3beaa44ef901b26c3ce924290f#3)). Список инцидентов не-менеджера отбирается SQL-соединением с `access_rules` по группам пользователя ([incident_queries.go#111](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/service/storing/incident_queries.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#111)). Менеджер видит все. Вывод: это близко к «группам доступа» контракта (§5), только ключ — группа пользователей облака, а не роли, и есть ещё фильтры по типу устройства и типу события.

## Модель данных

Схема — [001_initial_scheme.sql](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/service/storing/migrations/001_initial_scheme.sql?at=b743797a38daeb3beaa44ef901b26c3ce924290f#1) и миграции 002–013.

| Что | Таблицы | Состояние |
|---|---|---|
| Арендатор | `customers` | один тестовый |
| Источники | `agents`, `agent_api_keys`, `agent_enrollment_tokens`, `sources` (`uid`, `type_guid`, `agent_guid`, `is_online`), `source_types`, `source_event_types` | используется |
| Группы устройств | `source_groups` (`parent_guid`), `source_group_memberships` (устройство может быть в нескольких группах), `source_group_tree_meta` (версия для CAS) | используется; дерево — в памяти, ADR-001 |
| События | `events` (`raw_data jsonb`, `processed`, ссылки на устройство, тип, тип события) | используется |
| Правила | `incident_rules` (имя, приоритет), `incident_rule_scenarios` (многие-ко-многим со сценариями), `incident_rules_conditions` | используется |
| Сценарии | `scenario_definitions` (guid, автор), `scenarios` (PK `guid+version`, `script jsonb`, `is_archived`, `read_only`), представление `scenarios_actual`; `scenarios_customers` — только таблица, код её не читает | используется. Правка = новая версия, прежняя архивируется ([scenario/service.go#125](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/service/scenario/service.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#125)); формат `script` не проверяется |
| Инциденты | `incidents` ([001#175](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/service/storing/migrations/001_initial_scheme.sql?at=b743797a38daeb3beaa44ef901b26c3ce924290f#175)): `name`, `status_guid`, `priority_guid`, `escalated*`, `assignee_user_id`, `assigned_*`, `event_guid`, `scenario_guid + scenario_version` (FK на версию), `scenario_result jsonb`, мягкое удаление | создаются обработчиком; меняются только удалением |
| Статусы | `statuses` (`code`, `name`, `is_default`); заведены `open`, `in_progress`, `closed` | CRUD есть, к машине не привязаны |
| Приоритеты | `priorities` (`name`, `value bigint`, уникальны в пределах клиента) | CRUD |
| Журнал | `incident_activities` ([001#211](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/service/storing/migrations/001_initial_scheme.sql?at=b743797a38daeb3beaa44ef901b26c3ce924290f#211)): старое и новое значение статуса, приоритета, исполнителя, эскалации | таблица и DTO есть, код в неё не пишет |
| Действия и переходы | `incident_actions` (`code`), `incident_action_transitions` (из статуса → в статус) ([001#243](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/service/storing/migrations/001_initial_scheme.sql?at=b743797a38daeb3beaa44ef901b26c3ce924290f#243)) | только таблицы и DTO, кода нет |
| Доступ | `access_rules`, `access_rule_groups` (кто и когда менял правила группы) | используется |

> Поправка (второй круг, 2026-10-28): у `incidents` нет `incident_rule_guid` — его удалила миграция 010; `statuses.code` уникален глобально, а не по клиенту. См. [14, поправки](14-im-backend-operator.md#поправки-к-первому-кругу).

**Исполнитель машины состояний и сценариев — нет.** Переходов, таймеров, условий, CEL (`cel-go` в зависимостях нет), сессии оператора, нормативов, связей «основной—привязанный», номера инцидента для показа, версии записи — ничего этого в коде нет. Таблица `incident_action_transitions` — набросок «действие переводит из статуса в статус» без условий и эффектов. Вывод: исполнение [`workflow_schema.v1.json`](../../Specification/Workflow_machine/workflow_schema.v1.json) и сценариев по [`BACKEND.md`](../../Specification/Workflow_machine/BACKEND.md) — новая работа. Опереться можно на сценарии с версиями, привязку инцидента к версии сценария и `scenario_result`.

Чего не хватает в `incidents` под машину (по [`BACKEND.md`](../../Specification/Workflow_machine/BACKEND.md)): `number`, состояние машины вместо `status_guid`, `version`, адресат передачи (человек или дежурная группа), таймеры и дедлайны, причины, результат закрытия, `linked_to`, `linked_at`, `left_group`. Нужны и новые таблицы: сессии и состояния операторов, журнал в виде `templateKey + vars`, схемы workflow с версиями, ключи идемпотентности, лента событий для SSE, дежурные группы, связи камер, справочные ссылки.

## Сверка с контрактом операторской части

Контракт — [`openapi.json`](../../Specification/Workflow_machine/openapi.json), пути от `/api/v1/im-backend`. «Частично» — данные или похожая операция есть, но путь, форма, права или поведение другие.

| Операция прототипа | Есть в сервере | Расхождения |
|---|---|---|
| `GET /operator/workflow/active`, `…/schemas` (список, создать, получить, изменить, проверить, опубликовать, симулятор) — 8 | нет | Схем workflow нет совсем |
| `GET /operator/session` | нет | Есть только проверка токена в облаке: id, имя, группы, права. Нет `agentState`, лимитов, `usage`, дежурных групп. Права — `incident_manager.*`, а не `incident:*` |
| `PUT /operator/session/agent-state`, `POST …/heartbeat`, `PATCH …/preferences` | нет | `GET /heartbeat` сервера — проверка живости сервиса, не признак активности оператора |
| `GET /operator/incidents` (очередь) | частично: `GET /incidents` | Без страниц, фильтров, поиска, сортировки. Поля — `guid, name, createdAt, event.guid, scenarioGuid/Version, scenarioResult`; нет `number`, `state`, `ownership`, `owner`, `priority`, `version`, таймеров, `linkedTo`. Право — `take.any` |
| `GET /operator/incidents/counters`, `POST …/selection`, `POST …/filter` | нет | — |
| `GET /operator/incidents/{guid}` (карточка) | частично: `GET /incidents/{guid}` | Только `manage` (см. «Права»); нет `ETag`, `readOnly`, `note`, таймеров, устройства и группы |
| `GET …/{guid}/actions`, `POST …/transitions/{id}`, `POST /operator/incidents/transitions/{id}/bulk` | нет | Нет машины, `If-Match`/`412`/`428`, `idempotencyKey`, `expectedVersions` |
| `GET …/{guid}/scenario` | частично (данные) | У инцидента есть `scenarioGuid/Version` и `scenarioResult`, сценарий версии — `GET /scenarios/{guid}/versions/{v}` (только `manage`). Нет пути, курсора, прогресса, `ahead`, `requiredStepsFilled` |
| `POST …/scenario/answer`, `PUT …/scenario/cursor` | нет | Исполнителя сценариев нет |
| `GET …/{guid}/journal` | нет | Таблица `incident_activities` есть, не заполняется, формат не `templateKey + vars` |
| `GET …/{guid}/media` | нет | Камер и связей камер нет |
| `GET /operator/transfer-targets` | нет | Нет списка пользователей с правами и присутствием, нет дежурных групп |
| `GET /operator/reference/reasons/{catalogId}` | нет | — |
| `GET /operator/reference/event-types` | частично: `GET /sources/event-types` | Типы событий привязаны к типу устройства; нет `id`-кода и `defaultReactionSec`; только `manage` |
| `GET /operator/reference/device-types` | частично: `GET /sources/types` | `uid`/`name` вместо `id`/`label`; только `manage` |
| `GET /operator/reference/source-groups` | частично: `GET /sources/groups/tree`, `…/search` | Сервер отдаёт по одному уровню (`parentGroupGuid`), счётчики — групп и устройств; контракту нужно всё дерево с устройствами и счётчиками открытых инцидентов (`open`, `topPriority`). Только `manage` |
| `GET /operator/reference/help-links` | нет | — |
| `GET /operator/strings` | нет | Каталога строк нет; ошибки — `key` + английское `description` |
| `GET /operator/reference/priorities` | частично: `GET /priorities` | Ключ — `guid`, `value` любое `int64`; в контракте значение 0–100 и есть ключом, плюс цвета и нормативы. Только `manage` |
| `POST /operator/admin/priorities`, `PUT/DELETE …/{value}` | частично: `POST /priorities`, `PATCH/DELETE /priorities/{guid}` | Ключ `guid`, а не `value`; нет события `reference.priorities_changed` |
| `GET /operator/admin/access-groups` | частично: `GET /access-rules` (+ `GET /user-groups`) | Сервер: группа пользователей облака → устройство, тип, тип события, группа устройств. Контракт: группа с `roles` → `sourceGroups` + `devices` |
| `GET /operator/admin/duty-groups` | нет | Основа может быть в группах пользователей облака, но участников группы сервер не получает |
| `GET /operator/admin/camera-links` | нет | — |
| `GET /operator/stream` (SSE) | нет | См. «Реальное время» |
| `POST /operator/incidents/merge`, `GET/DELETE …/{guid}/linked`, `DELETE …/linked/{linkedGuid}` | нет | Связей инцидентов нет |
| `POST /test/incidents` | частично (аналог): `POST /events` + обработчик правил | Вход агента по HMAC, создание асинхронно (до 1 с), по инциденту на сценарий правила; правило без сценария инцидента не создаёт |
| `POST /test/reset`, `POST /test/clock`, `PUT /test/operators/{id}/roles` | нет | Нет эталонного набора, управляемых часов, смены ролей. Демо-режим `IM_CLOUD_URL=demo` — только зашитые пользователи |

**Итого:** полностью — 0 из 48; частично — 12 (`listIncidents`, `getIncident`, `getIncidentScenario`, `listEventTypes`, `listDeviceTypes`, `listSourceGroups`, `listPriorities`, `createPriority`, `updatePriority`, `deletePriority`, `listAccessGroups`, `testCreateIncident`); нет — 36.

Сквозные расхождения:
- **Версия OpenAPI.** Сервер — 3.0.1, генератор на `kin-openapi`; контракт прототипа — 3.1.0 и 77 раз использует `"type": [..., "null"]`. Предположение: форк `oapi-codegen` 3.1 не понимает, понадобится перевод на 3.0 (`nullable`) или другой генератор.

> Поправка (второй круг, 2026-10-28): подтверждено: форк на `kin-openapi v0.117.0`, `Schema.Type` — строка; мест только из 3.1 — 109. См. [14, п. 5](14-im-backend-operator.md#5-openapi-31-против-30-ошибки-cors).

- **Ошибки:** `{key, description}` против `application/problem+json` с `code` из перечня `Problem.code`.
- **Версия записи:** у сценариев `If-Match: <число>`, в контракте — `ETag` в кавычках, `"12"`, и `428`/`412` у инцидентов.
- **CORS** ([main.go#84](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/cmd/im/main.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#84)): нет `If-Match` в `Allow-Headers` и `Access-Control-Expose-Headers: ETag`, `credentials` не разрешены — тестам стенда это нужно ([`BACKEND.md`](../../Specification/Workflow_machine/BACKEND.md), «Тестовый стенд», п. 5).
- **Идентификаторы людей:** сервер — `int64`, контракт — строки внешней системы. Совместимо, если отдавать строкой.
- **Схема входа совпадает по замыслу:** контракт описывает `bearerAuth` как «портальный JWT из `localStorage.accessToken`, как в остальных вызовах im-backend», сервер принимает такой же Bearer. Вопрос потока SSE (браузерный `EventSource` не передаёт `Authorization`) в сервере не решён.

## Реальное время

Нет ничего: ни SSE, ни WebSocket, ни long-polling, ни уведомлений операторам. `gin-contrib/sse` есть в `go.mod` только как косвенная зависимость gin. Внутренняя шина ([eventbus.go](https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/infrastructure/eventbus/eventbus.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#1)) живёт в памяти одного процесса, несёт только сигналы «перечитай дерево групп» и «перечитай состав групп» и при переполнении теряет сообщения (неблокирующая отправка). Для нескольких экземпляров сервиса ADR-001 обещает NATS/JetStream «позже». Вывод: поток `GET /operator/stream` с `Last-Event-ID` (хранить не меньше 500 событий и не меньше 10 минут, `stream.reset`) и планировщик таймеров — новая работа; при нескольких экземплярах понадобится общая шина или лента событий в БД.

> Поправка (второй круг, 2026-10-28): несколько экземпляров деплой уже допускает (upstream из Consul); при втором экземпляре уже сейчас расходятся условия правил в памяти и дублируются инциденты. Ленту можно сделать в PostgreSQL с `LISTEN/NOTIFY`. См. [14, поправки](14-im-backend-operator.md#поправки-к-первому-кругу), [14, п. 1](14-im-backend-operator.md#1-где-делать-операторский-api-машину-сценарии-и-поток-событий).

## Ветка db-schema-design

Через Bitbucket MCP: голова `f59b55d`, ответвлена от `master` `f52af7c` (init); в `develop` не влита. 7 коммитов Asker Shogenov с 2025-11-17 по 2026-01-12, последний — «version 7 (role to user-group for rule assignments)». Кода нет, только проект схемы: `v1/incident-manager-backend.sql`, `v1/cloud-additions.sql`, `v2/incident-manager-backend.sql`, `v2/db-scheme-description.pdf`.

- `v2/incident-manager-backend.sql` — почти та же схема, что миграция 001 в `develop`. Отличие — таблица `incident_action_role_permissions`: внешняя роль → действие над инцидентом, по клиенту, с отзывом. Ещё в ветке id внешних пользователей и групп — UUID, а в `develop` — `bigint`. В PDF это описано как RBAC: «внешние роли — интеграция с внешней IAM», действия вроде resolve, escalate, reassign, переходы статусов по действиям.
- `v1/cloud-additions.sql` — набросок иерархии облака: `domains`, `customers`, `control_centers`, `facilities`, `areas`, `domain_areas`.

Вывод: для операторской части ветка важна только как история замысла. Права «роль → действие» в `develop` заменены каталогом прав облака, а машины состояний там тоже нет. Иерархия «домен — клиент — центр управления — объект — зона» может пригодиться для вопроса арендности и площадок (`site` в контракте) — это вопрос к коллегам по облаку.

## Открытые вопросы

Бэкенду МИ:
1. Где исполнять машину и сценарии: в этом сервисе (Go, `cel-go`) рядом с текущим API под `/operator/…` или отдельным сервисом? Кто ведёт работу?
2. Как оператор получает права `incident:*` машины: расширить каталог `incident_manager.*` до 14 прав машины с переименованием, или вести таблицу соответствия? Что делать с `filter.edit` и `track`, у которых нет пары?
3. `GET /incidents/{guid}` требует `manage` — ошибка или задумано?
4. Одно событие → один инцидент с одним сценарием (§14.5): как выбрать сценарий, если у правила их несколько или событие подошло под несколько правил? Сейчас инцидент создаётся на каждый сценарий.
5. Как сервер переходит на OpenAPI 3.1 контракта или контракт — на 3.0? Ошибки — `problem+json`?
6. Статусы `open / in_progress / closed` и таблицы `incident_actions` / `incident_action_transitions` — убрать в пользу состояний машины или сопоставить с ними?
7. Тестовый стенд (`/test/*`, управляемые часы) — готовы ли сделать отдельной сборкой?

Облаку (`axxoncloudgo`, `axxoncloud-ui`) — записываем, не исследовали:
8. Что возвращает `introspect-user-token`, кроме id, групп и прав: есть ли арендатор, домен или организация? Как сопоставить их с `customer_guid`?
9. Есть ли сервисные вызовы: участники группы пользователей, права и группы любого пользователя, список пользователей? Без них нет адресатов передачи и дежурных групп (§5, §8.1, §15).
10. Как защищены вызовы `/ac/v1/*`: сейчас это `http` без авторизации и без арендатора. Что видит МИ при нескольких арендаторах?
11. «Роли» в правилах (§5, группы доступа и дежурные группы по ролям) — это группы пользователей облака или отдельные роли облака?
12. События устройств: только через агентов МИ (`POST /events`) или облако тоже должно создавать инциденты? Где код агента?
13. Присутствие оператора (на месте, перерыв) — ведёт МИ или в облаке уже есть свой статус?
14. Как проходит вход для SSE в облаке: cookie сессии портала, токен в адресе или шлюз?
15. Иерархия из `cloud-additions.sql` (домен, клиент, центр управления, объект, зона) — есть ли она в облаке сейчас, и это ли «площадка» (`site`) в карточке инцидента?

> Поправка (второй круг, 2026-10-28): ответы: 1 — [14, п. 1](14-im-backend-operator.md#1-где-делать-операторский-api-машину-сценарии-и-поток-событий); 2 — [10, п. 6](10-permissions.md#6-соответствие-14-прав-машины); 3 — [10, п. 7](10-permissions.md#7-get-incidentsguid-только-для-manage); 4 — [14, п. 4](14-im-backend-operator.md#4-один-инцидент-на-событие-и-выбор-одного-сценария-145); 5 — [14, п. 5](14-im-backend-operator.md#5-openapi-31-против-30-ошибки-cors); 6, 7 — [14, п. 6](14-im-backend-operator.md#6-статусы-и-incident_actions-против-машины-тестовый-стенд); 8–11, 13, 15 — [12, п. 1](12-tenancy-users.md#1-что-считать-арендатором-ми), [12, п. 2](12-tenancy-users.md#2-служебные-api-для-адресатов-передачи-и-дежурных-групп), [12, п. 4](12-tenancy-users.md#4-роли-в-группах-доступа-и-дежурных-группах), [12, п. 5](12-tenancy-users.md#5-безопасность-служебных-api); 12 — код агента не найден, [14, п. 2](14-im-backend-operator.md#2-агенты-ми-где-код-и-какие-поля-приходят); 14 — вход в поток: `fetch` + `Authorization`, [11, п. 4](11-auth-session.md#4-вход-в-поток-событий-sse).
