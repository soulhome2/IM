# Карта нагрузки рабочего места оператора (агент К)

- **Дата:** 2026-11-09. Сервер `c3d6b33`, клиент `51226ca` (ветка `feature/im_operator`), бинарь стенда `~/Work/stand/bin/im-events`.
- **Прогон:** `load.py 10 60` (два оператора, 10 мин, пачка событий раз в 60 с), 23:04:22–23:14:22 (+05). Одновременно в headless Chrome было открыто рабочее место оператора (`/im/operator/`, пользователь dev-login), сеть записывалась puppeteer.
- **Источники цифр:** журнал Postgres (`log_min_duration_statement = 0` на время прогона), журнал сервера `~/Work/stand/im-server.log` («completed handling request», поле `took`), запись сети браузера, итог `load.py` (`~/Work/stand/load/out/load-20261109-230422/`).
- Скрипты и сырые данные — в scratchpad сессии: `cap.mjs` (сеть браузера), `pglog.py` (свод журнала Postgres), `net.jsonl`, `pg.log`.

Оптимизаций здесь нет — только что и сколько.

## 0. Главное в пяти строках

1. **Одна выборка даёт 95 % времени базы:** `QueueClasses` (`storing/queue_queries.go:31`, `queueClassesSQL`) — группировка всех ~970 тыс. инцидентов с `events` и правилами доступа. 752 мс в среднем, 2424 вызова за 10 мин, 1824 с из 1912 с всего времени базы.
2. Её запускают **три вызова API**: список очереди `GET /operator/incidents`, счётчики `GET /operator/incidents/counters` и дерево объектов `GET /operator/reference/source-groups?withCounters=true`. Каждый занимает ~730–750 мс на сервере.
3. Клиент на **каждое чужое событие SSE** (и на каждое своё действие) перечитывает все пять запросов: сессию, очередь, счётчики, дерево и карточку (`useReloadAll`, `state/workplaceStore.ts:261`). Выходит три выборки по 0,75 с на событие.
4. Под нагрузкой двух операторов браузер ждал эти три ответа **в среднем 16–18 с, максимум 30 с**, хотя сервер отвечал за 0,75 с: запросы копятся в очереди. 148 запросов клиент отменил, не дождавшись ответа, но сервер их всё равно посчитал.
5. Переходы (взять, отложить, передать, закрыть) сами по себе быстрые: 22–26 мс на сервере. Тормозят не они, а перечитывание после них.

## 1. Действия оператора → API → база

Время «сервер» — медиана `took` из журнала сервера за прогон. Время «браузер» — медиана в Chrome.

Обозначения запросов к базе (`storing/`):
- **QC** — `QueueClasses` (`queue_queries.go:142`, `queueClassesSQL`): правила доступа + дерево групп (`ClosurePairs` передаётся массивом) + `incidents ⋈ events` всего клиента, группировка по объекту, типу, состоянию, владельцу, группе. **~750 мс.**
- **QP** — `QueuePage` (`queue_queries.go:297`): страница выбранных классов, `array_agg(i.guid)`, сортировка; четыре варианта выражения по порядку сортировки (`1a654129…`, `1240e211…`, `98207284…`, `0daaf3fd…`) и `queueMatched` (`974e4072…`). 3–4 мс.
- **RF** — `ReadIncidentFamily` (`incident_machine_queries.go:166`): семья инцидента через `UNION` (`f906098c…`). 3,9 мс в среднем, максимум 252 мс.
- **LF** — `LockIncidentFamily` (`:157`): то же с `FOR UPDATE` (`0091eade…`). 0,26 мс.
- **VI** — `VisibleIncidentIDs` (`access_queries.go:182`): видит ли пользователь эти инциденты, правила доступа по `i.guid = ANY` (`3faea9eb…`, `2758185e…`). 0,1 мс.
- **MI** — `GetMachineIncidents` и похожие (`incident_machine_queries.go:120…`): по `guid`, `event_guid`, `linked_to`, `owner+state` (`b3b21043…`, `8ef62c41…`, `c79cbe6e…`, `49baa363…`, `d1b3c31f…`). 0,01–0,1 мс.
- **SES** — `operator_sessions`: `OperatorSessions` (`43e7c0d7…`), `TouchOperator` (`f4b782b8…`), `SetOpenIncident` (`60c1cabc…`).
- **REF** — справочники: `sources`, `source_types`, `source_event_types`, `source_groups`, `source_group_memberships`, `scenarios` (по версии), `priorities`, `duty_groups`, `incident_rules`. Каждый 0,01–0,1 мс, но их много (см. §4).
- **J** — `GetJournalEntries` (`incident_journal`, `e151939a…`). 0,03 мс.
- Каждый запрос API проходит `activity` (`handler/operator/activity.go:27`) → `TouchOperator`: одно `UPDATE operator_sessions`.

