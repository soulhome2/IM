# План 71: аудит МИ, первый этап — план реализации

> **Для исполнителей-агентов:** обязательный скилл — superpowers:subagent-driven-development. Шаги отмечаются `- [ ]`. Каждая задача — TDD: сначала падающий тест, потом код.

**Цель:** журнал действий операторов и журнал изменений настроек пишутся, хранятся по сроку и читаются в конфигураторе с выгрузкой CSV.

**Архитектура:** правила и машина (IM) → контракт `openapi.json` и встроенный сервер прототипа → сервер МИ (Go, PostgreSQL 9.6): расширение `operator_actions`, новая `settings_audit`, маршруты `/operator/admin/audit/*`, чистка функцией → конфигуратор (TypeScript, React, vitest): раздел «Аудит», «История», сравнение.

**Стек:** Go + oapi-codegen + PostgreSQL 9.6; TypeScript + TanStack Router + zod + vitest; прототип — JS, headless Chrome.

**Спецификация:** [69-audit.md](69-audit.md), разделы «Предложение» и «Спорные места» (решения 1–8 от 2026-11-08).

**Репозитории и ветки** — все `feature/im_operator`: IM (этот), `~/Work/incident-manager-server` (сервер), `~/Work/incident-manager` (конфигуратор). axxoncloudgo не трогаем.

## Решения пользователя к плану (2026-11-08)

- **Разбивки по месяцам нет**: PostgreSQL 9.6 её не умеет. Чистка — функция `purge_audit(before, limit)`. Триггер запрета пропускает DELETE только внутри неё (флаг сессии `im.audit_purge`, который ставит сама функция) и только строки старше `before`. Обычный DELETE, UPDATE и TRUNCATE по-прежнему запрещены. Разбивка — при переходе на PG 10+ (в TECH-DEBT).
- **Права**: в первом этапе аудит доступен по `incident_manager.manage` (`model.PermManage`). Ключи `im.audit.actions.view`, `im.audit.settings.view`, `im.audit.export` описываются в правилах и в `model/permission.go` как сопоставление с `PermManage`. Старший смены аудит пока не видит. Права в облаке — отдельная задача (в TECH-DEBT).

## Global Constraints

