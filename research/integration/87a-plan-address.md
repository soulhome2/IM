# План 87а: источник и адрес в строке и карточке

> **Для агентов-исполнителей:** обязательный навык — superpowers:subagent-driven-development (рекомендуется) или superpowers:executing-plans. Шаги — чекбоксы `- [ ]`. Сервер и конфигуратор — по superpowers:test-driven-development: сначала тест, он падает, потом код.

**Цель:** оператор видит в строке очереди и в карточке, что сработало и где: устройство-источник, его тип и действующий адрес. Ссылки площадки в меню справки снова работают: они привязаны к группе устройств, а не к полю `site`, которое сервер не заполняет.

**Архитектура:**
- **Адрес — у устройства**, две колонки: из источника (пишет только сверка `/sync/sources`) и введённый в МИ (пишет только администратор). Действует введённый в МИ, иначе адрес источника. Адрес группы — заготовка без наследования: «Подставить адрес устройствам группы» пишет его как введённый в МИ.
- Операторский контракт отдаёт в сводке `source` и `address` на момент чтения; `site`, `siteType`, `location` уходят.
- **Ссылка справки** — одна из трёх областей: общая; группы (видна, если источник в группе или вложенной); «не назначена» — старая ссылка площадки, её не видит никто.
- Правка адресов — через прежний API конфигуратора (`api/im/backend.openapi.yaml`, `/api/v1/im-backend/sources…`), где уже правят группы; операторская часть — через контракт IM `openapi.json`.

**Спецификация:** [87-notifications.md](87-notifications.md), раздел «Источник и адрес в строке и карточке». Решения там приняты 2026-11-15, им следовать буквально. Правила: [States rules IM.md](../../Specification/State_rules/States%20rules%20IM.md), §1, §5, §7, §12.4, §14.5, §19.1, §20.

**Где:**
- IM — `/mnt/hgfs/VmWareShared/soul2home/IM`;
- сервер — `~/Work/incident-manager-server`;
- конфигуратор — `~/Work/incident-manager`.

Ветка везде `feature/im_operator`.

## Общие ограничения

