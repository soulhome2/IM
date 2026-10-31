# Этап 5а: сессия оператора, очередь, поток — план работ

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Оператор работает через настоящие сессию, очередь и поток: у него хранимое состояние (готов, перерыв, вышел) с перерывом, выходом и молчанием, очередь со страницами, порядком, поиском и счётчиками, а действия других людей приходят ему сами, без перезагрузки. Два оператора под разными пользователями видят действия друг друга.

**Architecture:** Сначала снимается цена чтения: один запрос видимости на набор, одна матрица доступа на запрос, одно чтение семьи на вид. На этом стоят очередь и поток, поэтому порядок задач менять нельзя. Сессия и общая память о людях — таблица `operator_sessions`. Очередь считает видимость и порядок в SQL, а смысл фильтров берёт из машины: выражение считается один раз на класс строк. Лента — таблица `stream_events`, строки пишутся в транзакции ядра хуком `Op.InTx`, он же становится единственным местом разбора `Result.After`. `NOTIFY` только будит, правда всегда в таблице. На соединение приходится один курсор и никакой очереди в памяти.

**Tech Stack:** Go 1.27.1, gin v1.11.0, oapi-codegen (пакет `operatorgen`), `mgutz/dat`, cel-go, PostgreSQL 9.6, pgx v5.7.6 (`pgx.Connect`, `WaitForNotification`, `ConnConfig.Tracer`; уже прямая зависимость), testify `require`, kin-openapi v0.133.0 (только тесты), golangci-lint v2.14.0.

**Spec:** [40-plan.md](40-plan.md), этап 5; ADR-005 сервера (`docs/adr/005-transitions-in-transaction.md`, «Carried to stages 5-7», строки 106–125), ADR-002 (`docs/adr/002-operator-api-package.md`, решения 10, 12–14), ADR-001 (дерево групп); [55-plan-stage4c.md](55-plan-stage4c.md), решения 45–65 и итог; контракт `Specification/Workflow_machine/openapi.json` (`listIncidents`, `getQueueCounters`, `setAgentState`, `sessionHeartbeat`, `updatePreferences`, `openEventStream`, `IncidentStreamEvent`); правила §5, §7, §9, §11, §12, §14.10; `prototype/server.js` как образец поведения.

---

## Размер и разбиение

В `40-plan.md` этап 5 оценён как M. Это занижено: честная оценка L, примерно 36 задач. Одним планом такое не провести, поэтому этап делится.

| Часть | Что входит | Размер |
|---|---|---|
| **5а** (этот план) | цена чтения, правка контракта, сессия и общая память о людях, очередь и счётчики, лента, поток, критерий готовности | 27 задач, 30–35 коммитов, объём сравним с 4в |
| **5б** (набросок в конце) | `filterIncidents`, `resolveSelection`, идемпотентность в PostgreSQL, перенос пакета `idempotency`, дерево групп на нескольких экземплярах, проверка двух экземпляров на стенде | около 10 задач, свой план после итога 5а |

Граница такая: 5а доводит до критерия готовности, 5б ничего для него не добавляет. Фильтры панели и выборка нужны экрану оператора, а экраны — этапы 8–9. Идемпотентность в памяти работает на одном экземпляре, а стенд один. Два экземпляра в 5а проверяются только на уровне ленты и `Hub`.

## Критерий готовности: как его можно выполнить

В `40-plan.md`: «Два окна браузера под разными пользователями видят действия друг друга без перезагрузки». Буквально, в интерфейсе оператора, в этом этапе он не выполним, и причина не в сервере.

| Препятствие | Где | Кто снимает |
|---|---|---|
| `api.js` не шлёт `Authorization`, поток открыт через `EventSource`, а он заголовок не умеет | `prototype/api.js`, `subscribe` | вход и токены отложены до слова пользователя |
| `?api=` на другой адрес требует CORS | `cmd/im/main.go:84–97` | этап 7 |
| экраны оператора на настоящем API | — | этапы 8–9 |
| второй пользователь на стенде | файла `~/Work/stand/second-operator.pass` сейчас нет | пользователь |

Поэтому критерий проверяется по уровням, как в 4в.

| Уровень | Что доказывает | Где | От чего зависит |
|---|---|---|---|
| **А** | два `operatorClient` разных пользователей, настоящий сокет, настоящая лента в im-test-db: действие одного приходит другому без запроса; перерыв, передача, доступ, повтор по `Last-Event-ID` | `TestTwoOperatorsSeeEachOther` и соседи, Task 25 | ни от чего |
| **Б** | каждое сообщение потока сверено со схемой `IncidentStreamEvent` и форматом SSE контракта | `checkStream`, Task 25 | ни от чего |
| **В** | настоящие токены, настоящий шлюз без буферизации, две `curl -N`, повтор и сброс | `~/Work/stand/check-operator-stream.sh`, Task 26 | без файла пароля две сессии одного `test@axxonnet.test`; строка «разные пользователи» даёт `SKIP` с причиной |
| **Г** | два контекста настоящего браузера на странице стенда `~/Work/stand/two-windows.html` (`fetch` с `Authorization`, вне репозиториев) | `ui-check/check-two-windows.mjs`, Task 26 | только с файлом пароля, иначе `SKIP` |

Что честно будет сказано в итоге: без файла разные пользователи подтверждены только на уровнях А и Б, а через шлюз проходит один пользователь. Пароль нигде не искать, в отчётах и логах не печатать. Если `user@gmail.com` не может войти или у него нет `incident:accept` и правила доступа, это `SKIP`, обхода нет. Буквальные два окна с интерфейсом оператора станут возможны, когда пользователь скажет снять запрет на вход.

## Global Constraints

- Сервер: `~/Work/incident-manager-server`, ветка `feature/im_operator`, план сверен с коммитом `3c39868`. IM: `/mnt/hgfs/VmWareShared/soul2home/IM`, ветка `feature/im_operator`, коммит `6c7fa0b`. Конфигуратор не меняем.
- Только локально. Каждая задача — коммит. `git push` никогда, только по просьбе.
- `~/Work/axxoncloudgo` не менять. В `ac_db` ничего не пишем. Вход и токены в `prototype/api.js` отложены.
- Тесты только на im-test-db: `postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable`, контейнер `sg docker -c "make test-db-up"`. База стенда `imdb` в тестах запрещена.
- Новые миграции идут за `018_incident_machine.sql`: `019_operator_sessions.sql`, `020_stream_events.sql`, `021_queue_index.sql`. На стенде они применяются только в Task 26 и только после дампа: `sg docker -c "docker exec \$(docker ps -qf name=ac_db) pg_dump -U im imdb" > ~/Work/stand/backup/imdb-before-019.sql`.
- Команды Go начинаются с `source ~/go/offline-env.sh &&` в той же строке. Новых зависимостей нет, `go.mod` не меняется. Нельзя добавлять `gorillamux` и `golang.org/x/text`.
- **Без базы:** `source ~/go/offline-env.sh && go test -race $(go list ./internal/im/... | grep -v /handler/test)`.
- **С базой:** `source ~/go/offline-env.sh && TESTDB='postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable' && IM_TEST_DB_URL=$TESTDB go test -race ./internal/im/handler/test/ -run '<шаблон>'`. Весь пакет идёт около 13 минут и требует `-timeout 40m`, поэтому в задачах запускается только свой шаблон.
- **Замеры:** та же команда без `-race` и с `IM_MEASURE=1`. Без этой переменной тесты бюджетов пропускаются (`t.Skip`), потому что время на общей машине не повод ронять сборку. Счётчики запросов идут всегда.
- `make gen` и `gen-api-im` не запускать. `make gen-api-operator` и `make vendor-operator-contract` — только в Task 9.
- `golangci-lint run ./...` — 0 замечаний (`funlen` 120 строк и 60 операторов, `dupl` 150), `gofmt -l internal/im` пусто. testify в `-race` как принято.
- Комментарии и ADR — английский. Документы IM и коммиты — русский, простыми словами.
- Временные файлы — в scratchpad (`$S`).
- Коммиты сервера: одна задача — один коммит, сообщение через файл `.git/COMMIT_MSG_STAGE5A`, начинается с `Этап 5а: `, последняя строка `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`, `git commit -q -F`. Коммиты IM: файл `.superpowers/sdd/56-plan-stage5/commit-msg.txt`. Журнал работы: `.superpowers/sdd/56-plan-stage5/progress.md`.
- В IM действуют правила `CLAUDE.md`: `openapi.json` в CRLF, собранные файлы руками не править, новый функционал — вместе с шагом `prototype/selftest.js`, прототип не держит логики правил.
- Правило меняется в машине IM с векторами. В этом плане правила и машина не меняются.

**Решения пользователя (обязательны, не пересматривать):** `404` раньше `If-Match`. Операторский API применяет правила доступа, `manage` видит всё только на старых маршрутах. Коды вне контракта решаются правкой контракта IM, один раз на план, перенос на сервер отдельным шагом. Адресаты передачи — из памяти процесса до этапа 7. Вход отложен. Первая задача — цена чтения.

**Решения прошлых планов, на которые опирается этот:** 45–48, 52, 54, 56, 57, 59–61, 63, 65 из плана 55. Решения 66–93 — новые, обоснования в конце.

**Решения этого плана (обязательны для задач):**

*Цена чтения*

- **66.** `VisibleAmong(ctx, user, guids) (map[uuid.UUID]bool, error)` в `appservice/incident`: один SQL и один `ClosurePairs` на вызов, клиент сравнивается в SQL (`i.customer_guid = $1`), `HasAnyMachinePermission` — первым, как в `Visible` (`appservice/incident/incident.go:90–106`). Кусок условия `accessRuleMatch` один на всех: на него же садятся матрица доступа (67), очередь (Task 17) и поток (Task 24). `Deps.Visible` остаётся тонкой обёрткой над `VisibleAmong`, потому что на него опираются тесты и `params.go:34,52`.
- **67.** Доступ других людей считается одной матрицей на запрос: `AccessMatrix(ctx, customer, people, keys, ancestors, descendants)` возвращает пары «человек — (источник, тип источника, тип события)» одним SQL. `AccessMemo` живёт один запрос, общий для `serverWorld` и `rest.otherPerson`. Наполняется лениво при первом вопросе о доступе: люди — все из `Directory.People`, ключи — все тройки семьи или страницы. Ключ вне набора — ещё один такой же запрос на этот ключ. Запись о клиенте в ключе памяти остаётся: человек и ключ сравниваются внутри клиента `Op.Customer`.
- **68.** Одно чтение семьи на вид: `Core.View` и `Core.ViewPage`, у вида методы `Actions`, `Present`, `Form`, `CanEditScenario`. Старые `Core.Actions`, `Core.Present`, `Core.Form`, `Core.CanEditScenario` остаются обёртками, тесты ядра не переписываются. Кандидаты запоминаются в `refSource` по `(fact, args)`. Это безопасно и в пути чтения, и внутри попытки: `Repo.Write` — последний шаг попытки, а поверх памяти черновик объединяется как раньше.
- **69.** Бюджеты. Время (только при `IM_MEASURE=1`, на дереве около 8000 пар замыкания, цель — заметно меньше секунды):

| Что | Было (ADR-005) | Бюджет |
|---|---|---|
| `GET` карточки, 200 привязанных | 3,17 с | ≤ 300 мс |
| `GET linked?pageSize=200`, 200 привязанных | 4,38 с | ≤ 500 мс |
| основной в работе, 50 привязанных, 10 людей | 9,72 с | ≤ 400 мс |
| страница очереди, 25 строк, 10 людей | — | ≤ 300 мс |
| `getQueueCounters`, 5000 открытых и 20000 закрытых | — | ≤ 200 мс |
| удержание `FOR UPDATE`: основной, 50 привязанных, 10 людей | не мерили | ≤ 200 мс |

Запросы (идут всегда, считает драйвер, обойти нельзя). Главное требование — равенство, а не потолок: число запросов не зависит от числа привязанных и людей.

| Что | Равенство | Потолок |
|---|---|---|
| карточка | 1 и 200 привязанных; 1 и 10 людей | 30 |
| `listLinked` | 1 и 200 привязанных | 20 |
| страница очереди | 8 и 25 строк; 1 и 10 людей | 25 |
| чтения под блокировкой (`SELECT`) | 1 и 10 людей; 1 и 50 привязанных | 30 |

- **70.** Под блокировкой работает та же память: мир один на запрос и переживает повторы попытки. Ответы доступа не зависят от записей ядра. Кандидаты памяти живут одну попытку, потому что `refSource` создаётся на операцию.
- **71.** `ListLinked` строит страницу из уже прочитанных строк и `LoadMany` (Task 16 расширяет то, что вводит Task 5). Строка, удалённая между чтениями, пропускается, а не даёт 500. `total` остаётся как посчитан: страница может быть на строку короче, и это честнее ошибки.
- **72.** Гонка отсоединения: `Op.LinkedTo string`, проверка под блокировкой в `operation.lock`. Ожидался другой основной — `ErrNotLinkedHere`. HTTP как в решении 16 итога 4в: один инцидент — `404`, все — `412` с текущим основным.

*Контракт*

