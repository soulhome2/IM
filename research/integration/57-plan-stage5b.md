# Этап 5б: фильтр и выборка, скрытие номеров, отсоединение — план работ

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Закрыть все операции очереди: панель фильтра и выборка работают на настоящем сервере, номера скрываются всюду, где человек не вправе их видеть, отсоединение отвечает одинаково на обоих маршрутах, битые строки сессии чинятся. Сервер остаётся в одном экземпляре, и что при этом открыто, названо в ADR и в разделе «Отложено до публичного запуска».

**Architecture:** Сначала закрываются долги и одним коммитом правится контракт. Битые строки сессии чинятся записью. Журнал скрывает номера по чтению номеров, а не по связям. Фильтр считается на тех же классах, что очередь, только класс шире: сценарий, тип устройства, тип события, устройство. Условие объединения машины считается один раз на класс, строки читаются только для основного и для готового списка. Выборка стоит на списке очереди и одном `ViewPage`. `People`, память повторов и дерево групп остаются на процесс: так и записывается в ADR.

**Tech Stack:** Go 1.27.1, gin v1.11.0, oapi-codegen (`operatorgen`), `mgutz/dat`, cel-go, PostgreSQL 9.6, pgx v5.7.6, testify `require`, kin-openapi v0.133.0 (только тесты), golangci-lint v2.14.0.

**Spec:** [40-plan.md](40-plan.md), этап 5; [56-plan-stage5.md](56-plan-stage5.md): «Набросок 5б», обоснования, «Итог этапа 5а»; [56-final-review.md](56-final-review.md), раздел 7, таблица «5б»; ADR-002 и ADR-005 сервера (`docs/adr/`, «Carried to stages 5b-7»); контракт `Specification/Workflow_machine/openapi.json` (`filterIncidents`, `resolveSelection`, `FilterRequest`, `FilterResult`, `SelectionRequest`, `SelectionResult`); `prototype/server.js` как образец поведения (`filterView` 778–859, `selectionActions` 1313, `sharedForm` 1379, `selection` 1407); правила: RULE-138, §5, §11; [30-local-stand.md](30-local-stand.md).

---

## Размер и разбиение

Решением пользователя от 2026-11-01 этап сокращён. Из 26 задач в нём остаётся 17: Task 1–7, 11–19, 26. Task 8–10 и Task 20–25 отложены до публичного запуска: они лежат в одноимённом разделе в конце плана, текст сохранён. Номера задач не менялись, их называют журнал, ревью и сделанные коммиты. Деления на части больше нет: полный прогон один (Task 19), ревью всей ветки одно (Task 26).

| Задачи | Что входит | Состояние |
|---|---|---|
| Task 1–5 | долги, стенд, контракт | сделаны, коммиты в `progress.md` |
| Task 6–7 | перенос контракта, битые строки | впереди |
| Task 11–12 | номера журнала, отсоединение | впереди |
| Task 13–18 | ядро, фильтр, выборка, замер и `maxBulk` | впереди |
| Task 19, 26 | стенд, полный прогон, ADR, итог | впереди |

## Критерий готовности

Критерий этапа 5 в `40-plan.md` (два окна) закрыт в 5а настолько, насколько это возможно без файла пароля, 5б его не меняет. Свой критерий 5б такой: заглушки `FilterIncidents` и `ResolveSelection` убраны (`stubs.go`, было 32, станет 30), все пункты таблицы «Что входит» закрыты, кроме помеченных «отложено», и всё проверено по уровням.

| Уровень | Что доказывает | Где | От чего зависит |
|---|---|---|---|
| **А** | маршруты на настоящей базе, сверка классов с честным подсчётом по строкам | `handler/test`, Task 14–17 | ни от чего |
| **Б** | каждый ответ `filterIncidents` и `resolveSelection` проходит `checkContract`, таблица соответствия 23 тестам `tests/api-scenarios.js` | Task 17, Task 19 | ни от чего |
| **В** | настоящий токен через шлюз: фильтр, выборка | `check-operator-filter.sh`, Task 19 | свой стенд, один пользователь |
| **Г** | второй настоящий пользователь | `check-operator-stream.sh`, `check-operator-transitions.sh` (передача и приём), `ui-check/check-two-windows.mjs` | только с `~/Work/stand/second-operator.pass`, иначе `SKIP` |

Что будет сказано честно: без файла разные пользователи подтверждены только на уровне А. Адресаты идут из памяти процесса, а пользователь на стенде один, поэтому на стенде их список может быть пуст: настоящие адресаты подтверждены только на уровне А. Пароль нигде не искать, в отчётах и логах не печатать. Файл создаёт только пользователь. Task 4 уже сделана, поэтому тот же пользователь как разные не пройдёт.

## Global Constraints