- Перед началом — `git fetch` в трёх репозиториях; есть новое — `git pull --ff-only`, не выходит — остановиться.
- IM: прототип логику правил не держит; сгенерированные файлы (`prototype/openapi.js`, `fixture.js`, `strings.js`, `openapi.v30.json`, `SETTINGS.md`) собирает `python3 tools/build_workflow.py`. `openapi.json` и `Workflow_machine/README.md` — CRLF: `git diff --stat` не должен показывать переписанный целиком файл.
- Сервер: в каждом новом запросе `customer_guid = $N`, у `sources` — ещё `deleted_at IS NULL`, где нужно. Тесты — только на `im-test-db` (`sg docker -c "make test-db-up"`, `make test-local`), не на `imdb`.
- Адрес — одна строка, обрезается по краям; пустая — `NULL` (пустую строку не хранить); больше 500 символов (`char_length`) — 422.
- Журнал инцидента адрес не пишет. Поток отдаёт адрес только тем, кому виден инцидент (строка потока — та же `IncidentSummary`).
- Коммиты — локальные, без push; префикс `Адрес: …`, по-русски, трейлер `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Фокус ревью — 5 опасных входов

1. **Сверка устройств:** `address` нет — не трогать; `""` — стереть; значение — записать. `address_im` сверка не пишет никогда; 501 символ — 422; ETag сверки учитывает адрес.
2. **Старые ссылки площадки не становятся общими** ни при миграции 072, ни при правке без выбора области, ни при восстановлении старой копии с `site`, ни при удалении группы ссылки.
3. **Доступ и заказчик:** `help-links?incidentGuid=` невидимого инцидента — только общие; чужой `groupGuid` — 422; подстановка по дереву не выходит за `customer_guid`; адрес не уходит тем, кому не виден инцидент.
4. **Подстановка по группе:** по умолчанию только устройствам без действующего адреса, `overwrite` — только флажком; удалённые не трогать; число `dryRun` = числу изменённых; одна запись журнала.
5. **Поиск по адресу:** `%`, `_`, `\` экранируются (как в `queueSearchPattern`); адрес удалённого устройства не ищется и не показывается; p95 очереди без поиска не меняется.

## Интерфейсы (общие для всех задач)

**Операторский контракт IM (`Specification/Workflow_machine/openapi.json`):**

| Схема / запрос | Было | Стало |
|---|---|---|
| `IncidentSummary` | `site`, `siteType`, `location` | убраны. Новые поля: `source` — `DeviceRef` или `null` (переезжает сюда из `IncidentCard`); `address` — строка до 500 символов или `null`, действующий адрес источника на момент чтения, у удалённого устройства `null` |
| `IncidentCard` | своё `source` | своего нет, наследует из `IncidentSummary` (`allOf`) |
| `DeviceRef` | `guid, name, typeId, typeLabel, counters` | плюс `deleted` (boolean, по умолчанию false): устройство удалено, экран пишет «устройство удалено» |
| `GET /operator/reference/help-links` | параметр `site` | параметр `incidentGuid` (uuid). Без параметра — все ссылки, для вкладки администрирования. С параметром — общие ссылки и ссылки групп, куда входит источник инцидента (с вложенными). Инцидент не найден или не виден — только общие. Ссылки «не назначена» в меню не попадают никогда |
| `HelpLink` | `site` | убрано. Новые поля: `scope` — `shared`, `group` или `unassigned`, обязательное; `groupGuid` — uuid или `null`; `groupName` — строка или `null`, только чтение; `legacySite` — строка или `null`, только чтение, прежняя площадка ссылки для подсказки «выберите группу» |
| `HelpLinkChange` | `site` | убрано. Новые поля: `scope` — `shared`, `group` или `unassigned`, обязательное; `groupGuid` — uuid или `null`, обязателен при `group`. `unassigned` можно, только если ссылка уже «не назначена» (правка названия без выбора группы). Иначе 422 `HELP_LINK_SCOPE_INVALID`. Группа не найдена или чужая — 422 `HELP_LINK_GROUP_UNKNOWN` |
| `TestIncidentRequest`, `TestEventRequest` | `site`, `location` | убраны: адрес берётся у устройства |
| enum `objectType` в `SettingsAuditEntry`, `AuditObjectSuggestion` и параметре фильтра журнала настроек | … | плюс `source` и `source_group` |
| параметр `search` очереди | номер, тревога, тип | плюс название устройства-источника и его действующий адрес |

**База сервера (`072_device_address.sql`):**
- `sources.address_source TEXT NULL`, `sources.address_im TEXT NULL`. У обеих `CHECK (char_length(…) <= 500)`.
- `source_groups.address TEXT NULL` с тем же CHECK.
- `help_links`: `RENAME COLUMN site TO legacy_site`; новая колонка `group_guid UUID NULL REFERENCES source_groups(guid)`, без каскада; `CHECK (group_guid IS NULL OR legacy_site IS NULL)`; индекс `(customer_guid, group_guid)`
- `settings_audit_object_type_check` — тот же список, что в 069, плюс `'source'` и `'source_group'`.
- Down — обратно. Перед этим `legacy_site` ссылок с группой не восстанавливается. Это записано в комментарии миграции.

**Модель Go:**
- `model.Source.AddressSource`, `AddressIM *string` и метод `Address() *string`.
- `model.SourceGroup.Address *string`.
- `model.SyncSource.Address *string`: `nil` — поля не было.
- `model.HelpLink`: поле `Site` → `LegacySite *string`; новые поля `GroupGUID *uuid.UUID`, `GroupName *string`; метод `Scope() string`.
- Константы `model.SettingsObjectSource = "source"`, `model.SettingsObjectSourceGroup = "source_group"`.

**Контракт агента (`docs/agent-api/agent.openapi.yaml`, 0.6.0 → 0.7.0):**
- `SyncSource.address` — строка, `maxLength: 500`, необязательное поле, в `required` не входит.
- Пустая строка стирает адрес источника.

**API конфигуратора (`api/im/backend.openapi.yaml`, `make gen-api-im`).** Право — `incident_manager.manage` (`model.PermManage` → `incident:schema:admin`), как у правки групп. Новые поля и запросы:
- В схеме `source`: `addressSource`, `addressIm`, `address` — все строка или `null`. `address` — действующий.
- `PUT /sources/{guid}/address`, тело `{address: string}` (1–500 после обрезки) — ввести адрес в МИ. Ответ 200 — устройство.
- `DELETE /sources/{guid}/address` — «Вернуть адрес из источника» (`address_im = NULL`). Ответ 200 — устройство.
- В схеме группы — `address`, строка или `null`.
- `PUT /sources/groups/{guid}/address` `{address}` и `DELETE /sources/groups/{guid}/address` — адрес группы.
- `POST /sources/groups/{guid}/address/apply`, тело `{overwrite: boolean, dryRun: boolean}`, ответ `{devices: integer}`.; У группы нет адреса — 422 `GROUP_ADDRESS_EMPTY`; Чужое или удалённое — 404

**Журнал настроек (`settings_audit`).** У всех записей `action = update`.

| Что | `object_type`, `object_id` | before → after |
|---|---|---|
| Правка адреса устройства | `source`, guid устройства | `{"addressIm": …}` → `{"addressIm": …}` |
| Возврат к источнику | `source`, guid устройства | `{"addressIm": "X"}` → `{"addressIm": null}` |
| Адрес группы | `source_group`, guid группы | `{"address": …}` → `{"address": …}` |
| Подстановка | `source_group`, guid группы | before `null`, after `{"applyAddress": {"address", "overwrite", "devices"}}` |

Подстановка даёт одну запись, а не по записи на устройство.

## Задача 1. IM: правила и журнал правил

**Репозиторий:** IM. **Модель:** opus. **Ревью:** полное.

**Файлы:** `Specification/State_rules/States rules IM.md`, `Specification/State_rules/CHANGELOG.md`.

- [ ] **§1, словарь.** Новый термин **Адрес**: строка у устройства, до 500 символов, только для показа. Действует введённый в МИ, иначе адрес из источника; У «Площадки» — пометка: в МИ площадка задаётся группой устройств (§19.1), отдельного поля у инцидента нет
- [ ] **§5.** Адрес и ссылки группы видны только тем, кому виден инцидент. В журнал инцидента адрес не пишется.
- [ ] **§7, «В очереди».** Под типом события — «название устройства · адрес». Адрес обрезается многоточием, полный — в подсказке. То же в блоке «Мне на принятие».
- [ ] **§7, поиск.** Поиск находит по номеру, номеру тревоги, типу события, названию устройства и адресу. Площадки и места в поиске больше нет.
- [ ] **§7, «В карточке».** Блок «Источник»: устройство, тип, адрес. Нет адреса — только устройство. Удалённое — «устройство удалено».
- [ ] **§7, «Меню вспомогательных ссылок».** Общие ссылки и ссылки группы устройств (с вложенными); запрос `help-links?incidentGuid=…`; Без открытого инцидента — только общие; Ссылка «не назначена» (прежняя площадка) не показывается никому, конфигуратор помечает её «выберите группу»; При удалении группы её ссылки становятся «не назначена»
- [ ] **§12.4.** В журнале изменений настроек новые объекты «устройство» и «группа устройств». Записи: правка адреса, возврат к источнику, подстановка по группе — одной записью: группа, адрес, число устройств.
- [ ] **§14.5.** Источник и адрес не снимаются в момент события: сводка показывает устройство и его действующий адрес на момент чтения.
- [ ] **§19.1, «Кто ведёт группы».** Адрес устройства: два значения; сверка не затирает адрес, введённый в МИ; кнопка «Вернуть адрес из источника»; Адрес группы — заготовка без наследования. Подстановка с вложенными: по умолчанию только устройствам без адреса, флажок «и тем, у кого уже есть» — с подтверждением и числом устройств; Право — `incident:schema:admin`
- [ ] **§20.** В перечень данных МИ добавить «адреса устройств и групп».
- [ ] **§17, «Отступления».** Прототип правку адресов не показывает — она в конфигураторе.
- [ ] **CHANGELOG.md.** Строка в таблицу «Изменения после v10». Основание: «решения пользователя 2026-11-15, research/integration/87-notifications.md, план 87а». Коммит вписать после коммита.
- [ ] **Проверка:** `python3 tools/check_links.py` без ошибок.

## Задача 2. IM: контракт, строки, сборка

**Репозиторий:** IM. **Модель:** opus. **Ревью:** полное (контракт).

**Файлы:**
- `Specification/Workflow_machine/openapi.json` (CRLF);
- `Specification/Workflow_machine/strings/ru.json`, `en.json`: ключ `workflow.settings.tab.links.what` — «общие и ссылки групп устройств» вместо «site links»;
- описания в `Specification/Workflow_machine/README.md` и `FRONTEND.md`, если там есть `site` или `location` — проверить `grep -n 'site\|location'`.

- [ ] Внести изменения из таблицы «Интерфейсы». Схемы перечисленные: строки 1639–1660 (`help-links`); `IncidentSummary` (~7339); `HelpLink` (~9126); `TestIncidentRequest` и `TestEventRequest` (~9850, ~9888); `HelpLinkChange` (~10258); `DeviceRef`; `IncidentCard`; enum-ы `objectType` — найти по `maintenance_window`
- [ ] `python3 tools/build_workflow.py`, затем все быстрые проверки CLAUDE.md: `build_workflow.py --check`; `check_machine.py` и `--mutations`; `python3 -m unittest tools/test_openapi30.py`; `check_cel.mjs`, `test_cel.mjs`; `cel_vectors.mjs --check`; `gen_quint.mjs --check`; `check_links.py`
- [ ] `python3 tools/check_i18n.py`.
- [ ] **Ожидаемо:** все зелёные. Если `cel_vectors.mjs --check` падает только из-за `site` или `location` в записанных ответах — его чинят задача 3 и `--update` в конце задачи 3.

## Задача 3. IM: эталонный набор, прототип, самопроверка, руководство

**Репозиторий:** IM. **Модель:** opus. **Ревью:** полное.

**Файлы:**
- **`Specification/Workflow_machine/fixtures/demo.json`:** `devices[].address` — адрес из источника. У каждого устройства-источника инцидента собрать «<site>, <location>» из нынешних инцидентов, например «Торговый центр, Магазин 1, торговый зал»; Одному устройству дать `addressIm` (введённый в МИ, отличается); Одному устройству-источнику адрес не давать — показать «только устройство»; `incidents[]`: убрать `site`, `siteType`, `location`; `helpLinks`: `evacuation-mall` → `scope: "group"`, `groupGuid: "30000000-0000-4000-8000-000000000021"` (Торговый центр). Остальные — `scope: "shared"`. Плюс одна ссылка `scope: "unassigned"`, `legacySite: "Складской комплекс"`; `plans[].site` оставить: это подпись плана, а не контракт
- **`prototype/server.js`:** 605 — `HELP_LINKS`; 644–646 — загрузка инцидента: без `site`; 883–885 — сводка: `source` и `address` берутся из `deviceSpec` источника на момент чтения, плюс `deleted`; 1150 — `planOf`: убрать запасной путь `p.site === ev.site`. Сейчас он не срабатывает: у всех источников есть `position`; 1261 — `hit`: номер, тревога, тип, название устройства, адрес; 2058–2059 — `help-links` по `incidentGuid` и группам источника с предками. Прежний помощник дерева групп уже есть в server.js — найти по `sourceGroups`; админские `POST`/`PUT /operator/admin/help-links` — `scope` и 422; 2089–2090, 2389–2390 — без `site` и `location`
- **`prototype/app.js`:** 2404 — строка очереди `event-sub`: под заголовком отдельная строка `event-source` «устройство · адрес», `text-overflow: ellipsis`, `title` — полный адрес; 2693 — шапка карточки: вместо `incident-meta` блок «Источник»; 4232 — вкладка привязанных: устройство вместо `location`; 4488–4501 — меню справки: `{incidentGuid: ev.guid}`, подпись раздела — `groupName`; 4671–4673 — таблица ссылок в «Настройках администратора»: колонка «Группа» или «выберите группу»
- **`prototype/index.html:187`** — подсказка поиска «Поиск по номеру, типу, устройству, адресу…». То же в `prototype/i18n-html.js:94` и связанных строках `i18n-*.js`. Стили — в `prototype/styles.css`.
- **`prototype/selftest.js`:** убрать `site` и `location` из тел `/test/…` (строки 670, 737, 824, 951, 978, 1021, 2563, 2756, 3095); шаг справки 2118–2123 переписать на группы
- **`tests/api-scenarios.js`** (703, 1006, 1391–1394, 1875) и **`tests/api-junction.js`**: отбор по `source.guid` и группам вместо `e.site`, справка — по `incidentGuid`.
- **`Specification/Operator guide.md`:** строка 15 — поиск; описание строки очереди, карточки и меню справки

- [ ] **Сначала тест.** Новый шаг самопроверки `address: источник и адрес` в `prototype/selftest.js`. Проверки: строка инцидента Торгового центра показывает «<устройство> · <адрес>», а у `title` полный адрес; поиск по части адреса находит инцидент, по названию устройства — тоже; в карточке блок «Источник» с типом и адресом; у устройства без адреса — только название; меню справки при открытом инциденте Торгового центра содержит «Схема эвакуации «Мега»», при инциденте Главного офиса — нет; ссылки «не назначена» нет нигде; у устройства с `addressIm` показан он, а не адрес источника. Прогнать — шаг падает.
- [ ] Сделать правки, `python3 tools/build_workflow.py`.
- [ ] **Проверки:** selftest (бюджет 180000), ожидаемо `data-selftest="pass"`; `tests/api.html` (120000), ожидаемо `data-apitest="pass"`; `tests/scenario.html` (20000); `python3 tools/check_ui.py` (~2 мин); `check_guide.py`, `check_i18n.py`; `check_scenarios.py`; `node tools/scenario_vectors.mjs --check`, при расхождении `--update`; `node tools/cel_vectors.mjs --check`; если падает — `--update --tmp=<scratchpad>` (~6 мин), потом `--check`; все быстрые проверки. Полные порчи кода (`check_code_mutations.py`) не гонять, только предложить.
- [ ] **Коммиты IM:** «Адрес: правила и контракт — источник и адрес устройства, ссылки по группе» (задачи 1–2); «Адрес: прототип и эталонный набор» (задача 3); отдельный коммит — хэш в `CHANGELOG.md`

## Задача 4. Сервер: миграция и модель

**Репозиторий:** сервер. **Модель:** opus. **Ревью:** полное (миграция). **Зависит от:** задача 2 (имена).

**Файлы:**
- `internal/im/service/storing/migrations/072_device_address.sql` — следующий номер. Последний — `071_workflow_settings_defaults.sql`;
- `internal/im/model/source.go`, `model/source_group.go` (или где лежит `SourceGroup`), `model/help_link.go`, `model/settings_audit.go`;
- `storing/source_queries.go`: `convertSourceFromAppModel`, чтение `address_source` и `address_im`;
- `storing/source_group_queries.go`;
- `storing/reference_queries.go`: `helpLinksSQL`, `addHelpLinkSQL`, обновление ссылки — `legacy_site`, `group_guid`, имя группы через `LEFT JOIN source_groups`.

- [ ] **Сначала тест** — `storing/address_migration_test.go`: `TestMigration072HelpLinkSiteBecomesUnassigned`: ссылка с `site='ТЦ'` до миграции после неё имеет `legacy_site='ТЦ'`, `group_guid IS NULL`, `Scope()=="unassigned"`. Ссылка без `site` — `shared`; `TestSourceAddressCheck501`: вставка 501 символа нарушает CHECK; `TestSourceAddressEffective`: `Address()` — `address_im`, иначе `address_source`, иначе `nil`. Миграции стартуют сами при запуске (`applyMigrations`). Для первого теста — заготовка строки через `migrate` до 071, затем Up 072; если в тестах такой обвязки нет — проверить на копии стенда в задаче 9 и оставить в тесте только CHECK и `Scope()`.
- [ ] **Проверка:** `make test-local` (или `go test -race ./internal/im/service/storing/...` с `IM_TEST_DB_URL`) — зелёное. `go vet ./...`.

## Задача 5. Сервер: сверка устройств с адресом, контракт агента 0.7.0, эмулятор

**Репозиторий:** сервер. **Модель:** opus. **Ревью:** полное (контракт, сверка). **Параллельно с:** задачи 6 и 7 — после задачи 4.

**Файлы:**
- `docs/agent-api/agent.openapi.yaml`: `version: 0.7.0`, `SyncSource.address`, затем `make gen-api-agent`;
- `docs/agent-api/CHANGELOG.md`: «## 2026-11-16 — 0.7.0», необязательный `address` у устройства при сверке; три случая;
- `docs/agent-api/README.md` — если там перечислены поля устройства;
- новый пример `docs/agent-api/examples/10-sources-address.json`: устройство с адресом, без поля и с `""`;
- `handler/agentapi/sync.go`: `convertGeneratedToSyncSource` переносит `Address`;
- `appservice/sync/sync_source.go`: `getDiffSources` — изменение адреса тоже повод обновить; создание — `address_source` из поля
- `storing/source_queries.go`: `UpdateSource` пишет `address_source`, только если `Address != nil`. Отдельный список колонок; `address_im` не трогать никогда;
- проверка длины — 422, как у других полей, по образцу `examples/error-422.json`;
- **эмулятор `tools/agent-emulator/`:** `data.go` — `emuSource.Address string \`json:"address,omitempty"\``; `link.go` — `etagSource` и `topologyEtag` с адресом; `run.go` — `topology`; `main.go:245` — демо-сверка; `democonfig.go` — адрес из `devices[].address` эталонного набора; `testdata/agent-emulator.json`