- **73.** Строки очереди не строят варианты людей: у действия в строке есть `fieldOptions` справочных полей (`resultId`, `causeId`, `reasonId`), `fieldRules`, `formNote`, но нет `fieldOptions.targetId` и его значения по умолчанию. Клиент при открытии формы из строки читает карточку и берёт варианты из неё. Условие `hasTransferTarget` на строке считается как раньше, оно без SQL благодаря 67. Флаг — `ViewOp.RowForm bool`, а не `Surface == "queue"`, потому что выборка 5б тоже идёт с этой поверхности и варианты людей ей нужны.
- **74.** Один коммит контракта (Task 9): `fieldOptions` в строке; `listLinked.pageSize` по умолчанию 8 и `getJournal.pageSize` без значения по умолчанию, «без размера — весь журнал», как код (ADR-002, пункт 13); `idempotencyKey` с `maxLength: 200` во всех трёх схемах (сервер начнёт отказывать в 5б, клиент таких ключей не шлёт); в `openEventStream` — кадр из одного `id` и закрытие медленного соединения; в `IncidentSummary.linkedTo` — невидимый основной. Новых кодов нет: `400` у `listIncidents`, `updatePreferences`, `sessionHeartbeat` уже покрыт общим правилом `serverStatuses` (`operator_contract_test.go:40`).

*Сессия*

- **75.** Память о людях становится общей: таблица `operator_sessions`, `Directory.Person` читает её. `Directory.People` по решению пользователя остаётся из памяти процесса: это адресаты передачи до этапа 7, и второй экземпляр не предложит человека, которого сам не видел (открытый вопрос 2). Интерфейс `Directory` получает `ctx`. `Remember` пишет только при изменении: сравнение с прошлой записью в памяти процесса, чтобы `GET` не давал `INSERT` на каждый запрос.
- **76.** Начальное состояние — `offline`, как `initial` машины и §12.1 («с этого состояния оператор начинает»). Первая запись `operator_sessions` создаётся с ним, повторный вход состояние не трогает. Оператор выходит на линию `PUT agent-state ready`. Тестовый помощник `f.operator` ставит `ready` прямо в таблицу, скрипты стенда делают `PUT`. Это меняет поведение 4в (там были `ready` все), см. открытый вопрос 1.
- **77.** Активность — любой не-`GET` под `/operator/*` после `Authenticate`, включая отказанный (§12.3). Поток активностью не считается: это `GET`. Запрос без пользователя не считается. Запись: `UPDATE … SET last_activity_ms = GREATEST(last_activity_ms, $now)`. Ошибка записи только в журнал, запрос идёт дальше. Время только серверное (`Deps.Now`), клиент времени не присылает. `idleSec = max(0, floor((now − last_activity_ms) / 1000))`. Новая запись сессии получает `last_activity_ms = now`.
- **78.** Потерянный heartbeat ничего не меняет: правила не меняют состояние оператора по молчанию (§12.3), `idleSec` только растёт, действует планировщик этапа 6. `available` у адресата считается по состоянию, а не по молчанию.
- **79.** `setAgentState` — порядок `server.js:1425–1463`: то же состояние — `200` без события; нет перехода — `409 TRANSITION_NOT_ALLOWED_FROM_STATE`; нет права — `403 PERMISSION_DENIED`; нет причины — `422 FORM_FIELD_REQUIRED`. Смена условная: `UPDATE … WHERE agent_state = $from`. Ноль строк — перечитать и повторить проверку один раз. Состояние пишется первым, потому что условия системных переходов его читают. Затем системные переходы, затем событие `session.agent_state_changed`. Хранится `ready`, `busy` только показывается: `derived.expr` машины считается на чтении.
- **80.** Системные переходы перерыва и выхода — не планировщик этапа 6, а `SessionMoves`: кандидаты — инциденты, где человек владелец или адресат, каждый `Core.Run` в своей транзакции, переходы с условием `agentStateIs(to)` в порядке машины (`system_hold_break`, `owner_signed_out`, `addressee_signed_out_to_group`, `addressee_signed_out_to_queue`). Отказ значит «не подошёл» и не ошибка. Сбой на одном инциденте в журнал, остальные идут дальше, ответ `200`, состояние уже сменилось. Доделает планировщик этапа 6.
- **81.** Настройки: `preferences || $patch` (верхний уровень, как `Object.assign`). `locale` из настроек — язык ответа: `viewerOf` читает его из снимка сессии, неизвестный язык — `ru`. `newProblem` получает язык параметром. Отказ до `viewer` (401) остаётся на `catalog.DefaultLocale`.

*Очередь*

- **82.** Невидимый основной: по умолчанию `linkedTo: null` в сводке, `primaryNumber: "—"` в пояснении карточки и в строках журнала с текущим основным. Номер тревоги остаётся (§5: «Номер тревоги — поле самого инцидента, он виден всегда»). Флаг — `ViewOp.HidePrimary`, считается одним `VisibleAmong` вместе с загрузкой. Давние основные в журнале не скрываются: связь с ними уже не хранится. Открытый вопрос 3.
- **83.** Фильтры — через классы: `SELECT state, owner, assignment_group, count(*) … GROUP BY 1,2,3` по видимым строкам, выражение `queueFilters[*].expr` считается один раз на класс на представителе. Счётчики — суммы, список — SQL по классам, прошедшим фильтр. Смысл остаётся в машине, правило дублировать негде. Тест `TestQueueClassesMatchRowCEL` сверяет с честным подсчётом по строкам на всех состояниях и всех `ownership`. Строки категории `linked` ни в один фильтр не попадают сами собой, потому что выражения их не пропускают.
- **84.** Порядок: перевод четырёх `queueSort.options` в SQL в одной таблице `queueOrderSQL`, при равенстве всегда `i.number`. Тест `TestQueueOrderMatchesMachineKeys` сверяет SQL с ключами CEL. Вариант машины без перевода — ошибка на старте. `operatorMayChange: false` — значит `sort` и настройка не действуют, порядок по умолчанию (`sortOf`, `server.js:1005`).
- **85.** Страницы: смещение, размер по контракту 25, больше 200 — урезается до 200, страница за концом — последняя (`server.js:1056–1067`). Счётчик и страница — два запроса. Строка может уехать между страницами, это принято: клиент перечитывает по потоку. `focusPage` — через `row_number()` по тому же порядку, только когда `focusGuid` дан. `filter` не указан — `open` по контракту, неизвестный — как прототип (только «проходит хоть один фильтр»). Поиск: номер, номер тревоги, название типа события, `lower(…) LIKE`, спецсимволы экранируются. Площадки и места у сервера пока нет. Найденные через привязанных — только видимые (§5).

*Поток*

- **86.** Лента — таблица, и пишется в той же транзакции, что и переход: `Op.InTx func(ctx model.AppContext, r *Result) error` вызывается в `Core.attempt` после `o.run()` внутри `DoInTx`, только при успехе без отказа. Откат попытки откатывает и строки ленты. Это единственное место разбора `Result.After`: три записи в журнал (`transition.go:162`, `linked.go:166`, `merge.go:167`) уходят.
- **87.** Порядок ленты равен порядку фиксаций: `pg_advisory_xact_lock(2085, hashtext($customer))` прямо перед `INSERT`, это последний оператор транзакции. Без него строка с меньшим `id` может стать видна позже, и курсор её потеряет. Взаимной блокировки нет: после этого замка транзакция ничего не ждёт, кроме своей фиксации. Интейк идёт в транзакции вызывающего, поэтому пишет ленту последним шагом `create`.
- **88.** В строке ленты только нейтральные данные: типы, id, `payload` с `state`, `owner`, `transitionId`. `incident`, имя `actor` и `addressedToMe` собираются при доставке глазами получателя. История остаётся в `payload`, а сводка всегда текущая. Повторная доставка тем самым не показывает устаревшего и не раскрывает то, что получатель уже не вправе видеть.
- **89.** Аудитории: `visible` (все, кто видит инцидент), `people` (список), `all`. Все, кроме `all` и `session.agent_state_changed`, проверяют видимость при доставке. Изменение прав вступает в силу на следующей пачке или при переобновлении пользователя раз в 60 с.
- **90.** `Hub` один на процесс: отдельное соединение pgx `LISTEN im_stream`, не из пула. Обрыв — повтор через 1→30 с и после восстановления будит всех. Страховка — опрос `max(id)` каждые 5 с. `NOTIFY` только будит. Подписчик — канал ёмкостью 1, пробуждения склеиваются. Обрезка ленты каждые 60 с: держим и не меньше 1000 строк, и не меньше часа (контракт: 500 и 10 минут). Обрезать может любой экземпляр.
- **91.** У соединения нет очереди, только курсор: пачка до 100 строк читается, когда прошлая записана. Память не зависит от скорости клиента. Запись с дедлайном 10 с на кадр. Дедлайн вышел — соединение закрыто, клиент вернётся с `Last-Event-ID`. Комментарий-пустышка каждые 15 с. Семафор на 8 сборок пачки, чтобы поток не съел пул из 16 соединений. Не больше 8 соединений на пользователя, лишнее закрывает самое старое. Переобновление пользователя раз в 60 с через `AuthenticateUser`: просроченный токен закрывает поток.
- **92.** Дедлайн записи не дотягивается через обычный `ResponseWriter`: `ResponseWriterDecorator` из go-util (`http_util.go:15`) не имеет `Unwrap`, поэтому `http.NewResponseController(c.Writer).SetWriteDeadline` вернёт `ErrNotSupported`. Самая внешняя обёртка в `handler.GetHandler` кладёт настоящий writer в контекст запроса, поток берёт его оттуда. Менять go-util нельзя. Ограничения времени записи на сервере не вводить (`WriteTimeout` убил бы поток).
- **93.** `Last-Event-ID`: нет заголовка — с текущего конца. Есть, и строка с таким `id` у клиента есть — со следующей. Не число, обрезано или больше конца — первое сообщение `stream.reset` с `id` последнего на сервере, поток идёт от него. Строки, которые получателю не положены, не отправляются, но если такой строкой заканчивается пачка, идёт кадр из одного `id: n`, без данных. Браузер запоминает `id`, события не создаёт, поэтому `Last-Event-ID` не отстаёт и невидимые строки не дают сброса.

## Review Focus

1. **Медленный клиент и память.** Читатель, который не читает, не растит память сервера и не держит соединение БД, а его соединение закрывается по дедлайну; вернувшись с `Last-Event-ID`, он получает всё пропущенное. Тест `TestSlowClientClosedNotBuffered`, Task 23.
2. **Потеря истории и порядок.** Обрезанный, неизвестный и нечисловой `Last-Event-ID` дают ровно один `stream.reset`, а не тихий пропуск; две параллельные фиксации не дают курсору перескочить строку. Тесты `TestStreamResetWhenHistoryTrimmed`, Task 24, и `TestFeedOrderIsCommitOrder`, Task 20.
3. **События о недоступном.** Получатель без доступа не видит ни `incident`, ни `incidentGuid`, ни номера соседа, ни имени инцидента в `payload`; потерявший доступ между записью и доставкой тоже; `Last-Event-ID` при этом не отстаёт. Тест `TestStreamHidesInvisibleIncident`, Task 24.
4. **Потерянный `NOTIFY` и два экземпляра.** Оборванный `LISTEN` не теряет событий: их находит страховочный опрос и пробуждение после восстановления; строка, записанная одним `Hub`, доходит подписчику другого. Тесты `TestHubCatchesUpAfterListenDrop`, `TestTwoHubsSeeOneFeed`, Task 22.
5. **Очередь и сессия не лгут со временем.** Страницы при движении строк не дублируют строку на одной странице и не падают, страница за концом — последняя; пропавший heartbeat не меняет состояние, а `idleSec` считается только по часам сервера, даже если часы идут назад. Тесты `TestQueuePageWhileRowsMove`, Task 18, и `TestStateStaysAfterHeartbeatLost`, `TestIdleIsOnServerClock`, Task 11.

## Что входит

| Операция или пункт | Задача |
|---|---|
| первая задача ADR-005: `VisibleAmong`, память доступа, одно чтение семьи, `ListLinked`, бюджеты, тест на число запросов | 1–5 |
| те же проверки под `FOR UPDATE` | 6 |
| гонка отсоединения | 7 |
| `ActorName`, порядок `maxBulk` у слияния, `test-local`, ключи `StringsRU` | 8 |
| правка контракта, перенос на сервер | 9 |
| общая память `Directory`, `agentState`, `lastTransferTarget` | 10, 12, 20 |
| `sessionHeartbeat`, настоящий `idleSec` | 11 |
| `getOperatorSession`, `setAgentState`, настоящий `countMine` в ответе | 12, 13 |
| `updatePreferences`, язык ответа, `DefaultLocale` | 14 |
| невидимый основной | 15 |
| `getQueueCounters` | 17 |
| `listIncidents` | 16, 18, 19 |
| лента, `Result.After` в одном месте, уведомления, вытеснение | 20, 21 |
| `touch` как `journal.appended`, `incident.updated` после объединения | 21 |
| `openEventStream`, `Last-Event-ID`, `stream.reset` | 23, 24 |
| несколько экземпляров: лента и `Hub` | 22 |
| критерий готовности, уровни А–Г | 25, 26 |
| ADR, документы, итог | 27 |

