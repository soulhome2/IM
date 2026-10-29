# Этап 4б-1: столбцы инцидента и переход в одной транзакции — план работ

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Сервер МИ хранит инцидент со всеми полями машины и выполняет ручной переход машины одной транзакцией PostgreSQL: доступность → форма → окно после дедлайна → эффекты → журнал → версия, всё или ничего; при приёме события создание инцидента идёт эффектами перехода `create` (норматив реакции запущен).

**Architecture:** Миграция 018 добавляет столбцы под тип `Incident` машины и `kind` журнала. Новый пакет `internal/im/service/transition` — ядро исполнения: оно берёт под блокировку «семью» инцидента (`SELECT … ORDER BY number FOR UPDATE`), строит черновик из строк базы, вызывает исполнитель машины этапа 4а (`internal/im/machine`), собирает журнал и действия мира и пишет всё одной транзакцией с проверкой версии в `UPDATE`. Факты над инцидентами — запрос SQL отбирает кандидатов по индексу, к ним добавляется черновик, смысл даёт выражение `ref` машины. Мир — интерфейс: настоящие ответы сервер даёт по дереву групп и по пользователю запроса, остальное подставляет вызывающий. Приём события (`service/intake`) создаёт инциденты через `Core.Create`. Векторы переходов, объединение и «Отсоединить все» — вторая часть, [54-plan-stage4b2.md](54-plan-stage4b2.md).

**Tech Stack:** Go 1.27.1, cel-go v0.26.1 (уже в сервере), dat.v1 + pgx/v5, PostgreSQL 9.6, testify `require`, golangci-lint v2.14.0.