| Действие | Вызов API | Запросы к базе на вызов | Сколько раз | Время сейчас |
|---|---|---|---|---|
| **Вход** (раз) | `GET /operator/session` | SES (чтение сессии, людей, групп дежурных) | 1 | 3 мс сервер, 7 мс браузер |
| | `GET /operator/workflow/active`, `GET /operator/strings?locale=ru`, `…=en` | нет (машина и строки в памяти) | 1 + 2 | 0,2–5 мс |
| | `GET /operator/reference/priorities`, `/event-types`, `/device-types`, `/transfer-targets`, `/help-links` | REF, по одному запросу | по 1 | 3–10 мс |
| | `GET /operator/reference/scenarios` | сценарии всех версий | 1 | **181 мс** сервер |
| | `POST /operator/session/heartbeat` | VI (открытый инцидент), `SetOpenIncident` | 1 | 3 мс |
| | `GET /operator/incidents?filter=open&page=1&pageSize=8` | **QC** + QP + на каждую строку страницы чтение семьи и прогон машины (RF/MI + REF) | 1 | **748 мс** сервер, 800 мс браузер |
| | `GET /operator/incidents/counters` | **QC** + фильтры машины над классами (в памяти) | 1 | **727 мс** |
| | `GET /operator/reference/source-groups?withCounters=true` | **QC** (`references.go:217`, `sourceCounts`) + дерево групп из памяти | 1 | **733 мс** |
| | Итого вход | 15 запросов к API, три QC | | готово через ~1,1 с после `/session` (без нагрузки) |
| **Очередь в покое** | `POST /operator/session/heartbeat` | VI + `SetOpenIncident` (+ TouchOperator) | раз в 30 с (`session.heartbeatSec` машины, `useHeartbeat.ts:50`) | 3 мс |
| | `GET /operator/stream` (SSE, одно долгое соединение) | на пробуждение: `StreamEventsFrom` (`029fd482…`), затем отрисовка: VI по инцидентам пачки, MI, REF. Пинг раз в 15 с, перепроверка токена раз в 60 с (`stream.go:22–26`) | 1 соединение; пробуждение по `NOTIFY im_stream` и по опросу хаба раз в 5 с | 0,01–0,1 мс на запрос |
| | **Каждое чужое событие SSE** → `useReloadAll` | `GET /operator/session` + `GET /operator/incidents?…&focusGuid=…` + `/counters` + `/source-groups?withCounters=true` + `GET /operator/incidents/{id}` (если открыта карточка; `/linked`, если есть связанные) | под нагрузкой ≈ 1,3 раза в секунду (628 раз за 8 мин) | **три QC на событие**; браузер ждал очередь 18 с, счётчики 16 с (медиана), до 30 с |
| | Опроса по таймеру (`refetchInterval`) нет. `refetchOnWindowFocus: false`, `staleTime: 0` (`api/queries.ts`) | | | |
| **Открыть карточку** | `GET /operator/incidents/{id}` | RF семьи, прогон машины (действия, вид), J, `GetScenariosAtVersions` (`e2aeada6…`), прогоны сценария (`fc472906…`), REF события | 1 | **11 мс** сервер, 16–20 мс браузер |
| | `POST /operator/session/heartbeat` (сразу при смене открытого) | VI + `SetOpenIncident` | 1 | 3 мс |
| | `GET /operator/incidents/{id}/linked?page=…` | только если `linkedCount > 0` (`card/useLinked.ts`) | 0–3 | не замерено (в данных нет связанных) |
| | Открытие карточки само не вызывает `useReloadAll`, но приходящие события продолжают его вызывать | | | |
| **Взять** (`claim`) | `POST /operator/incidents/{id}/transitions/claim` | `pg_advisory_xact_lock`; LF (`FOR UPDATE`); `UPDATE incidents` (`1ed84b38…`); `INSERT incident_journal`, `INSERT operator_actions` (`c06c4185…`); `INSERT stream_events` + `pg_notify`; `set_config('lock_timeout')`; SAVEPOINT; после коммита — догоняющий тик `CatchUp`/`Settle` (`transition.go:177–232`: MI по владельцу и состоянию + DueIncidents по семье), затем карточка в ответе (RF, J, сценарий) | 1 | **22 мс** сервер, 24 мс клиент `load.py` |
| | затем клиент: `useReloadAll` (5 запросов, три QC) + `invalidate selection` | см. «каждое событие» | 1 | ~750 мс без нагрузки |
| **Ответить на шаг** | `POST /operator/incidents/{id}/scenario/answer` (`If-Match`) | `WriteScenarioRun`: `UPDATE incidents SET scenario_result…` (`9eaa3deb…`), `INSERT incident_journal`, `stream_events` | 1 | `load.py` шаги не отвечает; по журналу сервера за день 16 мс медиана, до 1,3 с |
| | затем `GET /operator/incidents/{id}` (`invalidate card`, `useScenario.ts:126`) | как «открыть карточку» | 1 | 11 мс |
| | `PUT /operator/incidents/{id}/scenario/cursor` (переход по шагам назад) | `UPDATE incidents` (курсор) | по клику | не замерено |
| | `useReloadAll` после ответа не вызывается; события SSE от этого ответа у других операторов — вызывают | | | |
| **Отложить** (`hold`), **возобновить** (`resume`) | `POST …/transitions/hold`, `…/resume` | как «взять» | 1 | 23 / 24 мс |
| **Передать** (`transfer`), **принять** (`accept`) | `POST …/transitions/transfer`, `…/accept` | как «взять» + `SetLastTransferTarget` (`f0a88d69…`) | 1 | 26 / 26 мс |
| **Закрыть** (`close`) | `POST …/transitions/close` | как «взять» + закрытие связанных в той же семье | 1 | 22 мс медиана, **максимум 7,9 с** (один раз, см. §4) |
| После любого перехода | клиент: `setQueryData(card)`, `useReloadAll`, `invalidate selection` (`forms/useRunTransition.ts:105–116`) | 5 запросов, три QC | 1 | ~750 мс без нагрузки |
| **Связать** | переход через `POST …/transitions/{id}` с `linkedTo`; разорвать — `DELETE …/linked/{linkedGuid}`, `DELETE …/linked` | как переход, плюс LF по обеим семьям | — | не замерено: `load.py` не связывает |
| **Слить** | `POST /operator/incidents/merge` | `findAll` (RF по каждому), `pickPrimary`, переходы по каждому в одной транзакции | — | не замерено |
| **Отметить строки / массовое действие** | `POST /operator/incidents/selection`, `POST /operator/incidents/transitions/{id}/bulk` | `filterRows` → QC + `FilterClasses`/`FilterPage` (`filter_queries.go`); bulk — переход на каждый | — | не замерено |
| **Окно фильтра** | `POST /operator/incidents/filter` | `FilterClasses` + `FilterPage` (`filter_queries.go:145, 187`) | на смену условий | не замерено |
| **Новое событие от устройства** | `POST /events` (агент) | `agent_api_keys`; REF источника; **`LoadIntakeRules` — три запроса правил на каждое событие** (`intake_queries.go:39`: `6f64af25…`, `700a0e9a…`, `539e1973…`); проверка «есть ли инцидент у события» (MI по `event_guid`); `INSERT events`, `INSERT incidents`, `incident_counters`, `INSERT incident_journal`, `stream_events` + `pg_notify`; `UPDATE events SET processed` | 270 за прогон | **9,5 мс** сервер, до 36 мс |
| | затем у каждого оператора: SSE-событие → `useReloadAll` → три QC | | на каждого подключённого | ~2,2 с работы базы на оператора |