- [ ] **Сначала тесты** — `handler/test/agent_sync_address_test.go`: `TestSyncSourceAddressSet` — пришёл адрес, `address_source` записан; `TestSyncSourceAddressAbsentKeeps` — поля нет, прежний адрес источника на месте; `TestSyncSourceAddressEmptyClears` — `""` даёт `NULL`; `TestSyncSourceNeverTouchesIMAddress` — `address_im` задан, сверка с другим адресом: `address_im` прежний, `address_source` новый; `TestSyncSourceAddressTooLong` — 501 символ, 422; заказчик B с тем же `uid` не задет. В эмуляторе: `TestTopologyEtagChangesWithAddress`.
- [ ] **Проверка:** `make test-local`, `go test ./tools/agent-emulator/...` — зелёное. `make check-no-stand`.

## Задача 6. Сервер: правка адресов в API конфигуратора и журнал настроек

**Репозиторий:** сервер. **Модель:** opus. **Ревью:** полное (доступ). **Параллельно с:** задачами 5 и 7.

**Файлы:**
- `api/im/backend.openapi.yaml`: запросы и поля из «Интерфейсов», затем `make gen-api-im`;
- `handler/v1/source.go`, `handler/v1/source_group.go`;
- `appservice/sourcegroup/source_group.go` и, по образцу, appservice устройств: проверка `user.Permissions.Has(model.PermManage)`, как в `source_group.go:79/125`;
- **`storing`:** `SetSourceAddressIM(ctx, customer, guid, *string)`; `SetSourceGroupAddress(ctx, customer, guid, *string)`; `ApplyGroupAddress(ctx, customer, group, address string, overwrite, dryRun bool) (int, error)`: рекурсивный CTE по `source_groups.parent_guid` с `customer_guid` на каждом шаге; затем `source_group_memberships`; затем `sources … deleted_at IS NULL`; условие `overwrite OR (address_im IS NULL AND address_source IS NULL)`; `DISTINCT`; `dryRun` — только `count`
- **журнал:** `Store.AppendSettingsAudit` в той же транзакции. Актёр — как у операторских админских запросов. Помощник — по образцу `auditDictionary` (`handler/operator/duty_groups.go:294`). Новое: `auditSource(...)` в слое v1.