- Язык документов, строк интерфейса и сообщений коммитов — русский, простыми словами. Коммит начинается с `71-TN: …`, в конце — `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Правило меняется в машине и правилах, не в `prototype/*.js`. Собранные файлы (`prototype/workflow.js`, `openapi.js`, `SETTINGS.md`, `openapi.v30.json` и др.) — только через `python3 tools/build_workflow.py`.
- `openapi.json` и `Specification/Workflow_machine/README.md` — в CRLF.
- Обе таблицы аудита — только на добавление. Удаление — только `purge_audit`.
- `retention.auditDays`: по умолчанию 1095, допустимо `0` (бессрочно) или от 365; один срок для обоих журналов.
- Ответ сценария в аудите: шаг, автор, время, выбранный вариант. Свободный текст — только `hasText: true` и `textLength`, без самого текста.
- Выгрузка: CSV, UTF-8 с BOM, разделитель `;`. Предел — период не больше 92 дней и не больше 1 000 000 строк. Иначе 422 с кодом `audit_export_too_large`. Каждая выгрузка — строка `audit_export` (кто, когда, фильтры, число строк).
- Время на экранах — в поясе компьютера (решение 2026-11-08; задача 1 сначала брала пояс из профиля облака `/me`).
- Тесты сервера — только `im-test-db` (55432), никогда `imdb`. Push — только по просьбе.
- Новый функционал прототипа — с шагом самопроверки в `prototype/selftest.js`.

## Review Focus

1. **Ошибка записи аудита в транзакции действия.** Если упала только запись в аудит, оператор всё равно должен выполнить действие. Аудит пишется под `SAVEPOINT`, при ошибке — откат к нему и строка `audit_gap` в следующей успешной записи (Task 4).
2. **Пустой и длинный период.** `from > to` — 400. Период больше 92 дней в выгрузке — 422. Чтение без `from`/`to` — последние 7 дней (Task 6).
3. **Курсор при одном `at` у многих строк.** Порядок `(at, seq)` — без пропусков и повторов между страницами (Task 6).
4. **Чужая организация.** Каждая выборка фильтруется по `customer_guid` запрашивающего; чужой `id` в `/settings/{id}` — 404 (Task 6).
5. **Чистка не трогает свежее и не открывает DELETE.** Обычный DELETE после `purge_audit` в той же сессии всё так же отказывает. `auditDays = 0` не удаляет ничего (Task 7).

---

### Task 1: Время в поясе компьютера (конфигуратор и оператор)

Решение 2026-11-08 (§14.9 правил): время на всех экранах МИ — в поясе компьютера (браузера). Пояс из профиля облака `/me` не используем: там по умолчанию UTC. Сервер хранит и отдаёт время в UTC; выгрузки CSV — в поясе, который браузер передаёт в `tz`.

**Файлы:** `~/Work/incident-manager/src/shared/lib/formatAudit.ts`, `formatAudit.test.ts`, `src/operator/lib/clock.ts`, вызовы выгрузки аудита.

**Интерфейсы — создаёт:** `formatAuditTimestamp(value, locale): string` — `Intl.DateTimeFormat` без `timeZone`; `browserTimeZone(): string` — `Intl.DateTimeFormat().resolvedOptions().timeZone`, для параметра `tz` выгрузки.

- [ ] Тест: `formatAuditTimestamp` не передаёт `timeZone` в `Intl` (время совпадает с `new Date(value).toLocaleString(locale)`); `browserTimeZone()` возвращает непустое имя IANA; запрос выгрузки содержит `tz=<browserTimeZone()>`.
- [ ] Прогнать тест: `npx vitest run src/shared/lib/formatAudit.test.ts` — FAIL.
- [ ] Убрать передачу пояса из сессии (`timezone` из `/me` не читать); часы оператора и списки — в поясе браузера; к `actions/export` и `settings/export` добавить `tz`.
- [ ] `npm run test:run && npm run lint` — PASS.
- [ ] Коммит `71-T1: время в конфигураторе и у оператора — в поясе компьютера`.

### Task 2: Правила и машина (IM)

**Файлы:** `Specification/State_rules/States rules IM.md` §12.4, §14.11, §5 (права); `State_rules/CHANGELOG.md`; `Specification/Workflow_machine/workflow_schema.v1.json` (`retention`, секция `retention` настроек); `strings/*.json`; `research/integration/TECH-DEBT.md`.

- [ ] Самопроверка: шаг в `prototype/selftest.js` — в настройках есть `retention.auditDays = 1095`; `check_machine.py` отклоняет `auditDays` 100 и принимает 0 и 365 (мутация в `tools/mutations/machine.json`, если проверка значений там). Прогнать — FAIL.
- [ ] §12.4: добавить в журнал передачу (кому), перенаправление (куда), объединение и отвязку, эскалацию (ручную и по таймеру), действия системы по инциденту (автор — система), ответы на шаги сценария (без свободного текста), выгрузку аудита, отметку о пропуске записей. Добавить журнал изменений настроек: кто, когда, объект, действие, было/стало или пара версий. Экран — раздел «Аудит» в конфигураторе.
- [ ] §14.11: заменить «не удаляется» на срок `retention.auditDays` (1095, 0 — бессрочно, иначе не меньше 365), чистка раз в час пачками; нехватка места — пост работает, пишется отметка о пропуске; версия настроек, на которую ссылается аудит, не удаляется.
- [ ] §5: права `im.audit.actions.view`, `im.audit.settings.view`, `im.audit.export`; в первой версии — у администратора (`manage`).
- [ ] Машина: `retention.auditDays` (тип, умолчание, границы, `labelKey`, `whatKey`) и поле в секции `retention`; строки на всех языках в `strings/`.
- [ ] CHANGELOG — строка со ссылкой на 69-audit.md. TECH-DEBT — разбивка по месяцам на PG 10+, права в облаке, старший смены.
- [ ] `python3 tools/build_workflow.py`, затем все быстрые проверки из CLAUDE.md, `check_i18n.py`, `check_guide.py`, затронутые мутации, самопроверка — PASS. `node tools/cel_vectors.mjs --update` — если изменилась машина.
- [ ] Коммит `71-T2: правила и машина — аудит действий и настроек, срок retention.auditDays`.

### Task 3: Контракт и встроенный сервер прототипа (IM)

**Файлы:** `Specification/Workflow_machine/openapi.json` (CRLF), `prototype/server.js`, `tests/api.html` (тесты API), `prototype/selftest.js`, раздел «Отступления» правил.

**Интерфейсы — создаёт** (всё под `manage`, иначе 403):
- `GET /operator/admin/audit/actions?person&incident&kind&from&to&cursor&limit` → `{items: AuditAction[], next?: string}`. `AuditAction = {id, at, personId, personName, actorKind: 'person'|'system', kind, incidentGuid?, incidentNumber?, transition?, fromState?, toState?, reasonId?, targetPersonId?, targetGroupId?, relatedIncidentGuid?, scenarioStep?, answer?: {option?: string, hasText: boolean, textLength: number}, details?: object}`. `kind` ∈ `sign_in, sign_out, break, back, link_lost, link_restored, transition, handover, redirect, merge, escalation, scenario_answer, auto, audit_export, audit_gap`.
- `GET /operator/admin/audit/settings?objectType&objectId&actor&from&to&cursor&limit` → `{items: SettingsAuditEntry[], next?}`. `SettingsAuditEntry = {id, at, actorId, actorName, objectType, objectId, objectName, action, fromVersion?, toVersion?}`; `objectType` ∈ `incident_rule, scenario, dictionary, access_group, schema, post_settings`; `action` ∈ `create, update, delete, publish, rollback, archive`.
- `GET /operator/admin/audit/settings/{id}` → `SettingsAuditEntry & {before?: object, after?: object}`; 404 — нет или чужой.
- `GET /operator/admin/audit/actions/export` и `/settings/export` — те же фильтры, `text/csv`; 422 `audit_export_too_large`.
- `GET /operator/admin/audit/usage` → `{bytes, rowsPerDay, capacityBytes?, level: 'ok'|'warn'|'alarm'}` (сервер — Task 7; прототип отдаёт `ok`).
- `limit` по умолчанию 100, максимум 500; без `from`/`to` — последние 7 суток; `from > to` — 400.

- [ ] Тесты в `tests/api.html`: страницы с курсором без пропусков при одном `at`; 403 без `manage`; 400 при `from > to`; 422 при 93 днях; CSV начинается с BOM, разделитель `;`; после выгрузки в `actions` есть `audit_export` с числом строк; `scenario_answer` не содержит текста. Прогнать — FAIL.
- [ ] Маршруты и схемы в `openapi.json`; встроенный сервер пишет журнал в памяти по тем же правилам и отдаёт маршруты.
- [ ] Шаг самопроверки: после «Передать» в журнале действий — `handover` с `targetPersonId`.
- [ ] Отступление в правилах: журнал настроек прототипа пуст — редактора настроек в прототипе нет.
- [ ] Сборка, быстрые проверки, `python3 -m unittest tools/test_openapi30.py`, тесты API и самопроверка — PASS.
- [ ] Коммит `71-T3: контракт /operator/admin/audit/* и журнал во встроенном сервере`.

### Task 4: Журнал действий в сервере

**Файлы:** `internal/im/service/storing/migrations/042_audit_actions.sql`, `internal/im/model/operator_action.go`, `internal/im/appservice/operator/feed.go:119` (`keepOperatorActions`), `appservice/operator/scenario.go:178` (`AnswerStep`), `storing/scheduler_queries.go:125`, тесты в `internal/im/handler/test/operator_actions_test.go`.

**Интерфейсы — создаёт:** константы `OperatorActionHandover, …Redirect, …Merge, …Escalation, …ScenarioAnswer, …Auto, …AuditExport, …AuditGap`; поля `OperatorAction.ActorKind, TargetPersonID, TargetGroupID, RelatedIncidentGUID *uuid.UUID, ScenarioStep string, Details json.RawMessage`; `func OperatorActionOfTransition(transition string, actor string) (kind, actorKind string)`.

Сопоставление переходов из машины (`api/im/operator/workflow_schema.v1.json`): `transfer, takeover, release` → `handover`; `reject, addressee_signed_out_to_group, addressee_signed_out_to_queue, addressee_lost_access, addressee_cannot_accept` → `redirect`; `merge, detach, close_linked` → `merge`; `auto_escalate, resolution_escalate, escalation_ceiling, resolution_ceiling` → `escalation`; прочие переходы с автором `system`/`dispatcher` → `auto`; остальные → `transition`. `actorKind` — `system` для авторов `system`, `dispatcher` и пустого, иначе `person`. Кому и куда — из `line.Vars` (имена ключей взять из `TemplateKey` журнала этих переходов).

- [ ] Тесты: `TestOperatorActionOfTransition` (таблица по всем 32 переходам); `TestOperatorActionsHandoverTarget` — после передачи строка `handover` с `target_person_id`; `TestOperatorActionsTimerEscalation` — `escalation`, `actor_kind = system`; `TestOperatorActionsScenarioAnswerNoText` — ответ со свободным текстом «Иванов 8-777» даёт `details` с `hasText: true, textLength: 12` и не содержит текста; `TestOperatorActionsAuditFailureDoesNotBlock` — при сбое вставки в аудит (порча через `CHECK`, наложенный в тесте) переход проходит, следующая успешная запись сопровождается `audit_gap`. Прогнать — FAIL.
- [ ] Миграция 042: расширить `CHECK kind`, добавить столбцы (по умолчанию пустые), индекс `(customer_guid, incident_guid, at, seq)`; представление `operator_action_journal` оставить, добавив новые столбцы.
- [ ] Код: классификация в `keepOperatorActions`; строка `scenario_answer` в транзакции `AnswerStep`; вставка под `SAVEPOINT audit`, при ошибке — `ROLLBACK TO SAVEPOINT`, счётчик пропусков в памяти процесса, строка `audit_gap` (`details: {missed: N}`) при следующей успешной записи.
- [ ] `IM_TEST_DB_URL=… go test -race -run 'TestOperatorAction' ./internal/im/...`, затем `make lint` и полный `make test-local` (тестовую базу пересоздать) — PASS.
- [ ] Коммит `71-T4: журнал действий — передача, перенаправление, объединение, эскалация, ответы, действия системы`.

### Task 5: Журнал изменений настроек в сервере

**Файлы:** `migrations/043_settings_audit.sql`, `internal/im/model/settings_audit.go`, `storing/settings_audit_queries.go`; места записи — `appservice/incidentrule/incident_rule.go:55,105,113`, `appservice/accessrule/access_rule.go:131,148,158`, `appservice/scenario/scenario.go:55,135,146`, `handler/operator/duty_groups.go` (`editDutyGroups:88`), `help_links.go` (`editHelpLinks:81`), `priorities.go` (`editPriorities:112`), `appservice/operator/settings.go:158,210,243,275`; тесты в `internal/im/handler/test/settings_audit_test.go`.

**Интерфейсы — создаёт:** `type SettingsAuditEntry struct{GUID; CustomerGUID; At time.Time; ActorID, ActorName, ObjectType, ObjectID, ObjectName, Action string; FromVersion, ToVersion *int64; Before, After json.RawMessage}`; `func (s *Store) AppendSettingsAudit(ctx model.AppContext, e *model.SettingsAuditEntry) error` (в транзакции ctx).

- [ ] Тесты (по одному на тип объекта): правка правила — `update` с `before`/`after`; удаление справочника — `delete` с `before`; публикация настроек поста — `publish` с `from_version`/`to_version`, без копий; сохранение черновика — `update` с автором, без копий; откат транзакции правки не оставляет строки аудита; UPDATE/DELETE таблицы — отказ. Для `Update` и `Discard` настроек автор передаётся новым параметром `by string`. Прогнать — FAIL.
- [ ] Миграция 043: таблица, индексы `(customer_guid, at, seq)` и `(customer_guid, object_type, object_id, at)`, триггеры запрета, как в 026.
- [ ] Запись во всех местах выше — в той же транзакции; `before` читается под блокировкой перед правкой.
- [ ] Запрет удаления версии, на которую ссылается аудит: удаление черновика (`Discard`) — разрешено (черновик не версия); у сценариев — версия, на которую есть ссылка, не удаляется (409 `version_referenced_by_audit`), тест.
- [ ] Тесты, `make lint`, полный `make test-local` — PASS.
- [ ] Коммит `71-T5: журнал изменений настроек — правила, доступ, сценарии, справочники, настройки поста`.

### Task 6: API аудита и выгрузка CSV в сервере

**Файлы:** `api/im/operator/openapi.v30.json` (через `make vendor-operator-contract` из IM после Task 3), `make gen-api-operator`, `internal/im/handler/operator/audit.go`, `storing/audit_read_queries.go`, тесты `internal/im/handler/test/audit_api_test.go`.

**Интерфейсы — потребляет:** маршруты и схемы Task 3, таблицы Task 4–5.

- [ ] Тесты — те же случаи, что в `tests/api.html` (Task 3), плюс Review Focus 2–4; курсор — непрозрачная строка base64 от `(at, seq)`. Прогнать — FAIL.
- [ ] Обработчики: проверка `PermManage`; фильтр по `customer_guid`; выборка `WHERE (at, seq) > ($cursor) ORDER BY at, seq LIMIT n+1`; CSV пишется потоком (`encoding/csv`, `Comma = ';'`, BOM в начале); `audit_export` — после успешной выдачи; имя человека — из `operator_sessions`/людей, как в журнале карточки.
- [ ] Тесты, `make lint`, полный `make test-local` — PASS; на стенде `tests/api.html` против сервера — маршруты аудита зелёные.
- [ ] Коммит `71-T6: API аудита — выборка с курсором и выгрузка CSV`.

### Task 7: Чистка по сроку и объём

**Файлы:** `migrations/044_audit_purge.sql`, `appservice/operator/retention.go:30`, `service/transition/core_prepare.go:216` (рядом — `AuditRetentionDays`), `storing/retention_queries.go`, маршрут `GET /operator/admin/audit/usage` (контракт — Task 3), тесты `internal/im/handler/test/audit_purge_test.go`.

**Интерфейсы — создаёт:** SQL `purge_audit(before timestamptz, lim int) RETURNS int`; `func (s *Store) PurgeAudit(ctx, before time.Time, limit int) (int, error)`; `transition.AuditRetentionDays(m) int`; `GET /operator/admin/audit/usage` → `{bytes: number, rowsPerDay: number, capacityBytes?: number, level: 'ok'|'warn'|'alarm'}`.

- [ ] Тесты: строки старше срока удаляются, моложе — нет; `auditDays = 0` — ничего; после `purge_audit` обычный `DELETE` в той же сессии — отказ; `purge_audit` с `before` позже, чем `now - 365 дней`, — отказ (защита нижней границы в самой функции); пачка не больше `lim`; `usage.level` — `warn` от 80%, `alarm` от 95% `capacityBytes` (из `IM_AUDIT_CAPACITY_BYTES`; не задано — только `ok` и объём). Прогнать — FAIL.
- [ ] Миграция 044: функция `SECURITY DEFINER` ставит `set_config('im.audit_purge', before::text, true)`, удаляет, сбрасывает флаг; триггеры обеих таблиц пропускают DELETE, только если флаг стоит и `OLD.at < флаг`.
- [ ] Чистка в `purgeDue` после инцидентов, пачками по 5000; объём — `pg_total_relation_size` обеих таблиц, скорость — строки за последние 7 суток / 7.
- [ ] Тесты, `make lint`, полный `make test-local` — PASS.
- [ ] Коммит `71-T7: чистка аудита по retention.auditDays и объём журнала`.

### Task 8: Раздел «Аудит» в конфигураторе

**Файлы:** `src/features/audit/{api/auditApi.ts, api/useAudit.ts, components/AuditPage.tsx, components/ActionsTab.tsx, components/SettingsTab.tsx, lib/}` (по образцу `src/features/duty-groups/`), `src/app/router.tsx`, `src/shared/navigation/navItems.ts`, строки.

- [ ] Тесты (vitest + Testing Library, моки `apiFetch`): две закладки; фильтры уходят в запрос; «Показать ещё» передаёт `cursor`; «Выгрузить» скачивает файл, ошибку 422 показывает текстом «Сузьте период или фильтр»; строка `scenario_answer` показывает вариант и «был текст (N знаков)»; время — через `formatAuditTimestamp` с поясом пользователя; плашка объёма при `warn`/`alarm`; пункт меню виден только при `manage`. Прогнать — FAIL.
- [ ] Реализация; клиент — zod-схемы по контракту Task 3.
- [ ] `npm run test:run && npm run lint`, сборка и `rsync` на стенд (`npm run build && rsync -a --delete dist/ ~/Work/stand/im-dist/`), проверка на стенде глазами — PASS.
- [ ] Коммит `71-T8: раздел «Аудит» в конфигураторе`.

### Task 9: «История» у настроек и сравнение «было/стало»

**Файлы:** `src/features/audit/components/HistoryDrawer.tsx`, `DiffView.tsx`, `lib/diff.ts`; кнопки «История» на страницах правил, доступа, сценариев, дежурных групп, ссылок, приоритетов, настроек поста.

**Интерфейсы — создаёт:** `diffObjects(before: unknown, after: unknown): DiffRow[]`, `DiffRow = {path: string, before?: unknown, after?: unknown, change: 'added'|'removed'|'changed'}`.

- [ ] Тесты: `diffObjects` — вложенные объекты, массивы по `id`/`guid` (иначе по индексу), без изменений — пусто; «История» открывает журнал с `objectType`/`objectId`; для записи с версиями — загрузка двух версий и сравнение; нет версии — «версия недоступна». Прогнать — FAIL.
- [ ] Реализация.
- [ ] Тесты, линтер, стенд — PASS.
- [ ] Коммит `71-T9: история объекта настроек и сравнение было/стало`.

### Task 10: Итог

- [ ] Ревью всей ветки в трёх репозиториях (свежий агент).
- [ ] Стенд: передать инцидент, ответить на шаг, поправить правило, опубликовать настройки, выгрузить CSV — всё видно в «Аудите».
- [ ] 69-audit.md: отметить выполненное, добавить ссылку на этот план; итог в конце этого файла.

## Порядок

T1 (не зависит ни от чего) и T2 → T3 → T4 → T5 → T6 → T7 → T8 → T9 → T10. T1 можно делать параллельно с T2–T3.

## Итог (2026-11-08)

Все задачи сделаны, коммитов нет: по решению пользователя — один общий коммит на репозиторий, когда он скажет. Ранние локальные коммиты (IM `d5c0a4a`, конфигуратор `d344626`, `5b2483e`, `f9d3a9f`) войдут в него.

- **Сделано:** время на экранах — в поясе компьютера (§14.9; сначала было по профилю облака, решение пользователя 2026-11-08 — пояс компьютера); правила §5, §12.4, §14.11 и `retention.auditDays`; контракт `/operator/admin/audit/*` и журнал во встроенном сервере прототипа; журнал действий (передача, перенаправление, объединение, эскалация, ответы сценариев без текста, действия системы, выгрузки, пропуски) — миграции 042, 045; журнал настроек — 043; API чтения с курсором, выгрузка CSV, чистка `purge_audit` и объём — 044; раздел «Аудит» и «История изменений» в строке каждого объекта со сравнением «было / стало».
- **Сверх плана, по просьбе пользователя после просмотра:** люди — выбором по имени, инцидент — по номеру, объект — поиском по названию (`objectName`); кнопки периода «Час … Год»; «Подробности» словами; значки вместо надписей; «История» настроек поста переименована в «Версии»; номер инцидента и связанного инцидента хранятся в строке аудита (миграция 045) и не пропадают после удаления инцидента по сроку; у дежурных групп — описание и пояснение про порядок.
- **Проверки:** тесты сервера (полный прогон), конфигуратора (1777), прототипа (самопроверка, тесты API), быстрые проверки IM — проходят. Ревью каждой задачи и итоговое ревью всех трёх репозиториев — замечаний Critical и Important не осталось.
- **Стенд:** сервер `~/Work/stand/bin/im-audit2`, миграции 042–045 в `imdb`, копии базы до миграций — `~/Work/stand/backup/imdb-before-audit-*.sql`; старый `bin/im` оставлен для отката. Проверены запросами: журнал действий, журнал настроек (правила, дежурные группы), одна запись с «было / стало», объём, 400 / 422, CSV с BOM, поиск по номеру и названию, guid приоритетов.
- **Не проверено:** `tests/api.html` против сервера стенда — ему нужен служебный сброс базы, он стёр бы `imdb`; история сценария, группы доступа и справочной ссылки на стенде — по коду ключи совпадают.
- **Отложено** в [TECH-DEBT](TECH-DEBT.md): разбивка аудита по месяцам на PG 10+; отдельная роль базы для чистки; точность отметки о пропуске записей и номер прежнего основного при отвязке; права `im.audit.*` в облаке и роль старшего смены. Второй этап — по разделу «Экраны» в [69-audit.md](69-audit.md).