## 2. Фоновые задачи сервера

| Задача | Где | Как часто | Запросы к базе | Время сейчас |
|---|---|---|---|---|
| Тик машины: потеря связи | `appservice/operator/scheduler.go:216` → `MarkLinkLost` (`scheduler_queries.go:239`) | раз в 1 с | `UPDATE operator_sessions … link_lost_ms` (`71f0868a…`) | 0,07 мс |
| Тик: истёкшие таймеры | `DueIncidents` (`scheduler_queries.go:61`) | раз в 1 с | `im_next_due(timers) <= now` по живым инцидентам, `LIMIT 1000` (`3b5bd242…`) | 5,7 мс, максимум 508 мс |
| Тик: инциденты ушедших людей | `PeopleIncidents` (`:77`) | раз в 1 с | инциденты с владельцем в `in_progress, on_hold, pending_acceptance`, чей владелец не `ready` или молчит (`e8923ba3…`) | **66 мс** — вторая по сумме выборка (40 с за 10 мин) |
| Тик: связанные закрытых | `LinkedOfClosed` (`:86`) | раз в 1 с | `state='linked' AND linked_to IN (закрытые)` (`e83d1eb3…`) | 0,02 мс |
| Обход адресатов (sweep) | `AddressedIncidents` (`:93`) | раз в 30 с, страницами по 500 | открытые с владельцем или группой и связанные с ними (`d38a6f27…`) | **206 мс** |
| Переходы тика | `tickOf` → ядро машины | по найденным, до 500 за тик | как переход (LF, UPDATE, журнал, поток) | на этих данных почти нет |
| Сброс активности при старте | `ResetActivity` (`:100`) | при запуске | `UPDATE operator_sessions` | — |
| Хаб потока: опрос | `service/stream/hub.go:299` | раз в 5 с | `SELECT customer_guid, max(id) FROM stream_events GROUP BY customer_guid` (`64d17f5f…`) | 0,24 мс |
| Хаб потока: слушание | `hub.go:223` | постоянно, отдельное соединение | `LISTEN im_stream` | — |
| Хаб потока: чистка | `hub.go:317`, `TrimStreamEvents` | раз в 60 с | `DELETE FROM stream_events …row_number()` (`22e181e7…`), хранит 1000 строк или 1 ч | 0,6 мс |
| Срок хранения (§14.11) | `appservice/operator/retention.go`, `PurgeExpired`, `PurgeAudit` (`retention_queries.go:58, 87`) | раз в час (`Retention: time.Hour`) | удаление пачками старых событий, инцидентов, журналов, аудита | в окно прогона не попал; не замерено |
| Размер аудита | `AuditUsage` (`retention_queries.go:100`) | по запросу конфигуратора | `pg_total_relation_size(...)` | 15 мс |
| Запоминание человека | `Directory.Remember` (`appservice/operator/session.go:462`) | при входе, потом не чаще раза в 10 мин | `INSERT … ON CONFLICT operator_sessions` | 0,06 мс |
| Приём событий | `service/intake/service.go:92` (`Process`) | на каждое событие, синхронно в `POST /events` | см. §1, «новое событие» | 9,5 мс |