- [ ] **Сначала тесты** — `handler/test/source_address_test.go`: `TestSourceAddressPutDelete`: PUT ставит `addressIm`, ответ `address` = введённый; DELETE возвращает к `addressSource`; `TestSourceAddressRights`: без `incident_manager.manage` — 403; `TestSourceAddressForeign`: устройство другого заказчика — 404; `TestSourceAddressAudit`: две записи `source/update` с before/after `addressIm`; `TestGroupAddressApplyDefault`: в группе и во вложенной — устройство без адреса, с адресом источника и с `addressIm`. Меняется только первое, `devices=1`; `TestGroupAddressApplyOverwrite`: `overwrite` — все три, `dryRun` перед тем вернул 3 и ничего не изменил; `TestGroupAddressApplyAudit`: одна запись `source_group/update` с `applyAddress`; `TestGroupAddressApplyEmpty`: у группы нет адреса — 422; удалённое устройство не тронуто; чужой заказчик через общий `parent_guid` невозможен — проверить в тесте
- [ ] **Проверка:** `make test-local` — зелёное.

## Задача 7. Сервер: операторский контракт — сводка, карточка, поиск, ссылки по группе, резервная копия

**Репозиторий:** сервер. **Модель:** opus. **Ревью:** полное (доступ, контракт). **Параллельно с:** задачами 5 и 6. **Зависит от:** задачи 2 и 4.