## Структура файлов

| Файл (сервер) | Что |
|---|---|
| `internal/im/service/storing/common.go` | `NewStoreTraced` |
| `internal/im/service/storing/access_queries.go` (новый) | `accessRuleMatch`, `VisibleIncidentIDs`, `AccessMatrix` |
| `internal/im/service/storing/session_queries.go` (новый) | чтение и запись `operator_sessions` |
| `internal/im/service/storing/queue_queries.go` (новый) | классы, страница, поиск, порядок |
| `internal/im/service/storing/stream_queries.go` (новый) | вставка, чтение, обрезка ленты |
| `internal/im/service/storing/migrations/019…021` | таблицы и индекс |
| `internal/im/service/transition/view.go`, `view_card.go`, `view_form.go`, `refs.go`, `world.go`, `run.go`, `family.go`, `core.go` | вид, память, хук, `Op.LinkedTo` |
| `internal/im/service/stream/` (новый) | `Row`, `Feed`, `Hub`, обрезка |
| `internal/im/appservice/incident/incident.go` | `VisibleAmong` |
| `internal/im/appservice/operator/load.go`, `world.go`, `directory.go`, `deps.go` | `LoadMany`, память, общая `Directory` |
| `internal/im/appservice/operator/access.go` (новый) | `AccessMemo` |
| `internal/im/appservice/operator/session.go` (новый) | `Sessions`, смена состояния, `SessionMoves` |
| `internal/im/appservice/operator/queue.go` (новый) | классы и фильтры машины, порядок |
| `internal/im/appservice/operator/feed.go` (новый) | сборка строк ленты из `Result`, хук `InTx` |
| `internal/im/handler/operator/queue.go` (новый) | `ListIncidents`, `GetQueueCounters` |
| `internal/im/handler/operator/stream.go`, `stream_render.go` (новые) | `OpenEventStream`, насос, сборка сообщений |
| `internal/im/handler/operator/session.go`, `activity.go` (новый) | сессия, активность |
| `internal/im/handler/handler.go` | настоящий writer в контексте |
| `internal/im/handler/test/operator_cost_test.go`, `operator_session_test.go`, `operator_queue_test.go`, `operator_stream_test.go`, `stream_helpers_test.go` (новые) | тесты |
| `Makefile`, `cmd/im/main.go`, `docs/adr/002…`, `005…` | сборка, остановка, ADR |

| Файл (IM) | Что |
|---|---|
| `Specification/Workflow_machine/openapi.json` | правка контракта (CRLF) |
| `prototype/server.js`, `prototype/app.js`, `prototype/selftest.js`, `tests/api-scenarios.js` | строка без вариантов людей |
| `research/integration/30-local-stand.md`, `40-plan.md`, `56-plan-stage5.md` | стенд, этапы, итог |

## Часть 1. Цена чтения

Очередь и поток повторно используют `Load` и `summary`, поэтому эта часть идёт первой.

### Task 1: Замер и счётчик запросов

**Files:** изменить `internal/im/service/storing/common.go`, `internal/im/handler/test/common.go`, `helpers.go` (строка 149), `intake_store_test.go` (строка 46); создать `internal/im/handler/test/operator_cost_test.go`.

**Interfaces:**
- Consumes: `initDBConn` (`common.go:46`), `pgx.ParseConfig`, `stdlib.OpenDB`.
- Produces: `storing.NewStoreTraced(config *model.Config, logger logrus.FieldLogger, tracer pgx.QueryTracer) (*Store, error)`; `sqlCounter` с методами `Reset()`, `Count() int`, `Selects() int`; `f.costTree(t)`, `f.bigFamily(t, linked, people int) *costCase`; `measure(t, name string, budget time.Duration, fn func())`.

- [ ] **Step 1: Счётчик.** `NewStore` становится обёрткой над `NewStoreTraced(config, logger, nil)`. `tracer` кладётся в `ConnConfig.Tracer`. `sqlCounter` реализует `pgx.QueryTracer`, считает атомарно. Все `Store` пакета `handler/test` создаются с ним: и тот, что у `AppServices`, и общий у `f.store`.
- [ ] **Step 2: Тест счётчика.** `TestSQLCounterSeesStore`: `Reset`, один `GetMachineIncidents`, `require.Equal(t, 1, c.Selects())`. Обход счётчика невозможен: он стоит на драйвере.
- [ ] **Step 3: Запуск.** Команда «с базой», `-run 'TestSQLCounterSeesStore'`. Ожидается PASS.
- [ ] **Step 4: Набор для замера.** `f.costTree` строит дерево групп: 1000 групп глубины 8, около 8000 пар замыкания, и проверяет `len(ancestors) >= 7900`. В репозитории такого набора нет, в ADR-005 цифры сняты на том, что накопилось в im-test-db, поэтому набор задаётся здесь. `f.bigFamily(t, 200, 10)`: основной с `linked` привязанными на разных источниках, `people` человек в `Directory`, правило доступа на корень.
- [ ] **Step 5: Запись «было».** `TestReadCostBefore` под `IM_MEASURE=1` пишет `t.Log` времени и числа запросов шести строк решения 69. Числа — в `progress.md`. Эталонов в этом тесте нет, тест удаляется в Task 6.
- [ ] **Step 6: Прогон и коммит.** `Этап 5а: счётчик запросов на драйвере и набор для замера`.

### Task 2: Набор видимости `VisibleAmong`

**Files:** создать `internal/im/service/storing/access_queries.go`; изменить `internal/im/appservice/incident/incident.go`, `internal/im/appservice/operator/deps.go`, `load.go`, `internal/im/handler/operator/*`; тесты `operator_cost_test.go`.

**Interfaces:**
- Consumes: `GetIncidentByUserGroupIDs` (`service/storing/incident_queries.go:45–92`), `Visible` (`appservice/incident/incident.go:90–106`), `visibleOnly` (`load.go:156–171`).
- Produces: `const accessRuleMatch`; `(*Store).VisibleIncidentIDs(ctx model.AppContext, customer uuid.UUID, ids []uuid.UUID, groups []int64, ancestors, descendants []uuid.UUID) (map[uuid.UUID]bool, error)`; `incident.AppService.VisibleAmong(ctx, user *model.User, guids []uuid.UUID) (map[uuid.UUID]bool, error)`; `Deps.VisibleAmong`. Обёртка `Deps.Visible` — по решению 66.

- [ ] **Step 1: Тесты.** `TestVisibleAmongMatchesVisible`: таблица случаев (правило на источник, на тип источника, на тип события, на группу, на предка группы, без правил, удалённое правило, удалённый инцидент), на каждый случай `VisibleAmong` равно ответу старого `Visible`. Старый запрос `GetIncidentByUserGroupIDs` пока жив и служит образцом. `TestVisibleAmongOtherCustomer`: инцидент чужого клиента — `false`, даже при совпавшем правиле. `TestVisibleAmongOneQuery`: 200 id — `c.Selects() == 1` плюс проверка прав, если она ходит в базу; `ClosurePairs` вызван один раз (подсчёт через обёртку `GroupTree`).
- [ ] **Step 2: Запуск.** `-run 'TestVisibleAmong'`, ожидается FAIL (нет функции).
- [ ] **Step 3: Реализация.** Форма SQL (PostgreSQL 9.6 материализует CTE один раз, что здесь и нужно): `rules` — правила клиента по группам пользователя; `closure` — `unnest` пар; `rule_sources` — правило → источник через замыкание; затем инциденты с их событиями `LEFT JOIN` на правила. `Load` (`visibleOnly`) и `loadRelatives` спрашивают один раз про весь набор.
- [ ] **Step 4: Запрос на карточку.** `TestCardVisibleOnce`: карточка с 200 привязанными и `linkedCount` — видимость соседей одним запросом; в `Load` число запросов равно при 1 и при 200 привязанных.
- [ ] **Step 5: Запуск и коммит.** `-run 'TestVisibleAmong|TestCardVisibleOnce|TestFlow'` и команда «без базы». `Этап 5а: видимость набором одним запросом`.

### Task 3: Память доступа на запрос

**Files:** создать `internal/im/appservice/operator/access.go`; изменить `internal/im/service/transition/world.go`, `internal/im/service/storing/access_queries.go`, `internal/im/appservice/operator/world.go`; тесты `operator_cost_test.go`, `appservice/operator/access_test.go`.

**Interfaces:**
- Consumes: `serverWorld.access` (`transition/world.go:110–131`), `eventDevice` (`:255`), `rest.otherPerson` (`appservice/operator/world.go:83–94`), `Directory.People`.
- Produces: `storing.AccessPerson{ID string; Groups []int64}`, `storing.AccessKey{Source, SourceType, EventType uuid.UUID}`, `(*Store).AccessMatrix(ctx, customer, people []AccessPerson, keys []AccessKey, ancestors, descendants []uuid.UUID) (map[string]map[AccessKey]bool, error)`; `transition.AccessSource` с методом `Access(person string, x map[string]any) (bool, error)`; `opapp.AccessMemo`, `opapp.NewAccessMemo(ctx, deps, customer) *AccessMemo`, `(*AccessMemo).Prefill(incidents []map[string]any) error`.

- [ ] **Step 1: Тесты.** `TestAccessMatrixMatchesVisible`: те же случаи, что в Task 2, матрица равна `VisibleAmong`. `TestAccessMemoOneQueryForTenPeople`: 10 людей, 200 инцидентов с 200 разными тройками, все вопросы `Access` — один запрос матрицы. `TestAccessMemoKeyOutsideSet`: ключ вне набора — ещё ровно один запрос, ответ верный. `TestAccessMemoKeepsCustomer`: человек с тем же id в другом клиенте доступа не получает.
- [ ] **Step 2: Запуск.** `-run 'TestAccess'`, ожидается FAIL.
- [ ] **Step 3: Реализация.** Тройка инцидента читается из события; `eventDevice` запоминает всю тройку и получает набор: одно чтение на все события семьи. `serverWorld` и `rest` держат один `AccessMemo`; новый `serverWorld` на вызов в `otherPerson` убирается. `NewServerWorld` с `nil` у интейка работает как раньше. Мир уже держит мьютекс на `device`, память защищена так же: Core зовёт факты из одной горутины, но поток и тесты с `-race` не должны зависеть от этого.
- [ ] **Step 4: Правка учёта.** `offersTransferTo` считает людей × строки на CEL, но без SQL. `TestFormTransferNoSQLPerPerson`: 1 и 10 людей — равное число запросов на карточке.
- [ ] **Step 5: Запуск и коммит.** `-run 'TestAccess|TestFormTransfer|TestFlow|TestVectors'`, «без базы». `Этап 5а: матрица доступа на запрос`.

### Task 4: Одно чтение семьи на вид

**Files:** изменить `internal/im/service/transition/view.go`, `view_card.go`, `view_form.go`, `refs.go`; `internal/im/handler/operator/view_summary.go`, `view_card.go`, `view_actions.go`; тесты `service/transition/view_test.go`, `operator_cost_test.go`.

**Interfaces:**
- Consumes: `viewScope` (`view.go:61–82`), `Actions` (`:89`), `CanEditScenario` (`:193`), `Present` (`service/transition/view_card.go:41`), `Form` (`view_form.go:51`), `newRefSource` (`refs.go`).
- Produces: `transition.View`; `(*Core).View(ctx, repo, w, op ViewOp, incident map[string]any) (*View, error)`; `(*Core).ViewPage(ctx, repo, w, op ViewOp, incidents []map[string]any) ([]*View, error)`; методы вида `Actions() ([]ActionView, error)`, `Present(enabled []string)` с тем же результатом, что у `Core.Present`, `Form(formID string) (*FormView, error)`, `CanEditScenario() (bool, error)`.

- [ ] **Step 1: Тесты.** `TestViewSameAsSeparateCalls`: на всех инцидентах набора векторов `View.*` равны старым `Core.*`. `TestViewPageSameAsViewOne`: `ViewPage` на странице разных семей равен `View` на каждой строке: это проверяет, что общий список семей не меняет ответы. `TestRefSourceCandidatesMemo`: два одинаковых `(fact, args)` — один вызов `Repo.Candidates`; изменённый черновик виден поверх памяти. `TestViewReadsFamilyOnce`: на `MemRepo` счётчик `ReadFamily` равен 1 на `View` со всеми четырьмя методами и 1 на `ViewPage`.
- [ ] **Step 2: Запуск.** Команда «без базы», ожидается FAIL.
- [ ] **Step 3: Реализация.** Комментарий `refs.go` «Cost: nothing is cached» заменить. Обёртки `Core.Actions`, `Present`, `Form`, `CanEditScenario` — через `View`. `summary` и `card` берут один `View`; `sibling` (`handler/operator/view_card.go:149`) — `ViewPage` на соседей.
- [ ] **Step 4: Проверка.** `TestCardSQLCount`: равенство 1 и 200 привязанных, 1 и 10 людей, потолок 30 (решение 69).
- [ ] **Step 5: Запуск и коммит.** «Без базы» и `-run 'TestCardSQLCount|TestFlow|TestVectors'`. `Этап 5а: одно чтение семьи на вид`.