## 3. Десять самых дорогих запросов за прогон (по сумме)

Всего по журналу 226 148 выполнений, 1912 с времени базы за 10 мин. Свод: `python3 -I pglog.py pg.log`.

| # | Запрос | Где | Вызовов | Сумма, с | Среднее, мс | Максимум, мс |
|---|---|---|---|---|---|---|
| 1 | Классы очереди (группировка всех инцидентов с правилами доступа) | `QueueClasses`, `queue_queries.go:31` | 2424 | **1824,0** | **752** | 1215 |
| 2 | Инциденты людей, которые не на линии | `PeopleIncidents`, `scheduler_queries.go:77` (тик) | 596 | 39,5 | 66 | 146 |
| 3 | Семья инцидента (`UNION`) | `ReadIncidentFamily`, `incident_machine_queries.go:166` | 6729 | 26,2 | 3,9 | 252 |
| 4 | Обход адресатов | `AddressedIncidents`, `scheduler_queries.go:93` (тик) | 20 | 4,1 | 206 | 247 |
| 5 | Истёкшие таймеры | `DueIncidents`, `scheduler_queries.go:61` (тик) | 596 | 3,4 | 5,7 | 508 |
| 6–9 | Страница очереди, четыре варианта сортировки | `QueuePage`, `queue_queries.go:297` | 693 + 692 + 690 + 222 | 2,8 + 2,7 + 2,3 + 0,7 | 3,2–4,0 | 14,5 |
| 10 | Видимость инцидентов по `guid` | `VisibleIncidentIDs`, `access_queries.go:182` (`2758185e…`, `3faea9eb…`) | 5501 + 4768 | 0,6 + 0,5 | 0,1 | 3,6 |