**Файлы:**
- `make vendor-operator-contract && make gen-api-operator`, в `api/im/operator/SOURCE` — хэш коммита IM задачи 2;
- `handler/operator/view_summary.go`: в `summaryOn` — `s.Source` и `s.Address`;
- `handler/operator/view_card.go`: `deviceRefs` (:135) — общая функция для сводки и карточки, с `Deleted`; `cardOf` (:93/96) — убрать `Site`, `SiteType`, `Location`
- `appservice/operator/load.go`, `loadSource` (:440): `l.Source` — как сейчас, только живое устройство (на нём держатся доступ и группы). Новое поле `l.DeletedSource *model.Source` читается, только если живого нет, — для `deleted: true` с именем. Если очередь грузит источники пачкой, а не через `loadSource`, адресные колонки добавить в тот же запрос: лишних запросов на строку не делать;
- `storing/queue_queries.go`: `queueSearchJoin` (:46) — `LEFT JOIN sources s ON s.guid = <источник события> AND s.customer_guid = i.customer_guid`; `queueSearchHit` (:65) — плюс `lower(s.name)` и `lower(CASE WHEN s.deleted_at IS NULL THEN coalesce(s.address_im, s.address_source) END)`; комментарий «нет площадки и места» обновить
- **ссылки справки:** `handler/operator/reference.go` (:481), `ListHelpLinks` — параметр `IncidentGuid`. Инцидент читается тем же путём с проверкой видимости, что и карточка. Не виден или не найден — только общие; группы источника и все их предки — из дерева в памяти, тем же, что у `deps.deepest`, или CTE по `parent_guid`; `Store.HelpLinks(ctx, customer, all bool, groups []uuid.UUID)` — `group_guid IS NULL AND legacy_site IS NULL OR group_guid = ANY($n)`
- `handler/operator/help_links.go`: `readHelpLinkBody` — `scope` и `groupGuid`, проверка группы своего заказчика, правило `unassigned`; `helpLinkOf` и `helpLinkReply`;
- **удаление группы** (`appservice/sourcegroup.DeleteSourceGroup` → `storing.DeleteSourceGroup:74`): в той же транзакции, до удаления, ссылки поддерева переходят в `legacy_site = <имя группы>`, `group_guid = NULL`;
- **резервная копия** `service/backup/`: колонки берутся из таблиц; в применении (`apply.go` или `validate.go`) строка `helpLinks` старого файла с ключом `site` переименовывается в `legacySite`; `groupGuid` должен ссылаться на группу из файла или из базы; `Version` не менять
- **загрузка эталонного набора стенда** `internal/im/stand/load_catalog.go` (:68, :207, :400): `devices[].address` → `address_source`, `addressIm` → `address_im`, у ссылок `scope`, `groupGuid`, `legacySite`.

