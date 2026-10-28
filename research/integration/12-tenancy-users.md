# Арендность, пользователи, группы, служебные API и их защита

Тема второго круга: что считать арендатором МИ; какие служебные API облака есть для адресатов передачи и дежурных групп; какие события облако публикует; что такое «роли» в правилах МИ; как защищены `/ac/v1/*` и `configsync /internal/*`.

Дата: 2026-10-28.

Обозначения: без пометки — факт со ссылкой; **Вывод:** — следует из фактов; **Предположение:** — кодом не проверено.

## Что читали

| Репозиторий | Снимок | Как читали |
|---|---|---|
| `PROJ/axxoncloudgo`, ветка прав `epic/CLOUD-23284-perms-i18n` — **основной снимок** | `e51bd552b593db9fdedba16505808bde48b1db96` | Bitbucket MCP |
| `PROJ/axxoncloudgo`, `develop` — для сравнения | `0228c7a9b1acf8faa62aa1097d6ec085882e8cf3` | Bitbucket MCP |
| `PROJ/axxoncloudgo`, `epic/CLOUD-22828-add-webhook` | `c7200b4dcca16e28fe7b3a63c792a9389556086b` | Bitbucket MCP |
| `PROJ/go-util` (общая библиотека), `master` | `450af322e11966f56c3de8e9b4573c3dad492e42` | Bitbucket MCP |
| `IT/axxoncloud-deploy` (ansible и RPM боевой выкладки облака), ветка по умолчанию | `91d1e6d25f3e5ff4273fc1277bf109970a8fcaec` | Bitbucket MCP |
| `IT/axxoncloud-k8s` (helm, 2023 г., устарел) | `020ddada00dd0c12af626d9dfc01756c52d951f8` | Bitbucket MCP |
| `NEW/incident-manager-server`, `develop` | `b743797a38daeb3beaa44ef901b26c3ce924290f` | локально |
| `NEW/incident-manager-server`, `db-schema-design` | `f59b55df441030a1f8d23b66b9bbe9815fde53af` | локально, `git show` |
| `PROJ/incident-manager` (конфигуратор), `master` | `1fcfa25` | локально |
| IM (правила) | `main` `d891125` | локально |

Поиск Bitbucket ищет только по ветке по умолчанию, поэтому всё найденное перечитано на снимках выше. Где ветка прав и `develop` расходятся, это сказано явно. Сокращения в ссылках: **E** — ветка прав `e51bd55`, **D** — `develop` `0228c7a`.