### Task 5: `ListLinked` и бюджеты чтения

**Files:** изменить `internal/im/handler/operator/linked.go`, `internal/im/appservice/operator/load.go`; тесты `operator_cost_test.go`, `operator_flows_test.go`.

**Interfaces:**
- Consumes: `ListLinked` (`linked.go:26–68`, ветка 500 на строках 53–57), `Load` (`load.go:40–71`).
- Produces: `(*Deps).LoadMany(ctx, user *model.User, rows []*model.MachineIncident) ([]*Loaded, error)`: число запросов не зависит от длины; порядок как у входа; удалённая в окне строка отсутствует в ответе.

- [ ] **Step 1: Тесты.** `TestListLinkedSkipsDeletedInWindow`: подмена `Deps.Store`, которая удаляет строку между списком и загрузкой, — ответ `200`, строки нет, `total` как посчитан. `TestListLinkedSQLCount`: равенство 1 и 200, потолок 20. `TestLoadManySameAsLoad`: каждая строка равна `Load` одного. `TestReadBudgets` (`IM_MEASURE=1`): первые три строки решения 69.
- [ ] **Step 2: Запуск.** `-run 'TestListLinked|TestLoadMany'`, ожидается FAIL.
- [ ] **Step 3: Реализация.** `ListLinked` не вызывает `h.deps.Load` на строку. Ошибка `model.ErrEntryNotFound` для одной строки не ошибка ответа.
- [ ] **Step 4: Замер.** Команда «замеры», `-run 'TestReadBudgets'`. Бюджет не сошёлся — разбирать, а не поднимать число. Поднять можно только с записью в итог плана и причиной.
- [ ] **Step 5: Запуск и коммит.** `Этап 5а: привязанные одним набором и бюджеты чтения`.

### Task 6: Те же проверки под блокировкой

**Files:** изменить `internal/im/appservice/operator/world.go`, `internal/im/handler/operator/transition.go`, `linked.go`, `merge.go`; тест `operator_cost_test.go`.

**Interfaces:**
- Consumes: `Core.Run` (`run.go:26`), `attempt` (`family.go:30–42`), `check` (`run.go:211`), `Deps.World`.
- Produces: мир один на запрос во всех повторах попытки (решение 70); тестовая обёртка `Repo` с временем между `LockFamily` и концом `DoInTx`.

- [ ] **Step 1: Тесты.** `TestLockedChecksSQLCount`: операция над основным в работе, 1 и 10 людей, 1 и 50 привязанных — равное `c.Selects()`, потолок 30. `TestRetryKeepsAccessMemo`: `ErrFamilyChanged` в первой попытке — матрица доступа прочитана один раз, кандидаты прочитаны заново. `TestLockHoldBudget` (`IM_MEASURE=1`): удержание ≤ 200 мс.
- [ ] **Step 2: Запуск.** Ожидается FAIL на равенстве, пока `Deps.World` создаётся на попытку или проверяется без памяти.
- [ ] **Step 3: Реализация.** До блокировки `AccessMemo.Prefill` не нужен: он читает лениво. Если замер покажет, что матрица читается под блокировкой слишком долго, перенести `Prefill` по `ReadFamily` до `DoInTx`, ответы доступа от блокировки не зависят.
- [ ] **Step 4: Удалить `TestReadCostBefore`** из Task 1; числа «после» записать в `progress.md` рядом с «было».
- [ ] **Step 5: Запуск и коммит.** `-run 'TestLocked|TestRetry|TestFlow'`, «замеры» `TestLockHoldBudget`. `Этап 5а: цена проверок под блокировкой`.

### Task 7: Гонка отсоединения

**Files:** изменить `internal/im/service/transition/core.go`, `run.go`, `internal/im/handler/operator/linked.go`, `mapping.go`; тесты `service/transition/run_test.go`, `operator_flows_test.go`.

**Interfaces:**
- Consumes: `Op` (`core.go:119–132`), `lock` (`run.go:98`), `DetachLinked` (`linked.go:72–107`), `runAllLinked` (`:138–169`), `linkedTo` (`:181`).
- Produces: `Op.LinkedTo string`, `transition.ErrNotLinkedHere`.

- [ ] **Step 1: Тесты.** `TestDetachRefusedWhenMergedElsewhere` (ядро): инцидент уже привязан к B, `Op.LinkedTo` = A — `ErrNotLinkedHere`, ничего не записано. `TestDetachRaceThirdRequest` (маршрут, через `Deps.World` как тесты правок финального ревью): проигравший между своей проверкой `linkedTo` и блокировкой, третий запрос объединил инцидент в B, ответ `404`, инцидент остался в B. `TestDetachAllRaceThirdRequest`: `412` с текущим основным.
- [ ] **Step 2: Запуск.** Ожидается FAIL.
- [ ] **Step 3: Реализация.** Проверка в `lock` после `lockedPrimary` на каждой своей строке, если `op.LinkedTo != ""`. Ошибка не повторяется попыткой. `failed` переводит её в те же ответы, что уже есть у проигравшего (`runOne`, `runAllLinked`).
- [ ] **Step 4: Запуск и коммит.** «Без базы», `-run 'TestDetach'`. `Этап 5а: отсоединение проверяет основного под блокировкой`.

### Task 8: Мелкие долги

**Files:** изменить `internal/im/appservice/operator/world.go`, `internal/im/handler/operator/merge.go`, `Makefile`, `internal/im/model/permission_machine_test.go` или `service/catalog/catalog_test.go`; ADR-005.

**Interfaces:**
- Consumes: `ActorName` (`world.go:136–149`, строка 146), `merge` (`merge.go:46–74`: `findAll` на 47, `maxBulk` на 60), `Makefile:44–45`, `machineStrings` (`model/permission_machine_test.go:211`).
- Produces: ничего нового.

- [ ] **Step 1: `ActorName`.** `TestActorNameFallsBackToID`: человек с пустым `Name` — возвращается id. Правка строки 146.
- [ ] **Step 2: Порядок у слияния.** `TestMergeTooManyBeforeRead`: id больше `maxBulk` — отказ без единого `SELECT` по инцидентам (`sqlCounter`). Проверка переносится перед `findAll`. Отличие от `executeBulk` и прототипа записать в ADR-005 одной строкой. Значение `limits.maxBulk` сейчас `null`, поэтому тест задаёт лимит подменой машины, как `patchedCore`.
- [ ] **Step 3: `test-local`.** `IM_TEST_DB_URL='$(TEST_DB_URL)' go test -race -timeout 40m ./...`. Проверка: `make -n test-local`.
- [ ] **Step 4: Ключи строк.** `TestStringsRUHasMachineKeys`: все `labelKey`, `textKey`, `hintKey`, `errorKey` машины есть в `operatorapi.StringsRU`. Образец — `machineStrings`. Разошедшиеся ключи чинятся только правкой IM. Если тест их найдёт, ключи добавляются в список правок Task 9, а здесь тест коммитится с `t.Skip("Task 9")`; Task 9 этот `Skip` снимает.
- [ ] **Step 5: Запуск и коммит.** «Без базы», `-run 'TestActorName|TestMerge'`. `Этап 5а: мелкие долги 4в`.

## Часть 2. Контракт

### Task 9: Правка контракта и прототипа, перенос на сервер

Единственная правка контракта в 5а (решение 74). Сначала IM, потом сервер.

**Files (IM):** `Specification/Workflow_machine/openapi.json` (CRLF), `prototype/server.js`, `prototype/app.js`, `prototype/selftest.js`, `tests/api-scenarios.js`; собранные — только через сборку.
**Files (сервер):** `api/im/operator/*`, `api/im/operator/SOURCE`, `internal/im/handler/operator/*.gen.go` если сборка изменит.

**Interfaces:**
- Consumes: `formView` (`server.js:576`), `openDialog` (`app.js:1668`, `fieldOptions` на 1680).
- Produces: контракт новой версии; строка очереди без `fieldOptions.targetId`.

- [ ] **Step 1: Перед правкой IM.** `git fetch`. Есть новое — сначала сказать.
- [ ] **Step 2: Тест прототипа.** В `tests/api-scenarios.js` новый тест: `actionOf(row, "transfer").fieldOptions.targetId` равно `undefined`, у карточки варианты есть, `actionOf(row, "close").fieldOptions.resultId` на месте (строки 781 и 874 не меняются). Шаг самопроверки в `selftest.js`: передача из строки очереди открывает форму с адресатами.
- [ ] **Step 3: Прототип.** `formView`: при `surface === "queue"` поле с `source: transferTargets` пропускается. `openDialog` становится асинхронным: нет вариантов у поля с источником — `api.get` карточки и `actionOf(card, id)`.
- [ ] **Step 4: Контракт.** Пять правок решения 74, плюс в `listIncidents.pageSize`: «больше 200 — урезается до 200». Править скриптом с `newline=""`, чтобы сохранить CRLF. Проверка: `file Specification/Workflow_machine/openapi.json` показывает CRLF, `git diff --stat` не показывает весь файл.
- [ ] **Step 5: Сборка и проверки IM.** `python3 tools/build_workflow.py`, все быстрые проверки из `CLAUDE.md`, `python3 tools/check_ui.py`, `python3 tools/check_guide.py`, самопроверка и `tests/api.html` в headless Chrome (временные файлы в scratchpad). Коммит IM: `Этап 5а: контракт и прототип — строка очереди без вариантов людей, кадр без данных, ключ повтора`.
- [ ] **Step 6: Перенос.** `make vendor-operator-contract`, затем `make gen-api-operator`, в `SOURCE` хэш коммита IM. Строки `StringsRU` — как собраны, если ключи изменились. Включить `TestStringsRUHasMachineKeys` из Task 8.
- [ ] **Step 7: Сервер.** `ViewOp.RowForm`: `formOn` (`view_form.go`) пропускает поле с `source == "transferTargets"`, `form` в `view_actions.go` не пишет `targetId`. `TestRowFormHasNoPeople` (ядро), `fieldRules` остальных полей равны карточке.
- [ ] **Step 8: Запуск и коммит.** «Без базы», `-run 'TestFlow|TestVectors|TestContract'`. `Этап 5а: перенос контракта`.

## Часть 3. Сессия

### Task 10: Таблица `operator_sessions` и общая память

**Files:** создать `internal/im/service/storing/migrations/019_operator_sessions.sql`, `internal/im/service/storing/session_queries.go`, `internal/im/appservice/operator/session.go`, тест `operator_session_test.go`; изменить `internal/im/appservice/operator/directory.go`, `deps.go`, `world.go`, `internal/im/handler/operator/auth.go`, `handler/test/operator_helpers_test.go`.

**Interfaces:**
- Consumes: `Directory` (`directory.go:21–29`), `SeenDirectory` (`:39`), `Authenticate` (`auth.go:17–33`, `Remember` на строке 28), `otherPerson`, `Fact` (`world.go:43–77`).
- Produces: таблица ниже; `model.OperatorSession`; `(*Store).RememberOperator(ctx, s *model.OperatorSession, now int64) error`, `OperatorSessions(ctx, customer, ids []int64) (map[int64]*model.OperatorSession, error)`; `Directory.Remember(ctx, u) error`, `Person(ctx, customer, id) (*model.User, bool, error)`, `People(customer) []*model.User`; `opapp.SharedDirectory`.

```sql
CREATE TABLE operator_sessions (
    customer_guid UUID NOT NULL,
    user_id BIGINT NOT NULL,
    name TEXT NOT NULL DEFAULT '',
    permissions JSONB NOT NULL DEFAULT '[]',
    user_group_ids JSONB NOT NULL DEFAULT '[]',
    agent_state TEXT NOT NULL DEFAULT 'offline',
    reason_id TEXT NOT NULL DEFAULT '',
    preferences JSONB NOT NULL DEFAULT '{}',
    last_transfer_target TEXT NOT NULL DEFAULT '',
    open_incident_guid UUID,
    last_activity_ms BIGINT NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    PRIMARY KEY (customer_guid, user_id)
);
```

- [ ] **Step 1: Тесты.** `TestFirstSightIsOffline`: первый запрос нового человека — строка с `offline`, `last_activity_ms = now`. `TestSecondSignInKeepsState`: состояние `ready`, новый запрос с другими правами — права новые, состояние прежнее. `TestRememberWritesOnlyOnChange`: 5 одинаковых `GET` — одна запись. `TestPersonFromOtherInstance`: два `SharedDirectory` на одну базу, `Remember` в первом, `Person` во втором находит, права совпадают; `People` второго пуст (решение 75, тест закрепляет ограничение). `TestPersonOtherCustomer`: тот же id в другом клиенте — никто.
- [ ] **Step 2: Запуск.** `-run 'TestFirstSight|TestSecondSignIn|TestRemember|TestPerson'`, ожидается FAIL.
- [ ] **Step 3: Реализация.** `SharedDirectory` обёртывает `SeenDirectory`: `People` — из него, `Person` — сначала снимок запроса, потом таблица. `Authenticate`: ошибка `Remember` только в журнал, запрос идёт.
- [ ] **Step 4: Снимок.** `rest` читает `OperatorSessions` один раз на запрос на всех людей `People` плюс себя. Факт `agentState` — из снимка, `agentStateUnknown` для незнакомых как было (`world.go:56–64`). `AgentStateNow` удалить: `available` (`view_actions.go:128`) и `session.go` идут от снимка.
- [ ] **Step 5: Помощник тестов.** `f.operator` ставит `ready` прямо в таблицу (решение 76), `f.operatorOffline` этого не делает. `TestCardSQLCount` не ухудшился: один запрос снимка на 10 людей.
- [ ] **Step 6: Запуск и коммит.** `-run 'TestFirstSight|TestSecondSignIn|TestRemember|TestPerson|TestCardSQLCount|TestFlow'`. Прогнать и весь пакет: смена начального состояния трогает все тесты 4в. `Этап 5а: сессия оператора в таблице, общая память о людях`.