- [ ] **Сначала тесты:** `operator_card_test.go`: `TestCardSourceAndAddress` — `source.name`, `typeLabel`, `address`; `TestCardDeletedSource` — `deleted: true`, `address: null`; `operator_queue_test.go`: `TestQueueRowSourceAddress` — адрес действующий на момент чтения: поменяли `address_im` — строка показывает новый; `TestQueueSearchByDeviceName`, `TestQueueSearchByAddress`, `TestQueueSearchAddressLikeEscaped` — `%` в поиске не находит всё; `operator_reference_test.go`: `TestHelpLinksByGroupNested` — ссылка группы-предка видна; `TestHelpLinksInvisibleIncident` — только общие; `TestHelpLinksUnassignedHidden`; `operator_help_links_admin_test.go`: `TestHelpLinkScopeGroupForeign` — 422 `HELP_LINK_GROUP_UNKNOWN`; `TestHelpLinkScopeUnassignedOnlyKeeps` — 422 `HELP_LINK_SCOPE_INVALID`; `TestHelpLinkGroupDeletedBecomesUnassigned`; `backup_test.go`: `TestRestoreOldHelpLinkSite` — старый файл с `site` даёт `unassigned`; `stand` (тег `imtest`): эталонный набор грузится, `go test -tags imtest ./internal/im/stand/...`
- [ ] **Проверка:** `make test-local` и `make test-stand` — зелёные; `make check-no-stand`; `grep -rn 'Site\b' internal --include=*.go | grep -v generated` пусто, кроме `LegacySite`

## Задача 8. Конфигуратор и экран оператора

**Репозиторий:** конфигуратор. **Модель:** sonnet. **Ревью:** короткое, а 8в — полное: там отмена старых ссылок. **Зависит от:** задача 2 (контракт). Сервер не нужен: Vitest на заглушках. Подзадачи а, б, в могут идти параллельно, но в одном рабочем дереве — по очереди.

### 8а. Экран оператора