**Spec:** [40-plan.md, «4. Исполнитель машины»](40-plan.md#4-исполнитель-машины--сервер-ми-l) (этап делится на 4а, 4б, 4в — решение пользователя 2026-10-29; 4б — на две части по размеру, решение 8 ниже); [52-plan-stage4a.md, «Не в этом этапе»](52-plan-stage4a.md#не-в-этом-этапе); ADR-004 сервера (`docs/adr/004-machine-executor.md`), раздел «Contract for 4b»; [BACKEND.md](../../Specification/Workflow_machine/BACKEND.md) — «Факты над множеством инцидентов», «Переход атомарен», «Версия записи», «Срок группы», «Алерты», «Ложная тревога у соседа»; [CEL.md](../../Specification/Workflow_machine/CEL.md) — «Эффекты», «Действия мира», «Ядро исполнения», «Векторы». Образец исполнения — `run`, `applySteps`, `celApply`, `validateForm`, `windowBefore`/`windowAfter`/`overridden`, `vars`, `create` в [prototype/engine.js](../../prototype/engine.js); `log`, `runTransition`, `touch` в [prototype/server.js](../../prototype/server.js). Находки разведки — `server-findings.md` и `proto-findings.md`, ревью этого плана — `plan-review.md` (scratchpad сессии 2026-10-29; всё нужное перенесено сюда). Сервер — `8ca6eae`, IM — `6e86123`; сверено 2026-10-29.

## Global Constraints

- Сервер — `~/Work/incident-manager-server`, ветка `feature/im_operator`, от `8ca6eae`. IM — `/mnt/hgfs/VmWareShared/soul2home/IM`, ветка `feature/im_operator`, от `6e86123`. Пути в задачах — от корня репозитория задачи. Порядок: задачи 1–14 — сервер, задача 15 — стенд, задача 16 — сервер и документы IM. Код IM в этой части не меняется: машина, прототип, векторы — те же, копия контракта сервера (`api/im/operator`, `SOURCE` = `6e86123`) не обновляется.
- Только локально. Push — только по просьбе пользователя. `~/Work/axxoncloudgo` не менять; кажется, что нужна правка облака, — **стоп, спросить пользователя**.
- Вход отложен: тестовый пользователь `test@axxonnet.test`; обработку токена не трогать. Новых маршрутов HTTP нет: ядро переходов вызывают только тесты и приём события; операторский API — 4в.
- Пакет `internal/im/machine` по-прежнему без базы и без HTTP. Тесты с базой — только контейнер `im-test-db` (`127.0.0.1:55432`): `make test-local` или `TESTDB='postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable' && IM_TEST_DB_URL=$TESTDB go test …`; база стенда `imdb` — не для тестов. Контейнер не запущен — `sg docker -c "make test-db-up"`. Пакеты без базы — `go test -race $(go list ./internal/im/... | grep -v /handler/test)`: `internal/im/handler/test` без `IM_TEST_DB_URL` ищет базу `db` из `tools/env/testing.env`.
- Перед любой командой `go` — `source ~/go/offline-env.sh`. Новых зависимостей нет; `go.mod` в этой части не меняется. Адрес `npm.itvgroup.ru` недоступен, не использовать. Docker — только через `sg docker -c "…"`.
- `make gen`, `make gen-api-im`, `make gen-api-operator` не запускать (контракт не меняется). Сгенерированное руками не править.
- `golangci-lint run ./...` — 0 замечаний в каждой задаче (`funlen` 120 строк / 60 операторов, `dupl` 150, `gosec`, `errorlint`, `staticcheck`). `gofmt -l` по файлам задачи — пусто; `gofmt -l internal/im` целиком — пусто начиная с задачи 3 (в ней правятся три места, которые не прошли gofmt ещё в 4а).
- Тесты — testify `require`, пакеты с горутинами — под `-race`. Номера инцидентов в тестах с базой — из счётчика (`ReserveIncidentNumbers`), не придуманные. Комментарии в коде и ADR — по-английски; документы IM — по-русски, простыми словами.
- **Правила IM.** Прототип только исполняет машину; машина, правила, `State_rules/CHANGELOG.md` в этапе не меняются. Сгенерированные файлы IM — только своим инструментом. Кажется, что прототип расходится с BACKEND.md или CEL.md, а решения 2 ниже нет, — **стоп, спросить**: это новый пункт ревью в IM, а не правка сервера «под прототип». Перед правкой документов IM — `git -C /mnt/hgfs/VmWareShared/soul2home/IM fetch`; есть новое на GitHub — сказать пользователю.
- Миграции — только новые файлы с номером 018 и дальше; применённые не переписывать и не перенумеровывать (`applyMigrations` сверяет префикс).
- Временные файлы — в scratchpad сессии исполнителя; в командах ниже он `$S` (задать `S=…` в той же строке).
- Коммиты. Сервер — один на задачу, сообщение по-русски, начинается с «Этап 4б: », пишется инструментом записи файла в `.git/COMMIT_MSG_STAGE4B` (без heredoc), последняя строка — `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`; затем `git commit -q -F .git/COMMIT_MSG_STAGE4B`. IM — так же, файл `.superpowers/sdd/53-plan-stage4b/commit-msg.txt` (папка в `.gitignore`), `git commit -q -F .superpowers/sdd/53-plan-stage4b/commit-msg.txt`; сообщение начинается с «Этап 4б: » (пункта ревью под эту работу нет: PROC-44 закрыт и говорит о векторах CEL, а не о переходах). Команды Bash — в одну строку. Журнал работ — `.superpowers/sdd/53-plan-stage4b/progress.md` в IM.

**Решения пользователя (обязательны):**

- Этап 4 — три части со своими планами и итоговым просмотром: 4а — исполнитель CEL и векторы (сделан); 4б — столбцы инцидента и переходы в транзакции, векторы переходов; 4в — операторский API и минимум из этапов 5–7.
- Этап 4 принимается без `tests/api.html` (вход отложен): тесты Go, векторы JS↔Go и скрипт стенда «взять, отложить, передать, закрыть» (4в).
- PROC-44 в3: ошибка вычисления выражения — ошибка сервера, не `false`: переход не применяется, ничего не записано.
- «404 раньше `If-Match`» — 4в (HTTP).
- Тип события в условии правила — по `uid`, как в машине, пока пользователь не ответил на вопрос «uid или пара».
- RULE-137 «всё или ничего» при приёме события остаётся.

**Решения этого плана (обязательны для задач; решения 1–10 — указания ведущего, обоснования остальных — в конце):**

1. **Уровень векторов — ядро прототипа** (`run`, `runAll`, `merge`, `create` объекта `IMEngine.create`), а не HTTP. Версии в вектор не входят: ядро Go даёт +1 изменённым инцидентам (решение 16). Отображение на HTTP — 4в. Планировщик (`tick`) — этап 6, минимум — 4в; окно после дедлайна (`windowBefore`/`overridden`) ручного перехода — здесь. Сами векторы — часть 4б-2.
2. **Где прототип срезает углы в памяти, Go следует BACKEND.md и CEL.md — всё в одной транзакции:** нарушение отменённого таймером перехода (у прототипа — вторая фиксация в `windowAfter`), запись «некому» `notify.emptyLog` (у прототипа — после фиксации), записи `merged_in*` (у прототипа — `server.js` вне ядра, 4б-2), `shareAnswers` (у прототипа меняет живой `run`). Порядок записей журнала — тот же, что у прототипа (решение 13), поэтому векторы сравнивают равные итоги.
3. **Ошибка вычисления эффекта — ошибка Go** (решение 11 этапа 4а, в3): `(nil, err)`, ничего не записано. Прототип отдаёт её как `422 FORM_FIELD_REQUIRED` (`server.js`, `runTransition`) — расхождение слоя HTTP, решается в 4в; открытый вопрос 2.
4. **Мир.** Настоящие ответы: `inSourceGroup`, `deviceInGroup`, `groupDepth` (дерево групп, как у приёма события), `can` и `access` для пользователя запроса. Всё остальное — интерфейс `World`, его реализацию подставляет вызывающий: в тестах — в памяти, настоящая — 4в и этап 5. Факты над инцидентами — SQL в транзакции с черновиком (решения 12, 18).
5. **Конкурентность.** Один `DoInTx` на операцию; `SELECT … FOR UPDATE` на все инциденты, которые операция читает как свои и пишет, в порядке номера (без взаимной блокировки); версия проверяется и растёт в `UPDATE … WHERE version = $n`. Факты над инцидентами вне взятого набора (`countMine`, `mineOf` по другим инцидентам оператора) читают снимок READ COMMITTED без блокировки (обоснование 5).
6. **Черновик** строится из строк базы в порядке номера; инцидент получает состояние `to` своего шага перед своими эффектами (решение 14). `Scope.Incident` расходится с черновиком по `state` — ошибка. Действия мира применяются в порядке `Draft.Actions()` внутри транзакции: `log` (с `once`), `setCursor`, `shareAnswers`; после фиксации — `notify`, `command`, `evict`; `touch` — версия +1 в транзакции и событие потока после фиксации. Эта фраза дописывается в ADR-004, решение 6 (задача 16).
7. **Сценарий.** Тип `Incident` машины прогресса сценария не содержит: `setCursor`, `shareAnswers`, `stepsFilled`, прогресс и номер шага для журнала — через `World`; у приёма события — заглушки (`STAGE6`), хранилища курсора нет. Сценарий целиком — этап 6.
8. **Размер.** Этап больше 12 задач — делится: 4б-1 (этот план, 16 задач) — схема, хранилище, ядро одиночного перехода, эффекты `create` при приёме; 4б-2 ([54](54-plan-stage4b2.md), 10 задач) — запись и файл векторов переходов в IM, «Отсоединить все», объединение, сверка Go с векторами в памяти и на PostgreSQL. Третьего файла нет: задачи этой части мелкие, по одной теме каждая.
9. **Порядок и коммиты** — Global Constraints; в 4б-1 нет задач IM, кроме документов в задаче 16.
10. **Открытый вопрос «тип события по `uid` или по паре»** остаётся открытым; план следует `uid`.
11. **Ядро — пакет `internal/im/service/transition`** без HTTP; хранилище — интерфейс `Repo` (PostgreSQL — переходник над `storing.Store`, в тестах — `transitiontest.MemRepo`). `storing` не знает пакета `transition`: его методы — на типах `model`. `transition` не импортирует `intake` (свой `GroupTree`), `intake` импортирует `transition`.
12. **Факты над инцидентами: SQL — отбор кандидатов, смысл — `ref` машины.** У каждого из 6 фактов с `ref` — запрос по индексу, который отдаёт надмножество; к нему добавляется черновик (решение 18); результат — выражение `ref` машины над этим списком. Факт с `ref` без запроса — ошибка (тест `TestEveryRefFactHasSQL`).
13. **Порядок записей журнала у инцидента:** `workflow.journal.timer_overridden` — первой из записей операции; затем записи эффектов шага по `Draft.Actions()`; затем записи «некому» (`emptyLog`) этого шага в порядке действий `notify`; затем записи `recordBreach` отменённого перехода; `merged_in*` — последней (4б-2). Так у прототипа: `applySteps` фиксирует и сразу выполняет `after` (там «некому»), `windowAfter` идёт после и вставляет запись о таймере на место `logAt`, `server.js` пишет `merged_in` после ядра.
14. **Состояние `to` — перед эффектами инцидента, а не всей операции:** так `celApply` (состояние меняется в цикле по инцидентам, у объединения «Взять» основного — вторым шагом). Требование ADR-004 («черновик держит инцидент уже в `to`») выполняется на момент его эффектов.
15. **«Семья» — набор блокировки.** `S0` — свои инциденты операции и их основные (`linked_to` своих). Семья — строки арендатора без `deleted_at`, у которых `guid ∈ S0`, или `linked_to ∈ S0`, или `left_group->>'primaryId' ∈ S0`, или `event_guid` — событие одной из строк `S0` (соседи и своих, и их основных). Это все, кому эффекты ручных переходов машины пишут (`relinkToPrimary`, `tightenPrimaryDeadline`, `clearLink`, `recordBreach`, `logSiblings`). Одна команда: условия — `OR` с подзапросами в `WHERE`, без `UNION` (PostgreSQL не берёт `FOR UPDATE` у `UNION`). Запись `set`/`append`, журнала или `touch` вне семьи — `ErrFamilyChanged` (решение 19).
16. **Версия +1** — один раз за операцию у каждого инцидента, у которого есть запись `set`/`append`, новая или заменённая (`once`) запись журнала или `touch`; у создаваемого — версия 1. `changed_at` = `now` у тех же. Это сознательно шире `server.js`: прототип не даёт новой версии инциденту, которому достался только журнал (основной при «Переоткрыть» → `clearLink` с ключом журнала). Версий в векторах ядра нет; векторам HTTP 4в это нужно учесть.
17. **Время в столбцах.** Моменты, которые читают люди и отчёты (`closed_at`, `linked_at`, `changed_at`), — `timestamptz NULL` (пусто ↔ 0); внутренности таймеров, нарушений и выхода из группы — `jsonb` с целыми мс, как в машине.
18. **Черновик поверх кандидатов — объединение:** список факта = кандидаты SQL ∪ все инциденты черновика; у инцидента, который есть и там, и там, берётся версия черновика; порядок — `Row.Order`. Так факт видит и инцидент, который эффекты уже изменили, хотя SQL по старым полям его не отдал бы (взятый в черновике `new` → `in_progress` считается в `countMine`). Новый инцидент `create` в хранилище ещё не лежит и фактам не виден (как у прототипа).
19. **`ErrFamilyChanged` — повтор операции.** Блокировка берёт строки, которые подошли на снимке команды; связь, добавленная параллельной транзакцией (объединение), в семью может не попасть. Ядро повторяет операцию целиком (новый `DoInTx`) до 3 попыток; после третьей — `ErrFamilyChanged`. В 4в — `412 VERSION_CONFLICT` с актуальной карточкой (обоснование 12).
20. **Часы — целые мс.** Ядро получает `now` в мс; приём события усекает свои часы до мс (`Truncate(time.Millisecond)`), чтобы `incidents.created_at` и `at` записи журнала `create` совпадали.
21. **Порядок записей журнала в базе.** `GetJournalEntries` сортирует по `(at, guid)`, а у записей одной операции `at` один. Поэтому `guid` (UUID v7) записям выдаются после того, как порядок операции собран (решение 13), подряд в этом порядке; заменённые `once` записи сохраняют свой `guid`.
22. **`since` у таймеров `reaction` и `resolution`.** Эффекты машины пишут `since = now` при запуске таймера, Go это хранит. Прототип хранит `since` только у `hold` (`FIELDS` в `engine.js`), выражения машины его у других таймеров не читают. Векторы 4б-2 сравнивают `since` только у `hold`, как `check_quint_replay.mjs` (решение 25 плана 54).

## Review Focus

1. **Всё или ничего в PostgreSQL:** отказ, ошибка вычисления, конфликт версии, сбой записи журнала — ни строки инцидента, ни журнала, ни версии. Тесты — задача 7: `TestRunEffectErrorIsGoError`; задача 12: `TestRunAllOrNothingOnPostgres`.
2. **Порядок записей журнала** (решения 13, 21) и `once`. Тесты — задача 9: `TestRunWindowAfterDeadline`, `TestLogOnce`, `TestEmptyLogAfterOperationRows`; задача 12: `TestRunWindowOnPostgres`.
3. **Блокировки:** одна команда `FOR UPDATE` на семью; запись вне семьи — повтор, потом ошибка; пересекающиеся семьи в разном порядке не дают `40P01`. Тесты — задача 10: `TestLockFamily`; задача 12: `TestConcurrentClaim`, `TestLockFamilyNoDeadlock`; задача 8: `TestRunRetriesFamilyChanged`.
4. **Черновик:** `to` — перед эффектами инцидента; `before` — до смены состояния; кандидаты ∪ черновик; `Scope` против черновика — ошибка. Тесты — задача 4: `TestEffectScopeStateDisagreesWithDraft`; задача 7: `TestRunStateSetBeforeEffects`; задача 8: `TestRefsSeeDraft`.
5. **Целые числа и пусто из базы:** `jsonb` — `UseNumber`, `float64` — ошибка; `NULL` — `''`, `0`, запись из нулей; в `timers` — все три таймера машины. Тесты — задача 2: `TestToMachineTypes`, `TestToMachineRejectsFloat`, `TestFromMachineRoundTripPool`.

---

## Строка базы ↔ инцидент машины

Общая для задач 1, 2, 10. Перевод — `transition.ToMachine` / `transition.FromMachine` (задача 2); поля из соединений только читаются.

| Поле `Incident` | Тип | Столбец / откуда | Пусто ↔ |
|---|---|---|---|
| `id` | string | `incidents.guid` | — |
| `number` | string | `incidents.number` → `model.FormatIncidentNumber` (`INC-1851`) | — |
| `eventType` | string | `events.guid = incidents.event_guid` → `source_event_types.uid` (только чтение) | — |
| `priority` | int | `priorities.value` по `incidents.priority_guid` (только чтение) | — |
| `occurredAt` | int | `events.occurred_at`, мс (только чтение) | — |
| `state` | string | `state` (есть) | — |
| `owner` | string | новый `owner text NOT NULL DEFAULT ''` | `''` |
| `assignmentGroup` | string | новый `assignment_group text NOT NULL DEFAULT ''` | `''` |
| `holdReasonId` | string | новый `hold_reason_id text NOT NULL DEFAULT ''` | `''` |
| `escalationLevel` | int | новый `escalation_level bigint NOT NULL DEFAULT 0` | `0` |
| `transferCount` | int | новый `transfer_count bigint NOT NULL DEFAULT 0` | `0` |
| `closeResultId` | string | новый `close_result_id text NOT NULL DEFAULT ''` | `''` |
| `closeCauseId` | string | новый `close_cause_id text NOT NULL DEFAULT ''` | `''` |
| `result` | string | новый `close_comment text NOT NULL DEFAULT ''` (комментарий закрытия; не `scenario_result`) | `''` |
| `closedBy` | string | новый `closed_by text NOT NULL DEFAULT ''` | `''` |
| `closedAt` | int | новый `closed_at timestamptz NULL` | `NULL` ↔ `0` |
| `slaBreached` | bool | новый `sla_breached boolean NOT NULL DEFAULT false` | `false` |
| `breaches` | list<Breach> | новый `breaches jsonb NOT NULL DEFAULT '[]'`: `[{"kind","at","owner"}]`, `at` — мс | `[]` |
| `timers` | map<string, Timer> | новый `timers jsonb NOT NULL DEFAULT '{}'`: по id таймера `{"due","paused","left","fired","since"}`, мс | нет ключа таймера машины — нулевая запись; при записи — все таймеры машины |
| `linkedTo` | string | новый `linked_to uuid NULL REFERENCES incidents(guid) ON DELETE SET NULL` | `NULL` ↔ `''` |
| `linkedAt` | int | новый `linked_at timestamptz NULL` | `NULL` ↔ `0` |
| `leftGroup` | LeftGroup | новый `left_group jsonb NULL`: `{"primaryId","linkedAt","at"}` | `NULL` ↔ запись из нулей |
| `scenario` | string | `scenario_guid` (есть) | — |
| `eventGuid` | string | `event_guid` (есть) | — |
| — | — | новый `changed_at timestamptz NULL` — момент последнего перехода (RULE-48, BUG-76; машина не читает, планировщик этапа 6 — да) | — |
| — | — | `status_guid` — по состоянию, `model.StatusCodeForState` (как этап 3) | — |

Журнал: новый `incident_journal.kind text NOT NULL DEFAULT 'transition'` с `CHECK (kind IN ('transition', 'system', 'macro', 'external'))` (перечень `JournalEntry.kind` контракта); у записей `actor` `dispatcher` или `system` — `system`, иначе `transition` — как `journalView` в `server.js`. Миграция ставит `system` уже записанным строкам `dispatcher`.

Индексы: `idx_incidents_owner_state ON incidents (customer_guid, owner, state) WHERE deleted_at IS NULL` — `countMine`, `mineOf`; `idx_incidents_linked_to ON incidents (linked_to) WHERE linked_to IS NOT NULL` — `linkedOf`, `groupMembersAt`, семья; `idx_incidents_left_group_primary ON incidents ((left_group->>'primaryId')) WHERE left_group IS NOT NULL` — `groupMembersAt`, семья; соседи — по `event_guid` (индекс `uq_incidents_event_scenario` уже есть).

Старые столбцы `escalated*`, `assignee_user_id`, `assigned_*` не удаляются и машиной не пишутся.

## Структура файлов

| Файл | Что | Задача |
|---|---|---|
| `internal/im/service/storing/migrations/018_incident_machine.sql`; `internal/im/model/{incident.go, journal.go}`, `internal/im/model/dbmodel/{incident.go, journal.go}`, `internal/im/service/storing/{incident_converters.go, journal_converters.go, journal_queries.go}`; `internal/im/handler/test/{migration_018_test.go, intake_store_test.go}` | столбцы, `kind`, модель | 1 |
| `internal/im/model/machine_incident.go`; `internal/im/service/storing/incident_machine_queries.go`; `internal/im/service/transition/{doc.go, row.go, row_test.go}`; `internal/im/handler/test/transition_store_test.go` | строка ↔ инцидент машины | 2 |
| `internal/im/machine/{eval.go, env.go, effect.go, machine.go}` (+ тесты) | `Scope.Refs`, `Action.Target`, gofmt | 3 |
| `internal/im/machine/{effect.go, effect_build.go, machine.go}` (+ тесты) | `Draft.Put`, `Draft.Err`, сверка с черновиком, кэш программ, одна ошибка на эффект | 4 |
| `internal/im/service/transition/{core.go, run.go, errors.go}`, `internal/im/service/transition/transitiontest/{memrepo.go, world.go}`, `internal/im/service/transition/run_test.go` (пакет `transition_test`) | каркас ядра и отказы | 5 |
| `internal/im/service/transition/{form.go, form_test.go}` | проверка формы | 6 |
| `internal/im/service/transition/{effects.go, journal.go, effects_test.go}` | эффекты, журнал, действия мира | 7 |
| `internal/im/service/transition/{refs.go, family.go, family_test.go}` | семья, кандидаты ∪ черновик, версии, повтор | 8 |
| `internal/im/service/transition/{window.go, window_test.go, journal_test.go}` | окно после дедлайна, `once`, `emptyLog` | 9 |
| `internal/im/model/version_conflict.go`; `internal/im/service/storing/{incident_machine_queries.go, journal_queries.go}`; `internal/im/service/transition/{pgrepo.go, pgrepo_test.go}`; `internal/im/handler/test/transition_store_test.go` | хранилище PostgreSQL | 10 |
| `internal/im/service/transition/{world.go, world_test.go}`; `internal/im/handler/test/transition_world_test.go`; `internal/im/machine/intake_test.go` | мир сервера | 11 |
| `internal/im/handler/test/transition_test.go` | ядро на PostgreSQL, конкурентность | 12 |
| `internal/im/service/transition/{create.go, create_test.go}` | `Core.Create` | 13 |
| `internal/im/service/intake/{service.go, store.go, world.go, service_test.go}`, `internal/im/model/intake.go`, `internal/im/appservice/{appservice.go, event/event.go}`, `internal/im/handler/test/intake_test.go`; Delete: `internal/im/ruleselect/` | приём на `Core.Create` | 14 |
| стенд (`~/Work/stand`), кода нет | миграция 018 и `create` на базе `imdb` | 15 |
| `docs/adr/{004-machine-executor.md, 005-transitions-in-transaction.md}`; IM: `research/integration/{40-plan.md, 53-plan-stage4b.md}` | решения, отметки | 16 |

---

### Task 1: Миграция 018 — столбцы машины у инцидента, `kind` у журнала

**Files:**
- Create: `internal/im/service/storing/migrations/018_incident_machine.sql`
- Modify: `internal/im/model/incident.go` (поля машины), `internal/im/model/journal.go` (`Kind`, константы `JournalKindTransition = "transition"`, `JournalKindSystem = "system"`, `func JournalKindOf(actor string) string`), `internal/im/model/dbmodel/{incident.go, journal.go}`, `internal/im/service/storing/{incident_converters.go, journal_converters.go, journal_queries.go}`
- Test: `internal/im/handler/test/migration_018_test.go`; Modify: `internal/im/handler/test/intake_store_test.go`; Test: `internal/im/model/journal_test.go`

**Interfaces:**
- Produces:
  - `model.Incident` — новые поля: `Owner, AssignmentGroup, HoldReasonID, CloseResultID, CloseCauseID, CloseComment, ClosedBy string; EscalationLevel, TransferCount int64; SLABreached bool; ClosedAt, LinkedAt, ChangedAt *time.Time; LinkedTo *uuid.UUID; Breaches, Timers, LeftGroup json.RawMessage` (`LeftGroup` `nil` — `NULL`);
  - конвертер модели в DTO: `Breaches` `nil` — `'[]'`, `Timers` `nil` — `'{}'` (`InsertIncident` пишет все столбцы — `Whitelist("*")`, и `NULL` в `NOT NULL` упал бы); обратно читаются и старые поля, которые до сих пор терялись (`Escalated*`, `Assignee*`, `Assigned*`, `UpdatedAt`);
  - `model.JournalEntry.Kind string`; `model.JournalKindOf("dispatcher") == "system"`, `("system") == "system"`, `("op1") == "transition"`; `InsertJournalEntries` пишет `kind`, пустой — `JournalKindOf(actor)`.

Миграция: `-- +migrate Up` — `ALTER TABLE incidents ADD COLUMN …` по таблице «Строка базы ↔ инцидент машины»; индексы `idx_incidents_owner_state`, `idx_incidents_linked_to`, `idx_incidents_left_group_primary` оттуда же; `ALTER TABLE incident_journal ADD COLUMN kind text NOT NULL DEFAULT 'transition'`, `ADD CONSTRAINT incident_journal_kind_check CHECK (…)`, `UPDATE incident_journal SET kind = 'system' WHERE actor IN ('dispatcher', 'system')`. `-- +migrate Down` — как у 012: `DROP INDEX IF EXISTS …`, `ALTER TABLE incident_journal DROP CONSTRAINT IF EXISTS …, DROP COLUMN IF EXISTS kind`, `ALTER TABLE incidents DROP COLUMN IF EXISTS …` по каждому новому столбцу.

- [x] **Step 1: Тесты**

```go
func TestMigration018(t *testing.T)
  // как migration_017_test: сырой pgx, транзакция всегда откатывается. Выполнить Down-часть 018 (тот же файл, раздел Down),
  // вставить сырым SQL событие, инцидент (номер — ReserveIncidentNumbers) и две записи журнала: actor "dispatcher" и "op1";
  // выполнить storing.MigrationUpSQL("018_incident_machine.sql") ⇒ kind: "system" и "transition"; у инцидента owner "",
  // escalation_level 0, sla_breached false, breaches '[]', timers '{}', closed_at, linked_to, left_group — NULL;
  // три индекса — в pg_indexes; INSERT журнала с kind "nope" ⇒ ошибка 23514 (check_violation)
func TestIncidentMachineColumnsRoundTrip(t *testing.T)
  // inRolledBackTx: InsertIncident со всеми новыми полями (owner "op1", escalation_level 2, timers {"reaction":{"due":1790845440000,…}},
  // linked_to — guid другого инцидента, closed_at 2026-10-01T09:00:00.123Z) ⇒ GetIncident — то же самое, время — до мс;
  // и старые поля (escalated true, assignee_user_id 7, updated_at) — тоже читаются; InsertIncident с Breaches и Timers nil ⇒ '[]' и '{}'
func TestJournalEntriesRoundTrip(t *testing.T) // тот же тест этапа 3 + Kind: пустой у "dispatcher" ⇒ "system"; "op1" с Kind "" ⇒ "transition"
func TestJournalKindOf(t *testing.T)           // пакет model: три случая выше
```

- [x] **Step 2: Тесты падают**

Run: `cd ~/Work/incident-manager-server && source ~/go/offline-env.sh && go test ./internal/im/model/ 2>&1 | tail -3 && TESTDB='postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable' && IM_TEST_DB_URL=$TESTDB go test ./internal/im/handler/test/ -run 'TestMigration018|TestIncidentMachineColumnsRoundTrip|TestJournalEntriesRoundTrip' 2>&1 | tail -5`
Expected: FAIL — не собирается (`Owner`, `Kind`, `JournalKindOf` не объявлены).

- [x] **Step 3: Реализация** миграции, модели, DTO, конвертеров.

- [x] **Step 4: Тесты проходят, этап 3 цел**

Run: `go build ./... && go test ./internal/im/model/ && make test-local 2>&1 | tail -8 && golangci-lint run ./...`
Expected: PASS всех пакетов; тесты этапа 3 (`TestEvent*`, `TestProcess_*`) — без правок; lint — 0.

- [x] **Step 5: Commit**

Сообщение: «Этап 4б: миграция 018 — поля машины у инцидента (владелец, адресат, таймеры, нарушения, связи, закрытие) и kind у журнала; старые поля читаются обратно».
Run: `git add internal/im/service/storing internal/im/model internal/im/handler/test/migration_018_test.go internal/im/handler/test/intake_store_test.go && git commit -q -F .git/COMMIT_MSG_STAGE4B`

---

### Task 2: Строка базы ↔ инцидент машины

**Files:**
- Create: `internal/im/model/machine_incident.go`; `internal/im/service/transition/{doc.go, row.go}`; Test: `internal/im/service/transition/row_test.go`
- Create: `internal/im/service/storing/incident_machine_queries.go`; Test: `internal/im/handler/test/transition_store_test.go`

**Interfaces:**
- Consumes: задача 1; `machine.Vendored()` — id таймеров машины.
- Produces:
  - `type model.MachineIncident struct { Incident; EventTypeUID string; PriorityValue int64; OccurredAt time.Time }`;
  - `func (s *Store) GetMachineIncidents(ctx model.AppContext, customer uuid.UUID, guids []uuid.UUID) ([]*model.MachineIncident, error)` — с соединениями `events`, `source_event_types`, `priorities`; порядок — `number`; удалённые (`deleted_at`) не отдаются;
  - `func ToMachine(mi *model.MachineIncident, timerIDs []string) (map[string]any, error)` — данные машины: `string`, `int64`, `bool`, `[]any`, `map[string]any`; `jsonb` — `json.Decoder.UseNumber`, целое — `int64`, дробное — ошибка;
  - `func FromMachine(x map[string]any, inc *model.Incident) error` — пишет в `inc` только изменяемые поля; `id`, `number`, `eventType`, `priority`, `occurredAt`, `scenario`, `eventGuid` в `x` отличаются от `inc` — ошибка `read-only field <имя>`; `timers` — все ключи из `x`;
  - `func TimerIDs(m *machine.Machine) []string` — id из `timers` машины по порядку.

- [x] **Step 1: Тесты**

```go
func TestToMachineTypes(t *testing.T)
  // EscalationLevel 2 ⇒ int64(2); Timers {"reaction":{"due":1790845440000}} ⇒ timers.reaction.due int64(1790845440000),
  // timers.resolution и timers.hold — {due 0, paused false, left 0, fired 0, since 0}; ClosedAt nil ⇒ closedAt int64(0);
  // LinkedTo nil ⇒ linkedTo ""; LeftGroup nil ⇒ {primaryId "", linkedAt 0, at 0}; Number 1851 ⇒ "INC-1851";
  // EventTypeUID "fire", PriorityValue 50, OccurredAt 2026-10-01T09:00:00Z ⇒ eventType "fire", priority 50, occurredAt 1790845200000
func TestToMachineRejectsFloat(t *testing.T)   // Timers {"reaction":{"due":1.5}} ⇒ ошибка; Breaches [{"at": 1e3}] ⇒ ошибка
func TestFromMachineRoundTripPool(t *testing.T)
  // инциденты пула api/im/operator/cel-vectors.json, у которых id, eventGuid и scenario — UUID, а number — "INC-<цифры>"
  // (на 6e86123 таких 1002 из 1029: у 27 синтетических id вида "s1" и пустые eventGuid и scenario, у 4 — пустой number;
  // require — не меньше 1000): MachineIncident из неизменяемых полей пула, FromMachine(x) ⇒ ToMachine ⇒ равен x,
  // где у x недостающие таймеры машины дописаны нулевыми записями (у инцидента пула 653a46ba2cbf0a75 нет reaction)
func TestFromMachineReadOnlyFields(t *testing.T) // x["priority"] = 75 при PriorityValue 50 ⇒ ошибка "read-only field priority"
func TestGetMachineIncidents(t *testing.T)     // база, inRolledBackTx: событие с типом uid "fire" и occurred_at, приоритет value 50, два инцидента
                                               // с номерами из счётчика n и n+1, вставленные в обратном порядке ⇒ порядок [n, n+1]; eventType "fire",
                                               // priority 50; удалённый — не отдаётся; инцидент другого арендатора — не отдаётся
```

- [x] **Step 2: Тесты падают**

Run: `go test ./internal/im/service/transition/ 2>&1 | tail -3`
Expected: FAIL — пакета нет.

- [x] **Step 3: Реализация**

- [x] **Step 4: Тесты проходят**

Run: `go test ./internal/im/service/transition/ && TESTDB='postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable' && IM_TEST_DB_URL=$TESTDB go test ./internal/im/handler/test/ -run TestGetMachineIncidents && golangci-lint run ./...`
Expected: PASS; lint — 0.

- [x] **Step 5: Commit**

Сообщение: «Этап 4б: инцидент машины из строки базы и обратно — целые числа, пусто как в машине, все таймеры; неизменяемые поля только читаются».
Run: `git add internal/im/model internal/im/service/storing internal/im/service/transition internal/im/handler/test/transition_store_test.go && git commit -q -F .git/COMMIT_MSG_STAGE4B`

---

### Task 3: Исполнитель — кандидаты фактов над инцидентами, снимок цели действия, gofmt

**Files:**
- Modify: `internal/im/machine/eval.go` (`Scope.Refs`, `RefSource`; `''` → `""` в комментарии строки 389), `internal/im/machine/env.go` (`refFact` берёт список у `Refs`), `internal/im/machine/effect.go` (`Action.Target`), `internal/im/machine/machine.go` (выравнивание в строке 23)
- Test: `internal/im/machine/{eval_test.go, effect_test.go}` (в `eval_test.go:226` — `''` → `""` в комментарии)

**Interfaces:**
- Produces:
  - `type RefSource interface { Candidates(fact string, args []any) ([]map[string]any, error) }` — список факта с `ref`: все инциденты, которых он может вернуть (можно больше), в порядке вызывающего; аргументы — данные, инцидент — словарь целиком;
  - `Scope.Refs RefSource` — задан: факт с `ref` вычисляет своё выражение над `Refs.Candidates(имя, аргументы)`, а не над `Scope.Incidents` или черновиком; не задан — как в 4а (векторы CEL не меняются);
  - `Action.Target map[string]any` — инцидент действия (`args.incident`, у `shareAnswers` — `args.from`) таким, каким он был в черновике в момент действия; нет инцидента — `nil`.

- [x] **Step 1: Тесты**

```go
func TestRefSourceAnswersRefFacts(t *testing.T)
  // копия: limits.maxActive = 1; Scope.Refs отдаёт [a (in_progress, op1), b (new, op1)] ⇒ withinActiveLimit ⇒
  // Fail{Key "workflow.guard.active_limit", Vars {"n": 1, "id": a.number}}; Refs вызван с ("countMine", ["op1", "in_progress", x.id]);
  // Scope.Incidents при этом nil — не ErrNoIncidents
func TestRefSourceErrorPropagates(t *testing.T) // Candidates ⇒ errBoom ⇒ errors.Is(err, errBoom)
func TestEffectRefSourceSeesWrites(t *testing.T)
  // recordBreach, как TestEffectOverlayVisible, но Scope.Refs — функция над d.Incidents() того же черновика ⇒ тот же итог
func TestActionTargetIsSnapshot(t *testing.T)
  // копия: эффект _logThenSet: [world log {incident: incident, key: 'k'}; set incident.owner = 'x'] ⇒
  // Actions()[0].Target["owner"] == "", Get(id)["owner"] == "x"
```

- [x] **Step 2: Тесты падают**

Run: `go test ./internal/im/machine/ -run 'RefSource|ActionTarget' 2>&1 | tail -3`
Expected: FAIL — не собирается (`RefSource`, `Target` не объявлены).

- [x] **Step 3: Реализация** и gofmt трёх мест.

- [x] **Step 4: Тесты проходят, векторы 4а — тоже**

Run: `go test -race ./internal/im/machine/ -v -run TestVectors 2>&1 | grep -E 'vectors [0-9]|^ok|FAIL' && go test -race ./internal/im/machine/ ./internal/im/service/intake/ && gofmt -l internal/im && golangci-lint run ./...`
Expected: `ok`; `vectors 2324 …, mismatches 0, tape misses 0`; `gofmt -l` пусто; lint — 0.

- [x] **Step 5: Commit**

Сообщение: «Этап 4б: исполнитель — кандидаты фактов над инцидентами от вызывающего (Scope.Refs), снимок инцидента у действия мира; gofmt».
Run: `git add internal/im/machine && git commit -q -F .git/COMMIT_MSG_STAGE4B`

---

### Task 4: Исполнитель — черновик для ядра и хвосты 4а

**Files:**
- Modify: `internal/im/machine/effect.go` (`Draft.Put`, `Draft.Err`, сверка `Scope.Incident` с черновиком, `view` не глотает ошибку), `internal/im/machine/effect_build.go` (программа строится из приведённых аргументов), `internal/im/machine/machine.go` (одна ошибка сборки эффекта — один раз)
- Test: `internal/im/machine/{effect_test.go, machine_test.go}`

**Interfaces:**
- Produces:
  - `func (d *Draft) Put(x map[string]any) error` — заменить инцидент черновика с этим `id` (нет такого — ошибка); считается записью (`Changed`);
  - `func (d *Draft) Err() error` — ошибка, после которой черновик не годится, в том числе ошибка `toPlain` в `view` (раньше — молча исходный словарь);
  - `var ErrScopeDraftMismatch = errors.New("machine: scope incident disagrees with the draft")` — `Effect`: черновик держит id, а `Scope.Incident["state"]` другое.

Аргументы перехода приводятся к данным (JSON туда и обратно с `UseNumber`, целые — `int64`), программа строится из приведённых, ключ кэша — их JSON (как сейчас). Ошибка сборки, которую дают и сборка по переходу, и сборка как `call`, в `errors.Join` — один раз (по тексту).

- [x] **Step 1: Тесты**

```go
func TestDraftPut(t *testing.T)                 // Put(x со state "in_progress") ⇒ Changed — [x.id], Get(x.id)["state"] == "in_progress"; Put(id "nope") ⇒ ошибка
func TestEffectScopeStateDisagreesWithDraft(t *testing.T)
  // черновик: x в "in_progress"; Effect(setOwner, Scope.Incident = x со state "new") ⇒ errors.Is(err, ErrScopeDraftMismatch); со state "in_progress" ⇒ nil
func TestDraftViewErrorIsKept(t *testing.T)     // в черновик записан record с полем не-данными (внутренний помощник теста) ⇒ Incidents(); d.Err() != nil
func TestEffectProgramFromNormalizedArgs(t *testing.T)
  // две свежие машины: в первой logSiblings сначала с []any{[]string{"false_alarm"}, k}, затем с []any{[]any{"false_alarm"}, k};
  // во второй — в обратном порядке ⇒ Actions всех четырёх вызовов равны. Ключ кэша уже сейчас общий (json.Marshal), поэтому тест
  // может пройти и до правки: тогда сборка уже не зависит от вида значения в Go — записать в журнал работ, правка effect_build.go — только приведение
func TestLoadReportsBrokenEffectOnce(t *testing.T)
  // копия: у pauseTimer в do — "incident.nope == 1" ⇒ в тексте ошибки Load каждая строка "registries.effects.pauseTimer…" — один раз
```

- [x] **Step 2: Тесты падают**

Run: `go test ./internal/im/machine/ -run 'DraftPut|ScopeState|ViewError|NormalizedArgs|BrokenEffectOnce' 2>&1 | tail -3`
Expected: FAIL — не собирается (`Put`, `Err`, `ErrScopeDraftMismatch` не объявлены).

- [x] **Step 3: Реализация**

- [x] **Step 4: Тесты проходят, векторы 4а — тоже**

Run: `go test -race ./internal/im/machine/ -v -run TestVectors 2>&1 | grep -E 'vectors [0-9]|^ok|FAIL' && go test -race ./internal/im/machine/ && gofmt -l internal/im && golangci-lint run ./...`
Expected: `ok`; `mismatches 0, tape misses 0`; `gofmt -l` пусто; lint — 0.

- [x] **Step 5: Commit**

Сообщение: «Этап 4б: исполнитель — Draft.Put и Draft.Err, ошибка при расхождении Scope с черновиком; программа эффекта из приведённых аргументов, одна ошибка сборки на эффект».
Run: `git add internal/im/machine && git commit -q -F .git/COMMIT_MSG_STAGE4B`

---

### Task 5: Ядро — каркас перехода и отказы

**Files:**
- Create: `internal/im/service/transition/{core.go, run.go, errors.go}`
- Create: `internal/im/service/transition/transitiontest/{memrepo.go, world.go}` (пакет `transitiontest`: только для тестов, обычный пакет — им пользуются и тесты с базой в 4б-2)
- Test: `internal/im/service/transition/run_test.go` (пакет `transition_test`)

**Interfaces:**
- Consumes: задачи 2, 3, 4.
- Produces:
  - `type Core struct{…}`; `func New(m *machine.Machine) (*Core, error)`;
  - `type Op struct { Customer uuid.UUID; Transition string; IDs []string; PrimaryID string; Form map[string]any; Surface, Me string; Now int64; Expect map[string]int64 }` — `Form` — значения формы как прислал клиент; `Now` — мс; `Expect` — версии, которые видел вызывающий (`nil` — не сверять; `If-Match` и `expectedVersions` — 4в);
  - `func (c *Core) Run(ctx model.AppContext, repo Repo, w World, op Op) (*Result, error)` — `op.IDs` из одного id;
  - `type Row struct { Incident map[string]any; Version, Order int64 }` — `Order` — номер у PostgreSQL, место в списке у `MemRepo`;
  - `type JournalEntry struct { ID uuid.UUID; IncidentID, Actor, Kind, Transition, TemplateKey string; At int64; Vars map[string]any }`;
  - `type Write struct { Incidents []Row; Journal, Replaced []JournalEntry; Now int64 }` — `Incidents[i].Version` — прочитанная под блокировкой, хранилище пишет `Version + 1 … WHERE version = Version`; `Journal` — в порядке решения 13, `ID` уже выданы (решение 21);
  - `type Repo interface { DoInTx(ctx model.AppContext, fn func() error) error; LockFamily(ctx model.AppContext, customer uuid.UUID, ids []string) ([]Row, error); Candidates(ctx model.AppContext, customer uuid.UUID, fact string, args []any) ([]Row, error); JournalAt(ctx model.AppContext, ids []string, at int64) ([]JournalEntry, error); Write(ctx model.AppContext, customer uuid.UUID, w *Write) error }`;
  - `type World interface { machine.World; ActorName(id string) (any, error); Progress(incident map[string]any) (filled, total int64, err error); StepNumber(incident map[string]any) (int64, error); SetCursor(incident map[string]any) error; ShareAnswers(from, to map[string]any, at int64) (int64, error) }` — `ActorName` отдаёт строку или ключ-список (`["workflow.label.unassigned"]`), как `rawName` в `server.js`;
  - `type Result struct { Refusal *Refusal; Incidents []Row; Journal map[string][]JournalEntry; After []After; External map[string][]External; Facts map[string]Facts; Canceled map[string]string }` — `Incidents` — записанные, с новой версией, по `Order`;
  - `type Refusal struct { Key string; Vars map[string]any; Guard, Code, ID string; NotFrom bool }` — отказ ядра (`{ok: false}` прототипа); ничего не записано;
  - `type After struct { Action, Incident, Actor, TransitionID, Who, By, About string; Recipients []string; Alert bool }`; `type External struct { Fn, Target string }`; `type Facts struct { From, To Snap; Breach string }`; `type Snap struct { State, Owner, Addressee string; Breaches int }`;
  - `var ErrNotFound`, `var ErrFamilyChanged`; `type VersionConflict struct { ID string; Current int64 }`, `func (e *VersionConflict) Error() string` — ошибка `*VersionConflict`;
  - `transitiontest.NewMemRepo(rows []transition.Row) *MemRepo` — семья — по решению 15 над своими строками, кандидаты — все строки, `Write` — копия, `Writes() int`, `Rows()`, `Journal()`, `LockCalls() int`, `HideFromFamily(id string, attempts int)` — не отдавать строку в первых `attempts` вызовах `LockFamily` (`-1` — всегда); `transitiontest.FactWorld` — факты и методы `World` функциями из словаря, неизвестный — ошибка; `SetCursorCalls() []string`.

Каркас `Run` (как начало `run` в `engine.js`): `DoInTx` → `LockFamily` (нет инцидента — `ErrNotFound`) → `Expect` (`*VersionConflict`) → переход машины (нет — `Refusal{Key: "workflow.error.unknown_action"}`) → `machine.Availability` (`Scope.Refs` — кандидаты без черновика; отказ — `Key`, `Vars`, `Guard`, `NotFrom`). Форма — задача 6, эффекты — задача 7, семья и версии — задача 8, окно — задача 9.

- [x] **Step 1: Тесты**

Инцидент `inc(id, number, state, owner)` — полный, приоритет 50, все три таймера; мир по умолчанию (`FactWorld`): `can` — true, `agentState` — `ready`, `access` — true, `isGroup` — false, `members` — `[]`, `ActorName(id)` — `"Имя " + id`, `""` — `["workflow.label.unassigned"]`, `Progress` — (1, 3), `StepNumber` — 2. `Me` — `op1`, `Now` — 1790845200000.

```go
func TestRunRefusalWritesNothing(t *testing.T)
  // can incident:claim false ⇒ Refusal{Key "workflow.guard.no_permission", Vars {"p": "incident:claim"}, Guard "hasPermission"}; repo.Writes() == 0
func TestRunNotFromState(t *testing.T)      // x closed ⇒ Refusal{Key "workflow.guard.wrong_state", NotFrom true}
func TestRunVersionConflict(t *testing.T)   // Expect {x: 3}, в репозитории 2 ⇒ var vc *VersionConflict; errors.As(err, &vc); *vc == VersionConflict{ID: x, Current: 2}
func TestRunNotFound(t *testing.T)          // id не из репозитория ⇒ errors.Is(err, ErrNotFound)
func TestRunUnknownTransition(t *testing.T) // "nope" ⇒ Refusal{Key "workflow.error.unknown_action"}
```

- [x] **Step 2: Тесты падают**

Run: `go test ./internal/im/service/transition/ -run 'TestRun' 2>&1 | tail -3`
Expected: FAIL — не собирается (`Run` не объявлен).

- [x] **Step 3: Реализация** (каждая функция — в пределах `funlen`).

- [x] **Step 4: Тесты проходят**

Run: `go test -race ./internal/im/service/transition/... && golangci-lint run ./...`
Expected: PASS; lint — 0.

- [x] **Step 5: Commit**

Сообщение: «Этап 4б: ядро перехода — каркас: семья под блокировкой, сверка версии, доступность; отказ — не ошибка и ничего не пишет».
Run: `git add internal/im/service/transition && git commit -q -F .git/COMMIT_MSG_STAGE4B`

---

### Task 6: Ядро — проверка формы

**Files:**
- Create: `internal/im/service/transition/form.go`; Test: `internal/im/service/transition/form_test.go`

**Interfaces:**
- Consumes: задача 5; `machine.UIRule` (`forms.<id>.fields.<имя>.requiredExpr`, `visibleExpr`, `optionExpr`, `enabledExpr`).
- Produces: `func (c *Core) checkForm(tr, incident map[string]any, form map[string]any, s *machine.Scope) (*Refusal, error)` — внутри `Run` после доступности.

Как `validateForm`: поля формы перехода по порядку; невидимое — не обязательно; обязательное пустое (нет значения или одни пробелы) — `workflow.error.reason_required` у `kind: text`, иначе `workflow.error.field_required {name: [labelKey]}`; у непустого поля с `source` значение должно быть видно, среди вариантов (`reasonCatalog:<id>` — позиции справочника машины, `transferTargets` — факт мира `transferTargets`), пройти `optionExpr` и `enabledExpr`; иначе `workflow.error.field_invalid {name: [labelKey]}`, `Code: "FORM_FIELD_INVALID"`.

- [x] **Step 1: Тесты** (мир задачи 5)

```go
func TestRunFormRequired(t *testing.T)     // hold у владельца op1 без reasonId ⇒ Refusal{Key "workflow.error.field_required", Vars {"name": ["workflow.form.hold.field.reasonId"]}}
func TestRunFormInvalid(t *testing.T)      // hold reasonId "nope" ⇒ Refusal{Key "workflow.error.field_invalid", Vars {"name": ["workflow.form.hold.field.reasonId"]}, Code "FORM_FIELD_INVALID"}
func TestRunFormHiddenFieldNotRequired(t *testing.T) // close resultId "processed" без causeId ⇒ отказа формы нет; resultId "mass" без causeId ⇒ field_required causeId
func TestRunFormTransferTarget(t *testing.T) // transfer targetId "op9", transferTargets ⇒ ["op2"] ⇒ field_invalid targetId; "op2" ⇒ отказа формы нет
func TestRunFormSpacesAreEmpty(t *testing.T) // hold reasonId "  " ⇒ field_required
```

- [x] **Step 2: Тесты падают**

Run: `go test ./internal/im/service/transition/ -run 'TestRunForm' 2>&1 | tail -3`
Expected: FAIL — отказа формы нет (дальше идёт каркас без эффектов).

- [x] **Step 3: Реализация**

- [x] **Step 4: Тесты проходят**

Run: `go test -race ./internal/im/service/transition/... && golangci-lint run ./...`
Expected: PASS; lint — 0.

- [x] **Step 5: Commit**

Сообщение: «Этап 4б: ядро перехода — проверка формы по правилам интерфейса машины: обязательные поля, варианты справочника и адресатов».
Run: `git add internal/im/service/transition && git commit -q -F .git/COMMIT_MSG_STAGE4B`

---

### Task 7: Ядро — эффекты, журнал, действия мира

**Files:**
- Create: `internal/im/service/transition/{effects.go, journal.go}`; Test: `internal/im/service/transition/effects_test.go`

**Interfaces:**
- Consumes: задачи 4–6.
- Produces: `Run` целиком без окна: `Result.Incidents`, `Journal`, `After`, `External`, `Facts`; `Write` в хранилище.

После формы (решения 6, 13, 14, 21): черновик из семьи (`NewDraft` по `Order`) → `before` = инцидент черновика, `previousOwnerName` = `ActorName(addressee(before))`, `Put` со `state` = `to` → эффекты перехода по порядку (`Scope.Incident` — инцидент черновика, `Before`, `Form`, `Actor` = `Me`; неизвестный эффект — ошибка) → действия `Draft.Actions()` по порядку: `log` — подстановки из `args.vars` или, если их нет, как `vars()` прототипа по `Action.Target` (`comment` из формы, `stepNumber`, `holdReasonLabel`, `targetName` — `ActorName(addressee(цель))`, `escalationLevel`, `closeResultLabel`, `filledSteps`, `totalSteps`, `escalationReason` — `[escalation.reasonKey]`, `primaryNumber`) плюс `previousOwnerName`; `actor` — из действия или шага; `kind` — `JournalKindOf`; `setCursor`, `shareAnswers` — `World` (у `shareAnswers` с `n > 0` и `logKey` — запись основному `{number, n}`); `notify`, `evict`, `touch` — в `After`; `notify`, `command` — в `External` инцидента шага → `Facts` (`From` — до операции, `To` — после эффектов перехода) → выдать `ID` записям → `Write`. Любая ошибка — `(nil, err)`, `DoInTx` откатывает.

- [x] **Step 1: Тесты** (мир задачи 5)

```go
func TestRunClaim(t *testing.T)
  // x new ⇒ Refusal nil; Incidents — [x] с version 2: state "in_progress", owner "op1";
  // Journal[x] — [{TemplateKey "workflow.journal.claim", Actor "op1", Kind "transition", At Now, Transition "claim"}];
  // SetCursorCalls — [x.id]; After пусто; External[x] пусто; Facts[x] — From {new, "", "", 0}, To {in_progress, op1, op1, 0}
func TestLogVars(t *testing.T)
  // claim ⇒ Vars == {comment "", stepNumber 2, holdReasonLabel "", targetName "Имя op1", escalationLevel 0, closeResultLabel "",
  // filledSteps 1, totalSteps 3, escalationReason ["workflow.escalation.reason"], primaryNumber "", previousOwnerName ["workflow.label.unassigned"]}
func TestRunEffectErrorIsGoError(t *testing.T)
  // копия машины: у claim первым эффектом stopTimer ["nope"] ⇒ err != nil, Result nil; repo.Writes() == 0
func TestRunStateSetBeforeEffects(t *testing.T)
  // копия: у claim первым эффектом _probe: [set incident.result = incident.state; set incident.closedBy = before.state] ⇒ result "in_progress", closedBy "new"
func TestRunShareAnswersLog(t *testing.T)
  // копия: у claim эффект copyAnswersToPrimary ['workflow.journal.answers_moved'] с формой {primaryId: p}, ShareAnswers ⇒ 2 ⇒
  // Journal[p] — [{TemplateKey "workflow.journal.answers_moved", Vars {"number": x.number, "n": 2}}]; ShareAnswers ⇒ 0 ⇒ записи нет
func TestJournalIDsInOrder(t *testing.T)    // у записей одной операции ID — UUID v7 по возрастанию в порядке Journal
```

- [x] **Step 2: Тесты падают**

Run: `go test ./internal/im/service/transition/ -run 'TestRunClaim|TestLogVars|TestRunEffectError|TestRunStateSet|TestRunShareAnswers|TestJournalIDs' 2>&1 | tail -3`
Expected: FAIL — `Incidents` и `Journal` пусты (эффектов ещё нет).

- [x] **Step 3: Реализация**

- [x] **Step 4: Тесты проходят**

Run: `go test -race ./internal/im/service/transition/... && golangci-lint run ./...`
Expected: PASS; lint — 0.

- [x] **Step 5: Commit**

Сообщение: «Этап 4б: ядро перехода — эффекты на черновике, состояние to перед эффектами, журнал с подстановками машины, действия мира в транзакции и после неё».
Run: `git add internal/im/service/transition && git commit -q -F .git/COMMIT_MSG_STAGE4B`

---

### Task 8: Ядро — семья, кандидаты с черновиком, версии, повтор

**Files:**
- Create: `internal/im/service/transition/{refs.go, family.go}`; Test: `internal/im/service/transition/family_test.go`

**Interfaces:**
- Consumes: задачи 5, 7.
- Produces: `Scope.Refs` эффектов — список решения 18; проверка «запись вне семьи»; версии решения 16; повтор решения 19.

Запись (`Draft.Changed()`), запись журнала или `touch` у инцидента не из семьи — `ErrFamilyChanged`. Элемент `forEach`, которого нет в черновике, — строка кандидатов, прочитанная в этой же транзакции; писать в него можно, только если он из семьи (так закрыт хвост 4а «элемент добавляется из записи, а не загружается по id»). `ErrFamilyChanged` — повтор операции целиком (новый `DoInTx`), всего до 3 попыток.

- [x] **Step 1: Тесты** (мир задачи 5)

```go
func TestRunVersionPlusOneForChanged(t *testing.T)
  // close с resultId "false_alarm" у x; сосед s (тот же eventGuid, in_progress, owner "op2") ⇒ Incidents — [x, s] (по Order), у обоих version +1;
  // Journal[s] — [{TemplateKey "workflow.journal.sibling_closed", Vars {"number": x.number, "result": ["workflow.catalog.close_result.false_alarm"]}}];
  // After — [touch s (Actor "op1"), notify s (Recipients ["op2"], About x, Alert false)];
  // External[x] — [{Fn "notify", Target "op2"}, {Fn "externalCommand", Target "axxondata.export_incident"}]
func TestRefsSeeDraft(t *testing.T)
  // копия: у claim после setOwner эффект _count: [set incident.transferCount = countMine(me, 'in_progress', '')];
  // Repo, у которого Candidates отдаёт [] (SQL по старым полям x не нашёл бы) ⇒ transferCount 1 (x из черновика)
func TestRunWriteOutsideFamilyIsError(t *testing.T)
  // HideFromFamily(s, -1), Candidates отдаёт s ⇒ close false_alarm ⇒ errors.Is(err, ErrFamilyChanged); Writes() == 0; LockCalls() == 3
func TestRunRetriesFamilyChanged(t *testing.T) // HideFromFamily(s, 1) ⇒ вторая попытка проходит: Result без отказа, LockCalls() == 2, Writes() == 1
```

- [x] **Step 2: Тесты падают**

Run: `go test ./internal/im/service/transition/ -run 'PlusOne|RefsSeeDraft|OutsideFamily|RetriesFamily' 2>&1 | tail -3`
Expected: FAIL — сосед не записан, `countMine` даёт 0, ошибки `ErrFamilyChanged` нет.

- [x] **Step 3: Реализация**

- [x] **Step 4: Тесты проходят**

Run: `go test -race ./internal/im/service/transition/... && golangci-lint run ./...`
Expected: PASS; lint — 0.

- [x] **Step 5: Commit**

Сообщение: «Этап 4б: ядро перехода — факты над инцидентами по кандидатам с черновиком, версия +1 изменённым, запись вне семьи — повтор операции, потом ошибка».
Run: `git add internal/im/service/transition && git commit -q -F .git/COMMIT_MSG_STAGE4B`

---

### Task 9: Окно после дедлайна, `once`, запись «некому»

**Files:**
- Create: `internal/im/service/transition/window.go`; Modify: `internal/im/service/transition/{run.go, journal.go}`
- Test: `internal/im/service/transition/{window_test.go, journal_test.go}`

**Interfaces:**
- Consumes: задачи 7, 8.
- Produces: `Result.Canceled[id]` — id отменённого перехода по таймеру; `Result.Facts[id].Breach` — вид нарушения отменённого перехода; `Write.Replaced` — записи прежних операций того же момента, у которых `once` заменил подстановки.

Окно (как `overridden`, `windowBefore`, `windowAfter`; `invariants.manualWinsOverTimer.graceSec` машины): переходы `trigger: timer` из нынешнего состояния с условием `timerExpired [t]`; дедлайн `due` ≠ 0, `due ≤ now < due + graceSec·1000`, `timers[t].fired ≠ due`, переход не в `timers[t].continuesOn`; условия перехода выполняются при `Now = due`; из подходящих — с наименьшим `due`, при равенстве — первый по машине. Найден (после формы, до черновика шага): `before` окна = инцидент до действия, затем `timers[t].fired = due` в черновике; `before` шага берётся уже после отметки (так `celApply` снимает его с черновика, где отметка есть). После эффектов шага и его «некому» (`Facts.To` взят до окна) — эффекты `recordBreach` отменённого перехода по его аргументам на том же черновике (`Actor` `dispatcher`, `Deadline` = `due`, `Before` = `before` окна, состояние не меняется); `Facts.Breach` — их первый аргумент; запись `workflow.journal.timer_overridden {timer: [labelKey таймера], transition: [labelKey отменённого]}` от `dispatcher` — первой в хвосте инцидента (решение 13). `once` у `log`: запись с тем же ключом и `at == now` у того же инцидента — в этой операции или в `JournalAt` — получает новые подстановки, новой записи нет. `emptyLog`: у `notify` без получателей — запись `emptyLog` с подстановками `{}` от шага, после записей эффектов шага, в порядке `notify`.

- [x] **Step 1: Тесты**

Мир задачи 5; инцидент x `new`, `timers.reaction.due` = D = 1790845200000; эскалировать некому (`can` для `petrova` и `noc` — false).

```go
func TestRunWindowAfterDeadline(t *testing.T)
  // claim при Now = D + 1000 ⇒ Canceled {x: "escalation_ceiling"}; x.breaches — [{kind "reaction", at D, owner ""}], slaBreached true,
  // timers.reaction.fired == D; Facts[x].Breach "reaction", Facts[x].To.Breaches 0; Journal[x] — [timer_overridden (Actor "dispatcher", Kind "system",
  // Vars {"timer": ["workflow.timer.reaction"], "transition": ["workflow.transition.escalation_ceiling"]}), claim (Actor "op1")]
func TestRunWindowOver(t *testing.T)          // Now = D + 3000 ⇒ Canceled пусто, breaches пусто
func TestRunWindowContinuesOn(t *testing.T)   // transfer (continuesOn у reaction) при Now = D + 1000, targetId "op2" ⇒ Canceled пусто
func TestRunWindowAlreadyFired(t *testing.T)  // timers.reaction.fired == D ⇒ Canceled пусто
func TestRunWindowGuardsAtDeadline(t *testing.T)
  // копия: escalation.enabled false ⇒ отменён "reaction_overdue", а не escalation_ceiling (условия — на момент D)
func TestLogOnce(t *testing.T)
  // копия: у claim два эффекта [world log {incident, key: 'k', vars: {'n': 1}, once: true}], второй с {'n': 2} ⇒ Journal[x] — одна запись k с {"n": 2};
  // JournalAt отдаёт запись k прежней операции в момент Now ⇒ новой записи k нет, Write.Replaced — [та запись с {"n": 2}], x — version +1
func TestEmptyLogAfterOperationRows(t *testing.T)
  // копия: у claim после appendLog — notify ['alerts.target', true]; isGroup('grp-leads') ⇒ true, members('grp-leads') ⇒ [] ⇒
  // Journal[x] — [claim, alert_no_recipient (Actor "op1", Vars {})]; After — [notify {Incident x, Recipients [], Alert true}]
```

- [x] **Step 2: Тесты падают**

Run: `go test ./internal/im/service/transition/ -run 'Window|LogOnce|EmptyLog' 2>&1 | tail -3`
Expected: FAIL — `Canceled` пуст, записи `timer_overridden` нет, у `once` две записи.

- [x] **Step 3: Реализация**

- [x] **Step 4: Тесты проходят**

Run: `go test -race ./internal/im/service/transition/... && golangci-lint run ./...`
Expected: PASS; lint — 0.

- [x] **Step 5: Commit**

Сообщение: «Этап 4б: ручное действие в окне после дедлайна отменяет переход по таймеру — нарушение и запись в той же транзакции, запись о таймере первой; log.once и запись «некому» — как у прототипа».
Run: `git add internal/im/service/transition && git commit -q -F .git/COMMIT_MSG_STAGE4B`

---

### Task 10: Хранилище PostgreSQL — семья, кандидаты, запись с версией

**Files:**
- Create: `internal/im/model/version_conflict.go`
- Modify: `internal/im/service/storing/incident_machine_queries.go`, `internal/im/service/storing/journal_queries.go`
- Create: `internal/im/service/transition/{pgrepo.go, pgrepo_test.go}`
- Modify: `internal/im/handler/test/transition_store_test.go`

**Interfaces:**
- Consumes: задачи 1, 2, 5.
- Produces (в `storing`, на типах `model`, внутри `DoInTx` вызывающего):
  - `type model.VersionConflictError struct { GUID uuid.UUID; Current int64 }` (`error`);
  - `func (s *Store) LockIncidentFamily(ctx model.AppContext, customer uuid.UUID, guids []uuid.UUID) ([]*model.MachineIncident, error)` — одна команда `SELECT … ORDER BY i.number FOR UPDATE OF i` по решению 15;
  - `func (s *Store) MachineIncidentsByOwnerState(ctx, customer uuid.UUID, owner, state string)`, `MachineIncidentsLinkedTo(ctx, customer, primary uuid.UUID)`, `MachineIncidentsInGroupOf(ctx, customer, primary uuid.UUID)` (`linked_to` или `left_group->>'primaryId'`), `MachineIncidentsOfEvent(ctx, customer, event uuid.UUID)` — все `([]*model.MachineIncident, error)`, по `number`, без `deleted_at`;
  - `func (s *Store) UpdateMachineIncident(ctx model.AppContext, inc *model.Incident, version int64) error` — `UPDATE … SET …, version = version + 1, status_guid = (статус по state), changed_at = … WHERE guid = $1 AND customer_guid = $2 AND version = $3`; 0 строк — `*model.VersionConflictError`;
  - `func (s *Store) GetJournalEntriesAt(ctx model.AppContext, guids []uuid.UUID, at time.Time) ([]*model.JournalEntry, error)`, `func (s *Store) UpdateJournalVars(ctx model.AppContext, guid uuid.UUID, vars json.RawMessage) error`;
  - в `transition`: `type StoreAPI interface` — методы выше и `DoInTx`, `InsertJournalEntries`, `GetMachineIncidents`; `func NewStoreRepo(store StoreAPI, timerIDs []string) Repo`; `Candidates` по таблице `refSQL` (имя факта → запрос и перевод аргументов); имени нет — `fmt.Errorf("no SQL for ref fact %s", name)`; `*model.VersionConflictError` → `*VersionConflict`.

Кандидаты (надмножество `ref` машины, решение 12): `incidentById(id)` — `guid = id`; `linkedOf(id)` — `linked_to = id`; `countMine`, `mineOf(who, state, except)` — `owner = who AND state = state`; `groupMembersAt(p, at)` — `linked_to = p.id OR left_group->>'primaryId' = p.id`; `siblingsOf(x)` — `event_guid = x.eventGuid` (у пустого — пусто). Не UUID в аргументе (`incidentById('nope')`) — пустой список, не ошибка.

- [x] **Step 1: Тесты**

Набор `family` (база, `inRolledBackTx`, номера — из счётчика): основной P (in_progress, op1); L1 (linked к P, открыт), L2 (linked к P, closed), W (вышел из группы P: `left_group.primaryId` = P); X (new), Y (in_progress, op1); S1, S2 — соседи P по событию; Z — инцидент другого арендатора с `linked_to` = P.

```go
func TestEveryRefFactHasSQL(t *testing.T)   // без базы: для каждого факта cel.world машины с ref — запись в refSQL; Candidates("nope", nil) ⇒ ошибка "no SQL for ref fact nope"
func TestCandidatesSuperset(t *testing.T)
  // для каждого ref-факта и аргументов (incidentById P/L1/"nope"; linkedOf P; countMine и mineOf (op1, in_progress, '') и (op1, in_progress, Y);
  // groupMembersAt (P, at до и после W.leftGroup.at); siblingsOf P и X): machine ref над Candidates == ref над всеми инцидентами арендатора; Z — нигде.
  // Подтест uses_index: ещё 2000 инцидентов op2 в new, ANALYZE incidents, EXPLAIN запроса countMine для op1 — Index Scan или Bitmap Index Scan по idx_incidents_owner_state
func TestLockFamily(t *testing.T)           // LockFamily([L1]) ⇒ [P, L1, L2, W, S1, S2] в порядке number; LockFamily([X]) ⇒ [X] и соседи X по событию; Z — нет
func TestWriteVersioned(t *testing.T)       // Write: строка с Version 1, в базе 2 ⇒ var vc *VersionConflict; errors.As(err, &vc); vc.Current == 2; state и журнал не изменились
func TestWriteStatusFollowsState(t *testing.T) // state "in_progress" ⇒ status_guid статуса "in_progress"; "linked" ⇒ "closed"; changed_at == Now
func TestWriteJournalOrder(t *testing.T)    // Write с тремя записями одного at ⇒ GetJournalEntries — в порядке Journal (решение 21); Replaced — vars заменены, guid прежний
func TestJournalAt(t *testing.T)            // записи в Now и Now+1 ⇒ JournalAt(Now) — только первая; Kind сохраняется
```

- [x] **Step 2: Тесты падают**

Run: `go test ./internal/im/service/transition/ -run TestEveryRefFactHasSQL 2>&1 | tail -3 && TESTDB='postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable' && IM_TEST_DB_URL=$TESTDB go test ./internal/im/handler/test/ -run 'TestCandidatesSuperset|TestLockFamily|TestWrite|TestJournalAt' 2>&1 | tail -5`
Expected: FAIL — не собирается (`NewStoreRepo`, `LockIncidentFamily` не объявлены).

- [x] **Step 3: Реализация**

- [x] **Step 4: Тесты проходят**

Run: `go test ./internal/im/service/transition/ && TESTDB='postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable' && IM_TEST_DB_URL=$TESTDB go test ./internal/im/handler/test/ -run 'TestCandidatesSuperset|TestLockFamily|TestWrite|TestJournalAt' -v 2>&1 | grep -E '^(--- |ok|FAIL)' && golangci-lint run ./...`
Expected: PASS; lint — 0.

- [x] **Step 5: Commit**

Сообщение: «Этап 4б: хранилище переходов — семья инцидента под блокировкой в порядке номеров, кандидаты фактов над инцидентами по индексу, запись с проверкой версии, статусом по состоянию и порядком журнала».
Run: `git add internal/im/model internal/im/service/storing internal/im/service/transition internal/im/handler/test/transition_store_test.go && git commit -q -F .git/COMMIT_MSG_STAGE4B`

---

### Task 11: Мир сервера — дерево групп и пользователь запроса

**Files:**
- Create: `internal/im/service/transition/world.go`; Test: `internal/im/service/transition/world_test.go`, `internal/im/handler/test/transition_world_test.go`
- Modify: `internal/im/machine/intake_test.go` (`TestMachineTreeFactsPinned` — и `inSourceGroup`)

**Interfaces:**
- Consumes: `tree.Index` (`IsSelfOrAncestor`, `PathFromRoot`, `ClosurePairs`), `storing.Store.GetEvent`, `GetSourceGroupGUIDs`, `GetIncidentByUserGroupIDs`.
- Produces:
  - `type GroupTree interface { IsSelfOrAncestor(ancestor, guid uuid.UUID) bool; PathFromRoot(guid uuid.UUID) []uuid.UUID; ClosurePairs() (ancestors, descendants []uuid.UUID, versionSum uint64) }` — свой у `transition` (`transition` не импортирует `intake`; `*tree.Index` подходит как есть);
  - `type WorldStore interface { GetEvent(ctx model.AppContext, guid uuid.UUID) (*model.Event, error); GetSourceGroupGUIDs(ctx model.AppContext, sourceGUID uuid.UUID) ([]uuid.UUID, error); GetIncidentByUserGroupIDs(ctx model.AppContext, guid uuid.UUID, groupIDs []int64, closureAncestors, closureDescendants []uuid.UUID) (*model.Incident, error) }`;
  - `func NewServerWorld(ctx model.AppContext, store WorldStore, tree GroupTree, user *model.User, rest World) World` — `user` `nil` — пользователя нет (приём события);
  - `can(who, p)`: `who == strconv.FormatInt(user.ID, 10)` — `slices.Contains(user.Permissions.MachineKeys(), p)`; иначе — `rest`;
  - `access(who, x)`: пользователь запроса — `GetIncidentByUserGroupIDs(x.id, user.UserGroupIDs, tree.ClosurePairs())` нашёл инцидент; иначе — `rest`;
  - `inSourceGroup(x, g)`: устройство события `x.eventGuid` (`GetEvent` → `Source`) — в группе `g` или вложенной (смысл `treeWorld.DeviceInGroup` приёма, повторён здесь); `deviceInGroup`, `groupDepth` — как `treeWorld`; первый ответ на группу запоминается на операцию;
  - прочие факты и методы `World` — `rest` как есть.

Факт мира читает только `id` и `eventGuid` инцидента-аргумента и данные сервера, а не поля машины (ADR-004, «Contract for 4b»: инцидент у факта — запись до транзакции).

- [x] **Step 1: Тесты**

```go
func TestServerWorldCanForRequestUser(t *testing.T)
  // user ID 7, Permissions — облачное имя права incident:claim ⇒ can("7", "incident:claim") true, can("7", "incident:hold") false; can("8", …) ⇒ вызов rest
func TestServerWorldDelegates(t *testing.T)    // members, agentState, idleSec, ActorName, Progress, StepNumber, SetCursor, ShareAnswers ⇒ rest с теми же аргументами
func TestServerWorldInSourceGroup(t *testing.T)
  // база: событие устройства D1; D1 в группе nested, nested под mall ⇒ inSourceGroup(x, mall) true, (x, nested) true, (x, other) false
func TestServerWorldAccessForRequestUser(t *testing.T)
  // база: правило доступа группы пользователей 1 на источник D1 ⇒ access("7", x у D1) true, access("7", x у D2) false; access("8", x) ⇒ rest
func TestServerWorldIgnoresMachineFields(t *testing.T)
  // inSourceGroup и access с x, у которого owner, state, timers другие ⇒ те же ответы
func TestMachineTreeFactsPinned(t *testing.T)  // хэш — deviceInGroup, groupDepth и inSourceGroup (с $comment); сообщение называет treeWorld и NewServerWorld
```

- [x] **Step 2: Тесты падают**

Run: `go test ./internal/im/service/transition/ -run ServerWorld 2>&1 | tail -3`
Expected: FAIL — `NewServerWorld` не объявлен.

- [x] **Step 3: Реализация**

- [x] **Step 4: Тесты проходят**

Run: `go test -race ./internal/im/service/transition/ ./internal/im/machine/ && TESTDB='postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable' && IM_TEST_DB_URL=$TESTDB go test ./internal/im/handler/test/ -run ServerWorld && golangci-lint run ./...`
Expected: PASS; lint — 0.

- [x] **Step 5: Commit**

Сообщение: «Этап 4б: мир сервера для переходов — группы источников по дереву, права и доступ пользователя запроса; остальное — от вызывающего; inSourceGroup под замком хэша».
Run: `git add internal/im/service/transition internal/im/machine/intake_test.go internal/im/handler/test/transition_world_test.go && git commit -q -F .git/COMMIT_MSG_STAGE4B`

---

### Task 12: Ядро на PostgreSQL — всё или ничего и конкурентность

**Files:**
- Create: `internal/im/handler/test/transition_test.go`

**Interfaces:**
- Consumes: задачи 5–11 (`Core.Run`, `NewStoreRepo`, `NewServerWorld`, `transitiontest.FactWorld` как `rest`).

Тесты с фиксацией (не `inRolledBackTx`): каждый создаёт свои инциденты с номерами из счётчика арендатора теста и удаляет их в `t.Cleanup`.

- [x] **Step 1: Тесты**

```go
func TestRunOnPostgres(t *testing.T)
  // claim op1 ⇒ строка: state "in_progress", owner "op1", version 2, status_guid статуса "in_progress", changed_at — Now;
  // журнал — одна запись claim, kind "transition", vars как в TestLogVars (мир FactWorld)
func TestRunAllOrNothingOnPostgres(t *testing.T)
  // обёртка над StoreAPI: UpdateMachineIncident проходит, затем InsertJournalEntries ⇒ errBoom ⇒ ошибка; строка — version 1, state "new", журнал пуст
func TestRunWindowOnPostgres(t *testing.T)    // как TestRunWindowAfterDeadline ⇒ breaches и timers.reaction.fired в jsonb; GetJournalEntries — [timer_overridden, claim]
func TestConcurrentClaim(t *testing.T)
  // 2 горутины, start-канал: claim одного инцидента от op1 и op2, Expect nil ⇒ одна — без отказа, другая — Refusal{Key "workflow.guard.wrong_state", NotFrom true};
  // version 2; в журнале ровно одна запись claim
func TestConcurrentClaimWithExpect(t *testing.T) // то же с Expect {x: 1} ⇒ одна — без отказа, другая — ошибка *VersionConflict с Current 2
func TestLockFamilyNoDeadlock(t *testing.T)
  // 2 горутины × 50, DoInTx { LockFamily; sleep 5 мс }: первая — [L1, S1], вторая — [S1, L1] (одна семья, свои в обратном порядке);
  // затем первая — [L1], вторая — [S2] (семьи пересекаются частично: P, S1, S2) ⇒ ни одной ошибки, нет SQLSTATE 40P01
```

- [x] **Step 2: Тесты падают** — до помощников набора.

Run: `TESTDB='postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable' && IM_TEST_DB_URL=$TESTDB go test ./internal/im/handler/test/ -run 'TestRunOnPostgres|TestRunAllOrNothingOnPostgres|TestRunWindowOnPostgres|TestConcurrentClaim|TestLockFamilyNoDeadlock' 2>&1 | tail -5`
Expected: FAIL — не собирается (помощники набора не объявлены); после — падение показывает расхождение, правится ядро или хранилище (задачи 5–10), а не тест.

- [x] **Step 3: Тесты проходят, гонок нет**

Run: `IM_TEST_DB_URL=$TESTDB go test -race -count=3 ./internal/im/handler/test/ -run 'TestRunOnPostgres|TestRunAllOrNothingOnPostgres|TestRunWindowOnPostgres|TestConcurrentClaim|TestLockFamilyNoDeadlock' && make test-local 2>&1 | tail -8 && golangci-lint run ./...`
Expected: PASS три раза подряд; без `DATA RACE`; все пакеты; lint — 0.

- [x] **Step 4: Commit**

Сообщение: «Этап 4б: переход на PostgreSQL — всё или ничего при сбое журнала, окно после дедлайна, два «Взять» одного инцидента: один выигрывает, второй — отказ или конфликт версии; без взаимной блокировки».
Run: `git add internal/im/handler/test/transition_test.go && git commit -q -F .git/COMMIT_MSG_STAGE4B`

---

### Task 13: Ядро — `Core.Create`

**Files:**
- Create: `internal/im/service/transition/create.go`; Test: `internal/im/service/transition/create_test.go`

**Interfaces:**
- Consumes: задачи 5, 7.
- Produces:
  - `func (c *Core) Create(w World, now int64, incidents []map[string]any) ([]*Created, error)` — переход `trigger: event` машины на каждом новом инциденте по порядку, каждый — своим черновиком (как `engine.create`); `actor` — `actor` перехода (`dispatcher`); фактов над инцидентами у `create` машины нет: `Scope.Refs` не задан, попросит — ошибка (её поймает вектор `create` в 4б-2); в базу ничего не пишет;
  - `type Created struct { Incident map[string]any; Journal []JournalEntry; After []After; External []External; Facts Facts }` — `ID` записей выданы (решение 21).

- [x] **Step 1: Тесты** (мир задачи 5)

```go
func TestCreateStartsReaction(t *testing.T)
  // приоритет 50, Now 1790845200000 ⇒ state "new", owner "", assignmentGroup "", escalationLevel 0;
  // timers.reaction — due 1790846100000 (override priority 50: 900 с), since Now, paused false; resolution, hold — нули;
  // Journal — [{TemplateKey "workflow.journal.create", Actor "dispatcher", Kind "system", At Now}]
func TestCreatePriorityOverrides(t *testing.T) // приоритет 100 ⇒ due Now + 240 000; 25 ⇒ Now + 1 800 000; 60 (нет override) ⇒ Now + 300 000 (defaultSec)
func TestCreateEachIncidentOwnDraft(t *testing.T) // два инцидента одного события ⇒ два Created по порядку, у каждого своя запись журнала
func TestCreateEvalErrorIsError(t *testing.T)  // копия: у create первым эффектом stopTimer ["nope"] ⇒ ошибка, Created nil
```

- [x] **Step 2: Тесты падают**

Run: `go test ./internal/im/service/transition/ -run TestCreate 2>&1 | tail -3`
Expected: FAIL — `Create` не объявлен.

- [x] **Step 3: Реализация**

- [x] **Step 4: Тесты проходят**

Run: `go test -race ./internal/im/service/transition/... && golangci-lint run ./...`
Expected: PASS; lint — 0.

- [x] **Step 5: Commit**

Сообщение: «Этап 4б: ядро — переход create машины на новых инцидентах события: норматив реакции, журнал с подстановками, без записи в базу».
Run: `git add internal/im/service/transition && git commit -q -F .git/COMMIT_MSG_STAGE4B`

---

### Task 14: Приём события — `create` эффектами машины, `ruleselect` убран

**Files:**
- Modify: `internal/im/service/intake/{service.go, store.go, world.go}`, `internal/im/model/intake.go` (`IntakeEvent.OccurredAt time.Time`), `internal/im/appservice/event/event.go` (заполняет `OccurredAt` из события), `internal/im/appservice/appservice.go` (ядро в `intake.NewService`; `machine.UniqueKeyFromMachine` уже там, строка 318)
- Modify (тесты этапа 3 — по смыслу перехода `create`): `internal/im/service/intake/service_test.go` — импорт `ruleselect` (строка 14) → `machine.UniqueKeyFromMachine`; `fakeStore` — методы `WorldStore` (`GetEvent`, `GetIncidentByUserGroupIDs`); `fakeTree` и `shrinkingTree` — `ClosurePairs`; `newTestService` (строка 179), `TestProcess_TreeChangeWithinEventIsStable` (338), `TestNewService` (348) — новая подпись `NewService`; `TestProcess_CreatesInPickOrder` (201; `require.Nil(t, e.Vars)` в 248) — подстановки машины; новый `TestProcess_CreateErrorWritesNothing`. `internal/im/handler/test/intake_test.go` — `TestEventCreateFields` (306)
- Delete: `internal/im/ruleselect/` (пакет целиком; `STAGE4B: remove`)

**Interfaces:**
- Consumes: задачи 2, 11, 13.
- Produces:
  - `intake.NewService(store Store, tree GroupTree, now func() time.Time, uniqueKey []string, core *transition.Core)`; `intake.Store` — и `transition.WorldStore`; `intake.GroupTree` — `transition.GroupTree`;
  - мир приёма — `NewServerWorld(ctx, store, tree, nil, intakeRest)`: `ActorName("")` — `["workflow.label.unassigned"]`, `Progress` — (0, 0), `StepNumber` — 0 (`STAGE6`: прогресс сценария), прочее — ошибка `fact <имя> is not available at intake`.

`service.create()`: `now := s.now().UTC().Truncate(time.Millisecond)` (решение 20) → инцидент модели как раньше (`Version: 1`, `CreatedAt: now`, `State: ""` до перехода) → `ToMachine` (тип события, приоритет правила, `OccurredAt`) → `Core.Create(world, now.UnixMilli(), …)` на всех инцидентах события → `FromMachine` → `InsertIncident`; журнал — записи `Created.Journal` (`Transition: "create"`, `Kind` по `actor`, `At` = `now`), одним `InsertJournalEntries`. Ошибка `Create` — `fmt.Errorf("intake: %w", err)`: `500`, событие не отмечено, ничего не записано.

- [x] **Step 1: Тесты**

```go
// service_test.go:
//   TestProcess_CreatesInPickOrder: вместо require.Nil(t, e.Vars) — подстановки машины: escalationReason ["workflow.escalation.reason"],
//   targetName ["workflow.label.unassigned"], filledSteps 0, totalSteps 0; e.Kind "system"; у инцидента timers.reaction.due ==
//   testNow (мс) + 1000 × норматив reaction машины для PriorityValue правила-победителя
//   TestProcess_CreateErrorWritesNothing (новый): NewService с ядром transition.New(копия машины, у create первым эффектом stopTimer ["nope"]) ⇒
//   Process — ошибка; ни InsertIncident, ни журнала, ни MarkEventProcessed
// intake_test.go:
//   TestEventCreateFields: inc.CreatedAt.Equal(journal[0].At) — по-прежнему true (оба — мс); у инцидента timers.reaction.due > 0; у записи журнала kind "system"
```

- [x] **Step 2: Тесты падают**

Run: `go test ./internal/im/service/intake/ 2>&1 | tail -5`
Expected: FAIL — не собирается (`NewService` без ядра, `ClosurePairs` у `fakeTree` нет).

- [x] **Step 3: Реализация и переключение приёма**

- [x] **Step 4: Тесты проходят; `ruleselect` нет**

Run: `go build ./... && go test -race $(go list ./internal/im/... | grep -v /handler/test) 2>&1 | tail -15 && make test-local 2>&1 | tail -10 && ! grep -rn 'ruleselect' --include=*.go internal && golangci-lint run ./...`
Expected: PASS всех пакетов; `grep` ничего не нашёл; lint — 0.

- [x] **Step 5: Commit**

Сообщение: «Этап 4б: приём события — инцидент создаётся эффектами перехода create машины (норматив реакции запущен, журнал с подстановками машины, часы в мс); переходник ruleselect убран».
Run: `git add -A internal/im && git commit -q -F .git/COMMIT_MSG_STAGE4B`

---

### Task 15: Стенд — приём события и норматив реакции

**Files:**
- нет новых файлов кода; запись в журнал работ

Проверка на стенде, что миграция 018 и `create` с таймером идут на базе `imdb` с данными этапа 3 (как запускается стенд — [30-local-stand.md, шаг 5](30-local-stand.md#шаг-5-событие--инцидент-этап-3)). Меняются данные стенда, не код.

- [x] **Step 1: Копия базы до миграции** (требование шага 5 файла 30)

Run: `mkdir -p ~/Work/stand/backup && sg docker -c "docker exec \$(docker ps -qf name=ac_db) pg_dump -U im imdb" > ~/Work/stand/backup/imdb-before-018.sql && wc -c ~/Work/stand/backup/imdb-before-018.sql`
Expected: файл не пустой.

- [x] **Step 2: Сервер стенда с новым кодом** — остановить прежний (`pkill -f "$HOME/Work/stand/bin/im"`), запустить `~/Work/stand/run-im-server.sh > ~/Work/stand/im-server.log 2>&1` в фоне (`run_in_background`), подождать строку старта в логе.

Run: `sg docker -c "docker exec \$(docker ps -qf name=ac_db) psql -U im -d imdb -tAc \"SELECT id FROM im_db_migrations ORDER BY id DESC LIMIT 1\"" && grep -c panic ~/Work/stand/im-server.log`
Expected: `018_incident_machine.sql`; `panic` — `0`.

- [x] **Step 3: Событие → инцидент, как в этапе 3**

Run: `L=demo-$(date +%s) && ~/Work/stand/bin/agent-emulator replay --run $L && ~/Work/stand/check-demo-intake.sh $L; echo $?`
Expected: `отправлено 27, пропущено 0`; все строки `OK`, код `0` — 30 новых инцидентов, как в этапе 3.

- [x] **Step 4: Норматив реакции и журнал у новых инцидентов**

Run: `sg docker -c "docker exec \$(docker ps -qf name=ac_db) psql -U im -d imdb -c \"SELECT i.number, i.state, i.owner = '' AS unowned, (i.timers->'reaction'->>'due')::bigint > 0 AS reaction, j.kind FROM incidents i JOIN incident_journal j ON j.incident_guid = i.guid ORDER BY i.number DESC LIMIT 5\""`
Expected: `new`, `t`, `t`, `system` в каждой строке. Инциденты, созданные до миграции, — с `timers` `{}` (открытый вопрос 6).

- [x] **Step 5: Журнал работ** — итог в `.superpowers/sdd/53-plan-stage4b/progress.md`; коммита нет.

---

### Task 16: ADR, документы, последний прогон

**Files:**
- Create: `docs/adr/005-transitions-in-transaction.md` (сервер, по-английски, по образцу ADR-004)
- Modify: `docs/adr/004-machine-executor.md` (решение 6 — фраза решения 6 плана; «Contract for 4b» — ссылка на ADR-005; «Known limits» — порядок списка инцидентов, открытый вопрос 3)
- Modify (IM): `research/integration/40-plan.md` (этап 4: «4б-1 сделан», ссылка на этот план; 4б-2 и 4в впереди), `research/integration/53-plan-stage4b.md` (отметки, «Итог этапа 4б-1» — таблица задач и коммитов)

**Interfaces:**
- Consumes: всё из задач 1–15.

- [x] **Step 1: ADR-005** — ядро `transition` и почему так: одна транзакция на операцию, семья под блокировкой в порядке номеров и её точное правило, повтор при `ErrFamilyChanged` и `412` в 4в, версия в `UPDATE`, факты над инцидентами — SQL-кандидаты ∪ черновик и `ref` машины, черновик и `to` перед эффектами инцидента, порядок записей журнала и `guid` по порядку, окно после дедлайна в той же транзакции, мир: что настоящее и что от вызывающего, столбцы и время в мс, `since`, `create` при приёме; известные пределы: `countMine` вне семьи (снимок, лимит может превыситься на один при одновременных запросах одного оператора), версия +1 шире `server.js` (решение 16), прогресс сценария у приёма — 0 до этапа 6; дальше — 4б-2 (векторы, объединение, «Отсоединить все»), 4в.

- [x] **Step 2: Документы IM** — перед правкой `git -C /mnt/hgfs/VmWareShared/soul2home/IM fetch`; новое — сказать пользователю.
Run: `cd /mnt/hgfs/VmWareShared/soul2home/IM && python3 tools/check_links.py && node tools/cel_vectors.mjs --check | head -1`
Expected: «Нерабочих ссылок: 0»; `векторов: 2324 (guard 350, rule 626, definition 685, effect 663), расхождений: 0, промахов ленты: 0, без векторов: 0` (машина не менялась).

- [x] **Step 3: Последний прогон сервера**

Run: `cd ~/Work/incident-manager-server && source ~/go/offline-env.sh && go test -race $(go list ./internal/im/... | grep -v /handler/test) && make test-local 2>&1 | tail -15 && go vet ./... && gofmt -l internal/im && golangci-lint run ./...`
Expected: всё PASS; `go vet` и `gofmt -l` чисто; lint — 0.

- [x] **Step 4: Commit (два репозитория)**

Сервер — «Этап 4б: ADR о переходах в транзакции; ADR-004 — действия мира в транзакции и после неё». Run: `git add docs/adr && git commit -q -F .git/COMMIT_MSG_STAGE4B`
IM — «Этап 4б-1 встраивания: столбцы инцидента и переход в транзакции — план отмечен». Run: `cd /mnt/hgfs/VmWareShared/soul2home/IM && git add research/integration/40-plan.md research/integration/53-plan-stage4b.md && git commit -q -F .superpowers/sdd/53-plan-stage4b/commit-msg.txt`

---

## Итог этапа 4б-1

Этап сделан. Сервер хранит инцидент со всеми полями машины и выполняет ручной переход одной транзакцией PostgreSQL: доступность, форма, окно после дедлайна, эффекты, журнал, версия — всё или ничего. Приём события создаёт инцидент эффектами перехода `create` машины, норматив реакции запущен. Зеркало `ruleselect` и дерево `treeWorld` у приёма убраны. Проверено на стенде (задача 15): миграция 018 применилась на данных этапа 3, повторный прогон `replay` дал 27 событий → новые инциденты с таймером реакции и записью `create` в журнале, `check-demo-intake` 30 из 30, ошибок 0. Решения и пределы — в ADR-005 сервера (`docs/adr/005-transitions-in-transaction.md`) и ADR-004.

| Задача | Репозиторий | Коммиты |
|---|---|---|
| 1. Миграция 018 — столбцы машины у инцидента, `kind` у журнала | сервер | `9564cd6` |
| 2. Строка базы ↔ инцидент машины | сервер | `cf66f86` |
| 3. Исполнитель — кандидаты фактов над инцидентами, снимок цели действия | сервер | `fec8178`, `2cec08b` (тест: факт видит запись эффекта, договор `RefSource`) |
| 4. Исполнитель — черновик для ядра (`Put`, `Err`), хвосты 4а | сервер | `bd5bcc7`, `4805158` (ошибка сборки вызванного эффекта по одному разу, копия после `Put`) |
| 5. Ядро — каркас перехода и отказы | сервер | `bdbecd9` |
| 6. Ядро — проверка формы | сервер | `00b01a7` |
| 7. Ядро — эффекты, журнал, действия мира | сервер | `673f739` |
| 8. Ядро — семья, кандидаты с черновиком, версии, повтор | сервер | `ddbb385`, `7ec47b2` (тесты: версия черновика сильнее кандидата, порядок, инцидент без места) |
| 9. Окно после дедлайна, `once`, запись «некому» | сервер | `3831913`, `a1228e5` (`once` ищет сначала в журнале базы), `38a237f` (тесты окна, форма окна пустая) |
| 10. Хранилище PostgreSQL — семья, кандидаты, запись с версией | сервер | `49cb88b` |
| 11. Мир сервера — дерево групп и пользователь запроса | сервер | `ba64903`, `6dba1a9` (пустой `eventGuid` — не в группе) |
| 12. Ядро на PostgreSQL — всё или ничего, конкурентность, точка сохранения на попытку | сервер | `85843d3` |
| 13. Ядро — `Core.Create` | сервер | `5f16e1f` |
| 14. Приём события — `create` эффектами, `ruleselect` убран | сервер | `c96e05b`, `e961f76` (тест группы вне дерева, статус по итоговому состоянию, действия `create` не теряются) |
| 15. Стенд — приём события и норматив реакции | — (без кода; дамп `~/Work/stand/backup/imdb-before-018.sql`) | нет |
| 16. ADR-005, ADR-004, документы, последний прогон | сервер, IM | этот коммит (сервер), этот коммит (IM) |

Последний прогон — в отчёте задачи 16 (`.superpowers/sdd/53-plan-stage4b/task-16-report.md`): `go test -race`, `make test-local`, `go vet`, `gofmt`, `golangci-lint` — чисто; `check_links.py` — 0 нерабочих ссылок; `cel_vectors.mjs --check` — 0 расхождений (машина не менялась).

Что осталось: 4б-2 ([54](54-plan-stage4b2.md)) — векторы переходов, объединение, «Отсоединить все»; для него записано: объединение должно блокировать `form.primaryId`, `Facts.To` ядро берёт по шагу (прототип — после всей операции). 4в — HTTP, `412`, массовые действия, `shareAnswers` без `logKey` (версия +1). Инциденты стенда, созданные до миграции 018, остались без таймера (открытый вопрос 6).

---

## Не в этом этапе

| Что | Когда |
|---|---|
| Векторы переходов (`kind: transition`): запись в IM, файл, `--check`, сверка Go в памяти и на PostgreSQL | 4б-2 ([54](54-plan-stage4b2.md)) |
| «Отсоединить все» (`runAll`), объединение с «Взять» основного (`merge`), записи `merged_in*` в транзакции | 4б-2 |
| Отображение на HTTP: `ETag`/`If-Match`, «404 раньше `If-Match`», `expectedState`, `expectedVersions`, `422` и `403` по отказу, ошибка вычисления — `500` (открытый вопрос 2), `ErrFamilyChanged` — `412`, идемпотентность | 4в |
| Массовое действие `each_allowed` (по одному `Run` на инцидент, частичный успех), `bulk.scope`, выбор основного (`mergePrimary`, `bulkPrimary`), `minItems`, `maxBulk` | 4в |
| Догон автоматических переходов перед запросом и системные после него (ARCH-10), планировщик (`tick`, `agentIdleFor`, `changed_at`) | минимум — 4в, целиком — 6 |
| Доставка действий после фиксации: уведомления, вытеснение карточки, события потока (`touch` → `journal.appended`) | 5 (ядро уже отдаёт `After`) |
| Факты о людях и группах (`members`, `isOperator`, `isGroup`, `dutyGroups`, `agentState`, `idleSec`, `transferTargets`, `lastTransferTarget`, права и доступ других людей), имена (`ActorName`) | 4в (минимум), 5 |
| Сценарий: `setCursor`, `shareAnswers`, `stepsFilled`, прогресс и номер шага в журнале; хранилище курсора | 6 |
| Сверка вида ошибки у векторов CEL с `expect.error` (хвост ревью 4а) | не делается: текст ошибки не сравнивается по PROC-44, а вид у 7 синтетических векторов-ошибок однозначен по случаю (`case`); классификация ошибок cel-go и cel-js — работа без пользы. У векторов переходов отказ и ошибка различаются (4б-2) |
| Удаление старых столбцов `escalated*`, `assignee_user_id`, `assigned_*` | после 4в, когда старые маршруты перестанут их читать |
| Таймер реакции у инцидентов, созданных до миграции 018 | не делается: на стенде новый прогон `replay` создаёт инциденты с таймером (открытый вопрос 6) |

## Решения этого плана — обоснования (на подтверждение)

1. **Ядро — отдельный пакет, хранилище — интерфейс (решение 11).** Ядро — порядок проверок, черновик, журнал, версии — и есть смысл 4б, а SQL — только где лежат строки. Интерфейс `Repo` даёт два исполнения: PostgreSQL и память; второе нужно и для быстрых тестов, и для сверки с векторами в 4б-2, где порядок списка задаёт вектор. `storing` остаётся на типах `model`, как во всём сервере. Свой `GroupTree` у `transition` — потому что `intake` теперь импортирует `transition`, и обратная ссылка дала бы цикл.
2. **SQL — только отбор кандидатов, смысл — `ref` машины (решение 12).** BACKEND.md требует, чтобы запрос «давал то же», что `ref`. Если писать смысл в SQL, получится второй источник смысла — то, что 4а убрало у `ruleselect`. Надмножество проверить проще, чем равенство: тест сравнивает `ref` над кандидатами с `ref` над всеми строками. Цена — лишние строки в памяти на один факт; запросы идут по индексу.
3. **Семья под блокировкой (решение 15).** Брать в порядке номера можно только то, что известно до эффектов. Эффекты ручных переходов машины пишут только основному, привязанным и вышедшим из группы основного и соседям по событию — это видно по машине. Одна команда `SELECT … ORDER BY number FOR UPDATE` берёт их в одном порядке у всех запросов — взаимной блокировки нет. Если машина когда-нибудь начнёт писать кому-то ещё, ядро даст ошибку, а не запишет без блокировки; векторы 4б-2 проверяют это на всех записанных переходах.
4. **Версия в `UPDATE … WHERE version` при уже взятой блокировке.** Под `FOR UPDATE` версия не меняется, но проверка в `UPDATE` — вторая защита: строка, изменённая мимо ядра (старые маршруты `UpdateIncident`), не перезапишется молча.
5. **Факты вне семьи — снимок без блокировки (указание 5).** Вне семьи читаются только `countMine`/`mineOf` — сколько у оператора своих в работе и отложенных (лимиты `maxActive`, `maxOnHold`). Блокировать все инциденты оператора — значит выстроить в очередь его несвязанные действия. Гонка возможна только между двумя одновременными запросами одного оператора и даёт лимит + 1, следующий запрос видит верное число; прототип однопоточный, векторы это не задевают. Записано в ADR-005 и в открытом вопросе 4.
6. **`to` перед эффектами инцидента (решение 14).** Так делает прототип: у «Отсоединить все» второй привязанный ещё `linked`, пока идут эффекты первого; у объединения основной ещё `new`, пока идут эффекты присоединяемых. Если поставить `to` всем сразу, эффекты увидят другие состояния и векторы 4б-2 разойдутся.
7. **Порядок записей журнала как у прототипа (решение 13).** Указание 2 переносит три поздние записи прототипа в транзакцию; если поставить их в другое место хвоста, векторы разойдутся, а смысла в другом порядке нет: запись о таймере идёт перед действием, которое его отменило, «некому» — после действия.
8. **Время: `timestamptz` для людей, мс в `jsonb` для машины (решение 17).** `closed_at`, `linked_at`, `changed_at` нужны отчётам и SQL (окно переоткрытия, срок группы); у `timestamptz` точность — микросекунды, мс переводятся без потерь. Таймеры, нарушения, выход из группы — записи машины целиком; отдельные столбцы таймеров понадобятся, только если планировщик этапа 6 будет искать по дедлайну — тогда индекс по выражению `((timers->'reaction'->>'due')::bigint)` (PostgreSQL 9.6 умеет).
9. **Курсора сценария нет в столбцах (указание 7).** Тип `Incident` машины его не содержит, эффекты работают с ним только через действия мира. Столбец без исполнителя сценариев (этап 6) хранил бы значение, которое никто не вычисляет.
10. **`create` без хранилища.** У перехода `create` машины нет фактов над инцидентами и записей чужим инцидентам; приём события уже идёт в транзакции события (этап 3) с номерами под блокировкой счётчика. Поэтому `Core.Create` только вычисляет, а пишет сервис приёма своими методами, как раньше: тесты этапа 3 меняются только там, где меняется смысл (подстановки журнала, таймер, мс).
11. **Кандидаты ∪ черновик (решение 18).** «Черновик поверх» без объединения терял бы инцидент, который эффекты сделали подходящим (SQL ищет по старым полям). Добавлять весь черновик дёшево: это семья, она мала, а `ref` машины сам отбросит лишнее.
12. **`ErrFamilyChanged` — повтор, затем `412` (решение 19).** Гонка связей — обычная работа двух операторов (один объединяет, другой закрывает соседа), а не ошибка программы: повтор с новым снимком её почти всегда снимает. Если не сняли три попытки, клиенту честнее всего сказать «инцидент изменился, вот новая карточка» — это `412 VERSION_CONFLICT`, который клиент уже умеет обрабатывать; нового кода в контракте не нужно, а `500` заставил бы думать о сбое сервера.
13. **`guid` журнала по порядку (решение 21).** Отдельный столбец порядка — миграция и ещё одно поле в каждом запросе; UUID v7, выданные подряд после сборки порядка, уже сортируются так, как нужно, и `GetJournalEntries` менять не надо.
14. **Версия +1 и журналу (решение 16).** Запись журнала меняет то, что видит карточка; без новой версии клиент со старой версией выполнит действие по устаревшей карточке без `412`. Прототип в этом месте не строже, а просто не думал об этом; векторы ядра версий не сравнивают.
15. **Задача 15 — стенд, а не тест.** Миграция 018 идёт на базе с данными этапа 3; тесты Go её проверяют на пустой схеме. Стенд — единственное место, где видно, что демо грузится, как раньше.

## Открытые вопросы

1. Тип события в условии правила — по `uid` (как в машине и на сервере) или по паре «тип устройства + `uid`» (вопрос от 2026-10-29). План следует `uid`.
2. Ошибка вычисления эффекта: прототип отдаёт `422 FORM_FIELD_REQUIRED` (`server.js`, `runTransition`: `r.code || "FORM_FIELD_REQUIRED"` и для `workflow.error.transition_failed`), а CEL.md и решение в3 — ошибка сервера. Завести в IM пункт ревью «прототип: `transition_failed` — `500`» или оставить `422`? Сервер в 4в по умолчанию отдаёт `500`.
3. Порядок списка инцидентов у фактов над инцидентами: у прототипа — порядок набора и появления (`events`, новые — в начало), у сервера — по номеру. Порядок влияет на `After` при `forEach` по нескольким соседям и на подстановку `id` у `withinActiveLimit`. Сделать в прототипе список для ядра по номеру (пункт ревью в IM) или оставить? 4б-2 посчитает, сколько векторов от этого зависит.
4. `countMine` вне блокировки: лимит `maxActive`/`maxOnHold` может превыситься на один при двух одновременных запросах одного оператора. Принять (план) или брать рекомендательную блокировку на оператора (`pg_advisory_xact_lock`)?
5. Прогресс сценария в записи `create` (`filledSteps`, `totalSteps`) у сервера до этапа 6 — `0`, у прототипа — число шагов пути. Принять до этапа 6?
6. Инциденты стенда, созданные до миграции 018, — без таймера реакции. Оставить (новый прогон `replay` создаёт инциденты с таймером, план) или дописать миграцией запуск таймера по нормативу?