### Task 11: Активность и heartbeat

**Files:** создать `internal/im/handler/operator/activity.go`; изменить `internal/im/handler/operator/handler.go`, `session.go`, `stubs.go`, `internal/im/appservice/operator/world.go`, `session_queries.go`; тест `operator_session_test.go`.

**Interfaces:**
- Consumes: `SessionHeartbeat` (`stubs.go:107`), `idleSec` (`world.go:65`, STAGE5), `Deps.Now`.
- Produces: `(*Store).TouchOperator(ctx, customer, userID, now int64) error`, `SetOpenIncident(ctx, customer, userID, guid *uuid.UUID) error`; посредник `Handler.activity`.

- [ ] **Step 1: Тесты.** `TestRefusedRequestCountsAsActivity`: отказанный `POST` (`422`) сдвигает `last_activity_ms`. `TestGetIsNotActivity`: `GET` не сдвигает. `TestStreamIsNotActivity` — позже, в Task 23. `TestHeartbeatStoresOpenIncident`: `204`, значение сохранено, `null` стирает, тело пустое допустимо, неверный JSON — `400`. `TestStateStaysAfterHeartbeatLost`: `ready`, часы вперёд на 2 часа без запросов — состояние `ready`, `available` не изменился, `idleSec` = 7200. `TestIdleIsOnServerClock`: часы назад на минуту — `idleSec` = 0, а не отрицательный; следующая активность с меньшим `now` не двигает `last_activity_ms` назад (`GREATEST`).
- [ ] **Step 2: Запуск.** `-run 'TestRefused|TestGetIs|TestHeartbeat|TestStateStays|TestIdleIs'`, ожидается FAIL.
- [ ] **Step 3: Реализация.** Посредник идёт после `Authenticate`, пишет до обработчика (отказ тоже считается). `/test/*` не считается. Снимок (Task 10) даёт `idleSec`. Заглушка `SessionHeartbeat` уходит из `stubs.go`.
- [ ] **Step 4: Запуск и коммит.** `Этап 5а: активность и heartbeat на часах сервера`.

### Task 12: `getOperatorSession` и `setAgentState`

**Files:** изменить `internal/im/handler/operator/session.go`, `stubs.go`, `internal/im/appservice/operator/session.go`, `session_queries.go`; тест `operator_session_test.go`.

**Interfaces:**
- Consumes: `sessionView` (`server.js:953–973`), `usage` (`:946`), `session` машины, `refusalProblem`, `GetOperatorSession` (`session.go:16–37`).
- Produces: `(*Store).MoveOperator(ctx, customer, userID, from, to, reason string) (bool, error)`; `(*Deps).SetAgentState(ctx, user, to, reason string) (*StateChange, *transition.Refusal, error)`; `StateChange{From, To string; Affected []string}`.

- [ ] **Step 1: Тесты.** Таблица из `tests/api-scenarios.js:474–521`: `TestAgentStateTable` — из каждого состояния в каждое: код и `messageKey` как в решении 79. `TestAgentStateSameIsNoop`: причина перерыва не меняется, события нет. `TestAgentStateNeedsPermission`, `TestAgentStateNeedsReason`, неизвестная причина — `422`. `TestBusyIsShownNotStored`: своё в работе — ответ `busy`, в таблице `ready`, перерыв из `busy` работает. `TestAgentStateRace`: два параллельных запроса от одного человека, `break` и `sign_out` — итог один из допустимых, оба ответа в контракте. `TestSessionShape`: `limits` без `$`, `usage` по настоящему `countMine`, `preferences`, `lastTransferTargetId`, `workflowSchemaVersion`, `permissionIssues: []`, сверка с контрактом через `o.do`. `TestReadOnlyAfterBreak`: на перерыве переход отказан `AGENT_NOT_READY`, текст из `readOnlyReasonKey`.
- [ ] **Step 2: Запуск.** `-run 'TestAgentState|TestBusy|TestSessionShape|TestReadOnly'`, ожидается FAIL.
- [ ] **Step 3: Реализация.** Переходы, причины, права и `derived.expr` — из `m.Data("session.…")`, ничего не зашивать. `busy` — через `Definition` или выражение машины с `me`.
- [ ] **Step 4: Запуск и коммит.** `Этап 5а: состояние оператора`.

### Task 13: Системные переходы при перерыве и выходе

**Files:** изменить `internal/im/appservice/operator/session.go`, `internal/im/handler/operator/session.go`; тест `operator_session_test.go`.

**Interfaces:**
- Consumes: `Core.Run`, переходы решения 80, `summary`, `MachineIncidentsByOwnerState`.
- Produces: `(*Deps).SessionMoves(ctx, user, to string) ([]uuid.UUID, error)`.

- [ ] **Step 1: Тесты.** `TestBreakHoldsMine`: в работе — `on_hold`, причина `break`, таймер решения на паузе, `affectedIncidents` содержит его, свои `on_hold` не тронуты. `TestSignOutReleasesMine`: в работе и отложенные — `new`. `TestSignOutAddressedToQueue`: адресованный лично и не принятый — `new` (группы нет до этапа 7). `TestSignOutAddressedToGroup`: при `dutyGroupOf` из подмены мира — к группе. `TestSessionMoveFailureDoesNotStop`: подмена `Core`, ошибка на втором из трёх — первый и третий выполнены, ответ `200`, ошибка в журнале. `TestReadyMovesNothing`: `ready` — пустой `affectedIncidents`.
- [ ] **Step 2: Запуск.** `-run 'TestBreak|TestSignOut|TestSessionMove|TestReadyMoves'`, ожидается FAIL.
- [ ] **Step 3: Реализация.** Актор `system`, поверхность как у системных переходов в векторах 4б. Порядок кандидатов — по номеру. Каждый `Core.Run` с `Op.InTx` появится в Task 20, здесь без него.
- [ ] **Step 4: Запуск и коммит.** `Этап 5а: системные переходы при перерыве и выходе`.

### Task 14: `updatePreferences` и язык ответа

**Files:** изменить `internal/im/handler/operator/reply.go`, `mapping.go`, `session.go`, `stubs.go`, `session_queries.go` и места вызова `newProblem`; тест `operator_session_test.go`.

**Interfaces:**
- Consumes: `viewerOf` (`reply.go:54`, строка 61), `refusalProblem` (`mapping.go:41`), `errorProblem` (`:64`), `internalProblem` (`:84`), `newProblem` (`:88`, строка 89).
- Produces: `(*Store).MergePreferences(ctx, customer, userID, patch []byte) ([]byte, error)`; `newProblem(locale, …)`.

- [ ] **Step 1: Тесты.** `TestPreferencesShallowMerge`: `{theme}` не стирает `panels`, вложенные `panels` заменяются целиком, как `Object.assign`. `TestPreferencesBadJSON`: `400`. `TestPreferencesEmptyPatch`: `200`, прежнее значение. `TestAnswerLanguage`: `locale: en` — `Problem.message` и `reason` действий на английском из каталога; неизвестный — `ru`. `TestLocaleInReasonVars`: ключ не меняется, меняется только текст. `TestLocaleOfFirstRequest`: первое чтение до настройки — `ru`.
- [ ] **Step 2: Запуск.** Ожидается FAIL.
- [ ] **Step 3: Реализация.** 63 места вызова через функции маппинга: `locale` идёт параметром, `Authenticate` не трогается. Метка `STAGE5` на `mapping.go:40` и `reply.go:61` уходит. Если в каталоге строки нет — как раньше, каталог сам берёт `ru`. Английских строк может быть мало: это этап строк, а не сервера.
- [ ] **Step 4: Запуск и коммит.** «Без базы», `-run 'TestPreferences|TestAnswerLanguage|TestLocale|TestFlow'`. `Этап 5а: настройки и язык ответа`.

## Часть 4. Очередь

### Task 15: Невидимый основной

Идёт до очереди: `summary` будет на каждой строке и в потоке.

**Files:** изменить `internal/im/service/transition/view.go`, `view_card.go`, `internal/im/appservice/operator/load.go`, `internal/im/handler/operator/view_summary.go`, `view_card.go`, `incident.go`; тест `operator_flows_test.go`.

**Interfaces:**
- Consumes: `cardNote` (`service/transition/view_card.go:125`, `primaryNumber` на 159), `summary` (`handler/operator/view_summary.go:60`), `service/transition/journal.go:192`, `getJournal`.
- Produces: `ViewOp.HidePrimary bool`, `Loaded.PrimaryVisible bool`.

- [ ] **Step 1: Тесты.** `TestInvisiblePrimaryHidden`: привязанный виден, основной нет — в сводке `linkedTo` нет, в пояснении карточки `primaryNumber` равно `—`, в строке журнала о привязке тоже `—`, `alarmNumber` на месте. Ответ сырьём не содержит ни guid, ни номера основного (`require.NotContains` по телу). `TestVisiblePrimaryShown`: видимый основной показан как раньше. Те же поля в строке очереди проверит Task 16, в потоке — Task 24.
- [ ] **Step 2: Запуск.** Ожидается FAIL.
- [ ] **Step 3: Реализация.** `Load` и `LoadMany` спрашивают видимость основных тем же запросом `VisibleAmong`, отдельного запроса нет.
- [ ] **Step 4: Запуск и коммит.** `Этап 5а: невидимый основной не раскрывается`.

### Task 16: Строка очереди набором

**Files:** изменить `internal/im/appservice/operator/load.go`, `internal/im/handler/operator/view_summary.go`, `internal/im/service/transition/view.go`; тест `operator_cost_test.go`.

**Interfaces:**
- Consumes: `LoadMany` (Task 5), `ViewPage` (Task 4), `loadRelatives` (`load.go:138–153`), `RowForm`.
- Produces: `(h *Handler) summaries(v *viewer, list []*opapp.Loaded) ([]operatorgen.IncidentSummary, error)`: строки глазами `v`, поверхность `queue`, `RowForm: true`, отсутствующие строки опущены.

- [ ] **Step 1: Тесты.** `TestSummariesSameAsSummary`: на наборе потоков каждая строка равна `summary` одной, кроме вариантов людей. `TestSummariesSQLCount`: 8 и 25 строк, 1 и 10 людей — равно, потолок 25; `linkedOf` на строку заполнен одним запросом (`MachineIncidentsLinkedToAny`), `countMine` из памяти кандидатов. `TestRowHidesInvisiblePrimary`.
- [ ] **Step 2: Запуск.** Ожидается FAIL.
- [ ] **Step 3: Реализация.** `ViewPage` заполняет память кандидатов `linkedOf` по всем id. Поля `linkedCount`, `siblingCount` — одним запросом на набор.
- [ ] **Step 4: Запуск и коммит.** `Этап 5а: строки очереди набором`.

### Task 17: Классы фильтров и `getQueueCounters`

**Files:** создать `internal/im/appservice/operator/queue.go`, `internal/im/service/storing/queue_queries.go`, `internal/im/handler/operator/queue.go`, тест `operator_queue_test.go`; изменить `stubs.go`.

**Interfaces:**
- Consumes: `queueFilters` машины, `accessRuleMatch`, `counters` (`server.js:1070`).
- Produces: `storing.QueueScope{Customer uuid.UUID; Groups []int64; ScenarioGUIDs []uuid.UUID}` (Task 19 добавит остальные сужения); `(*Store).QueueClasses(ctx, scope QueueScope, ancestors, descendants []uuid.UUID) ([]QueueClass, error)`; `QueueClass{State, Owner, AssignmentGroup string; Count int}`; `(*Deps).QueueFilters(ctx, user, classes []QueueClass) (map[string][]QueueClass, error)`.

- [ ] **Step 1: Тесты.** `TestQueueClassesMatchRowCEL`: все состояния × `ownership` (`owner`, `target`, `other`, ничей), счётчики по классам равны подсчёту `queueFilters` CEL по каждой строке. `TestCountersHideInvisible`: чужое устройство не считается ни в одном фильтре. `TestCountersHideLinked`. `TestCountersByScenario`: только `scenarioGuid` сужает, через запятую. `TestCountersAllFilters`: в ответе все id `queueFilters` машины, нули тоже. `TestCountersCheckContract`. `TestCountersBudget` (`IM_MEASURE=1`): 5000 и 20000, ≤ 200 мс; `TestCountersOneQuery`: один запрос классов, не считая видимости прав.
- [ ] **Step 2: Запуск.** Ожидается FAIL.
- [ ] **Step 3: Реализация.** Представитель класса — карта с `state`, `owner`, `assignmentGroup`; остальных полей выражения фильтров сейчас не читают, тест сверки обязателен. `inCategory` — определение машины. Если бюджет не сойдётся, сначала частичный индекс, потом открытый вопрос 7, а не правка смысла.
- [ ] **Step 4: Запуск и коммит.** `-run 'TestQueueClasses|TestCounters'`. `Этап 5а: счётчики очереди по классам машины`.