**Файлы:**
- `src/operator/testing/openapi.json` — копия из IM через `tr -d '\r'`, хэш — в `tests/operator-fake-contract.test.ts`; `workflow_schema.v1.json`, если менялись строки;
- `src/operator/api/contract.ts`: `IncidentSummary` (:108) — без `site`, `siteType`, `location`, с полями `source` и `address`; `DeviceRef` (:169) — `deleted`; `HelpLink` (:497) — `scope`, `groupGuid`, `groupName`, `legacySite`;
- `src/operator/api/operatorCalls.ts` (:66, :173): `getHelpLinks(incidentGuid?)`;
- `src/operator/testing/contractCalls.ts` (:162, :168), `src/operator/testing/factories.ts` (:91);
- `src/operator/queue/IncidentRow.tsx` (:261, ~:290): строка `data-op="row-source"` «устройство · адрес», многоточие и `title`;
- `src/operator/card/CardPanel.tsx` (:207, :222): компонент `SourceBlock` (`data-op="card-source"`) после `AlarmBlock`;
- `src/operator/card/LinkedTab.tsx` (:359);
- `src/operator/shell/HelpMenu.tsx` (:85–142): `queryKey ['helpLinks', card?.guid]`, подпись раздела — `groupName`. Без инцидента — только `scope === 'shared'`;
- `src/shared/i18n/locales/{ru,en}/operator.json`: «Источник», «Устройство удалено», подсказка поиска.

- [ ] **Сначала тесты:** `IncidentRow.test.tsx`: «shows device and address under the event type», «address has ellipsis and full title», «row without address shows device only», «deleted device»; `CardPanel.test.tsx`: «source block with type and address»; `HelpMenu.test.tsx`: «asks links by incident guid», «without incident shows shared only», «group links under group name». Блок «Мне на принятие» — это фильтр `inbox` с тем же `IncidentRow`, отдельного теста не нужно.

### 8б. Устройство и группа: адрес

**Файлы:**
- `src/features/source-groups/api/imBackendSourceGroups.dto.ts` (:17, :44, :84): `addressSource`, `addressIm`, `address`;
- `api/imBackendSourceGroups.ts`: `setSourceAddress`, `resetSourceAddress`, `setGroupAddress`, `clearGroupAddress`, `applyGroupAddress(groupId, {overwrite, dryRun})`;
- `api/sourceGroupsRepository.ts` (:19), `imBackendSourceGroupsRepository.ts`, `testing/createTestSourceGroupsRepository.ts`;
- `model/types.ts` (`DeviceInfo`:7, `TreeGroupNode`:26), `lib/mapSourceDto.ts`;
- `components/DeviceDetailCard.tsx`: поле «Адрес из источника» — только чтение; поле «Адрес в МИ» с сохранением; пометка «отличается от источника»; кнопка «Вернуть адрес из источника»
- `components/GroupDetailCard.tsx`: поле «Адрес группы»; кнопка «Подставить адрес устройствам группы»; диалог `ApplyGroupAddressDialog`: флажок «и тем, у кого адрес уже есть»; при нём подтверждение «Будет изменено N устройств», N берётся из `dryRun`
- `HistoryButton` на обеих карточках; `src/features/audit/api/auditApi.ts` (`OBJECT_TYPES`:29) — `source`, `source_group` и их подписи;
- `src/shared/i18n/locales/*/sourceGroups.json` (есть во всех языках) — ru и en переводом, остальные — английским текстом, как принято в репозитории (проверить по соседним ключам).

- [ ] **Сначала тесты:** `DeviceDetailCard.test.tsx`: «shows both addresses and differs mark», «reset returns to source»; `GroupDetailCard.test.tsx`: «apply only empty by default», «overwrite asks confirmation with count from dry run»; `auditApi` — новые типы объектов разбираются

### 8в. Ссылки справки по группе

**Файлы:**
- `src/features/references/api/referencesApi.ts` (:108–123);
- `lib/helpLinkForm.ts` (:8, :40, :53): `scope`, `groupGuid`. У «не назначена» по умолчанию `scope='unassigned'`; сохранить без выбора можно, ссылка остаётся скрытой;
- `components/HelpLinkDrawer.tsx` (:152): выбор «Общая» или «Группа» и дерево групп из `fetchSourceGroupTree`; у «не назначена» — предупреждение «выберите группу (была площадка «…»)»;
- `components/HelpLinksTab.tsx` (:60, :137, :150): колонка «Группа», метка «выберите группу»;
- `lib/sortHelpLinks.ts` (:3): ключ `site` → `group`, сортировка по `groupName`, а «не назначена» — первыми;
- `locales/{ru,en,kk,zh}/references.json`: ключи `fieldSite`, `fieldSiteHint`, `siteShared` заменить ключами группы.

- [ ] **Сначала тесты** — `HelpLinksTab.test.tsx` (на месте прежних «site null»): «legacy link marked choose group»; «editing legacy link without group keeps it unassigned»; «group picked sends scope group»; «shared sends scope shared»

**Проверка 8а–8в:** `npm run test:run`, `npm run lint`, `npm run build:ts` — зелёные. `tests/operator-locale-keys.test.ts` зелёный. `PROJECT.md` обновить, если появились новые файлы (`SourceBlock`, `ApplyGroupAddressDialog`).

## Задача 9. Стенд и коммиты

**Модель:** sonnet. **Ревью:** короткое.

