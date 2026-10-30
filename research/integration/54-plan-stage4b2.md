# Этап 4б-2: векторы переходов, «Отсоединить все» и объединение — план работ

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ядро переходов сервера МИ даёт тот же итог, что ядро прототипа, и это доказано: каждый вектор перехода «инциденты + лента мира + действие → инциденты, журнал, действия после фиксации», записанный на ядре прототипа, ядро Go повторяет в памяти и на PostgreSQL; «Отсоединить все» и объединение с «Взять» основного — одной транзакцией. Сначала ядро чинит хвост 4б-1: основной вне семьи — повтор, только если его строка жива.

**Architecture:** Задача 1 чинит в ядре `transition` (4б-1) проверку основного своей строки и даёт `MemRepo` мягкое удаление. В IM ядро прототипа получает два стыка без правил — обратный мост `fromView` и подмену мира `ctx.world`; запись векторов CEL 4а — кадры; `tests/transition-vectors.js` при `tests/api.html?celVectors=1` пишет каждый вызов `run`, `runAll`, `merge`, `create` объекта `IMEngine.create`: список инцидентов, ленту фактов мира (кадром записи 4а) и функций сервера, итог; записи `merged_in*`, которые `server.js` дописывает после ядра, входят в итог с пометкой `server`; отбор идёт при записи. `tools/cel_vectors.mjs` тем же прогоном Chrome собирает и `fixtures/transition-vectors.json`, добавляет синтетику на границах окна и формы, `--check` повторяет векторы на JS. На сервере ядро сначала получает шаги операции на любом инциденте и переходе (окно после дедлайна — у каждого шага, факты и записи «некому» — после всей операции, как у прототипа), затем `RunAll` и `Merge`; объединение блокирует и основного. Тест сверки повторяет каждый вектор на `transitiontest.MemRepo` в порядке вектора, тест с базой — каждый вектор на PostgreSQL против того же ядра в памяти в порядке номеров.

**Tech Stack:** Go 1.27.1, cel-go v0.26.1, PostgreSQL 9.6, testify `require`, golangci-lint v2.14.0; IM — Node 22 (без зависимостей), cel-js 8.0.0, headless Chrome.