### Task 18: `listIncidents`: порядок и страницы

**Files:** создать `internal/im/service/storing/migrations/021_queue_index.sql`; изменить `queue_queries.go`, `appservice/operator/queue.go`, `handler/operator/queue.go`, `stubs.go`; тест `operator_queue_test.go`.

**Interfaces:**
- Consumes: `QueueClasses`, `summaries`, `page` (`server.js:1056–1067`), `sortOf` (`:1005`), `queueSort` машины.
- Produces: `queueOrderSQL map[string]string` с проверкой на старте `CheckQueueOrders(m *machine.Machine) error`; `(*Store).QueuePage(ctx, scope, classes []QueueClass, order string, offset, limit int, focus *uuid.UUID) (*QueuePage, error)`; `QueuePage{IDs []uuid.UUID; Total int; FocusIndex *int}`.

Перевод порядка: `priority_then_oldest` → `p.value DESC, e.occurred_at ASC`; `-priority,-occurredAt` → `p.value DESC, e.occurred_at DESC`; `occurredAt` → `e.occurred_at ASC`; порядок по таймеру реакции → «таймер идёт» первым, затем `(timers->'reaction'->>'due')::bigint` у идущих и время события у остальных. Всегда в конце `i.number`. Имена вариантов брать из `queueSort.options` машины, таблица выше — смысл.

- [ ] **Step 1: Тесты.** `TestQueueOrderMatchesMachineKeys`: все варианты на наборе с равными приоритетами, с идущим и сработавшим таймером: порядок SQL равен сортировке по ключам CEL. `TestCheckQueueOrdersRefusesUnknown`: вариант без перевода — ошибка. `TestQueueSortIgnoredWhenLocked`: `operatorMayChange: false` — параметр и настройка не действуют. `TestQueueFilters`: каждый фильтр, по умолчанию `open`, неизвестный — проходит хоть один. `TestQueuePageBounds`: за концом — последняя, `page` в ответе настоящая, размер 0 и меньше — 1, 500 — 200, пустой список — страница 1. `TestQueueFocusPage`: виден — номер страницы, не виден — `null`. `TestQueuePageWhileRowsMove`: между страницами 1 и 2 строка закрыта и новая создана — ответы корректны, на одной странице нет повторов, ошибок нет; строка могла съехать, и тест это записывает как принятое. `TestQueuePageBudget` (`IM_MEASURE=1`). `TestQueueCheckContract`.
- [ ] **Step 2: Запуск.** Ожидается FAIL.
- [ ] **Step 3: Реализация.** Индекс `021`: `(customer_guid, state) WHERE deleted_at IS NULL`. `EXPLAIN` на наборе замера записать в `progress.md`. Проверка `CheckQueueOrders` — в сборке `Deps`, где загружается машина. `TestQueueSQLCount`: потолок решения 69.
- [ ] **Step 4: Запуск и коммит.** `-run 'TestQueue'`. `Этап 5а: очередь, порядок и страницы`.

### Task 19: Поиск и сужения

**Files:** изменить `queue_queries.go`, `handler/operator/queue.go`; тест `operator_queue_test.go`.

**Interfaces:**
- Consumes: `hit`, `linkedHits` (`server.js:1024–1025`), `visible` (`:1026–1054`), дерево групп.
- Produces: поля `QueueScope`: `Search string; SourceIDs []uuid.UUID; DeviceTypeIDs []string; Priority *int64; States []string`; `QueuePage.Matched map[uuid.UUID][]MatchedLinked`.

- [ ] **Step 1: Тесты.** `TestQueueSearchNumber`, `TestQueueSearchAlarmNumber`, `TestQueueSearchTypeName`: без учёта регистра, часть строки. `TestQueueSearchEscapes`: `%` и `_` — обычные символы. `TestQueueSearchMatchedLinked`: основной найден по привязанному, `matchedLinked` с его guid и номером. `TestQueueSearchHiddenLinked`: привязанный невидим — основной не найден, номера нет в теле. `TestQueueGroupFilter`: группа — всё поддерево; id не группы считается устройством. `TestQueueCommaFilters`: `eventTypeGuid`, `scenarioGuid`, `deviceTypeId` через запятую, значение `all` не сужает. `TestQueuePriorityState`. `TestQueueNoSQLInjection`: кавычка в поиске.
- [ ] **Step 2: Запуск.** Ожидается FAIL.
- [ ] **Step 3: Реализация.** Параметры SQL, никакой склейки значений. `touches` у сервера — только источник (RULE-85, §19). Заглушка `ListIncidents` уходит.
- [ ] **Step 4: Запуск и коммит.** `-run 'TestQueue'`. `Этап 5а: поиск и сужения очереди`.

## Часть 5. Поток

### Task 20: Лента и запись в транзакции ядра

**Files:** создать `internal/im/service/storing/migrations/020_stream_events.sql`, `internal/im/service/storing/stream_queries.go`, `internal/im/service/stream/feed.go`, `internal/im/appservice/operator/feed.go`, тест `operator_stream_test.go`; изменить `internal/im/service/transition/core.go`, `family.go`, `internal/im/handler/operator/transition.go`, `linked.go`, `merge.go`, `bulk.go`, `internal/im/appservice/operator/deps.go`.

**Interfaces:**
- Consumes: `Result` (`core.go:204–218`), `After` (`:231–235`), `attempt` (`family.go:30–42`), `emitTransition` (`server.js:1222–1235`), `runTransition` (`:1237–1254`, адресат передачи на 1249). `Run`, `RunAll` и `Merge` — проверить, что все три идут через `attempt`; если нет, хук ставится и там.
- Produces: таблица ниже; `Op.InTx func(ctx model.AppContext, r *Result) error`; `stream.Row{ID int64; Customer uuid.UUID; Type string; At int64; Incident *uuid.UUID; Actor string; Audience string; People []string; Payload json.RawMessage}`; `stream.Feed` с методами `Append(ctx, customer, rows []Row) error`, `After(ctx, customer, cursor int64, limit int) ([]Row, error)`, `Last(ctx, customer) (int64, error)`, `Has(ctx, customer, id int64) (bool, error)`, `Trim(ctx, keepRows int, before int64) (int64, error)`; `(*Deps).InTx(op transition.Op) func(model.AppContext, *transition.Result) error`; `(*Store).SetLastTransferTarget`.

```sql
CREATE TABLE stream_events (
    id BIGSERIAL PRIMARY KEY,
    customer_guid UUID NOT NULL,
    type TEXT NOT NULL,
    at_ms BIGINT NOT NULL,
    incident_guid UUID,
    actor TEXT NOT NULL DEFAULT '',
    audience TEXT NOT NULL,
    people TEXT[] NOT NULL DEFAULT '{}',
    payload JSONB NOT NULL DEFAULT '{}'
);
CREATE INDEX idx_stream_events_customer_id ON stream_events (customer_guid, id);
```

- [ ] **Step 1: Тесты ядра.** `TestInTxRunsInsideAttempt`: хук вернул ошибку — ничего не записано, ошибка наружу. `TestInTxNotOnRefusal`. `TestInTxRepeatedOnFamilyChanged`: повтор попытки зовёт хук заново, строки первой попытки откатились (`MemRepo`).
- [ ] **Step 2: Тесты ленты.** `TestFeedRolledBackWithTransition`: откат — строк нет, `NOTIFY` не приходил. `TestFeedOrderIsCommitOrder`: транзакция А вставила и держится, Б стоит на замке, `After` пока пуст; после фиксации А, затем Б: `id` А меньше `id` Б, и читатель видит обе строки по порядку. Плюс 50 параллельных переходов и читатель-хвост: собранное равно всем строкам, ни одна не потеряна. `TestFeedTransitionedPayload`: `transitionId`, `trigger`, `state.from/to`, `owner.from/to`, `addressee`, `breach` как `emitTransition`; `addressedToMe` в строке нет. `TestFeedOneRowPerStep`: `RunAll` на три инцидента — три строки в порядке `Result.Incidents`. `TestLastTransferTargetSavedInTx`: передача сохраняет адресата, отказ и откат — нет; факт `lastTransferTarget` и значение по умолчанию в форме дают его. Поле берётся по `source: transferTargets` формы перехода, а не по имени `targetId`.
- [ ] **Step 3: Запуск.** Ожидается FAIL.
- [ ] **Step 4: Реализация.** `Append`: `pg_advisory_xact_lock`, `INSERT` всех строк, `SELECT pg_notify('im_stream', $customer)`. Пустой список — ничего, и замка тоже нет. Заменить записи в журнал на `transition.go:162`, `linked.go:166`, `merge.go:167`. `Op.InTx` заполняют все места вызова ядра: `runOne`, `runAllLinked`, `runMerge`, выборка, `SessionMoves`. Комментарий к `Result.After` обновить: разбирается в транзакции, доставляется после фиксации. Метка STAGE5 решения 59 уходит.
- [ ] **Step 5: Запуск и коммит.** «Без базы», `-run 'TestInTx|TestFeed|TestLastTransferTarget|TestFlow'`. `Этап 5а: лента в транзакции ядра, After в одном месте`.

### Task 21: Остальные источники событий

**Files:** изменить `internal/im/appservice/operator/feed.go`, `touch.go`, `session.go`, `internal/im/service/intake/service.go`, сборку `AppServices`; тест `operator_stream_test.go`.

**Interfaces:**
- Consumes: `After` с действиями `notify`, `evict`, `touch` (`effects.go:249–270`), `deliver`, `onBreachShared`, `onEvict` (`server.js:336–353`), слияние (`:1265–1295`), `TouchAfterMerge` (`touch.go:17–52`), `create` (`intake/service.go:138`).
- Produces: `intake.Feed` (необязательная зависимость, `nil` у старых тестов); таблица ниже.

| Откуда | Тип | Аудитория | Деталь |
|---|---|---|---|
| `notify` c `Alert` | `incident.alert` | `people`: получатели | актор `dispatcher`, `payload.transitionId` |
| `notify` c `About` | `incident.sibling_closed` | `people`: получатели без того, кто закрыл | `incident` — инцидент получателя, актор — закрывший, `payload` как `server.js:338` |
| `evict` | `incident.card_evicted` | `people`: `Who` | только если у него открыт этот инцидент (`open_incident_guid`); актор `By`, `payload.transitionId` |
| `touch` | `journal.appended` | `visible` | актор шага или `dispatcher` |
| `TouchAfterMerge` | `incident.updated` | `visible` | `payload.stepIds: []`, в транзакции дописывания версий, поэтому после новой версии; только если основного не взяли шагом слияния |
| `create` интейка | `incident.created` | `visible` | последним шагом `create` |
| `setAgentState` | `session.agent_state_changed` | `people`: сам | `payload.agentState`, после системных переходов |

- [ ] **Step 1: Тесты.** `TestFeedAlertRecipients`, `TestFeedSiblingClosedNeverCloser`, `TestFeedEvictOnlyIfOpen`: открыт другой инцидент — строки нет, свой перерыв и выход — строки нет. `TestFeedTouchIsJournalAppended`. `TestFeedMergeOrder`: сначала переходы присоединённых, затем взятие основного или `incident.updated`. `TestFeedUpdatedAfterVersion`: при чтении строки `incident.updated` версия уже новая. `TestFeedCreatedOnIntake`: откат транзакции вызывающего — строки нет. `TestFeedAgentStateOrder`: при выходе — переходы, затем `session.agent_state_changed`; повторить проверку `tests/api-scenarios.js:638`: передача, затем «адресат вышел». `TestFeedNoEventOnSameState`.
- [ ] **Step 2: Запуск.** Ожидается FAIL.
- [ ] **Step 3: Реализация.** `command` остаётся `External` и в ленту не идёт. Срабатывает `SessionMoves` с `Op.InTx`.
- [ ] **Step 4: Запуск и коммит.** `-run 'TestFeed|TestFlow|TestIntake'`. `Этап 5а: все источники событий ленты`.

### Task 22: `Hub`: пробуждение и обрезка

**Files:** создать `internal/im/service/stream/hub.go`, `hub_test.go`; изменить `internal/im/appservice/appservice.go`, `cmd/im/main.go`; тесты `operator_stream_test.go`.

**Interfaces:**
- Consumes: `pgx.Connect`, `(*pgx.Conn).WaitForNotification`, `Feed`, строка подключения из `model.Config`.
- Produces: `stream.NewHub(cfg HubConfig, feed Feed, logger) *Hub`; `HubConfig{URL string; Poll, TrimEvery, RetryMin, RetryMax time.Duration; KeepRows int; KeepFor time.Duration; Now func() int64}`; `(*Hub).Start(ctx)`, `Subscribe(customer uuid.UUID) (<-chan struct{}, func())`, `Stop()`, `Done() <-chan struct{}`.