Ещё заметно, но не в десятке: `GET /operator/reference/scenarios` — 181 мс на вызов (только при входе). Аудит конфигуратора (`operator_actions … GROUP BY person_id` — 469 мс, подсчёт `operator_actions` — 218 мс) — это не рабочее место оператора.

`pg_stat_statements` **не включался**: библиотеки нет в `shared_preload_libraries` (Postgres 9.6.24, расширение 1.4 доступно). Чтобы её включить, нужен перезапуск общего контейнера `ac_db`, на котором работает облако. Вместо неё на время прогона был полный журнал запросов (см. «Что сделано на стенде»). Итог тот же: вызовы, сумма, среднее.

## 4. Расхождения кода с делом

1. **Одна и та же группировка трижды на одно событие.** `QueueClasses` в коде — разные вызовы API (список, счётчики, дерево), но клиент всегда шлёт их вместе (`useReloadAll`). Выходит три одинаковых выборки по 0,75 с с теми же параметрами. По журналу: 2424 QC ≈ 1038 списков + 693 счётчика + 693 дерева.
2. **Отменённые клиентом запросы сервер считает до конца.** Браузер отменил 148 запросов (`failed`: 66 списков, 49 деревьев, 33 счётчика): следующее событие сбросило кэш раньше, чем пришёл ответ. На сервере эти выборки всё равно шли. Это видно по числу QC: их больше, чем ответов, которые получил браузер.
3. **Сервер отвечал за 0,75 с, браузер ждал 16–18 с.** Медианы по журналу сервера: список 748 мс, счётчики 727 мс, дерево 733 мс. В Chrome под той же нагрузкой: 17,9 с, 15,9 с, 16,2 с, максимум ровно 30 с. Догадка: запросы стоят в очереди. Причины могут быть такие: предел соединений браузера на один адрес (одно занято SSE), шлюз облака, слоты базы. Новые события добавляют запросы быстрее, чем они проходят. Проверить — агенту У (тайминги Chrome: `queued`/`stalled`) и агенту А (пул соединений).
4. **`ReadIncidentFamily` вызывается 6729 раз** — больше, чем любой вызов API (≈ 10 на один список очереди). Догадка: при сборке страницы (`rowsOf` → `LoadMany`, `handler/operator/session.go:258`) и отрисовке событий SSE семья читается по одной строке. Время небольшое (3,9 мс), но максимум 252 мс. Проверить N+1 — агенту А.
5. **Правила приёма читаются заново на каждое событие.** `LoadIntakeRules` — три запроса на `POST /events` (270 × 3), кэша нет. Сейчас это дёшево (0,02 мс).
6. **Новое подготовленное выражение на каждый порядок колонок.** `INSERT INTO incidents` встречается в журнале под ~40 разными именами `stmtcache_…`, `INSERT INTO events` — под ~10, `INSERT INTO incident_journal` — под ~20. Колонки идут в разном порядке, видимо, из обхода словаря в построителе запросов `dat`. Каждый новый порядок — новая подготовка выражения на каждом соединении пула. Проверить — агенту А.
7. **Тик раз в секунду тратит 66 мс на `PeopleIncidents`,** даже когда переходить нечему. За 10 мин — 40 с базы; это вторая по сумме выборка, хотя оператор её не видит.
8. **Закрытие один раз заняло 7,9 с** (`transitions/close`, при медиане 22 мс), `load.py` записал то же (7864 мс). Догадка: ожидание блокировки семьи или пула под тремя QC одновременно. Проверить — агенту Б (`pg_locks`).
9. **`GET /operator/session` перечитывается на каждое событие** вместе с очередью. Это дёшево (3 мс), но таких запросов 628 за 8 мин у одного оператора.
10. **Ожидаемое, но не идёт:** опроса очереди по таймеру нет, как и задумано: только SSE и `useReloadAll`. `GET /operator/incidents/{id}/actions` и `/journal` клиент не вызывает: всё приходит в карточке.
11. **Данные:** у `load.py` очередь берётся `pageSize=100&sort=createdAt` (722–958 мс у клиента), в браузере — `pageSize=8`. Время почти одинаковое: его определяет QC, а не размер страницы.