- [ ] Взять блокировку `~/Work/stand/lock-server` по правилам стенда.
- [ ] Дамп `imdb` перед миграцией: `pg_dump -U im imdb > ~/Work/stand/backup/imdb-before-address-2026-11-16.sql`.
- [ ] **Сервер:** собрать бинарник без тега `imtest` в `~/Work/stand/bin/`, перезапуск через `~/Work/stand/run-im-binary.sh` (или юнит `im-stand-server`); в логе — миграция 072 применена; `select count(*) from help_links where legacy_site is not null` равно числу прежних ссылок с `site`
- [ ] **Эмулятор агента:** остановить, собрать, запустить `run-agent.sh`. После сверки у демо-устройств заполнен `address_source`.
- [ ] **Конфигуратор:** `npm run build && rsync -a --delete dist/ ~/Work/stand/im-dist/`.
- [ ] **Глазами на стенде:** строка очереди и блок «Мне на принятие» — «устройство · адрес»; карточка — «Источник»; поиск по адресу; меню справки у инцидента ТЦ; ссылка «не назначена» помечена в конфигураторе; правка адреса, возврат и подстановка (с флажком и без) — записи в журнале настроек
- [ ] Прогнать `~/Work/stand/check-operator-api.sh` и `check-operator-filter.sh`: не хуже, чем до задачи.
- [ ] Снять блокировку.
- [ ] **Коммиты, локально, без push:** **сервер:** «Адрес: миграция 072 — адрес устройства и группы, ссылки по группе»; «Адрес: сверка устройств с адресом, контракт агента 0.7.0»; «Адрес: правка адресов и подстановка по группе, журнал настроек»; «Адрес: источник и адрес в сводке и карточке, поиск, справка по группе»; **конфигуратор:** «Адрес: строка очереди, карточка и меню справки»; «Адрес: адрес устройства и группы»; «Адрес: ссылки справки по группе». У всех — трейлер `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

**Параллельность:** 1 → 2 → 3 по порядку. После 2: 4 → (5 ∥ 6 ∥ 7), а 8 — параллельно с сервером. 9 — последней.

## Решения исполнителя (ночь 2026-11-15)

Пользователь спал, выбран самый осторожный вариант, совместимый с правилами:

1. **Правка адресов — в прежнем API конфигуратора** (`backend.openapi.yaml`, `/sources…`), а не в операторском контракте IM. Там уже правят группы, а в `openapi.json` IM нет запросов правки устройств. Право — `incident_manager.manage` = `incident:schema:admin`.
2. **Ввести и вернуть адрес — разные запросы** (`PUT` и `DELETE …/address`), у группы так же. Так нет неоднозначности «поле не пришло / `null`» в PATCH, а в журнале видно, что это возврат.
3. **Пустой адрес** после обрезки — `NULL`. `PUT` с пустым — 422: для возврата есть `DELETE`.
4. **Область ссылки** — явное поле `scope` (`shared`, `group`, `unassigned`), обязательное в `HelpLinkChange`.; Сохранение старой ссылки без выбора группы оставляет её скрытой. Общей она становится только явным выбором «Общая»; Прежняя площадка хранится в `legacy_site` (переименование колонки `site`) — для подсказки «выберите группу (была «…»)»
5. **Удаление группы** переводит её ссылки в «не назначена» (`legacy_site` = имя группы). Каскада и `SET NULL` нет: иначе ссылки стали бы общими.
6. **`GET help-links` без параметра** по-прежнему отдаёт все ссылки — так сейчас, этим пользуется вкладка администрирования. Меню без открытого инцидента само показывает только общие. С `incidentGuid` невидимого инцидента — только общие, без ошибки.
7. **`siteType` убран** вместе с `site` и `location`: сервер его не заполнял, а без площадки он теряет смысл.
8. **Источник в сводке** — `IncidentSummary.source` (`DeviceRef`, переехал из карточки) и отдельное `IncidentSummary.address`: «`site` и `location` заменить на `address`» — буквально. У `DeviceRef` своего адреса нет. Удалённое устройство — `deleted: true`, имя — последнее известное, `address: null`.
9. **Журнал настроек:** новые типы объектов `source` и `source_group`, действие — существующее `update`. CHECK `action` не трогаем. Подстановка — одна запись с `applyAddress {address, overwrite, devices}`.
10. **Подстановка `overwrite`** меняет и устройства с адресом источника: «у кого адрес уже есть» — по действующему адресу. Удалённые устройства не трогаются никогда. Перед подтверждением — `dryRun` с числом.
11. **Эталонный набор.** Адрес устройства = «площадка, место» прежних инцидентов. У устройства `…0011` два разных места — берётся первое по набору: «Складской комплекс, Склад №2, центральный проход»; `plans[].site` остаётся подписью плана, а запасной путь `planOf` по площадке удаляется: сейчас он не срабатывает; Добавлены пример `addressIm`, устройство без адреса и одна ссылка «не назначена»
12. **Сырые данные события** эмулятора (`replay.go`, поле `site` в `RawData`) не трогаем: это не поле инцидента.
13. **Резервная копия:** версия формата остаётся 1. Ключ `site` старых файлов при восстановлении читается как `legacySite`, то есть ссылка не становится общей.
14. **Прочие языки конфигуратора** без перевода получают английский текст. Прототип правку адресов не показывает — записано в §17 «Отступления».