**Spec:** [53-plan-stage4b.md](53-plan-stage4b.md) — решения 1–22 (обязательны и здесь), ядро и хранилище, «Итог этапа 4б-1» (что осталось); ADR-005 сервера (`docs/adr/005-transitions-in-transaction.md`), разделы «Known limits and notes» и «Carried to 4b-2 and 4c»; ADR-004 (`docs/adr/004-machine-executor.md`); [52-plan-stage4a.md](52-plan-stage4a.md) — формат и запись векторов CEL; [CEL.md, «Векторы»](../../Specification/Workflow_machine/CEL.md#векторы) — пул, лента, канонический JSON. Образец — `runAll`, `merge`, `mergeCheck`, `applySteps`, `create`, `celWorld`, `writeBack`, `windowBefore`/`windowAfter`, `validateForm`/`candidates` в [prototype/engine.js](../../prototype/engine.js); `mergeIncidents`, `log`, `engineCtx`, `DELETE /operator/incidents/{incidentGuid}/linked` в [prototype/server.js](../../prototype/server.js); загрузка ядра в Node и сравнение `since` — `tools/check_quint_replay.mjs` (строки 74–75, 122, 164–169); запись — `recorder` в [tests/cel-vectors.js](../../tests/cel-vectors.js); лента Go 4а — `internal/im/machine/tape_test.go` (`tapeWorld`, `callKey`, `tapeArg`, `canon`). Сервер — `5af4de4`, IM — `16b9e4d`; ссылки плана на код сверены с ними 2026-10-29 и по ревью плана 2026-10-30 (`internal/im/service/transition`, `internal/im/machine`, `internal/im/service/storing/incident_machine_queries.go`, `prototype/`, `tests/`).

## Global Constraints

- Сервер — `~/Work/incident-manager-server`, ветка `feature/im_operator`, от `5af4de4`. IM — `/mnt/hgfs/VmWareShared/soul2home/IM`, ветка `feature/im_operator`, от `16b9e4d`. Пути в задачах — от корня репозитория задачи. Порядок: задача 1 — сервер; задачи 2–13 — IM; задачи 14–22 — сервер; задача 14 копирует файлы из IM, поэтому начинается только после коммитов задач 2–13 (в `SOURCE` — хэш IM без `dirty`).
- Только локально. Push — только по просьбе пользователя. `~/Work/axxoncloudgo` не менять; кажется, что нужна правка облака, — **стоп, спросить пользователя**.
- Вход отложен; новых маршрутов HTTP нет. Ядро вызывают только тесты и приём события; один вызов ядра — одна транзакция вызывающего или своя (ADR-005, решение 4); несколько вызовов в одной транзакции и REPEATABLE READ — не делать (4в).
- Тесты с базой — только контейнер `im-test-db` (`127.0.0.1:55432`): `make test-local` или `TESTDB='postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable' && IM_TEST_DB_URL=$TESTDB go test …`; база стенда `imdb` — не для тестов. Контейнер не запущен — `sg docker -c "make test-db-up"`. Пакеты без базы — `go test -race $(go list ./internal/im/... | grep -v /handler/test)`.
- Перед любой командой `go` — `source ~/go/offline-env.sh`. Новых зависимостей нет; `go.mod` не меняется. Адрес `npm.itvgroup.ru` недоступен, не использовать. Docker — только через `sg docker -c "…"`.
- `make gen` и `make gen-api-im` не запускать; `make gen-api-operator` — только если копия контракта изменилась (в этом этапе не должна: машина и контракт IM не меняются; копия сервера `6e86123` побайтно равна IM `16b9e4d` — сверено). Сгенерированное руками не править.
- `golangci-lint run ./...` — 0 замечаний в каждой серверной задаче (`funlen` 120 строк / 60 операторов, `dupl` 150); `gofmt -l internal/im` — пусто.
- Тесты — testify `require`, под `-race`. Тесты ядра 4б-1 (`internal/im/service/transition/...`, `internal/im/handler/test`) проходят без правки, кроме названных в задачах. Комментарии в коде и ADR — по-английски; документы IM — по-русски, простыми словами.
- **Правила IM.** Прототип только исполняет машину: правка `prototype/engine.js` — только стыки для записи и повтора (`fromView`, `ctx.world`), правил IM в коде нет; `server.js` не меняется. Машина, правила и `State_rules/CHANGELOG.md` в этапе не меняются; кажется, что нужно, — **стоп, спросить**. Сгенерированные файлы — только своим инструментом (`fixtures/cel-vectors.json` и `fixtures/transition-vectors.json` — `node tools/cel_vectors.mjs --update`). Перед первой правкой IM — `git -C /mnt/hgfs/VmWareShared/soul2home/IM fetch`; есть новое на GitHub — сказать пользователю.
- Быстрые проверки IM после каждой задачи 2–13 (из `CLAUDE.md`): `python3 tools/build_workflow.py --check && python3 tools/check_machine.py && python3 tools/check_machine.py --mutations && python3 -m unittest tools/test_openapi30.py && node tools/check_cel.mjs && node tools/test_cel.mjs && node tools/cel_vectors.mjs --check && node tools/gen_quint.mjs --check && python3 tools/check_links.py`.
- Временные файлы — в scratchpad сессии исполнителя; в командах ниже он `$S` (задать `S=…` в той же строке). Профиль Chrome у `--update` — `--tmp=$S`, не `TMPDIR` (CEL.md, «Векторы»).
- Векторы руками не правятся. Go расходится с вектором — правится Go. Кажется, что неправ прототип (расходится с BACKEND.md или CEL.md, а решения 2 плана 53 об этом нет), — **стоп, спросить**: это новый пункт ревью в IM, а не правка вектора.
- Коммиты. Сервер — один на задачу, сообщение по-русски, начинается с «Этап 4б: », пишется инструментом записи файла в `.git/COMMIT_MSG_STAGE4B` (без heredoc), последняя строка — `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`; `git commit -q -F .git/COMMIT_MSG_STAGE4B`. IM — так же, файл `.superpowers/sdd/54-plan-stage4b2/commit-msg.txt` (папка в `.gitignore`), `git commit -q -F .superpowers/sdd/54-plan-stage4b2/commit-msg.txt`; сообщения начинаются с «Этап 4б: » (PROC-44 закрыт и покрывает векторы CEL, векторов переходов в нём нет — `reviews/2026-10-22/plan.md`, строка PROC-44; второго коммита-отметки нет). Команды Bash — в одну строку. Журнал работ — `.superpowers/sdd/54-plan-stage4b2/progress.md` в IM.

**Решения пользователя (обязательны):** те же, что в плане 53.

**Решения этого плана (обязательны для задач; решения 1–22 — плана 53; обоснования новых — в конце; приняты ведущим 2026-10-30):**

23. **Векторы переходов — отдельный файл** `fixtures/transition-vectors.json` со своим пулом, тем же `machineSha256` и `format: 1`; собирает и проверяет тот же `tools/cel_vectors.mjs` тем же прогоном Chrome (`--update` не удлиняется на второй прогон, `--check` проверяет оба файла).
24. **Запись — обёртка `IMEngine.create`,** как `IMCel.create` в 4а: только ядра исходной машины; `run`, `runAll`, `create` — вектор закрывается на возврате; `merge` — по решению 39.
25. **`since` таймеров сравнивается только у `hold`** (решение 22 плана 53): у `reaction` и `resolution` — `0` с обеих сторон перед сравнением, как `norm` в `check_quint_replay.mjs`. Правило — в формате; его применяют `--check` на JS, `Compare` и `Same` на Go и тест обратного моста `fromView`. Go хранит `since = now`, прототип не меняется.
26. **Лента — на уровне `cel.world`** (кадр перехода в записи 4а собирает вызовы всех вычислений CEL внутри вызова ядра) плюс функции сервера вне `cel.world` с приставкой `ctx.`: `ctx.actorName`, `ctx.progress`, `ctx.stepNumber`, `ctx.shareAnswers`. Варианты поля с `source: transferTargets` (`candidates` в `validateForm` зовёт `ctx.transferTargets(ev)` мимо `celWorld`) — факт `transferTargets` той же ленты. `null` прототипа запись пишет как `""` в аргументах `ctx.*`, в `facts` и в действиях (`ctx.actorName(null)` — `[""]`, пустой владелец и адресат — `""`, нет нарушения — `""`, нет `about` — `""`, у `evict` нет `who` или `by` — `""`): у Go пусто — `""`. Повтор на JS подменяет мир ядра (`ctx.world`) лентой; на Go лента — `transition.World`.
27. **Ожидаемое** — по указанию 1 плана 53: `celView` каждого изменённого инцидента, хвост журнала по инцидентам (`actor`, `at`, `kind`, `templateKey`, `vars`), записи журнала в момент `now` после вызова (`once` меняет подстановки и прежних записей), действия после фиксации по порядку, `external`, `facts`, `canceled`; плюс вызовы сценария внутри транзакции (`setCursor`, `shareAnswers`) по порядку. Что прототип не отдаёт, в вектор не идёт: `canceled` — только у `run` (у `runAll` и `merge` ядро его не возвращает; отменённое видно по записи `timer_overridden` в журнале), `external` у `merge` — только присоединяемых (внешнее основного ядро теряет). Отказ ядра — `refusal` (`why`, `guard`, `notFrom`, `code`, `id` — что есть в ответе прототипа), ничего не изменилось. Ошибка `workflow.error.transition_failed` — `error`: Go должен дать ошибку, текст не сравнивается (решение 3 плана 53). Версий в векторе нет; полей записи журнала `Transition` и `ID` — тоже. Как сравнивать — решение 41.
28. **Пределы отбора:** не больше 20 векторов на `op:name`, не больше 4 на один исход (исход — отказ и его ключ, или набор ключей журнала, видов действий после фиксации и наличие `timer_overridden`); отбор — при записи (решение 40); файл — до 4 МБ; `--check` обоих файлов — до 20 с; `--update` — не дольше 8 минут (было ~6).
29. **Сверка Go — двумя тестами.** `TestTransitionVectors` — ядро на `MemRepo` в порядке списка вектора против ожидаемого (прототип = Go). `TestTransitionVectorsOnPostgres` — то же ядро на PostgreSQL против `MemRepo` в порядке номеров (Go в памяти = Go в базе), сравнение полное по решению 41, в том числе порядок `After`. Сколько векторов зависит от порядка списка — число в логе (открытый вопрос 3 плана 53).
30. **`merged_in*` — в ядре Go:** `Merge` пишет запись основному в той же транзакции, последней (решение 13 плана 53), от `op.Me`, вид — `model.JournalKindOf(op.Me)`, `Transition` — id перехода объединения (`bulk.mode: merge`); присоединённых больше пяти — `merged_in_more {ids, more}`, иначе `merged_in {ids}`; `ids` — номера первых пяти через «, », в порядке `op.IDs`; присоединяемых нет — записи нет (как `server.js`: `else if (others.length)`). Пять — константа `server.js` (`MERGED_IN_SHOWN`), не машины (открытый вопрос 2).
31. **Векторы и база.** У синтетики переходов id инцидентов, `eventGuid` и `scenario` — UUID, у всех инцидентов есть событие: такие векторы можно положить в PostgreSQL. Вектор повторяется только в памяти, если в его пуле: id не UUID; пустой `eventGuid`; `linkedTo` на инцидент вне пула; два инцидента одного события с одним сценарием (`uq_incidents_event_scenario`); инциденты одного события с разными `occurredAt` или `eventType` (в базе это поля события); `number`, который не даёт себя же через `model.FormatIncidentNumber` (`INC-%04d`). Их число по причинам — в логе `TestTransitionVectorsOnPostgres`; у записанных (без `case`) оно должно быть 0, иначе — **стоп, спросить**. Инциденты в базу кладутся в два прохода: сначала строки без `linkedTo`, затем с ним (основной сам не привязан — `mergePrimaryValid`; ссылка на ещё не вставленный инцидент нарушила бы внешний ключ).
32. **Шага самопроверки нет** (подтверждено ведущим 2026-10-30). Запись векторов — инструмент тестов, а не функция прототипа, как запись векторов CEL в 4а; стыки `fromView` и `ctx.world` пользователю не видны (как `store.instance` в 4а). Их проверяют `tools/test_cel.mjs` и неизменные самопроверка и тесты API; шага в `prototype/selftest.js` нет.
33. **Основной вне семьи — повтор, только если его строка жива** (хвост 4б-1, проверка в `operation.lock`, `run.go`, строки 93–100). Своя строка указывает (`linkedTo`) на основного, которого блокировка не вернула: живой (`Candidates(…, "incidentById", [id])` его отдаёт) — `ErrFamilyChanged`, повтор, как сейчас; удалённый (`deleted_at`) или отсутствующий — не ошибка: операция идёт дальше, факты основного не видят (`incidentById` — пусто), дальше решают условия машины. Сейчас удалённый основной даёт `ErrFamilyChanged` три раза.
34. **Шаг операции — на любом инциденте и переходе; окно — у каждого шага; факты и «некому» — после операции.** Как `applySteps`, `runAll` и `merge` в `engine.js`: окно после дедлайна ищется у каждого инцидента шага по переходу его шага (у объединения — у каждого присоединяемого по переходу объединения, у основного — по «Взять»); отметка окна и запись `timer_overridden` — у всех до первого шага; записи `emptyLog` всех шагов — после всех шагов, в порядке действий `notify`; `Facts` (`From` — до операции, `To` — после всех шагов, до окна после) — после всех шагов; окно после — у всех после этого, в порядке шагов, и его собственные действия (`recordBreach` и «некому» в нём) идут сразу, как `done.after` в `windowAfter`. У `Run` и `Create` (один шаг) итог тот же, что в 4б-1.
35. **Объединение блокирует основного:** `Merge` вызывает `LockFamily` с присоединяемыми и `op.PrimaryID` (это `form.primaryId` шага объединения). Иначе основной не в семье — записи эффектов ему (`tightenPrimaryDeadline`, `copyAnswersToPrimary`, шаг «Взять») дают `ErrFamilyChanged` три раза, а `linked_to = основной` берёт у его строки `FOR KEY SHARE` вне порядка номеров — риск `40P01`.
36. **`MemRepo.DoInTx` не вложенный — так и остаётся.** В 4б-2 вложения нет: `RunAll` и `Merge` — одна операция с одним `retry`, как `Run`; путь «ядро в транзакции вызывающего» (точка сохранения) бывает только на PostgreSQL и проверен там (`TestRunRetryInOuterTransaction` плана 53; векторы задачи 21 идут так же). Вложенный вызов `MemRepo` — взаимная блокировка на своём `tx`; это записано в комментарии `DoInTx`.
37. **`closeResultLabel` `[""]` у Go = `""` у прототипа.** Прототип даёт `""`, если ключ подписи пуст (`closeResultLabel(ev) ? […] : ""`), Go — `[""]` (`journal.go`, `closeResultLabel`). На машине так не бывает: у всех пунктов справочников есть `labelKey`. `Compare` нормализует подстановку `closeResultLabel` `[""]` → `""` у Go и считает такие случаи; в логе `TestTransitionVectors` число должно быть 0. Go не меняется (открытый вопрос 6).
38. **Пустой список — не ошибка.** Прототип его принимает, и запись его поймает: `tests/api-scenarios.js` (строка 3513) зовёт «Отсоединить все» у основного без привязанных и ждёт `200`, `server.js` зовёт `engine.runAll(detach.id, [])`; объединение выборки из одного — `engine.merge(primary, [])`, то есть только «Взять». Поэтому: `RunAll` с пустым `op.IDs` — после поиска перехода (нет перехода — отказ `unknown_action`, как `runAll`) пустой `Result` без отказа, без `LockFamily` и без `Write`. `Merge` без присоединяемых (после того как основной убран из `op.IDs`, как `others = list.filter(e => e !== primary)` в `server.js`) — блокировка основного и только «Взять», если основной в `from` перехода `grouping.takeWith`, без `merged_in*`; иначе — пустой `Result` без `Write`.
39. **Закрытие вектора объединения.** На возврате `merge` запись сразу закрывает ленту кадра и снимает полное «после» (`celView` и журналы всех инцидентов списка). Отложено только чтение новых записей журнала основного: на закрытии их должно быть не больше одной, `workflow.journal.merged_in` или `workflow.journal.merged_in_more` от `me`, — она входит в ожидаемое с `server: true`. Закрывает вектор следующий вызов любого обёрнутого ядра — своего и коллег (`run`, `runAll`, `merge`, `create`, `tick`, `startTimer`…`resumeTimer`; `runScheduler` зовёт `tick`) — или `take()`. На закрытии у каждого инцидента списка (а не только у своих объединения) `celView` равен снимку «после», а журнал — снимку плюс разве что эта запись основного; иначе — вектор не пишется, счёт `skipped.outsideEngine`, `--update` с ненулевым счётом — стоп. Вызовы мира после возврата (`emitTransition`, `card(primary)`) в ленту не идут: кадр уже закрыт.
40. **Отбор — при записи.** Каждый закрытый вектор сразу проходит отбор (решение 28) по `op:name` и исходу; не прошедший не хранится, и его инциденты в пул не добавляются: пул — только инциденты оставленных векторов. Иначе каждый вектор держит весь `ctx.events()`, а случайные прогулки `tests/api-properties.js` дают по 120+ шагов. Проверка «один `id` — два разных `expect`» идёт по всем, в том числе отброшенным (`id` → хэш ожидаемого). Часы и случайные числа записи зафиксированы (`?celVectors=1`), поэтому отбор повторяется. Размер файла — по первому прогону (в журнал работ); больше 4 МБ — **стоп, спросить** (пределы — открытый вопрос 3).
41. **Правила сравнения — полностью.** JS-повтор (`--check`), `Compare` (вектор против Go) и `Same` (Go в памяти против Go в базе):
    - **Лента** — как у векторов CEL: поиск по `fn` и аргументам, равным по значению; промах — провал; неиспользованная запись — только счёт.
    - **Пул и порядок списка.** Инциденты — из пула в порядке `incidents`; `journalAtNow` — журнал до вызова. Прототип даёт ядру список в порядке набора и появления (`events`, новые — в начало), сервер — по номеру (решение 6 плана 53; ADR-005, «Order of the list of incidents»). `Compare` идёт в порядке вектора, `Same` — в порядке номеров; сколько векторов дают при этих порядках разный итог — число `order-sensitive` в логе задачи 21 (открытый вопрос 3 плана 53).
    - **`since`** — только у `hold` (решение 25).
    - **Пусто:** `null` → `""` (решение 26: `facts`, `about`, `who` и `by` у `evict`, аргументы `ctx.*`); `vars` `nil` = `{}`.
    - **Числа:** `json.Number` и `int64` — одно (инциденты, подстановки журнала, `facts`, подстановки отказа, лента).
    - **`closeResultLabel`:** `[""]` у Go = `""` (решение 37); счёт — в логе.
    - **`incidents`** — записанные (`Result.Incidents`), чей инцидент машины отличается от исходного, равны ожидаемым.
    - **Журнал** — по инцидентам, по порядку; JS-повтор не сравнивает записи с `server: true` (их пишет `server.js`, а не ядро), Go — сравнивает. `journalAtNow` после вызова — у Go журнал `MemRepo` (заменённые `once` на месте).
    - **`external`** — только у инцидентов, для которых он есть в ожидаемом; **`canceled`** — только у `run` (решение 27).
    - **Отказ:** `Refusal` есть; совпадают поля, которые есть в ожидаемом: `why[0]` — `Key`, `why[1]` — `Vars`, `guard` — `Guard`, `notFrom` — `NotFrom`, `code` — `Code`, `id` — `ID`; ничего не записано (`Writes() == 0`).
    - **Ошибка:** `expect.error` (прототип — `workflow.error.transition_failed`, у `server.js` это `422`) — Go даёт `(nil, err)`; `err` — не промах ленты, не `ErrFamilyChanged`, не `*VersionConflict`; ничего не записано; текст не сравнивается (решение 3 плана 53, открытый вопрос 2 плана 53).
    - **`after`** — по порядку: и JS-повтор, и `Compare`, и `Same` (итоговое ревью: порядок, не сравнённый с прототипом, прошёл бы мимо — `Same` сравнивает Go с Go и расхождения с прототипом не видит).
    - **Не сравниваются с вектором:** версии (`Row.Version`, решение 1 плана 53), поля записи журнала `Transition` и `ID`.
    - **`Same`:** всё выше плюс `Canceled` у всех `op` и `Transition` записей журнала; не сравниваются `Row.Order` (в памяти — место в списке, в базе — номер), абсолютные версии (только прирост +1 у записанных) и `JournalEntry.ID`; журнал — только новые записи операции (`Result.Journal`) и заменённые `once`, а не записи `journalAtNow`, положенные заранее.

## Review Focus

1. **Основной вне семьи (решение 33):** живой основной вне блокировки — повтор; удалённый или отсутствующий — не повтор. Тесты — задача 1: `TestRunPrimaryNotSiblingOutsideFamilyIsError`, `TestRunDeletedPrimaryIsNotLocked`, `TestRunDeletedPrimaryOnPostgres`.
2. **Запись видит всё и только ядро (решения 39, 40):** `merged_in*` — с пометкой `server`, прочее вне ядра — стоп записи; отбор при записи; `cel-vectors.json` после `--update` — те же байты. Тесты — задача 4: «отбор при записи»; задача 5: «запись merge: merged_in после ядра — в expect», «закрытие merge вызовом ядра коллеги и tick», «запись вне ядра с другим ключом — стоп»; задачи 3 и 8 — `git diff --exit-code cel-vectors.json`.
3. **Шаги на одном черновике (решение 34):** второй видит первого; факты и «некому» — после всей операции; окно — у каждого. Тесты — задача 16: `TestRunAllSecondSeesFirst`, `TestRunAllFactsAfterOperation`, `TestRunAllEmptyLogAfterOperation`; задача 17: `TestMergeTakeSeesTightenedDeadline`, `TestMergeTakeSeesRelink`, `TestMergePrimaryNewDuringMergeEffects`, `TestMergeWindowEach`.
4. **Всё или ничего у нескольких инцидентов, пустой список (решение 38):** отказ или ошибка у любого — не меняется ни один, отказ называет его; пустой список — пустой итог без записи. Тесты — задача 16: `TestRunAllFirstRefusalNamesIncident`, `TestRunAllOneTransaction`, `TestRunAllEmptyIsOk`; задача 17: `TestMergeRefusalNamesIncident`, `TestMergeWithoutOthersIsTake`.
5. **Объединение блокирует основного (решение 35):** нет `ErrFamilyChanged` и `40P01`. Тесты — задача 17: `TestMergeLocksPrimary`, `TestConcurrentMergeAndClaimOnPostgres`.
6. **Сравнение (решение 41):** отказ против ошибки, пусто против `null`, числа, `since`, `closeResultLabel`. Тесты — задача 19: `TestCompareNormalizes`, `TestSameIgnores`; задача 20: `TestTransitionVectors`.
7. **Память = база:** семья берёт всех, кому пишут эффекты, на всех векторах; порядок номеров — один и тот же в обоих хранилищах. Тест — задача 21: `TestTransitionVectorsOnPostgres`.

---

## Формат векторов переходов

Общий для задач 4–12 и 18–21; в IM описывается в CEL.md, раздел «Векторы переходов» (задача 13). Значения — как у векторов CEL: канонический JSON, пул инцидентов `{"$ref"}`, инцидент в ленте и действиях — `{"$incident": id}`, числа — безопасные целые.

```json
{"$comment": "Собрано tools/cel_vectors.mjs --update из записи tests/api.html?celVectors=1 и синтетики. Руками не править. Формат — CEL.md, «Векторы переходов»",
 "counts": {"create": 0, "merge": 0, "run": 0, "runAll": 0},
 "format": 1,
 "incidents": {"<ключ>": {"…Incident целиком…": ""}},
 "machineSha256": "<sha256 байтов workflow_schema.v1.json>",
 "skipped": {"nowChanged": 0, "outsideEngine": 0, "tapeRepeat": 0, "worldError": 0},
 "uncovered": {"<имя перехода>": "почему нет вектора ok, словами"},
 "vectors": [{"…": ""}]}
```

`uncovered` — то же, что `UNCOVERED_TRANSITIONS_OK` в `cel_vectors.mjs` (не больше 3); его читают и `--check`, и тест покрытия Go (задача 20).

| Поле вектора | Что |
|---|---|
| `id` | `transition:<op>:<name>:<первые 10 hex sha256 канонического входа>`; вход — все поля, кроме `id`, `case`, `expect` |
| `kind` | `transition` |
| `op` | `run`, `runAll`, `merge`, `create` |
| `name` | id перехода; у `merge` — переход с `bulk.mode: merge`; у `create` — `create` |
| `case` | только у синтетики: название случая по-русски |
| `me` | оператор ядра (`ctx.me`); он же `actor` у `run`, `runAll`, `merge` |
| `now` | `ctx.now()` на входе, мс; во время вызова не меняется (иначе вектор не пишется, счёт `skipped.nowChanged`) |
| `surface` | `opts.surface` или `""` (у `merge` и `create` — `""`) |
| `form` | значения формы как есть (`run`, `runAll`); у `merge` и `create` — `{}` |
| `target` | `run` — `{"id"}`; `runAll` — `{"ids"}` (может быть пустым — решение 38); `merge` — `{"primaryId", "ids"}` (присоединяемые в порядке вызова, могут быть пустыми); `create` — `{"incident": {"$ref"}}` (новый, до перехода) |
| `incidents` | `ctx.events()` на входе — список `{"$ref"}` в порядке прототипа |
| `journalAtNow` | `{"<id>": [запись]}` — записи журнала инцидентов списка с `at == now` до вызова (для `once`); только непустые |
| `world` | лента `[{"fn", "args", "out"}]`: факты `cel.world` без `ref`, `transferTargets` и `ctx.actorName [id]`, `ctx.progress [инцидент] → {"filled", "total"}`, `ctx.stepNumber [инцидент]`, `ctx.shareAnswers [from, to, at] → n`; `null` в аргументах `ctx.*` — `""` |
| `expect` | `{"ok": {…}}`, `{"refusal": {…}}` или `{"error": "текст"}` |

Запись журнала: `{"actor", "at", "kind", "templateKey", "vars"}`, плюс `"server": true` у записей, которые `server.js` дописал после ядра (`merged_in*`); `kind` — как `journalView` в `server.js` (`dispatcher`, `system` — `system`, иначе `transition`; у Go — `model.JournalKindOf`); `vars` — `{}`, если пусто.

`expect.ok`:

| Поле | Что |
|---|---|
| `incidents` | `{"<id>": {"$ref"}}` — `celView` после вызова у каждого инцидента списка (и у нового при `create`), чей `celView` изменился |
| `journal` | `{"<id>": [запись]}` — хвост журнала по инцидентам, по порядку; только непустые |
| `journalAtNow` | `{"<id>": [запись]}` — записи с `at == now` после вызова у инцидентов, у которых они были до вызова (видно, что `once` заменил подстановки прежней записи) |
| `after` | по порядку: `{"action": "notify", "incident", "recipients", "alert", "about", "actor", "transitionId"}`, `{"action": "evict", "incident", "who", "transitionId", "by"}`, `{"action": "touch", "incident", "actor"}` (`about` — `{"$incident"}` или `""`; `who`, `by` — id или `""`) |
| `scenario` | по порядку: `{"action": "setCursor", "incident"}`, `{"action": "shareAnswers", "from", "to"}` |
| `external` | `{"<id>": [{"fn", "target"}]}` — у инцидентов, для которых ядро прототипа его отдаёт: `run` — свой, `runAll` — все, `merge` — присоединяемые; пустые — тоже |
| `facts` | `{"<id>": {"from": {"state", "owner", "addressee", "breaches"}, "to": {…}, "breach"}}` — у инцидентов шагов (у `merge` — присоединяемые и основной, если его взяли); пусто — `""` |
| `canceled` | только у `run`: `{"<id>": "<переход по таймеру>"}`, если отменён |

`expect.refusal`: `{"why": [ключ, подстановки?], "guard"?, "notFrom"?, "code"?, "id"?}` — поля ответа ядра; запись проверяет, что `celView` и журнал всех инцидентов списка не изменились. `expect.error` — текст `why[1].error` у `workflow.error.transition_failed`.

Правила сравнения — решение 41.

## Структура файлов

| Файл | Что | Задача |
|---|---|---|
| `internal/im/service/transition/{run.go, family_test.go}`, `internal/im/service/transition/transitiontest/{memrepo.go, memrepo_test.go}`, `internal/im/handler/test/transition_test.go` | проверка основного у живой строки, мягкое удаление в `MemRepo` | 1 |
| IM: `prototype/engine.js`, `tests/transition-vectors.js` (`lib.normalize`), `tools/test_cel.mjs` | стыки ядра `fromView`, `ctx.world` | 2 |
| IM: `tests/cel-vectors.js`, `tools/test_cel.mjs` | кадры записи CEL | 3 |
| IM: `tests/transition-vectors.js`, `tools/test_cel.mjs` | запись `run`, `runAll`, `create`, отбор при записи | 4 |
| IM: `tests/transition-vectors.js`, `tools/test_cel.mjs` | закрытие вектора объединения | 5 |
| IM: `tests/transition-vectors.js`, `tools/test_cel.mjs` | повтор по ленте | 6 |
| IM: `tests/api.html`, `tests/harness.js` | запись в Chrome | 7 |
| IM: `tools/cel_vectors.mjs`, `Specification/Workflow_machine/fixtures/transition-vectors.json` | сборка `--update` | 8 |
| IM: `tools/cel_vectors.mjs` | `--check` векторов переходов | 9 |
| IM: `tools/cel_vectors.mjs`, `fixtures/transition-vectors.json` | синтетика | 10 |
| IM: `tools/cel_vectors.mjs`, `fixtures/transition-vectors.json` | покрытие, `uncovered` | 11 |
| IM: `tools/cel_vectors.mjs` | `--engine`, пробы порчи | 12 |
| IM: `Specification/Workflow_machine/{CEL.md, BACKEND.md}`, `README.md`, `CLAUDE.md`, `.graphifyignore` | раздел «Векторы переходов», проверки | 13 |
| `Makefile`, `api/im/operator/{transition-vectors.json, SOURCE, vectors_test.go}` | копия векторов с IM HEAD | 14 |
| `internal/im/service/transition/{run.go, effects.go, window.go, create.go}` | шаги операции (без нового поведения у `Run` и `Create`) | 15 |
| `internal/im/service/transition/{runall.go, runall_test.go}` | «Отсоединить все» | 16 |
| `internal/im/service/transition/{core.go, merge.go, merge_test.go}`, `internal/im/handler/test/transition_test.go` | объединение и «Взять» основного | 17 |
| `internal/im/service/transition/transitiontest/{tape.go, tape_test.go}` | лента Go | 18 |
| `internal/im/service/transition/transitiontest/{vectors.go, compare.go, compare_test.go}` | формат и сравнение | 19 |
| `internal/im/service/transition/transitiontest/run.go`, `internal/im/service/transition/vectors_test.go` | сверка с векторами в памяти | 20 |
| `internal/im/handler/test/{transition_vectors_test.go, transition_seed_test.go}` | сверка на PostgreSQL | 21 |
| `docs/adr/{004-machine-executor.md, 005-transitions-in-transaction.md}`; IM: `research/integration/{40-plan.md, 54-plan-stage4b2.md}` | решения, отметки | 22 |

---

### Task 1: Ядро — основной вне семьи только у живой строки, мягкое удаление в `MemRepo`

**Files:**
- Modify: `internal/im/service/transition/run.go` (`operation.lock`, строки 93–100)
- Modify: `internal/im/service/transition/transitiontest/memrepo.go` (`SoftDelete`; `LockFamily`, `Candidates`, `Write` — без удалённых; комментарий `DoInTx` — решение 36); Test: `internal/im/service/transition/transitiontest/memrepo_test.go`
- Test: `internal/im/service/transition/family_test.go`, `internal/im/handler/test/transition_test.go`

**Interfaces:**
- Produces: `func (r *MemRepo) SoftDelete(id string)` — строка помечена удалённой, как `deleted_at` у `Store.DeleteIncident`. Как `lockIncidentFamilySQL`: в `S0` идут только живые свои строки и их `linkedTo` (id удалённого основного в `S0` остаётся, живые привязанные к нему — в семье); сама удалённая строка в семью не идёт и событие в `S0` не даёт. `Candidates` её не отдаёт; `Rows()` — отдаёт; `Write` её — ошибка (у `storeRepo` она не взята блокировкой).
- Changes: `operation.lock` — основной своей строки, которого нет среди взятых, — `ErrFamilyChanged` только когда он жив: `o.repo.Candidates(o.ctx, o.op.Customer, "incidentById", []any{primary})` отдаёт строку с этим id (так ищет `numberOf` в `journal.go`). Иначе операция идёт дальше (решение 33).

- [x] **Step 1: Тесты**

Помощники — `closeRepo`, `closeFalseAlarm`, `zedRow` (`family_test.go`); `storeWrap` со счётом `locks` и `f.commit` (`transition_test.go`).

```go
// family_test.go
func TestRunPrimaryNotSiblingOutsideFamilyIsError(t *testing.T)
  // rows := append(closeRepo().Rows(), zedRow()); rows[0].Incident["linkedTo"] = zed (своё событие — не сосед x);
  // repo := transitiontest.NewMemRepo(rows); repo.HideFromFamily(zed, -1) ⇒
  // ErrorIs ErrFamilyChanged, LockCalls() == 3, Writes() == 0, Journal() пуст; без HideFromFamily — NoError, Writes() == 1.
  // close «Ложная тревога» основному не пишет, поэтому тест падает, если проверку убрать (TestRunPrimaryOutsideFamilyIsError — нет: там основной — сосед sib)
func TestRunDeletedPrimaryIsNotLocked(t *testing.T)
  // подтесты "soft-deleted" — то же, но SoftDelete(zed) вместо HideFromFamily; "absent" — linkedTo = "10000000-0000-4000-8000-000000009999" (строки нет)
  // ⇒ NoError, Refusal nil, LockCalls() == 1, Writes() == 1; zed не записан (Rows()[2].Version — 7)
// memrepo_test.go
func TestMemRepoSoftDelete(t *testing.T)
  // P удалён; L, M привязаны к P; S — сосед P по событию ⇒ LockFamily([L]) — [L, M] (ни P, ни S); LockFamily([P]) — пусто;
  // Candidates без P; Rows() с P; Write с P — ошибка
// transition_test.go (с базой)
func TestRunDeletedPrimaryOnPostgres(t *testing.T)
  // f.commit: p, затем x в работе у op1 с linked_to p; p удалён Store.DeleteIncident; close «Ложная тревога» по storeWrap ⇒
  // NoError, Refusal nil, store.locks == 1; x в базе closed, версия +1; p не изменился
```

- [x] **Step 2: Тесты падают**

Run: `cd ~/Work/incident-manager-server && source ~/go/offline-env.sh && go test ./internal/im/service/transition/... -run 'PrimaryNotSibling|DeletedPrimary|SoftDelete' 2>&1 | tail -5`
Expected: FAIL — `SoftDelete` не объявлен; после него — `TestRunDeletedPrimaryIsNotLocked` падает с `3 attempts: … the family of the incident changed`. `TestRunPrimaryNotSiblingOutsideFamilyIsError` проходит и до правки: он ловит удаление проверки, а не её отсутствие.

- [x] **Step 3: Реализация**

- [x] **Step 4: Тесты проходят**

Run: `go test -race ./internal/im/service/transition/... && TESTDB='postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable' && IM_TEST_DB_URL=$TESTDB go test ./internal/im/handler/test/ -run 'TestRunDeletedPrimaryOnPostgres|TestRunOnPostgres|TestRunRetryInOuterTransaction|TestLockFamily|TestFamilyMemMatchesPostgres' && golangci-lint run ./...`
Expected: PASS, прежние тесты ядра — без правки; lint — 0.

- [x] **Step 5: Commit**

Сообщение: «Этап 4б: ядро — основной вне семьи даёт повтор, только если его строка жива: удалённый или отсутствующий основной не даёт ErrFamilyChanged; MemRepo — мягкое удаление».
Run: `git add internal/im/service/transition internal/im/handler/test/transition_test.go && git commit -q -F .git/COMMIT_MSG_STAGE4B`

---

### Task 2: IM — стыки ядра `fromView` и `ctx.world`

**Files:**
- Modify: `prototype/engine.js` (`fromView` в объекте ядра; `const celWorld = ctx.world || {…}`)
- Create: `tests/transition-vectors.js` (пока — `window.IMTransitionVectors.lib.normalize`; грузится и в Node через `vm`)
- Modify: `tools/test_cel.mjs`

**Interfaces:**
- Produces:
  - `engine.fromView(plain, base)` — инцидент прототипа из `celView`: `base` (поля сервера вне `celView`: `log`, `run`, `version` и прочие) плюс поля по `celIncident` и `writeBack`; `scenarioGuid` — из `plain.scenario` (у `celView` это `ctx.scenarioKey(ev)`, то есть `ev.scenarioGuid`; без этого повтор теряет сценарий);
  - `ctx.world` — задан: факты мира ядра — его функции (имена и аргументы `cel.world`), а не обёртки над `ctx`; `celWorld` берётся один раз при `IMEngine.create`, поэтому повтор (задача 6) даёт устойчивый объект, который отвечает по ленте текущего вектора; не задан — как раньше;
  - `lib.normalize(incident, W)` — правило решения 25 (`since` у таймеров кроме `hold` — `0`) и пусто как у `cel.value`: `null` в поле — нулевое значение типа поля по `cel.types.Incident` (`""`, `0`, `false`); недостающий таймер машины — нулевая запись.

- [x] **Step 1: Тесты** (в `tools/test_cel.mjs`; ядро в `vm`, как в `check_quint_replay.mjs`, мир — словарь)

```js
test("fromView: celView(fromView(x)) == x для инцидентов пула fixtures/cel-vectors.json", ...)
  // все 1029; сравнение — после lib.normalize с обеих сторон: у 653a46ba2cbf0a75 нет reaction,
  // у 87c0fdeef1627852 и b2706381283b9197 owner, closedAt, holdReasonId — null (синтетика 4а); fromView(x).scenarioGuid == x.scenario
test("ctx.world: факт мира берётся из ctx.world", ...)  // ctx.can → false, ctx.world.can → true ⇒ availability('claim', x).ok
```

- [x] **Step 2: Тесты падают**

Run: `cd /mnt/hgfs/VmWareShared/soul2home/IM && git fetch && node tools/test_cel.mjs`
Expected: FAIL — `fromView` нет, `IMTransitionVectors` не объявлен; прежние 20 проходят.

- [x] **Step 3: Реализация**

- [x] **Step 4: Тесты проходят; прототип — как раньше**

Run: `node tools/test_cel.mjs`
Expected: `test_cel: 22 из 22`.

Run: быстрые проверки IM; самопроверка (`prototype/index.html?selftest`, бюджет 180000) и тесты API (`tests/api.html`, 120000) — по `CLAUDE.md`, профиль в `$S`; `python3 -c "import sys; sys.path.insert(0, 'tools'); import check_code_mutations as m; bad = m.stale(); print(len(m.MUTATIONS), 'порч, устаревших:', len(bad), bad)"`.
Expected: всё зелёное; `data-selftest="pass"`, `data-apitest="pass"`, итог тестов API — тот же, что до задачи; устаревших порч — 0. Шага самопроверки нет (решение 32).

- [x] **Step 5: Commit**

Сообщение: «Этап 4б: стыки ядра прототипа для векторов переходов — обратный мост fromView и подмена мира ctx.world».
Run: `git add prototype/engine.js tests/transition-vectors.js tools/test_cel.mjs && git commit -q -F .superpowers/sdd/54-plan-stage4b2/commit-msg.txt`

---

### Task 3: IM — кадры записи CEL

**Files:**
- Modify: `tests/cel-vectors.js` (`recorder` — кадры; `window.IMCelVectors.frame` — кадр активной записи), `tools/test_cel.mjs`

**Interfaces:**
- Produces: `rec.frame()` записи 4а и `IMCelVectors.frame()` — открыть кадр: каждый вызов факта мира без `ref` в любом вычислении, пока кадр открыт, идёт и в его ленту; `close()` — лента кадра (повтор вызова с тем же ответом — одна запись, с другим — `tapeRepeat`). Векторы CEL кадр не меняет.

- [x] **Step 1: Тесты**

```js
test("кадр: факты мира всех вычислений внутри кадра — в его ленте; повтор с тем же ответом — одна запись, с другим — tapeRepeat", ...)
test("кадр не меняет запись CEL: те же векторы с открытым кадром и без", ...)
```

- [x] **Step 2: Тесты падают** — `node tools/test_cel.mjs`: FAIL — `frame` нет; прежние 22 проходят.

- [x] **Step 3: Реализация**

- [x] **Step 4: Тесты проходят; векторы CEL — те же байты**

Run: `S=<scratchpad> && node tools/test_cel.mjs && node tools/cel_vectors.mjs --update --tmp=$S && git diff --exit-code Specification/Workflow_machine/fixtures/cel-vectors.json`
Expected: `test_cel: 24 из 24`; `git diff` пуст (код 0). Быстрые проверки IM — зелёные.

- [x] **Step 5: Commit**

Сообщение: «Этап 4б: кадры записи векторов CEL — лента фактов мира всех вычислений внутри вызова ядра».
Run: `git add tests/cel-vectors.js tools/test_cel.mjs && git commit -q -F .superpowers/sdd/54-plan-stage4b2/commit-msg.txt`

---

### Task 4: IM — запись `run`, `runAll`, `create`; отбор при записи

**Files:**
- Modify: `tests/transition-vectors.js`, `tools/test_cel.mjs`

**Interfaces:**
- Consumes: задачи 2, 3.
- Produces: `lib.recorder(create, reference, frame)` → `{create, take}`; `lib.select(vectors, {perName: 20, perOutcome: 4})` и отбор на закрытии (решение 40); `lib.kindOf(whoId)`; `recording`, `take(): {incidents, vectors, skipped}`.

Запись (решения 24–27, 40): обёртка `IMEngine.create(ctx)` — машина не исходная — как есть; иначе обёрнуты функции `ctx` (`actorName`, `progress`, `stepNumber`, `shareAnswers` — в ленту, `null` в аргументах — `""`; `transferTargets` — в ленту как факт `transferTargets`; `setCursor`, `shareAnswers` — в `scenario`; `deliver`, `onEvict`, `onBreachShared` — в `after`, `null` в `about`, `who`, `by` — `""`) и методы ядра `run`, `runAll`, `create` (кадр, снимок «до»: `celView`, длины журналов и `journalAtNow` всех инцидентов списка; вызов; «после»; отбор). Снимки — только `celView` (`cel.value`/`plain`), без `cel.call`, `guard`, `rule`: иначе запись CEL получит лишние векторы. `now` изменился за вызов — вектора нет, `skipped.nowChanged`. Исключение ядра пробрасывается дальше и вектора не даёт. Один `id` — два разных `expect` — исключение «один вход — два ответа».

- [x] **Step 1: Тесты**

```js
test("запись run: вектор с журналом и неизменённым остальным", ...)
  // два инцидента [x new, y new], claim x ⇒ один вектор: op run, target {id: x}, expect.ok.incidents — только x,
  // journal {x: [{templateKey "workflow.journal.claim", kind "transition", actor me, at now}]}, scenario [setCursor x], after [];
  // в ленте ctx.actorName [""] (а не [null]); facts.x.from.owner ""
test("запись runAll с пустым списком — вектор ok без изменений", ...) // runAll('detach', []) ⇒ target {ids: []}, expect.ok без incidents и journal
test("отказ: expect.refusal, инциденты не изменились", ...) // claim при can → false ⇒ {why: ["workflow.guard.no_permission", {p: "incident:claim"}]}
test("отбор при записи: 25 одинаковых claim — 4 вектора, пул — только их инциденты", ...)
test("now меняется во время вызова — вектора нет, skipped.nowChanged 1", ...)
```

- [x] **Step 2: Тесты падают** — `node tools/test_cel.mjs`: FAIL — `recorder` нет; прежние 24 проходят.

- [x] **Step 3: Реализация**

- [x] **Step 4: Тесты проходят**

Run: `node tools/test_cel.mjs`
Expected: `test_cel: 29 из 29`; быстрые проверки IM — зелёные.

- [x] **Step 5: Commit**

Сообщение: «Этап 4б: запись векторов переходов — обёртка ядра прототипа (run, runAll, create), лента мира кадром записи CEL, отбор при записи».
Run: `git add tests/transition-vectors.js tools/test_cel.mjs && git commit -q -F .superpowers/sdd/54-plan-stage4b2/commit-msg.txt`

---

### Task 5: IM — закрытие вектора объединения

**Files:**
- Modify: `tests/transition-vectors.js`, `tools/test_cel.mjs`

**Interfaces:**
- Consumes: задача 4.
- Produces: обёртка `merge` по решению 39: кадр закрыт и «после» снято на возврате; закрытие — на следующем вызове любого обёрнутого ядра (общий счёт для всех ядер записи) или в `take()`.

- [x] **Step 1: Тесты**

```js
test("запись merge: merged_in после ядра — в expect с server: true", ...)
  // merge, затем «сервер» дописывает основному merged_in и вызывает ядро ещё раз ⇒ последняя запись журнала основного — merged_in, server: true
test("закрытие merge вызовом ядра коллеги и tick", ...) // второе ядро (другой me) или tick() закрывает вектор так же
test("лента merge закрыта на возврате: факт мира после merge в ленту не идёт", ...) // как emitTransition, card(primary)
test("запись: запись журнала вне ядра с другим ключом или изменение другого инцидента списка — вектора нет, skipped.outsideEngine 1", ...)
test("merge без присоединяемых — только «Взять», без merged_in", ...)
```

- [x] **Step 2: Тесты падают** — `node tools/test_cel.mjs`: FAIL; прежние 29 проходят.

- [x] **Step 3: Реализация**

- [x] **Step 4: Тесты проходят**

Run: `node tools/test_cel.mjs`
Expected: `test_cel: 34 из 34`; быстрые проверки IM — зелёные.

- [x] **Step 5: Commit**

Сообщение: «Этап 4б: запись векторов переходов — объединение: лента закрыта на возврате, записи merged_in от server.js — с пометкой server, прочее вне ядра — вектора нет».
Run: `git add tests/transition-vectors.js tools/test_cel.mjs && git commit -q -F .superpowers/sdd/54-plan-stage4b2/commit-msg.txt`

---

### Task 6: IM — повтор по ленте

**Files:**
- Modify: `tests/transition-vectors.js`, `tools/test_cel.mjs`

**Interfaces:**
- Consumes: задачи 2, 4, 5.
- Produces: `lib.replay(engineFor, vector, pool) → {ok, got, misses}`. `engineFor(me)` даёт ядро, созданное один раз с устойчивым `ctx.world`, который отвечает по ленте текущего вектора (`world.tape = v.world` перед вызовом). `ctx` повтора: `events` — инциденты пула через `fromView`, `now`, `ctx.*` по ленте, `transferTargets: () => tape("transferTargets", []).map((id) => ({id}))`, `scenarioKey` — `ev.scenarioGuid`, `log` — запись в журнал инцидента, `deliver`/`onEvict`/`onBreachShared`/`setCursor` — в итог. Сравнение — по решению 41.

- [x] **Step 1: Тесты**

```js
test("повтор: run по ленте даёт тот же expect; лента без can — промах", ...) // replay → ok; misses = ["can"]
test("повтор: transfer — варианты поля targetId из ленты transferTargets", ...)
test("повтор merge: записи server: true не сравниваются", ...)
```

- [x] **Step 2: Тесты падают** — `node tools/test_cel.mjs`: FAIL — `replay` нет; прежние 34 проходят.

- [x] **Step 3: Реализация**

- [x] **Step 4: Тесты проходят**

Run: `node tools/test_cel.mjs`
Expected: `test_cel: 37 из 37`; быстрые проверки IM — зелёные.

- [x] **Step 5: Commit**

Сообщение: «Этап 4б: повтор векторов переходов на ядре прототипа — мир по ленте, варианты передачи из ленты».
Run: `git add tests/transition-vectors.js tools/test_cel.mjs && git commit -q -F .superpowers/sdd/54-plan-stage4b2/commit-msg.txt`

---

### Task 7: IM — запись векторов переходов при тестах API

**Files:**
- Modify: `tests/api.html` (`<script src="transition-vectors.js">` после `../prototype/engine.js` и до `../prototype/server.js` — `server.js` создаёт ядра при загрузке; `<pre id="transitionvectors-out" hidden></pre>`), `tests/harness.js` (`finish`: при `IMTransitionVectors.recording` — блок `transitionvectors-out` = `JSON.stringify(IMTransitionVectors.take())`)

**Interfaces:**
- Consumes: задачи 2–6.
- Produces: блок `transitionvectors-out` в выводе `tests/api.html?celVectors=1` — `{incidents, vectors, skipped}`; без параметра — пустой.

- [x] **Step 1: Проверка до правки** — блока и скрипта нет.

Run: `grep -c 'transition-vectors.js\|transitionvectors-out' tests/api.html`
Expected: `0`.

- [x] **Step 2: Реализация** правок `api.html` и `harness.js`.

- [x] **Step 3: Запись в Chrome зелёная и повторяется**

Run: `S=<scratchpad> && for n in 1 2; do google-chrome --headless=new --disable-gpu --no-first-run --user-data-dir=$S/chrome$n --virtual-time-budget=180000 --dump-dom "file://$PWD/tests/api.html?celVectors=1" > $S/rec$n.html; done && python3 -c "import html,re,sys,json,hashlib;[print('pass' if 'data-apitest=\"pass\"' in p else 'FAIL', (lambda s: (len(s), (lambda d: (len(d['vectors']), sorted({v['op'] for v in d['vectors']}), d['skipped'], hashlib.sha256(json.dumps(d,sort_keys=True).encode()).hexdigest()[:12]))(json.loads(s))))(html.unescape(re.search(r'<pre id=\"transitionvectors-out\"[^>]*>(.*?)</pre>',p,re.S).group(1)))) for p in [open(f,encoding='utf-8').read() for f in sys.argv[1:]]]" $S/rec1.html $S/rec2.html`
Expected: обе строки — `pass`; виды — `create`, `merge`, `run`, `runAll`; `skipped` — нули; размер блока, число векторов и хэш в двух прогонах совпадают; размер — в журнал работ (решение 40). Без параметра (`tests/api.html`) — `pass`, блок пустой. Блок `celvectors-out` сверяется в задаче 8 (`git diff --exit-code cel-vectors.json` после `--update`).

- [x] **Step 4: Commit**

Сообщение: «Этап 4б: запись векторов переходов при тестах API — tests/api.html?celVectors=1 пишет и блок transitionvectors-out».
Run: `git add tests/api.html tests/harness.js && git commit -q -F .superpowers/sdd/54-plan-stage4b2/commit-msg.txt`

---

### Task 8: IM — `transition-vectors.json`: сборка `--update`

**Files:**
- Modify: `tools/cel_vectors.mjs`
- Create (собирает `--update`): `Specification/Workflow_machine/fixtures/transition-vectors.json`

**Interfaces:**
- Consumes: задача 7.
- Produces: `node tools/cel_vectors.mjs --update` — один прогон Chrome, оба блока; тесты API не `pass`, `skipped.outsideEngine` или `skipped.nowChanged` ≠ 0 — стоп без записи; файл — по формату (`counts`, `skipped`, `uncovered: {}`, пул, векторы по `id`); файл больше 4 МБ — стоп. Повтор перед записью — задача 9.

- [x] **Step 1: Проверка до правки** — `ls Specification/Workflow_machine/fixtures/transition-vectors.json`: файла нет.

- [x] **Step 2: Реализация**

- [x] **Step 3: Сборка, повторяемость; векторы CEL — те же байты**

Run: `S=<scratchpad> && F=Specification/Workflow_machine/fixtures && /usr/bin/time -f '%e с' node tools/cel_vectors.mjs --update --tmp=$S && sha256sum $F/transition-vectors.json > $S/t1 && node tools/cel_vectors.mjs --update --tmp=$S && sha256sum -c $S/t1 && git diff --exit-code $F/cel-vectors.json && ls -l $F/transition-vectors.json`
Expected: время `--update` — до 480 с (в журнал работ); второй `--update` дал те же байты (`OK`); `cel-vectors.json` не изменился; файл переходов — до 4 МБ (размер — в журнал работ).

- [x] **Step 4: Commit**

Сообщение: «Этап 4б: векторы переходов для бэкенда — fixtures/transition-vectors.json тем же прогоном --update».
Run: `git add tools/cel_vectors.mjs Specification/Workflow_machine/fixtures/transition-vectors.json && git commit -q -F .superpowers/sdd/54-plan-stage4b2/commit-msg.txt`

---

### Task 9: IM — `--check` векторов переходов

**Files:**
- Modify: `tools/cel_vectors.mjs`

**Interfaces:**
- Consumes: задачи 6, 8.
- Produces: `node tools/cel_vectors.mjs --check [--file=…] [--transitions=путь] [--machine=…]` — после строк векторов CEL (итог и строка «синтетика: …») — строка `векторов переходов: N (run …, runAll …, merge …, create …), расхождений: 0, промахов ленты: 0`; нет файла переходов — «нет файла векторов переходов, соберите: node tools/cel_vectors.mjs --update», код 1. `--update` перед записью делает то же. Повтор — ядро в `vm` по образцу `check_quint_replay.mjs`, по ядру на каждое `me`, `lib.replay`; сравнение — решение 41.

- [x] **Step 1: Проверка без файла переходов**

Run: `S=<scratchpad> && node tools/cel_vectors.mjs --check --transitions=$S/nope.json; echo $?`
Expected сейчас (красное): код `0` — флаг не известен, файл не проверяется.

- [x] **Step 2: Реализация**

- [x] **Step 3: Проверка проходит и ловит порчу**

Run: `time node tools/cel_vectors.mjs --check && S=<scratchpad> && F=Specification/Workflow_machine/fixtures/transition-vectors.json && python3 -c "import sys;l=open(sys.argv[1],encoding='utf-8').read().split('\n');i=next(k for k,x in enumerate(l) if '\"workflow.journal.claim\"' in x and '\"ok\"' in x);l[i]=l[i].replace('\"workflow.journal.claim\"','\"workflow.journal.claimX\"',1);open(sys.argv[2],'w',encoding='utf-8').write('\n'.join(l))" $F $S/bad.json && node tools/cel_vectors.mjs --check --transitions=$S/bad.json; echo $?`
Expected: первый `--check` — код 0, обе строки векторов — `расхождений: 0, промахов ленты: 0`, меньше 20 с; второй — код `1`, в списке расхождений — `id` испорченного вектора. Шаг 1 теперь даёт «нет файла векторов переходов…», код `1`.

- [x] **Step 4: Commit**

Сообщение: «Этап 4б: cel_vectors.mjs --check повторяет векторы переходов на ядре прототипа».
Run: `git add tools/cel_vectors.mjs && git commit -q -F .superpowers/sdd/54-plan-stage4b2/commit-msg.txt`

---

### Task 10: IM — синтетика векторов переходов

**Files:**
- Modify: `tools/cel_vectors.mjs`; пересобирается `fixtures/transition-vectors.json`

**Interfaces:**
- Consumes: задачи 4–6, 9.
- Produces: синтетика с `case`, строка `--check` «синтетика переходов: N».

Запись в Node: `g.IMCel.create = celLib.recorder(g.IMCel.create, W).create` — до первого `IMEngine.create`; кадр этой записи идёт в `lib.recorder(create, reference, frame)`; синтетика — на исходной машине, ожидаемое — запись на ядре прототипа (решение 31). Основа: инцидент с id `10000000-0000-4000-8000-000000009001`, `INC-9001`, событие `70000000-0000-4000-8000-000000009001`, сценарий `60000000-0000-4000-8000-000000000002`, приоритет 50, все таймеры; второй — `…9002` (`INC-9002`, своё событие); оператор `op1` на месте, с правами; эскалировать некому (`can` для `petrova`, `noc` — false). Окно после дедлайна — 3000 мс (`invariants.manualWinsOverTimer.graceSec` = 3).

| Случай | Что | Ждём |
|---|---|---|
| `run claim` в окне | `new`, `reaction.due` = now − 2999 | `canceled` `escalation_ceiling`; нарушение `reaction` на момент дедлайна; журнал `[timer_overridden, claim]` |
| `run claim` на конце окна | `due` = now − 3000 | `canceled` нет, нарушения нет |
| `run transfer` в окне | `due` = now − 1000, `targetId` — `op2` (может принять) | `canceled` нет (`continuesOn`) |
| `run hold` с чужой причиной | `in_progress` у `op1`, `reasonId: "nope"` | `refusal` `workflow.error.field_invalid`, `code` `FORM_FIELD_INVALID` |
| `run close` без результата | форма `{}` | `refusal` `workflow.error.field_required`, `name` `[workflow.form.close.field.resultId]` |
| `run close` «массовый сбой» без причины | `{resultId: "mass"}` | `refusal` `field_required`, `name` `[workflow.form.close.field.causeId]` |
| `runAll detach`, второй не привязан | `[…9001 linked к …9003, …9002 new]`; `…9003` (`INC-9003`, своё событие) — в пуле, `in_progress` у `op1` (`primaryEditable`) | `refusal` `notFrom`, `id` `…9002` |
| `create`, приоритет без своего норматива | приоритет 60 | `timers.reaction.due` = now + 300 000 |

- [x] **Step 1: Проверка до правки** — `node tools/cel_vectors.mjs --check | grep -c 'синтетика переходов'`: `0`.

- [x] **Step 2: Реализация**

- [x] **Step 3: Сборка и проверка**

Run: `S=<scratchpad> && F=Specification/Workflow_machine/fixtures && node tools/cel_vectors.mjs --update --tmp=$S && git diff --exit-code $F/cel-vectors.json && node tools/cel_vectors.mjs --check`
Expected: «синтетика переходов: 8»; расхождений и промахов — 0; `cel-vectors.json` не изменился.

- [x] **Step 4: Commit**

Сообщение: «Этап 4б: синтетика векторов переходов — окно после дедлайна, форма, «Отсоединить все», норматив create».
Run: `git add tools/cel_vectors.mjs Specification/Workflow_machine/fixtures/transition-vectors.json && git commit -q -F .superpowers/sdd/54-plan-stage4b2/commit-msg.txt`

---

### Task 11: IM — покрытие векторов переходов

**Files:**
- Modify: `tools/cel_vectors.mjs`; пересобирается `fixtures/transition-vectors.json`

**Interfaces:**
- Produces: покрытие в `--check` и `--update`: у каждого перехода `trigger: manual` (12) и у `create` — вектор `ok`; у `run`, `runAll`, `merge` — хотя бы один `refusal`; хотя бы один вектор `run` с `canceled`; иначе имя — в `UNCOVERED_TRANSITIONS_OK` с причиной словами (не больше 3; больше — синтетика); `UNCOVERED_TRANSITIONS_OK` пишется в поле `uncovered` файла. Нарушено — «без векторов: …», код 1.

- [x] **Step 1: Проверка до правки** — `node tools/cel_vectors.mjs --check | grep -c 'без векторов'` на строке переходов: `0`.

- [x] **Step 2: Реализация**

- [x] **Step 3: Покрытие и проба**

Run: `S=<scratchpad> && node tools/cel_vectors.mjs --update --tmp=$S && node tools/cel_vectors.mjs --check && python3 -c "import json,sys;d=json.load(open(sys.argv[1]));d['vectors']=[v for v in d['vectors'] if v['name']!='reopen'];json.dump(d,open(sys.argv[2],'w'))" Specification/Workflow_machine/fixtures/transition-vectors.json $S/noreopen.json && node tools/cel_vectors.mjs --check --transitions=$S/noreopen.json; echo $?`
Expected: первый `--check` — строка переходов `…, без векторов: 0`; второй — «без векторов: reopen», код `1`.

- [x] **Step 4: Commit**

Сообщение: «Этап 4б: покрытие векторов переходов — у каждого ручного перехода и create вектор ok, отказы у run, runAll, merge».
Run: `git add tools/cel_vectors.mjs Specification/Workflow_machine/fixtures/transition-vectors.json && git commit -q -F .superpowers/sdd/54-plan-stage4b2/commit-msg.txt`

---

### Task 12: IM — `--engine` и проба порчи ядра

**Files:**
- Modify: `tools/cel_vectors.mjs`

**Interfaces:**
- Produces: `--engine=путь` — только для проб порчи: повтор на копии `prototype/engine.js` вместо исходного.

- [x] **Step 1: Проверка до правки** — `node tools/cel_vectors.mjs --check --engine=prototype/engine.js; echo $?`: флаг не известен.

- [x] **Step 2: Реализация**

- [x] **Step 3: Проба**

Run: копия `engine.js` в `$S`, у `windowAfter` убран `splice` (запись о таймере — в конец); `node tools/cel_vectors.mjs --check --engine=$S/engine.js; echo $?`
Expected: расхождение у вектора «`run claim` в окне», код `1`; с исходным `engine.js` — код 0.

- [x] **Step 4: Commit**

Сообщение: «Этап 4б: cel_vectors.mjs --engine — повтор векторов переходов на копии ядра для проб порчи».
Run: `git add tools/cel_vectors.mjs && git commit -q -F .superpowers/sdd/54-plan-stage4b2/commit-msg.txt`

---

### Task 13: IM — раздел «Векторы переходов», проверки

**Files:**
- Modify: `Specification/Workflow_machine/CEL.md` (после «Векторы» — раздел «Векторы переходов»; строка «Векторы переходов … будут на этапе 4б» — ссылкой на него), `Specification/Workflow_machine/BACKEND.md` (в «На что обратить внимание» — пункт «Векторы переходов»; в «Когда готово» — строка), `README.md` («Проверки»), `CLAUDE.md` (строка таблицы сгенерированных файлов `fixtures/cel-vectors.json` — и `transition-vectors.json`, исходники — и `tests/transition-vectors.js`, тем же `--update`), `.graphifyignore`

Раздел «Векторы переходов» (по-русски, простыми словами): зачем — переход целиком, а не одно вычисление; уровень — ядро, не HTTP, версий нет; откуда (запись + синтетика), отбор при записи и почему `merged_in*` с пометкой `server`; формат (таблицы выше) и все правила сравнения решения 41; как повторяет бэкенд — лента, пул, порядок списка; что из этого следует для бэкенда: всё в одной транзакции (нарушение отменённого таймером перехода, «некому», `merged_in*`, перенос ответов); порядок записей журнала (решение 13 плана 53); состояние `to` — перед эффектами инцидента, факты — после всей операции; окно — у каждого шага; пустой список — не ошибка; отказ — не ошибка, ошибка вычисления — ошибка сервера; планировщик — этап 6. BACKEND.md — коротко и ссылкой; «Когда готово» — «векторы `fixtures/transition-vectors.json` проходят у ядра бэкенда (CEL.md, «Векторы переходов»)». Чисел машины в новых строках BACKEND.md нет.

- [x] **Step 1: Документы и проверки**

Run: быстрые проверки IM и `python3 tools/check_links.py`.
Expected: всё зелёное; «Нерабочих ссылок: 0».

- [x] **Step 2: Commit**

Сообщение: «Этап 4б: CEL.md и BACKEND.md — раздел «Векторы переходов»; проверки и таблица сгенерированных файлов».
Run: `git add Specification/Workflow_machine/CEL.md Specification/Workflow_machine/BACKEND.md README.md CLAUDE.md .graphifyignore && git commit -q -F .superpowers/sdd/54-plan-stage4b2/commit-msg.txt`

---

### Task 14: Сервер — копия векторов переходов с IM HEAD

**Files:**
- Modify: `Makefile` (`vendor-operator-contract`: ещё `$(OP_SRC_DIR)/fixtures/transition-vectors.json` → `$(OP_API_DIR)/`)
- Create (make): `api/im/operator/transition-vectors.json`; Modify (make): `api/im/operator/SOURCE` (сейчас `6e86123`)
- Modify: `api/im/operator/vectors_test.go`

- [x] **Step 1: Тест**

```go
func TestTransitionVectorsMatchMachine(t *testing.T) // как TestCELVectorsMatchMachine: os.ReadFile("transition-vectors.json"); format == 1; machineSha256 == hex(sha256(Machine)); counts run, runAll, merge, create > 0
```

- [x] **Step 2: Тест падает**

Run: `cd ~/Work/incident-manager-server && source ~/go/offline-env.sh && go test ./api/im/operator/ 2>&1 | tail -3`
Expected: FAIL — нет `transition-vectors.json`.

- [x] **Step 3: Копия**

Run: `git -C /mnt/hgfs/VmWareShared/soul2home/IM status --porcelain -- Specification/Workflow_machine && make vendor-operator-contract && cat api/im/operator/SOURCE && git status --short`
Expected: `status` IM пуст; в `SOURCE` — хэш задачи 13 без `dirty`; новый файл `transition-vectors.json` и `SOURCE`; машина, контракт, строки и `cel-vectors.json` — без изменений (машина в этапе не менялась). Иначе — **стоп, спросить**.

- [x] **Step 4: Тесты проходят**

Run: `go test ./api/... ./internal/im/machine/ && golangci-lint run ./...`
Expected: PASS; lint — 0.

- [x] **Step 5: Commit**

Сообщение: «Этап 4б: копия векторов переходов с IM <SOURCE>».
Run: `git add Makefile api/im/operator && git commit -q -F .git/COMMIT_MSG_STAGE4B`

---

### Task 15: Ядро — шаги операции (без нового поведения у `Run` и `Create`)

**Files:**
- Modify: `internal/im/service/transition/{run.go, effects.go, window.go, create.go}`

**Interfaces:**
- Consumes: план 53, задачи 5–9, 13; задача 1.
- Changes (внутри пакета; решение 34):
  - `operation.lock` берёт все `op.IDs` одной `LockFamily`; каждый должен быть в семье (`ErrNotFound`); проверка основного решения 33 — у каждой своей строки;
  - `available` и `form` — у инцидента и перехода шага; `refuse` получает id инцидента (сейчас — всегда `o.self`);
  - `step(d, row, st)` — шаг на инциденте `row` по своему переходу, форме и исполнителю (`stepRun` уже держит `transition`, `form`, `actor`; переход как данные — новое поле); сейчас `step` читает `o.tr`, `o.op.Transition`, `o.op.Form`;
  - `window(row, transition)` — вместо `o.self` и `o.op.Transition`; `windowBefore`/`windowAfter` — у `canceled` своего инцидента; `windowAfter` по-прежнему сразу выполняет свои действия (`actions`);
  - записи `emptyLog` шагов копятся в операции и добавляются после всех шагов (сейчас — в конце шага, `actions`); `Facts` — после всех шагов, до окна после (сейчас — в `step`);
  - `Core.createOne` (зовёт `o.step(d, row)` и читает `o.res.Facts[id]`) после своего единственного шага добавляет «некому» и считает факты тем же кодом.

- [x] **Step 1: Проверка до правки** — все тесты пакета зелёные.

Run: `go test -race ./internal/im/service/transition/... -v 2>&1 | grep -c '^--- PASS'`
Expected: число — в журнал работ.

- [x] **Step 2: Реализация** (только перестройка; нового поведения у `Run` и `Create` нет)

- [x] **Step 3: Тесты проходят без правки**

Run: `go test -race ./internal/im/service/transition/... -v 2>&1 | grep -c '^--- PASS' && go test -race ./internal/im/service/intake/... && TESTDB='postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable' && IM_TEST_DB_URL=$TESTDB go test ./internal/im/handler/test/ -run 'TestRun|TestIntake|TestConcurrent|TestLockFamily' && golangci-lint run ./...`
Expected: то же число; тесты 4б-1 (`TestRun*`, `TestCreate*`, `TestEmptyLogAfterOperationRows`, `TestRunWindow*`, приём события) — без правки и зелёные; lint — 0.

- [x] **Step 4: Commit**

Сообщение: «Этап 4б: ядро — шаг операции на любом инциденте и переходе, окно у каждого шага, факты и «некому» после всей операции; у Run и Create итог прежний».
Run: `git add internal/im/service/transition && git commit -q -F .git/COMMIT_MSG_STAGE4B`

---

### Task 16: Ядро — «Отсоединить все» (`RunAll`)

**Files:**
- Create: `internal/im/service/transition/runall.go`; Test: `internal/im/service/transition/runall_test.go` (пакет `transition_test`)

**Interfaces:**
- Consumes: задача 15.
- Produces: `func (c *Core) RunAll(ctx model.AppContext, repo Repo, w World, op Op) (*Result, error)` — `op.IDs` — список в порядке вызывающего; пустой — решение 38; `op.Expect` — как у `Run` (ключ вне семьи — `ErrNotFound`; с массовыми `expectedVersions` — 4в); `Result.Canceled` заполняется, хотя в векторах его нет (решение 27).

Порядок (как `runAll` в `engine.js`): переход (нет — `unknown_action`) → список пуст — пустой `Result` → семья всех `op.IDs` одной блокировкой → `Expect` → для каждого по порядку доступность и форма, первый отказ — `Refusal` с `ID` этого инцидента → окно у каждого (отметка, `timer_overridden`) → один шаг на всех на одном черновике (у каждого `before`, `to` и эффекты — по очереди) → «некому» всех → факты всех → окно после у каждого → журнал, версии, `Write` одной транзакцией; повтор при `ErrFamilyChanged` — как у `Run`. Окна у `detach` не бывает (из `linked` нет переходов по таймеру); окно у каждого шага проверяет задача 17.

- [x] **Step 1: Тесты**

Основной P (`in_progress`, `op1`), привязанные L1, L2 (`linked`, `linkedTo` P); `me` — `op1`; мир — `transitiontest.DefaultWorld()` (`world()` тестов). Пробы — помощником `detachWith(t, uses, defs...)`, как `claimWith`, по байтам эффектов `detach` (`machineWith`); операции пробы — `{"if": …, "then": […]}`, `{"forEach": …}`, `{"world": "log", …}`, как в `effects_test.go`.

```go
func TestRunAllDetachAll(t *testing.T)
  // detach [L1, L2] ⇒ оба "new", linkedTo "", linkedAt 0, leftGroup {primaryId P, linkedAt — прежний, at Now};
  // Journal[L1] и [L2] — [workflow.journal.detach]; у P записей нет (у clearLink в detach ключи журнала пусты);
  // Incidents — [L1, L2] по Order, у каждого version +1; P не записан; Facts[L1].To.State "new"
func TestRunAllEmptyIsOk(t *testing.T) // detach [] ⇒ NoError, Refusal nil, Incidents пуст, LockCalls() == 0, Writes() == 0; неизвестный переход [] ⇒ Refusal unknown_action
func TestRunAllFirstRefusalNamesIncident(t *testing.T) // [L1, X], X "new" ⇒ Refusal{Key "workflow.guard.wrong_state", NotFrom true, ID X}; Writes() == 0
func TestRunAllOneTransaction(t *testing.T)
  // копия: у detach последним эффектом _failOnL2: {"if": "incident.id == '<L2>'", "then": [{"let": "t", "value": "incident.timers['nope']"}]} ⇒
  // ошибка; L1 не изменился, Writes() == 0
func TestRunAllSecondSeesFirst(t *testing.T)
  // копия: у detach первым эффектом _probe: {"set": "incident.transferCount", "value": "size(linkedOf(incident.linkedTo))"} ⇒
  // у L1 — 2, у L2 — 1 (L1 уже отсоединён в черновике)
func TestRunAllFactsAfterOperation(t *testing.T)
  // копия: у detach эффект _ownerOfL1OnL2: {"if": "incident.id == '<L2>'", "then": [{"forEach": "z", "in": "incidentById('<L1>')", "do": [{"set": "z.owner", "value": "'op9'"}]}]} ⇒
  // Facts[L1].To.Owner == "op9" (факты — после всей операции; по шагу было бы "")
func TestRunAllEmptyLogAfterOperation(t *testing.T)
  // копия: у detach первыми — alertUse (journal_test.go) и _logL1OnL2 (на шаге L2 — {"world": "log"} инциденту L1 с ключом 'k', vars {});
  // w.Facts["isGroup"] — grp-leads ⇒ keys(Journal[L1]) == [detach, k, workflow.journal.alert_no_recipient] («некому» — после всех шагов)
func TestRunAllRetriesFamilyChanged(t *testing.T) // HideFromFamily(P, 1) ⇒ NoError, LockCalls() == 2, Writes() == 1
```

- [x] **Step 2: Тесты падают**

Run: `go test ./internal/im/service/transition/ -run RunAll 2>&1 | tail -3`
Expected: FAIL — `RunAll` не объявлен.

- [x] **Step 3: Реализация**

- [x] **Step 4: Тесты проходят**

Run: `go test -race ./internal/im/service/transition/... && golangci-lint run ./...`
Expected: PASS, прежние тесты — без правки; lint — 0.

- [x] **Step 5: Commit**

Сообщение: «Этап 4б: ядро — «Отсоединить все» одним переходом на всех: проверки всех до эффектов, один черновик, отказ называет инцидент, всё или ничего; пустой список — пустой итог».
Run: `git add internal/im/service/transition && git commit -q -F .git/COMMIT_MSG_STAGE4B`

---

### Task 17: Ядро — объединение и «Взять» основного (`Merge`)

**Files:**
- Modify: `internal/im/service/transition/core.go` (`Op.PrimaryID`)
- Create: `internal/im/service/transition/merge.go`; Test: `internal/im/service/transition/merge_test.go`
- Test: `internal/im/handler/test/transition_test.go`

**Interfaces:**
- Consumes: задачи 15, 16.
- Produces:
  - `Op.PrimaryID string` — основной объединения; у `Run`, `RunAll` — пусто, иначе ошибка;
  - `func (c *Core) Merge(ctx model.AppContext, repo Repo, w World, op Op) (*Result, error)` — `op.PrimaryID` — основной (его выбирает вызывающий: `mergePrimary` машины — 4в); `op.IDs` — присоединяемые, основной из них убирается (как `server.js`), пустой список — решение 38; `op.Transition`, `op.Form`, `op.Surface` — пусто (переход — `bulk.mode: merge` машины, «Взять» — `grouping.takeWith`; форма шага объединения — `{primaryId}`, «Взять» — `{}`, как `mergeCheck`; форм у этих переходов в машине нет, `checkForm` не вызывается); `Result.Facts`, `Result.External` и `Result.Canceled` — и у основного, если его взяли;
  - `LockFamily(ctx, op.Customer, append(slices.Clone(ids), op.PrimaryID))` (решение 35); основного нет в семье — `ErrNotFound`;
  - запись `merged_in*` — по решению 30 (`Transition` — id перехода объединения).

Порядок (как `mergeCheck` и `merge` в `engine.js`; решения 13, 14 плана 53, 30, 34, 35, 38): семья основного и всех присоединяемых одной блокировкой → `Expect` → переход `bulk.mode: merge` доступен каждому присоединяемому с формой `{primaryId}` (первый отказ — `Refusal` с `ID`); основной в `from` перехода `grouping.takeWith` — «Взять» доступно основному (отказ — `ID` основного) → окно у каждого присоединяемого (по переходу объединения) и у основного (по «Взять»), отметки и `timer_overridden` — до шагов → шаг 1: объединение на присоединяемых, шаг 2: «Взять» на основном — один черновик → «некому» → факты → окно после: присоединяемые по порядку, затем основной → запись `merged_in*` основному последней → журнал, версии, `Write`.

- [x] **Step 1: Тесты**

Основной P `new`; A `new`, B `in_progress` у `op1`; у A привязанный C; один сценарий; `me` — `op1`; номера P, A, B, C — `INC-0001`…`INC-0004` (`MemRepo` в этом порядке); мир — `world()` с `ShareAnswersFunc`, который возвращает `0` (`copyAnswersToPrimary` спрашивает мир, а у `DefaultWorld` `ShareAnswers` нет); для окна — `windowWorld()` (`window_test.go`: `can` для `petrova` и `noc` — false, эскалировать некому) с тем же `ShareAnswersFunc`; в тесте с базой — `f.serverWorld(ctx, rest)` с таким же `rest`.

```go
func TestMergeWithTake(t *testing.T)
  // ⇒ A, B — "linked", linkedTo P; P — "in_progress", owner "op1"; Journal[P] кончается на claim, затем
  // merged_in {Vars {"ids": "INC-0002, INC-0003"}, Actor "op1", Kind "transition", Transition "merge"} — последней; Facts[P].To.State "in_progress"
func TestMergeTakeSeesRelink(t *testing.T)           // C (привязан к A) после объединения — linkedTo P (relinkToPrimary); C в Incidents с version +1
func TestMergeTakeSeesTightenedDeadline(t *testing.T)
  // присоединяется только A; P: resolution на паузе с остатком 1 500 000; A: resolution на паузе с остатком 300 000 ⇒ tightenPrimaryDeadline ставит P left 300 000,
  // «Взять» (resumeTimer resolution) видит его: P.timers.resolution.due == Now + 300 000 (а не Now + 1 500 000);
  // у P одна запись workflow.journal.group_deadline (once)
func TestMergePrimaryNewDuringMergeEffects(t *testing.T)
  // копия: у merge первым эффектом _probe: {"set": "incident.result", "value": "incidentById(form.primaryId)[0].state"} ⇒ у A и B result "new"
func TestMergePrimaryInProgressNoTake(t *testing.T)  // P "in_progress" у op1 ⇒ записи claim у P нет; merged_in — последняя; Facts[P] нет
func TestMergeWithoutOthersIsTake(t *testing.T)
  // IDs [] (и IDs [P] — основной убран) ⇒ P "in_progress" у op1, Journal[P] — [claim], merged_in нет;
  // P "in_progress" у op1 и IDs [] ⇒ NoError, Incidents пуст, Writes() == 0
func TestMergedInMore(t *testing.T)                  // 7 присоединяемых ⇒ merged_in_more {"ids": первые 5 номеров через ", ", "more": int64(2)}
func TestMergeRefusalNamesIncident(t *testing.T)     // у B другой сценарий ⇒ Refusal{Key "workflow.guard.merge_scenario", Guard "sameScenarioAsPrimary", ID B}; Writes() == 0
func TestMergeTakeRefusalNamesPrimary(t *testing.T)  // can("op1", "incident:claim") false ⇒ Refusal{Key "workflow.guard.no_permission", ID P}
func TestMergeWindowEach(t *testing.T)
  // windowWorld(); у A и у P reaction.due = Now − 1000 ⇒ Canceled {A: "escalation_ceiling", P: "escalation_ceiling"};
  // Journal[A] и Journal[P] начинаются с timer_overridden; Journal[P] кончается на merged_in
func TestMergeLocksPrimary(t *testing.T)
  // P — своё событие, не сосед и не привязан; обёртка над MemRepo пишет ids вызовов LockFamily ⇒ [[A, B, P]];
  // LockCalls() == 1, NoError (без P в блокировке — ErrFamilyChanged ×3)
// transition_test.go (с базой)
func TestConcurrentMergeAndClaimOnPostgres(t *testing.T)
  // P new, A new (f.newIncidents, один сценарий); одновременно Merge(P, [A]) от op1 и claim P от op2 (как claimTogether, slowLockRepo) ⇒
  // ни у одного нет 40P01; основного берёт ровно один; у победившего Merge — A linked_to P в базе, журнал P кончается на merged_in
```

- [x] **Step 2: Тесты падают**

Run: `go test ./internal/im/service/transition/ -run Merge 2>&1 | tail -3`
Expected: FAIL — `Merge` и `Op.PrimaryID` не объявлены.

- [x] **Step 3: Реализация**

- [x] **Step 4: Тесты проходят**

Run: `go test -race ./internal/im/service/transition/... && TESTDB='postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable' && IM_TEST_DB_URL=$TESTDB go test -race ./internal/im/handler/test/ -run 'TestConcurrentMergeAndClaimOnPostgres|TestConcurrentClaim|TestLockFamilyNoDeadlock' && golangci-lint run ./...`
Expected: PASS; lint — 0.

- [x] **Step 5: Commit**

Сообщение: «Этап 4б: ядро — объединение и «Взять» основного одной транзакцией на общем черновике; основной — в блокировке семьи; окно после дедлайна у каждого; запись merged_in — в той же транзакции, последней».
Run: `git add internal/im/service/transition internal/im/handler/test/transition_test.go && git commit -q -F .git/COMMIT_MSG_STAGE4B`

---

### Task 18: Лента Go для векторов переходов

**Files:**
- Create: `internal/im/service/transition/transitiontest/tape.go`; Test: `internal/im/service/transition/transitiontest/tape_test.go`

**Interfaces:**
- Produces: `type TapeEntry struct { Fn string; Args []any; Out any }`; `func NewTape(m *machine.Machine, entries []TapeEntry) *Tape` — `transition.World`: `Fact` — по `fn` и аргументам, как `tapeWorld` 4а (`callKey`, `tapeArg`, `canon` из `internal/im/machine/tape_test.go` — тестовый файл, не импортируется: повторить; инцидент в аргументах — карта со всеми полями `m.Data("cel.types.Incident")`, по `id`; `json.Number` и `int64` — одно); `ActorName`, `Progress`, `StepNumber`, `ShareAnswers` — записи `ctx.*`; `SetCursor`, `ShareAnswers` — и в `Scenario()`; промах — ошибка и запись в `Misses()`; `Unused()` — счёт.

- [x] **Step 1: Тесты**

```go
func TestTape(t *testing.T) // попадание — out; json.Number("5") и int64(5) — одно; инцидент — по id; ctx.actorName — по id; вызова нет — ошибка, Misses() == ["can(...)"]; два ответа — промах; Scenario() по порядку
```

- [x] **Step 2: Тесты падают** — `go test ./internal/im/service/transition/transitiontest/ -run TestTape`: FAIL — `NewTape` не объявлен.

- [x] **Step 3: Реализация**

- [x] **Step 4: Тесты проходят** — `go test -race ./internal/im/service/transition/... && golangci-lint run ./...`: PASS; lint — 0.

- [x] **Step 5: Commit**

Сообщение: «Этап 4б: лента мира для векторов переходов на Go — факты машины и функции сервера по записи прототипа».
Run: `git add internal/im/service/transition/transitiontest && git commit -q -F .git/COMMIT_MSG_STAGE4B`

---

### Task 19: Формат векторов и сравнение на Go

**Files:**
- Create: `internal/im/service/transition/transitiontest/{vectors.go, compare.go}`; Test: `internal/im/service/transition/transitiontest/compare_test.go`

**Interfaces:**
- Consumes: задача 18.
- Produces:
  - `func LoadTransitionVectors(path string) (*TransitionFile, error)` — `UseNumber`, `$ref` разворачиваются (как `loadVectors` и `resolveRefs` в `internal/im/machine/vectors_test.go`); `type TransitionVector struct{…}` — поля формата; `TransitionFile.Uncovered`;
  - `type Run struct { Before []transition.Row; Result *transition.Result; Created []*transition.Created; Err error; Repo *MemRepo; Tape *Tape }`;
  - `func Compare(v *TransitionVector, r *Run) []string` — расхождения с ожидаемым словами; `func Same(a, b *Run) []string` — расхождения двух прогонов; пусто — совпало. Оба — по решению 41; `create`: `Created` — инцидент, журнал, `After`, `External`, `Facts`.

- [x] **Step 1: Тесты**

```go
func TestCompareNormalizes(t *testing.T)
  // since у reaction — не расхождение, у hold — расхождение; closeResultLabel [""] против "" — не расхождение, счёт 1;
  // json.Number и int64 — одно; vars nil = {}; evict who "" = null; Transition записи — не сравнивается;
  // refusal: guard, notFrom, code сравниваются, если есть в ожидаемом; error — Go-ошибка, но не ErrFamilyChanged
func TestSameIgnores(t *testing.T) // Row.Order, абсолютные версии, JournalEntry.ID — не расхождение; другой Transition, Canceled, порядок After — расхождение
```

- [x] **Step 2: Тесты падают** — `go test ./internal/im/service/transition/transitiontest/ -run 'Compare|Same'`: FAIL — `Compare` не объявлен.

- [x] **Step 3: Реализация**

- [x] **Step 4: Тесты проходят** — `go test -race ./internal/im/service/transition/... && golangci-lint run ./...`: PASS; lint — 0.

- [x] **Step 5: Commit**

Сообщение: «Этап 4б: формат векторов переходов и сравнение на Go — пусто, числа, since, closeResultLabel, отказ и ошибка».
Run: `git add internal/im/service/transition/transitiontest && git commit -q -F .git/COMMIT_MSG_STAGE4B`

---

### Task 20: Сверка ядра Go с векторами переходов (в памяти)

**Files:**
- Create: `internal/im/service/transition/transitiontest/run.go`; Test: `internal/im/service/transition/vectors_test.go`

**Interfaces:**
- Consumes: задачи 14–19; `api/im/operator/transition-vectors.json` — по пути `../../../../api/im/operator/transition-vectors.json`; `MemRepo` (`NewMemRepo`, `AddJournal`, `Writes`, `Rows`, `Journal`, `LastWrite`).
- Produces (для тестов):
  - `type Order int` — `VectorOrder` (место в `incidents`) или `NumberOrder` (число из `number`);
  - `func RunVector(core *transition.Core, m *machine.Machine, v *TransitionVector, order Order) *Run` — машина передаётся явно (`Core.m` не экспортирован, `Core` её не отдаёт); `NewMemRepo` из пула в порядке `order`, `journalAtNow` — `AddJournal` (с ID); лента — `NewTape(m, v.World)`; `op` — `core.Run`, `core.RunAll`, `core.Merge` (`Op.PrimaryID` — `target.primaryId`) или `core.Create(tape, v.Now, []map[string]any{incident})`; `Op.Customer` — любой UUID (`MemRepo` его не читает);
  - `func RunVectorOn(core *transition.Core, v *TransitionVector, ctx model.AppContext, repo transition.Repo, customer uuid.UUID, tape *Tape) *Run` — то же на чужом хранилище (задача 21: PostgreSQL), `Run.Repo` — `nil`.

- [x] **Step 1: Тесты**

```go
func TestTransitionVectors(t *testing.T)
  // MachineSHA256 == sha256(operatorapi.Machine); подтест на каждый id, порядок — VectorOrder; упал — расхождения в сообщении;
  // промах ленты — провал; в конце t.Logf: "transition vectors N (run …, runAll …, merge …, create …), mismatches M, tape misses K, unused tape entries U, closeResultLabel normalized C"
func TestTransitionVectorsCoverMachine(t *testing.T)
  // у каждого перехода trigger: manual и у create — вектор ok, кроме имён TransitionFile.Uncovered (то же, что UNCOVERED_TRANSITIONS_OK)
```

- [x] **Step 2: Тесты падают**

Run: `go test ./internal/im/service/transition/ -run 'TestTransitionVectors' 2>&1 | tail -3`
Expected: FAIL — `RunVector` не объявлен.

- [x] **Step 3: Реализация** `RunVector`, `RunVectorOn`.

- [x] **Step 4: Прогон и разбор расхождений**

Run: `go test ./internal/im/service/transition/ -run 'TestTransitionVectors' -v 2>&1 | grep -E '^(--- FAIL|ok|FAIL)|transition vectors [0-9]' | tail -30`
Expected: расхождения, если есть. Каждое разобрать: правится ядро (задачи 5–9 плана 53, задачи 1, 15–17 этого), а не вектор; похоже на ошибку прототипа — **стоп, спросить**. Каждую причину — в журнал работ.

- [x] **Step 5: Тесты проходят**

Run: `go test -race ./internal/im/service/transition/ -v -run 'TestTransitionVectors' 2>&1 | grep -E 'transition vectors [0-9]|^ok|FAIL' && golangci-lint run ./...`
Expected: `ok`; `mismatches 0, tape misses 0`, `closeResultLabel normalized 0`; число векторов — как `counts` файла; lint — 0.

- [x] **Step 6: Commit**

Сообщение: «Этап 4б: сверка ядра переходов Go с прототипом — все векторы переходов совпадают в памяти; отказ и ошибка различаются, мир — по ленте».
Run: `git add internal/im/service/transition && git commit -q -F .git/COMMIT_MSG_STAGE4B`

---

### Task 21: Сверка на PostgreSQL — память и база дают одно

**Files:**
- Create: `internal/im/handler/test/{transition_vectors_test.go, transition_seed_test.go}`

**Interfaces:**
- Consumes: задача 20; `transition.NewStoreRepo(store, timerIDs)` (план 53, задача 10); помощники `intakeFixture` (`newIntakeFixture`, `inRolledBackTx`, `insertCustomer`, `timerIDs`, `pgCore`).
- Produces (только тесты): `func (f *intakeFixture) seedVector(t *testing.T, ctx model.AppContext, v *transitiontest.TransitionVector) uuid.UUID` — в откатываемой транзакции, арендатор — новый (`f.insertCustomer`), его id — ответ. Кладёт: тип источника, источник и типы событий арендатора (`source_event_types.uid` = `eventType` пула); события с `guid` = `eventGuid`, `occurred_at` и своим типом; приоритеты с нужными `value`; сценарии (`scenario_definitions`, `scenarios`) с `guid` пула; инциденты пула — `transition.FromMachine` в `model.MachineIncident` (поля только для чтения — из вектора), `status_guid` — по состоянию (`model.StatusCodeForState`), номер — из `number` (новый арендатор: счётчик не нужен, номер — часть вектора), два прохода (решение 31); `journalAtNow` — `InsertJournalEntries` (`transition.JournalRow`).

Для каждого вектора `op` `run`, `runAll`, `merge` (у `create` в ядре нет хранилища), который можно положить в базу (решение 31): `f.inRolledBackTx` → `seedVector` → `RunVectorOn(core, v, ctx, transition.NewStoreRepo(f.store, timerIDs(t)), customer, transitiontest.NewTape(m, v.World))` (ядро идёт в точке сохранения транзакции теста — ADR-005, решение 4); эталон — `RunVector(core, m, v, NumberOrder)`; сравнение — `Same` (решение 41), плюс журнал, прочитанный из базы; транзакция откатывается.

- [x] **Step 1: Тесты**

```go
func TestTransitionVectorsOnPostgres(t *testing.T)
  // подтест на каждый вектор run, runAll, merge: Same(база, NumberOrder) пусто; новые записи журнала из базы == Result.Journal; версии в базе — +1 у Result.Incidents;
  // в конце t.Logf: "postgres vectors N, mismatches 0, order-sensitive K, memory-only M (not uuid …, no event …, link outside pool …, event+scenario twice …, event fields differ …, number …)"
  // (K — векторы, у которых VectorOrder и NumberOrder дают разный итог; M у записанных, без case, — 0, иначе — стоп, спросить)
func TestSeedVectorRoundTrip(t *testing.T) // для 20 первых векторов: GetMachineIncidents по пулу (ToMachine) == инциденты вектора, linked_to — на месте
```

- [x] **Step 2: Тесты падают**

Run: `TESTDB='postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable' && IM_TEST_DB_URL=$TESTDB go test ./internal/im/handler/test/ -run 'TestTransitionVectorsOnPostgres|TestSeedVectorRoundTrip' 2>&1 | tail -3`
Expected: FAIL — `seedVector` не объявлен.

- [x] **Step 3: Реализация** `seedVector`.

- [x] **Step 4: Прогон и разбор расхождений**

Run: `IM_TEST_DB_URL=$TESTDB go test ./internal/im/handler/test/ -run 'TestTransitionVectorsOnPostgres|TestSeedVectorRoundTrip' -v 2>&1 | grep -E '^(--- FAIL|ok|FAIL)|postgres vectors' | tail -20`
Expected: расхождения, если есть: правится хранилище или ядро, не тест. `ErrFamilyChanged` у вектора после трёх попыток — семья (решение 15 плана 53) не берёт того, кому пишет машина: **стоп, спросить** (меняется правило семьи).

- [x] **Step 5: Тесты проходят**

Run: `IM_TEST_DB_URL=$TESTDB go test -race ./internal/im/handler/test/ -run 'TestTransitionVectorsOnPostgres|TestSeedVectorRoundTrip' -v 2>&1 | grep -E 'postgres vectors|^ok|FAIL' && make test-local 2>&1 | tail -10 && golangci-lint run ./...`
Expected: `ok`; `mismatches 0`; время прогона — в журнал работ (больше 3 минут — **стоп, спросить**); числа `order-sensitive` и `memory-only` — в журнал работ, первое — и в ответ на открытый вопрос 3 плана 53; все пакеты; lint — 0.

- [x] **Step 6: Commit**

Сообщение: «Этап 4б: векторы переходов на PostgreSQL — ядро на базе даёт то же, что в памяти: семья, кандидаты фактов, запись с версией, журнал».
Run: `git add internal/im/handler/test && git commit -q -F .git/COMMIT_MSG_STAGE4B`

---

### Task 22: ADR, документы, последний прогон

**Files:**
- Modify: `docs/adr/005-transitions-in-transaction.md` (векторы переходов и их итог, правила сравнения; `RunAll`, `Merge`, `Op.PrimaryID`, пустой список; шаги операции — решение 34; `merged_in*`; основной вне семьи — решение 33; число векторов, зависящих от порядка; «Carried to 4b-2 and 4c» — сделанное убрать, оставить пункты 4в), `docs/adr/004-machine-executor.md` (`Consequences`, «Next» — 4в)
- Modify (IM): `research/integration/40-plan.md` (строка «Что уже готово» этапа 4б-1 — «Столбцы инцидента и переходы в транзакции (этап 4б)» со ссылками на 53 и 54; в разделе этапа 4 — 4а и 4б сделаны, 4в впереди), `research/integration/54-plan-stage4b2.md` (отметки, «Итог этапа 4б-2» — таблица задач и коммитов, как «Итог этапа 4б-1» плана 53)

- [x] **Step 1: ADR** — дописать в ADR-005 по итогам задач 1–21.

- [x] **Step 2: Документы IM** — перед правкой `git -C /mnt/hgfs/VmWareShared/soul2home/IM fetch`; новое — сказать пользователю.
Run: `cd /mnt/hgfs/VmWareShared/soul2home/IM && python3 tools/check_links.py && node tools/cel_vectors.mjs --check | grep -E '^(векторов|векторов переходов):'`
Expected: «Нерабочих ссылок: 0»; обе строки векторов — `расхождений: 0`.

- [x] **Step 3: Последний прогон сервера**

Run: `cd ~/Work/incident-manager-server && source ~/go/offline-env.sh && go test -race $(go list ./internal/im/... | grep -v /handler/test) && make test-local 2>&1 | tail -15 && go vet ./... && gofmt -l internal/im && golangci-lint run ./...`
Expected: всё PASS; `go vet`, `gofmt -l` чисто; lint — 0.

- [x] **Step 4: Commit (два репозитория)**

Сервер — «Этап 4б: ADR-005 — векторы переходов, «Отсоединить все», объединение». Run: `git add docs/adr && git commit -q -F .git/COMMIT_MSG_STAGE4B`
IM — «Этап 4б встраивания: столбцы инцидента, переходы в транзакции и векторы переходов — план отмечен». Run: `cd /mnt/hgfs/VmWareShared/soul2home/IM && git add research/integration/40-plan.md research/integration/54-plan-stage4b2.md && git commit -q -F .superpowers/sdd/54-plan-stage4b2/commit-msg.txt`

---

## Не в этом этапе

| Что | Когда |
|---|---|
| Векторы планировщика (`tick`): переходы по таймеру и системные, `agentIdleFor`, `changedAt`, порядок догона | 6 (минимум для `/test/clock` — 4в) |
| Векторы на уровне HTTP: `If-Match`, коды `403`/`409`/`412`/`422`, `externalEffects` ответа, `journalEntries` с текстом, версии (и решение 16 плана 53: Go даёт версию и инциденту, которому достался только журнал) | 4в (по образцу `tests/api.html`, когда вход заработает) |
| Ответы HTTP на итог ядра: `Refusal` — условие `403`, не то состояние `409`, форма `422`; `*VersionConflict` и `ErrFamilyChanged` — `412` | 4в: маршрутов HTTP в этом этапе нет |
| Маршрут перехода HTTP пускает только `trigger: manual` (ядро исполняет любой переход машины по id) | 4в: маршрута нет; ядро вызывают только тесты и приём события |
| Несколько вызовов ядра в одной транзакции вызывающего, уровень REPEATABLE READ — запрет записать в договор вызывающего | 4в: вызывающего с транзакцией в 4б-2 нет, кроме теста задачи 21 (один вызов в точке сохранения) |
| Ключ `Expect` вне семьи — `ErrNotFound`: решить вместе с массовыми `expectedVersions` | 4в: `RunAll` и `Merge` здесь ведут себя как `Run` |
| Машина приёма события — из ядра (`intake.NewService` грузит свою `machine.Vendored()`, хотя получает ядро `transition.New` от `appservice`) | 4в: поведение не меняется, это одна загрузка машины вместо двух |
| `shareAnswers` без `logKey` не даёт версии +1 (сценарий меняется, версия нет) | 4в: версии — слой HTTP (`412`), векторы ядра версий не сравнивают; настоящий перенос ответов — этап 6, до него `ShareAnswers` сервера — заглушка `STAGE6` (`n = 0`) |
| Вложенный `DoInTx` у `MemRepo` | не делается (решение 36): в 4б-2 вложения нет, путь с точкой сохранения проверен на PostgreSQL |
| Массовое действие `each_allowed`, `bulk.scope`, выбор основного `mergePrimary`/`bulkPrimary`, `minItems`, `maxBulk`, `expectedVersions` | 4в |
| Синтетика объединения: `merged_in_more` | не делается: случай закрыт тестом Go `TestMergedInMore` (задача 17), вектора у него нет. `once` у `tightenPrimaryDeadline` сделан: синтетический вектор замены записи журнала (задача 20б) и требование покрытия `journal:once`; синтетический случай пишет запись `merged_in` сам, как `server.js` (запись `merged_in*` — у `server.js`, ядро прототипа её не даёт). `TestMergeTakeSeesTightenedDeadline` (задача 17) и `TestLogOnce` (план 53, задача 9) остаются |
| Версия и `incident.updated` у уже привязанных открытых инцидентов основного и у не взятого основного, когда никто не присоединён (так делает `server.js` при объединении, Go — нет) | 4в: открытый вопрос 7; рекомендация — обработчик трогает их после фиксации |
| `canceled` у `runAll` и `merge`, `external` основного при объединении в векторах | не делается: ядро прототипа их не возвращает; у Go они есть и проверены тестами задач 16, 17 |
| Перенос ответов сценария по-настоящему (`shareAnswers` с `n > 0`), курсор | 6; в векторах — по ленте `ctx.shareAnswers` |
| Порядок списка инцидентов в прототипе по номеру | по ответу на открытый вопрос 3 плана 53 (пункт ревью IM); ответ по измерению — в открытом вопросе 4 ниже, для подтверждения |
| Из ядра в 4в без изменения поведения: соответствие `Refusal`, `VersionConflict`, `ErrFamilyChanged` кодам HTTP; отказ объединения без охранника — `422 BULK_SELECTION_INVALID`; пустой итог с `nil` вместо `{}`; ошибка повторного id — сторож и `400`, id убирает обработчик до ядра; только ручные переходы; один `Run` на транзакцию вызывающего, без REPEATABLE READ; машина приёма события — из ядра | 4в (ADR-005, «Carried to 4c») |

## Решения этого плана — обоснования (приняты ведущим 2026-10-30; 38–41 — по ревью плана)

23. **Отдельный файл, тот же инструмент.** У векторов переходов свой пул (инциденты целого списка) и свой размер; смешать с `cel-vectors.json` — значит менять формат 1 и `TestVectors` 4а. Отдельный инструмент дал бы второй прогон Chrome на ~6 минут; тот же прогон пишет оба блока.
24. **Обёртка ядра, как в 4а.** Ядро — единственное место, где у прототипа есть переход целиком; обёртка `IMEngine.create` видит его вход и итог, не меняя `server.js`.
25. **`since` — только у `hold`.** Машина пишет `since` при запуске любого таймера, а мост прототипа хранит его только у `hold` (`FIELDS`); у остальных его никто не читает. Без правила почти каждый вектор с запуском таймера разошёлся бы на поле без смысла; так же уже сравнивает модель Quint.
26. **Лента на уровне `cel.world`, пусто — `""`.** Мир Go говорит именами и аргументами `cel.world`, а `ctx` прототипа — своими (`permsOf(who)` — список, `can` — `includes`). Кадр записи 4а уже видит факты так, как их видит машина. `null` у прототипа — то же «пусто», что `''` у машины и `""` у Go; писать его как есть — значит получить расхождения, которых нет.
27. **В векторе — только то, что ядро прототипа отдаёт.** Восстанавливать `canceled` у `runAll` и `merge` по журналу — значит писать в инструменте логику ядра; запись `timer_overridden` и так сравнивается, а Go-поля проверяют свои тесты. `Transition` записи журнала прототип в ядре не держит (его дописывает `server.js`), версии — слой HTTP.
28. **Пределы отбора меньше, чем у CEL.** Вектор перехода в десятки раз больше вектора выражения (весь список и длинная лента); 20 на `op:name` и 4 на исход при 15 именах — не больше 300 векторов. Размер зависит от длины списка, поэтому оценивается первым прогоном, а не заранее.
29. **Две сверки вместо одной.** Порядок списка у прототипа — порядок набора, у базы — номер (открытый вопрос 3 плана 53). Цепочка «прототип = Go в памяти в порядке вектора» и «Go в памяти в порядке номеров = Go в базе» проверяет и смысл, и SQL полностью, а цену вопроса о порядке показывает числом.
30. **`merged_in*` в ядре Go.** BACKEND.md: переход — одна транзакция с журналом. Запись — часть итога объединения, вектор её ждёт (указание 2 плана 53). Пять — значение `server.js`, а не машины: в Go — константа с комментарием-ссылкой; перенос в машину — открытый вопрос.
31. **UUID у синтетики и два прохода.** База требует UUID, событие и сценарий у каждого инцидента, не больше одного инцидента на пару «событие, сценарий», а время и тип события хранит в событии, не в инциденте; номер — число. Синтетика 4а с id `s1` в неё не ляжет. Записанные векторы приходят из тестов API с UUID (эталонный набор: 28 инцидентов, у всех UUID и событие, пар-повторов нет) — у них «только память» быть не должно, иначе база проверяет не всё. Внешний ключ `linked_to` требует, чтобы основной уже был в таблице; основной сам не привязан, поэтому хватает двух проходов.
32. **Без шага самопроверки.** Самопроверка проверяет то, что видит пользователь; запись векторов — инструмент тестов, как запись векторов CEL в 4а.
33. **Основной вне семьи — только живой.** Проверка 4б-1 защищает от гонки: параллельная транзакция привязала инцидент после снимка, и эффекты прочли бы основного без блокировки. Удалённого основного блокировка не берёт никогда (`deleted_at IS NULL` в `lockIncidentFamilySQL`), повтор ничего не меняет, и операция над привязанным к нему инцидентом кончалась бы `ErrFamilyChanged` всегда. Живость проверяется тем же запросом `incidentById`, что у фактов, — нового метода `Repo` не нужно. Прежний тест не ловил отсутствие проверки: его основной — сосед по событию, и `close` писал ему сам.
34. **Шаги как у прототипа.** `applySteps` собирает факты после фиксации всех шагов, а записи «некому» — в `after`, после всех шагов; `merge` и `runAll` ищут окно у каждого инцидента. Если оставить по шагу, у объединения с «Взять» и у «Отсоединить все» векторы разойдутся там, где второй шаг меняет первого. У одиночного перехода порядок тот же, поэтому тесты 4б-1 не меняются; перестройка идёт отдельной задачей при зелёных тестах.
35. **Основной — в блокировке объединения.** Основной не обязан быть соседом или основным присоединяемых: его выбирают из выборки. Без него в `LockFamily` запись ему — вне семьи, а внешний ключ `linked_to` берёт его строку `FOR KEY SHARE` уже после блокировки семьи, вне порядка номеров. Одна строка в списке id снимает оба риска.
36. **`MemRepo` не вложенный.** Вложенный `DoInTx` в памяти нужен, только если ядро идёт в транзакции вызывающего, а это путь PostgreSQL (точка сохранения), и он проверен на базе. Повторять точки сохранения в памяти — код в тестовом хранилище без потребителя.
37. **`closeResultLabel` — нормализация, а не правка.** На машине разница не возникает (у всех пунктов справочников есть `labelKey`); править Go под «ложное» значение пустой строки JS — значит повторять особенность прототипа без случая. Счёт в логе покажет, если случай появится.
38. **Пустой список — как у прототипа.** Тесты API уже ждут `200` от «Отсоединить все» без привязанных, а объединение выборки из одного — это «Взять»; ошибка Go на пустом списке дала бы вектор, который ядро Go не проходит. Без инцидентов нечего блокировать и писать, поэтому нет и `LockFamily`; у объединения основной всё равно берётся под блокировку, его же берут в работу.
39. **Лента объединения закрывается на возврате.** После `engine.merge` `server.js` зовёт `emitTransition` и `card(primary)`, а они спрашивают мир; с открытым кадром эти вызовы попали бы в ленту и Go не нашёл бы им пары. Отложить нужно только одно — запись `merged_in*`, которую `server.js` пишет своим `log`. Следующий вызов может быть у ядра коллеги или у планировщика (`runScheduler` → `tick`), поэтому закрывает любой обёрнутый вызов; а проверка «ничего больше не изменилось» идёт по всему списку, потому что `touch` и прочее `server.js` может задеть и чужие инциденты.
40. **Отбор при записи.** Хранить всё до конца прогона — значит держать в памяти браузера полный список инцидентов на каждый вызов ядра, а прогулки `api-properties` дают их сотни. Отбор на закрытии держит не больше 300 векторов и пул только их; повторяемость сохраняется, потому что запись идёт с зафиксированными часами и случайными числами.
41. **Правила сравнения — в одном месте.** JS-повтор, `Compare` и `Same` сравнивают разное (вектор против Go, память против базы), но по одним правилам; разбросанные по разделам, они расходились бы между тремя реализациями. Каждое правило снимает расхождение без смысла: пусто против `null`, `json.Number` против `int64`, `nil` против `{}`, место в списке против номера, ID записей журнала, которые выдаются заново.

## Открытые вопросы

Работу не задерживают: исполнитель идёт по ответам плана (решение ведущего 2026-10-30).

1. Тип события в условии правила — по `uid` или по паре «тип устройства + `uid`» (вопрос от 2026-10-29). План следует `uid`.
2. Число номеров в записи `merged_in` (5, `MERGED_IN_SHOWN` в `server.js`) — оставить константой сервера (план) или перенести в машину (`grouping.mergedInShown`, правка IM)? (Вопрос 7 плана 53.)
3. Отбор: 20 векторов переходов на `op:name`, 4 на исход, файл до 4 МБ — достаточно? (Вопрос 8 плана 53.)
4. Вопросы 2–6 плана 53 остаются с ответами по умолчанию (`transition_failed` у прототипа — `422`; порядок списка инцидентов; `countMine` вне блокировки; прогресс сценария 0 при `create` до этапа 6; инциденты стенда без таймера реакции); ответ на 3 получен в задаче 21, см. ниже.
   **Порядок списка — ответ по измерению (задача 21), для подтверждения пользователем.** У 79 из 87 векторов на PostgreSQL порядок списка отличается от порядка номеров; на этих 79 число векторов, где итог ядра зависит от порядка, K = 0. С обратным пулом R = 0 из 87. Значит, на этих векторах итог ядра от порядка списка не зависит. Это не доказательство для любого пула: не проверяли, есть ли такой вектор, где у одного факта два кандидата и машина берёт первого. Если такое правило появится, нужен вектор на него.
5. Удалённый основной (решение 33): ядро идёт дальше, как будто основного нет, — у привязанного к нему инцидента условия машины решают сами (`detach` откажет по `primaryEditable`). Так оставить (план) или при мягком удалении основного отвязывать его привязанных (правило IM)?
6. `closeResultLabel` (решение 37): нормализовать при сравнении (план) или сделать Go как прототип — `""` при пустом ключе подписи?
7. Новый, для 4в. При объединении `server.js` поднимает версию (и шлёт `incident.updated`) у уже привязанных открытых инцидентов основного и у не взятого основного, когда никто не присоединён. Go этого не делает. Где это делать: в ядре, в обработчике после фиксации или оставить разницу? Рекомендация ведущего — обработчик трогает их после фиксации.

## Итог этапа 4б-2

Этап сделан. Ядро переходов сервера повторяет ядро прототипа по векторам: 92 вектора переходов (`run` 62, `runAll` 4, `merge` 21, `create` 5; из них 9 синтетических), записанных на ядре прототипа при тестах API, Go проходит в памяти, 0 расхождений. На PostgreSQL сверено 87 векторов, результат тот же, что в памяти, 0 расхождений; 5 векторов `create` пропущены, потому что ядро создаваемый инцидент не пишет. «Отсоединить все» (`RunAll`) и объединение с «Взять» основного (`Merge`) работают одной транзакцией, запись `merged_in*` в ней же, основной объединения — в блокировке семьи. Зависит ли итог ядра от порядка списка: на этих векторах нет (K = 0 из 79, R = 0 из 87) — ответ по измерению, для подтверждения. Решения и пределы — в ADR-005 сервера, раздел «Stage 4b-2», и в ADR-004.

| Задача | Репозиторий | Коммиты |
|---|---|---|
| 1. Основной вне семьи — только живой, мягкое удаление в `MemRepo` | сервер | `9657c7d` |
| 2. Стыки ядра `fromView` и `ctx.world` | IM | `c1db6a8` |
| 3. Кадры записи CEL | IM | `2959867` |
| 4. Запись `run`, `runAll`, `create`; отбор при записи | IM | `48b1fc5`, `7c20097` (закрывают вектор только изменяющие вызовы) |
| 5. Закрытие вектора объединения | IM | `0f3f9a6` |
| 6. Повтор по ленте | IM | `b384b93` |
| 7. Запись векторов переходов при тестах API | IM | `3b6cae8` |
| 8. `transition-vectors.json`: сборка `--update` | IM | `b4a0dac` |
| 9. `--check` векторов переходов | IM | `d64b7be` |
| 10. Синтетика векторов переходов | IM | `7042eff` |
| 11. Покрытие векторов переходов | IM | `dad852a` |
| 12. `--engine` и проба порчи ядра | IM | `b11da0d` |
| 13. Раздел «Векторы переходов», проверки | IM | `9725a95`, `6f04e4e` (правки по просмотру) |
| 14. Копия векторов переходов на сервере | сервер | `3673426` |
| 15. Шаги операции (без нового поведения у `Run` и `Create`) | сервер | `39ac64d` |
| 16. «Отсоединить все» (`RunAll`) | сервер | `f311d77` |
| 17. Объединение и «Взять» основного (`Merge`), основной в блокировке | сервер | `4fab6bb` |
| 18. Лента Go для векторов переходов | сервер | `60a07d7` |
| 19. Формат векторов и сравнение на Go | сервер | `0dafa2f` |
| 20. Сверка ядра Go с векторами в памяти | сервер | `0aa3c8d` |
| 20б. Синтетический вектор замены записи журнала (`once`), покрытие `journal:once` (добавлена по ревью задачи 20: порча пути `once` пережила все 91 вектор) | IM, сервер | `53094d9` (IM), `f7b5bfd` (сервер) |
| 21. Сверка на PostgreSQL: память и база дают одно; порядок списка | сервер | `bba664b`, `74a97e6` (знаменатель порядка 79, проба обратного порядка, пул в базе у каждого вектора) |
| 22. ADR-005, ADR-004, документы, последний прогон | сервер, IM | `83e5629` (сервер), `e5d0e96` (IM) |
| Правки по итоговому ревью: `Compare` сравнивает порядок `After`; тесты `Expect` для `Merge` и `RunAll`; переносы в 4в в ADR-005; `CEL.md` | сервер, IM | `3f8a6be` (сервер), `453a55c` (IM) |

Последний прогон — в отчёте задачи 22 (`.superpowers/sdd/54-plan-stage4b2/task-22-report.md`): `go test -race` по `internal/im` без `handler/test`, `go test ./...` на `im-test-db` (порт 55432), `go vet`, `gofmt -l`, `golangci-lint` — чисто; `check_links.py` — 0 нерабочих ссылок; `cel_vectors.mjs --check` — 0 расхождений.

Что осталось: 4в — отображение ответов ядра на HTTP, массовые действия, `expectedVersions`, версии при объединении (открытый вопрос 7), векторы уровня HTTP; планировщик и `tick` — этап 6; сценарий (`setCursor`, `shareAnswers` с `n > 0`) — этап 6.
