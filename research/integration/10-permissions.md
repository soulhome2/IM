# Права: каталог прав МИ в облаке

- Тема: права МИ в облаке — регистрация каталога, `/me` и introspect, фронт облака, соответствие 14 прав машины.
- Дата изучения: 2026-10-28.
- Снимки:

| Репозиторий | Ветка | Коммит | Как читали |
|---|---|---|---|
| `PROJ/axxoncloudgo` | `epic/CLOUD-23284-perms-i18n` (основной снимок) | `e51bd552b593db9fdedba16505808bde48b1db96` | Bitbucket MCP |
| `PROJ/axxoncloudgo` | `develop` (для сравнения) | `0228c7a9b1acf8faa62aa1097d6ec085882e8cf3` | Bitbucket MCP |
| `PROJ/axxoncloud-ui` | `CLOUD-23284-epic-perms-catalog` (основной снимок) | `83a04e587c90809e10c4efb4b5a57ce29a335174` | Bitbucket MCP |
| `PROJ/axxoncloud-ui` | `DANV-6795-localize-new-permission` | `2132c4aa8aea82fb33d984e8c9c487a1389e3c5b` | Bitbucket MCP, только история |
| `NEW/incident-manager-server` | `develop` | `b743797a38daeb3beaa44ef901b26c3ce924290f` | локально |
| IM (прототип) | `main` | `d891125` | локально |

Обозначения: без пометки — факт со ссылкой; «Вывод:» — заключение из фактов; «Предположение:» — кодом не проверено. Номера строк — по указанным коммитам. Ничего не запускали.

Ссылки ниже сокращены: `[cg:путь#N]` — `axxoncloudgo` на `e51bd55`, `[ui:путь#N]` — `axxoncloud-ui` на `83a04e5`, `[im:путь#N]` — сервер МИ на `b743797`. Полные адреса — в конце файла.

## Коротко

- **Маршрут есть.** На ветке облака `epic/CLOUD-23284-perms-i18n` объявлен `PUT /ac/v1/global-permissions/catalog`. Тело — дерево узлов `view_group` / `permission` с `i18n`. Запрос сервера МИ ему отвечает **поле в поле**: вне демо-режима сервер МИ с облаком этой ветки стартует. С `develop` облака по-прежнему не стартует: маршрута там нет.
- **Повторная регистрация безопасна.** Права пишутся по UUID (upsert), группы — по имени. Право, которого нет в новом дереве, помечается `deprecated`, но из ролей и из `permissions[]` пользователя не пропадает. Пустые группы удаляются. Всё делается в одной транзакции.
- **Слияние в `develop` не запланировано в коде.** Последний коммит ветки — 2026-10-01. Открытых PR в `develop` нет ни в облаке, ни во фронте. С момента ответвления в `develop` облака влито около 55 PR. Сроки — вопрос к команде облака.
- **Фронт облака на ветке рисует редактор глобальных ролей по каталогу:** группы, порядок, переводы из `i18n`. Права МИ там видны и назначаются, какие бы глаголы в них ни были. Проверка `hasCapability` по-прежнему знает только 15 глаголов, и `take/close/assign/suspend/process/track` для неё «нет права».
- **Глаголы и пространства в облаке зашиты в код:** 21 действие, 7 пространств. Сервис своих глаголов (`release`, `reopen`, `bulk`) и пространства `agent` завести не может. Обходной путь — глагол как ресурс плюс разрешённое действие, например `incident_manager.incidents.release.use`.
- **Только глобальные права.** Каталог сервиса не может завести доменные права: пространство `domains` запрещено. «Оператор видит только свои объекты» делается правилами доступа самого сервера МИ.
- **Ошибка в сервере МИ подтверждена.** `GET /incidents/{guid}` требует `incident_manager.manage`, поэтому оператор карточку не откроет. Кроме того, `GET /incidents` требует `take.any`, то есть по нашей таблице право перехвата. Оператор без перехвата очереди не увидит.

## 1. Маршрут `PUT /ac/v1/global-permissions/catalog` и сверка с сервером МИ

**Ответ.**

