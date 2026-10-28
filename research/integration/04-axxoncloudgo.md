# Бэкенд облака: axxoncloudgo

- Репозиторий: `PROJ/axxoncloudgo` (Bitbucket `src.axxonsoft.dev`)
- Ветка: `develop`, коммит `0228c7a9b1acf8faa62aa1097d6ec085882e8cf3`
- Дата изучения: 2026-10-28
- Как читали: только Bitbucket MCP, без клонирования. Поиск Bitbucket ищет по ветке по умолчанию (`master`), поэтому всё найденное перепроверено чтением на коммите выше.

Обозначения: «Вывод:» — наше заключение из фактов; «Предположение:» — не проверено кодом.

Ссылки на код ведут на файлы этого коммита (`?at=0228c7a…`), якорь `#N` — номер строки.

## Коротко

- Облако — набор Go-сервисов в одном репозитории: `backend` (главный API), `arpserver` (туннель к VMS), `configsync` (копия конфигурации VMS: камеры, группы, раскладки), `monitoring`, `jobrunner`, `vsaasmanager`, `vmsmanager`, `uploader`. Шина — NATS (Streaming и JetStream), БД — PostgreSQL, кэш и обнаружение сервисов — Redis (или Consul). Вход — haproxy → nginx с маршрутами по префиксу пути.
- **Слов `incident`/`incident-manager`/`im` в деплое (compose, k8s, nginx) нет.** Единственный след МИ в коде — пространство прав `incident_manager` и действия `take/close/track/assign/suspend/process` в каталоге прав ([permissions.go](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/model/permissions/permissions.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#53)).

> Поправка (второй круг, 2026-10-28): в `axxoncloudgo` так. Боевой деплой — `IT/axxoncloud-deploy` (Ansible + consul-template, там же Helm в `IT/k3s-test`); у Bezeq есть роль `incidentmanager`, `/api/v1/im-backend` и `/im`. См. [15, поправки](15-deploy-configurator.md#поправки-к-первому-кругу), [13, поправки](13-cloud-ui-menu-video.md#поправки-к-первому-кругу), [11, поправки](11-auth-session.md#поправки-к-первому-кругу).

- Токены выпускает сам `backend` (HS256, общий секрет, без JWKS). Другие сервисы проверяют токен вызовом `POST /api/v1/auth/introspect` или `/api/v1/auth/introspect-user-token` — так делают `arpserver`, `arpgateway` и (через свой `AuthService`) `monitoring`. Keycloak — только в отдельной ветке.
- Права: глобальные (роль → группа пользователей) и доменные (роль → политика «узел пользователей × узел доменов»). Внешний сервис может зарегистрировать **свои глобальные права** через `POST /ac/v1/global-permissions`.

> Поправка (второй круг, 2026-10-28): на ветке прав штатный путь регистрации — `PUT /ac/v1/global-permissions/catalog` с деревом. См. [10, поправки](10-permissions.md#поправки-к-первому-кругу).

- Тревоги VMS облако превращает в push/SMS (`backend` + `jobrunner`). Источник инцидентов МИ — не они, а агенты МИ (`POST /events` бэкенда МИ, см. [03-im-server.md](03-im-server.md)).
- Видео и события VMS в браузере — через прокси `arpserver`: `/arpserver/<домен>_<n>/webclient/...` с облачным токеном в `authToken`. Своего WebSocket/SSE для уведомлений браузеру в облаке нет.

> Поправка (второй круг, 2026-10-28): адрес `/arpserver/…` — локальный стенд; в бою префикс — имя хоста arpserver из Consul, адрес брать из `domain.webClientURL`. В nginx Bezeq есть WebSocket `/api/v1/notifier/connect` — что это, неизвестно. См. [13, поправки](13-cloud-ui-menu-video.md#поправки-к-первому-кругу).

- Готовый образец «сервиса рядом с облаком» — `monitoring`: свой API `/api/v1/monitoring`, авторизация через introspect, права `monitoring.view/edit`, S2S-API `/s2s/v1/monitoring`.

## Сервисы и шлюз

Источник — локальный стек [tools/compose/anticonsul-ac.docker-stack.yml](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/tools/compose/anticonsul-ac.docker-stack.yml?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3), шлюз — [tools/docker/nginx.anticonsul.conf](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/tools/docker/nginx.anticonsul.conf?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3) и [haproxy.anticonsul.cfg](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/tools/docker/haproxy.anticonsul.cfg?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3). Боевых Helm-чартов в репозитории нет: в [tools/k8s](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/tools/k8s/README.md?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3) лежат манифесты для minikube (backend, arpserver, configsync, nginx, haproxy, postgres, queue, redis).

| Сервис | Назначение | Транспорт | Хранилище |
|---|---|---|---|
| `backend` ([main/axxoncloudgo](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/main/axxoncloudgo/main.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3)) | главный API: пользователи, группы, роли, домены, сайты, устройства, токены, уведомления | HTTP :8000 (`/api/v1`, `/api/v3/ac-backend`, `/an/api`, S2S `/ac/v1`) | PostgreSQL `db`, Redis, NATS |
| `arpserver` ([axxonrp/server](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/axxonrp/server/auth_checker.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3)) | держит TCP-туннели от `arpagent` на серверах VMS и проксирует к ним HTTP, WebSocket, RTSP, gRPC | :8080 (TCP агентов), :8888 (HTTP), :8890 (gRPC) | в памяти, NATS |
| `configsync` ([configsync](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/configsync/api/configsync.swagger.yaml?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3)) | копия конфигурации VMS в облаке: камеры (с координатами), группы, детекторы, архивы, раскладки | HTTP :9006, `/api/v1/configsync` | своя БД (не уточнял) |
| `monitoring` ([monitoring](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/monitoring/handlers/common.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3)) | метрики доменов и облака, правила оповещений, статусы VMS | HTTP :9007, `/api/v1/monitoring`, S2S `/s2s/v1/monitoring` | PostgreSQL `monitoring-db`, Prometheus/vmalert |
| `jobrunner` ([main/jobrunner](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/main/jobrunner?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3)) | рассылка e-mail, SMS, push; фоновые задачи | NATS | — |
| `vsaasmanager`, `vmsmanager` | управление VMS-контейнерами (managed-домены) | HTTP, NATS (`vsaasmanager.container.status`, `vmsmanager.task`) | — |
| `uploader` | загрузка файлов | HTTP `/api/v1/uploader` | файлы |
| `mediaserver` (mediamtx 1.8.2) | приём потоков RTSP/RTMP по ключам `/streaming` | RTSP :554, RTMP :1935 | — |
| `queue` (nats-streaming 0.14), `jetstream` (nats 2.10) | шина событий | NATS :4222 / :4223 | файлы |
| `redis`, `db` (postgres 9.6), `prometheus` | кэш/обнаружение, основная БД, метрики | — | — |

**Шлюз.**

- `haproxy` слушает 80/443. На 443 смотрит первые байты: если это `HelloFromArpAgent` — TCP-соединение агента VMS уходит в `arpserver:8080`, остальное — в nginx ([haproxy.anticonsul.cfg](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/tools/docker/haproxy.anticonsul.cfg?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#33)).
- `nginx` раздаёт статику фронтенда (`/`, `/pos-ui/`) и проксирует по префиксу: `/api/` и `/api/v3/ac-backend/` → `backend:8000`; `/api/v1/configsync/` → `configsync:9006`; `/api/v1/uploader` → `uploader`; `/arpserver/...` → `arpserver:8888` (вкл. WebSocket `.../ws`, `.../events`, `.../webclient/ws`, `.../webclient/events`, `.../rtspproxy`); `/axxonsoft.bl.*` → gRPC `arpserver:8890` ([nginx.anticonsul.conf](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/tools/docker/nginx.anticonsul.conf?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#172), [#304](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/tools/docker/nginx.anticonsul.conf?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#304)). В конце — `include servers/*;`: сюда можно положить дополнительные server-блоки.
- Маршрута для `/api/v1/monitoring` в nginx этого репозитория нет. Предположение: боевые конфиги шлюза лежат в другом репозитории (деплой).

> Поправка (второй круг, 2026-10-28): подтверждено: боевые конфиги — `IT/axxoncloud-deploy`, nginx на каждого заказчика; там же `/api/v1/monitoring`. Номера строк на `0228c7a`: `location /` — 276, `location /api/` — 172. См. [15, п. 1](15-deploy-configurator.md#1-боевой-конфиг-шлюза-где-apiv1monitoring-есть-ли-im-и-apiv1im-backend), [15, поправки](15-deploy-configurator.md#поправки-к-первому-кругу), [12, поправки](12-tenancy-users.md#поправки-к-первому-кругу).

**Обнаружение сервисов.** `backend` при старте регистрируется под именем `axxoncloud` с адресом WAN и HTTP-проверкой `/ac/v1/heartbeat/backend`: в Consul, если задан `ConsulAddress`, иначе — в Redis с TTL ([main.go](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/main/axxoncloudgo/main.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#122)).

**Варианты поставки.** Облако (docker swarm / k8s) и on-premises установщик для Windows/Linux: собирается в один пакет с nginx и UI ([installer.mk](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/installer.mk?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#1)).

## Как подключается внешний сервис (МИ)

Отдельного механизма «регистрации внешнего сервиса» (каталог приложений, манифест, ключ клиента) в `develop` нет — не найдено, искал: `incident`, `webhook`, маршруты nginx, `servicediscovery`, S2S-маршруты. По факту внешний сервис подключается так же, как `monitoring`:

1. **Сеть и маршрут.** Сервис запускается в той же сети, что `backend`; в nginx добавляется `location /api/v1/<сервис>/ → <сервис>:<порт>` (есть `include servers/*`).
2. **Авторизация пользователя.** Фронтенд шлёт облачный access-токен; сервис проверяет его вызовом `POST /api/v1/auth/introspect-user-token?withUserGroups=true` и получает `userId`, группы и глобальные права. Готовый клиент — `BackendClient.AuthUser` в [handler/rest/client/backend_client.go](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/handler/rest/client/backend_client.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3) (там же `GetDomainsWithPermissions` → `/ac/v1/users/domains/permissions`); тем же вызовом пользуется `arpgateway`. `monitoring` кэширует результат проверки на 30 секунд ([monitoring/handlers/common.go](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/monitoring/handlers/common.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#93)) и проверяет `monitoring.view` / `monitoring.edit` ([monitoring/model/auth.go](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/monitoring/model/auth.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#18)).
3. **Свои права.** При старте — `POST /ac/v1/global-permissions` с правами `incident_manager.*` (см. «Права и ACL»).

> Поправка (второй круг, 2026-10-28): на ветке прав штатный путь — `PUT …/catalog` с деревом (так и делает сервер МИ); `POST` там принимает и расширенное тело. См. [10, поправки](10-permissions.md#поправки-к-первому-кругу).

4. **Данные облака.** Через S2S `/ac/v1/...` (пользователи, группы, домены, права по доменам) и `configsync` `/api/v1/configsync/internal/...` (камеры, группы камер).
5. **События.** Подписка на NATS (см. «Устройства, видео, события»).
6. **Регистрация в обнаружении сервисов** — по желанию: Consul или Redis, как `backend`.

Вывод: для МИ путь «как monitoring» реален без изменений в облаке, кроме маршрута в nginx и решения, кто регистрирует права. Предположение: `NEW/incident-manager-server` уже делает часть этого — сверить с [03-im-server.md](03-im-server.md).

## Авторизация

**Кто выпускает токены.** Сам backend облака (сервис `backend`, пакет `service/auth`). Keycloak в `develop` нет: работа над ним идёт в отдельной ветке `feature/CLOUD-22056-epic-keycloak` (последние коммиты «CLOUD-23390 oidc keycloak», «CLOUD-23391 2 part sso keycloak»), в наш снимок она не влита.

Вход пользователя — `POST /api/v3/ac-backend/users/login` (и `/users/login/v2`), а также Azure (OAuth и SAML), Google, Apple, Facebook, VK, Okta, Сбер, Doma.ai; плюс одноразовые коды (OTP, TOTP) через `/auth-flow/*` ([server.go](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/handler/v3/boilerplate/server.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#762), [auth_service.go](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/service/auth/auth_service.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#167)).

**Подпись.** HS256, общий секрет. Секретов пять — отдельно для access, refresh, domain (токен VMS), share и device ([auth_service.go](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/service/auth/auth_service.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#68), [#201](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/service/auth/auth_service.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#201), [#406](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/service/auth/auth_service.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#406)). Открытых ключей (JWKS) нет: проверить подпись может только тот, кто знает секрет. `Issuer` = `"Cloud"`.

**Сроки.** Access — короткий («сейчас 15 минут»), refresh — длинный («сейчас 2 недели»); точные значения задаются настройками `AccessTokenTTL`, `RefreshTokenTTL` ([model/auth/auth.go](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/model/auth/auth.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#64), [auth_service.go](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/service/auth/auth_service.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#119)). Обновление: `POST /api/v1/auth/tokens` или `POST /api/v3/ac-backend/auth/tokens`, в заголовке `Authorization` — refresh-токен; ответ — новая пара access + refresh ([handler/rest/auth.go](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/handler/rest/auth.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#653), [init.go](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/handler/rest/init.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#106)). На частое обновление стоит ограничитель (Redis).

> Поправка (второй круг, 2026-10-28): умолчание — `P1D`/`P1M`, комментарий устарел; значения по установке (`axxoncloud/prod` — сутки, `selectel2/prod` — 15 минут). Ограничитель в Redis считает только неудачные обновления по IP: 5000 за окно, блок на 5 минут. Refresh одноразовый. См. [11, поправки](11-auth-session.md#поправки-к-первому-кругу), [11, п. 1](11-auth-session.md#1-refresh-токен-одноразовый-или-нет-где-хранится-гонка-сроки).

**Состав claims (структура `AxxonCloudClaims`).** У пользовательского токена: `UserID`, `UserName`, `ClientID`, `ClientType` (web/mobile/desktop), `Version` = `v2`, `Type` (access/refresh), `CreatedAt`, а также `exp`, `iat`, `iss` ([auth_service.go](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/service/auth/auth_service.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#264)). Домена (организации), ролей и прав в самом токене нет.

**Сессия в БД.** В собственных обработчиках backend токен считается действующим, только если жива сессия пользователя: при проверке backend смотрит таблицу сессий (`CheckSessionIsActive`) и что пользователь не заблокирован ([auth_service.go](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/service/auth/auth_service.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#421), [handler/v3/common.go](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/handler/v3/common.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#204)). Вывод: проверить токен «у себя» по подписи недостаточно — выход пользователя и блокировка видны только через backend.

> Поправка (второй круг, 2026-10-28): оба introspect-маршрута, которыми пользуются МИ и `monitoring`, сессию и блокировку не проверяют. См. [12, поправки](12-tenancy-users.md#поправки-к-первому-кругу).

**Как другие сервисы проверяют токен.** Через вызов backend — других способов в коде нет:

- `POST /api/v1/auth/introspect` `{token}` → `resultObject: {active, UserID, UserName, DomainID, permissions[], OrganizationID, OrganizationName, TokenType}` ([handler/rest/auth.go](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/handler/rest/auth.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#686), [model/auth_token_response.go](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/model/auth_token_response.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#11)). Принимает и токен пользователя, и токен домена (VMS).
- `POST /api/v1/auth/introspect-user-token?withUserGroups=true` `{token}` → `{status, tokenType, accessData.authData: {userId, userName, userGroupIds[], permissions[]}}` ([handler/rest/auth.go](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/handler/rest/auth.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#731), [model/auth/auth.go](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/model/auth/auth.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#33)). Этот вариант отдаёт группы и глобальные права — Предположение: его и использует бэкенд МИ (проверить в `03-im-server.md`).
- Так же устроены свои сервисы облака: arpserver вызывает introspect через `BackendClient.GetClaimsAndVerifyAuthToken` ([handler/rest/client/backend_client.go](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/handler/rest/client/backend_client.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3)).

Оба introspect-адреса лежат под `/api/`, то есть доступны и снаружи через nginx; ограничения по сети или по ключу сервиса нет.

**Свой OAuth-сервер (новое).** В `develop` есть сервер авторизации OAuth 2.1: `/.well-known/oauth-authorization-server`, `/oauth/authorize`, `/oauth/token`, регистрация клиентов `/oauth/register` (RFC 7591). Включается настройкой `AXXONCLOUD_OAUTH_AS_ENABLED` ([handler/oauth/handler.go](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/handler/oauth/handler.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#41), [handler/cloud/api.go](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/handler/cloud/api.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#102)). В конфиге nginx маршрутов `/oauth` и `/.well-known` нет. Вывод: для МИ это пока не готовый путь, но может стать стандартным входом для внешних приложений.

**Другие виды токенов.** Domain token (для VMS, без срока, `Issuer: Cloud`), device token, share token (для просмотра без регистрации), JWS для входа в VMS домена, подписанный закрытым ключом домена ([auth_service.go](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/service/auth/auth_service.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#284)).


## Арендность, пользователи, группы

**Отдельной сущности «организация/арендатор» в облаке нет.** Её роль играет пользователь-владелец: у домена есть `create_user_id`, а при introspect токена домена `OrganizationID` = id владельца домена, `OrganizationName` = имя домена; для токена пользователя `OrganizationID` = id самого пользователя ([model/domain_model.go](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/model/domain_model.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#65), [service/auth/auth_service.go](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/service/auth/auth_service.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3)). Вывод: «организация» в ответе introspect — условность, на неё нельзя опираться как на арендатора.

**Домен** — одна установка VMS, подключённая к облаку. Типы: `vms/on-site`, `vms/on-site-managed`, `vms/managed`, `vms/intellect` (ПСИМ «Интеллект»), `device/tunnel` (камера напрямую). Поля: имя, владелец, версия VMS, лицензия, регион, кластер, **координаты** (`coordinates`, точка), `vms_uid` ([model/domain_model.go](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/model/domain_model.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#22)).

**Сайт (контейнер)** — узел VMS, развёрнутый облаком в managed-домене; у него статусы жизненного цикла и список устройств (камера, NVR, мост) ([model/site_model.go](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/model/site_model.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#13)). API: `GET/POST /domains/{id}/sites`, `PATCH/DELETE /sites/{id}`.

**Три дерева (материализованный путь `path`)** ([model/domain-roles/tree_roles.go](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/model/domain-roles/tree_roles.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#27)):

| Дерево | Узлы | API (`/api/v3/ac-backend`) |
|---|---|---|
| пользователей `tree_users` | пользователь, группа, LDAP | `GET/POST /trees/users`, `PATCH/DELETE /trees/users/{id}`, `/trees/users/move` |
| доменов `tree_domains` | группа доменов, домен | `/domain-scope/trees/domains`, `/cloud-scope/trees/domains`, `/trees/domains/{id}` |
| ролей `tree_roles` | доменная роль: права облака + права VMS (`vms_role_name`, `vms_permissions`) | `/roles/domain`, `/trees/roles/{domainNodeId}` |

**Пользователь.** Почта, ФИО, телефон, блокировка, LDAP-логин; входит в **группы пользователей** ([model/user_group.go](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/model/user_group.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#14)). Группа хранит: одну **глобальную роль** (`global_role_id`), лимиты сессий по типу клиента, тайм-аут неактивности, включение OTP/TOTP; есть группа по умолчанию и группа поддержки. API: `/users`, `/users/{id}`, `/me`, `/user-groups`, `/user-groups/{id}`, `/user-groups/users` (добавить/убрать), `/roles/global/assign`.

**Для сервисов (S2S, без авторизации, только внутренняя сеть)** ([handler/s2s/init.go](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/handler/s2s/init.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#31), [model/urls.go](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/model/urls.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#502)):

- `GET /ac/v1/users/:userId` — данные пользователя; `GET /ac/v1/axxondata/users` — несколько пользователей;

> Поправка (второй круг, 2026-10-28): `/axxondata/users` — постраничный список **всех** пользователей с именами групп и `isOnline`; `/user-groups` исключает группы LDAP. В списке не хватает `GET /ac/v1/shared/token/:userId` (share-токен на любого пользователя без проверки), `PUT …/catalog` (ветка прав), `DELETE` пользователя и домена VSaaS. См. [12, поправки](12-tenancy-users.md#поправки-к-первому-кругу), [12, п. 2](12-tenancy-users.md#2-служебные-api-для-адресатов-передачи-и-дежурных-групп).

- `GET /ac/v1/user-groups` — группы;
- `GET /ac/v1/users/domains/permissions` — права пользователя по доменам;
- `GET /ac/v1/domains`, `/ac/v1/domains/:domainId` — базовые данные доменов; `GET /ac/v1/axxondata/domains` — домены пользователя;
- `GET /ac/v1/arp/domains/:domainId` — данные домена с токеном для входа в VMS (по access- или share-токену пользователя).

Вывод: для МИ есть всё, чтобы получить список операторов и групп и их доступ к доменам, но только как внутреннему сервису в той же сети, что `backend:8000` (nginx адрес `/ac/` наружу не пропускает — в [nginx.anticonsul.conf](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/tools/docker/nginx.anticonsul.conf?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#172) есть только `/api/`, `/api/v3/ac-backend/`, `/an/api/`, `/domain/`, `/jp1/`, `/jp2/`).

> Поправка (второй круг, 2026-10-28): «nginx `/ac/` наружу не пропускает» верно для локального стека и ansible-выкладки; on-prem (`nginx.ssl.conf`, `windows/nginx.conf`) и k8s-конфиг `cluster` проксируют `/ac/`, а порты `:8000`/`:9006` в бою закрыты только iptables. См. [12, п. 5](12-tenancy-users.md#5-безопасность-служебных-api).

## Права и ACL

**Два уровня прав.**

1. **Глобальные права** (на всё облако) — собраны в **глобальные роли**, роль назначается **группе пользователей** (не пользователю). Проверка — `globalPermsBLService.CheckPerm(user, имя_права)` ([appservices/globalroles/global_roles.go](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/appservices/globalroles/global_roles.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#100)).
2. **Доменные права** (на домен и его поддерево) — собраны в **доменные роли**; выдаются **политикой** `Policy {узел пользователей, узел доменов, роль, from_time, to_time}`. Политика действует на всё поддерево пользователей и поддерево доменов; бывает временной (например, доступ поддержки, `POST /policies/support`) ([tree_roles.go](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/model/domain-roles/tree_roles.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#127)). API: `/policies`, `/policies/bulk`, `/roles/domain`, `/roles/domain/permissions`.

**Формат имён прав** — `<пространство>[.<ресурс>…].<действие>[.own|.any]`, нижний регистр ([model/permissions/methods.go](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/model/permissions/methods.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#15)). Пространства: `core`, `domains`, `axxon_data`, `monitoring`, `sip`, `update_server`, **`incident_manager`**, `classifier`. Действия, среди прочих: **`take`, `close`, `track`, `assign`, `suspend`, `process`** ([model/permissions/permissions.go](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/model/permissions/permissions.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#47)). Вывод: пространство и глагольный набор под МИ (взять, закрыть, отслеживать, назначить, приостановить, обработать) уже заложены в облако, но ни одного права `incident_manager.*` статически в коде нет.

**Свой каталог прав сервиса — есть механизм.** `POST /ac/v1/global-permissions` с телом `[{uuid, name, description}]` создаёт глобальные права в БД ([handler/s2s/init.go](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/handler/s2s/init.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#64), [handler/rest/auth.go](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/handler/rest/auth.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#773), [appservices/globalroles/global_roles.go](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/appservices/globalroles/global_roles.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#307)). Проверки: uuid обязателен, имя проходит формат, пространство — из известного списка, кроме `domains` ([methods.go](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/model/permissions/methods.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#131)). Значит, сервис МИ может при старте зарегистрировать, например, `incident_manager.incidents.take`; администратор включает их в глобальную роль; МИ видит их в `permissions[]` ответа introspect. Доменные права так добавить нельзя — только глобальные.

> Поправка (второй круг, 2026-10-28): верно для `develop`; на ветке `epic/CLOUD-23284-perms-i18n` есть `PUT …/catalog` с деревом. См. [10, п. 1](10-permissions.md#1-маршрут-put-acv1global-permissionscatalog-и-сверка-с-сервером-ми).

**Возможности (capabilities).** Список прав переводится в дерево `пространство → ресурс → действия (+ области own/any)` для фронтенда ([model/permissions/capabilities.go](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/model/permissions/capabilities.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#31)); узлы дерева доменов приходят с `UserCapabilities`.

**Доступ к объектам (камерам, сайтам).** В облаке он задан на уровне **домена/узла дерева доменов**: доменная роль даёт, например, `domains.domain.cameras.view`, `domains.domain.webclient.use`, `domains.domain.sites.view` ([permissions.go](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/model/permissions/permissions.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#165)). Права на отдельные камеры внутри домена облако не хранит — их несёт VMS-роль (`vms_role_name`, `vms_permissions`), которую облако синхронизирует в VMS (`PUT /sync/security`). Вывод: «может ли оператор видеть камеру X» облако отвечает только с точностью до домена; точнее — только VMS.

**Ветки вне `develop`** (не изучались, только названия): `feature/CLOUD-23281-epic-acl`, `CLOUD-23501-doma.ai-object_acl-4-part` (объектные ACL), `epic/CLOUD-23284-perms-i18n` (переводы названий прав), `CLOUD-23620-fix-perm-check`, `CLOUD-23235-permisions-for-cameras-map-and-domains-map`. Предположение: object ACL могут дать права на отдельные объекты — то, чего МИ не хватает для камер.

> Поправка (второй круг, 2026-10-28): `epic/CLOUD-23284-perms-i18n` — не только переводы: каталог прав с группами, порядком, `i18n`, скрытыми и устаревшими правами и S2S-регистрацией каталога. Webhook-ветка — без типов событий и отправителей; Keycloak — только ещё один вход. См. [10, поправки](10-permissions.md#поправки-к-первому-кругу), [12, п. 3](12-tenancy-users.md#3-события-об-изменениях), [11, п. 5](11-auth-session.md#5-keycloak).


## Устройства, видео, события

**Где живут камеры.**

- Камеры VMS остаются в VMS. Облако хранит их **копию** в `configsync`: камера (`displayId`, `vmsUid`, `accessPoint`, узел, производитель/модель, `displayName`, **`geoLatitude`, `geoLongitude`, `geoAzimuth`**, IP, детекторы, группы), группы камер, детекторы, архивы, раскладки пользователя ([configsync.swagger.yaml](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/configsync/api/configsync.swagger.yaml?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#160)). Копию обновляет `arpagent` (`/sync`, `/unitsync`, `/groupsync` по токену домена); при изменении — событие `cloud.domain.cameras.config.changed`.
- API `configsync` (`/api/v1/configsync`): для пользователя — `GET /cameras` («камеры с геопозицией», `coords`, `previewUrl`), `GET /groups`, `/layouts`; для сервисов — `GET /internal/cameras?domainIds=…&include=groups,detectors`, `/internal/cameras/uid`, `/internal/cameras/groups`, `/internal/objects`, `/internal/groupNames`. У `/internal/*` в спецификации нет `security`, а nginx проксирует весь `/api/v1/configsync/` наружу — открытый вопрос.

> Поправка (второй круг, 2026-10-28): `/internal/*` в боевой ansible-выкладке закрыт 403 (кроме `stage4`); открыт в on-prem и helm 2023 г. См. [12, п. 5](12-tenancy-users.md#5-безопасность-служебных-api).

- Отдельно `backend` хранит **туннельные устройства** (камера напрямую через `arpagent` в прошивке, тип домена `device/tunnel`) и устройства сайтов managed-доменов: `/videoDevices`, `/cloud-scope/videoDevices`, `/containerVideoDevices` ([model/device_model.go](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/model/device_model.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#36)).

**Видео в браузере — через туннель `arpserver`.**

- Схема: браузер → nginx → `arpserver` → TCP-туннель → `arpagent` на сервере VMS → веб-сервер VMS. Адрес: `https://<облако>/arpserver/<domainId>_<номер агента>/webclient/<запрос к веб-API VMS>?authToken=<облачный access-токен>` ([docs/arp/arp.md](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/docs/arp/arp.md?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#99)).

> Поправка (второй круг, 2026-10-28): в бою префикс — имя хоста arpserver из Consul; адрес брать из `domain.webClientURL`. См. [13, поправки](13-cloud-ui-menu-video.md#поправки-к-первому-кругу).

- Токен берётся из `authToken`, `X-Cloud-Auth` или `Authorization` ([auth_checker.go](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/axxonrp/server/auth_checker.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#73)). `arpserver` спрашивает `backend` о доступе пользователя к домену (кэш до 4 часов), проверяет доменные права по пути (например, `webclient` → `domains.domain.webclient.use`) и подставляет учётные данные VMS — пользователь VMS-логин не вводит ([auth_checker.go](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/axxonrp/server/auth_checker.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#121)).

> Поправка (второй круг, 2026-10-28): ключ кэша включает `md5(token)`, а JWT разбирается без проверки подписи. См. [11, п. 4б](11-auth-session.md#б-токен-в-адресе-как-у-arpserver).

- Значит, живое видео, архив, кадры и события VMS доступны тем же веб-API, что у Web-клиента VMS, но через облачный префикс. WebSocket VMS (`.../webclient/ws`, `.../events`) nginx тоже пропускает; есть `rtspproxy` и gRPC-прокси к NativeBL VMS (`/axxonsoft.bl.*`, право `domains.domain.nativebl.use`).
- Ссылка на Web-клиент домена: `GET /api/v3/ac-backend/public/domains/{domainId}/webclienturl`; адреса агентов: S2S `GET /ac/v1/arp/domainsArpAddr`, `/ac/v1/arp/domains/:domainId`.
- Отдельного API «дай ссылку на поток камеры X» (HLS/WebRTC) в облаке нет — не найдено, искал: `stream`, `hls`, `webrtc` в списке маршрутов v3 ([server.go](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/handler/v3/boilerplate/server.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#19)). `/streaming` в облаке — это **приём** потоков в `mediamtx` по ключам, не выдача видео VMS.

**События и тревоги.**

- Тревоги VMS: `backend` получает их из шины NATS и рассылает push (FCM/APNS) и SMS через `jobrunner` ([service/queue/queue.go](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/service/queue/queue.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#221), [docs/jobrunner/sms.md](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/docs/jobrunner/sms.md?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#15)). Для МИ это не источник инцидентов. Имена тем — в общей библиотеке `PROJ/go-util`, `queue/model/queue-names.go` (там же `ad.cloud.audit`, `cloud.user.create/update/delete`).
- Старая модель события от VMS (`DomainEvent`: тип `alert`/`detector`/`device`, камера, тип детектора, `alertId`, `detectorEventId`, состояние устройства) — [model/an_event_model.go](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/model/an_event_model.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#11).
- Свои темы облака: `cloud.domain.wentonline/wentoffline`, `cloud.domain.node.*`, `cloud.domain.cameras.config.changed`, `cloud.domain.policy.change`, `cloud.notification.push/sms`, `cloud.delete.domain` и др. ([model/queue_events.go](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/model/queue_events.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#10)).
- **Может ли МИ подписаться.** Технически да: подписка `ListenEventInQueueGroup` — это группа подписчиков; сервис с **другим** именем группы получит свою копию тех же сообщений (Предположение: так работает NATS-группа, проверить настройки JetStream-потока — durable/retention). Нужен сетевой доступ к NATS и, если включён, TLS.
- **Webhook** в `develop` нет — не найдено, искал `webhook` (поиск по `master`) и в маршрутах v3. Работа ведётся в ветках `epic/CLOUD-22828-add-webhook`, `epic/CLOUD-22828-webhook` (не изучались).

> Поправка (второй круг, 2026-10-28): ветка `epic/CLOUD-22828-add-webhook`: CRUD и отправщик есть, типов событий и вызовов нет — МИ не поможет. См. [12, п. 3](12-tenancy-users.md#3-события-об-изменениях).

## Реальное время

- Своего канала «облако → браузер» (WebSocket, SSE, long-poll) для уведомлений в `develop` нет. Все `websocket.Upgrader` в коде — это **прокси** WebSocket к VMS (`axxonrp/wsproxy`, `arpserver`, `arpagent`) ([axxonrp/wsproxy](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/axxonrp/wsproxy/websocketproxy.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3)).

> Поправка (второй круг, 2026-10-28): в nginx Bezeq есть WebSocket `/api/v1/notifier/connect` → `backend`; код не найден — вопрос облаку. См. [13, поправки](13-cloud-ui-menu-video.md#поправки-к-первому-кругу).

- Ветка `feature/webSocket` не найдена (фильтр веток по `Socket`/`ocket` — пусто).
- Push есть только на **мобильные** устройства: FCM и APNS ([service/notification](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/service/notification/notification_service.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3)); API `/devices`, `/notifications/settings`, `/notifications/snooze`, `/notifications/event`. E-mail и SMS — через `jobrunner`.
- Вывод: для очереди инцидентов в браузере МИ нужен свой канал (WebSocket/SSE в бэкенде МИ) или брать события VMS через WebSocket веб-клиента VMS по туннелю — но это события одного домена, без облачной агрегации.

## Карты

- **Координаты домена** — поле `coordinates` (точка) у домена; в деревьях доменов приходят как `DomainExtraData.Coordinates {Lat, Lng}`; удалить — `DELETE /domains/{domainId}/coordinate` ([model/domain_model.go](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/model/domain_model.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#99), [tree_roles.go](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/model/domain-roles/tree_roles.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#71)).
- **Координаты камер** — в `configsync`: `geoLatitude`, `geoLongitude`, `geoAzimuth`; `GET /api/v1/configsync/cameras` возвращает камеры с `coords` и `previewUrl`.
- **Слоёв карт, планов объектов (этажей), привязки устройств к плану** в `develop` нет — не найдено, искал `map`, `layer`, `floor`, `plan` в списке маршрутов v3 и в моделях. Работа — в ветках `feature/CLOUD-22804-epic-map-layers`, `CLOUD-23235-permisions-for-cameras-map-and-domains-map`, `bugfix/CLOUD-14846-domain-maps` (не изучались). Предположение: права «карта камер» и «карта доменов» появятся как глобальные права.

## Похожие функции

| В облаке | Что делает | Пересечение с МИ |
|---|---|---|
| Push/SMS по тревогам VMS (`backend` + `jobrunner`) | тревога VMS → уведомление владельцу/подписчикам домена; SMS только по ряду детекторов | пересекается по смыслу (реакция на тревогу), но источник у МИ свой — агенты МИ |
| `monitoring`: правила оповещений ([monitoring/model/alert.go](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/monitoring/model/alert.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#21)) | «домен онлайн/офлайн», «камера онлайн/офлайн», CPU/RAM/архив выше порога, сертификат истекает; типы `Problem` и `Event`, дедупликация 6 мин; рассылка по настройкам | технические тревоги — кандидаты в источники инцидентов МИ; модель «проблема открыта/закрыта» близка к жизненному циклу инцидента |
| Политики поддержки (`/policies/support`) | временный доступ поддержки к домену | похоже на временную передачу/эскалацию, но про доступ, а не про инцидент |
| Раскладки (`configsync` `/layouts`) | сохранённые раскладки камер пользователя | можно переиспользовать для «видео по инциденту» |
| Аудит (`/audit`, NATS `ad.cloud.audit`) | журнал действий пользователя | МИ может писать туда действия оператора |

Обработки тревог оператором (взять, закрыть, комментарий, очередь) в облаке нет — не найдено. Ветка `epic/CLOUD-22825-monitoring-etisalat` не изучалась.

## Локальный запуск

Источник — [docs/run_cloud_on_local_machine.md](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/docs/run_cloud_on_local_machine.md?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3) в axxoncloudgo. Дальше — пересказ и проверка по файлам стенда.

**Требования (из документа)**

- ОС: Ubuntu (раздел «с нуля» — Ubuntu 20.04) ([#5](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/docs/run_cloud_on_local_machine.md?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#5); раздел «Full installation from empty ubuntu»).
- Go (snap), Docker CE с buildx и compose-plugin, пользователь в группе `docker`, `docker swarm init` (раздел «Required dependencies»).
- Вне офиса — корпоративный OpenVPN; проверка доступа к Go-прокси `npm.itvgroup.ru:3000` ([#13](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/docs/run_cloud_on_local_machine.md?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#13)). `make dep` = `GOPROXY=http://npm.itvgroup.ru:3000 go mod download`.
- SSH-ключ в Bitbucket, клон `ssh://git@src.axxonsoft.dev/proj/axxoncloudgo.git`, ветка `develop`.
- Доступ к Bamboo `build2.axxonsoft.dev` за артефактом UI.
- Память, процессор, диск — **в документе не указаны**.

**Шаги**

1. Клонировать axxoncloudgo, переключиться на `develop`.
2. Убедиться, что контейнеров нет (`docker ps`); почистить: `make rm`, `make clear-test`.
3. Вне офиса — VPN; проверить `npm.itvgroup.ru:3000`.
4. Добавить в `/etc/hosts` имена на `127.0.0.1`: для облака `axxonnet.test`, `vmscloud.local`, `backend`, `db`, `nats`, `queue`, `arpserver`, `configsync`, `nginx`, `vmsmanager`, `redis`, `axxon-next`, `vsaasmanager`, `minio`, `uploader`, `jetstream` (в документе есть и другие имена — они к МИ не относятся) ([#19](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/docs/run_cloud_on_local_machine.md?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#19)).
5. Из корня axxoncloudgo ([#48](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/docs/run_cloud_on_local_machine.md?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#48)):
   - `make dep` — зависимости (нужен VPN);
   - `go install go.uber.org/mock/mockgen@v0.6.0`;
   - `make gen-bp` — заготовки по swagger (ставит приватный `oapi-codegen@v0.11.0` через тот же прокси);
   - `make gen` — генерация кода по swagger;
   - скачать в Bamboo план `ASIP-AX` → Artifacts → «Build AxxonCloud UI» → `ui-AxxonNet.zip` и распаковать в `tools/compose`;
   - `make build-all` — собрать образы;
   - `make deploy` — поднять стек `ac` в Swarm.
6. Проверить `docker service ls`.

- Остановка: `make rm` (удаляет **все** сервисы Swarm на машине). Пересборка одного сервиса: `make redeploy-ac | -arp | -jr | -vsaasmanager | -configsync | -monitoring` ([local.mk](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/local.mk?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3)).
- Отладка: в `tools/docker/cloud.debug.Dockerfile` раскомментировать запуск через `dlv` на порту 40000 и подключить IDE как remote (раздел «Debug running local cloud»). Отдельно описана отладка arpagent с реальной VMS (раздел «Debugging arpagent»).

**Что поднимается** (стек `ac`, [anticonsul-ac.docker-stack.yml](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/tools/compose/anticonsul-ac.docker-stack.yml?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3), сеть `ac`, env `tools/env/dev.env`):

| Сервис | Порты на хосте |
|---|---|
| db (postgres 9.6, без пароля) | 5432 |
| redis 4 | 6379 |
| backend (облако) | 8000, отладка 40000 |
| arpserver | 8888, 8889, 8080, 8890, 40002 |
| jobrunner | 40006 |
| vsaasmanager | 8086, 40001 |
| uploader (`up/uploader`) | — |
| nginx (`ac/nginx-anticonsul`, отдаёт UI из `tools/compose/ui`) | 8082→8081, 8083→8082, 8084→8083 (TLS) |
| haproxy (вход) | 80, 443, 9292 (статистика `admin:password`) |
| queue (nats-streaming 0.14) | 4222, 8222 |
| jetstream (nats 2.10) | 4223, 8223 |
| configsync | 9006, 40003 |
| monitoring + monitoring-db (postgres 17) | 9007, 40004; 5433 |
| mediaserver (mediamtx) | 554, 322, 1935, 1936, 9997 |
| prometheus | 9090 |

- Вход: `https://axxonnet.test` → haproxy:443 → nginx:8082 → `/api/` и `/api/v3/ac-backend/` на `backend:8000`, `/api/v1/configsync/` на configsync, `/arpserver…` на arpserver, остальное — статический UI ([nginx.anticonsul.conf](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/tools/docker/nginx.anticonsul.conf?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3)). Сертификат — `tools/docker/axxonnet.test.pem`.

**Тестовые пользователи**

- В документе не описаны. В `local.mk` облака есть цель `make create-db-users`: вставляет в `users` пользователя `user@gmail.com` (поле `an_password = 'password'`) ([local.mk#22](https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/local.mk?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#22)). Предположение: вход — `user@gmail.com` / `password`; не проверено.

**Известные проблемы и расхождения** (факты из файлов, раздела «проблемы» в документе нет)

- Команда проверки `telnet npm.itvgroup.ru:3000` записана с двоеточием; telnet ждёт `telnet npm.itvgroup.ru 3000`.
- `minio` в hosts указан дважды; сервис minio в стеке закомментирован.
- `make build-all` не собирает `up/uploader`, а стек его ждёт. Откуда брать образ — в документе нет.


**Что добавить для МИ на локальном стенде**

Выводы и предложения. Ничего из этого в репозиториях пока нет.

1. **incident-manager-server** — сервис в стеке `ac` (или отдельный стек в сети `ac` с `attachable: true`). Своя база: отдельный postgres без проброса порта на хост или отдельная база в `db`. Env: адрес облака для introspect (`http://backend:8000` внутри сети или `https://axxonnet.test`).

> Поправка (второй круг, 2026-10-28): сервер МИ всегда строит `https://<IM_CLOUD_URL>`, `http://backend:8000` невозможен; нужны имя `axxonnet.test` внутри сети и доверенный сертификат стенда. См. [15, поправки](15-deploy-configurator.md#поправки-к-первому-кругу), [15, п. 6](15-deploy-configurator.md#6-локальный-стенд-план-добавления-ми-в-стек-ac-без-запуска).

2. **nginx облака** — добавить `location /im/` (статический конфигуратор, `try_files $uri /im/index.html`) и `location /api/…/im…` → incident-manager-server. Сейчас `location /` отдаёт `/index.html` облака на любой путь, так что без отдельного `location` SPA под `/im/` не откроется. `include servers/*` в конфиге подходит только для отдельных `server {}`, не для `location`. Значит, править `tools/docker/nginx.anticonsul.conf` и пересобирать образ (`make redeploy-ng`) или монтировать свой конфиг.
3. **Статика конфигуратора и операторской части** — положить сборки в `tools/compose/ui/im/` (и, например, `ui/im-operator/`): nginx облака монтирует эту папку как `html`.

> Поправка (второй круг, 2026-10-28): копировать содержимое `dist/`; zip конфигуратора с корнем `ui/` при распаковке в `tools/compose` смешается с порталом. См. [15, п. 6](15-deploy-configurator.md#6-локальный-стенд-план-добавления-ми-в-стек-ac-без-запуска).

4. **Пользователь и домен** — `make create-db-users` плюс домен с правами. Без домена и прав оператору нечего показывать.
5. **События для очереди** — источник инцидентов МИ — его агенты (`POST /events` бэкенда МИ, см. [03-im-server.md](03-im-server.md)). На стенде — тестовый агент или запросы из теста; настоящая VMS через arpagent — по разделу «Debugging arpagent».
6. **hosts** — добавить имя сервиса МИ, если его отлаживают с хоста вне Swarm.
7. **Отладка** — по образцу `cloud.debug.Dockerfile`: свой порт dlv, например 40010.

## Открытые вопросы

1. Кто регистрирует права `incident_manager.*` и какие именно: бэкенд МИ при старте через `POST /ac/v1/global-permissions` или облако статически? Нужны ли МИ **доменные** права (например, «оператор видит инциденты только своих объектов») — их сервис добавить не может.
2. Как в бою подключаются сервисы рядом с облаком: где конфиг nginx/ingress с `/api/v1/monitoring`, есть ли там уже `/im/`? В этом репозитории боевого деплоя нет.
3. Права на отдельные камеры: облако знает доступ только до домена. Нужно ли МИ ограничивать операторов по камерам/группам камер, и ждать ли для этого ветку object ACL (`CLOUD-23281-epic-acl`, `CLOUD-23501-doma.ai-object_acl`)?
4. Webhook (`epic/CLOUD-22828`): нужен ли он МИ — например, чтобы облако сообщало о смене пользователей, групп и прав? Источник инцидентов — агенты МИ, не облако.
5. Канал реального времени для браузера оператора: облако его не даёт — делать в бэкенде МИ?
6. Видео: достаточно ли веб-API VMS через `/arpserver/<домен>_<n>/webclient/...` для живого видео и архива в операторском месте, или нужен отдельный медиасервис (HLS/WebRTC)?
7. Keycloak (`feature/CLOUD-22056-epic-keycloak`): когда войдёт в `develop` и поменяет ли проверку токенов (JWKS вместо introspect)? От этого зависит авторизация бэкенда МИ.
8. `configsync /internal/*` без `security` и доступен через nginx — это так задумано или закрыто на уровне боевого шлюза?
9. Карты и планы объектов: ждать `feature/CLOUD-22804-epic-map-layers` или держать планы в МИ?
10. «Организация» в облаке — это пользователь-владелец домена. Как МИ будет делить данные между арендаторами (по владельцу домена, по узлу дерева доменов)?

> Поправка (второй круг, 2026-10-28): ответы: 1 — [10, п. 1](10-permissions.md#1-маршрут-put-acv1global-permissionscatalog-и-сверка-с-сервером-ми), [10, п. 5](10-permissions.md#5-глобальные-или-доменные-права-как-назначаются); 2 — [15, п. 1](15-deploy-configurator.md#1-боевой-конфиг-шлюза-где-apiv1monitoring-есть-ли-im-и-apiv1im-backend); 3 — [10, п. 5](10-permissions.md#5-глобальные-или-доменные-права-как-назначаются); 4 — [12, п. 3](12-tenancy-users.md#3-события-об-изменениях); 5 — поток делает МИ, [11, п. 4](11-auth-session.md#4-вход-в-поток-событий-sse); 6 — [13, п. 3](13-cloud-ui-menu-video.md#3-протокол-embeddedhtml-вебклиента-vms); 7 — [11, п. 5](11-auth-session.md#5-keycloak); 8 — [12, п. 5](12-tenancy-users.md#5-безопасность-служебных-api); 9 — [13, п. 4](13-cloud-ui-menu-video.md#4-карта-ключ-mapbox-и-слои); 10 — [12, п. 1](12-tenancy-users.md#1-что-считать-арендатором-ми).