## Что сделано на стенде

- Дамп перед записью: `~/Work/stand/backup/imdb-before-perf-map-20261109.sql.gz` (430 МБ).
- `ALTER DATABASE imdb SET log_min_duration_statement = 0` на время прогона (23:03–23:41), затем вернул `300`. Проверка: `pg_db_role_setting` → `{log_min_duration_statement=300}`.
- Сервер МИ был остановлен (23:01, до меня). Я запустил его тем же бинарём `~/Work/stand/bin/im-events` через `run-im-binary.sh`. **Сервер оставлен работать** для агентов Б, А и У.
- `load.py` записал в базу ~686 переходов, ~270 событий и инциденты от них. Откат — из дампа выше.
- `pg_stat_statements` не включался (нужен перезапуск общего контейнера).

## Что не удалось проверить и почему

- **Связать, слить, массовое действие, окно фильтра, ответ на шаг, курсор сценария, `/linked`** под нагрузкой не замерены: `load.py` их не делает, а сценарий кликов в браузере для них я не писал. Запросы для этих действий выписаны по коду. Ответ на шаг — по журналу сервера за день (12 вызовов).
- **Покой без нагрузки:** почти вся запись браузера сделана под `load.py` (прогон запустился раньше, чем открылся браузер). Чистый вход без нагрузки — первые ~2 с записи и §1 «вход».
- **Срок хранения** (раз в час) в окно прогона не попал.
- **Время отдельно по каждому вызову API** (какие запросы у одного вызова и в каком порядке) выведено из общего числа вызовов в журнале и из кода, а не из трассировки одиночных вызовов. Одиночная трассировка — работа агента А.
- **Сколько ждали в очереди браузера и где** (§4.3) — догадка, не разложено.
- **Цифры зависят от формы данных.** Почти все инциденты закрыты, у них нет `scenario_result`, нет связанных и слитых. QC группирует закрытые вместе с открытыми, поэтому его цена — от всего объёма, а не от числа открытых. Длинные цепочки слияния увеличили бы RF; крупные `scenario_result` — размер карточки.
- **Разброс:** прогон один (10 мин), а не три. Для QC разброс мал (752 мс в среднем, 1215 максимум, в журнале сервера медиана 727–748 мс). Остальные цифры — медианы сотен вызовов.