- [ ] **Step 1: Тесты.** `TestHubWakesOnCommit`: подписчик проснулся не позже 1 с при `Poll` = 1 мин. `TestHubCoalesces`: 1000 `Append` без чтения — подписчик не блокирует `Hub`, канал ёмкостью 1. `TestHubOtherCustomerSilent`. `TestHubCatchesUpAfterListenDrop`: `pg_terminate_backend` слушающего соединения, запись в окне обрыва — подписчик просыпается после восстановления и строка находится; отдельно случай, когда соединение живо, а `NOTIFY` потерян: подмена даёт только опрос, просыпается по `max(id)`. `TestTwoHubsSeeOneFeed`: два `Hub` на одной базе, запись идёт как от первого экземпляра, просыпается подписчик второго. `TestTrimKeepsBothLimits`: 2000 старых — осталось 1000; 2000 свежих — все; 500 старых — все. `TestHubStopClosesDone`.
- [ ] **Step 2: Запуск.** Ожидается FAIL.
- [ ] **Step 3: Реализация.** Решение 90. `pgx` отдельным соединением: пул 16 трогать нельзя. Значения по умолчанию: `Poll` 5 с, `TrimEvery` 60 с, `RetryMin` 1 с, `RetryMax` 30 с, `KeepRows` 1000, `KeepFor` 1 ч. Тесты без `Hub` его не запускают: фоновые запросы исказили бы счётчик.
- [ ] **Step 4: Запуск и коммит.** `-run 'TestHub|TestTwoHubs|TestTrim'`. `Этап 5а: Hub, пробуждение и обрезка ленты`.

### Task 23: Обработчик потока и медленный клиент

**Files:** создать `internal/im/handler/operator/stream.go`, `internal/im/handler/test/stream_helpers_test.go`; изменить `stubs.go`, `internal/im/handler/handler.go`, `internal/im/appservice/operator/deps.go`, `cmd/im/main.go`; тесты `operator_stream_test.go`.

**Interfaces:**
- Consumes: `Hub`, `Feed`, `AuthenticateUser` (`handler/v1/auth_middleware.go:102–118`), `GetHandler` (`internal/im/handler/handler.go`), сервер и остановка (`main.go:64–79`), `subscribe` (`server.js:1162–1174`).
- Produces: `OpenEventStream`; `streamConfig{Batch int; WriteTimeout, Ping, Reauth time.Duration; BuildSlots, PerUser int}`; `rawWriter(c *gin.Context) http.ResponseWriter`; помощник тестов `streamClient` с `next(t, timeout)`, `nextOfType`, `raw()`.

- [ ] **Step 1: Помощник.** `streamClient`: настоящий сокет через `httptest.Server`, разбирает кадры SSE, запоминает `id`, умеет не читать (`pause`) и закрываться.
- [ ] **Step 2: Тесты.** `TestStreamHeaders`: `text/event-stream`, `Cache-Control: no-cache`, `X-Accel-Buffering: no`, строки `event:` нет. `TestStreamNeedsAuth`: `401` как `Problem`. `TestStreamPing`: пустой комментарий по таймеру (в тесте 50 мс). `TestStreamIsNotActivity`. `TestStreamThroughGetHandler`: через настоящий `handler.GetHandler` с декоратором go-util дедлайн записи ставится, без ошибки `ErrNotSupported`. `TestSlowClientClosedNotBuffered`: клиент не читает, сокет с маленьким буфером, 20000 строк в ленте — соединение закрыто не позже дедлайна + 1 с; прирост кучи (`runtime.ReadMemStats` после `GC`) меньше 2 МБ; в момент ожидания записи занятых соединений пула нет; после возврата с `Last-Event-ID` пришло всё, порядок сохранён. `TestStreamConnectionCap`: девятое соединение пользователя закрывает самое старое. `TestStreamReauthClosesExpired`: подмена `AuthenticateUser` даёт ошибку — поток закрыт. `TestStreamBuildSlots`: 20 потоков, не больше 8 сборок разом. `TestShutdownClosesStreams`: `Stop` закрывает, `server.Shutdown` успевает меньше 10 с. `TestStreamClientGoneFreesEverything`: клиент ушёл — подписка снята, горутина кончилась (`goleak` нет в зависимостях, проверка через счётчик подписок и `runtime.NumGoroutine` с ожиданием).
- [ ] **Step 3: Запуск.** Ожидается FAIL.
- [ ] **Step 4: Реализация.** Решения 91, 92. Значения: `Batch` 100, `WriteTimeout` 10 с, `Ping` 15 с, `Reauth` 60 с, `BuildSlots` 8, `PerUser` 8. `ctx` запроса отменяется при разрыве. Сборку сообщения пока делает `render(v, rows)` с нейтральными полями, Task 24 его доделает. Соединение БД не удерживается во время записи в сокет: чтение пачки закончено до записи. `main.go`: `server.RegisterOnShutdown(s.Hub.Stop)`, `WriteTimeout` не задавать. Если `SetWriteDeadline` вернул ошибку — поток не открывается, `500` и запись в журнал: без дедлайна медленный клиент держал бы горутину вечно.
- [ ] **Step 5: Запуск и коммит.** `-run 'TestStream|TestSlowClient|TestShutdown'`. `Этап 5а: обработчик потока, медленный клиент, остановка`.

### Task 24: Сообщение глазами получателя, видимость, сброс

**Files:** создать `internal/im/handler/operator/stream_render.go`; изменить `stream.go`; тесты `operator_stream_test.go`.

**Interfaces:**
- Consumes: `summaries` (Task 16), `VisibleAmong`, `Deps.ActorName`, `IncidentStreamEvent` контракта, `emit` (`server.js:1134`).
- Produces: `render(ctx, v *viewer, rows []stream.Row) ([]frame, error)`; `frame{ID int64; Data []byte}`, у кадра без данных пустой `Data`; `startCursor(ctx, customer, lastID string) (cursor int64, reset bool, err error)`.

- [ ] **Step 1: Тесты.** `TestStreamHidesInvisibleIncident`: у получателя нет доступа — ни сообщения, ни `id` инцидента, ни номера в байтах потока; завершающий кадр только с `id: n`; следующий видимый приходит; после переподключения с этим `id` сброса нет. `TestStreamAccessLostBeforeDelivery`: доступ снят после записи строки, до чтения пачки — сообщения нет. `TestStreamSiblingHiddenNumber`: `sibling_closed` не раскрывает невидимого соседа. `TestStreamHidesInvisiblePrimary`: `linkedTo` как в Task 15. `TestStreamPersonAudience`: `session.agent_state_changed` только себе, `incident: null`. `TestStreamPeopleAudience`: чужой не получает алерт. `TestStreamAddressedToMe`: `true` у адресата, `false` у остальных, из одной строки. `TestStreamActorName`: имя берётся при доставке, пустое имя — id. `TestStreamSummaryIsCurrent`: повторная доставка после закрытия: `payload.state` прежний, `incident.state` текущий. `TestStreamOneSummaryPerBatch`: десять строк о том же инциденте — одна сборка сводки. `TestStreamLanguage`: `viewer.locale` из настроек.
- [ ] **Step 2: Тесты сброса.** `TestStreamResetWhenHistoryTrimmed`: `Last-Event-ID` обрезан — первое сообщение `stream.reset`, ровно одно, `id` равен последнему на сервере; следующая запись приходит. `TestStreamResetBadID`: не число, отрицательное, больше конца — то же. `TestStreamResendAfterID`: со следующей после данной, строки между не теряются. `TestStreamNoIDStartsAtEnd`: старое не приходит. `TestStreamEmptyFeed`: пустая лента, без заголовка — только пинги, новая строка приходит.
- [ ] **Step 3: Запуск.** Ожидается FAIL.
- [ ] **Step 4: Реализация.** Решения 88, 89, 93. `at` в RFC3339 как в остальном API. `summaries` на все инциденты пачки разом, отсутствующие — как невидимые. `v` переобновляется при `Reauth`.
- [ ] **Step 5: Запуск и коммит.** `-run 'TestStream'`. `Этап 5а: сообщения потока, видимость при доставке, сброс`.

### Task 25: Два оператора: уровни А и Б

**Files:** изменить `handler/test/operator_stream_test.go`, `stream_helpers_test.go`, `operator_contract_test.go`.

**Interfaces:**
- Consumes: `f.operator`, `o.grant`, `o.on`, `streamClient`, `checkContract`, схема `IncidentStreamEvent`.
- Produces: `checkStream(t, raw []byte)`: формат SSE и схема каждого сообщения.

- [ ] **Step 1: Сверка с контрактом.** `checkStream` в `streamClient`: каждая строка — комментарий, `id:` или `data:`; `data` — одна строка JSON; `event:` нет; схема `IncidentStreamEvent` через `openapi3.Schema.VisitJSON`; тип из перечня; у `stream.reset` есть `id`. Включена для всех тестов потока. Проверка, что тест умеет падать: подмена со строкой `event:` и с лишним типом даёт ошибку (`TestCheckStreamCatchesBadFrame`).
- [ ] **Step 2: Уровень А.** `TestTwoOperatorsSeeEachOther`: операторы А и Б разных пользователей, оба `ready`, оба с доступом, оба в потоке. А берёт инцидент — Б видит `incident.transitioned` с `owner.to`, карточка Б уже новой версии, без единого его запроса. Б открывает, А передаёт Б — у Б `addressedToMe: true`. Б принимает — А видит. А уходит на перерыв — Б видит отложенный инцидент, но не видит состояния А. Берёт чужой — у владельца `incident.card_evicted`, если карточка открыта через heartbeat.
- [ ] **Step 3: Соседние потоки.** `TestStreamMergeBetweenOperators`: слияние, `incident.updated`, у второго версия новая и `412` при старой. `TestStreamIntakeReachesOperators`: `incident.created` через интейк. `TestCounterRefreshAfterEvent`: после события `getQueueCounters` без задержки верен: запись закрыта до доставки. `TestReconnectWithoutLoss`: разрыв на середине потока переходов, возврат с `Last-Event-ID`, все события один раз.
- [ ] **Step 4: Замер.** `TestStreamFanoutBudget` (`IM_MEASURE=1`): 20 потоков, одно событие — всем за ≤ 1 с. Результат записать в итог, он покажет запас для этапов 8–9.
- [ ] **Step 5: Запуск.** `-run 'TestTwoOperators|TestStream|TestCheckStream|TestReconnect|TestCounterRefresh'` и один весь пакет с `-timeout 40m`.
- [ ] **Step 6: Коммит.** `Этап 5а: два оператора видят друг друга, уровни А и Б`.

### Task 26: Стенд: уровни В и Г

Без коммита в сервер: скрипты стенда лежат вне репозиториев.

**Files:** создать `~/Work/stand/check-operator-stream.sh`, `~/Work/stand/two-windows.html`, `~/Work/stand/ui-check/check-two-windows.mjs`; изменить `~/Work/stand/check-operator-api.sh`, `check-operator-transitions.sh`; IM: `research/integration/30-local-stand.md`.

**Interfaces:**
- Consumes: `run-im-server.sh`, `SECOND_EMAIL`, `SECOND_PASS_FILE`, `bin/agent-emulator replay --limit 1 --run <метка>`, `ui-check/lib.mjs`, шлюз с `proxy_read_timeout 1h`.
- Produces: скрипты с итогом `OK` и `SKIP` с причиной.

- [ ] **Step 1: Дамп.** Команда из Global Constraints. Файл не пуст: `test -s ~/Work/stand/backup/imdb-before-019.sql`. Без него дальше не идти.
- [ ] **Step 2: Перезапуск.** Собрать сервер, `run-im-server.sh`, миграции 019–021 применились (таблица `im_db_migrations`), ответы `/operator/session` есть.
- [ ] **Step 3: Старые скрипты.** Первым шагом `PUT agent-state ready` (решение 76). Ожидается как раньше: `check-operator-api.sh` OK 16 плюс новые, `check-operator-transitions.sh` OK 24 / SKIP 3.
- [ ] **Step 4: Новый скрипт.** Две `curl -N` через шлюз с настоящим токеном `test@axxonnet.test`. Проверки: событие приходит меньше чем за 2 с (нет буферизации); пинг приходит за 20 с; `X-Accel-Buffering`; повтор по `Last-Event-ID`; сброс при выдуманном `id`; `agent-emulator` даёт `incident.created`. SQL напрямую не использовать.
- [ ] **Step 5: Разные пользователи.** Файл `SECOND_PASS_FILE` есть и режим 600 — вход и обмен событиями, `OK`. Нет файла, вход не прошёл, нет права или правила — `SKIP` с причиной. Содержимое файла не печатать, искать пароль в другом месте нельзя.
- [ ] **Step 6: Браузер.** `two-windows.html`: `fetch` с `Authorization` читает поток, две кнопки действий. `check-two-windows.mjs`: два контекста, без перезагрузки. Только при наличии файла, иначе `SKIP`.
- [ ] **Step 7: Документ и коммит IM.** В `30-local-stand.md` шаг про миграции, скрипт потока и итог. `python3 tools/check_links.py`. Коммит IM: `Этап 5а: стенд — проверка потока`.