Связанные файлы первого круга: [03 — бэкенд МИ](03-im-server.md#авторизация-арендность-связь-с-облаком), [04 — облако](04-axxoncloudgo.md#арендность-пользователи-группы), [00 — итог](00-summary.md#вопросы).

## Коротко

- **Арендатора в облаке нет.** Сущностей «организация», «клиент», «команда», «центр управления» нет ни на ветке прав, ни в `develop`. Деревья пользователей, доменов и ролей — по одному на установку облака, владельца у узлов нет. Группы пользователей и глобальные роли — общие на всю установку. «Центр управления» есть только в черновике схемы БД МИ (ветка `db-schema-design`).
- **`introspect-user-token` отдаёт ровно четыре поля пользователя:** `userId`, `userName`, `userGroupIds` (по запросу), `permissions[]`. Плюс `status`, `error`, `tokenType`. Ни клиента, ни владельца, ни доменов в ответе нет.
- **Важная находка по безопасности.** `introspect-user-token` проверяет только подпись, срок и тип токена. Живую сессию и блокировку пользователя он **не** проверяет. Принимает не только access-, но и refresh-токен (2 недели) и share-токен. Сервер МИ тип токена не смотрит. Значит, в МИ работают:
  - токен вышедшего или заблокированного пользователя — до конца срока;
  - его refresh-токен — до двух недель;
  - share-токен любого пользователя, а его без всякой проверки выдаёт `GET /ac/v1/shared/token/:userId`.
- **Служебных API для адресатов почти нет.** Есть: группы (только id и имя, без LDAP), карточка пользователя, постраничный список всех пользователей с **именами** групп и признаком «есть сессия в облаке», домены одного пользователя. Нет: состава группы, прав и групп любого пользователя по id, пользователей с правом X, событий об изменениях.
- **Событий об изменении групп, ролей, прав и блокировок нет.** Есть только `cloud.user.create/update/delete` (update — только смена email и лимита; на ветке прав его нет вовсе) и `cloud.domain.policy.change`. Webhook пока без типов событий и без отправителей, в `develop` не влит.
- **«Роли» правил МИ на деле — группы пользователей облака.** Так уже сделано в сервере МИ (`access_rules.external_user_group_id`) и в конфигураторе (экран «Группы доступа»). Рекомендуем закрепить это в правилах.
- **Защита служебных API — только сетью.**
  - В боевой выкладке (`IT/axxoncloud-deploy`) nginx не пропускает `/ac/`, а `/api/v1/configsync/internal` закрыт ответом 403 (кроме конфига `stage4`).
  - Порты `backend:8000` и `configsync:9006` открыты на хосте. Закрывает их только iptables, если вручную прогнан playbook.
  - RPM-пакет публикует их по TLS на 18000 и 19006.
  - On-prem установщики и k8s-конфиг из самого облака пропускают `/ac/` наружу без защиты.
- **Рекомендация по арендатору:** сейчас — «одна установка облака = один арендатор МИ»: `customer_guid` берётся из настроек развёртывания, а не из `fakedata`. Так МИ уже и разворачивают: свои экземпляры для `bezeq` и `itv` в `IT/axxoncloud-deploy`. Запас на будущее — домен у агента и устройства, чтобы потом перейти к схеме «как monitoring».

## 1. Что считать арендатором МИ

### Ответ

**Что есть в облаке (факты).**

| Понятие | Что это в коде | Ссылки |
|---|---|---|
| Пользователь | строка `users`; входит в несколько групп пользователей (таблица `users_user_groups`) | [253_new_users_user_groups_table.sql#3 (E)][m253] |
| Claims в JWT | `UserID`, `UserName`, `ClientID`, `ClientType`, `Version`, `Type`, `CreatedAt` + `exp/iat/iss` — без организации и прав (подтверждаю [04](04-axxoncloudgo.md#авторизация)). `ClientID` — это id клиентского приложения или сессии, а не «клиент» в смысле заказчика | [04](04-axxoncloudgo.md#авторизация) |
| «Организация» в `POST /api/v1/auth/introspect` | для токена пользователя `OrganizationID = UserID`, `OrganizationName = UserName`; для токена домена — `domain.user_id` (владелец домена) и имя домена | [auth.go#2546 (E)][e-convclaims], [auth.go#2435 (E)][e-orgdomain] |
| Владелец домена | `domains.user_id` — пользователь, подключивший домен | [04](04-axxoncloudgo.md#арендность-пользователи-группы) |
| VSaaS «customer» | `customerId` — это **имя домена**; облако отдаёт `user_id` его владельца. Маршрут `/ac/v1/...` без авторизации | [handler/rest/vsaas.go#44 (E)][vsaas] |
| Деревья пользователей, доменов, ролей | у узла есть `id`, `path`, `name`, `user_id`/`domain_id`, `type` — **поля владельца или арендатора нет**; дерево одно на установку | [tree_roles.go#27 (E)][e-tree] |
| Группа пользователей | `id`, имя, одна глобальная роль, лимиты сессий, 2FA — тоже общая на установку | [04](04-axxoncloudgo.md#арендность-пользователи-группы) |
| DomaAI | внешний вход OIDC (сервис управления домами). Сотруднику УК облако назначает глобальную роль по имени `Manager`; жильцу — доменную политику с ролью `operator` по адресу и подъезду. Отдельного арендатора не создаёт | [auth.go#27, #1082 (E)][e-doma], [services/auth/doma_ai.go (E)][e-domaai] |
| Команды, организации, центр управления | в облаке не найдено: искал `control_center`, `CREATE TABLE organizations` — пусто | — |
| «Центр управления» в МИ | только черновик `v1/cloud-additions.sql` на ветке `db-schema-design` сервера МИ: `customers → control_centers → facilities → areas`, `domain_areas`. В `develop` сервера МИ его нет | `git show f59b55d:v1/cloud-additions.sql` |

**`POST /api/v1/auth/introspect-user-token?withUserGroups=true` — все поля ответа** ([model/auth/auth.go#33–#46 (E)][e-authmodel]; обработчик [handler/rest/auth.go#726 (E)][e-handler]; логика [appservices/user/auth.go#2459 (E)][e-iut], в `develop` — тот же код, [#2492 (D)][d-iut]):

```
{ status: 0|1, error?: string, tokenType: "access"|"refresh"|"share",
  accessData?: { authData: { userId, userName, userGroupIds?: [int64], permissions: [{name,…}] } } }
```

- `userGroupIds` заполняется только при `withUserGroups=true` ([#2501 (E)][e-mkinfo]).
- Клиента, владельца, доменов, локали, почты в ответе **нет**.
- Принимаются три типа токена: access, refresh, share ([#2459 (E)][e-iut]).
- Проверка — только разбор JWT, подписи и срока ([services/auth/service.go#653 (E)][e-parse]). Сессию (`CheckSessionIsActive`) и блокировку не проверяет. Собственные обработчики backend сессию проверяют (`ResolveUserByAccessToken`, `getUserByRefreshToken` — [auth.go#2306 (E)][e-sess]). Подробно — раздел 5.

**Как арендатора определяют сервисы рядом с облаком (образец для МИ).**

| Сервис | Как определяет «чьи данные» | Ссылки |
|---|---|---|
| `monitoring` | id арендатора нет. На каждый запрос: introspect → `userId` → `GET /ac/v1/users/domains/permissions?userId=` → список доменов пользователя; все выборки — по `domainIDs`. Свои записи (правила оповещений) — с `owner_id` = id пользователя. Изменять разрешает только по access-токену (`IsAccessToken`), смотреть — по любому | [monitoring/service/monitoring/types.go#13 (D)][mon-types], [monitoring/model/notification_config.go#29 (D)][mon-owner], [monitoring/service/auth/auth_service.go#33 (D)][mon-auth], [monitoring/model/auth.go#14 (D)][mon-isacc] |
| `configsync` | так же: домены пользователя по `GetDomainsWithPermissions`; служебные `/internal/*` — без пользователя | [04](04-axxoncloudgo.md#устройства-видео-события) |
| `arpserver` | доступ к домену по доменным политикам; слушает `cloud.domain.policy.change` | [04](04-axxoncloudgo.md#устройства-видео-события) |
| `vsaasmanager` | заказчик VSaaS = домен с именем `customerId` и его владелец | [vsaas.go#44][vsaas] |

**Вывод:** в облаке «арендатор» — это либо вся установка (группы, роли, деревья общие), либо набор доменов, доступных пользователю. Своего id арендатора ни один сервис не хранит.

**Как сервер МИ использует `customer_guid` сейчас.**

- Таблица `customers` (`guid`, `name`, `creator_user_id`) — [001_initial_scheme.sql#3][im-001]. Почти все таблицы ссылаются на неё через `customer_guid`. Одна запись `TestCustomer` вставлена миграцией [002#3][im-002].
- Пользователю middleware ставит `CustomerGUID` из заглушки: [auth_middleware.go#96][im-mw96]. Агенту — тоже: [#56][im-mw56]. Сама заглушка: [fakedata.go#59–#75][im-fake].
- Запросы к инцидентам и сценариям по `customer_guid` не фильтруются ([03](03-im-server.md#авторизация-арендность-связь-с-облаком)).
- `GET /user-groups` МИ отдаёт **все** группы облака без отбора ([access_rule.go#52][im-ar]).

**Что подставить вместо `fakedata` — варианты.**

| | А. Установка облака = арендатор | Б. Владелец домена (как monitoring) | В. Своя сущность МИ («центр управления») |
|---|---|---|---|
| Что такое `customer_guid` | одна запись на развёртывание: GUID из настройки (например `IM_CUSTOMER_GUID`) или создаётся при первом старте | `customer` = пользователь-владелец домена (`domains.user_id`); доступ пользователя — через его домены (`/ac/v1/users/domains/permissions`) | своя таблица МИ (`customers → control_centers`); пользователи и группы облака привязываются к ней администратором МИ |
| Что дать агенту и устройству | ничего | домен облака (id) — при выдаче токена регистрации агента | центр управления |
| Плюсы | Совпадает с тем, как устроено облако: группы, роли, деревья общие на установку. Совпадает с тем, как МИ уже разворачивают (`bezeq`, `itv` — свой МИ на каждую установку, [nginx bezeq#358][it-bezeq-im], [imbackend.env#5][it-imenv]). `GET /ac/v1/user-groups` без арендатора не мешает. Минимум работы: убрать `fakedata`, оставить фильтры по `customer_guid` | В духе облака, работает и в общем публичном облаке. Повторяет готовый образец `monitoring`. Связывает объекты МИ с доменами — нужно и для видео | Точная модель для охранного предприятия, которое обслуживает много заказчиков. Не зависит от облака |
| Минусы | Не годится для общего публичного облака с независимыми клиентами: администратор МИ увидит группы всех клиентов, а права `incident_manager.*` — глобальные на установку | У оператора могут быть домены нескольких владельцев: он в нескольких арендаторах сразу, нужен выбор. Группы пользователей и глобальные права — общие, по владельцу не делятся: правила доступа МИ по группам смешают клиентов. Лишний вызов на каждый запрос (нужен кэш). У агента МИ сейчас нет домена | Своя админка и своё сопоставление людей; облако о нём ничего не знает; дублирует дерево доменов. Самое дорогое |

**Рекомендация — А сейчас, с заделом на Б.** Обоснование:
- облако само однотенантно на уровне групп и ролей, а именно на них стоят права и правила доступа МИ;
- боевые развёртывания МИ уже идут «по установке»;
- вариант Б без изменений в облаке не даёт разделить группы и права между клиентами.

Задел: хранить у агента и устройства домен облака (нужен и для видео — см. [00](00-summary.md#что-операторской-части-нужно-и-где-это-взять)), во всех запросах держать фильтр по `customer_guid`. Тогда переход к Б — это смена источника `customer_guid`, а не схемы.

### Уверенность

- Поля introspect, отсутствие арендатора в облаке, `fakedata` в МИ — подтверждено кодом.
- Что МИ разворачивают по установке — подтверждено конфигами `IT/axxoncloud-deploy`.
- Рекомендация — вывод.

### Что осталось спросить у людей

- **Продукт / руководство МИ:** «Будет ли МИ работать в общем публичном облаке (axxonnet.com), где независимые клиенты делят одну установку? Или только в выделенных установках (как bezeq, itv)?» От ответа зависит, хватит ли варианта А.
- **Команда облака:** «Планируется ли сущность организации (арендатора) или владелец у узлов дерева доменов и пользователей? Будут ли группы пользователей и глобальные роли делиться по организациям?»
- **Команда бэкенда МИ:** «Черновик `cloud-additions.sql` (центр управления, объекты, зоны) — живая задумка или отменена?»

## 2. Служебные API для адресатов передачи и дежурных групп

Что нужно МИ — по правилам [§5](../../Specification/State_rules/States%20rules%20IM.md#5-права-доступа), [§8.1](../../Specification/State_rules/States%20rules%20IM.md#81-кто-может-быть-адресатом), [§8.3](../../Specification/State_rules/States%20rules%20IM.md#83-уровни), [§12](../../Specification/State_rules/States%20rules%20IM.md#12-состояние-оператора), [§15](../../Specification/State_rules/States%20rules%20IM.md#15-открытые-вопросы). Что есть — сервисные маршруты `/ac/v1` ([handler/s2s/init.go (E)][e-s2s]); на ветке и в `develop` набор один и тот же, кроме `PUT /global-permissions/catalog` — он есть только на ветке ([#65 (E)][e-s2s-cat]).

| Что нужно МИ | Зачем (правила) | Есть ли в облаке | Чего не хватает |
|---|---|---|---|
| Вошедший пользователь: id, имя, группы, права | проверка действий, группы доступа (§5) | да: `introspect-user-token?withUserGroups=true` | почты и ФИО; признака «сессия жива»; см. раздел 5 |
| Карточка любого пользователя по id | имя в журнале, в списке адресатов | да: `GET /ac/v1/users/:userId?params=name&params=email&params=surname` ([#105 (E)][e-s2s-user], [user_handler.go#50 (E)][e-uh]) | — |
| Все пользователи установки | список адресатов (§8.1) | частично: `GET /ac/v1/axxondata/users?pageLimit&pageOffset&searchByEmail&onlineOnly` ([#111 (E)][e-s2s-users], [user_handler.go#70 (E)][e-uh70]). Поля: `id`, `email`, `lastActivityTime`, **имена** групп, IP сессий, `isOnline` ([#88 (E)][e-uh88]) | имени и фамилии (только почта); **id** групп (только имена — сломается при переименовании); отбора по группе; страница по умолчанию — 10 |
| Список групп пользователей | правила доступа, дежурные группы | да: `GET /ac/v1/user-groups` → `[{id, name}]` ([usergroup_handler.go#20 (E)][e-ugh]) | группы LDAP **исключены** ([#29 (E)][e-ugh29]); нет глобальной роли группы; нет отбора по арендатору |
| Состав группы (кто в ней) | участники дежурной группы (§8.1), «группа на месте» | **нет** в `/ac/v1`. Есть только в публичном `GET /api/v3/ac-backend/user-groups` (`ListUserGroupsWithMembers`) — под токеном пользователя с правом управления группами ([user_groups_handlers.go (E)][e-v3ug]) | служебный `GET /ac/v1/user-groups/{id}/users` или `GET /ac/v1/users?groupIds=` |
| Группы любого пользователя по id | группы доступа адресата (§5, §8.1) | **нет** (косвенно — имена групп из `/axxondata/users`) | `userGroupIds` в `GET /ac/v1/users/:userId` |
| Права любого пользователя по id | «адресат может принять» — нужен `incident:accept` (§8.1, §8.3) | **нет**: права отдаёт только introspect по токену самого пользователя; служебного «роль группы → права» тоже нет | `GET /ac/v1/users/:userId/permissions` или пакетно `POST /ac/v1/users/permissions {userIds}` |
| Пользователи с правом X | список адресатов «кто может принять», «Передать некому» (§8.1) | **нет** | `GET /ac/v1/users?permission=incident_manager.incidents.process` |
| Доступ к объекту | «доступ к объекту инцидента» (§5) | в облаке доступ известен только с точностью до домена: `GET /ac/v1/users/domains/permissions?userId=` — домены одного пользователя ([#90 (E)][e-s2s], [domain_handler.go#209 (E)][e-dh]). Обратного («кто видит домен») нет | Для МИ доступ к объекту задают правила доступа самого МИ (группа → устройство). Облако здесь нужно, только если объекты МИ привяжут к доменам (вариант Б) |
| Присутствие («на месте», перерыв, вышел) | список адресатов в два раздела (§8.1), автоэскалация (§8.3) | только `isOnline` в `/axxondata/users` = есть хоть одна живая сессия облака с любого клиента; refresh живёт 2 недели | Это не присутствие в МИ. Присутствие ведёт сам МИ по своей сессии и heartbeat (§12) — облачное не годится |
| Сигнал «права, группы, роли изменились» | вернуть в очередь инцидент адресата без права или доступа (§5, §8.1); вариант «токен + событие» из §15 | **нет** (раздел 3) | события в NATS или опрос |
| Блокировка и удаление пользователя | снять его инциденты, исключить из адресатов | удаление — событие `cloud.user.delete`; блокировка — нет | событие блокировки |

**Вывод.** Без изменений в облаке МИ может:
- показать список групп;
- показать людей — только почту и имена групп, со страницами;
- проверить права **вошедшего** пользователя.

«Передать можно только тому, кто может принять» (§8.1) и состав дежурной группы по ролям без доработок облака честно не сделать.

**Обходной путь без облака** (вывод): МИ запоминает у себя права и группы каждого пользователя при каждом его запросе (из introspect). В адресаты берёт только тех, кто хоть раз входил в МИ. Для вышедших права — на момент последнего входа. Цена: снятое у вышедшего право МИ узнает только при его следующем входе. Для первой версии допустимо, если честно сказать об этом в правилах (§15).

**Минимум, который просить у облака** (по убыванию важности):
1. `GET /ac/v1/users?groupIds=&permission=&ids=` → `[{id, name, surname, email, userGroupIds[], permissions[], isBlocked}]`, со страницами;
2. событие об изменении членства в группе, роли группы, прав роли, блокировки (раздел 3);
3. служебный вход для `/ac/v1` (раздел 5).

### Уверенность

Подтверждено кодом (маршруты, обработчики, поля ответов). «Состава группы в S2S нет» — по полному списку маршрутов `init.go` на обоих снимках.

### Что осталось спросить у людей

**Команде облака (backend):** «Готовы ли добавить служебный список пользователей с отбором по группам и праву и с `userGroupIds` и `permissions` в ответе? Если нет — можно ли сервису МИ вызывать публичный `GET /api/v3/ac-backend/user-groups` от имени служебной учётной записи?»

## 3. События об изменениях

### Ответ

**Темы в общей библиотеке** ([go-util queue/model/queue-names.go][gu-names]):
- `cloud.user.create` (стр. 11), `cloud.user.update` (стр. 12), `cloud.user.delete` (стр. 13);
- `ad.cloud.audit` (стр. 18);
- `vmsmanager.bind/unbind.role.preset` (стр. 7–8) — это роли VMS, не облака.

Тем про группы, глобальные роли, права, блокировку **нет**. Тема политик `cloud.domain.policy.change` объявлена в самом облаке ([model/queue_events.go#32 (D)][d-qe]; на ветке — та же строка).

**Формат** ([go-util queue/model/events.go][gu-events]):
- `UserCreateEvent {userID, userName, orgID, orgName, indicesLimit}`;
- `UserUpdateEvent {userID, changes}` — ключи только `userName`, `indicesLimit`;
- `UserDeleteEvent {userId}`;
- `PolicyChangeEvent {policyId, editorId, userIds[], domainIds[], type}`.

Обёртка — `{"isWrappedData":true,"requestId","payload"}`.

**Кто публикует** (`develop`, [services/queue/queue.go#85 (D)][d-q]):
- create и delete — при создании и удалении пользователя; для vsaas-пользователей create не шлётся;
- update — **только при смене email или `indicesLimit`** ([appservices/user/users.go#1026 (D)][d-uupd]);
- политики — при создании и удалении политики и при создании домена ([domain_roles.go#759 (D)][d-pol]).

На ветке прав `e51bd55` **темы `cloud.user.update` нет** ([services/queue/queue.go#85 (E)][e-q]).

**Чего нет:**
- добавление в группу и удаление из неё (`AddUsersToGroupsByUser`, `DeleteUsersFromGroups`, `MoveUsersToGroupByUser`) пишут только аудит ([user_groups.go#296 (D)][d-ug296]);
- смена глобальной роли группы (`AssignRole`) и прав роли (`updateRoles`) — только аудит ([global_roles.go#212 (D)][d-gr212]);
- блокировка пользователя — только аудит и завершение сессий;
- выход и завершение сессии — событий нет.

**Подписчики в облаке.** `cloud.domain.policy.change` слушает `arpserver` ([axxonrp/server/queue.go#145 (D)][d-arpq]). На `cloud.user.*` внутри облака не подписан никто.

**Может ли МИ подписаться.**
- Технически да. При JetStream у каждого сервиса свой durable-консьюмер `<serviceName>-<тема>`, к имени темы добавляется префикс `VMS_CLOUD_EVENTS` без точки.
- Надёжности нет:
  - публикация «выстрелил и забыл» — ошибку видно только в логе;
  - хранение 3 часа;
  - сообщение подтверждается даже при ошибке обработчика ([go-util queue/jetstream/jetstream.go#228][gu-js]).
- Без JetStream — NATS Streaming; что включено в бою, по коду не видно.

**Побочный канал — аудит `ad.cloud.audit`.**
- Ключи `audit.user.group.add/delete`, `audit.role.change`, `audit.global.role.update`, `audit.user.block` ([model/audit_model.go#105 (D)][d-audit]).
- Работает только при включённом `AuditMode`.
- Цель в событии указана почтой и **именем** группы, а не id.

**Вывод:** как сигнал «перечитать» годится, как источник данных — нет.

**Webhook (`epic/CLOUD-22828-add-webhook`, `c7200b4`).**
- Есть CRUD `/notifications/webhook` для любого вошедшего пользователя ([backend.swagger.yaml#14071][wh-api]) и отправщик в `jobrunner`.
- Отправщик подписывает тело `X-Webhook-Signature: sha256=<HMAC>`, повторов нет ([webhook_sender.go#48][wh-send]).
- **Типов событий нет, ни один код webhook не вызывает.** Событий про пользователей, группы и права нет.
- В `develop` не влит.

**Вывод:** МИ webhook сейчас не поможет.

**Вывод по §15 правил.** Вариант «права в токене при входе + событие „права изменились“» облако сейчас не поддерживает: события нет. Реально:
- (а) права на каждый запрос через introspect с кэшем 30 с — как сейчас; так снятое у **работающего** оператора право действует до 30 с;
- (б) периодическая сверка адресатов и владельцев открытых инцидентов (§5: «если у владельца или адресата больше нет доступа…»). Сверять — по данным из п. 2 (обходной путь или новые служебные API), например раз в минуту;
- (в) просить у облака событие `cloud.user.access.changed {userIds[]}` при смене членства, роли группы, прав роли, блокировке. Публиковать его облаку просто: все места уже пишут аудит.

### Уверенность

Подтверждено кодом. Транспорт в бою (JetStream или STAN) — не найдено, искал в коде облака и `IT/axxoncloud-deploy` по `JETSTREAM`.

### Что осталось спросить у людей

**Команде облака:**
- «Добавите ли событие об изменении доступа пользователя (членство в группе, роль группы, права роли, блокировка) с id пользователей?»
- «Почему на ветке прав нет `cloud.user.update` — его убирают?»
- «В бою NATS Streaming или JetStream?»

## 4. «Роли» в группах доступа и дежурных группах

### Ответ

**В правилах МИ.** «Роль» — то, что основная система привязывает к людям. По роли задаются группы доступа (роль → устройства и группы устройств) и состав дежурной группы ([§5](../../Specification/State_rules/States%20rules%20IM.md#5-права-доступа), [§8.1](../../Specification/State_rules/States%20rules%20IM.md#81-кто-может-быть-адресатом)). Сколько ролей у человека, не сказано; по тексту — может быть несколько.

**В облаке три разных вещи, похожих на роль:**
1. **Группа пользователей** (`user_groups`). У человека их **несколько** ([m253][m253]), у группы одна глобальная роль.
2. **Глобальная роль** — набор глобальных прав, назначается группе ([04](04-axxoncloudgo.md#права-и-acl)). У человека столько ролей, сколько у его групп. Несколько групп могут делить одну роль.
3. **Доменная роль** — права на узел дерева доменов через политику «узел пользователей × узел доменов» ([04](04-axxoncloudgo.md#права-и-acl)). Узел пользователей тоже бывает «группой» (`type=group`, [tree_roles.go#14 (E)][e-tree]) — это **другая** группа, не `user_groups`.

**В сервере МИ.** Правило доступа — `external_user_group_id` → устройство, тип устройства, тип события или группа устройств ([007_add_access_rules.sql#8][im-007]).
- Список групп для выбора — `GET /user-groups` → облако `GET /ac/v1/user-groups` ([access_rule.go#52][im-ar], [client.go#121][im-cl121]).
- Группы пользователя — `userGroupIds` из introspect ([client.go#74][im-cl74]).
- Ветка `db-schema-design` прямо говорит о смене решения: последний коммит — «version 7 (role to user-group for rule assignments)» (`f59b55d`).

**В конфигураторе.** Пункт меню «Группы доступа» (`/role-user-groups`). Экран показывает группы пользователей облака и привязки к ним: «Группа пользователей: {name}», «Не выбрана группа пользователей» ([nav.json][cf-nav], [roleAssignments.json][cf-ra]). API — `/api/v1/im-backend/user-groups` и `/access-rules` ([imBackendRoleAssignments.ts#25][cf-api]).

**Рекомендация.** Считать «ролью» правил МИ **группу пользователей облака** (`user_groups`) и так и написать в §5 и §8.1:
- «группа доступа задаётся для группы пользователей облака»;
- «дежурная группа = группы пользователей облака + отдельные люди».

Почему не глобальная роль:
- облако выдаёт людям группы, а роль — только через группу;
- одна роль на несколько групп не позволит различать смены и площадки;
- сервер и конфигуратор уже на группах.

Доменные роли — другая ось: доступ к VMS. Их стоит учитывать, только если МИ перейдёт к варианту Б (раздел 1).

Оговорки, которые надо записать:
- `GET /ac/v1/user-groups` **не отдаёт группы LDAP** ([#29 (E)][e-ugh29]) — на них правило доступа завести нельзя. **Предположение:** introspect их id отдаёт, проверить;
- имена групп не переводятся — как и названия дежурных групп (§14.9);
- членство меняется без события (раздел 3).

### Уверенность

Сервер и конфигуратор — подтверждено кодом. Рекомендация — вывод.

### Что осталось спросить у людей

- **Нашей команде (правила):** «Принимаем „роль = группа пользователей облака“ и правим §5, §8.1, §1 (термин)?»
- **Команде облака:** «Почему служебный список групп исключает LDAP-группы, и можно ли их отдавать с признаком?»

## 5. Безопасность служебных API

### Ответ — что в коде облака

- `/ac/v1/*` регистрируется на том же роутере и порту `:8000`, что и публичный `/api/v1`, без промежуточного слоя авторизации ([handler/cloud/api.go (E)][e-api]: `ac := r.Group("ac/v1")`; `s2s.AddRoutes`). Swagger-заголовок: `Schemes: http`, `Host: backend:8000` ([init.go#5 (E)][e-s2s]). На обоих снимках одинаково.
- Среди служебных маршрутов без входа есть опасные:
  - `GET /ac/v1/shared/token/:userId` — **выдаёт share-токен на любого пользователя** ([init.go#118 (E)][e-s2s-share], [handler/rest/auth.go#627 (E)][e-sharetok], [service/auth/auth_service.go#309 (E)][e-genshare]);
  - `PUT /ac/v1/global-permissions/catalog` и `POST /ac/v1/global-permissions` — переписать каталог прав ([#64–#65 (E)][e-s2s-cat]);
  - `DELETE` пользователя и домена VSaaS ([#68–#70 (E)][e-s2s-cat]);
  - список всех пользователей.
- На том же роутере — `/debug/pprof/*` ([api.go (E)][e-api]).
- `configsync`: `/internal/cameras`, `/cameras/uid`, `/cameras/groups`, `/groupNames`, `/objects`, `/objectsamount` — без входа; токен домена требует только `/internal/groups`. Сервер слушает все интерфейсы ([configsync/handlers/boilerplate/server.go#807 (D)][cs-routes]; на ветке так же).

### Ответ — сеть и шлюз (по выкладкам)

| Где | `/ac/` наружу | `configsync /internal` наружу | Прямой доступ к `:8000` / `:9006` | Ссылки |
|---|---|---|---|---|
| Боевая выкладка ansible `IT/axxoncloud-deploy` | **нет**: только `location /ac/v1/heartbeat/nginx { return 200; }`, прочий `/ac/…` уходит в статику | **403** (`location /api/v1/configsync/internal`) | сервисы в `network_mode: host`, слушают все интерфейсы. Снаружи закрывает только iptables (`INPUT DROP`, открыты 22/80/443) — если вручную прогнан `fw-setup.yml`; ни один сценарий его не вызывает. Внутри кластера открыто всем хостам | [nginx.conf.ctmpl#251][it-ac], [#330][it-cs], [service-container-starter#73][it-host], [fw-setup.yml#31][it-fw] |
| То же, конфиг `stage4` | нет | **проксируется**, блока 403 нет | как выше | [stage4 nginx#311][it-stage4] |
| RPM-пакет облака (`IT/axxoncloud-deploy/rpm`) | — | — | **haproxy публикует `:18000` → `127.0.0.1:8000` и `:19006` → `127.0.0.1:9006` по TLS, без фильтров** | [haproxy-tls.cfg#40][it-rpm] |
| Helm `IT/axxoncloud-k8s` (2023) | нет | **проксируется** | backend и configsync — ClusterIP; NetworkPolicy нет | [nginx-configs-configmap.yaml#282][it-k8s] |
| Локальный стек облака `tools/docker/nginx.anticonsul.conf` | нет (статика) | **проксируется** | compose публикует `8000:8000`, `9006:9006` | [04](04-axxoncloudgo.md#сервисы-и-шлюз), [anticonsul-ac.docker-stack.yml#55 (D)][d-stack] |
| On-prem Linux (`tools/docker/nginx.ssl.conf`) | **да**: `location /ac/` → backend | да | — | [nginx.ssl.conf#214 (D)][d-ssl] |
| On-prem Windows (`tools/windows/nginx.conf`) | **да**: `location /ac/` → `127.0.0.1:8000` | да | установщик открывает в брандмауэре Windows все порты exe облака | [windows/nginx.conf#178 (D)][d-win], [axxonnet.on-premises.iss#564 (D)][d-iss] |
| k8s minikube `tools/k8s/configs/cluster` | **да** | да | nginx на NodePort 30080 | [cluster nginx.conf#188 (D)][d-k8s] |

nginx, haproxy, compose и Windows-конфиги на ветке прав совпадают с `develop` по размеру файла; построчно не сверяли.

NetworkPolicy, отдельного внутреннего ingress, `auth_request`, `allow/deny` для `/ac` — во всём Bitbucket не найдено.

**Где уже стоит МИ.** В `IT/axxoncloud-deploy` для `bezeq` и `itv` есть `location /api/v1/im-backend` → `im-backend` без доп. защиты ([bezeq nginx#358][it-bezeq-im]) и статика `/im`. Сервер МИ ходит в `IM_S2S_CLOUD_URL=backend:8000` ([imbackend.env#5][it-imenv]). В том же файле открытым текстом лежит ключ шифрования секретов агентов (значение не приводим).

### Как сервер МИ вызывает облако и риски

- Introspect — `https://<IM_CLOUD_URL>/api/v1/auth/introspect-user-token` через публичный шлюз ([client.go#90][im-cl90]).
- Служебные вызовы — `http://<IM_S2S_CLOUD_URL>/ac/v1/...`, без заголовков и без арендатора ([client.go#121, #144, #177, #195][im-cl195]).
- Тип токена (`tokenType`) МИ не проверяет ([client.go#50–#77][im-cl74]); кэш 30 с по строке токена ([#32][im-cl32]).

**Риски** (выводы; запуском не проверяли):
1. **Подмена пользователя.** Кто дотянулся до `/ac/v1` (on-prem — из локальной сети через nginx; в облаке — с любого хоста кластера или при открытом `:8000`/`:18000`), тот:
   - получает `GET /ac/v1/shared/token/<id администратора>`;
   - с этим share-токеном входит в МИ: introspect его принимает и отдаёт права владельца, МИ тип не проверяет;
   - получает `incident_manager.manage` и всё остальное.

   Срок share-токена задаётся настройкой `shareTokenTTL`.
2. **Отозванный доступ работает.** Выход, завершение сессий и блокировка не видны introspect-у:
   - access-токен работает в МИ до конца срока (~15 мин);
   - **refresh-токен — до 2 недель**, если кто-то пошлёт его вместо access.

   Это строже, чем «до 30 с кэша», как записано в первом круге.
3. **Подмена каталога прав.** Любой в той же сети может `PUT /ac/v1/global-permissions/catalog` и переписать пространство `incident_manager`.
4. **Без арендатора.** `GET /ac/v1/user-groups` и `/axxondata/users` отдают всю установку. При варианте Б (раздел 1) МИ обязан сам отсекать чужое.
5. **Открытый текст.** `http` до `backend:8000`: в `network_mode: host` и между узлами кластера трафик идёт по сети хостов без шифрования. В RPM-пакете для этого и стоит TLS-haproxy.

### Предложения

**В сервере МИ** (можно сделать сразу, без облака):
- принимать только `tokenType == "access"`; share-токену — максимум чтение или ничего, как `monitoring` разрешает изменения только по access ([monitoring/model/auth.go#14][mon-isacc]);
- проверять, что запрос пришёл с access-токеном; при 401 от облака — сбрасывать кэш;
- адреса облака и служебный адрес — в настройках с `https`; таймауты; ни один служебный ответ не логировать целиком;
- убрать ключ шифрования из `imbackend.env` и `im.docker-stack.yml` в секреты выкладки.

**У облака** (просьба команде облака):
- (а) промежуточный слой для `/ac/v1`: служебный токен (заголовок с секретом из выкладки) или mTLS; хотя бы отдельный порт, не публикуемый наружу;
- (б) `introspect-user-token`: проверять живую сессию и блокировку (`CheckSessionIsActive`), как это делают собственные обработчики backend; не принимать refresh-токен;
- (в) закрыть или защитить `GET /ac/v1/shared/token/:userId`;
- (г) убрать `location /ac/` из on-prem nginx (`nginx.ssl.conf`, `windows/nginx.conf`) и k8s-конфига; закрыть `/api/v1/configsync/internal` в `stage4` и on-prem;
- (д) проверить, где используется RPM-haproxy `:18000/:19006` и закрыт ли он брандмауэром.

### Уверенность

- Код облака и сервера МИ, конфиги выкладки — подтверждено чтением.
- Фактическое состояние iptables на боевых серверах, использование RPM-пакета, нормализация путей nginx (`/api/../ac/`) — не проверено. Это не видно из репозиториев, запусков не было.

### Что осталось спросить у людей

**Команде облака и эксплуатации (IT):**
- «Применён ли `fw-setup.yml` на боевых серверах? Где используется RPM с haproxy `:18000/:19006`?»
- «Планируется ли авторизация `/ac/v1`?»
- «Почему `introspect-user-token` не проверяет сессию и принимает refresh-токен — это задумано?»
- «Зачем `/ac/v1/shared/token/:userId` без проверки?»

## Поправки к первому кругу

- **00, «Риски и находки», и 03, «Авторизация…»**:
  - Было: «Отозванный токен работает в МИ до 30 с (кэш introspect)».
  - На деле: `introspect-user-token` не проверяет сессию и блокировку ([auth.go#2459 (E)][e-iut], [service.go#653 (E)][e-parse]). Отозванный access-токен работает до конца срока (~15 мин) плюс 30 с кэша.
  - Ещё: introspect принимает refresh-токен (до 2 недель) и share-токен, а МИ тип токена не проверяет ([client.go#50][im-cl74]).
- **04, «Авторизация», «Сессия в БД»**:
  - Было: «токен считается действующим, только если жива сессия пользователя» — верно только для обработчиков самого backend.
  - Стоит добавить: оба introspect-маршрута, которыми пользуются МИ и `monitoring`, сессию не проверяют.
- **04, «Арендность…», список S2S**:
  - Не хватает `GET /ac/v1/shared/token/:userId` (выдаёт share-токен на любого пользователя без проверки), `PUT /ac/v1/global-permissions/catalog` (есть на ветке прав) и `DELETE` пользователя и домена VSaaS ([init.go (E)][e-s2s]).
  - `GET /ac/v1/axxondata/users` — это не «несколько пользователей», а постраничный список **всех** с именами групп и `isOnline` ([user_handler.go#70 (E)][e-uh70]).
  - `GET /ac/v1/user-groups` исключает группы LDAP.
- **04, конец «Арендность…»**:
  - Было: «nginx адрес `/ac/` наружу не пропускает» — верно для `nginx.anticonsul.conf` и боевой выкладки ansible.
  - Неверно для on-prem установщиков (`nginx.ssl.conf#214`, `windows/nginx.conf#178`) и k8s-конфига `cluster` — там `/ac/` проксируется. Порты `:8000`/`:9006` в бою открыты на хосте, закрыты только iptables (раздел 5).
- **04, «Сервисы и шлюз»**:
  - Было: «Предположение: боевые конфиги шлюза лежат в другом репозитории» — подтверждено, это `IT/axxoncloud-deploy` (ansible).
  - Там же есть `/api/v1/monitoring` ([#342][it-mon]).
- **00, «Карта связей», п. 6**:
  - Было: «Маршрута `/api/v1/im-backend/` в nginx облака нет» — в репозитории облака нет.
  - Но в боевой выкладке `IT/axxoncloud-deploy` он уже есть для `bezeq` и `itv` ([bezeq nginx#358][it-bezeq-im]), со статикой `/im` и ролью `incidentmanager`.
- **00 и 04, `configsync /internal/*`**: «закрыто ли в бою — неизвестно». Ответ:
  - в ansible-выкладке закрыто ответом 403, кроме `stage4`;
  - открыто в on-prem, в локальном стеке и в helm 2023 г. (раздел 5).
- **00, «Коротко» и «Права»**:
  - Было: «в облаке маршрута `PUT /ac/v1/global-permissions/catalog` нет» — верно для `develop` `0228c7a`.
  - На ветке прав `e51bd55` маршрут есть ([init.go#65 (E)][e-s2s-cat], обработчик `ReplaceGlobalPermissionCatalog` в [handler/rest/auth.go (E)][e-handler]).
- **03, «Открытые вопросы», п. 8–11 и 15** — отвечены здесь, разделы 1–5.
- **04, «Открытые вопросы», п. 4** (webhook для смены пользователей и прав): webhook пока без типов событий и без отправителей — не подходит (раздел 3).

[m253]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/store/postgres/migrations/253_new_users_user_groups_table.sql?at=e51bd552b593db9fdedba16505808bde48b1db96#3
[e-convclaims]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/appservices/user/auth.go?at=e51bd552b593db9fdedba16505808bde48b1db96#2546
[e-orgdomain]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/appservices/user/auth.go?at=e51bd552b593db9fdedba16505808bde48b1db96#2435
[vsaas]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/handler/rest/vsaas.go?at=e51bd552b593db9fdedba16505808bde48b1db96#44
[e-tree]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/model/domain-roles/tree_roles.go?at=e51bd552b593db9fdedba16505808bde48b1db96#27
[e-doma]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/appservices/user/auth.go?at=e51bd552b593db9fdedba16505808bde48b1db96#1082
[e-domaai]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/services/auth/doma_ai.go?at=e51bd552b593db9fdedba16505808bde48b1db96
[e-authmodel]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/model/auth/auth.go?at=e51bd552b593db9fdedba16505808bde48b1db96#33
[e-handler]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/handler/rest/auth.go?at=e51bd552b593db9fdedba16505808bde48b1db96#726
[e-iut]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/appservices/user/auth.go?at=e51bd552b593db9fdedba16505808bde48b1db96#2459
[d-iut]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/appservices/user/auth.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#2492
[e-mkinfo]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/appservices/user/auth.go?at=e51bd552b593db9fdedba16505808bde48b1db96#2501
[e-parse]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/services/auth/service.go?at=e51bd552b593db9fdedba16505808bde48b1db96#653
[e-sess]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/appservices/user/auth.go?at=e51bd552b593db9fdedba16505808bde48b1db96#2306
[mon-types]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/monitoring/service/monitoring/types.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#13
[mon-owner]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/monitoring/model/notification_config.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#29
[mon-auth]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/monitoring/service/auth/auth_service.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#33
[mon-isacc]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/monitoring/model/auth.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#14
[im-001]: https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/service/storing/migrations/001_initial_scheme.sql?at=b743797a38daeb3beaa44ef901b26c3ce924290f#3
[im-002]: https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/service/storing/migrations/002_add_initial_data.sql?at=b743797a38daeb3beaa44ef901b26c3ce924290f#3
[im-mw96]: https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/handler/v1/auth_middleware.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#96
[im-mw56]: https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/handler/v1/auth_middleware.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#56
[im-fake]: https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/util/fakedata/fakedata.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#59
[im-ar]: https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/appservice/accessrule/access_rule.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#52
[im-007]: https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/service/storing/migrations/007_add_access_rules.sql?at=b743797a38daeb3beaa44ef901b26c3ce924290f#8
[im-cl32]: https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/externalclient/cloud/client.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#32
[im-cl74]: https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/externalclient/cloud/client.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#50
[im-cl90]: https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/externalclient/cloud/client.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#90
[im-cl121]: https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/externalclient/cloud/client.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#121
[im-cl195]: https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/externalclient/cloud/client.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#195
[e-s2s]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/handler/s2s/init.go?at=e51bd552b593db9fdedba16505808bde48b1db96#5
[e-s2s-cat]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/handler/s2s/init.go?at=e51bd552b593db9fdedba16505808bde48b1db96#64
[e-s2s-user]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/handler/s2s/init.go?at=e51bd552b593db9fdedba16505808bde48b1db96#105
[e-s2s-users]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/handler/s2s/init.go?at=e51bd552b593db9fdedba16505808bde48b1db96#111
[e-s2s-share]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/handler/s2s/init.go?at=e51bd552b593db9fdedba16505808bde48b1db96#118
[e-uh]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/handler/rest/user_handler.go?at=e51bd552b593db9fdedba16505808bde48b1db96#50
[e-uh70]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/handler/rest/user_handler.go?at=e51bd552b593db9fdedba16505808bde48b1db96#70
[e-uh88]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/handler/rest/user_handler.go?at=e51bd552b593db9fdedba16505808bde48b1db96#88
[e-ugh]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/handler/rest/usergroup_handler.go?at=e51bd552b593db9fdedba16505808bde48b1db96#20
[e-ugh29]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/handler/rest/usergroup_handler.go?at=e51bd552b593db9fdedba16505808bde48b1db96#29
[e-v3ug]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/handler/v3/user_groups_handlers.go?at=e51bd552b593db9fdedba16505808bde48b1db96
[e-dh]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/handler/rest/domain_handler.go?at=e51bd552b593db9fdedba16505808bde48b1db96#209
[gu-names]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/go-util/browse/queue/model/queue-names.go?at=450af322e11966f56c3de8e9b4573c3dad492e42#11
[gu-events]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/go-util/browse/queue/model/events.go?at=450af322e11966f56c3de8e9b4573c3dad492e42#7
[gu-js]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/go-util/browse/queue/jetstream/jetstream.go?at=450af322e11966f56c3de8e9b4573c3dad492e42#228
[d-qe]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/model/queue_events.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#32
[d-q]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/services/queue/queue.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#85
[e-q]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/services/queue/queue.go?at=e51bd552b593db9fdedba16505808bde48b1db96#85
[d-uupd]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/appservices/user/users.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#1026
[d-pol]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/appservices/domainroles/domain_roles.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#759
[d-ug296]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/appservices/user/user_groups.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#296
[d-gr212]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/appservices/globalroles/global_roles.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#212
[d-arpq]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/axxonrp/server/queue.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#145
[d-audit]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/model/audit_model.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#105
[wh-api]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/api/backend.swagger.yaml?at=c7200b4dcca16e28fe7b3a63c792a9389556086b#14071
[wh-send]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/main/jobrunner/sender/webhook_sender.go?at=c7200b4dcca16e28fe7b3a63c792a9389556086b#48
[cf-nav]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/shared/i18n/locales/ru/nav.json?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#5
[cf-ra]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/shared/i18n/locales/ru/roleAssignments.json?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#19
[cf-api]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/features/role-assignments/api/imBackendRoleAssignments.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#25
[e-api]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/handler/cloud/api.go?at=e51bd552b593db9fdedba16505808bde48b1db96#72
[e-sharetok]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/handler/rest/auth.go?at=e51bd552b593db9fdedba16505808bde48b1db96#627
[e-genshare]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/service/auth/auth_service.go?at=e51bd552b593db9fdedba16505808bde48b1db96#309
[cs-routes]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/configsync/handlers/boilerplate/server.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#807
[it-ac]: https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/ansible-hc/config/axxoncloud/common/nginx/nginx.conf.ctmpl?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec#251
[it-cs]: https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/ansible-hc/config/axxoncloud/common/nginx/nginx.conf.ctmpl?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec#330
[it-mon]: https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/ansible-hc/config/axxoncloud/common/nginx/nginx.conf.ctmpl?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec#342
[it-host]: https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/ansible-hc/roles/service-container-starter/tasks/main.yml?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec#73
[it-fw]: https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/ansible-hc/fw-setup.yml?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec#31
[it-stage4]: https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/ansible-hc/config/axxoncloud/stage4/nginx/nginx.conf.ctmpl?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec#311
[it-rpm]: https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/rpm/misc/haproxy-tls.cfg?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec#40
[it-k8s]: https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-k8s/browse/helm/axxoncloud/templates/configmaps/nginx-configs-configmap.yaml?at=020ddada00dd0c12af626d9dfc01756c52d951f8#282
[it-bezeq-im]: https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/ansible-hc/config/bezeq/common/nginx/nginx.conf.ctmpl.j2?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec#358
[it-imenv]: https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/ansible-hc/config/bezeq/pos1/docker/imbackend.env?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec#5
[d-stack]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/tools/compose/anticonsul-ac.docker-stack.yml?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#55
[d-ssl]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/tools/docker/nginx.ssl.conf?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#214
[d-win]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/tools/windows/nginx.conf?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#178
[d-iss]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/tools/windows/axxonnet.on-premises.iss?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#564
[d-k8s]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/tools/k8s/configs/cluster/nginx/nginx.conf?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#188