- Сервер: `~/Work/incident-manager-server`, ветка `feature/im_operator`, план сверен с `e036f84`. IM: `/mnt/hgfs/VmWareShared/soul2home/IM`, ветка `feature/im_operator`, `27d92a5`. Task 1–5 сделаны, дальше работа идёт от головы ветки. Конфигуратор не меняем.
- Только локально, `git push` никогда. Каждая задача — коммит. Сообщение на русском, простыми словами, последняя строка `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- `~/Work/axxoncloudgo` не менять. В `ac_db` ничего не пишем. Пользователей облака не создаём. Вход и токены отложены. AxxonData вне этапа.
- Тесты только на im-test-db: `postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable`. База стенда `imdb` в тестах запрещена. **Один прогон на тестовой базе за раз.**
- Перед полным прогоном (Task 19) база пересоздаётся: `cd ~/Work/incident-manager-server && sg docker -c "make test-db-down && make test-db-up"`. Тесты обработчиков на свежей базе идут 11–13 минут.
- Новых миграций в этапе нет, последней остаётся 021. Номера 022 и 023 заняты отложенными Task 8 и Task 21. `checkAppliedMigrations` сравнивает записи со списком по индексу, поэтому чужой номер сюда брать нельзя.
- Команды Go начинаются с `source ~/go/offline-env.sh &&` в той же строке. Новых зависимостей нет, `go.mod` не меняется. Нельзя добавлять `gorillamux` и `golang.org/x/text`.
- **Без базы:** `source ~/go/offline-env.sh && go test -race $(go list ./internal/im/... | grep -v /handler/test)`.
- **С базой:** `source ~/go/offline-env.sh && TESTDB='postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable' && IM_TEST_DB_URL=$TESTDB go test -race ./internal/im/handler/test/ -run '<шаблон>'`. Весь пакет — с `-timeout 40m`, в задачах запускается только шаблон задачи. Строка «Шаблон» в задаче подставляется сюда; у задачи без базы вместо неё указан пакет.
- **Замеры:** та же команда без `-race` и с `IM_MEASURE=1`. Без переменной тесты бюджетов пропускаются. Счётчики запросов идут всегда.
- `make gen` и `gen-api-im` не запускать. `make vendor-operator-contract` и `make gen-api-operator` — только в Task 6 и Task 18, и только они из генерации.
- `golangci-lint run ./...` — 0 замечаний (`funlen` 120 строк и 60 операторов, `dupl` 150), `gofmt -l internal/im` пусто.
- Комментарии и ADR — английский. Документы IM и коммиты — русский, простыми словами.
- Правки только через Edit и Write: без здесь-документов и `sed -i`. Временные файлы — в scratchpad (`$S`).
- Коммиты сервера: одна задача — один коммит, файл `.git/COMMIT_MSG_STAGE5B`, начинается с `Этап 5б: `, `git commit -q -F`. Коммиты IM: файл `.superpowers/sdd/57-plan-stage5b/commit-msg.txt`. Журнал работы: `.superpowers/sdd/57-plan-stage5b/progress.md`.
- В IM действуют правила `CLAUDE.md`: `openapi.json` и `Workflow_machine/README.md` в CRLF, собранные файлы руками не править, новый функционал — вместе с шагом `prototype/selftest.js`, прототип не держит логики правил, перед правкой `git fetch`.
- Скрипты стенда в `~/Work/stand` вне git: перед правкой копия `*.before-5b`.
- Полные мутации кода (`check_code_mutations.py`) не запускаются, это дело CI. Каждая задача IM проверяет, что образцы порч не устарели.

**Решения пользователя (обязательны, не пересматривать):** Решением от 2026-11-01 прежнее «`People` в 5б» отменено: `People` на `operator_sessions`, срок жизни строки, окно `comeBack`, `MoveAddressed`, строка слушателя только потока и проверка `open_incident_guid` (Task 8–10) отложены до публичного запуска, туда же идут Task 20–25. `People` остаётся в памяти процесса, как решение 75. Номер бывшего основного после разрыва связи скрывается (`left_group.primaryId`), номера соседей и привязанных в журнале без доступа скрываются. `POST` и `DELETE` отсоединения выравниваются, отсоединение тем, кто не видит основного, остаётся. `limits.maxBulk` 200 — только после замера. Объединение через маршрут одного инцидента остаётся `404`. `transition_failed` — `500`, правится `server.js:1247`. Передача адресату вне сети остаётся немедленной. Удалённый основной остаётся скрытым. `countMine` вне блокировки принят. Вышедший оператор выходит на линию сам. Решения про объёмы и защиту сервера — до публичного запуска, не в 5б. Вход и токены отложены.

**Решения прошлых планов, на которые опирается этот:** 25, 33, 49 из плана 55; 54, 65 (идемпотентность); 66–93 из плана 56. Решения 94–96, 98, 103–110, 118 — новые, обоснования в конце. Решения 97, 99–102, 111–117 отложены вместе со своими задачами, номера сохранены.

**Решения этого плана (обязательны для задач):**

*Контракт*

- **94.** Контракт правится один раз (Task 5) и один раз переносится (Task 6). `maxBulk` в машине — отдельное условное изменение Task 18, контракта оно не трогает. Правки:
  1. `maxLength: 200` у `search` в `listIncidents` и в `SelectionRequest.search`.
  2. Текст `IncidentSummary.linkedTo` (`openapi.json:4332`): факт привязки виден, номер скрыт, поле `null`, когда основной не виден.
  3. Текст `affectedIncidents` (`:3971`): и перерыв, и выход, все перемещённые.
  4. Фраза о `skipped` (`:941`, `BulkTransitionResult.skipped`, `:3315`, `BACKEND.md:44`, комментарий `server.js:1511`) приводится к RULE-138: «без изменений, кроме строки журнала открытого соседа при ложной тревоге и её версии». Сервер не меняется.
  5. Тексты `BAD_REQUEST` (`:2396`, `:2511`) называют и тело запроса.
  6. `DELETE linked/{id}` и `incidentGuids` массового маршрута: решения 95 и 104.
- **95.** Строка не-guid в `incidentGuids` массового маршрута — `400 BAD_REQUEST` до расхода ключа, как `strictGuidList` (решение 25). Проверка стоит в `ExecuteBulkTransition` (`bulk.go:87`) сразу после чтения тела, до `once`, а не в `readTransitionBody`: эта функция общая с `ExecuteTransition` и `MergeIncidents` (`merge.go:30`). `POST /merge` с не-guid остаётся `404` (`TestMergeMissing`): это выбор этого плана. `bulkFailure.IncidentGUID` становится `uuid.UUID`. Прототип делает то же. В `operator_contract_test.go:39` включается формат: `openapi3.DefineStringFormatValidator("uuid", openapi3.NewRegexpFormatValidator("^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$"))`. Шаблон общий, не `FormatOfStringForUUIDOfRFC4122`: тот отвергает версии выше пятой, а это не вина контракта. Проверка глобальна, поэтому сверяет и поток, и `checkContract`.
- **96.** Текст примечания при скрытом основном — поле правила машины `cardNotes.rules[].hiddenTextKey`, ключ `workflow.card.note.linked_hidden`: «Инцидент привязан к другому инциденту — его ведут в карточке основного.», плюс `en`. В машине, а не в Go: текст лежит рядом с правилом, в источнике истины, а сервер не заводит своих строк. С каталогом поле сверяет `tools/check_cel.mjs` (проверка `textKey`, около `:116`), его надо научить новому полю. `primaryNumber` в таком тексте не подставляется.

*Люди*

- **98.** Битые строки чинятся, а не прячутся. `model.CleanName(string) string`: `strings.ToValidUTF8` и удаление NUL, вызывается в `SessionOf` и `samePerson`. `comeBack` при отсутствующей строке делает `Rewrite` (только у каталога, который пишет). Настройки, которые не разбираются, читаются как `{}` с `Warn`: строка живёт, настройки человек задаст заново. Битые права и группы чинит запись. Строка, которая так и не читается, адресатом не становится: `OperatorSessions` оставляет её без ответа с `Warn`, а форма передачи её не предлагает (`TestBrokenRowOfAColleague`). Список `Directory.People` остаётся в памяти процесса, поэтому в общем списке `allTargets` (`reference.go:80`), где машина не спрашивается, такой человек виден до Task 9. Это записывается в ADR и итог.

*Журнал и отсоединение*

- **103.** Номера журнала скрываются по номеру, а не по связи. Из всех строк собираются значения `primaryNumber`, `number` и элементы списка `ids` (`merged_in`, `merged_in_more`). Один `Store.MachineIncidentsByNumbers` и один `VisibleAmong` на журнал. Не найден или не виден — `transition.HiddenPrimaryNumber` («—»). Это шире `left_group.primaryId`: тот хранит только последнего основного, а чтение по номеру закрывает и его, и более ранних, и соседей. Отдельно `left_group` поэтому не читается. Запрос идёт по клиенту, с `deleted_at IS NULL`, состояние не фильтрует; индекс `uq_incidents_customer_number` (`014_incident_intake.sql:51`) есть. Удалённый основной не находится и скрыт, как решение 33. Номер самого инцидента не спрашивается. `hidePrimaryNumber` уходит. Пустое значение (`primaryNumber: ""` есть в каждой строке, `journal.go:192`) пропускается без запроса и без лога. Значение, которое не разбирается как номер, скрывается и пишет `Warn`: показать непроверенное хуже, чем лишний раз скрыть. Это отменяет оговорку решения 82 о давних основных: они теперь тоже скрываются. Карточка получает +2 запроса, 17 → 19 при потолке 30.
- **104.** Отсоединение выровнено по таблице ниже. Порядок `DELETE linked/{id}` меняется: сначала привязанный, затем основной.

| Случай | `POST …/transitions/detach` | `DELETE …/linked/{id}` |
|---|---|---|
| привязанный не виден или нет такого | `404` | `404` |
| привязан к другому или не привязан | `409 TRANSITION_NOT_ALLOWED_FROM_STATE` | `404` |
| основной виден, отказ машины | коды перехода | те же коды (`TestDetachRoutesAnswerAlike`) |
| основной не виден | `200`, `TransitionResult` | `200`, карточка отсоединённого (новая фраза контракта) |
| основной не виден, отказ `primaryEditable` | `403`, без полей основного | `403`, без полей основного |
| версия устарела | `412` с карточкой | неприменимо: у `DELETE` нет `If-Match`, `expect = nil` (`linked.go:100`) |
| гонка: связь сменилась под блокировкой (`ErrNotLinkedHere`) | коды перехода | `412`, `current` — основной или, когда он не виден, тот, кого отсоединяли |
| `If-Match` нет | `428` | не требуется, как сейчас; заголовок в контракт не добавляется |

`DELETE linked` без `{id}` на невидимом основном остаётся `404`: список того, кого человек не видит, не читается. Прямое отсоединение через `POST` и так не открывает основного. `currentOfPrimary` (`linked.go:188`) сегодня даёт `404` для скрытого основного и должен падать на привязанного: `404` только когда не виден и он.

*Фильтр и выборка*

- **105.** `FilterView` начинается с той же проверки, что `classesOf` (`user.Permissions.HasAnyMachinePermission()`, `queue.go:29`): без права — `200` с пустым ответом, в базу запрос не идёт. Общего заслона на маршруте нет (`reply.go:69-98`), а `queue_queries.go:144` рассчитывает, что права проверил спрашивающий. Фильтр считается на широких классах. `model.FilterClass{State, Owner, AssignmentGroup string; Scenario uuid.UUID; DeviceType, EventType string; Source uuid.UUID; DeviceTypeName, EventTypeName, SourceName string; Count int; Leads bool}`. `DeviceType` — `source_types.uid`, `EventType` — `source_event_types.uid`, `Source` — guid устройства. Запрос `FilterClasses` построен как `queueClassesSQL`: группировка, `EXISTS` по правилам, `unnest`, добавляется сценарий и имена. Пул отбирается `QueueFilters` по тройке (состояние, владелец, группа). Варианты, каскад, `viable`, `badFilter`, `normCond`, `normFilter` — чистые функции в `appservice/operator/filter.go`, перенос `filterView`. Порядок отказов как в прототипе: узел, плохой `filter`, неизвестный `queueFilter`. Узел: строка без `format` (`openapi.json`, около `:6921`), пусто — без узла, не-guid и неизвестный — `404`, как `server.js:780` и `api-scenarios.js:2863`; дальше `GetSourceGroup` со сравнением клиента, в отличие от `sourcesUnder`, у которого неизвестная группа считается источником. Неизвестный `queueFilter` и плохой `filter` — `422 FORM_FIELD_REQUIRED`, `workflow.error.filter.bad` с `{name}`. `scenarioGuid`, которого нет среди сценариев, в том числе не-guid, — `200`, сценарий заменён лучшим (`api-scenarios.js:2824,2843`). Сортировка вариантов — по подписи в нижнем регистре, затем по id: `localeCompare` без `golang.org/x/text` недоступен, разница записывается. Имя сценария — `ScenarioNames`, нет имени — текст guid.
- **106.** `takeable` на классах. Основной по машине — ступень плюс срочность, плюс давность, плюс номер. Ступень считает машина: `Core.MergeCandidates` на представителях. Настоящего основного каждого сценария даёт один SQL: `FilterPrimaries`, `DISTINCT ON (i.scenario_guid)`, порядок `priority_then_oldest`, это ключи `mergePrimary`. `model.FilterPrimary` несёт класс целиком (`Class model.FilterClass`, те же поля, `Count` 1), а не только тройку. Основной входит в `base`, даже когда его класс условию не подошёл (агент на перерыве, нет `incident:bulk`: классы отпадают, остаётся он один), и варианты (`server.js:837-843`) берут из него тип устройства, событие и источник. Поэтому в `base` он идёт отдельным классом с числом 1, а в `FilterPage` — через `also`, не классом. `viable` требует `pickPrimary([e]) === e`, это не чистая функция: `FilterClass.Leads` считает машина, `Core.MergeCandidates` на одном представителе класса. Условие объединения считается один раз на класс: `Core.MergeFits`, с источником `incidentById`, который отвечает представителем основного, без SQL. У представителя свой id, отличный от основного, поэтому `ps[0].id != incident.id` не срабатывает на класс основного. Итог для сценария: сумма `Count` подошедших классов, плюс 1, если класс основного сам не подошёл, и 0, если основного нет. Это тот же подсчёт, что `list.filter(e === p || ok)`. Поле, которое условие читает, а класса в нём нет, добавляется в класс и `GROUP BY`: `TestTakeableClassesMatchRowCEL` этого не пропустит.
- **107.** Список — SQL по классам: `FilterPage(ctx, scope, classes, also, order, limit)`, порядок `h.queueOrder(v, nil)`, `also` — основной, чей класс не подошёл. Предел — `limits.maxBulk`, при `null` — `math.MaxInt32`. Версии — `GetMachineIncidents`. Строка, пропавшая между чтениями, уходит из `incidentGuids` и `versions`, `count` остаётся как посчитан: как решение 85.
- **108.** `resolveSelection`. `explicit`: `uniqueIDs`, `VisibleAmong`, `LoadMany`, порядок как дан, пустой список и тело без `incidentGuids` — `422 BULK_SELECTION_INVALID`, `workflow.error.selection_empty`, без `truncated`. `all_in_filter`: `QueueList`, из классов убираются завершённые по `isDone` машины, порядок очереди, размер `maxBulk` или `math.MaxInt32`, `truncated` = всего больше предела. Неизвестный `mode` — `400`. Пустой итог — `actions: []`. `candidateTransitionIds` принимается и `actions` не сужает: прототип его не читает. Отличия от прототипа, в сторону контракта, идут в итог: неизвестный `mode` `400` против пустого `200`, не-guid в `explicit` `400` против выбрасывания, `sourceGroupGuid: "all"`.
- **109.** Действия выборки. `v.selectionOp()` — `viewOp(surfaceQueue)` с `RowForm = false`, этим закрыт пункт `viewOp(surface)`: варианты людей выборке нужны. Один `ViewPage` на всю выборку. `View.Availability(id string, form map[string]any) (machine.Availability, error)` — с пустой поверхностью, как в ядре. `Core.MergeCheck` — проверка `mergeCheck` на пути чтения. В `actions` идёт строкой каждый ручной переход (`server.js:1315,1361`), скрытое — с `visible: false`, `enabled: false`. `visible` — относится хоть к одному инциденту. `enabled` при `each_allowed` — доступно каждому в охвате (`server.js:1322` `every`, `:1349`, контракт `SelectionResult.actions`), иначе причина `workflow.error.selection.item`. Проверка `minItems` идёт только при двух строках и больше (`server.js:1334`): один инцидент — обычное «Взять». Перенос `selectionActions`, `sharedForm`, `sharedFormOf`, `formNote` со `bulk.scopeNoteKey`.
- **110.** Бюджеты (только `IM_MEASURE=1`, дерево около 8000 пар, 5000 открытых и 20000 закрытых, 10 людей).

| Что | Бюджет |
|---|---|
| `filterIncidents`, без галочки | ≤ 300 мс |
| `filterIncidents`, `sameScenario` | ≤ 300 мс |
| `resolveSelection`, `all_in_filter`, 200 строк | ≤ 1 с |
| `resolveSelection`, `explicit`, 200 строк | ≤ 1 с |

Запросы идут всегда: `filterIncidents` не зависит от числа строк и сценариев (равенство 10 и 1000 строк, 1 и 5 сценариев), потолок 15. `resolveSelection` — равенство 2 и 200 строк, потолок 35.

- **118.** `limits.maxBulk: 200` ставится, только если замер сошёлся: массовое `hold` на 200 ≤ 20 с, 200 несуществующих guid ≤ 5 с, выборка ≤ 1 с. Не сошёлся — `null` остаётся, цифры идут пользователю.

## Review Focus

1. Фильтр и выборка выдают скрытое через число, вариант, `excluded` или сценарий, в том числе пользователю с группами без прав машины. `TestFilterHidesInvisible`, Task 14; `TestSelectionExplicitHidesInvisible`, Task 16.
2. Строки двигаются между чтением классов и списка: ответ не отдаёт пропавшую строку, число не расходится с причиной. `TestFilterRowMovesBetweenReads`, Task 14.
3. Журнал выдаёт номер внутри списка `ids` или номер другого клиента. `TestJournalHidesNumbersInMergedIn`, `TestJournalHidesOtherCustomerNumber`, Task 11.
4. Отсоединение при скрытом основном выдаёт его поля в отказе или в гонке. `TestDetachHiddenPrimaryRace`, `TestDetachHiddenPrimaryEditableRefused`, Task 12.
5. Основной, чей класс не подошёл условию, теряется из списка, числа или вариантов. `TestFilterPrimaryGivesOptions`, `TestFilterSamePrimaryOwnClass`, Task 15.

## Что входит: разбор наброска и таблицы «5б»

Пометка «отложено» значит: пункт ушёл в раздел «Отложено до публичного запуска» по решению пользователя от 2026-11-01 и в критерий этапа не входит.

| Откуда | Что | Где |
|---|---|---|
| набросок 1 | `filterIncidents` | Task 13–15 |
| набросок 2 | `resolveSelection`, фраза `skipped` | Task 5, 16, 17 |
| набросок 3 | перенос пакета | отложено, Task 20 |
| набросок 4–5 | таблица, захват, лиза | отложено, Task 21 |
| набросок 6 | длина ключа, предел, чистка | отложено, Task 20, 22 |
| набросок 7 | сбой между фиксацией и сохранением | отложено, Task 22 |
| набросок 8 | дерево | отложено, Task 23 |
| набросок 9 | два экземпляра на стенде | отложено, Task 25 |
| набросок 10 | замер, `maxBulk`, ADR, итог | Task 18, 26 |
| набросок 11 | `People`, срок жизни, окно, `open_incident_guid` | отложено, Task 8–10 |
| набросок 12–13 | номера журнала | Task 11 |
| набросок 14 | отсоединение | Task 12 |
| набросок 15–17 | контракт, плохой guid, `server.js` | Task 5, 6 |
| ревью, M-1 | защита и текст отката | Task 1 |
| ревью, M-2 | текст `400` в heartbeat | Task 3 |
| ревью, M-5 | `Feed.After`; `QueueRows` и `QueueRow` остаются, причина в Task 2 | Task 2 |
| 10a | имя с NUL | Task 7 |
| 10a | поздний запрос, настоящее окно «30 с плюс ход запроса» | отложено, Task 8 |
| 10b | битая своя строка, битая строка в форме передачи | Task 7 |
| 10b | битая строка в общем списке `allTargets` | отложено, Task 9 |
| 12 | `read failed` у неудачной записи, текст `BAD_REQUEST` | Task 3, 5 |
| 15 | текст примечания | Task 5, 6 |
| 18 | комментарий `ListLinked` | Task 3 |
| 20 | `Role: ""` без метки этапа | Task 3 |
| 24 | комментарии, слот при числовом `id` | Task 3 |
| решения | `format: uuid`, `maxLength`, `maxBulk`, `viewOp(surface)`, `affectedIncidents` | Task 5, 6, 18, 17, 5 |
| 26, M-1 | один пользователь как разные | Task 4 |
| добавлено | `MoveAddressed` (`session.go:190`), проба первой | отложено, Task 8 |
| добавлено | строка слушателя только потока | отложено, Task 10 |
| добавлено | комментарий `reply.go:90–91` | Task 3 |

Строка таблицы «`read failed` … `session.go:155`» устарела по номеру: это `h.failed(before, err)` в `SetAgentState`, сейчас около строки 174.

## Структура файлов

| Файл | Отвечает за |
|---|---|
| `service/storing/filter_queries.go` | `FilterClasses`, `FilterPage`, `FilterPrimaries`, `ScenarioNames` |
| `service/transition/view_merge.go` | `MergeFits`, `MergeCandidates`, `MergeCheck`, `ClassRep` |
| `appservice/operator/filter.go` | `FilterView`: права, `badFilter`, пул, сценарии, варианты |
| `appservice/operator/filter_test.go` | варианты и каскад без базы |
| `handler/operator/filter.go` | `FilterIncidents`: разбор тела, ответы |
| `handler/operator/selection.go` | `ResolveSelection`, действия, общая форма |
| `handler/test/operator_filter_test.go`, `operator_selection_test.go` | маршруты, сверка с прототипом, контракт |

Все пути — от `internal/im/`.

---

### Task 1: миграции: база новее сборки

**Files:**
- Modify: `service/storing/common.go:184-191`, `research/integration/30-local-stand.md` (IM)
- Create: `service/storing/common_test.go` (`TestCheckAppliedMigrationsNewerDatabase`)

**Interfaces:** ничего нового.

Пакет: `go test -race ./internal/im/service/storing/ -run TestCheckAppliedMigrationsNewerDatabase`.

- [ ] **Step 1: написать падающий тест** `TestCheckAppliedMigrationsNewerDatabase`: 2 миграции в списке, 3 записи. Ждём ошибку с текстом `database is newer than this build`, не панику.
- [ ] **Step 2: запустить.** Ожидание: паника `index out of range [2] with length 2`.
- [ ] **Step 3: добавить** перед сравнением `if i >= len(migrationList) { return fmt.Errorf("database is newer than this build: …") }`.
- [ ] **Step 4: запустить.** PASS.
- [ ] **Step 5: дописать в `30-local-stand.md` раздел «Откат сборки».** Старая сборка на базе с новыми миграциями не стартует. Откат: остановить сервер, снять дамп, затем либо вернуть дамп нужного этапа (`imdb-before-019.sql`, `imdb-before-022.sql`), либо выполнить `Down` миграций в обратном порядке и убрать их записи из `im_db_migrations`, запустить старую сборку. Честная оговорка: защита есть только у сборок начиная с этой, сборка 5а на стенде упадёт паникой, база при этом не портится.
- [ ] **Step 6: коммиты.** Сервер: `Этап 5б: база новее сборки даёт ошибку, а не панику`. IM: `Этап 5б: стенд — текст отката сборки`.

### Task 2: лишние пути чтения

**Files:**
- Modify: `service/stream/feed.go:67,75`, `service/storing/` (запрос `StreamEventsAfter`), `handler/operator/testsupport.go:60-69` (только комментарий)
- Test: `handler/test/operator_stream_test.go`, `stream_helpers_test.go:497,505-510`, `handler/operator/stream_test.go:77`

**Interfaces:**
- Produces: `Feed.After` больше нет. Тестовый `feedAfter(t, store, customer, cursor, limit)` в `stream_helpers_test.go`.

Шаблон: `TestStream|TestFeed|TestHub`. Пакет без базы: `go test -race ./internal/im/handler/operator/ ./internal/im/service/stream/`.

- [ ] **Step 1: прогнать шаблон как базу сравнения.** PASS, число тестов записать в журнал.
- [ ] **Step 2: убрать `StreamEventsAfter` и `Feed.After`.** `From` при курсоре 0 идёт через `StreamEventsFrom(0)`, `id >= 0`; строки курсора при нём нет, срезать нечего и дырой это не считается (`feed.go:80-86`). Тесты получают `feedAfter`: он зовёт `Store.StreamEventsFrom(cursor+1)` прямо, без `From`, потому что `From` срезает строку своего курсора и отвечает `false` на дырах, а дыры нормальны (ADR-005). `watchedFeed.StreamEventsAfter` и `emptyFeed.StreamEventsAfter` (`handler/operator/stream_test.go:77`) уходят. `watchedFeed.StreamEventsFrom` при курсоре 0 не вычитает строку из `longest` (`stream_helpers_test.go:505-510`).
- [ ] **Step 3: оставить `QueueRows`, `QueueRow`, записать причину.** Пункт M-5 ревью сужается до `Feed.After`. 10 вызовов (`operator_cost_test.go:2342,2345,2350,2353,2404,2416,2444,2451,2557,2643`) идут на своих обработчиках `f.rowsHandler`, с точным счётом вызовов, на привязанных вне очереди и на строке, удалённой после чтения. Маршрут этого не повторит, `rowsOf` не экспортирован, а `handler/test` — внешний пакет. Причину написать английским комментарием над функциями и строкой в журнале.
- [ ] **Step 4: запустить шаблон и пакет без базы.** PASS, то же число тестов.
- [ ] **Step 5: коммит.** `Этап 5б: убран лишний путь чтения ленты`. `ConnsInUse` и `Hub.Subscribers` остаются: это наблюдение, запись есть в журнале.

### Task 3: мелочи кода

**Files:**
- Modify: `handler/operator/session.go:174,257-260`, `handler/operator/view_summary.go:257`, `handler/operator/reference.go:152`, `handler/operator/linked.go:33-35`, `handler/operator/reply.go:90-91`, `handler/operator/stream.go` (`findCursor`), `handler/operator/stream_render.go:177-180`
- Test: `handler/test/operator_session_test.go`, `operator_stream_test.go`

**Interfaces:** ничего нового.

Шаблон: `TestHeartbeatBadBody|TestSetAgentStateWriteFails|TestStreamNumericCursorTakesNoSlot`.

- [ ] **Step 1: написать три падающих теста.**
  - `TestHeartbeatBadBody`: тело `{`. `400`, `code` `BAD_REQUEST`, `messageKey` есть, текста разбора в теле нет, `checkContract` проходит.
  - `TestSetAgentStateWriteFails`: сбой записи состояния. В логе нет `read failed`, есть `agent state failed`.
  - `TestStreamNumericCursorTakesNoSlot`: все слоты заняты, `Last-Event-ID: 5`. Заголовки ушли, хотя слота нет.
- [ ] **Step 2: запустить.** FAIL все три.
- [ ] **Step 3: исправить.**
  - `session.go:257`: `newProblem(h.deps.Catalog, locale, http.StatusBadRequest, CodeBadRequest, keyBadRequest, nil)`.
  - `SetAgentState`: своя запись лога `operator API: agent state failed`, затем `h.internalError`. Слово общее: `h.failed` покрывает здесь и чтения (`storedSession`), поэтому «write failed» верно не всегда.
  - `findCursor`: при числовом id слот не берётся.
- [ ] **Step 4: запустить.** PASS.
- [ ] **Step 5: поправить комментарии, без изменения поведения.**
  - `reply.go:90–91`: фраза о другом мире верна только для `streamViewerOf`, у `viewerOn` своего комментария нет, дописать, что мир задаёт вызывающий.
  - `linked.go:33–35`: контракт уже говорит 8.
  - `stream_render.go:177–180`: «один раз на строку, а не на инцидент», битый привязанный выбрасывает всю семью.
  - `operator_stream_test.go`: над `TestStreamBehindTheTrim` убрать упоминание полной пачки.
  - `Role: pointer("")` в обоих местах: `// STAGE7: the role comes with the directory of the cloud.`
- [ ] **Step 6: коммит.** `Этап 5б: мелочи — текст 400 в heartbeat, журнал записи, слот при числовом id, комментарии`.

### Task 4: стенд: тот же пользователь не проходит как разные

**Files (вне git):**
- Modify: `~/Work/stand/second-operator.sh` (`second_on_line`), `~/Work/stand/ui-check/second-verdict.mjs`, `~/Work/stand/ui-check/check-two-windows.mjs:9,80-81`
- Не меняются: `check-operator-stream.sh`, `check-operator-transitions.sh`: оба подключают `second-operator.sh` через `source` и уже печатают `$SECOND_WHY` строкой `SKIP`.
- Modify: `research/integration/30-local-stand.md` (IM)

**Interfaces:**
- Produces: `sameUserVerdict(oneGuid, twoGuid)` в `second-verdict.mjs`: `{ ok: true }` или `{ skip: 'второй оператор — тот же пользователь' }`, тот же вид итога, что у соседних функций. Причина в `second_on_line`: `SECOND_WHY="второй оператор — тот же пользователь"`.

Скрипты печатают строки `OK`, `FAIL`, `SKIP` и `итого ошибок: N`, код выхода — число `FAIL`.

- [ ] **Step 1: снять копии** `second-operator.sh.before-5b`, `ui-check/second-verdict.mjs.before-5b`, `ui-check/check-two-windows.mjs.before-5b`.
- [ ] **Step 2: воспроизвести.** Временный файл с паролем того же тестового пользователя в scratchpad, права 600: без них `second_login` даст `SKIP` по правам файла. Это разрешено, как в 5а, паролем второго пользователя не является; значение из `check-operator-stream.sh` не печатать. Запуск: `SECOND_EMAIL=test@axxonnet.test SECOND_PASS_FILE=<файл> ~/Work/stand/check-operator-stream.sh`. Ожидание: строка `OK   вход второго оператора test@axxonnet.test: …` и дальше шаги `two_people`: тот же пользователь прошёл как разные. То же для `check-operator-transitions.sh`: итог записать в журнал, он может быть и `FAIL` (себя нет среди адресатов), это тоже подтверждает находку.
- [ ] **Step 3: исправить `second_on_line`.** После `SECOND_ID=$(field .operator.guid)` и до `SECOND=$token`: `req GET /operator/session "$TOKEN"`, код не 200 — `second_refused`, `.operator.guid` равен `SECOND_ID` — `SECOND_WHY` и `return`. Сравнивать здесь, а не с `FIRST_ID`: `FIRST_ID` есть только в `check-operator-stream.sh`, в `check-operator-transitions.sh` его нет, а `TOKEN` обязателен обоим (шапка `second-operator.sh`). Шапку дополнить новой причиной.
- [ ] **Step 4: добавить `sameUserVerdict`.** В `check-two-windows.mjs` импорт на `:9`, вызов сразу за `connectVerdict` (`:80`): `if (!report(sameUserVerdict(one.guid, two.guid))) await finish(browser);`. Причины `SKIP` в шапке `second-verdict.mjs` дополнить. Проверка без файла пароля, из `~/Work/stand/ui-check`: `node -e` с импортом модуля, `('a','a')` — `skip`, `('a','b')` — `ok`.
- [ ] **Step 5: запустить тот же случай.** С теми же переменными: `check-operator-stream.sh` — `SKIP разные пользователи: второй оператор — тот же пользователь; …`; `check-operator-transitions.sh` — `SKIP второй оператор: …`, `SKIP transfer`, `SKIP accept`; `node check-two-windows.mjs` — `SKIP разные пользователи в браузере: …`. Везде `итого ошибок: 0`. Без переменных — `SKIP` с прежней причиной `нет файла …`.
- [ ] **Step 6: удалить временный файл, дописать «Шаг 8» в `30-local-stand.md`.** Коммит IM: `Этап 5б: стенд — один пользователь больше не проходит как разные`.

### Task 5: контракт, машина, прототип (IM)

**Files:**
- Modify: `Specification/Workflow_machine/openapi.json` (CRLF, правка скриптом с `newline=""`), `BACKEND.md:44`, `workflow_schema.v1.json` (`cardNotes`), `strings/ru.json`, `strings/en.json`, `prototype/server.js:1242,1247,1490-1520,1562-1610`, `tests/api-scenarios.js`, `prototype/selftest.js`
- Modify: `tools/check_cel.mjs` (проверка `textKey`, около `:116`)

**Interfaces:**
- Produces: поле `cardNotes.rules[].hiddenTextKey`, ключ `workflow.card.note.linked_hidden`, контракт по решениям 94–96, 104.

- [ ] **Step 1: `git fetch`.** Новое на GitHub — сначала разобраться, не править поверх.
- [ ] **Step 2: написать падающие тесты в `tests/api-scenarios.js`.**
  - `объединение через маршрут одного инцидента — 404 unknown_action`;
  - `сбой вычисления условия — 500 INTERNAL_ERROR`, на маршруте перехода и на «Отсоединить все»;
  - `массовый маршрут: не-guid — 400 до расхода ключа`;
  - `DELETE linked при невидимом основном — 200, карточка отсоединённого`.
- [ ] **Step 3: запустить тесты API.** Команда из `CLAUDE.md`, бюджет 120000. Ожидание: `data-apitest="fail"`, четыре названных.
- [ ] **Step 4: править контракт по решению 94**, все шесть пунктов, и `BACKEND.md:44`, `server.js:1511`. У `DELETE linked` заголовка `If-Match` нет и не добавляется (таблица решения 104). В `BACKEND.md:44` заодно «целое от 1» → «не меньше 2», как `States rules IM.md:563`: верны правила.
- [ ] **Step 5: править `server.js`.** `:1247` и `:1603`, в обоих стоит `r.code || "FORM_FIELD_REQUIRED"`: `r.code ? problem(422, r.code, r.why) : problem(500, "INTERNAL_ERROR", …)`, ошибка вычисления `engine.js:249` кода не несёт. Решение 49: `:1242` отвечает `404 NOT_FOUND`, `workflow.error.unknown_action`, и когда `tr.bulk.mode === "merge"`, как `routable` (`transition.go:200`). `400` на не-guid в массовом маршруте. Порядок `DELETE linked` по решению 104.
- [ ] **Step 6: править машину и строки.** `hiddenTextKey` в правиле `workflow.card.note.linked`, ключи `ru` и `en`. `tools/check_cel.mjs` сверяет `hiddenTextKey` с каталогом, как `textKey`. Прототип основного не скрывает (`server.js:674`, `engine.js:753`): эта разница с решением 82 остаётся и пишется в итог, новой ветки в нём нет. Шаг самопроверки сверяет, что у каждого правила с `{primaryNumber}` есть `hiddenTextKey` и ключ есть в каталоге.
- [ ] **Step 7: собрать и проверить.** `python3 tools/build_workflow.py`, `node tools/gen_quint.mjs`, `node tools/cel_vectors.mjs --update --tmp=<scratchpad>` (~6 мин). Затем все быстрые проверки из `CLAUDE.md`, `python3 tools/check_i18n.py`, `python3 tools/check_guide.py`, самопроверка `pass`, тесты API `pass`. Мутации эта правка не задевает: в `tools/mutations/machine.json` нет `cardNote`, в `tools/check_code_mutations.py` нет `r.why`.
- [ ] **Step 8: проверить, что `openapi.json` весь в CRLF.** `python3 -c` подсчётом строк с голым `\n`: 0.
- [ ] **Step 9: коммит IM.** `Этап 5б: контракт, примечание о скрытом основном, объединение и сбой вычисления в прототипе`.

### Task 6: перенос контракта, плохой guid, формат uuid

**Files:**
- Modify: `api/im/operator/*` (через `make`), `handler/operator/bulk.go:27,87-101,172-175`, `service/transition/view_card.go:137,160`, `docs/adr/005-transitions-in-transaction.md:96`
- Test: `handler/test/operator_bulk_test.go:308` (`TestBulkNotAGuid`), `operator_contract_test.go:39`, `operator_card_test.go` (`TestHiddenPrimaryNote`), `operator_flows_test.go:1216-1243,1350` (`TestInvisiblePrimaryHidden`, `TestInvisiblePrimaryOldNumberStays`), `operator_merge_test.go:138` (`TestMergeMissing`, не меняется)

**Interfaces:**
- Consumes: контракт Task 5.
- Produces: `bulkFailure.IncidentGUID uuid.UUID`.

Шаблон: `TestBulkNotAGuid|TestHiddenPrimaryNote|TestInvisiblePrimary|TestMergeMissing|TestCheck`.

- [ ] **Step 1: перенести.** `make vendor-operator-contract && make gen-api-operator`. Без базы: PASS, `git diff --stat api/` показывает только ожидаемое.
- [ ] **Step 2: включить формат** в `operator_contract_test.go:39` (решение 95). Запустить `-run 'TestCheck|TestStream|TestBulk'`. Падение на поле — ошибка сервера, чинить здесь. Если ошибается контракт, это единственная разрешённая вторая правка: записать в журнал, сделать в отдельном коммите IM, перенести.
- [ ] **Step 3: написать падающие тесты.**
  - `TestBulkNotAGuid` меняется сознательно: `400 BAD_REQUEST`, переход не выполнен; повтор того же ключа с верным телом выполняет работу, ключ не потрачен.
  - `TestHiddenPrimaryNote`: основной не виден, текст примечания без `—` и без номера, ключ `workflow.card.note.linked_hidden`.
  - `TestInvisiblePrimaryHidden` и `TestInvisiblePrimaryOldNumberStays` меняются сознательно: `requireNoteNames(card.Body, hiddenPrimary)` (`operator_flows_test.go:1243,1350`) ждёт `—` и старый ключ, вместо него новый `requireNoteHidden(t, card)`.
- [ ] **Step 4: запустить шаблон.** FAIL на этих четырёх.
- [ ] **Step 5: реализовать.** Проверка всех элементов — в `ExecuteBulkTransition`, сразу после чтения тела, до `once` (решение 95). `readTransitionBody` общий с `merge`, его не трогать: `TestMergeMissing` ждёт `404`. `cardNote` при `hide` берёт `hiddenTextKey`, если он есть.
- [ ] **Step 6: запустить шаблон и «без базы».** PASS. В ADR-005:96 заменить фразу «An id that is not a guid is in `failed`» новым ответом `400`.
- [ ] **Step 7: коммит.** `Этап 5б: контракт, не-guid в выборке — 400, формат uuid в проверках, примечание без номера`.
- [ ] **Step 8: отказ плохому ключу, без переноса пакета.** Контракт обещает `maxLength: 200`, решение 74 обещало отказ в 5б, а Task 20 отложена. В нынешнем пакете `handler/operator/idempotency` добавить `const MaxKeyLength = 200` и `Storable(value string) bool`: длина в символах, не байтах; NUL и битый UTF-8 — нет; пусто — да. Падающие тесты: `TestStorable` (без базы: 200 символов кириллицей да, 201 нет, NUL нет, `"\xff"` нет, пусто да), `TestKeyTooLongIsRefused` и `TestKeyWithNulIsRefused` (`400 BAD_REQUEST`, действия нет, на всех трёх маршрутах), `TestKeyExactly200Works` в `operator_idempotency_test.go`. Проверка в `once`, первой: неверный ключ не доходит до `Do`. `428` стоит внутри `once`, поэтому плохой ключ без `If-Match` даёт `400`. Шаблон: `TestKey|TestIdempotent|TestStorable`. Коммит: `Этап 5б: плохой ключ повтора — 400`.

### Task 7: битые строки и имя

**Files:**
- Modify: `model/operator_session.go`, `model/user.go`, `appservice/operator/session.go:473,601-608`, `service/storing/session_queries.go`
- Test: `model/operator_session_test.go` (`TestCleanName`), `handler/test/operator_session_test.go` (`TestNameWithNULKeepsRow`, `TestBrokenRowMends`, `TestBrokenPreferencesKeepRow`, `TestBrokenRowNotInPeople`)

**Interfaces:**
- Produces: `model.CleanName(name string) string`.

Шаблон: `TestNameWithNULKeepsRow|TestBrokenRowMends|TestBrokenRowNotInPeople|TestBrokenPreferencesKeepRow`. Пакет без базы: `go test -race ./internal/im/model/ -run TestCleanName`.

- [ ] **Step 1: написать падающие тесты.**
  - `TestCleanName` (без базы): `"a\x00b"` → `"ab"`, `"a\xffb"` → `"ab"`, обычное имя без изменений, кириллица без изменений.
  - `TestNameWithNULKeepsRow`: имя из облака с NUL. `GET` даёт `200`, строка есть, имя чистое.
  - `TestBrokenRowMends`: в строке `permissions` — JSON-строка вместо массива, `UPDATE` прямо в тестовой базе. После `GET` права читаются верно.
  - `TestBrokenPreferencesKeepRow`: `preferences = '[]'`. Строка читается, настройки `{}`, `Warn` есть.
  - `TestBrokenRowNotInPeople`: подготовка важна, иначе тест пройдёт на пустом месте. Второй человек сначала входит, он в памяти процесса; затем `UPDATE` ломает его `permissions`. Первый открывает форму передачи: запрос не падает, второго среди адресатов нет.
- [ ] **Step 2: запустить.** FAIL, кроме `TestBrokenRowNotInPeople`: по коду он зелёный уже сейчас, машина не предлагает человека без строки, как в `TestBrokenRowOfAColleague`. Тест остаётся защитой, если окажется красным — чинить здесь.
- [ ] **Step 3: реализовать по решению 98.** `TestBrokenRowNotInPeople` проверяет память плюс `Sessions`. Заодно комментарий над `comeBack`: «Those windows are for stage 5b» заменить на «before the public launch, plan 57».
- [ ] **Step 4: запустить шаблон и «без базы».** PASS.
- [ ] **Step 5: коммит.** `Этап 5б: имя с NUL и битые строки сессии чинятся, а не теряют человека`.

### Task 11: номера журнала

**Files:**
- Modify: `handler/operator/view_journal.go:105-113`, `appservice/operator/deps.go`, `service/storing/` (`MachineIncidentsByNumbers`), `appservice/operator/load.go` (`HideAsBefore`, если больше нигде не нужен), `model/incident_state.go`
- Modify: `handler/operator/view_journal_test.go:16`: `TestHidePrimaryNumber` становится `TestHideNumbers`, иначе пакет не соберётся
- Modify: `handler/test/operator_flows_test.go:1332-1352`: `TestInvisiblePrimaryOldNumberStays` становится `TestInvisiblePrimaryOldNumberHidden`
- Create: `handler/test/operator_journal_test.go` (`TestJournalHidesFormerPrimary`, `TestJournalHidesEarlierPrimary`, `TestJournalHidesSiblingAndLinked`, `TestJournalHidesNumbersInMergedIn`, `TestJournalDeletedPrimaryHidden`, `TestJournalHidesUnparsableNumber`, `TestJournalHidesOtherCustomerNumber`, `TestJournalEmptyNumberNoLog`, `TestJournalNumbersOneRead`)

**Interfaces:**
- Produces: `Store.MachineIncidentsByNumbers(ctx model.AppContext, customer uuid.UUID, numbers []int64) (map[int64]uuid.UUID, error)`; `model.ParseIncidentNumber(s string) (int64, bool)`.

Шаблон: `TestJournal|TestInvisiblePrimary`. Пакеты без базы: `go test -race ./internal/im/handler/operator/ ./internal/im/model/ -run 'TestHideNumbers|TestParseIncidentNumber'`.

- [ ] **Step 1: написать падающие тесты, таблицей по шаблонам журнала.**
  - `TestJournalHidesFormerPrimary`: после `detach`, `reopen_unlinked`, `linked_lost_access` основной не виден, в строке `—`; виден — номер.
  - `TestJournalHidesEarlierPrimary`: инцидент побывал у двух основных, виден второй, первого нет. Первый скрыт, второй показан.
  - `TestJournalHidesSiblingAndLinked`: `sibling_closed`, `linked_lost_access_primary`, `answers_moved`, `linked_reopened`, `group_deadline`: `number` скрыт, когда не виден.
  - `TestJournalHidesNumbersInMergedIn`: `ids` = `INC-0001, INC-0002, INC-0003`, виден только второй. Текст `—, INC-0002, —`, порядок и `{more}` сохранены.
  - `TestJournalDeletedPrimaryHidden`: удалённый основной скрыт.
  - `TestJournalHidesUnparsableNumber`: значение `мусор` показано как `—`, `Warn` есть.
  - `TestJournalHidesOtherCustomerNumber`: такой номер есть только у другого клиента. `—`.
  - `TestJournalEmptyNumberNoLog`: пустой `primaryNumber` не даёт запроса и `Warn`.
  - `TestInvisiblePrimaryOldNumberHidden`: сознательная замена `TestInvisiblePrimaryOldNumberStays`, которая закрепляла оговорку решения 82. Строка о прежнем невидимом основном теперь `—`, а не `numberOf(old)`.
  - `TestJournalNumbersOneRead`: 1 и 200 строк журнала — одно и то же число запросов.
  - `TestParseIncidentNumber` (без базы): `INC-0001`, `INC-12345`, пусто, мусор.
- [ ] **Step 2: запустить шаблон.** FAIL.
- [ ] **Step 3: реализовать по решению 103.** `journal` собирает номера до показа: значения заменяются до сборки текста, в готовую фразу номер не попадает. Номер без изменений, если он равен своему номеру инцидента. Комментарий решения 82 над тестом и в `view_journal.go` поправить. Ошибка чтения — `500`, как прочие чтения вида. `HideAsBefore` остаётся только там, где нужен примечанию.
- [ ] **Step 4: запустить шаблон и `-run 'TestCard|TestReadBudgets'`.** PASS, карточка 19 запросов при потолке 30.
- [ ] **Step 5: коммит.** `Этап 5б: журнал скрывает номера, которых человек не вправе видеть`.

### Task 12: отсоединение

**Files:**
- Modify: `handler/operator/linked.go:78-115,188`
- Test: `handler/test/operator_linked_test.go` (`TestDetachRoutesAnswerAlike`, `TestDetachHiddenPrimaryDelete`, `TestDetachHiddenPrimaryStale`, `TestDetachHiddenPrimaryRace`, `TestDetachHiddenPrimaryEditableRefused`, `TestDetachAllHiddenPrimary`, `TestDetachInvisibleLinked`)

**Interfaces:**
- Consumes: `runOne(c, l, transitionID, form, surface, expect, linkedTo)`.
- Produces: `(h *Handler) currentOfPrimary(v *viewer, primary, linked uuid.UUID) reply`.

Шаблон: `TestDetach|TestInvisiblePrimary`.

- [ ] **Step 1: написать падающие тесты.**
  - `TestDetachRoutesAnswerAlike`: таблица отказов, общая для `POST` и `DELETE`, основной виден: нет права, агент не готов. Коды те же, что в таблице решения 104. Устаревшей версии здесь нет: у `DELETE` нет `If-Match`.
  - `TestDetachHiddenPrimaryDelete`: привязанный виден, основной нет, у него нет владельца (`c.merger.done(c.primary.GUID, releaseID, commentForm())`, иначе откажет `primaryEditable`). `DELETE` — `200`, карточка отсоединённого, `linkedTo` пуст, основной не упомянут. `checkContract` проходит.
  - `TestDetachHiddenPrimaryStale`: только `POST`, устаревший `If-Match`. `412`, `current` — отсоединённый, полей основного нет. Этот случай зелёный уже сейчас (`operator_flows_test.go:1255`), тест остаётся защитой.
  - `TestDetachHiddenPrimaryRace`: только `DELETE`, гонка `ErrNotLinkedHere` через `f.racing`, как `TestInvisiblePrimaryInConflictOfDetachAll`. `412`, `current` — тот, кого отсоединяли, полей основного нет.
  - `TestDetachHiddenPrimaryEditableRefused`: основной у другого владельца, `primaryEditable` отказывает. `403` на обоих маршрутах, в теле нет номера и полей основного.
  - `TestDetachAllHiddenPrimary`: остаётся `404`.
  - `TestDetachInvisibleLinked`: `404`, на обоих маршрутах.
- [ ] **Step 2: запустить шаблон.** FAIL на случаях невидимого основного.
- [ ] **Step 3: реализовать.** Сначала `h.find` привязанного, `linkedTo` сверяется по его строке. `h.find` основного: не виден — ветка карточки. Иначе как сейчас. `currentOfPrimary` получает и привязанного: основной не виден — `h.conflict` по нему, `404` только если не виден и он.
- [ ] **Step 4: запустить шаблон и `-run 'TestLinked'`.** PASS.
- [ ] **Step 5: коммит.** `Этап 5б: отсоединение выровнено — тот, кто не видит основного, получает карточку привязанного`.

### Task 13: ядро: условия на пути чтения

**Files:**
- Create: `service/transition/view_merge.go`, `service/transition/view_merge_test.go` (`TestClassRepHasEveryField`, `TestMergeFitsFollowsGuards`, `TestMergeCandidatesFollowMachine`, `TestViewAvailabilityLikeEngine`, `TestMergeCheckOnReadLikeRun`)
- Modify: `service/transition/view.go`

**Interfaces:**
- Produces, все в пакете `transition`:
  - `(c *Core) ClassRep(id, state, owner, group, scenario string) (map[string]any, error)` — полный инцидент машины из пустой строки через `ToMachine(mi, timerIDs)` (`row.go:24`), чтобы выражения не падали на отсутствующем ключе. Метод `Core`: список таймеров знает он;
  - `(c *Core) MergeFits(w World, op ViewOp, primary, joined map[string]any) (bool, error)`;
  - `(c *Core) MergeCandidates(w World, me string, reps []map[string]any) ([]int, error)`;
  - `(v *View) Availability(id string, form map[string]any) (machine.Availability, error)`;
  - `(c *Core) MergeCheck(views []*View, primaryID string) (*MergeVerdict, error)` — сам ничего не читает, виды передаёт вызывающий: этим держится один `ViewPage` решения 109;
  - `MergeVerdict{OK bool; Fail *machine.Fail; Guard, Incident string; Take bool}`.

Пакет: `go test -race ./internal/im/service/transition/ -run 'TestClassRep|TestMergeFits|TestMergeCandidates|TestViewAvailability|TestMergeCheckOnRead'`.

- [ ] **Step 1: написать падающие тесты.**
  - `TestClassRepHasEveryField`: `ToMachine` на пустой строке даёт все поля; `mergePrimaryValid`, `sameScenarioAsPrimary` и `mergePrimary` считаются на представителях без ошибки.
  - `TestMergeFitsFollowsGuards`: таблица по `state`, `owner`, сценарию, готовности агента, сверка с `availableOn` на тех же данных с настоящим `incidentById`.
  - `TestMergeCandidatesFollowMachine`: есть «мой в работе» — в ступени только такие; нет — все `new`; нет никого — пусто.
  - `TestViewAvailabilityLikeEngine`: `OK`, `Hidden`, `NotFrom`, `Fail` совпадают с тем, что вернёт ядро, поверхность пустая.
  - `TestMergeCheckOnReadLikeRun`: `Refusal` из `operation.mergeCheck` и `MergeVerdict` дают одну причину на одних данных.
- [ ] **Step 2: запустить.** FAIL: нет функций.
- [ ] **Step 3: реализовать.** `MergeFits` собирает `machine.Scope` с `RefSource`, который на `incidentById` отвечает `primary`, форма `{primaryId}`. `MergeCandidates`, алгоритм: `W = MergePrimary(reps)`, нет — пусто. Класс `c` в одной ступени с `W`, если при `c.priority = 1`, `W.priority = 0` `MergePrimary([W, c])` выбирает `c`. Так ступень считает машина, а Go условия не дублирует.
- [ ] **Step 4: запустить, затем «без базы».** PASS.
- [ ] **Step 5: коммит.** `Этап 5б: ядро — условие объединения и доступность на пути чтения`.

### Task 14: `filterIncidents`: классы, варианты, список

**Files:**
- Create: `service/storing/filter_queries.go`, `model/filter.go`, `appservice/operator/filter.go`, `handler/operator/filter.go`
- Create: `appservice/operator/filter_test.go` (`TestFacetPickedValueKept`, `TestFacetCascade`, `TestBadFilterTable`), `handler/test/operator_filter_test.go` (`TestFilterClassesMatchRows`, `TestFilterHidesInvisible`, `TestFilterBadBody`, `TestFilterUnknownNode`, `TestFilterUnderNode`, `TestFilterLimit`, `TestFilterCountMatchesGuids`, `TestFilterOrderIsQueueOrder`, `TestFilterRowMovesBetweenReads`, `TestFilterSQLCount`)
- Modify: `appservice/operator/deps.go`, `handler/operator/stubs.go:44`

**Interfaces:**
- Consumes: `(d *Deps) QueueFilters`, `queueScope`, `h.queueOrder`, `user.Permissions.HasAnyMachinePermission()`.
- Produces:
  - `model.FilterClass` (решение 105), `model.FilterPrimary{GUID uuid.UUID; Class FilterClass}`: `Class.Count` равно 1, поля класса читает запрос;
  - `Store.FilterClasses(ctx model.AppContext, scope model.QueueScope, ancestors, descendants []uuid.UUID) ([]model.FilterClass, error)`;
  - `Store.FilterPage(ctx model.AppContext, scope model.QueueScope, classes []model.FilterClass, also []uuid.UUID, order string, limit int) ([]uuid.UUID, error)`;
  - `Store.FilterPrimaries(ctx model.AppContext, scope model.QueueScope, classes []model.FilterClass) ([]model.FilterPrimary, error)`;
  - `Store.ScenarioNames(ctx model.AppContext, customer uuid.UUID, guids []uuid.UUID) (map[uuid.UUID]string, error)`;
  - `opapp.FilterAsk{Queue string; Node string; Filter any; SameScenario bool; Scenario string}`: узел, фильтр и сценарий идут как прислал клиент, смысл им даёт `FilterView`. `opapp.FilterCondition{DeviceType string; EventTypes []string; Devices []string}` — внутри пакета, итог `normCond`;
  - `opapp.FilterResult{Count, Excluded int; GUIDs []uuid.UUID; Versions map[uuid.UUID]int64; Truncated bool; Scenario *uuid.UUID; Conditions []FilterOptions; Scenarios []FilterOption}`, `opapp.FilterOptions{DeviceTypes, EventTypes, Devices []FilterOption}`, `opapp.FilterOption{ID, Label string; Count int}`;
  - `(d *Deps) FilterView(ctx model.AppContext, user *model.User, ask FilterAsk) (*FilterResult, error)`; `opapp.ErrUnknownNode`; `opapp.BadFilterError{Name string}` на плохой `filter` и неизвестный `queueFilter`.

Шаблон: `TestFilter`. Пакет без базы: `go test -race ./internal/im/appservice/operator/ -run 'TestFacet|TestBadFilter'`.

- [ ] **Step 1: написать падающие тесты без базы.** `TestFacetPickedValueKept`, значение выбрано, строк нет, вариант с нулём есть; `TestFacetCascade`, события — по типу устройства, устройства — по типу и событиям, как `forEvents`, `forDevices`; `TestBadFilterTable`, перенос `badFilter`, `normCond`, `normFilter`.
- [ ] **Step 2: написать падающие тесты с базой.**
  - `TestFilterClassesMatchRows`: сумма `Count` по классам равна честному подсчёту строк, на каждом измерении.
  - `TestFilterHidesInvisible`: инцидент без правила доступа не даёт вариантов, чисел, сценария; чужой клиент тоже; пользователь с группами и правилами, но без прав машины — `200`, пусто, `FilterClasses` не вызван.
  - `TestFilterBadBody`: таблица из `400` (не JSON) и `422` (плохой `filter`, неизвестный `queueFilter`), `name` в тексте; узел проверяется раньше них.
  - `TestFilterUnknownNode`: нет узла, не-guid (`"nope"`) и узел другого клиента — `404`, как `api-scenarios.js:2863`.
  - `TestFilterUnderNode`: только источники узла и его потомков.
  - `TestFilterLimit`: `patchedCore` ставит `maxBulk: 3`, строк 5. `count` 5, три guid, три версии, `truncated`.
  - `TestFilterCountMatchesGuids`: покой, `maxBulk: null`. `count` равен длине списка.
  - `TestFilterOrderIsQueueOrder`: порядок как у очереди с настройками по умолчанию.
  - `TestFilterRowMovesBetweenReads`: обёртка над `Store` удаляет строку между `FilterClasses` и `FilterPage`. `200`, строки нет ни в `incidentGuids`, ни в `versions`, `count` прежний.
  - `TestFilterSQLCount`: 10 и 1000 строк — равенство, потолок 15.
  - Каждый ответ идёт через `checkContract`.
- [ ] **Step 3: запустить оба.** FAIL.
- [ ] **Step 4: реализовать по решениям 105, 107.** Варианты без галочки. Сценарии с `count` по `takeable` приходят в Task 15, здесь `FilterView` отдаёт `excluded = 0`, `scenarioGuid = nil`, `scenarios` с числом строк. `FilterIncidents` разбирает тело свободно, в `map`, не в сгенерированный тип: иначе плохой `filter` станет `400`, а не `422`. Порядок в `FilterView`: права, узел, `badFilter`, `queueFilter`, только потом запросы. Заглушка уходит.
- [ ] **Step 5: запустить оба и `-run 'TestQueue|TestCheck'`.** PASS.
- [ ] **Step 6: коммит.** `Этап 5б: filterIncidents — классы, варианты, список`.

### Task 15: `filterIncidents`: одинаковый сценарий

**Files:**
- Modify: `appservice/operator/filter.go`, `service/storing/filter_queries.go`
- Test: `handler/test/operator_filter_test.go` (`TestTakeableClassesMatchRowCEL`, `TestFilterPrimaryMatchesMachine`, `TestFilterPrimaryGivesOptions`, `TestFilterSameScenarioPicksBest`, `TestFilterSameScenarioAskedKept`, `TestFilterSameScenarioEmptyFallsToBest`, `TestFilterSameScenarioAllEmpty`, `TestFilterSameScenarioGone`, `TestFilterSamePrimaryOwnClass`, `TestFilterViableKeepsPicked`, `TestFilterSameScenarioHidesInvisible`), `appservice/operator/filter_test.go`

**Interfaces:**
- Consumes: всё из Task 13 и 14, `c.ClassRep`.
- Produces: заполненные `FilterResult.Excluded`, `FilterResult.Scenario`, `FilterClass.Leads`; внутри пакета `takeable(classes []model.FilterClass, primary *model.FilterPrimary) (count int, fit []model.FilterClass, also []uuid.UUID, err error)`: `fit` — подошедшие классы, плюс класс основного с `Count: 1`, если его собственный класс не подошёл. Этот добавленный класс — только для вариантов: в `FilterPage` идут классы без него, а сам основной через `also`.

Шаблон: `TestFilterSame|TestTakeable|TestFilterPrimary|TestFilterViable`.

- [ ] **Step 1: написать падающие тесты.**
  - `TestTakeableClassesMatchRowCEL`: все состояния, владелец я, другой, никто, группа; готов и на перерыве. Сверка `count`, `excluded` и списка с подсчётом по строкам: `MergePrimary` по строкам в порядке номера, `Availability` каждой строки. Это главный тест решения 106.
  - `TestFilterPrimaryMatchesMachine`: срочность, давность, равные с разным номером. `FilterPrimaries` равен `Core.MergePrimary` по строкам.
  - `TestFilterSameScenarioPicksBest`: не указан — сценарий с наибольшим числом.
  - `TestFilterSameScenarioAskedKept`: указан, есть что взять.
  - `TestFilterSameScenarioEmptyFallsToBest`: указан, взять нечего, в другом есть.
  - `TestFilterSameScenarioAllEmpty`: взять нечего нигде, указанный остаётся.
  - `TestFilterSameScenarioGone`: `scenarioGuid: "нет-такого"`. `200`, сценарий заменён лучшим, как `api-scenarios.js:2843`.
  - `TestFilterSamePrimaryOwnClass`: класс основного сам условию не подошёл, основной всё равно в списке и в числе.
  - `TestFilterPrimaryGivesOptions`: агент на перерыве, классы отпали, остался основной. Варианты при галочке содержат его тип устройства, событие и источник: любой выбор что-то оставляет, как `api-scenarios.js:2828–2841`.
  - `TestFilterViableKeepsPicked`: у варианта нет класса с `Leads` — вариант уходит, выбранный остаётся.
  - `TestFilterSameScenarioHidesInvisible`: невидимый не в `excluded`.
- [ ] **Step 2: запустить.** FAIL.
- [ ] **Step 3: реализовать по решению 106.** Один `FilterPrimaries` на `all` по сценариям. Для галочки и выбранного сценария ещё один, на `base`: `base` шире `all`, это пул без условий. Итого не больше двух запросов. `Leads` считается `MergeCandidates` на одном представителе, для каждого класса `base`, без SQL. Поле условия вне класса — в класс и `GROUP BY`.
- [ ] **Step 4: запустить `-run 'TestFilter|TestTakeable'`.** PASS. `TestFilterSQLCount` остаётся верным: дополнить случаем 1 и 5 сценариев.
- [ ] **Step 5: коммит.** `Этап 5б: filterIncidents — одинаковый сценарий на классах`.

### Task 16: `resolveSelection`: список

**Files:**
- Create: `handler/operator/selection.go`
- Create: `handler/test/operator_selection_test.go` (`TestSelectionExplicitOrder`, `TestSelectionExplicitHidesInvisible`, `TestSelectionExplicitEmpty`, `TestSelectionAllInFilter`, `TestSelectionTruncated`, `TestSelectionUnknownMode`, `TestSelectionBadGuid`, `TestSelectionSearchTooLong`, `TestSelectionEmptyHasNoActions`)
- Modify: `handler/operator/stubs.go:48`, `appservice/operator/queue.go` (`QueueAsk`)

**Interfaces:**
- Consumes: `QueueList`, `uniqueIDs`, `VisibleAmong`, `LoadMany`.
- Produces: `QueueAsk.LeaveDone bool`; `(h *Handler) ResolveSelection(c *gin.Context)`; `(h *Handler) selectionRows(v *viewer, body operatorgen.SelectionRequest) ([]*opapp.Loaded, bool, *reply)`.

Шаблон: `TestSelection`.

- [ ] **Step 1: написать падающие тесты.**
  - `TestSelectionExplicitOrder`: порядок как дан, повторы убраны, `truncated` нет.
  - `TestSelectionExplicitHidesInvisible`: невидимый и чужой не в ответе, ни guid, ни версия, отличить от несуществующего нельзя.
  - `TestSelectionExplicitEmpty`: `{mode: "explicit", incidentGuids: []}` и `{mode: "explicit"}` — оба `422 BULK_SELECTION_INVALID`, `workflow.error.selection_empty`, как `api-scenarios.js:2903`.
  - `TestSelectionAllInFilter`: завершённых нет, порядок очереди, фильтр, поиск, сценарий, узел, тип устройства работают как `listIncidents`.
  - `TestSelectionTruncated`: `maxBulk: 3`, строк 5, три guid, `truncated: true`.
  - `TestSelectionUnknownMode`: `400`.
  - `TestSelectionBadGuid`: не-guid в `explicit` — `400`.
  - `TestSelectionSearchTooLong`: `search` длиннее 200 — `400`, как `listIncidents`.
  - `TestSelectionEmptyHasNoActions`: `all_in_filter` без строк, `actions: []`.
  - Все ответы через `checkContract`. `actions` пока `[]`.
- [ ] **Step 2: запустить.** FAIL: `501`.
- [ ] **Step 3: реализовать по решению 108.** Заглушка уходит, `stubs.go` — 30 штук, поправить счётчик в тесте, если он есть. `LeaveDone` убирает классы, где `isDone` машины верно: завершённость решает машина.
- [ ] **Step 4: запустить шаблон и `-run 'TestQueue'`.** PASS.
- [ ] **Step 5: коммит.** `Этап 5б: resolveSelection — явный список и всё в фильтре`.

### Task 17: `resolveSelection`: действия и общая форма

**Files:**
- Modify: `handler/operator/selection.go`, `handler/operator/view_actions.go:18-20`
- Test: `handler/test/operator_selection_test.go` (`TestSelectionMergeNamesWhoBlocks`, `TestSelectionEachAllowed`, `TestSelectionSharedForm`, `TestSelectionFormHasPeople`, `TestSelectionHiddenActionCarriesFlags`, `TestSelectionMergeTooFew`, `TestSelectionSQLCount`)

**Interfaces:**
- Consumes: `v.selectionOp()`, `View.Availability`, `Core.MergeCheck`, `Core.MergePrimary`, `Core.BulkPrimary`.
- Produces: `(h *Handler) selectionActions(v *viewer, rows []*opapp.Loaded) ([]operatorgen.AvailableAction, error)`.

Шаблон: `TestSelection`.

- [ ] **Step 1: выписать 23 теста `tests/api-scenarios.js`** (строки 1626, 1640, 2345, 2372, 2390, 2415, 2436, 2792, 2847, 2871, 2902, 2914, 3560, 3590, 3606, 3687, 3851, 4133 и соседние по `grep`) в `.superpowers/sdd/57-plan-stage5b/mapping.md`: тест прототипа → тест Go. Пустая ячейка закрывается следующим шагом или причиной.
- [ ] **Step 2: написать падающие тесты по таблице.** Обязательные:
  - `TestSelectionMergeNamesWhoBlocks`: чужой сценарий в наборе, действие недоступно, причина с номером мешающего (`ARCH-08`).
  - `TestSelectionEachAllowed`: `accept`, `reject`, `hold`, `release`, `transfer`, `takeover`, `close`. `visible` — относится хоть к одному; `enabled` — доступно каждому в охвате; иначе `enabled: false`, причина `workflow.error.selection.item` с номером. Как `api-scenarios.js:2885-2888`: «Перехватить» видна, но недоступна, причина с номером; «Закрыть» доступна, потому что доступна обоим.
  - `TestSelectionSharedForm`: варианты пересекаются по всем инцидентам, `formNote` со `scopeNoteKey`, `fieldRules` есть (`transfer.fieldRules.targetId`, `api-scenarios.js:4144`).
  - `TestSelectionFormHasPeople`: `fieldOptions.targetId` есть, в отличие от строки очереди. Решение 73 и пункт `viewOp(surface)`. Адресаты идут из памяти процесса (решение 75), поэтому коллега делает запрос до выборки, таблицу тест не читает.
  - `TestSelectionHiddenActionCarriesFlags`: скрытое действие есть в `actions` с `visible: false`, `enabled: false`, как `api-scenarios.js:2887`. Панель фильтрует сама (`app.js:3952`).
  - `TestSelectionMergeTooFew`: `patchedCore` ставит `minItems: 3`, в выборке две строки, отказ по `minItems`. Один инцидент проверки не проходит: это обычное «Взять» (`server.js:1334`).
  - `TestSelectionSQLCount`: 2 и 200 строк равны, потолок 35.
- [ ] **Step 3: запустить.** FAIL.
- [ ] **Step 4: реализовать по решению 109.** `v.selectionOp()` рядом с `viewOp`. Порядок и тексты — `selectionActions`, `sharedForm`, `sharedFormOf`, `server.js:1313–1405`. Логики правил в Go не заводить: всё через `Availability`, `MergeCheck` и данные машины.
- [ ] **Step 5: запустить шаблон и `-run 'TestRowForm|TestQueue|TestCheck'`.** PASS. Таблица `mapping.md` без пустых ячеек.
- [ ] **Step 6: коммит.** `Этап 5б: resolveSelection — действия и общая форма выборки`.

### Task 18: замер и `limits.maxBulk`

**Files:**
- Modify: `handler/test/operator_cost_test.go`
- Modify при успешном замере: `Specification/Workflow_machine/workflow_schema.v1.json:1220` (IM), `tests/api-scenarios.js`, сборка; `api/im/operator/*` (через `make`), `docs/adr/005-transitions-in-transaction.md:100`

**Interfaces:** ничего нового.

Шаблон замера: `TestFilterBudget|TestSelectionBudget|TestBulkBudget`.

- [ ] **Step 1: написать тесты бюджетов.** `TestFilterBudget`, `TestFilterSameScenarioBudget`, `TestSelectionBudget`, `TestBulkBudget200`, `TestBulkBudget200Absent`, с `measure` на `f.costTree`, числа из решений 110, 118. Отдельный случай `TestFilterManyDevicesBudget`: 5000 открытых на 5000 устройств, классов столько же, это худший случай классов.
- [ ] **Step 2: запустить замер три раза** подряд, один прогон на базе за раз. Записать три значения каждой строки в журнал.
- [ ] **Step 3: разобрать.** Бюджет фильтра не сошёлся — чинить здесь: сначала посмотреть число классов и время `CEL` на класс. Не сошлось только на `TestFilterManyDevicesBudget` — записать цифру и не менять бюджет: это уже объёмы, решение до публичного запуска.
- [ ] **Step 4: решить по решению 118.** Сошлось — следующий шаг. Нет — шаги 5–7 пропускаются, цифры идут в открытые вопросы итога, в ADR записывается, что `null` остался и почему.
- [ ] **Step 5: IM, `git fetch`, `limits.maxBulk: 200`.** Правило `States rules IM.md:563` допускает значение от 2, правила не меняются. Строка в `SETTINGS.md` соберётся сама. `tests/api-scenarios.js:1595,1610` и `prototype/selftest.js:2641` уже задают `null` сами. Собрать: `python3 tools/build_workflow.py`, `node tools/gen_quint.mjs`, `node tools/cel_vectors.mjs --update --tmp=<scratchpad>`. Проверить: быстрые проверки, `python3 tools/check_scenarios.py`, самопроверка, тесты API, `python3 tools/check_mutations.py` по задетым. Коммит IM: `Этап 5б: limits.maxBulk 200 по замеру`.
- [ ] **Step 6: сервер.** `make vendor-operator-contract && make gen-api-operator`. Обновить строку ADR-005:100 новыми цифрами, вместо `2000 guid 26 с`.
- [ ] **Step 7: запустить `-run 'TestBulk|TestFilter|TestSelection|TestMerge'`.** PASS: тесты, где строк больше 200 без `patchedCore`, поправить, если есть.
- [ ] **Step 8: коммит сервера.** `Этап 5б: замер фильтра и выборки, limits.maxBulk`.

### Task 19: стенд и полный прогон

**Files:**
- Create (вне git): `~/Work/stand/check-operator-filter.sh`
- Modify: `research/integration/30-local-stand.md`

**Interfaces:** ничего нового.

- [ ] **Step 1: полный прогон.** Пересоздать im-test-db. Весь пакет с `-timeout 40m`, затем «без базы», `go vet ./...`, `gofmt -l internal/im`, `golangci-lint run ./...`, `make test-local`. Всё чисто.
- [ ] **Step 2: стенд.** Миграций нет, схема та же, что у 5а, поэтому дамп не нужен. Перезапустить `run-im-server.sh`: он сам собирает `bin/im`, вывод в `im-server.log` направляет вызывающий, старый лог сначала копируется в `im-server.before-5b.log`. В логе нет `database is newer`.
- [ ] **Step 3: написать `check-operator-filter.sh`** по образцу `check-operator-api.sh`: через шлюз, настоящий токен, строки `OK|FAIL|SKIP`, `итого ошибок: N`, код выхода — число `FAIL`. Оператор выходит на линию `PUT agent-state ready`, инцидент даёт `"$EMU" replay --limit 1 --run "stage5b-$(date +%s)"`. `POST filter` без условий, с условием, с `sameScenario`; `POST selection` `explicit` и `all_in_filter`; `400` на не-guid в массовом маршруте. Новых пользователей нет. Адресаты: `transfer` есть в `actions` выборки, но пользователь на стенде один, а список идёт из памяти процесса (решение 75). Пустой `fieldOptions.targetId` и `enabled: false` — не `FAIL`, а строка `SKIP` с этой причиной.
- [ ] **Step 4: запустить** `check-operator-filter.sh`, `check-operator-api.sh`, `check-operator-transitions.sh`, `check-operator-stream.sh`. Ожидание: `итого ошибок: 0`, `SKIP` только с названной причиной. `second-operator.pass` не искать.
- [ ] **Step 5: поправить раздел «Откат сборки» в `30-local-stand.md`:** в нём названа миграция 022 в Task 19. Пункт о дампах: `imdb-before-019.sql` подходит сборкам до 5а; сборки 5а и 5б стоят на одной схеме (21 миграция), откат с 5б на 5а базы не трогает; файл `imdb-before-022.sql` появится, только когда будет применена миграция 022 (Task 8 плана 57, отложена до публичного запуска), и снимать его надо до применения.
- [ ] **Step 6: коммит IM.** `Этап 5б: проверка фильтра на стенде, откат без миграции 022`.

### Task 26: ADR, документы, итог

**Files:**
- Modify: `docs/adr/002-operator-api-package.md`, `docs/adr/005-transitions-in-transaction.md` (`Carried to stages 5b-7`, `Known limits`) (сервер)
- Modify: `research/integration/40-plan.md:92`, `research/integration/README.md`, этот план (раздел «Итог»)

**Interfaces:** ничего нового.

- [ ] **Step 1: ADR.** Закрытое в 5б убрать из «Carried», оставить то, что ушло на этапы 6–7 и до публичного запуска, с пометкой, откуда. Записать разницы с прототипом: сортировка вариантов, строка журнала соседа без версии, неизвестный `mode`, не-guid в `explicit`, `candidateTransitionIds`, `sourceGroupGuid: "all"`. Сверить «Known limits» с Task 6: фраза ADR-005:96 о не-guid уже заменена. В ADR-002 (пункты 10, 12, 16) и ADR-005 (`Carried`, блок «Stage 5b») «stage 5b» заменить на «before the public launch, plan 57» и назвать по пунктам, что остаётся открытым, с номером отложенной задачи:
  - `People` остаётся в памяти процесса, перенос на `operator_sessions` отложен решением пользователя от 2026-11-01. Адресаты — только те, кто сделал запрос после старта процесса. Человек с битой строкой виден в `allTargets` (Task 9).
  - Окна `comeBack` и `Remember`: поздний запрос со старыми правами затирает новые. Память токена 30 с плюс ход запроса, миры `SessionMoves`, выборка, `MoveAddressed` (Task 8).
  - Срока жизни у человека нет, строка слушателя только потока отстаёт, `open_incident_guid` пишется как прислан (Task 10).
  - Обратная зависимость `deps.go:9`, клиента в ключе нет, ключ длиннее 200 символов или с NUL не отказывается, хотя контракт обещает `maxLength: 200` (Task 20).
  - Повторы живут в памяти процесса и пропадают при перезапуске, чистка `O(n)`, предела на пользователя нет, сбой между фиксацией и сохранением тестом не закреплён (Task 21, 22).
  - Дерево групп перечитывается только в своём процессе, два экземпляра не проверены: сервер работает в одном (Task 23–25).
- [ ] **Step 2: `40-plan.md`:** строка этапа 5 (около `:92`, найти `grep`, номер построчно не сверялся), статус и что осталось, отложенные задачи названы. `README.md`: строки 55, 56, 57 в таблице файлов. `python3 tools/check_links.py` чисто.
- [ ] **Step 3: дописать «Итог этапа 5б» в этот план:** таблица уровней с результатом, цифры, замер, `maxBulk`, таблица `mapping.md`, что `SKIP` и почему, отступления, решения по ходу, открытые вопросы с ответом или умолчанием, что осталось открытым (список Step 1). Отличия от прототипа списком: сортировка вариантов, неизвестный `mode` `400` против пустого `200`, не-guid в `explicit` `400` против выбрасывания, `candidateTransitionIds` не сужает `actions`, `sourceGroupGuid: "all"`, прототип не скрывает основного (решение 82).
- [ ] **Step 4: быстрые проверки IM** из `CLAUDE.md`, контракт на сервере равен IM побайтно: `cmp api/im/operator/openapi.v30.json …/Specification/Workflow_machine/openapi.v30.json`.
- [ ] **Step 5: коммиты.** Сервер: `Этап 5б: ADR — итог`. IM: `Этап 5б: итог`.
- [ ] **Step 6: ревью всей ветки от `e036f84`,** контроллер запускает. Находки закрываются отдельными коммитами, итог дополняется.

---

## Не в этом этапе

| Что | Куда | Почему |
|---|---|---|
| Task 8–10, Task 20–25 | до публичного запуска | решение пользователя от 2026-11-01, раздел в конце плана |
| M-3 девятая вкладка | этап 7 | нужен настоящий клиент |
| M-4 падение между транзакциями перемещений | этап 6 | лечит планировщик, записать в его требования |
| ключ `%T %v`, `close_linked` с `notifySiblings`, RULE-67, `linked_lost_access`, строка без двух попыток, `blockingIncidentGuid`, актор вытеснения, `addressedToMe` на группе, `incident.access_lost`, `incident.alert` | этапы 6–7 | таблица «6–7» ревью |
| объёмы, веер потоков, предел тела, тайм-ауты, `lock_timeout`, `MaxHeaderBytes`, плохое значение таймера, индекс `event_guid`, рост `stream_events`, `AccessMatrix` без клиента | до публичного запуска | решение пользователя |
| вход и токены, `Authorization` в `api.js` | по слову пользователя | решение пользователя |
| числа и сроки «Отложено до общего разбора» | общий разбор | кроме `maxBulk`, остаются значениями плана |
| экраны на настоящем API | этапы 8–9 | |
| шлюз на два экземпляра | до публичного запуска | стенду хватает прямых портов |

## Решения этого плана — обоснования

Обоснования решений 97, 99–102, 111–117 перенесены вместе с задачами в раздел «Отложено до публичного запуска».

- **94.** Контракт и в 5а правился один раз: так перенос проверяется целиком, а не по кускам. `maxBulk` вынесен, потому что зависит от замера.
- **95.** Контракт обещает `format: uuid`, значит клиент не может законно прислать другое. Отказ до ключа не тратит ключ на опечатку. `POST /merge` с не-guid остаётся `404`: это выбор этого плана, там другой смысл («нет такого»). Решение пользователя о `404` касается другого: объединения через маршрут одного инцидента (`routable`, `transition.go:200`).
- **96.** Текст с «—» читается как ошибка. Ключ только в Go вынес бы текст из машины, а сервер своих строк не держит.
- **98.** Человек без строки теряет состояние и настройки, а с `People` из таблицы (Task 9) исчезнет и из адресатов. NUL Postgres в тексте не хранит, поэтому чистить надо до записи.
- **103.** `left_group` помнит одного основного, а номера в журнале накапливаются. Чтение по номеру проще и не требует хранить связи, которых нет. Результат тот, что просил пользователь, и шире. Непарсимое скрывается: отказ здесь закрыт по умолчанию.
- **104.** `DELETE` начинал с основного, поэтому тот, кто его не видит, получал `404`, хотя `POST` проходил. Ответить основным нельзя, поэтому отвечаем тем, что он видит. Выдать сам факт нечего: человек и так видит привязанного, а знание guid основного нужно до запроса.
- **105.** Строками 5000 открытых в Go не считают. На классах варианты и каскад — чистые функции, их проверяют без базы. Отдельный запрос `FilterClasses` вместо расширения `QueueClasses`: очередь не должна платить за имена и устройства.
- **106.** Условие объединения зависит от класса, а выбор основного — от срочности и времени строки, поэтому основной читается, а условие считается. Подсчёт `+1` повторяет `e === p || ok`: основной входит в список, даже если сам к себе не присоединяется.
- **107.** Классы уже посчитаны, и повторять условия машины в SQL не нужно. Гонка принята как в очереди.
- **108.** `all_in_filter` — та же очередь без завершённых, поэтому берёт её код.
- **109.** Решение 73 оставило этот пункт на 5б. Один `ViewPage` закрывает равенство запросов.
- **110.** Тройка бюджетов как в 5а: заметно ниже секунды. Равенства важнее времени.
- **118.** Предел без цифры был бы угадыванием: ADR-005 честно говорит 90 мс на инцидент.

## Открытые вопросы (умолчания действуют, работу не останавливают)

Вопрос 1 ушёл вместе с Task 9, вопрос 5 снят: деления на части нет. Номера остальных не менялись.

| № | Вопрос | Умолчание |
|---|---|---|
| 2 | Чем отвечает `DELETE linked/{id}`, когда основной не виден | `200`, карточка отсоединённого инцидента |
| 3 | Номер бывшего основного: только `left_group.primaryId` или чтение по номеру | чтение по номеру: закрывает и его, и более ранних |
| 4 | Замер `maxBulk` не сошёлся | `null` остаётся, цифры пользователю |
| 6 | Версия соседа при ложной тревоге: прототип добавляет строку без версии, сервер поднимает версию | сервер не меняется, фраза контракта описывает RULE-138, разница в итоге |
| 7 | Сортировка вариантов без `localeCompare` | нижний регистр, затем id, разница в итоге |
| 8 | Файла `second-operator.pass` нет | уровень Г `SKIP`, файл создаёт только пользователь |
| 9 | `TestFilterManyDevicesBudget` не сошёлся | бюджет не меняется, цифра в итог, решение до публичного запуска |

## Отложено до публичного запуска

Решение пользователя от 2026-11-01. Task 8–10 и Task 20–25 в этап 5б не входят, при выполнении плана пропускаются. Текст задач, решений и обоснований ниже сохранён как был, поэтому в нём остались слова «5б», старые номера строк и ссылки вроде «Task 19». Основание по дереву групп — ADR-001.

| Задача | Что остаётся открытым, пока сервер один |
|---|---|
| Task 8 | Поздний запрос со старыми правами может затереть новые: память токена 30 с плюс ход запроса, миры `SessionMoves`, выборка, `MoveAddressed` (`session.go:190`). Следующий запрос того же человека пишет права заново. |
| Task 9 | Адресаты идут из памяти процесса: после перезапуска в списке только те, кто с тех пор сделал запрос. Человек с битой строкой виден в общем списке `allTargets`, форма передачи его не предлагает. |
| Task 10 | Срока жизни нет: уволенный остаётся в адресатах до перезапуска. Строка того, кто только слушает поток, отстаёт. `open_incident_guid` пишется как прислан, по решению 88 он ничего не открывает. |
| Task 20 | Обратная зависимость `deps.go:9`. Клиента в ключе нет: это безопасно, пока процесс обслуживает одного клиента (ADR-002, пункт 12). Ключ длиннее 200 символов, с NUL или битым UTF-8 не получает `400`, хотя контракт обещает `maxLength: 200`. |
| Task 21 | Повторы живут в памяти процесса: после перезапуска ключ забыт, защитой остаётся только `If-Match`. |
| Task 22 | Чистка памяти `O(n)` на запрос, предела на пользователя нет. Сбой между фиксацией и сохранением тестом не закреплён. |
| Task 23 | Дерево групп перечитывается только в своём процессе. Одному серверу этого хватает. |
| Task 24 | Память процесса не размечена аудитом, работа двух серверов на одной базе тестами не проверена. |
| Task 25 | Два экземпляра на стенде не проверены. Сервер запускается в одном. |

Как брать эти задачи:

- Сверить номера строк с кодом: `grep -n` по названным функциям. Сдвинутая строка не повод менять решение.
- Порядок прежний: Task 8, 9, 10, затем Task 20–25. Task 9 и Task 10 стоят на столбцах Task 8, Task 21–25 — на пакете Task 20, Task 24 проверяет и Task 8–9.
- Шаг стенда для миграции 022 стоял в Task 19 и там снят: применять её по правилу ниже, после Task 10. Миграция 023 применяется в Task 25.
- Правило миграций из Global Constraints: Новые миграции по порядку: `022_operator_identity.sql` (Task 8), `023_idempotency_keys.sql` (Task 21). `checkAppliedMigrations` сравнивает записи со списком по индексу, пропуск или перестановка роняет каждый `NewStore`. На стенде они применяются только в Task 19 и Task 25, только после дампа: `sg docker -c "docker exec \$(docker ps -qf name=ac_db) pg_dump -U im imdb" > ~/Work/stand/backup/imdb-before-022.sql`, затем `test -s` на файл.

### Решения этих задач

*Люди*

- **97.** Права монотонны. `model.User.CheckedAtMs int64` — время настоящего ответа облака, ставится внутри запомненного `authUser`, поэтому не молодеет от памяти токена. Столбец `operator_sessions.identity_ms BIGINT NOT NULL DEFAULT 0`. Запись только `WHERE operator_sessions.identity_ms <= EXCLUDED.identity_ms AND (поля различаются OR operator_sessions.seen_ms + $n <= EXCLUDED.seen_ms)`, где `$n` — `rememberEvery`: при одном `IS DISTINCT FROM` (`session_queries.go:104-105`) `seen_ms` не рос бы. Именно `<=`: фальшивый клиент тестов даёт 0, а строка `MoveAddressed` с той же меткой ничего не меняет. `INSERT` пишет обе метки: `DEFAULT 0` вывел бы новую строку за срок жизни. `SeenMs` ставит `SharedDirectory` по своим часам. `SessionOf` переносит `CheckedAtMs` в `IdentityMs`, `session.User()` — обратно. `comeBack` не пишет, если `row.IdentityMs > self.CheckedAtMs`. Это закрывает окна поздней записи: память токена 30 с плюс ход запроса, миры `SessionMoves`, выборку, `MoveAddressed`. Остаток: метка двигается только при записи, а `Remember` без изменений пропускает её до `rememberEvery`, поэтому двойное переключение прав в окне около 30 с остаётся. Остаток записывается в ADR и итог. `StreamWorld` и `WithoutRewrite` остаются: пачка потока не пишет ничего. Расхождение часов двух экземпляров даёт окно на секунды, вреда нет: следующий запрос записывает снова.
- **99.** Адресаты из таблицы. `Directory.People(ctx model.AppContext, customer uuid.UUID, asked []int64) ([]*model.OperatorSession, error)`. В `SharedDirectory` это `Store.OperatorPeople(ctx, customer, since, asked)`: один запрос `seen_ms >= $since OR user_id = ANY($asked)`, `ORDER BY user_id`. Снимок при первом чтении вместо `People` плюс `Sessions` делает этот один запрос. Второго запроса за спрошенными нет: он читал бы людей без строки и сдвинул точные счета (`require.Equal(21)` у `listLinked`, счёт чтений под блокировкой). `comeBack` идёт после этого чтения: иначе человек за `personKeepFor` считался бы без строки и по решению 98 перезаписывался на каждый запрос. `peopleSnapshot.People` после первого чтения ничего не читает. Узкий интерфейс `access.go:23` не меняется, а `load()` ошибки не возвращает, поэтому снимок держит ошибку первого чтения и отдаёт её на ближайшем чтении мира; пустой список при сбое ответом не считается. `rest.targets` (`world.go:231`) идёт через снимок, `allTargets` (`reference.go:80`) — через факт мира, функцией `transition.PeopleOf(w)`. `SeenDirectory.People` ставит то же состояние, что `Sessions`: `agentStateUnknown` (`directory.go:95`), а не пустое из `SessionOf`. Равенства решения 69 сохраняются. Ограничение решения 75 снято, тест на него заменяется.
- **100.** Срок жизни. `seen_ms BIGINT NOT NULL DEFAULT 0`, заполняется из `last_activity_ms` в той же миграции 022. `personKeepFor = 30 * 24 * time.Hour`: строки старше в `People` не попадают. Строки не удаляются: `Person` их находит, имена в журнале, состояние и настройки вернутся вместе с человеком. `Remember` обновляет `seen_ms` не чаще `rememberEvery = 10 * time.Minute` на человека, чтобы `GET` не писал на каждый запрос.
- **101.** Поток обновляет строку. После успешного `authenticate` раз в 60 с насос зовёт `Directory.Remember` со свежим пользователем: он свеж, как любой запрос, и монотонен по решению 97. Закрытая вкладка уходит под срок жизни (решение 100).
- **102.** `open_incident_guid`: `SessionHeartbeat` проверяет guid через `VisibleAmong`. Не виден или чужой — в строку пишется `NULL`, ответ всё равно `204`. Отличить чужой guid от несуществующего по ответу нельзя. Один запрос на heartbeat.

*Память повторов*

- **111.** Пакет переезжает в `internal/im/service/idempotency`, обратная зависимость `deps.go:9` уходит. `Key` получает `Customer uuid.UUID`. `MemoryStore` остаётся для тестов без базы. Ключ длиннее 200 символов (`utf8.RuneCountInString`), с NUL или битым UTF-8 — `400 BAD_REQUEST` в `once`, до `Do`.
- **112.** Таблица `idempotency_keys`: `customer_guid`, `user_id`, `key_hash BYTEA`, `state TEXT` (`running`, `done`), `owner UUID`, `lease_until_ms`, `status INT`, `headers JSONB`, `body BYTEA`, `expires_ms`, `created_ms`, ключ `(customer_guid, user_id, key_hash)`. Индексы `(expires_ms)`, `(customer_guid, user_id, created_ms)` и частичный `(lease_until_ms) WHERE state = 'running'`. `key_hash` — SHA-256 от метода, пути и значения через байт `0x00`: путь может нести `%00`, а значение длинное. Клиента и пользователя в хэше нет: они в первичном ключе.
- **113.** Захват одним оператором: `INSERT … ON CONFLICT DO UPDATE … WHERE (state = 'done' AND expires_ms <= $now) OR (state = 'running' AND lease_until_ms <= $now) RETURNING`. Живая строка `running` не забирается, даже если выполнение дольше срока ключа. У `running` в `expires_ms` стоит `now + TTL`, условия на него не смотрят; `Finish` пишет срок заново. Не `DO NOTHING`, как в наброске: тогда просроченную строку пришлось бы забирать вторым оператором, с окном гонки. Токен владельца ограждает `Finish` и продление (`WHERE owner = $token`). Лиза 30 с, продление каждые 10 с горутиной, которая кончается на возврате и на панике. Ожидающие опрашивают с отступом 50 мс → 1 с, смотрят на `ctx.Done()`, соединения не держат. Ответ `5xx` и паника удаляют строку, ожидающий захватывает сам: `ErrAborted` у `PostgresStore` не бывает, это отличие от памяти записывается. Часы — `Deps.Now`.
- **114.** Предел 1000 записей на пользователя: после захвата один `DELETE` готовых строк за новейшей тысячей, работа ограничена пределом, а не таблицей. Чистка просроченных раз в 60 с по индексам, тем же условием, что захват (решение 113), из цикла `Hub.trim`, чистить может любой экземпляр.
- **115.** Сбой между фиксацией и сохранением принят и закреплён `TestRepeatAfterLostAnswerDoesNotActTwice`: повтор получает `412` или отказ, второго действия нет. Исключение — `If-Match: *` на петле, оно записывается в ADR.

*Несколько экземпляров*

- **116.** Дерево. `SELECT pg_notify('im_tree', $1::text)` внутри `Store.Commit`. `Hub` слушает оба канала, `receive` различает их по `notification.Channel`. Сигнал, переподключение и `poll` раз в 5 с кладут отметку в канал на один элемент, а `HubConfig.TreeChanged func(ctx context.Context)` зовёт из него своя горутина, рядом с `listen`, `poll`, `trim`: циклы не держат друг друга (`hub.go:66`), а `receive` однопоточный, и перечитывание леса под общей блокировкой (`tree/index.go:52`, `LockCustomer` не смотрит на клиента) задержало бы запуск потоков. `SyncTree` сравнивает `TreeVersions` с `tree.Version(customer)` под `LockCustomer` и перечитывает отставшее. Версии — `uint64`, как `tree.Version` и `LoadAllTrees`. Членство в памяти не живёт (`appservice/sourcegroup/source_group_search.go:27` читает SQL), ему ничего не нужно.
- **117.** Два сервера в тестах: второй `appservice.GetServices` со своей шиной на той же тестовой базе. Аудит `grep -rn 'sync\.\(Mutex\|RWMutex\|Map\)' internal/im --include=*.go`: что остаётся на процесс — в ADR (память токена 30 с, память пользователя 5 мин, пределы потока на сервер, память `SharedDirectory` только как фильтр записи). На стенде — порты 5000 и 5001 напрямую с настоящим токеном, шлюз не меняется.

### Review Focus этих задач

1. Повтор запроса попадает на другой экземпляр или первый умер посередине: второго действия нет, ключ не висит вечно. `TestLeaseTakenOverAfterDeath`, `TestLongRunKeepsLease`, Task 21.
2. Ключ-мусор: NUL, `%00` в пути, длиннее 200, чужой клиент с тем же значением. Отказ `400` или свой ответ, не `500` и не чужое тело. `TestKeyWithNulIsRefused`, Task 20; `TestPathWithNulIsStored`, `TestSameKeyOtherCustomerNotShared`, Task 21.
3. Старые права приходят позже новых, с любого пути. `TestLateRequestDoesNotWriteBack`, `TestMoveAddressedKeepsNewRights`, Task 8.
4. Сигнал дерева потерян. `TestTreeCatchesUpAfterListenDrop`, Task 23.

### Файлы этих задач

| Файл | Отвечает за |
|---|---|
| `service/storing/migrations/022_operator_identity.sql` | `identity_ms`, `seen_ms` |
| `service/storing/migrations/023_idempotency_keys.sql` | таблица повторов |
| `service/storing/idempotency_queries.go` | операторы таблицы повторов |
| `service/idempotency/postgres.go` | `PostgresStore`, лиза, ожидание |
| `handler/test/two_servers_test.go` | второй сервер на той же базе |

### Открытый вопрос этих задач

| № | Вопрос | Умолчание |
|---|---|---|
| 1 | Срок жизни строки в адресатах | 30 дней (`personKeepFor`), одна константа |

### Обоснования этих решений

- **97.** Сравнивать права нечем: новые не лучше старых сами по себе. Сравнивать можно только время ответа облака. Метка делает неважным порядок поздних записей, поэтому закрывает и то, что нашли, и то, что не нашли; остаток назван в самом решении. Время берётся из ответа облака, а не из начала запроса: иначе память токена в 30 с делала бы старое новым.
- **99.** Снимок уже читает `Sessions`, и замена двух чтений одним не добавляет запросов. `ANY($asked)` делает ненужным второй запрос за теми, кто вышел за срок. Строка вместо пользователя нужна, чтобы тем же чтением получить состояние адресата.
- **100.** Уволенный оператор иначе вечно в адресатах: каталога пользователей до этапа 7 нет. Удалять строку нельзя: журнал читает имя, а вернувшийся человек потерял бы настройки. 30 дней — значение по умолчанию, см. открытые вопросы.
- **101.** Иначе тот, кто только слушает, стареет в таблице при открытой вкладке, а его права не обновляются. `I-1` запретил писать из пачки старое, а не свежее: `Remember` идёт с результатом только что сделанной проверки.
- **102.** Чужой guid в `open_incident_guid` при решении 88 ничего не открывает, но строка потом участвует в доставке. `204` на любой случай не даёт проверять чужие guid перебором.
- **111.** Пакет в `handler` при зависимости из `appservice` — обратное направление. С таблицей клиент обязан быть в ключе: номера пользователей могут совпасть при нескольких клиентах на сервер.
- **112.** Хэш, потому что `TEXT` не принимает NUL, а индекс не любит 200 символов на каждую строку.
- **113.** Один оператор исключает окно между проверкой и записью. Срок ключа действует только на готовые строки: иначе длинная выборка при `maxBulk: null` потеряла бы живую строку, и действие задвоилось бы. Токен нужен, потому что умерший по лизе может оказаться живым и медленным. Ожидание без соединения: иначе 50 ожидающих съедят пул.
- **114.** `O(n)` чистка на запрос из памяти нельзя перенести в таблицу. `DELETE` на пользователя ограничен пределом.
- **115.** Транзакция перехода и запись ответа — разные операции, совместить их значило бы тащить хранилище ключей в ядро ради редкого сбоя. `If-Match` уже защищает от второго действия, кроме петли.
- **116.** `NOTIFY` не гарантирован при обрыве, поэтому сверка. Сигнал только ускоряет. Отдельный слушатель не нужен: `Hub` уже держит соединение. Отдельная горутина нужна: перечитывание леса не должно задерживать уведомления потока.
- **117.** Два настоящих `GetServices` видят то, чего не увидит фальшивка: у каждого своя шина и своя память.

### Task 8: монотонные права и `MoveAddressed`

**Files:**
- Create: `service/storing/migrations/022_operator_identity.sql`
- Modify: `model/user.go`, `model/operator_session.go`, `internal/externalclient/cloud/client.go:50` (от корня репозитория, `authUser`), `service/storing/session_queries.go:104-105`, `appservice/operator/session.go:190,601-608`, `handler/test/fake_cloud_client.go`, ADR-005 (строка 222)
- Test: `handler/test/operator_session_test.go` (`TestMoveAddressedKeepsNewRights`, `TestLateRequestDoesNotWriteBack`, `TestRowNeverGoesBack`, `TestNewRowHasBothStamps`), `handler/test/migration_022_test.go` (`TestMigration022`)

**Interfaces:**
- Produces: `model.User.CheckedAtMs int64`, `model.OperatorSession.IdentityMs int64`, `SeenMs int64`. Столбцы `identity_ms`, `seen_ms`. `const rememberEvery = 10 * time.Minute`: `rememberOperatorSQL` получает его параметром, Task 10 учит ему память.

Шаблон: `TestMoveAddressedKeepsNewRights|TestLateRequestDoesNotWriteBack|TestRowNeverGoesBack|TestNewRowHasBothStamps|TestMigration022`.

- [ ] **Step 1: написать пробу `TestMoveAddressedKeepsNewRights` на текущем коде.** Обёртка над `Directory` в `engine(t, edit)`: после чтения `rows` в `MoveAddressed` другой запрос успевает записать новые права (`[assign.own]` вместо `[take.own, assign.own]`). Передача адресату вне сети. После неё в строке новые права.
- [ ] **Step 2: запустить пробу.** Ожидание: FAIL. Нашли чтением, поэтому сначала проба. Если PASS, записать в журнал «`MoveAddressed` не воспроизводится», тест оставить как защиту, дальше по плану: остальные окна решения 97 открыты и без него.
- [ ] **Step 3: написать падающие тесты.**
  - `TestLateRequestDoesNotWriteBack`: запрос A взял пользователя с меткой 100 и старыми правами, запрос B записал новые с меткой 200, A строит мир. В строке новые права.
  - `TestRowNeverGoesBack`: прямой `RememberOperator` с меткой 100 поверх 200 не меняет строку; с равной меткой и новым именем меняет; без различий, но с `seen_ms` старше `rememberEvery` двигает только метку времени.
  - `TestNewRowHasBothStamps`: первая запись человека. `identity_ms` и `seen_ms` не ноль.
  - `TestMigration022`: столбцы есть, `seen_ms` заполнен из `last_activity_ms`, `Down` работает, по образцу `migration_018_test.go`.
- [ ] **Step 4: запустить шаблон.** FAIL.
- [ ] **Step 5: реализовать по решению 97.** Метка ставится в `authUser` при настоящем обращении к облаку, память её не обновляет. `AuthenticateUser` копирует пользователя целиком, метка сохраняется. `fake_cloud_client` даёт растущий счётчик, если тест его задал, иначе 0. `rememberOperatorSQL` получает условие решения 97 с веткой `seen_ms`, `INSERT` пишет обе метки, обновление — `seen_ms = GREATEST(…)`. `SessionOf` и `session.User()` переносят метку, `SharedDirectory` ставит `SeenMs`.
- [ ] **Step 6: запустить шаблон, затем `-run 'TestStream|TestSession|TestFlow'`.** PASS. `TestStreamKeepsNewRights` не тронут и зелёный.
- [ ] **Step 7: ADR-005, строка 222.** Окно шире 30 с: память токена плюс ход запроса, закрыто меткой; записать и остаток из решения 97. Коммит: `Этап 5б: старые права не затирают новые — метка проверки в строке сессии`.

### Task 9: адресаты из таблицы

**Files:**
- Modify: `appservice/operator/directory.go:95`, `appservice/operator/session.go:414-658`, `appservice/operator/world.go:231-241`, `handler/operator/reference.go:80`, `service/transition/world.go`, `service/storing/session_queries.go`. `appservice/operator/access.go:23,168,204` не меняется: узкий интерфейс решения 99.
- Test: `handler/test/operator_session_test.go:211-212` (`TestSecondServerOffersPerson`, `TestPeopleOtherCustomer`, `TestPersonPastKeepFor`, `TestOldRowNotRewrittenEveryRequest`, `TestPeopleReadFailsTheRequest`), `operator_cost_test.go`, тесты с `SeenDirectory` (около 30 строк)

**Interfaces:**
- Consumes: `seen_ms` из Task 8.
- Produces: `Directory.People(ctx model.AppContext, customer uuid.UUID, asked []int64) ([]*model.OperatorSession, error)`; `Store.OperatorPeople(ctx model.AppContext, customer uuid.UUID, since int64, asked []int64) ([]*model.OperatorSession, error)`; `transition.PeopleOf(w World) ([]*model.OperatorSession, error)`; `const personKeepFor = 30 * 24 * time.Hour`.

Шаблон: `TestSecondServerOffersPerson|TestPeopleOtherCustomer|TestPersonPastKeepFor|TestOldRowNotRewrittenEveryRequest|TestPeopleReadFailsTheRequest|TestBrokenRowNotInPeople|TestListLinkedSQLCount|TestCardSQLCount|TestAccess|TestSummaries|TestLocked|TestFormTransfer`.

- [ ] **Step 1: написать падающие тесты.**
  - `TestSecondServerOffersPerson` заменяет ограничение решения 75 (`operator_session_test.go:211–212`): человек записан напрямую в таблицу, этот процесс его не видел; он есть среди адресатов.
  - `TestPeopleOtherCustomer`: человек другого клиента среди адресатов отсутствует.
  - `TestPersonPastKeepFor`: `seen_ms` старше 30 дней. В адресатах нет, `Person` находит, имя в журнале есть.
  - `TestOldRowNotRewrittenEveryRequest`: строка за `personKeepFor`, человек спрошен в мире, идут два запроса подряд. Лишней записи нет (`sqlCounter`).
  - `TestPeopleReadFailsTheRequest`: `OperatorPeople` падает. Запрос отвечает `500`, а не работает с пустым списком.
- [ ] **Step 2: запустить шаблон.** FAIL.
- [ ] **Step 3: реализовать по решению 99.** Сигнатура меняется, снимок делает один запрос, `comeBack` идёт после него. Ошибку снимок держит сам и отдаёт на ближайшем чтении мира: `load()` в `access.go` её не возвращает. `SeenDirectory` превращает пользователей в строки через `SessionOf` и ставит `agentStateUnknown`.
- [ ] **Step 4: запустить шаблон.** PASS, включая равенства решения 69 (1 и 10 людей), потолки и точный счёт `TestListLinkedSQLCount`.
- [ ] **Step 5: запустить `-run 'TestTargets|TestForm|TestSession|TestQueue|TestFlow'`.** PASS.
- [ ] **Step 6: коммит.** `Этап 5б: адресаты передачи из operator_sessions, строки старше 30 дней не предлагаются`.

### Task 10: срок жизни, слушатель потока, `open_incident_guid`

**Files:**
- Modify: `appservice/operator/session.go` (`unchanged`), `handler/operator/stream.go:465-472`, `handler/operator/session.go:245-268`
- Test: `handler/test/operator_session_test.go` (`TestRememberRefreshesSeen`, `TestRememberWritesRarely`, `TestHeartbeatKeepsOnlyVisibleIncident`), `operator_stream_test.go` (`TestStreamRefreshesRowOnReauth`, `TestStreamOnlyListenerStaysInPeople`)

**Interfaces:**
- Consumes: `Directory.Remember`, метка, ветка `seen_ms` в `rememberOperatorSQL` и `rememberEvery` из Task 8.

Шаблон: `TestRememberRefreshesSeen|TestRememberWritesRarely|TestStreamRefreshesRowOnReauth|TestStreamOnlyListenerStaysInPeople|TestHeartbeatKeepsOnlyVisibleIncident`.

- [ ] **Step 1: написать падающие тесты.**
  - `TestRememberRefreshesSeen`: без изменений прав, часы +11 минут. `seen_ms` обновлён.
  - `TestRememberWritesRarely`: 100 `GET` за минуту, одна запись (`sqlCounter`).
  - `TestStreamRefreshesRowOnReauth`: права в облаке поменялись, поток открыт, прошёл `Reauth`. В строке новые права, запросов от человека не было.
  - `TestStreamOnlyListenerStaysInPeople`: человек только слушает поток 31 день на `TestClock`. Он среди адресатов. Вкладка закрыта, ещё 31 день: нет.
  - `TestHeartbeatKeepsOnlyVisibleIncident`: виден — guid в строке; не виден, другой клиент, нет такого — `NULL`; во всех случаях `204`.
- [ ] **Step 2: запустить шаблон.** FAIL.
- [ ] **Step 3: реализовать по решениям 100–102.** `unchanged` смотрит и на время: прошло `rememberEvery` — запись идёт, хотя поля те же, условие SQL её пропустит. `Remember` в потоке — сбой только в журнал, поток живёт.
- [ ] **Step 4: запустить шаблон и `-run 'TestStream|TestSession'`.** PASS. Равенства потока не изменились: запись идёт раз в 60 с, не на пачку.
- [ ] **Step 5: коммит.** `Этап 5б: срок жизни строки, слушатель потока обновляет её сам, в heartbeat только видимый инцидент`.

### Task 20: перенос пакета и проверка ключа

Проверка ключа сделана в Task 6, Step 8, здесь от неё остаётся только перенос вместе с пакетом.

**Files:**
- Move: `handler/operator/idempotency/{store.go,memory.go,memory_test.go}` → `service/idempotency/`
- Modify: `appservice/operator/deps.go:9`, `appservice/appservice.go:368`, `handler/operator/reply.go:15,127-153`, `handler/test/operator_helpers_test.go:218,452`, `operator_wiring_test.go:145`, `operator_idempotency_test.go`
- Test: `handler/test/operator_idempotency_test.go` (`TestKeyTooLongIsRefused`, `TestKeyWithNulIsRefused`, `TestKeyExactly200Works`), `service/idempotency/memory_test.go` (`TestKeyHashSeparatesParts`, `TestStorable`)

**Interfaces:**
- Produces: `idempotency.Key{Customer uuid.UUID; UserID int64; Method, Path, Value string}`; `(k Key) Hash() [32]byte`; `const idempotency.MaxKeyLength = 200`; `idempotency.Storable(value string) bool`.

Шаблон: `TestIdempotent|TestKey|TestBulk|TestMerge`. Пакет без базы: `go test -race ./internal/im/service/idempotency/ -run 'TestKeyHash|TestStorable'`.

- [ ] **Step 1: перенести пакет,** поправить импорты, `Key.Customer` заполняется из `user.CustomerGUID`. Комментарий `once` «customers do not meet» заменить: клиент теперь часть ключа. Без базы: PASS.
- [ ] **Step 2: написать падающие тесты.**
  - `TestKeyHashSeparatesParts` (без базы): `("a", "bc")` и `("ab", "c")` дают разный хэш. `Customer` и `UserID` в хэш не входят, они в первичном ключе таблицы.
  - `TestStorable` (без базы): 200 символов кириллицей да; 201 нет; NUL нет; `"\xff"` нет; пусто да.
  - `TestKeyTooLongIsRefused`: `400 BAD_REQUEST`, действия нет, на всех трёх маршрутах.
  - `TestKeyWithNulIsRefused`: то же.
  - `TestKeyExactly200Works`.
- [ ] **Step 3: запустить.** FAIL.
- [ ] **Step 4: реализовать.** Проверка в `once`, первой: неверный ключ не доходит до `Do`. `428` стоит внутри `once`, в `run` (`transition.go:123-126`), поэтому плохой ключ без `If-Match` даёт `400`, вреда нет. Проверка не-guid из Task 6 в `ExecuteBulkTransition` и `readTransitionBody` не меняются.
- [ ] **Step 5: запустить шаблон и «без базы».** PASS. `grep -rn 'handler/operator/idempotency' internal` пусто.
- [ ] **Step 6: коммит.** `Этап 5б: пакет idempotency в service, клиент в ключе, плохой ключ — 400`.

### Task 21: таблица, захват, лиза

**Files:**
- Create: `service/storing/migrations/023_idempotency_keys.sql`, `service/storing/idempotency_queries.go`, `model/idempotency.go`, `service/idempotency/postgres.go`
- Create: `handler/test/idempotency_pg_test.go` (`TestPostgresStoreRunsOnce`, `TestLeaseTakenOverAfterDeath`, `TestLongRunKeepsLease`, `TestLongRunPastTTLNotStolen`, `TestOldOwnerCannotFinish`, `TestFailedRunLetsWaiterRun`, `TestPathWithNulIsStored`, `TestSameKeyOtherCustomerNotShared`, `TestSameKeyOtherUserNotShared`, `TestExpiredKeyRunsAgain`, `TestWaiterLeavesOnCancel`, `TestWaiterHoldsNoConnection`, `TestBodyRoundTrips`, `TestMigration023`)

**Interfaces:**
- Consumes: `Key.Hash`.
- Produces:
  - `model.IdempotencyRow{Customer uuid.UUID; UserID int64; KeyHash []byte; State string; Owner uuid.UUID; LeaseUntilMs, ExpiresMs, CreatedMs int64; Status int; Headers, Body []byte}`;
  - `idempotency.Table` со `ClaimKey(ctx model.AppContext, row model.IdempotencyRow, now int64) (*model.IdempotencyRow, bool, error)`, `ExtendKey(ctx, row model.IdempotencyRow) (bool, error)`, `FinishKey(ctx, row model.IdempotencyRow) (bool, error)`, `DropKey(ctx, row model.IdempotencyRow) error`, `ReadKey(ctx, row model.IdempotencyRow) (*model.IdempotencyRow, error)`, `TrimKeys(ctx, customer uuid.UUID, userID int64, keep int) error`, `SweepKeys(ctx model.AppContext, now int64) (int64, error)`;
  - `idempotency.PostgresConfig{TTL, Lease, Beat, PollMin, PollMax time.Duration; Keep int; Now func() int64; Context func(context.Context) model.AppContext}`, значения по умолчанию из решений 113, 114;
  - `idempotency.NewPostgresStore(t Table, cfg PostgresConfig, log logrus.FieldLogger) *PostgresStore`, реализует `Store`.

Шаблон: `TestPostgresStore|TestLease|TestLongRun|TestOldOwner|TestFailedRun|TestPathWithNul|TestSameKey|TestExpiredKey|TestWaiter|TestBody|TestMigration023`.

- [ ] **Step 1: написать падающие тесты.**
  - `TestPostgresStoreRunsOnce`: 20 горутин, один ключ. `run` один раз, все получили тот же ответ, 19 — `replayed`.
  - `TestLeaseTakenOverAfterDeath`: строка `running` с истёкшей лизой. Новый `Do` выполняет. Запоздавший `FinishKey` старого владельца не меняет строку.
  - `TestLongRunKeepsLease`: `Lease` 300 мс, `Beat` 100 мс, работа 1 с. Второй ждёт, `run` один раз.
  - `TestLongRunPastTTLNotStolen`: строка `running` с живой лизой и истёкшим `expires_ms`. Захват не проходит, `SweepKeys` её не трогает: выполнение дольше срока ключа не дублируется.
  - `TestOldOwnerCannotFinish`.
  - `TestFailedRunLetsWaiterRun`: ответ `500` и паника. Строки нет, ожидающий выполняет сам, горутина продления кончилась.
  - `TestPathWithNulIsStored`: путь с `\x00`, значение 200 символов. Запись и повтор работают.
  - `TestSameKeyOtherCustomerNotShared`, `TestSameKeyOtherUserNotShared`.
  - `TestExpiredKeyRunsAgain`.
  - `TestWaiterLeavesOnCancel`: отмена контекста. Возврат с ошибкой контекста, не позже 1 с.
  - `TestWaiterHoldsNoConnection`: 50 ожидающих, `ConnsInUse` не растёт.
  - `TestBodyRoundTrips`: тело и заголовки побайтно, `ETag` на месте.
  - `TestMigration023`: таблица, индексы, `Down`.
- [ ] **Step 2: запустить шаблон.** FAIL.
- [ ] **Step 3: реализовать по решениям 112, 113.** Условие захвата и `SweepKeys` одно: `(state = 'done' AND expires_ms <= $now) OR (state = 'running' AND lease_until_ms <= $now)`. Запись `Finish` и `Drop` — с `context.WithoutCancel`: клиент ушёл, а ответ всё равно нужен. Сбой `Finish` — в журнал, ответ возвращается: случай решения 115. Ошибка `ClaimKey` — `Do` возвращает ошибку, `once` отвечает `500`, действия нет.
- [ ] **Step 4: запустить шаблон с `-race` три раза подряд.** PASS: тесты времени не должны быть хрупкими.
- [ ] **Step 5: коммит.** `Этап 5б: память повторов в таблице — захват одним оператором, лиза, токен владельца`.

### Task 22: подключение, предел, чистка, потерянный ответ

**Files:**
- Modify: `appservice/appservice.go:368`, `service/stream/hub.go`, `service/idempotency/postgres.go`, `handler/test/operator_helpers_test.go:218`, `docs/adr/002-operator-api-package.md`
- Test: `handler/test/operator_idempotency_test.go` (весь файл таблично на двух хранилищах; `TestKeysCappedPerUser`, `TestSweepRemovesExpired`, `TestRepeatSurvivesRestart`, `TestRepeatAfterLostAnswerDoesNotActTwice`, `TestLoopWithStarActsAgain`)

**Interfaces:**
- Consumes: `NewPostgresStore`, `Table`.
- Produces: `HubConfig.Sweep func(ctx context.Context)`; `(s *PostgresStore) Sweep(ctx context.Context)`; тестовый `f.engineOnTable(t, edit)`: `engineLogging`, в котором вместо `MemoryStore` стоит `PostgresStore`.

Шаблон: `TestIdempotent|TestKeysCapped|TestSweep|TestRepeat|TestLoopWithStar|TestBulk|TestMerge`.

- [ ] **Step 1: написать падающие тесты.**
  - `TestKeysCappedPerUser`: 1005 ключей одного. 1000 новейших готовых, чужие не тронуты, `running` не тронут.
  - `TestSweepRemovesExpired`: просроченных `done` нет, свежие на месте, строка `running` с живой лизой на месте, даже с истёкшим `expires_ms`; `running` с истёкшей лизой удалена.
  - `TestRepeatSurvivesRestart`: новый `PostgresStore` на той же таблице отвечает из памяти.
  - `TestRepeatAfterLostAnswerDoesNotActTwice`: `Table` с падающим `FinishKey`. Клиент получил ответ, строка `running`. Лиза прошла. Повтор получает `412` или отказ, второй строки журнала нет.
  - `TestLoopWithStarActsAgain`: то же с `If-Match: *` на переходе-петле. Второе действие есть, тест назван и прокомментирован как принятое исключение.
- [ ] **Step 2: запустить.** FAIL.
- [ ] **Step 3: реализовать по решениям 114, 115.** `Deps.Idempotency` на сервере — `PostgresStore`, часы `now`, контекст через `model.NewContext`. `engineLogging` всегда ставит `MemoryStore` (`operator_helpers_test.go:218`), поэтому `f.engineOnTable` ставит таблицу, а тесты `operator_idempotency_test.go` идут таблично на обоих хранилищах. `brokenMemory` не меняется. `Sweep` вызывается в `Hub.trim`.
- [ ] **Step 4: запустить шаблон.** PASS: `operator_idempotency_test.go` целиком проходит на обоих хранилищах.
- [ ] **Step 5: ADR-002.** Что изменилось в решении 54: таблица, лиза, потерянный ответ, отличие `ErrAborted`. Коммит: `Этап 5б: сервер хранит повторы в таблице, предел на пользователя, чистка`.

### Task 23: дерево групп на всех экземплярах

**Files:**
- Modify: `service/storing/source_group_tree.go:61`, `service/sourcegroup/service.go`, `service/stream/hub.go:66,278-291`, `appservice/appservice.go`, `handler/test/common.go`
- Test: `service/stream/hub_test.go` (`TestHubTreeSignalCallsTreeChanged`, `TestHubStreamSignalDoesNotCallIt`, `TestHubReconnectCallsTreeChanged`, `TestHubPollCallsTreeChanged`, `TestHubTreeChangedDoesNotHoldReceive`)
- Create: `handler/test/two_servers_test.go` (`TestTreeReachesSecondServer`, `TestTreeCatchesUpAfterListenDrop`, `TestTreeNotifyRolledBack`, `TestTreeWritesOnTwoServers`)

**Interfaces:**
- Produces: `HubConfig.TreeChanged func(ctx context.Context)`; `(s *Service) SyncTree(ctx model.AppContext) error`; `Store.TreeVersions(ctx model.AppContext) (map[uuid.UUID]uint64, error)`; тестовый `f.secondServer(t)` в `handler/test/common.go`, решение 117, им пользуется и Task 24.

Шаблон: `TestTree`. Пакет без базы: `go test -race ./internal/im/service/stream/ -run 'TestHubTree|TestHubStreamSignal|TestHubReconnect|TestHubPoll'`.

- [ ] **Step 1: написать падающие тесты без базы** с фальшивым `listenConn`: `TestHubTreeSignalCallsTreeChanged`; `TestHubStreamSignalDoesNotCallIt`; `TestHubReconnectCallsTreeChanged`; `TestHubPollCallsTreeChanged`; `TestHubTreeChangedDoesNotHoldReceive`: `TreeChanged` висит, сигнал потока всё равно будит подписчика, пять сигналов дерева подряд дают один вызов после него.
- [ ] **Step 2: написать падающие тесты с базой.** Второй сервер строит помощник `f.secondServer(t)`, он создаётся здесь.
  - `TestTreeReachesSecondServer`: группа создана на первом, `Tree()` второго знает её за 1 с. Смотреть именно `Tree()`: `GET /sources/groups/tree` читает SQL (`GetGroupChildren`). Источник этой группы проходит видимость на втором.
  - `TestTreeCatchesUpAfterListenDrop`: у второго `Hub` закрыт `LISTEN`, сигнал потерян. За 6 с дерево новое.
  - `TestTreeNotifyRolledBack`: откат `Commit` не даёт сигнала.
  - `TestTreeWritesOnTwoServers`: два `Commit` подряд с разных серверов. Версия растёт, дерево цело, второй получает `ErrTreeVersionConflict` или проходит после перечитывания. Никогда `500` без причины.
- [ ] **Step 3: запустить.** FAIL.
- [ ] **Step 4: реализовать по решению 116.** `receive` сначала смотрит `notification.Channel`, потом разбирает клиента. Канал на один элемент, своя горутина рядом с `listen`, `poll`, `trim` (`hub.go:129`). Ошибка `SyncTree` — `Warn`, следующий круг повторит. `Hub` в `cmd/im/main.go` уже стартует, менять не надо.
- [ ] **Step 5: запустить шаблон и `-run 'TestSource|TestHub'`.** PASS.
- [ ] **Step 6: коммит.** `Этап 5б: дерево групп расходится по экземплярам сигналом и сверкой версий`.

### Task 24: два сервера в тестах и аудит процесса

**Files:**
- Modify: `handler/test/two_servers_test.go` (`TestTwoServersRepeatAcross`, `TestTwoServersRepeatWhileRunning`, `TestTwoServersStream`, `TestTwoServersPeople`, `TestTwoServersRightsOrder`, `TestTwoServersQueueAndFilter`)
- Modify: `docs/adr/002-operator-api-package.md`

**Interfaces:**
- Consumes: `f.secondServer(t)` из Task 23.

Шаблон: `TestTwoServers`.

- [ ] **Step 1: написать тесты.** Здесь ожидается `PASS` сразу на коде Task 20–23, поэтому падающий шаг заменён порчей.
  - `TestTwoServersRepeatAcross`: тот же ключ на втором сервере — ответ первого, побайтно.
  - `TestTwoServersRepeatWhileRunning`: первый выполняет, второй ждёт и получает тот же ответ.
  - `TestTwoServersStream`: действие на первом приходит потоку на втором.
  - `TestTwoServersPeople`: человек вошёл на первом, адресат на втором.
  - `TestTwoServersRightsOrder`: новые права на первом, старый запрос на втором, строка не откатилась.
  - `TestTwoServersQueueAndFilter`: очередь и фильтр сходятся на обоих.
- [ ] **Step 2: запустить шаблон.** PASS.
- [ ] **Step 3: проверить, что тесты видят поломку.** Временно вернуть `MemoryStore` на втором сервере: `TestTwoServersRepeatAcross` FAIL. Убрать `comeBack`-условие: `TestTwoServersRightsOrder` FAIL. Вернуть обе правки, `git status` чистый по коду.
- [ ] **Step 4: аудит.** Команда решения 117, каждая строка размечена: общая, на процесс и безвредно, на процесс и вредно. Вредное — исправить здесь с тестом или остановиться и записать в журнал.
- [ ] **Step 5: ADR-002.** Раздел «What stays per process», те же строки. Коммит: `Этап 5б: два сервера на одной базе — проверки и аудит памяти процесса`.

### Task 25: два экземпляра на стенде

**Files (вне git):**
- Create: `~/Work/stand/run-im-server-2.sh`, `~/Work/stand/check-two-instances.sh`
- Modify: `research/integration/30-local-stand.md`

**Interfaces:**
- Адреса: `http://127.0.0.1:5000/api/v1/im-backend` и `http://127.0.0.1:5001/api/v1/im-backend`, как `DIRECT` в `check-operator-stream.sh:9`. Вход идёт через `$CLOUD/api/v3/ac-backend/users/login` с `--cacert`, к портам `curl` без него.

- [ ] **Step 1: полный прогон перед стендом.** Пересоздать im-test-db, весь пакет, «без базы», `go vet`, `gofmt`, `golangci-lint`, `make test-local`. Чисто.
- [ ] **Step 2: дамп и запуск.** `imdb-before-023.sql`, `test -s`, затем `run-im-server.sh`, он сам собирает `bin/im`, миграция 023 применена. `run-im-server-2.sh` — копия без `go build`: первый скрипт пересобирает бинарь при каждом запуске, второй берёт готовый. После `source im-server.env` он делает `export IM_SERVER_PORT=5001` (`model/config.go:18`) и свой `IM_LOG_DIR`, значения `im-server.env` не читаются и не печатаются. Вывод — в `im-server-2.log`. Порядок запуска: сначала первый. Вторая сборка той же базы миграций не повторяет.
- [ ] **Step 3: написать `check-two-instances.sh`.** Настоящий токен, порты напрямую, шлюз не меняется. Каркас как у `check-operator-stream.sh`: `check`, `skip`, `finish`, строки `OK|FAIL|SKIP`, `итого ошибок: N`, код выхода — число `FAIL`. Оператор выходит на линию `PUT agent-state ready`.
  - Поток и инцидент: `curl -N` потока на 5001, `"$EMU" replay --limit 1 --run "stage5b-$(date +%s)"`. `incident.created` пришёл на 5001, guid берётся из кадра.
  - Повтор: `POST …/transitions/claim` на 5000 с `{"surface":"card","idempotencyKey":"<метка прогона>"}` и `If-Match`, тот же запрос на 5001. Код и тело совпадают (`cmp`), `ETag` тот же, в журнале инцидента одна строка взятия, в потоке одно `incident.transitioned`.
  - Дерево: `GET /sources/groups/tree` здесь не годится, он читает SQL (`GetGroupChildren`) и ответит верно без всякого сигнала. Проверка идёт через чтение, которое опирается на дерево в памяти: на 5000 `POST /sources/groups` создаёт группу внутри корневой группы источника, правило доступа группы 1 её накрывает, источник инцидента добавляется участником (`POST /sources/groups/{guid}/memberships`). На 5001 `GET /operator/incidents?sourceGroupGuid=<группа>&filter=all` за 6 с находит инцидент: неизвестную группу `sourcesUnder` считает источником, и строк не будет. Перед написанием прочитать, что `sourcesUnder` берёт потомков из `Deps.Tree`. Участие и группа удаляются в `trap`, что бы ни случилось; если источник лежит только в одной группе, он возвращается на место.
  - Инцидент закрывается переходом `close`, как в `check-operator-stream.sh`.
  - Смерть экземпляра посреди запроса и потерянный сигнал дерева на стенде не проверяются: задержать запрос нечем, а править строки `imdb` руками нельзя. Оба случая закрыты уровнем А, `check-two-instances.sh` пишет это строкой `SKIP`.
  - Адресат с другого экземпляра: `SKIP`, причина «на стенде один пользователь».
- [ ] **Step 4: запустить.** Строки `OK`, названные `SKIP`, `итого ошибок: 0`. Остановить второй экземпляр, стенд возвращается к одному.
- [ ] **Step 5: дописать «Шаг 9» в `30-local-stand.md`.** Коммит IM: `Этап 5б: стенд — два экземпляра`.