*Где объявлен и кто обрабатывает.*
- Маршрут: `v1.PUT(urls.S2sGlobalPermissionsCatalog(), …ReplaceGlobalPermissionCatalog)` [cg:handler/s2s/init.go#65], путь `/ac/v1/global-permissions/catalog` [cg:model/urls.go#506]. Он лежит рядом со старым `POST /ac/v1/global-permissions` (строка 64), в той же S2S-группе без авторизации — как и остальные сервисные маршруты ([04](04-axxoncloudgo.md#как-подключается-внешний-сервис-ми)).
- Обработчик `ReplaceGlobalPermissionCatalog` [cg:handler/rest/auth.go#818] читает тело в `permissions.CatalogNode`. При ошибке разбора отвечает 400, при успехе — `200` с телом `null`.
- Дальше: прикладной сервис в транзакции [cg:appservices/globalroles/global_roles.go#339] → `globalrole.Service.ReplaceGlobalPermissionCatalog` [cg:services/globalrole/service.go#649].

*Формат дерева* [cg:model/permissions/permissions.go#83]:

| Поле | Тип | Что значит |
|---|---|---|
| `uuid` | строка, `omitempty` | id листа-права; у групп не нужен |
| `name` | строка | ключ: у группы `incident_manager[.часть…]`, у права `incident_manager[.ресурс…].действие[.own\|.any]` |
| `type` | `view_group` \| `permission` | группа для показа или право |
| `description` | строка, `omitempty` | технический английский комментарий, не текст интерфейса |
| `deprecated` | bool | устаревшее: скрыто из редактора ролей |
| `isHidden` | bool | скрыто в дереве интерфейса, на проверку права не влияет |
| `i18n` | объект `{"<локаль>": {"title": "…", "description": "…"}}` | подписи групп и прав |
| `children` | массив узлов, `omitempty` | только у `view_group` |

*Проверки* (`Flatten` [cg:model/permissions/catalog_snapshot.go#12]):
- корень — `view_group`, его имя — пространство из одного сегмента (строка 41);
- все узлы — в пространстве корня, имена не повторяются;
- `i18n` — правильный JSON, у каждой локали непустой `title` или `description` (`validateI18n`, [cg:model/permissions/methods.go#283] и ниже);
- имя группы проходит `IsValidGroupName`, имя права — `IsValidPermissionName`: известное пространство и последний сегмент — известное действие или `own/any` после действия ([cg:model/permissions/methods.go#51]);
- пространство `domains` запрещено (`validateGlobalCatalogName`, [cg:model/permissions/methods.go#290]);
- у права обязателен правильный и неповторяющийся `uuid`, детей у права нет;
- неизвестный `type` — ошибка.

Любая ошибка проверки — ответ 400 `error.validate.param`.

*Хранение* [cg:services/globalrole/service.go#649], запросы — [cg:store/postgres/permission_catalog_queries.go#12]:
1. Группы — таблица `permission_groups` (`name`, `parent_name`, `sort_order` = позиция среди соседей, `i18n`), upsert по `name`.
2. Права — таблица `permissions`, `INSERT … ON CONFLICT (uuid) DO UPDATE` для `name, description, deprecated, group_name, is_hidden, sort_order, i18n` [cg:store/postgres/role_service_queries.go#4445]. Если с другим UUID приходит уже занятое имя, база отказывает по уникальности. Это превращается в `409 error.permission.name.conflict` [cg:services/globalrole/service.go#692].
3. Права пространства, которых нет в присланном дереве, помечаются `deprecated = TRUE` (`DeprecateGlobalPermissionsNotIn`, сравнение по UUID) [cg:store/postgres/permission_catalog_queries.go#86].
4. Группы пространства, которых нет в дереве и в которых не осталось прав и подгрупп, удаляются (`DeleteUnusedPermissionGroups`).

Облако регистрирует свои пространства (`core`, `axxon_data`, `monitoring`, `sip`, `update_server`) тем же методом при миграции. `incident_manager` в его затравке нет [cg:model/permissions/catalog.go#42]. Значит, пространство `incident_manager` целиком принадлежит сервису.

*Что отдаёт `/me` и introspect после регистрации.*
- Код построения дерева `capabilities` на ветке не менялся: `capabilities.go` того же размера, что в `develop`, функция `BuildCapabilitiesTreeFromPerms` [cg:model/permissions/capabilities.go#67]. Для каталога МИ дерево будет таким:

  ```
  incident_manager → ""                 → actions.manage
                   → "incidents"        → take{scopes:[own,any]}, close, track, assign, suspend, process
                   → "incidents.filter" → edit
  ```

- Introspect (`/api/v1/auth/introspect-user-token`) отдаёт права списком имён. Код ветка не трогала. Список прав пользователя собирается запросом `ListUserGlobalPermissionNames`: группы пользователя → их глобальные роли → права ролей. Признак `deprecated` запрос не проверяет [cg:store/postgres/permission_service_queries.go#150]. Проверка `IsUserHasGlobalPermission` его тоже не проверяет (строка 88).
- Вывод: что зарегистрировано и назначено роли, то сервер МИ и получит в `permissions[]`. Оговорка: что introspect берёт права именно этим запросом, не прослежено — файл `appservices/user/auth.go` (81 КБ) не дочитан.
- Каталог для экрана ролей отдаёт `GET /api/v3/ac-backend/roles/global/permissions/catalog`. Нужно право `core.global_roles.role.manage` [cg:appservices/globalroles/global_roles.go#310], [cg:api/backend.swagger.yaml#13125]. Сервер отдаёт и устаревшие листья с `deprecated: true` — отфильтровывает их фронт (п. 3).

*Сверка с клиентом сервера МИ — поле в поле.* Сервер МИ шлёт `PUT {internal}/ac/v1/global-permissions/catalog`, тело — `json.Marshal(model.PermissionCatalog())` [im:internal/externalclient/cloud/client.go#138].

| Поле `CatalogNode` в МИ [im:internal/im/model/permission.go#46] | В облаке | Совпадает |
|---|---|---|
| `uuid,omitempty` | `uuid,omitempty` | да |
| `name` | `name` | да |
| `type`: `view_group` / `permission` [im:internal/im/model/permission_catalog.go#4] | те же константы | да |
| `description,omitempty` | `description,omitempty` | да |
| `i18n`: `{"en":{"title"},"ru":{"title"}}` | `{"<локаль>":{"title","description"}}` | да; `description` у МИ нет, не обязателен |
| `children,omitempty` | `children,omitempty` | да |
| — | `deprecated`, `isHidden` | у МИ нет — по умолчанию `false`, это верно |

Имена МИ проходят проверки облака:
- корень `incident_manager`;
- группы `incident_manager.administration`, `incident_manager.incidents`;
- 9 прав с правильными UUID и действиями `manage, take, close, edit, track, assign, suspend, process`.

Метод, путь и `Content-Type` совпадают. Облако отвечает `200` — а сервер МИ ждёт именно `200` [im:internal/util/httputils/client.go#21]. Вывод: формат совпадает полностью.

*Что будет в разных случаях.*
- **Повторная регистрация того же дерева.** Тот же результат, ошибки нет: upsert по UUID и по имени группы.
- **Переименование права с тем же UUID.** Меняется `name`, связь с ролями сохраняется: роли хранят UUID права (`global_role_permissions.permission_uuid`). Вывод: так безопасно переименовывать и делить права. Например, `incidents.assign` → `incidents.assign.own` с прежним UUID.
- **Право убрано из каталога МИ.** В облаке оно становится `deprecated`, но не удаляется и с ролей не снимается. Introspect продолжает его отдавать (см. выше). Новые назначения облако запрещает: `error.permission.deprecated` в `resolveAssignableGlobalPermission` (PR #2342). Фронт при сохранении роли предупреждает «Эти права устарели и будут сняты с роли» и снимает их (п. 3). Вывод: чтобы право действительно перестало действовать, сервер МИ должен перестать его признавать. Сервер и так отбрасывает неизвестные имена [im:internal/im/model/permission.go#74].
- **Право вернули в каталог.** `deprecated` снова `false`: upsert перезаписывает поле.
- **Старое `incident_manager.incidents.view`.** Его когда-то регистрировали через `POST`, в коммите `5dac768` сервера МИ оно удалено. На первом же `PUT` оно станет `deprecated`: пространство одно, UUID в новом дереве нет.
- **Несколько экземпляров сервера МИ стартуют одновременно.** Каждый шлёт `PUT` и делает одну транзакцию. Вставки идут в одном порядке: обход дерева один и тот же. Вывод: вторая транзакция ждёт блокировку строк первой и пишет то же самое; ошибок и гонок по данным не видно. Предположение: взаимная блокировка маловероятна — порядок вставок совпадает.
- **Разные версии каталога при поэтапном обновлении.** Побеждает тот, кто записал последним. Старый экземпляр после перезапуска пометит новые права `deprecated`, а убранные — вернёт. На действующие права пользователей это не влияет, только на редактор ролей.
- **Облако недоступно при старте.** Сервер МИ не стартует: ошибка в `Start` [im:internal/im/appservice/appservice.go#530], тайм-аут 10 с, без повторов.

**Сравнение с `develop` облака.** В `develop` маршрута `…/catalog` нет, `POST /ac/v1/global-permissions` принимает плоский список `[{uuid, name, description}]` ([04](04-axxoncloudgo.md#права-и-acl)); файлов `catalog*.go` в `model/permissions/` нет (проверено обзором каталога на `0228c7a`). На ветке `POST` тоже есть и принимает расширенное тело (`group`, `order`, `deprecated`, `isHidden`, `i18n`); старое тело по-прежнему работает, право кладётся в группу-пространство (тест `TestS2SRegisterGlobalPermissionsLegacyBodyStillWorks`, PR #2339) [cg:services/globalrole/service.go#618].

**Вывод для стенда.** Сервер МИ поднимается рядом с облаком ветки `epic/CLOUD-23284-perms-i18n`. Чтобы он работал и с `develop`, нужен запасной путь: на `404` от `PUT …/catalog` слать `POST /ac/v1/global-permissions` плоским списком — его принимают обе ветки.

**Доказательства:** ссылки выше; тесты облака `TestS2SReplaceGlobalPermissionCatalog`, `TestS2SReplaceGlobalPermissionCatalogRejectsForeignNamespace` (PR #2339) проверяют именно пространство `incident_manager`.

**Уверенность:** подтверждено кодом. Не прослежено, что introspect берёт права запросом `ListUserGlobalPermissionNames` (вывод).

**Что спросить у людей** (команда облака, автор ветки — Asker Shogenov):
- Отдаёт ли introspect права с признаком `deprecated`, и так ли задумано?
- Будет ли у S2S-маршрутов проверка вызывающего сервиса? Сейчас любой из внутренней сети может переписать пространство `incident_manager`.

## 2. Ветка против `develop`, сроки слияния

**Ответ.**

*Облако.*
- Ветка `epic/CLOUD-23284-perms-i18n` ответвилась от `develop` на `f2a77d1` (PR #2298, 2026-09-09).
- В ней 12 влитых PR задач: #2302, #2305, #2307, #2314, #2318, #2320, #2332, #2334, #2335, #2339, #2342, #2344.
- Последний коммит `e51bd55` — 2026-10-01 (PR #2344 «custom groups. migrate groups and permissions»). После этого в ветке ничего нет.
- В `develop` после точки ответвления влито около 55 PR. Последний — `0228c7a`, 2026-10-27: подсчёт по `list_pull_requests`, цель `develop`, состояние MERGED.
- Открытых PR в репозитории нет совсем (`state=OPEN` → 0), в том числе ветка → `develop`.

*Фронт.*
- Ветка `CLOUD-23284-epic-perms-catalog` ответвилась от `develop` на `7c6265d` (2026-09-17).
- В ней 3 PR: #1457 «add permissions catalog», #1460 «customize group names and permissions for OEM», #1463 «unused strings». Последний — `83a04e5`, 2026-10-12.
- В `develop` фронта после ответвления около 19 PR. Среди них #1464 «Запретить создание глобальных ролей без пермишена User groups: Manage» правит тот же экран ролей, #1461 — «support sip capabilities».
- Открытых PR нет.

*Вывод: что придётся сделать при слиянии.*
- Облако проверяет при старте: каждое право реестра должно стоять в дереве каталога (`CloudCatalogTrees`, [cg:model/permissions/catalog.go#21]; `ValidateGlobalPermissions`).
- В `develop` после ответвления добавлены права: PR #2349 «classifier v2 perm», PR #2377 DANV-9228 «custom webapp new perms». Пространство `classifier` есть в `develop` ([04](04-axxoncloudgo.md#права-и-acl)), а на ветке его нет [cg:model/permissions/permissions.go#272].
- Значит, ветку нужно догнать и дописать каталог, иначе облако не стартует.

*Номера задач в именах.*
- Облако: CLOUD-23284 (эпик), CLOUD-23409, 23410, 23411, 23412, 23413, 23414, 23415, 23520, 23521, 23522, 23523, 23524.
- Фронт: CLOUD-23460, 23597, 23598.
- Сервер МИ: CLOUD-23650 (каталог прав МИ, коммит `5dac768` того же автора, что и эпик облака).

**Доказательства:** `list_commits` по ветке и по `develop`; `list_pull_requests` (ALL, MERGED, OPEN) в `axxoncloudgo` и `axxoncloud-ui`; `list_branches` с фильтром `23284` — по одной ветке в каждом репозитории.

**Уверенность:** подтверждено (история Bitbucket). Даты слияния в коде нет.

**Что спросить у людей** (команда облака: Asker Shogenov, ревьюер Nazir Bavizhev; фронт — Petr Khoraskin):
- Когда эпик CLOUD-23284 вливается в `develop` и в какой релиз (4.0.x?)?
- Бэкенд и фронт вливаются вместе?
- Можно ли до слияния поднять стенд облака с этой веткой для сервера МИ?

## 3. Фронт облака на ветке каталога

**Ответ.**

*Экран назначения прав* — «Системные настройки → Глобальные роли» (`SystemSettingsGlobalRoles`).
- На ветке экран запрашивает дерево `GET /api/v3/ac-backend/roles/global/permissions/catalog` (`getGlobalPermissionsCatalog`, PR #1457) и строит форму из него: `catalogToFormPermissions` [ui:app/components/SystemSettingsGlobalRoles/utils.ts#29].
- `view_group` превращается в группу, пустые группы не показываются. `permission` превращается в флажок; устаревшие (`deprecated`) и скрытые (`isHidden`) листья пропускаются.
- Порядок — как в массиве `children`: облако хранит его в `sort_order`.
- Назначать можно только листья, не устаревшие и не скрытые: `assignablePermissionNames` (строка 87).
- В `develop` фронта форма собрана по жёсткой карте групп, `categorizePermissions` (удалённый код в PR #1457). Любое право МИ попало бы там в группу «unknown», а подпись — ключ `roles.permission.<имя>`, для которого перевода нет.

*Переводы.*
- Подпись берётся так: сначала строка фронта `roles.permission.<имя>` или `roles.permission-group.<имя-в-kebab-case>`, если она есть (OEM может переопределить подпись, PR #1460). Иначе — `i18n` из каталога.
- Порядок поиска в `i18n`: полная локаль → короткая (`pt_br` → `pt`) → `en` → любая. Если не нашлось ничего — имя права (`catalogTitle` [ui:app/components/SystemSettingsGlobalRoles/utils.ts#7]).
- Вывод: у МИ только `en` и `ru`, поэтому на остальных 31 языке облака подписи прав МИ будут английскими. Своих строк фронта для МИ нет.

*Устаревшие права в роли.*
- Перед сохранением фронт показывает диалог «Эти права устарели и будут сняты с роли: …» (`assignedDeprecatedPermissions` [ui:app/components/SystemSettingsGlobalRoles/utils.ts#90]; ключ `roles.permission.deprecated.remove.warning`, PR #1457).
- Затем отправляет роль без них: `fromAdminToolsRole` фильтрует по назначаемым.

*Разбор `capabilities`* (`app/utils/capabilities.ts`).
- На ветке файл не менялся. `ACTIONS` — те же 15 глаголов: `create, view, edit, delete, manage, use, run, share, export, import, download, apply, bind, encrypt, block` [ui:app/utils/capabilities.ts#7].
- `NAMESPACES` — 6, без `sip` (строка 27); `sip` добавлен в `develop` PR #1461.
- Строка права с неизвестным глаголом разбирается в `null` (строка 73), и `hasCapability` даёт `false`.
- Итог: `take, close, assign, suspend, process, track` и любые новые глаголы из каталога сервиса фронт по-прежнему **не распознаёт**. Распознаёт `incident_manager.manage`, `incident_manager.incidents.filter.edit` и всё, что кончается на глагол из списка (`…use`, `…run`, `…view`). Проверка одного пространства `incident_manager` работает: она смотрит дерево напрямую, без списка глаголов («Namespace-only», строка 55 и `hasCapability`).

*Меню.*
- Пункт `incidentManager` рисует внешний пакет `@axxon-web/cloud-menu`, ему передаётся дерево `capabilities` ([06](06-axxoncloud-ui.md#как-подключаются-приложения-и-im)). Сам портал право `incident_manager.*` для меню не проверяет.
- Вывод: если пакет проверяет `incident_manager` (только пространство), пункт виден любому, у кого есть хоть одно право МИ. Если пакет проверяет конкретное право с глаголом МИ (`…take`), пункт не будет виден никогда.
- Исходников пакета в `PROJ` нет — не проверено.

*Ветка `DANV-6795-localize-new-permission`.*
- Её вершина `2132c4a` — обычный мерж-коммит `develop` от 2025-12-08 (PR #1207 «CLOUD-20760 supp user block unblock»). Своих коммитов поверх `develop` того времени в ней нет.
- Вывод: старая ветка, к каталогу прав и к МИ отношения не имеет.

**Доказательства:** ссылки выше; диффы PR #1457 и #1460 (`get_diff`).

**Уверенность:** экран ролей, переводы и `capabilities.ts` подтверждены кодом. Меню не проверено — пакет внешний.

**Что спросить у людей** (фронт облака, Petr Khoraskin):
- По какому праву пакет `@axxon-web/cloud-menu` показывает пункт `incidentManager`? Можно ли добавить пункт «Оператор»?
- Будут ли `ACTIONS` в `capabilities.ts` брать глаголы из каталога (или расширены `take/close/assign/suspend/process/track`)?
- Нужны ли переводы прав МИ на все 33 языка облака, и кто их делает: сервер МИ в `i18n` или фронт строками?

## 4. Свои глаголы и пространство для состояния оператора

**Ответ.** Глаголы и пространства зашиты в код облака — и на ветке, и в `develop`.

- Пространства — `nameSpaceMap`: `core, axxon_data, monitoring, update_server, sip, incident_manager, domains` [cg:model/permissions/permissions.go#272]. В `develop` есть ещё `classifier` ([04](04-axxoncloudgo.md#права-и-acl)).
- Действия — `actionsMap`, 21 штука, включая `take, close, track, assign, suspend, process` [cg:model/permissions/permissions.go#287].
- Области — `own`, `any` (строка 282).
- `IsValidPermissionName` требует известное пространство и чтобы последний сегмент (или предпоследний перед областью) был действием из списка [cg:model/permissions/methods.go#51]. Его вызывает и `Flatten` каталога, и `POST`.
- Значит, `incident_manager.incidents.release`, `…reopen`, `…bulk` и пространство `agent` облако отвергнет (400). Добавить их можно только правкой кода облака (`actionsMap`, `nameSpaceMap`), а для `hasCapability` — ещё и фронта (`ACTIONS`).

Без правки облака:
- Сегменты в середине имени — свободные ресурсы. Глагол МИ можно сделать ресурсом, а действием взять разрешённое: `incident_manager.incidents.release.use`, `incident_manager.incidents.reopen.use`, `incident_manager.incidents.bulk.use`, `incident_manager.agent.not_ready.use`.
- Все такие имена проходят проверку облака. Они видны `hasCapability`: `use` есть во фронте.
- Пространство для состояния оператора — ресурс `agent` внутри `incident_manager`: своё пространство сервису не завести.

Вывод:
- Если облако позже добавит глаголы, права можно переименовать с тем же UUID — назначения в ролях сохранятся (п. 1).
- Таблица соответствия ключей машины именам облака должна жить в сервере МИ: `ParseExternalPermissions` сейчас пропускает только имена из `AllPermissionsInfo` [im:internal/im/model/permission.go#74]. Контракт оператора (`session.permissions` с ключами `incident:*`) тогда не меняется.

**Доказательства:** ссылки выше; тест облака `TestCreateGlobalRoles` на ветке отвергает `incident_manager.incidents` как право — `BadPermissionsFormat`, PR #2314.

**Уверенность:** подтверждено кодом (ветка и `develop`).

**Что спросить у людей** (команда облака): согласны ли добавить в `actionsMap` глаголы `release`, `reopen`, `bulk` (и во фронт — `take, close, assign, suspend, process, track` и новые)? Или принимаем схему «глагол-ресурс + `use`»?

## 5. Глобальные или доменные права, как назначаются

**Ответ.**
- Каталог сервиса задаёт **только глобальные** права. `validateGlobalCatalogName` отвергает пространство `domains` [cg:model/permissions/methods.go#290]. Доменные права — отдельный статический реестр `allDomainPermissions` в коде облака, назначаются через доменные роли и политики «узел пользователей × узел доменов» ([04](04-axxoncloudgo.md#права-и-acl)).
- Назначение глобальных прав: **группа пользователей → одна глобальная роль** (`user_groups.global_role_id`) → права роли (`global_role_permissions`, по UUID). Права пользователя — объединение прав ролей всех его групп [cg:store/postgres/permission_service_queries.go#150].
- Назначить роль группе можно с правом `core.global_roles.role.apply` (кроме групп LDAP) [cg:appservices/globalroles/global_roles.go#221]. Править роли — с `core.global_roles.role.manage`.
- «Оператор видит только свои объекты» каталогом не выразить. Это делает сам сервер МИ: правила доступа «группа пользователей облака → устройство / тип устройства / тип события / группа устройств», список не-менеджера фильтруется SQL-соединением ([03](03-im-server.md#права)).
- Вывод: ключ видимости — группа пользователей облака, та же, через которую назначаются права. Это совпадает с «группами доступа» правил (§5), только у правил ключ — роль.
- Ветка `feature/CLOUD-23281-epic-acl` (PR #2351, #2379, #2384 «doma.ai object_acl», последний влит 2026-10-28) — объектные ACL. Не изучалась. Предположение: может дать права на отдельные объекты, но сделана под doma.ai.

**Доказательства:** ссылки выше.

**Уверенность:** подтверждено кодом. Object ACL не изучали.

**Что спросить у людей:**
- Продакт МИ: достаточно ли видимости по группам пользователей облака? Или нужны роли как в правилах §5?
- Команда облака: годится ли object ACL (`CLOUD-23281`) для «камеры и группы устройств оператора», и когда он будет в `develop`?

## 6. Соответствие 14 прав машины

Источники:
- права машины — [`workflow_schema.v1.json`](../../Specification/Workflow_machine/workflow_schema.v1.json) (`permissions`, строка 130) и [правила §5](../../Specification/State_rules/States%20rules%20IM.md);
- каталог сервера МИ — [im:internal/im/model/permissions_info.go#3];
- таблица «Права» — [00-summary](00-summary.md#права).

Принцип: имена — только с глаголами облака. Где глагола нет — «глагол МИ как ресурс + `use`». Существующие UUID сохраняем.

| Право машины | Что разрешает (§5) | Сейчас в каталоге МИ | Предлагаемое имя в облаке | Что изменить в каталоге МИ | Редактор ролей (фронт, ветка) | `hasCapability` (фронт) |
|---|---|---|---|---|---|---|
| `incident:claim` | взять, возобновить свой | `incident_manager.incidents.take.own` | то же | ничего | виден | нет (`take`) |
| `incident:accept` | принять передачу | `incident_manager.incidents.process` | то же | подпись «Принимать переданные» | виден | нет (`process`) |
| `incident:hold` | отложить свой | `incident_manager.incidents.suspend` | то же | ничего | виден | нет (`suspend`) |
| `incident:release` | вернуть в очередь, отклонить | — | `incident_manager.incidents.release.use` | добавить, новый UUID | виден | да |
| `incident:close` | закрыть свой с результатом | `incident_manager.incidents.close` | то же | ничего | виден | нет (`close`) |
| `incident:close:unprocessed` | «Массовый сбой» без сценария | — | `incident_manager.incidents.unprocessed.close` | добавить | виден | нет (`close`) |
| `incident:reopen` | переоткрыть | — | `incident_manager.incidents.reopen.use` | добавить | виден | да |
| `incident:transfer:own` | передать своё, ничьё, адресованное мне | `incident_manager.incidents.assign` (одно на оба) | `incident_manager.incidents.assign.own` | переименовать `incidents.assign` **с тем же UUID** `019f93e1-…` | виден | нет (`assign`) |
| `incident:transfer:any` | передать чужое | — | `incident_manager.incidents.assign.any` | добавить, новый UUID | виден | нет |
| `incident:reassign` | перехватить | `incident_manager.incidents.take.any` | то же | ничего; убрать его проверку из `GET /incidents` (п. 7) | виден | нет |
| `incident:bulk` | обработать несколько как один | — | `incident_manager.incidents.bulk.use` | добавить | виден | да |
| `incident:run_action` | макросы и команды | — | `incident_manager.incidents.actions.run` | добавить | виден | да |
| `incident:schema:admin` | схема, нормативы, автоэскалация | `incident_manager.manage` | то же | ничего; решить про «надмножество» (ниже) | виден | да |
| `agent:set_not_ready` | перерыв | — | `incident_manager.agent.not_ready.use` (новая группа `incident_manager.agent`) | добавить | виден | да |
| — | — | `incident_manager.incidents.filter.edit` | — | убрать | — | да |
| — | — | `incident_manager.incidents.track` | — | убрать или уточнить у продакта | — | нет |

Итог по каталогу сервера МИ:
- оставить 6 прав: `manage, take.own, take.any, close, suspend, process`;
- переименовать 1 с прежним UUID: `assign` → `assign.own`;
- добавить 7: `assign.any, release.use, unprocessed.close, reopen.use, bulk.use, actions.run, agent.not_ready.use`;
- убрать 2: `filter.edit`, `track`.
- Кроме того: дописать их в `AllPermissionsInfo` и в таблицу «ключ машины ↔ имя облака» в сервере МИ; подписи `en`/`ru` дать для каждого узла (тест `TestPermissionCatalog` это проверяет [im:internal/im/model/permission_catalog_test.go#5]); поправить в тесте число прав в группе (8).

**`filter.edit` и `track`.**
- В машине аналогов нет. Вкладки-фильтры из контракта убраны ([03](03-im-server.md#права)). Видимость инцидентов по правилам задают группы доступа, а не право (§5).
- Предлагаем убрать оба права из каталога. После следующего `PUT` облако пометит их `deprecated`; редактор ролей предупредит и снимет их с ролей при сохранении (п. 3). Сервер МИ перестанет их признавать, как только их не будет в `AllPermissionsInfo`.
- Если продакту нужен «наблюдатель» (видеть чужую работу без действий), это отдельное решение. Его стоит записать в правила, а не держать `track` в каталоге без смысла.

**`manage` как надмножество.**
- `Permissions.Has` считает `manage` любым правом [im:internal/im/model/permission.go#68]. В машине администратор и оператор — разные наборы: в примере ролей `incident:schema:admin` нет у роли с полным набором операторских прав, [`workflow_schema.v1.json`](../../Specification/Workflow_machine/workflow_schema.v1.json) строки 1547–1552.
- Вывод: для операторских переходов надмножество лучше не применять. Иначе администратор схемы получает, например, перехват, которого ему не давали. Решение — за командой бэкенда МИ и продактом.

**Уверенность:** таблица — наше предложение (вывод). Допустимость имён проверена по правилам облака на ветке. Колонка фронта — по коду ветки.

**Что спросить у людей:**
- Продакт МИ: убираем ли `filter.edit` и `track`? Нужен ли «наблюдатель»?
- Команда облака: схема «глагол-ресурс + `use`» или новые глаголы?
- Бэкенд МИ: согласны ли переименовать `incidents.assign` с прежним UUID?

## 7. `GET /incidents/{guid}` только для `manage`

**Ответ. Подтверждаю.**
- `GetIncident` первым делом требует `PermManage` [im:internal/im/appservice/incident/incident.go#69]. Дальше `IsManager()` у прошедшего проверку всегда истинен — он ищет то же `PermManage` [im:internal/im/model/user.go#16]. Ветка с фильтром по правилам доступа (строки 78–80) недостижима.
- Итог: оператор без `manage` получает 403 на любую карточку, а у менеджера правила доступа не применяются.
- История: проверка была `PermUnrestricted` с первого появления слоя (`5f1de46`, 2026-07-03), в `2cd668d` (2026-07-24) заменена на `PermManage`. Вывод: это недосмотр при переходе на права облака, а не замысел — иначе ACL-ветку не писали бы.

**Рядом ещё одна неточность.**
- `GetIncidents` требует `incident_manager.incidents.take.any` [im:internal/im/appservice/incident/incident.go#55]. В коммите `5dac768` оно заменило удалённое `incidents.view`.
- По таблице п. 6 `take.any` — это перехват (`incident:reassign`). Оператор с обычным набором прав (`claim`, без перехвата) очередь не увидит.

**Какое право должно быть.**
- По правилам §5 отдельного права «видеть» нет. Инцидент виден оператору, если устройство-источник доступно его группам доступа — «вне них инцидент не виден никак — ни в очереди, ни карточкой». Значит, для `GET /incidents` и `GET /incidents/{guid}` одинаково:
  1. допуск — любое операторское право МИ (хотя бы одно из списка п. 6, кроме `manage`) или `manage`;
  2. выборка — для не-менеджера всегда через `access_rules` (`GetIncidentByUserGroupIDs`), для менеджера — всё.
- Второй вариант — вернуть право `incident_manager.incidents.view` («работать с очередью»). Тогда старый UUID `019f93cb-094a-74c1-9687-6caeb286c4d8` вернёт его из `deprecated` с прежними назначениями. Но такого права нет в машине, его пришлось бы добавить и в правила.

**Доказательства:** ссылки выше; `git log -L` по `incident.go`.

**Уверенность:** подтверждено кодом. Какое право правильное — вывод из правил §5.

**Что спросить у людей** (команда бэкенда МИ): чинить по варианту 1 (любое операторское право + ACL) или вводить `incidents.view`? Убрать ли `take.any` из `GET /incidents`?

## Поправки к первому кругу

- **00-summary, «Коротко» и «Права»: «вне демо-режима сервер МИ с этим облаком не стартует».** Верно только для `develop` облака (`0228c7a`). На ветке `epic/CLOUD-23284-perms-i18n` (`e51bd55`) маршрут `PUT /ac/v1/global-permissions/catalog` есть [cg:handler/s2s/init.go#65], формат совпадает с сервером МИ поле в поле (п. 1). С облаком этой ветки сервер МИ стартует.
- **00-summary, «Локальный стенд», п. 4: «нужна ветка облака с этим маршрутом или правка сервера МИ на `POST`».** Ветка найдена — `epic/CLOUD-23284-perms-i18n`. Для работы и с `develop` нужен запасной `POST` при `404` (п. 1).
- **00-summary, «Права», таблица, колонка «Видно во фронте портала».** Колонку надо разделить.
  - Редактор глобальных ролей на ветке фронта показывает и даёт назначить **любое** право из каталога — глагол не важен (п. 3).
  - `hasCapability` по-прежнему не видит `take/close/assign/suspend/process/track` — на ветке так же, как в `develop`.
  - Строки `release`, `reopen`, `bulk`, `set_not_ready` с «глагола нет» — верно. Выход — схема «ресурс + `use`» (п. 4, 6).
- **00-summary, «Права», вывод (3): «облако хранит одно действие с двумя областями».** Верно для дерева `capabilities`. Но в каталоге и в ролях `take.own` и `take.any` — два отдельных права с разными UUID.
- **00-summary, «Вопросы»: «Где маршрут `PUT …/catalog`… когда в `develop`?».** Где — ответ есть (п. 1). Когда — в коде нет, открытых PR нет, вопрос к команде облака остаётся (п. 2).
- **03, «Права»: «При старте сервер отправляет каталог в облако (`PUT …/catalog`); облако назначает права».** Отправляет — верно. Работает только с облаком ветки `epic/CLOUD-23284-perms-i18n`. Облако права не назначает: оно хранит каталог, а назначает администратор — права в глобальную роль, роль группе пользователей. Таблица «Где проверяется»: у `take.any` проверка в `GET /incidents` — по смыслу ошибка (п. 7).
- **04, «Права и ACL»: «Свой каталог прав сервиса — `POST /ac/v1/global-permissions` с телом `[{uuid, name, description}]`».** Верно для `develop`. На ветке есть ещё `PUT …/catalog` с деревом, а `POST` принимает расширенное тело (п. 1).
- **04, «Ветки вне develop»: «`epic/CLOUD-23284-perms-i18n` (переводы названий прав)».** Не только переводы. Это каталог прав с группами `view_group`, сортировкой, `i18n` на 33 языках, скрытыми и устаревшими правами, S2S-регистрация каталога сервисом и экран каталога в API v3 (п. 1–2).
- **04, «Как подключается внешний сервис», п. 3: «при старте — `POST`…».** Уже поправлено в 00. Уточнение: на ветке облака `PUT …/catalog` — штатный путь регистрации.
- **06, «Права в интерфейсе».** Описано по `develop`. На ветке `CLOUD-23284-epic-perms-catalog` экран глобальных ролей строится по каталогу с сервера: группы, порядок, переводы из `i18n` с откатом на `en`. В `develop` права МИ попали бы в группу «unknown» с непереведённым ключом (п. 3). `capabilities.ts` на ветке тот же, без `sip`.
- **02, «Права».** Поправка из 00 остаётся верной: пространство `incident_manager` наполняет каталог сервера МИ, облако хранит его и отдаёт в `/me`. Других расхождений по правам не нашли.

## Открытые вопросы (сводно)

1. Команда облака: срок и релиз слияния CLOUD-23284 в `develop`; стенд с веткой для сервера МИ (п. 2).
2. Команда облака: новые глаголы (`release`, `reopen`, `bulk`) или схема «ресурс + `use`»; расширение `ACTIONS` во фронте (п. 4).
3. Команда облака: отдаёт ли introspect `deprecated`-права и так ли задумано; защита S2S-маршрута каталога (п. 1).
4. Фронт облака: по какому праву `@axxon-web/cloud-menu` показывает `incidentManager`; переводы прав МИ на 33 языка (п. 3).
5. Продакт МИ: убрать `filter.edit` и `track`; нужен ли «наблюдатель»; ключ видимости — группа пользователей или роль (п. 5, 6).
6. Бэкенд МИ: исправление `GET /incidents/{guid}` и `GET /incidents` (п. 7); `manage` как надмножество; переименование `assign` с прежним UUID; запасной `POST` для `develop` (п. 1, 6).

## Ссылки

[cg:handler/s2s/init.go#65]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/handler/s2s/init.go?at=e51bd552b593db9fdedba16505808bde48b1db96#65
[cg:model/urls.go#506]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/model/urls.go?at=e51bd552b593db9fdedba16505808bde48b1db96#506
[cg:handler/rest/auth.go#818]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/handler/rest/auth.go?at=e51bd552b593db9fdedba16505808bde48b1db96#818
[cg:appservices/globalroles/global_roles.go#339]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/appservices/globalroles/global_roles.go?at=e51bd552b593db9fdedba16505808bde48b1db96#339
[cg:appservices/globalroles/global_roles.go#310]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/appservices/globalroles/global_roles.go?at=e51bd552b593db9fdedba16505808bde48b1db96#310
[cg:appservices/globalroles/global_roles.go#221]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/appservices/globalroles/global_roles.go?at=e51bd552b593db9fdedba16505808bde48b1db96#221
[cg:services/globalrole/service.go#649]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/services/globalrole/service.go?at=e51bd552b593db9fdedba16505808bde48b1db96#649
[cg:services/globalrole/service.go#618]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/services/globalrole/service.go?at=e51bd552b593db9fdedba16505808bde48b1db96#618
[cg:services/globalrole/service.go#692]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/services/globalrole/service.go?at=e51bd552b593db9fdedba16505808bde48b1db96#692
[cg:model/permissions/permissions.go#83]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/model/permissions/permissions.go?at=e51bd552b593db9fdedba16505808bde48b1db96#83
[cg:model/permissions/permissions.go#272]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/model/permissions/permissions.go?at=e51bd552b593db9fdedba16505808bde48b1db96#272
[cg:model/permissions/permissions.go#287]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/model/permissions/permissions.go?at=e51bd552b593db9fdedba16505808bde48b1db96#287
[cg:model/permissions/catalog_snapshot.go#12]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/model/permissions/catalog_snapshot.go?at=e51bd552b593db9fdedba16505808bde48b1db96#12
[cg:model/permissions/catalog.go#21]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/model/permissions/catalog.go?at=e51bd552b593db9fdedba16505808bde48b1db96#21
[cg:model/permissions/catalog.go#42]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/model/permissions/catalog.go?at=e51bd552b593db9fdedba16505808bde48b1db96#42
[cg:model/permissions/methods.go#51]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/model/permissions/methods.go?at=e51bd552b593db9fdedba16505808bde48b1db96#51
[cg:model/permissions/methods.go#283]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/model/permissions/methods.go?at=e51bd552b593db9fdedba16505808bde48b1db96#283
[cg:model/permissions/methods.go#290]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/model/permissions/methods.go?at=e51bd552b593db9fdedba16505808bde48b1db96#290
[cg:model/permissions/capabilities.go#67]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/model/permissions/capabilities.go?at=e51bd552b593db9fdedba16505808bde48b1db96#67
[cg:store/postgres/permission_catalog_queries.go#12]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/store/postgres/permission_catalog_queries.go?at=e51bd552b593db9fdedba16505808bde48b1db96#12
[cg:store/postgres/permission_catalog_queries.go#86]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/store/postgres/permission_catalog_queries.go?at=e51bd552b593db9fdedba16505808bde48b1db96#86
[cg:store/postgres/role_service_queries.go#4445]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/store/postgres/role_service_queries.go?at=e51bd552b593db9fdedba16505808bde48b1db96#4445
[cg:store/postgres/permission_service_queries.go#150]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/store/postgres/permission_service_queries.go?at=e51bd552b593db9fdedba16505808bde48b1db96#150
[cg:api/backend.swagger.yaml#13125]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/api/backend.swagger.yaml?at=e51bd552b593db9fdedba16505808bde48b1db96#13125
[ui:app/utils/capabilities.ts#7]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/utils/capabilities.ts?at=83a04e587c90809e10c4efb4b5a57ce29a335174#7
[ui:app/components/SystemSettingsGlobalRoles/utils.ts#7]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/components/SystemSettingsGlobalRoles/utils.ts?at=83a04e587c90809e10c4efb4b5a57ce29a335174#7
[ui:app/components/SystemSettingsGlobalRoles/utils.ts#29]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/components/SystemSettingsGlobalRoles/utils.ts?at=83a04e587c90809e10c4efb4b5a57ce29a335174#29
[ui:app/components/SystemSettingsGlobalRoles/utils.ts#90]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/components/SystemSettingsGlobalRoles/utils.ts?at=83a04e587c90809e10c4efb4b5a57ce29a335174#90
[im:internal/externalclient/cloud/client.go#138]: https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/externalclient/cloud/client.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#138
[im:internal/im/model/permission.go#46]: https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/model/permission.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#46
[im:internal/im/model/permission.go#68]: https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/model/permission.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#68
[im:internal/im/model/permission.go#74]: https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/model/permission.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#74
[im:internal/im/model/permission_catalog.go#4]: https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/model/permission_catalog.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#4
[im:internal/im/model/permission_catalog_test.go#5]: https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/model/permission_catalog_test.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#5
[im:internal/im/model/permissions_info.go#3]: https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/model/permissions_info.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#3
[im:internal/im/model/user.go#16]: https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/model/user.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#16
[im:internal/im/appservice/appservice.go#530]: https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/appservice/appservice.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#530
[im:internal/im/appservice/incident/incident.go#55]: https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/appservice/incident/incident.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#55
[im:internal/im/appservice/incident/incident.go#69]: https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/appservice/incident/incident.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#69
[im:internal/util/httputils/client.go#21]: https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/util/httputils/client.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#21