### Task 27: ADR, документы, итоговый прогон

**Files:** сервер: `docs/adr/002-operator-api-package.md`, `docs/adr/005-transitions-in-transaction.md`. IM: `research/integration/40-plan.md`, `56-plan-stage5.md`.

**Interfaces:** нет.

- [ ] **Step 1: ADR-005.** «Carried to stages 5-7»: закрытые пункты убрать, числа «было» и «стало» записать, что осталось на 5б и 6 назвать. Записать хук `Op.InTx`, порядок ленты и почему замок.
- [ ] **Step 2: ADR-002.** Пункты 13 (закрыт контрактом), решения о `viewer.locale`, о памяти `Directory`, о начальном состоянии; пункты 10, 12 — ссылка на 5б.
- [ ] **Step 3: `40-plan.md`.** Этап 5 разделён на 5а и 5б, оценка L, что сделано и как проверен критерий.
- [ ] **Step 4: Итоговый прогон.** `source ~/go/offline-env.sh && go test -race $(go list ./internal/im/... | grep -v /handler/test) && make test-local 2>&1 | tail -15 && go vet ./... && gofmt -l internal/im && golangci-lint run ./...`. Заглушки: `grep -c '^func (h \*Handler) [A-Z]' internal/im/handler/operator/stubs.go` даёт 32 (было 38). IM: `python3 tools/build_workflow.py --check && python3 tools/check_links.py`. Замеры: все строки решения 69 — в итог.
- [ ] **Step 5: Итог.** Раздел «Итог этапа 5а» в этом файле: уровни, цифры, принятые по ходу решения с ценой, что `SKIP` и почему. Коммиты сервера и IM. Push только по просьбе.

## Не в этом этапе

| Что | Почему | Куда |
|---|---|---|
| `filterIncidents`, `resolveSelection` | критерию не нужны, нужны экрану; строятся на классах и `accessRuleMatch` из 5а | 5б |
| идемпотентность в PostgreSQL: клиент в ключе, предел длины ключа, предел записей, ожидание между экземплярами, сбой между фиксацией и сохранением | один экземпляр в 5а работает на памяти, а смена хранилища — отдельная работа с лизой | 5б |
| слой `deps.go` → `handler/operator/idempotency` (строка 8) | чинится переносом пакета вместе с хранилищем | 5б |
| дерево групп на втором экземпляре (ADR-001: шина в памяти процесса) | на одном стенде не видно, проверять вместе с запуском двух экземпляров | 5б |
| запуск двух экземпляров на стенде | лента и `Hub` проверены тестом, остальное ждёт идемпотентности | 5б |
| значение `limits.maxBulk` | правило машины, менять без пользователя нельзя; мерить после 5а, предложение 200 в открытом вопросе 6 | решение пользователя |
| метки `STAGE7` в `world.go`, `reference.go` | группы, состав, люди из облака — этап 7, метки остаются | 7 |
| состояние при бездействии: `system_hold_idle`, `system_release_idle` | нужен планировщик | 6 |
| `macro.completed` | нет макросов | 6 |
| `incident.access_lost` | в прототипе только тестовый маршрут (`server.js:2065`), отслеживать смену правил доступа негде до планировщика | 6–7 |
| `schema_published`, `priorities_changed` | конфигуратор пока не даёт события; аудитория `all` готова | 7 |
| журнал действий оператора §12.4 | так в `40-plan.md` | 6 |
| адресаты передачи из настоящего источника, удалённые люди | облако не отдаёт список, решение пользователя | 7 |
| `countMine` вне семьи, превышение предела на единицу, вариант с `pg_advisory_xact_lock` на операторе | известный предел ADR-005, пункта о смене решения нет | по слову пользователя |
| вход и токены в `api.js`, `EventSource` с заголовком, CORS | отложено пользователем и этапом 7 | по слову пользователя, 7 |
| предел тела запроса и тайм-ауты сервера | решение пользователя; поток не должен иметь `WriteTimeout` | по слову пользователя |
| площадка и место в поиске, `Role`, `AvailabilityLabel` | данных нет | 7 и дальше |

## Набросок 5б

Около 10 задач, свой план с решениями от следующего номера. Здесь только направление, а не обязательства.

1. `filterIncidents` (`FilterRequest`, `FilterResult`, `filterView`, `server.js:775–856`): считается на классах и видимости без строк, значения из таблиц.
2. `resolveSelection`: `all_in_filter` и `explicit`, `truncated`, `actions` (`selectionActions`, `sharedForm`). Здесь варианты людей снова нужны, `RowForm` не ставится.
3. Перенос пакета в `internal/im/service/idempotency`: снимает обратную зависимость `deps.go:8`.
4. Таблица `idempotency_keys`: ключ из клиента, пользователя, метода, пути и значения; состояние, статус, заголовки, тело, срок лизы.
5. Захват через `INSERT … ON CONFLICT DO NOTHING`, ожидающие опрашивают с отступом, продление лизы, истечение.
6. Длина ключа 200 → `400`, предел 1000 записей на пользователя, чистка без O(n) на запрос.
7. Сбой между фиксацией и сохранением: принять и закрепить тестом (повтор получает `412` или отказ, второго действия нет, кроме `If-Match: *` на петле).
8. Дерево групп на всех экземплярах: `NOTIFY im_tree` рядом с лентой.
9. Два экземпляра на стенде и `People` по ответу на открытый вопрос 2.
10. Замер выборки, `maxBulk`, ADR, итог.

## Решения этого плана — обоснования

- **66.** `Load` стоил 15,6 мс на инцидент из-за одного запроса видимости. Сравнение клиента — в SQL, потому что `GetIncidentByUserGroupIDs` клиента не проверяет, и проверка в Go на наборе означала бы лишнее чтение. Условие одно, иначе очередь и карточка разойдутся.
- **67.** ADR предлагал память по людям и тройкам. Сама по себе память снимает только повторы: при разных камерах у привязанных остаётся люди × строки. Матрица одним запросом снимает это в худшем случае и не заводит второго описания правил в Go.
- **68.** `viewScope` читал семью в трёх местах. Обёртки сохранены, чтобы не трогать тесты 4б. Память кандидатов безопасна, так как запись — последний шаг, а черновик накладывается поверх.
- **69.** Бюджеты взяты примерно втрое ниже секунды: `Selects` даст обычно 15–25 запросов. Равенство важнее времени: время шумит, а равенство нельзя тихо испортить. Числа подлежат уточнению первым замером, но не в сторону секунды.
- **70.** Ревью не мерило удержание блокировки, а именно оно задерживает других операторов. Память доступа живёт на запрос: права не зависят от записей ядра. Кандидаты зависят, поэтому живут попытку.
- **71.** Строка, удалённая в окне, — обычная гонка чтения, а не ошибка сервера.
- **72.** Проверка до блокировки — проверка устаревшего. Только `lock` видит правду; `Expect` не подходит, версия связи не выражает.
- **73.** Варианты людей у строки — единственный источник рядов × людей в CPU, а на этапе 7 людей станут сотни. Справочные поля дешёвые, и клиент с тестами их читает (`api-scenarios.js:781, 874`), поэтому их не убираем. Передача доступна из строки (`ui.surface` содержит `queue`), значит клиенту нужно дочитать карточку: это одна асинхронная ветка в `openDialog`. Вариант «посчитать всё по памяти» SQL бы не дал, но байты и CPU на каждую строку и на каждое событие потока остались бы.
- **74.** Контракт меняется один раз на план, поэтому все его долги собраны вместе. Ключ `maxLength` входит сюда же, чтобы 5б не открывал контракт.
- **75.** Пользователь решил про адресатов до этапа 7, это не пересматривается. Общим становится то, что нужно планировщику этапа 6: состояние, молчание, права по id. `People` остаётся в памяти как есть, ограничение закреплено тестом.
- **76.** Правила и машина говорят одно, фикстура прототипа — демонстрация. `ready` по умолчанию сделал бы выход бессмысленным: следующий запрос вернул бы состояние. Выход на линию в клиенте уже есть. Цена — правки помощников и двух скриптов стенда.
- **77.** Часы клиента в расчёт не входят вовсе. `GREATEST` страхует от разницы часов двух экземпляров и от сдвига `TestClock`.
- **78.** Правила не меняют состояние по молчанию: перевод делают только инциденты через планировщик. Менять здесь значило бы придумать правило.
- **79.** Порядок проверок виден оператору и закреплён `tests/api-scenarios.js`. Условный `UPDATE` закрывает две вкладки.
- **80.** Планировщик — этап 6, но перерыв и выход без своих переходов нарушают §12.2 и §8.1. Отдельные транзакции, потому что каждый инцидент — своя семья. Сбой не отменяет выход человека.
- **81.** Язык уже хранится в настройках клиента, отдельного поля не нужно. Параметр дешевле снимка в глобальном месте, хотя затрагивает 63 места.
- **82.** §5 разрешает номер тревоги и запрещает показывать соседа по номеру, а план 55 в Review Focus запрещал раскрытие. `null` у `linkedTo` честнее guid: guid дал бы ссылку на `404`. Отсоединять такой инцидент оператор и так не может: маршрут требует видимого основного. Символ `—` не требует новых строк в каталоге.
- **83.** Перевод фильтров в SQL дублировал бы правило. Классов немного: состояния × владельцы, это десятки. Ограничение: выражения читают только поля класса, это держит сверочный тест.
- **84.** Выражения `queueSort.keys` в SQL не переводятся автоматически, а сортировка в памяти означала бы чтение всех строк. Сверочный тест удерживает перевод. Проверка на старте не даёт разойтись тихо.
- **85.** Смещение проще курсора, контракт уже такой, клиент обновляет страницу по потоку. Съехавшая строка — принятая цена.
- **86.** Запись после фиксации потеряла бы событие при сбое. Хук внутри — единственная точка, через которую проходят все виды операций, и он же решает сворачивание `After` перед уведомлениями. Строить его отдельно от After означало бы делать работу дважды.
- **87.** `BIGSERIAL` выдаёт номер до фиксации, и курсор мог бы перескочить строку медленной транзакции. Альтернатива с `txid_snapshot_xmin` не держит замка, но долгая транзакция задержит весь поток, и два поля вместо одного. Замок берётся на доли миллисекунды в конце транзакции.
- **88.** Сводка в ленте устарела бы и закрепила бы взгляд чужого человека. Цена — сборка на получателя, её считает `TestStreamFanoutBudget`.
- **89.** Проверка при записи не знает, кто подключится, а права меняются.
- **90.** `LISTEN` в пуле привязал бы соединение. `NOTIFY` теряется при обрыве, поэтому он только ускоряет, а не несёт данные. Опрос дешёв: один `max(id)` по индексу.
- **91.** Очередь на соединение и есть рост памяти. Курсор в ленте заменяет её полностью. Дедлайн 10 с покрывает мобильную связь, а реальный обрыв всё равно лечится повтором по `Last-Event-ID`.
- **92.** Проверено по коду go-util и gin: `Unwrap` есть только у gin, и он упирается в декоратор. Модуль менять нельзя.
- **93.** Кадр без данных разрешён форматом SSE: браузер обновляет последний `id` и не создаёт события. Без него получатель, у которого последние строки ленты чужие, после обрезки получил бы ложный сброс.

## Открытые вопросы

Работа их не ждёт: у каждого есть значение по умолчанию.

1. **Начальное состояние.** По умолчанию `offline`, как §12.1 и машина; оператор сам выходит на линию. Иначе первый вход сразу `ready`, правится одна строка миграции и решение 76, но выход перестаёт что-то значить.
2. **`People` в памяти процесса.** По умолчанию оставлено решение пользователя: на втором экземпляре список адресатов другой, после перезапуска пуст. Чтение из `operator_sessions` — правка одной функции `SharedDirectory.People`, смысл «кого сервер видел» не меняется; можно сделать в 5б, если пользователь разрешит.
3. **Невидимый основной.** По умолчанию `linkedTo: null`, номер `—`. Альтернатива: guid оставить, скрыть только номер, тогда клиент покажет ссылку, ведущую на `404`.
4. **Строка очереди без вариантов людей.** По умолчанию контракт и `app.js` меняются. Альтернатива: варианты оставить, контракт не трогать, платить CPU и байтами на строку и на событие потока, что станет заметно на этапе 7.
5. **Бюджеты решения 69.** Предложены мной. Цель пользователя «заметно меньше секунды» выполнена с запасом; другие числа меняются в одной таблице.
6. **`limits.maxBulk`.** Сейчас `null`, 2000 случайных id стоили 26 с. Предлагается 200 после замера в 5б, правкой машины.
7. **Счётчики на больших объёмах.** `done` и `all` идут по всем закрытым инцидентам на каждый запрос. Если на 20000 бюджет не сойдётся или база вырастет в десятки раз, нужна сводная таблица по классам. По умолчанию её нет.
8. **Файл `~/Work/stand/second-operator.pass`.** Без него уровни В и Г для разных пользователей дают `SKIP`. Создаёт только пользователь, с правом `incident:accept` и правилом доступа.
