# Этап 4б-2: векторы переходов, «Отсоединить все» и объединение — план работ

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ядро переходов сервера МИ даёт тот же итог, что ядро прототипа, и это доказано: каждый вектор перехода «инциденты + лента мира + действие → инциденты, журнал, действия после фиксации», записанный на ядре прототипа, ядро Go повторяет в памяти и на PostgreSQL; «Отсоединить все» и объединение с «Взять» основного — одной транзакцией.

**Architecture:** В IM ядро прототипа получает два стыка без правил — обратный мост `fromView` и подмену мира `ctx.world`; `tests/transition-vectors.js` при `tests/api.html?celVectors=1` пишет каждый вызов `run`, `runAll`, `merge`, `create` объекта `IMEngine.create`: список инцидентов, ленту фактов мира (через кадры записи 4а) и функций сервера, итог; записи `merged_in*`, которые `server.js` дописывает после ядра, входят в итог с пометкой `server`. `tools/cel_vectors.mjs` тем же прогоном Chrome собирает и `fixtures/transition-vectors.json`, добавляет синтетику на границах окна и формы, `--check` повторяет векторы на JS. На сервере ядро `transition` (4б-1) получает `RunAll` и `Merge`; тест сверки повторяет каждый вектор на `transitiontest.MemRepo` в порядке вектора, тест с базой — каждый вектор на PostgreSQL против того же ядра в памяти в порядке номеров.

**Tech Stack:** Go 1.27.1, cel-go v0.26.1, PostgreSQL 9.6, testify `require`, golangci-lint v2.14.0; IM — Node 22 (без зависимостей), cel-js 8.0.0, headless Chrome.

**Spec:** [53-plan-stage4b.md](53-plan-stage4b.md) — решения 1–22 (обязательны и здесь), ядро и хранилище; [52-plan-stage4a.md](52-plan-stage4a.md) — формат и запись векторов CEL; [CEL.md, «Векторы»](../../Specification/Workflow_machine/CEL.md#векторы) — пул, лента, канонический JSON; ADR-004 и ADR-005 сервера. Образец — `runAll`, `merge`, `mergeCheck`, `create`, `celWorld`, `writeBack` в [prototype/engine.js](../../prototype/engine.js); `mergeIncidents`, `log`, `engineCtx` в [prototype/server.js](../../prototype/server.js); загрузка ядра в Node и сравнение `since` — `tools/check_quint_replay.mjs` (строки 104–169); запись — `recorder` в [tests/cel-vectors.js](../../tests/cel-vectors.js). Ревью планов 53 и 54 — `plan-review.md` (scratchpad сессии 2026-10-29). Сервер и IM — от последних коммитов 4б-1 (хэши — в «Итог этапа 4б-1» плана 53).

## Global Constraints

- Сервер — `~/Work/incident-manager-server`, IM — `/mnt/hgfs/VmWareShared/soul2home/IM`, обе — ветка `feature/im_operator`, от последних коммитов 4б-1. Пути в задачах — от корня репозитория задачи. Порядок: задачи 1–4 (IM), затем 5–10 (сервер); задача 5 копирует файлы из IM, поэтому начинается только после коммитов задач 1–4 (в `SOURCE` — хэш IM без `dirty`).
- Только локально. Push — только по просьбе пользователя. `~/Work/axxoncloudgo` не менять; кажется, что нужна правка облака, — **стоп, спросить пользователя**.
- Вход отложен; новых маршрутов HTTP нет.
- Тесты с базой — только контейнер `im-test-db` (`127.0.0.1:55432`): `make test-local` или `TESTDB='postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable' && IM_TEST_DB_URL=$TESTDB go test …`; база стенда `imdb` — не для тестов. Контейнер не запущен — `sg docker -c "make test-db-up"`. Пакеты без базы — `go test -race $(go list ./internal/im/... | grep -v /handler/test)`.
- Перед любой командой `go` — `source ~/go/offline-env.sh`. Новых зависимостей нет. Адрес `npm.itvgroup.ru` недоступен, не использовать. Docker — только через `sg docker -c "…"`.
- `make gen` и `make gen-api-im` не запускать; `make gen-api-operator` — только если копия контракта изменилась (в этом этапе не должна: машина и контракт IM не меняются). Сгенерированное руками не править.
- `golangci-lint run ./...` — 0 замечаний в каждой серверной задаче; `gofmt -l internal/im` — пусто.
- Тесты — testify `require`, под `-race`. Комментарии в коде и ADR — по-английски; документы IM — по-русски, простыми словами.
- **Правила IM.** Прототип только исполняет машину: правка `prototype/engine.js` — только стыки для записи и повтора (`fromView`, `ctx.world`), правил IM в коде нет; `server.js` не меняется. Машина, правила и `State_rules/CHANGELOG.md` в этапе не меняются; кажется, что нужно, — **стоп, спросить**. Сгенерированные файлы — только своим инструментом (`fixtures/cel-vectors.json` и `fixtures/transition-vectors.json` — `node tools/cel_vectors.mjs --update`). Перед первой правкой IM — `git -C /mnt/hgfs/VmWareShared/soul2home/IM fetch`; есть новое на GitHub — сказать пользователю.
- Быстрые проверки IM после каждой задачи 1–4 (из `CLAUDE.md`): `python3 tools/build_workflow.py --check && python3 tools/check_machine.py && python3 tools/check_machine.py --mutations && python3 -m unittest tools/test_openapi30.py && node tools/check_cel.mjs && node tools/test_cel.mjs && node tools/cel_vectors.mjs --check && node tools/gen_quint.mjs --check && python3 tools/check_links.py`.
- Временные файлы — в scratchpad сессии исполнителя; в командах ниже он `$S` (задать `S=…` в той же строке). Профиль Chrome у `--update` — `--tmp=$S`, не `TMPDIR` (CEL.md, «Векторы»).
- Векторы руками не правятся. Go расходится с вектором — правится Go. Кажется, что неправ прототип (расходится с BACKEND.md или CEL.md, а решения 2 плана 53 об этом нет), — **стоп, спросить**: это новый пункт ревью в IM, а не правка вектора.
- Коммиты. Сервер — один на задачу, сообщение по-русски, начинается с «Этап 4б: », файл `.git/COMMIT_MSG_STAGE4B`, последняя строка — `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`; `git commit -q -F .git/COMMIT_MSG_STAGE4B`. IM — так же, файл `.superpowers/sdd/54-plan-stage4b2/commit-msg.txt`, `git commit -q -F .superpowers/sdd/54-plan-stage4b2/commit-msg.txt`; сообщения начинаются с «Этап 4б: » (PROC-44 закрыт и покрывает векторы CEL, векторов переходов в нём нет — `reviews/2026-10-22/plan.md`, строка PROC-44; второго коммита-отметки нет). Команды Bash — в одну строку. Журнал работ — `.superpowers/sdd/54-plan-stage4b2/progress.md` в IM.

**Решения пользователя (обязательны):** те же, что в плане 53.

**Решения этого плана (обязательны для задач; решения 1–22 — плана 53; обоснования новых — в конце):**

23. **Векторы переходов — отдельный файл** `fixtures/transition-vectors.json` со своим пулом, тем же `machineSha256` и `format: 1`; собирает и проверяет тот же `tools/cel_vectors.mjs` тем же прогоном Chrome (`--update` не удлиняется на второй прогон, `--check` проверяет оба файла).
24. **Запись — обёртка `IMEngine.create`,** как `IMCel.create` в 4а: только ядра исходной машины; `run`, `runAll`, `create` — вектор закрывается на возврате; `merge` — на следующем вызове ядра верхнего уровня (`run`, `runAll`, `merge`, `create`, `tick`, `startTimer`…`resumeTimer`) или в `take()`: так в вектор попадают записи `merged_in*`, которые `server.js` пишет после ядра. Между возвратом `merge` и закрытием у его инцидентов могут добавиться только записи журнала с ключами `workflow.journal.merged_in` и `workflow.journal.merged_in_more` у основного и ничего в `celView`; иное — вектор не пишется, счёт `skipped.outsideEngine`, `--update` с ненулевым счётом — стоп.
25. **`since` таймеров сравнивается только у `hold`** (решение 22 плана 53): у `reaction` и `resolution` — `0` с обеих сторон перед сравнением, как `norm` в `check_quint_replay.mjs`. Правило — в формате; его применяют `--check` на JS, `Compare` и `Same` на Go и тест обратного моста `fromView`. Go хранит `since = now`, прототип не меняется.
26. **Лента — на уровне `cel.world`** (кадр перехода в записи 4а собирает вызовы всех вычислений CEL внутри вызова ядра) плюс четыре функции сервера вне `cel.world` с приставкой `ctx.`: `ctx.actorName`, `ctx.progress`, `ctx.stepNumber`, `ctx.shareAnswers`. Варианты поля с `source: transferTargets` — факт `transferTargets` той же ленты. `null` прототипа запись пишет как `""` в аргументах `ctx.*` и в `facts` (`ctx.actorName(null)` — `[""]`, пустой владелец и адресат — `""`, нет нарушения — `""`): у Go пусто — `""`. Повтор на JS подменяет мир ядра (`ctx.world`) лентой; на Go лента — `transition.World`.
27. **Ожидаемое** — по указанию 1 плана 53: `celView` каждого изменённого инцидента, хвост журнала по инцидентам (`actor`, `at`, `kind`, `templateKey`, `vars`), записи журнала в момент `now` после вызова (`once` меняет подстановки и прежних записей), действия после фиксации по порядку, `external`, `facts`, `canceled`; плюс вызовы сценария внутри транзакции (`setCursor`, `shareAnswers`) по порядку. Что прототип не отдаёт, в вектор не идёт: `canceled` — только у `run` (у `runAll` и `merge` ядро его не возвращает; отменённое видно по записи `timer_overridden` в журнале), `external` у `merge` — только присоединяемых (внешнее основного ядро теряет). Отказ ядра — `refusal` (`why`, `guard`, `notFrom`, `code`, `id` — что есть в ответе прототипа), ничего не изменилось. Ошибка `workflow.error.transition_failed` — `error`: Go должен дать ошибку, текст не сравнивается (указание 3 плана 53). Версий в векторе нет.
28. **Отбор:** не больше 20 векторов на `op:name`, не больше 4 на один исход (исход — отказ и его ключ, или набор ключей журнала, видов действий после фиксации и наличие `timer_overridden`); файл — до 4 МБ; `--check` обоих файлов — до 20 с; `--update` — не дольше 8 минут (было ~6).
29. **Сверка Go — двумя тестами.** `TestTransitionVectors` — ядро на `MemRepo` в порядке списка вектора против ожидаемого (прототип = Go). `TestTransitionVectorsOnPostgres` — то же ядро на PostgreSQL против `MemRepo` в порядке номеров (Go в памяти = Go в базе), сравнение полное, в том числе порядок `after`. Сколько векторов зависит от порядка списка — число в логе (открытый вопрос 3 плана 53).
30. **`merged_in*` — в ядре Go:** `Merge` пишет запись основному в той же транзакции, последней (решение 13 плана 53), от `me`; присоединённых больше пяти — `merged_in_more {ids, more}`, иначе `merged_in {ids}`; `ids` — номера первых пяти через «, ». Пять — константа `server.js` (`MERGED_IN_SHOWN`), не машины (открытый вопрос 2).
31. **Векторы и база.** У синтетики переходов id инцидентов, `eventGuid` и `scenario` — UUID, у всех инцидентов есть событие: такие векторы можно положить в PostgreSQL. Вектор, в пуле которого есть id не UUID или пустой `eventGuid`, повторяется только в памяти; их число — в логе `TestTransitionVectorsOnPostgres`, у записанных (без `case`) оно должно быть 0, иначе тест падает. Инциденты в базу кладутся в два прохода: сначала все строки без `linked_to`, затем `linked_to` (ссылка на ещё не вставленный инцидент нарушила бы внешний ключ).
32. **Шага самопроверки нет.** Запись векторов — инструмент тестов, а не функция прототипа; стыки `fromView` и `ctx.world` пользователю не видны (как `store.instance` в 4а). Их проверяют `tools/test_cel.mjs` и неизменные самопроверка и тесты API.

## Review Focus

1. **Запись видит всё и только ядро:** `merged_in*` — с пометкой `server`, прочее вне ядра — стоп записи; `cel-vectors.json` после `--update` — те же байты. Тесты — задача 1: «запись merge: merged_in после ядра — в expect», «запись вне ядра с другим ключом — стоп»; задача 3, шаг 3.
2. **Общий черновик шагов объединения:** «Взять» основного видит записи присоединения (ужатый срок, перепривязанные); основной — `new` во время эффектов присоединяемых. Тесты — задача 7: `TestMergeTakeSeesTightenedDeadline`, `TestMergeTakeSeesRelink`, `TestMergePrimaryNewDuringMergeEffects`.
3. **Всё или ничего у нескольких инцидентов:** отказ или ошибка у любого — не меняется ни один, отказ называет его. Тесты — задача 6: `TestRunAllFirstRefusalNamesIncident`, `TestRunAllOneTransaction`; задача 7: `TestMergeRefusalNamesIncident`.
4. **Отказ против ошибки, пусто против `null`, `since`:** вектор с `refusal` — Go даёт `Refusal`, с `error` — ошибку, не промах ленты; сравнение — по правилам решений 25–27. Тест — задача 8: `TestTransitionVectors`.
5. **Память = база:** семья берёт всех, кому пишут эффекты, на всех векторах; порядок номеров — один и тот же в обоих хранилищах. Тест — задача 9: `TestTransitionVectorsOnPostgres`.

---

## Формат векторов переходов

Общий для задач 1–3, 8, 9; в IM описывается в CEL.md, раздел «Векторы переходов» (задача 4). Значения — как у векторов CEL: канонический JSON, пул инцидентов `{"$ref"}`, инцидент в ленте и действиях — `{"$incident": id}`, числа — безопасные целые.

```json
{"$comment": "Собрано tools/cel_vectors.mjs --update из записи tests/api.html?celVectors=1 и синтетики. Руками не править. Формат — CEL.md, «Векторы переходов»",
 "counts": {"create": 0, "merge": 0, "run": 0, "runAll": 0},
 "format": 1,
 "incidents": {"<ключ>": {"…Incident целиком…": ""}},
 "machineSha256": "<sha256 байтов workflow_schema.v1.json>",
 "skipped": {"outsideEngine": 0, "tapeRepeat": 0, "worldError": 0},
 "vectors": [{"…": ""}]}
```

| Поле вектора | Что |
|---|---|
| `id` | `transition:<op>:<name>:<первые 10 hex sha256 канонического входа>`; вход — все поля, кроме `id`, `case`, `expect` |
| `kind` | `transition` |
| `op` | `run`, `runAll`, `merge`, `create` |
| `name` | id перехода; у `merge` — переход с `bulk.mode: merge`; у `create` — `create` |
| `case` | только у синтетики: название случая по-русски |
| `me` | оператор ядра (`ctx.me`); он же `actor` у `run`, `runAll`, `merge` |
| `now` | `ctx.now()` на входе, мс; во время вызова не меняется (иначе вектор не пишется) |
| `surface` | `opts.surface` или `""` |
| `form` | значения формы как есть (`run`, `runAll`); у `merge` и `create` — `{}` |
| `target` | `run` — `{"id"}`; `runAll` — `{"ids"}`; `merge` — `{"primaryId", "ids"}` (присоединяемые в порядке вызова); `create` — `{"incident": {"$ref"}}` (новый, до перехода) |
| `incidents` | `ctx.events()` на входе — список `{"$ref"}` в порядке прототипа |
| `journalAtNow` | `{"<id>": [запись]}` — записи журнала инцидентов списка с `at == now` до вызова (для `once`); только непустые |
| `world` | лента `[{"fn", "args", "out"}]`: факты `cel.world` без `ref` и `ctx.actorName [id]`, `ctx.progress [инцидент] → {"filled", "total"}`, `ctx.stepNumber [инцидент]`, `ctx.shareAnswers [from, to, at] → n`; `null` в аргументах `ctx.*` — `""` |
| `expect` | `{"ok": {…}}`, `{"refusal": {…}}` или `{"error": "текст"}` |

Запись журнала: `{"actor", "at", "kind", "templateKey", "vars"}`, плюс `"server": true` у записей, которые `server.js` дописал после ядра (`merged_in*`); `kind` — как `journalView` в `server.js` (`dispatcher`, `system` — `system`, иначе `transition`); `vars` — `{}`, если пусто.

`expect.ok`:

| Поле | Что |
|---|---|
| `incidents` | `{"<id>": {"$ref"}}` — `celView` после вызова у каждого инцидента списка (и у нового при `create`), чей `celView` изменился |
| `journal` | `{"<id>": [запись]}` — хвост журнала по инцидентам, по порядку; только непустые |
| `journalAtNow` | `{"<id>": [запись]}` — записи с `at == now` после вызова у инцидентов, у которых они были до вызова (видно, что `once` заменил подстановки прежней записи) |
| `after` | по порядку: `{"action": "notify", "incident", "recipients", "alert", "about", "actor", "transitionId"}`, `{"action": "evict", "incident", "who", "transitionId", "by"}`, `{"action": "touch", "incident", "actor"}` (`about` — `{"$incident"}` или `null`) |
| `scenario` | по порядку: `{"action": "setCursor", "incident"}`, `{"action": "shareAnswers", "from", "to"}` |
| `external` | `{"<id>": [{"fn", "target"}]}` — у инцидентов, для которых ядро прототипа его отдаёт: `run` — свой, `runAll` — все, `merge` — присоединяемые; пустые — тоже |
| `facts` | `{"<id>": {"from": {"state", "owner", "addressee", "breaches"}, "to": {…}, "breach"}}`; пусто — `""` |
| `canceled` | только у `run`: `{"<id>": "<переход по таймеру>"}`, если отменён |

`expect.refusal`: `{"why": [ключ, подстановки?], "guard"?, "notFrom"?, "code"?, "id"?}` — поля ответа ядра; запись проверяет, что `celView` и журнал всех инцидентов списка не изменились. `expect.error` — текст `why[1].error` у `workflow.error.transition_failed`.

Сравнение (JS и Go): ленты — как у векторов CEL (поиск по `fn` и аргументам, равным по значению, промах — провал); инциденты — из пула в порядке `incidents`; `journalAtNow` — журнал до вызова. `timers.reaction.since` и `timers.resolution.since` — `0` с обеих сторон (решение 25). `incidents` у Go — записанные, чей инцидент машины отличается от исходного. JS-повтор не сравнивает записи с `server: true` (их пишет `server.js`, а не ядро); Go — сравнивает.

## Структура файлов

| Файл | Что | Задача |
|---|---|---|
| IM: `prototype/engine.js`; `tests/transition-vectors.js`, `tests/cel-vectors.js` (кадр записи); `tools/test_cel.mjs` | стыки ядра и библиотека записи | 1 |
| IM: `tests/api.html`, `tests/harness.js` | запись в Chrome | 2 |
| IM: `tools/cel_vectors.mjs`, `Specification/Workflow_machine/fixtures/transition-vectors.json` | сборка, синтетика, `--check` | 3 |
| IM: `Specification/Workflow_machine/{CEL.md, BACKEND.md}`, `README.md`, `CLAUDE.md`, `.graphifyignore` | раздел «Векторы переходов», проверки | 4 |
| `Makefile`, `api/im/operator/{transition-vectors.json, SOURCE, vectors_test.go}` | копия векторов с IM HEAD | 5 |
| `internal/im/service/transition/{runall.go, runall_test.go}` | «Отсоединить все» | 6 |
| `internal/im/service/transition/{merge.go, merge_test.go}` | объединение и «Взять» основного | 7 |
| `internal/im/service/transition/transitiontest/{vectors.go, tape.go, compare.go}`, `internal/im/service/transition/vectors_test.go` | сверка с векторами в памяти | 8 |
| `internal/im/handler/test/{transition_vectors_test.go, transition_seed_test.go}` | сверка на PostgreSQL | 9 |
| `docs/adr/{004-machine-executor.md, 005-transitions-in-transaction.md}`; IM: `research/integration/{40-plan.md, 54-plan-stage4b2.md}` | решения, отметки | 10 |

---

### Task 1: IM — стыки ядра и библиотека записи векторов переходов

**Files:**
- Modify: `prototype/engine.js` (`fromView` в объекте ядра; `const celWorld = ctx.world || {…}`)
- Create: `tests/transition-vectors.js`
- Modify: `tests/cel-vectors.js` (`recorder` — кадры: `frame()` → `{close(): tape}`; `window.IMCelVectors.frame` — кадр активной записи)
- Modify: `tools/test_cel.mjs`

**Interfaces:**
- Produces:
  - `engine.fromView(plain, base)` — инцидент прототипа из `celView`: `base` (поля сервера вне `celView`: `scenarioGuid`, `log`) плюс поля по `celIncident` и `writeBack`; `celView(fromView(x, b))` равен `x` после правила решения 25;
  - `ctx.world` — задан: факты мира ядра — его функции (имена и аргументы `cel.world`), а не обёртки над `ctx`; не задан — как раньше;
  - `rec.frame()` записи 4а и `IMCelVectors.frame()` — открыть кадр: каждый вызов факта мира без `ref` в любом вычислении, пока кадр открыт, идёт и в его ленту; `close()` — лента кадра (повтор вызова с тем же ответом — одна запись, с другим — `tapeRepeat`);
  - `window.IMTransitionVectors` (грузится и в Node через `vm`): `lib.recorder(create, reference, frame)` → `{create, take}`; `lib.replay(engineFor, vector, pool) → {ok, got, misses}` (`ctx` повтора: `events`, `now`, `world`, `ctx.*` по ленте, `scenarioKey` — `ev.scenarioGuid`, `log` — запись в журнал инцидента, `deliver`/`onEvict`/`onBreachShared`/`setCursor` — в итог); `lib.normalize(incident)` — правило решения 25; `lib.select(vectors, {perName: 20, perOutcome: 4})`; `lib.kindOf(whoId)`; `recording`, `take(): {incidents, vectors, skipped}`.

Запись (решения 24–27): обёртка `IMEngine.create(ctx)` — машина не исходная — как есть; иначе обёрнуты функции `ctx` (`actorName`, `progress`, `stepNumber`, `shareAnswers` — в ленту, `null` в аргументах — `""`; `transferTargets` — в ленту как факт `transferTargets`; `setCursor`, `shareAnswers` — в `scenario`; `deliver`, `onEvict`, `onBreachShared` — в `after`) и методы ядра `run`, `runAll`, `merge`, `create` (кадр, снимок «до»: `celView`, длины журналов и `journalAtNow` всех инцидентов списка; вызов; «после»). Исключение ядра пробрасывается дальше и вектора не даёт. Один `id` — два разных `expect` — исключение «один вход — два ответа».

- [ ] **Step 1: Тесты** (в `tools/test_cel.mjs`; ядро в `vm`, как в `check_quint_replay.mjs`, мир — словарь)

```js
test("fromView: celView(fromView(x)) == x для инцидентов пула fixtures/cel-vectors.json", ...)
  // все 1029; сравнение — после lib.normalize (since только у hold) и с дописанными нулевыми таймерами машины (у 653a46ba2cbf0a75 нет reaction)
test("ctx.world: факт мира берётся из ctx.world", ...)  // ctx.can → false, ctx.world.can → true ⇒ availability('claim', x).ok
test("запись run: вектор с журналом и неизменённым остальным", ...)
  // два инцидента [x new, y new], claim x ⇒ один вектор: op run, target {id: x}, expect.ok.incidents — только x,
  // journal {x: [{templateKey "workflow.journal.claim", kind "transition", actor me, at now}]}, scenario [setCursor x], after [];
  // в ленте ctx.actorName [""] (а не [null]); facts.x.from.owner ""
test("запись merge: merged_in после ядра — в expect с server: true", ...)
  // merge, затем «сервер» дописывает основному merged_in и вызывает ядро ещё раз ⇒ последняя запись журнала основного — merged_in, server: true
test("запись: запись журнала вне ядра с другим ключом — вектора нет, skipped.outsideEngine 1", ...)
test("отказ: expect.refusal, инциденты не изменились", ...) // claim при can → false ⇒ {why: ["workflow.guard.no_permission", {p: "incident:claim"}]}
test("повтор: run по ленте даёт тот же expect; лента без can — промах", ...) // replay → ok; misses = ["can"]
```

- [ ] **Step 2: Тесты падают**

Run: `cd /mnt/hgfs/VmWareShared/soul2home/IM && git fetch && node tools/test_cel.mjs`
Expected: FAIL — `fromView` нет, `IMTransitionVectors` не объявлен; прежние 20 проходят.

- [ ] **Step 3: Реализация**

- [ ] **Step 4: Тесты проходят; прототип — как раньше**

Run: `node tools/test_cel.mjs`
Expected: `test_cel: 27 из 27`.

Run: быстрые проверки IM; самопроверка (`prototype/index.html?selftest`, бюджет 180000) и тесты API (`tests/api.html`, 120000) — по `CLAUDE.md`, профиль в `$S`; `python3 -c "import sys; sys.path.insert(0, 'tools'); import check_code_mutations as m; bad = m.stale(); print(len(m.MUTATIONS), 'порч, устаревших:', len(bad), bad)"`.
Expected: всё зелёное; `data-selftest="pass"`, `data-apitest="pass"`, итог тестов API — тот же, что до задачи; устаревших порч — 0. Шага самопроверки нет (решение 32).

- [ ] **Step 5: Commit**

Сообщение: «Этап 4б: библиотека записи векторов переходов — обёртка ядра прототипа (run, runAll, merge, create), лента мира кадром записи CEL, записи server.js после объединения; стыки ядра fromView и ctx.world».
Run: `git add prototype/engine.js tests/transition-vectors.js tests/cel-vectors.js tools/test_cel.mjs && git commit -q -F .superpowers/sdd/54-plan-stage4b2/commit-msg.txt`

---

### Task 2: IM — запись векторов переходов при тестах API

**Files:**
- Modify: `tests/api.html` (`<script src="transition-vectors.js">` после `engine.js` и `cel-vectors.js`; `<pre id="transitionvectors-out" hidden></pre>`), `tests/harness.js` (`finish`: при `IMTransitionVectors.recording` — блок `transitionvectors-out` = `JSON.stringify(IMTransitionVectors.take())`)

**Interfaces:**
- Consumes: задача 1.
- Produces: блок `transitionvectors-out` в выводе `tests/api.html?celVectors=1` — `{incidents, vectors, skipped}`; без параметра — пустой.

- [ ] **Step 1: Проверка до правки** — блока нет.

Run: `S=<scratchpad> && google-chrome --headless=new --disable-gpu --no-first-run --user-data-dir=$S/chrome0 --virtual-time-budget=180000 --dump-dom "file://$PWD/tests/api.html?celVectors=1" | grep -c transitionvectors-out`
Expected: `0`.

- [ ] **Step 2: Реализация** правок `api.html` и `harness.js`.

- [ ] **Step 3: Запись в Chrome зелёная и повторяется**

Run: `S=<scratchpad> && for n in 1 2; do google-chrome --headless=new --disable-gpu --no-first-run --user-data-dir=$S/chrome$n --virtual-time-budget=180000 --dump-dom "file://$PWD/tests/api.html?celVectors=1" > $S/rec$n.html; done && python3 -c "import html,re,sys,json,hashlib;[print('pass' if 'data-apitest=\"pass\"' in p else 'FAIL', (lambda d: (len(d['vectors']), sorted({v['op'] for v in d['vectors']}), d['skipped'], hashlib.sha256(json.dumps(d,sort_keys=True).encode()).hexdigest()[:12]))(json.loads(html.unescape(re.search(r'<pre id=\"transitionvectors-out\"[^>]*>(.*?)</pre>',p,re.S).group(1))))) for p in [open(f,encoding='utf-8').read() for f in sys.argv[1:]]]" $S/rec1.html $S/rec2.html`
Expected: обе строки — `pass`; виды — `create`, `merge`, `run`, `runAll`; `skipped` — нули; число векторов и хэш в двух прогонах совпадают. Без параметра (`tests/api.html`) — `pass`, блок пустой; блок `celvectors-out` с параметром — тот же, что до задачи (хэш как в шаге 4 задачи 2 плана 52).

- [ ] **Step 4: Commit**

Сообщение: «Этап 4б: запись векторов переходов при тестах API — tests/api.html?celVectors=1 пишет и блок transitionvectors-out».
Run: `git add tests/api.html tests/harness.js && git commit -q -F .superpowers/sdd/54-plan-stage4b2/commit-msg.txt`

---

### Task 3: IM — `transition-vectors.json`: сборка, синтетика, `--check`

**Files:**
- Modify: `tools/cel_vectors.mjs`
- Create (собирает `--update`): `Specification/Workflow_machine/fixtures/transition-vectors.json`

**Interfaces:**
- Consumes: `IMTransitionVectors.lib` (задачи 1, 2).
- Produces:
  - `node tools/cel_vectors.mjs --update` — один прогон Chrome, оба блока; тесты API не `pass` или `skipped.outsideEngine` ≠ 0 — стоп без записи; отбор (решение 28), синтетика, затем всё, что делает `--check`, и только потом запись обоих файлов;
  - `node tools/cel_vectors.mjs --check [--file=…] [--transitions=путь] [--machine=…]` — после строк векторов CEL (итог и строка «синтетика: …») — отдельная строка `векторов переходов: N (run …, runAll …, merge …, create …), расхождений: 0, промахов ленты: 0, без векторов: 0`; нет файла переходов — «нет файла векторов переходов, соберите: node tools/cel_vectors.mjs --update», код 1;
  - `--engine=путь` — только для проб порчи: повтор на копии `prototype/engine.js` вместо исходного;
  - покрытие: у каждого перехода `trigger: manual` (12) и у `create` — вектор `ok`; у `run`, `runAll`, `merge` — хотя бы один `refusal`; хотя бы один вектор `run` с `canceled`; иначе имя — в `UNCOVERED_TRANSITIONS_OK` с причиной словами (не больше 3; больше — синтетика); размер файла — до 4 МБ.

Повтор на JS: ядро в `vm` по образцу `check_quint_replay.mjs`, по ядру на каждое `me`, `lib.replay`; сравнение — по правилам раздела «Формат».

Синтетика — на исходной машине, мир — лента того же `lib` (решение 31). Основа: инцидент с id `10000000-0000-4000-8000-000000009001`, `INC-9001`, событие `70000000-0000-4000-8000-000000009001`, сценарий `60000000-0000-4000-8000-000000000002`, приоритет 50, все таймеры; второй — `…9002` (`INC-9002`, своё событие); оператор `op1` на месте, с правами; эскалировать некому (`can` для `petrova`, `noc` — false).

| Случай | Что | Ждём |
|---|---|---|
| `run claim` в окне | `new`, `reaction.due` = now − 2999 | `canceled` `escalation_ceiling`; нарушение `reaction` на момент дедлайна; журнал `[timer_overridden, claim]` |
| `run claim` на конце окна | `due` = now − 3000 | `canceled` нет, нарушения нет |
| `run transfer` в окне | `due` = now − 1000, `targetId` — `op2` (может принять) | `canceled` нет (`continuesOn`) |
| `run hold` с чужой причиной | `in_progress` у `op1`, `reasonId: "nope"` | `refusal` `workflow.error.field_invalid`, `code` `FORM_FIELD_INVALID` |
| `run close` без результата | форма `{}` | `refusal` `workflow.error.field_required`, `name` `[workflow.form.close.field.resultId]` |
| `run close` «массовый сбой» без причины | `{resultId: "mass"}` | `refusal` `field_required`, `name` `[workflow.form.close.field.causeId]` |
| `runAll detach`, второй не привязан | `[…9001 linked к …9003, …9002 new]` | `refusal` `notFrom`, `id` `…9002` |
| `create`, приоритет без своего норматива | приоритет 60 | `timers.reaction.due` = now + 300 000 |

- [ ] **Step 1: Проверка без файла переходов** — до реализации `--check` о файле переходов не знает.

Run: `S=<scratchpad> && node tools/cel_vectors.mjs --check --transitions=$S/nope.json; echo $?`
Expected сейчас (красное): код `0` — флаг не известен, файл не проверяется. После реализации: «нет файла векторов переходов, соберите: node tools/cel_vectors.mjs --update», `1`.

- [ ] **Step 2: Реализация** сборки, повтора и синтетики.

- [ ] **Step 3: Сборка, повторяемость, проверка; векторы CEL — те же байты**

Run: `S=<scratchpad> && F=Specification/Workflow_machine/fixtures && /usr/bin/time -f '%e с' node tools/cel_vectors.mjs --update --tmp=$S && sha256sum $F/transition-vectors.json > $S/t1 && node tools/cel_vectors.mjs --update --tmp=$S && sha256sum -c $S/t1 && git diff --exit-code $F/cel-vectors.json && time node tools/cel_vectors.mjs --check`
Expected: время `--update` — до 480 с (записать в журнал работ); второй `--update` дал те же байты (`OK`); `cel-vectors.json` не изменился; `--check` — код 0, строка векторов CEL и строка векторов переходов — `расхождений: 0, промахов ленты: 0, без векторов: 0`, меньше 20 с; файл переходов — до 4 МБ. Шаг 1 теперь даёт код `1`.

- [ ] **Step 4: Проверка ловит порчу**

Run: `S=<scratchpad> && F=Specification/Workflow_machine/fixtures/transition-vectors.json && python3 -c "import sys;l=open(sys.argv[1],encoding='utf-8').read().split('\n');i=next(k for k,x in enumerate(l) if '\"workflow.journal.claim\"' in x and '\"ok\"' in x);l[i]=l[i].replace('\"workflow.journal.claim\"','\"workflow.journal.claimX\"',1);open(sys.argv[2],'w',encoding='utf-8').write('\n'.join(l))" $F $S/bad.json && node tools/cel_vectors.mjs --check --transitions=$S/bad.json; echo $?`
Expected: код `1`, в списке расхождений — `id` испорченного вектора. Вторая проба: копия `engine.js` в `$S`, у `windowAfter` убран `splice` (запись о таймере — в конец), `node tools/cel_vectors.mjs --check --engine=$S/engine.js` — расхождение у вектора «`run claim` в окне», код `1`.

- [ ] **Step 5: Commit**

Сообщение: «Этап 4б: векторы переходов для бэкенда — fixtures/transition-vectors.json тем же прогоном --update, синтетика окна после дедлайна и формы, --check повторяет их на ядре прототипа».
Run: `git add tools/cel_vectors.mjs Specification/Workflow_machine/fixtures/transition-vectors.json && git commit -q -F .superpowers/sdd/54-plan-stage4b2/commit-msg.txt`

---

### Task 4: IM — раздел «Векторы переходов», проверки

**Files:**
- Modify: `Specification/Workflow_machine/CEL.md` (после «Векторы» — раздел «Векторы переходов»; строка «Векторы переходов … будут на этапе 4б» — ссылкой на него), `Specification/Workflow_machine/BACKEND.md` (в «На что обратить внимание» — пункт «Векторы переходов»; в «Когда готово» — строка), `README.md` («Проверки»), `CLAUDE.md` (строка таблицы сгенерированных файлов `fixtures/cel-vectors.json` — и `transition-vectors.json`, тем же `--update`), `.graphifyignore`

Раздел «Векторы переходов» (по-русски, простыми словами): зачем — переход целиком, а не одно вычисление; уровень — ядро, не HTTP, версий нет; откуда (запись + синтетика) и почему `merged_in*` с пометкой `server`; формат (таблицы выше) и правила сравнения: `since` — только у `hold`, `null` — `""`, `canceled` — только у `run`, `external` объединения — только присоединяемых; как повторяет бэкенд — лента, пул, порядок списка; что из этого следует для бэкенда: всё в одной транзакции (нарушение отменённого таймером перехода, «некому», `merged_in*`, перенос ответов); порядок записей журнала (решение 13 плана 53); состояние `to` — перед эффектами инцидента; отказ — не ошибка, ошибка вычисления — ошибка сервера; планировщик — этап 6. BACKEND.md — коротко и ссылкой; «Когда готово» — «векторы `fixtures/transition-vectors.json` проходят у ядра бэкенда (CEL.md, «Векторы переходов»)». Чисел машины в новых строках BACKEND.md нет.

- [ ] **Step 1: Документы и проверки**

Run: быстрые проверки IM и `python3 tools/check_links.py`.
Expected: всё зелёное; «Нерабочих ссылок: 0».

- [ ] **Step 2: Commit**

Сообщение: «Этап 4б: CEL.md и BACKEND.md — раздел «Векторы переходов»; проверки и таблица сгенерированных файлов».
Run: `git add Specification/Workflow_machine/CEL.md Specification/Workflow_machine/BACKEND.md README.md CLAUDE.md .graphifyignore && git commit -q -F .superpowers/sdd/54-plan-stage4b2/commit-msg.txt`

---

### Task 5: Сервер — копия векторов переходов с IM HEAD

**Files:**
- Modify: `Makefile` (`vendor-operator-contract`: ещё `$(OP_SRC_DIR)/fixtures/transition-vectors.json` → `$(OP_API_DIR)/`)
- Create (make): `api/im/operator/transition-vectors.json`; Modify (make): `api/im/operator/SOURCE`
- Modify: `api/im/operator/vectors_test.go`

- [ ] **Step 1: Тест**

```go
func TestTransitionVectorsMatchMachine(t *testing.T) // os.ReadFile("transition-vectors.json"); format == 1; machineSha256 == hex(sha256(Machine)); counts run, runAll, merge, create > 0
```

- [ ] **Step 2: Тест падает**

Run: `cd ~/Work/incident-manager-server && source ~/go/offline-env.sh && go test ./api/im/operator/ 2>&1 | tail -3`
Expected: FAIL — нет `transition-vectors.json`.

- [ ] **Step 3: Копия**

Run: `git -C /mnt/hgfs/VmWareShared/soul2home/IM status --porcelain -- Specification/Workflow_machine && make vendor-operator-contract && cat api/im/operator/SOURCE && git status --short`
Expected: `status` IM пуст; в `SOURCE` — хэш задачи 4 без `dirty`; новый файл `transition-vectors.json` и `SOURCE`; машина, контракт, строки и `cel-vectors.json` — без изменений (машина в этапе не менялась). Иначе — **стоп, спросить**.

- [ ] **Step 4: Тесты проходят**

Run: `go test ./api/... ./internal/im/machine/ && golangci-lint run ./...`
Expected: PASS; lint — 0.

- [ ] **Step 5: Commit**

Сообщение: «Этап 4б: копия векторов переходов с IM <SOURCE>».
Run: `git add Makefile api/im/operator && git commit -q -F .git/COMMIT_MSG_STAGE4B`

---

### Task 6: Ядро — «Отсоединить все» (`RunAll`)

**Files:**
- Create: `internal/im/service/transition/runall.go`; Test: `internal/im/service/transition/runall_test.go` (пакет `transition_test`)

**Interfaces:**
- Consumes: `Core.Run` и его части (план 53, задачи 5–9).
- Produces: `func (c *Core) RunAll(ctx model.AppContext, repo Repo, w World, op Op) (*Result, error)` — `op.IDs` — список в порядке вызывающего; `Result.Canceled` заполняется, хотя в векторах его нет (решение 27).

Порядок (как `runAll` в `engine.js`): семья всех `op.IDs` одной блокировкой → `Expect` → для каждого по порядку доступность и форма, первый отказ — `Refusal` с `ID` этого инцидента → окно у каждого → один шаг на всех на одном черновике (у каждого `before`, `to` и эффекты — по очереди) → окно после у каждого → журнал, версии, `Write` одной транзакцией; повтор при `ErrFamilyChanged` — как у `Run`.

- [ ] **Step 1: Тесты**

Основной P (`in_progress`, `op1`), привязанные L1, L2 (`linked`, `linkedTo` P); `me` — `op1`; мир — задачи 5 плана 53.

```go
func TestRunAllDetachAll(t *testing.T)
  // detach [L1, L2] ⇒ оба "new", linkedTo "", linkedAt 0, leftGroup {primaryId P, linkedAt — прежний, at Now};
  // Journal[L1] и [L2] — [workflow.journal.detach]; у P записей нет (у clearLink в detach ключи журнала пусты);
  // Incidents — [L1, L2] по Order, у каждого version +1; P не записан
func TestRunAllFirstRefusalNamesIncident(t *testing.T) // [L1, X], X "new" ⇒ Refusal{Key "workflow.guard.wrong_state", NotFrom true, ID X}; Writes() == 0
func TestRunAllOneTransaction(t *testing.T)
  // копия: у detach последним эффектом _failOnL2: [if incident.id == '<id L2>': let t = incident.timers['nope']] ⇒ ошибка; L1 не изменился, Writes() == 0
func TestRunAllSecondSeesFirst(t *testing.T)
  // копия: у detach первым эффектом _probe: [set incident.transferCount = size(linkedOf(incident.linkedTo))] ⇒
  // у L1 — 2, у L2 — 1 (L1 уже отсоединён в черновике)
```

- [ ] **Step 2: Тесты падают**

Run: `go test ./internal/im/service/transition/ -run RunAll 2>&1 | tail -3`
Expected: FAIL — `RunAll` не объявлен.

- [ ] **Step 3: Реализация**

- [ ] **Step 4: Тесты проходят**

Run: `go test -race ./internal/im/service/transition/... && golangci-lint run ./...`
Expected: PASS; lint — 0.

- [ ] **Step 5: Commit**

Сообщение: «Этап 4б: ядро — «Отсоединить все» одним переходом на всех: проверки всех до эффектов, один черновик, отказ называет инцидент, всё или ничего».
Run: `git add internal/im/service/transition && git commit -q -F .git/COMMIT_MSG_STAGE4B`

---

### Task 7: Ядро — объединение и «Взять» основного (`Merge`)

**Files:**
- Create: `internal/im/service/transition/merge.go`; Test: `internal/im/service/transition/merge_test.go`

**Interfaces:**
- Consumes: план 53, задачи 5–9; задача 6.
- Produces: `func (c *Core) Merge(ctx model.AppContext, repo Repo, w World, op Op) (*Result, error)` — `op.PrimaryID` — основной (его выбирает вызывающий: `mergePrimary` машины — 4в), `op.IDs` — присоединяемые; `Result.Facts`, `Result.External` и `Result.Canceled` — и у основного, если его взяли.

Порядок (как `mergeCheck` и `merge` в `engine.js`; решения 13, 14 плана 53 и 30): семья основного и всех присоединяемых одной блокировкой → `Expect` → переход `bulk.mode: merge` машины доступен каждому присоединяемому с формой `{primaryId}` (первый отказ — `Refusal` с `ID`); основной в `from` перехода `grouping.takeWith` — «Взять» доступно основному (отказ — `ID` основного) → окно у каждого присоединяемого (по переходу объединения) и у основного (по «Взять») → шаг 1: объединение на присоединяемых, шаг 2: «Взять» на основном — один черновик → окно после у всех → запись `merged_in*` основному последней → журнал, версии, `Write`.

- [ ] **Step 1: Тесты**

Основной P `new`; A `new`, B `in_progress` у `op1`; у A привязанный C; один сценарий; `me` — `op1`; номера P, A, B, C — `INC-0001`…`INC-0004`; мир задачи 5 плана 53, `can` для `petrova` и `noc` — false (эскалировать некому).

```go
func TestMergeWithTake(t *testing.T)
  // ⇒ A, B — "linked", linkedTo P; P — "in_progress", owner "op1"; Journal[P] кончается на claim, затем
  // merged_in {Vars {"ids": "INC-0002, INC-0003"}, Actor "op1", Kind "transition"} — последней; Facts[P].To.State "in_progress"
func TestMergeTakeSeesRelink(t *testing.T)           // C (привязан к A) после объединения — linkedTo P (relinkToPrimary); C в Incidents с version +1
func TestMergeTakeSeesTightenedDeadline(t *testing.T)
  // присоединяется только A; P: resolution на паузе с остатком 1 500 000; A: resolution на паузе с остатком 300 000 ⇒ tightenPrimaryDeadline ставит P left 300 000,
  // «Взять» (resumeTimer resolution) видит его: P.timers.resolution.due == Now + 300 000 (а не Now + 1 500 000);
  // у P одна запись workflow.journal.group_deadline (once)
func TestMergePrimaryNewDuringMergeEffects(t *testing.T)
  // копия: у merge первым эффектом _probe: [set incident.result = incidentById(form.primaryId)[0].state] ⇒ у A и B result "new"
func TestMergePrimaryInProgressNoTake(t *testing.T)  // P "in_progress" у op1 ⇒ записи claim у P нет; merged_in — последняя
func TestMergedInMore(t *testing.T)                  // 7 присоединяемых ⇒ merged_in_more {"ids": первые 5 номеров через ", ", "more": 2}
func TestMergeRefusalNamesIncident(t *testing.T)     // у B другой сценарий ⇒ Refusal{Guard "sameScenarioAsPrimary", ID B}; Writes() == 0
func TestMergeTakeRefusalNamesPrimary(t *testing.T)  // can("op1", "incident:claim") false ⇒ Refusal{Key "workflow.guard.no_permission", ID P}
func TestMergeWindowOnPrimary(t *testing.T)          // у P reaction.due = Now − 1000 ⇒ Canceled {P: "escalation_ceiling"}; Journal[P] начинается с timer_overridden
```

- [ ] **Step 2: Тесты падают**

Run: `go test ./internal/im/service/transition/ -run Merge 2>&1 | tail -3`
Expected: FAIL — `Merge` не объявлен.

- [ ] **Step 3: Реализация**

- [ ] **Step 4: Тесты проходят**

Run: `go test -race ./internal/im/service/transition/... && golangci-lint run ./...`
Expected: PASS; lint — 0.

- [ ] **Step 5: Commit**

Сообщение: «Этап 4б: ядро — объединение и «Взять» основного одной транзакцией на общем черновике; окно после дедлайна у каждого; запись merged_in — в той же транзакции, последней».
Run: `git add internal/im/service/transition && git commit -q -F .git/COMMIT_MSG_STAGE4B`

---

### Task 8: Сверка ядра Go с векторами переходов (в памяти)

**Files:**
- Create: `internal/im/service/transition/transitiontest/{vectors.go, tape.go, compare.go}`; Test: `internal/im/service/transition/vectors_test.go`

**Interfaces:**
- Consumes: задачи 5–7; `api/im/operator/transition-vectors.json` — по пути `../../../../api/im/operator/transition-vectors.json`.
- Produces (для тестов):
  - `func LoadTransitionVectors(path string) (*TransitionFile, error)` — `UseNumber`, `$ref` разворачиваются; `type TransitionVector struct{…}` — поля формата;
  - `func NewTape(entries []TapeEntry) *Tape` — `transition.World`: `Fact` — по `fn` и аргументам (`json.Number` и `int64` — одно, инцидент — по `id`), `ActorName`, `Progress`, `StepNumber`, `ShareAnswers` — записи `ctx.*`; `SetCursor`, `ShareAnswers` — в `Scenario()`; промах — ошибка и запись в `Misses()`;
  - `type Order int` — `VectorOrder` (место в `incidents`) или `NumberOrder` (число из `number`);
  - `type Run struct { Before []transition.Row; Result *transition.Result; Err error; Repo *MemRepo; Tape *Tape }`;
  - `func RunVector(core *transition.Core, v *TransitionVector, order Order) *Run` — `MemRepo` из пула, `journalAtNow` — в его журнал; `op` — вызов `Run`, `RunAll`, `Merge` или `Create`;
  - `func RunVectorOn(core *transition.Core, v *TransitionVector, repo transition.Repo, tape *Tape) *Run` — то же на чужом хранилище (задача 9: PostgreSQL), `Run.Repo` — `nil`;
  - `func Compare(v *TransitionVector, r *Run) []string` — расхождения с ожидаемым словами; `func Same(a, b *Run) []string` — расхождения двух прогонов (задача 9); пусто — совпало. Оба нормализуют `since` (решение 25).

Сравнение (раздел «Формат», решения 25–27): `ok` — `Result` без отказа; `incidents` — записанные, чей инцидент машины отличается от исходного, равны ожидаемым; журнал по инцидентам — по порядку, с записями `server: true`; `journalAtNow` после вызова; `after`, `scenario`; `external` — только у инцидентов, для которых он есть в ожидаемом; `facts`; `canceled` — только у `run`. `refusal` — `Refusal`, совпадают поля, которые есть в ожидаемом (`why[0]` — `Key`, `why[1]` — `Vars`), `repo.Writes() == 0`. `error` — `err != nil`, не промах ленты, `repo.Writes() == 0`.

- [ ] **Step 1: Тесты**

```go
func TestTape(t *testing.T)              // попадание — out; json.Number("5") и int64(5) — одно; ctx.actorName — по id; вызова нет — ошибка, Misses() == ["can(...)"]
func TestTransitionVectors(t *testing.T)
  // MachineSHA256 == sha256(operatorapi.Machine); подтест на каждый id, порядок — VectorOrder; упал — расхождения в сообщении;
  // промах ленты — провал; в конце t.Logf: "transition vectors N (run …, runAll …, merge …, create …), mismatches M, tape misses K, unused tape entries U"
func TestTransitionVectorsCoverMachine(t *testing.T) // у каждого перехода trigger: manual и у create — вектор ok (как покрытие --check)
```

- [ ] **Step 2: Прогон**

Run: `go test ./internal/im/service/transition/ -run 'TestTape|TestTransitionVectors' -v 2>&1 | grep -E '^(=== RUN|--- FAIL|ok|FAIL)|transition vectors [0-9]' | tail -30`
Expected сначала: FAIL — `RunVector` не объявлен; затем — расхождения, если есть. Каждое разобрать: правится ядро (задачи 5–9 плана 53, задачи 6–7 этого), а не вектор; похоже на ошибку прототипа — **стоп, спросить**. Каждую причину — в журнал работ.

- [ ] **Step 3: Тесты проходят**

Run: `go test -race ./internal/im/service/transition/ -v -run 'TestTransitionVectors' 2>&1 | grep -E 'transition vectors [0-9]|^ok|FAIL' && golangci-lint run ./...`
Expected: `ok`; `mismatches 0, tape misses 0`; число векторов — как `counts` файла; lint — 0.

- [ ] **Step 4: Commit**

Сообщение: «Этап 4б: сверка ядра переходов Go с прототипом — все векторы переходов совпадают в памяти; отказ и ошибка различаются, мир — по ленте».
Run: `git add internal/im/service/transition && git commit -q -F .git/COMMIT_MSG_STAGE4B`

---

### Task 9: Сверка на PostgreSQL — память и база дают одно

**Files:**
- Create: `internal/im/handler/test/{transition_vectors_test.go, transition_seed_test.go}`

**Interfaces:**
- Consumes: задача 8; `transition.NewStoreRepo` (план 53, задача 10).
- Produces (только тесты): `func seedVector(t *testing.T, ctx model.AppContext, f *seedFixture, v *transitiontest.TransitionVector)` — в откатываемой транзакции: приоритеты с нужными `value`, типы событий с нужными `uid`, события с `guid` = `eventGuid` и `occurred_at`, сценарии (`scenario_definitions`, `scenarios`) с `guid` пула, инциденты пула через `FromMachine` с номером из `number` — в два прохода (решение 31), `journalAtNow`; арендатор — новый на прогон.

Для каждого вектора `op` `run`, `runAll`, `merge` (у `create` в ядре нет хранилища) с пулом из UUID и событий: `seedVector` → `RunVectorOn(core, v, NewStoreRepo(…), tape)`; эталон — `RunVector(core, v, NumberOrder)`; сравнение — `Same`, полное (решение 29), плюс журнал, прочитанный из базы. Затем `inRolledBackTx` откатывает всё.

- [ ] **Step 1: Тесты**

```go
func TestTransitionVectorsOnPostgres(t *testing.T)
  // подтест на каждый вектор run, runAll, merge: Same(база, NumberOrder) пусто; журнал из базы == Result.Journal; версии в базе — +1 у Result.Incidents;
  // в конце t.Logf: "postgres vectors N, mismatches 0, order-sensitive K, memory-only M"
  // (K — векторы, у которых VectorOrder и NumberOrder дают разный итог; M — векторы с id не UUID или без события; M у записанных, без case, — 0, иначе FAIL)
func TestSeedVectorRoundTrip(t *testing.T) // для 20 первых векторов: GetMachineIncidents по пулу == инциденты вектора (ToMachine), linked_to — на месте
```

- [ ] **Step 2: Прогон**

Run: `TESTDB='postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable' && IM_TEST_DB_URL=$TESTDB go test ./internal/im/handler/test/ -run 'TestTransitionVectorsOnPostgres|TestSeedVectorRoundTrip' -v 2>&1 | grep -E '^(--- FAIL|ok|FAIL)|postgres vectors' | tail -20`
Expected сначала: FAIL — `seedVector` не объявлен; затем — расхождения, если есть: правится хранилище или ядро, не тест. `ErrFamilyChanged` у вектора после трёх попыток — семья (решение 15 плана 53) не берёт того, кому пишет машина: **стоп, спросить** (меняется правило семьи).

- [ ] **Step 3: Тесты проходят**

Run: `IM_TEST_DB_URL=$TESTDB go test -race ./internal/im/handler/test/ -run 'TestTransitionVectorsOnPostgres|TestSeedVectorRoundTrip' -v 2>&1 | grep -E 'postgres vectors|^ok|FAIL' && make test-local 2>&1 | tail -10 && golangci-lint run ./...`
Expected: `ok`; `mismatches 0`; время прогона — в журнал работ (больше 3 минут — **стоп, спросить**); числа `order-sensitive` и `memory-only` — в журнал работ, первое — и в ответ на открытый вопрос 3 плана 53; все пакеты; lint — 0.

- [ ] **Step 4: Commit**

Сообщение: «Этап 4б: векторы переходов на PostgreSQL — ядро на базе даёт то же, что в памяти: семья, кандидаты фактов, запись с версией, журнал».
Run: `git add internal/im/handler/test && git commit -q -F .git/COMMIT_MSG_STAGE4B`

---

### Task 10: ADR, документы, последний прогон

**Files:**
- Modify: `docs/adr/005-transitions-in-transaction.md` (векторы переходов и их итог, правила сравнения; `RunAll`, `Merge`; `merged_in*`; число векторов, зависящих от порядка), `docs/adr/004-machine-executor.md` («Next» — 4в)
- Modify (IM): `research/integration/40-plan.md` («Что уже готово» — строка «Столбцы инцидента и переходы в транзакции (этап 4б)» со ссылками на 53 и 54; в разделе этапа 4 — 4а и 4б сделаны, 4в впереди), `research/integration/54-plan-stage4b2.md` (отметки, «Итог этапа 4б» — таблица задач и коммитов обеих частей)

- [ ] **Step 1: ADR** — дописать в ADR-005 по итогам задач 1–9.

- [ ] **Step 2: Документы IM** — перед правкой `git -C /mnt/hgfs/VmWareShared/soul2home/IM fetch`; новое — сказать пользователю.
Run: `cd /mnt/hgfs/VmWareShared/soul2home/IM && python3 tools/check_links.py && node tools/cel_vectors.mjs --check | grep -E '^(векторов|векторов переходов):'`
Expected: «Нерабочих ссылок: 0»; обе строки векторов — `расхождений: 0`.

- [ ] **Step 3: Последний прогон сервера**

Run: `cd ~/Work/incident-manager-server && source ~/go/offline-env.sh && go test -race $(go list ./internal/im/... | grep -v /handler/test) && make test-local 2>&1 | tail -15 && go vet ./... && gofmt -l internal/im && golangci-lint run ./...`
Expected: всё PASS; `go vet`, `gofmt -l` чисто; lint — 0.

- [ ] **Step 4: Commit (два репозитория)**

Сервер — «Этап 4б: ADR-005 — векторы переходов, «Отсоединить все», объединение». Run: `git add docs/adr && git commit -q -F .git/COMMIT_MSG_STAGE4B`
IM — «Этап 4б встраивания: столбцы инцидента, переходы в транзакции и векторы переходов — план отмечен». Run: `cd /mnt/hgfs/VmWareShared/soul2home/IM && git add research/integration/40-plan.md research/integration/54-plan-stage4b2.md && git commit -q -F .superpowers/sdd/54-plan-stage4b2/commit-msg.txt`

---

## Не в этом этапе

| Что | Когда |
|---|---|
| Векторы планировщика (`tick`): переходы по таймеру и системные, `agentIdleFor`, `changedAt`, порядок догона | 6 (минимум для `/test/clock` — 4в) |
| Векторы на уровне HTTP: `If-Match`, коды `403`/`409`/`412`/`422`, `externalEffects` ответа, `journalEntries` с текстом, версии (и решение 16 плана 53: Go даёт версию и инциденту, которому достался только журнал) | 4в (по образцу `tests/api.html`, когда вход заработает) |
| Массовое действие `each_allowed`, `bulk.scope`, выбор основного `mergePrimary`/`bulkPrimary`, `minItems`, `maxBulk`, `expectedVersions` | 4в |
| Синтетика объединения (`merged_in_more`, `once` у `tightenPrimaryDeadline`) | не делается: запись `merged_in*` — у `server.js`, синтетика ядра её не даёт; случаи закрыты тестами Go `TestMergedInMore`, `TestMergeTakeSeesTightenedDeadline` (задача 7) и `TestLogOnce` (план 53, задача 9) |
| `canceled` у `runAll` и `merge`, `external` основного при объединении в векторах | не делается: ядро прототипа их не возвращает; у Go они есть и проверены тестами задач 6, 7 |
| Перенос ответов сценария по-настоящему (`shareAnswers` с `n > 0`), курсор | 6; в векторах — по ленте `ctx.shareAnswers` |
| Порядок списка инцидентов в прототипе по номеру | по ответу на открытый вопрос 3 плана 53 (пункт ревью IM) |

## Решения этого плана — обоснования (на подтверждение)

23. **Отдельный файл, тот же инструмент.** У векторов переходов свой пул (инциденты целого списка) и свой размер; смешать с `cel-vectors.json` — значит менять формат 1 и `TestVectors` 4а. Отдельный инструмент дал бы второй прогон Chrome на ~6 минут; тот же прогон пишет оба блока.
24. **Закрытие вектора объединения на следующем вызове ядра.** `merged_in*` пишет `server.js` сразу после `engine.merge`, своей функцией `log`, не через `ctx`, — перехватить её можно, только меняя `server.js`. Между `merge` и следующим вызовом ядра `server.js` трогает у этих инцидентов только версию и журнал основного; запись проверяет это по ключам и `celView`, и любое другое изменение останавливает `--update`, а не попадает в вектор молча.
25. **`since` — только у `hold`.** Машина пишет `since` при запуске любого таймера, а мост прототипа хранит его только у `hold` (`FIELDS`); у остальных его никто не читает. Без правила почти каждый вектор с запуском таймера разошёлся бы на поле без смысла; так же уже сравнивает модель Quint.
26. **Лента на уровне `cel.world`, пусто — `""`.** Мир Go говорит именами и аргументами `cel.world`, а `ctx` прототипа — своими (`permsOf(who)` — список, `can` — `includes`). Кадр записи 4а уже видит факты так, как их видит машина. `null` у прототипа — то же «пусто», что `''` у машины и `""` у Go; писать его как есть — значит получить расхождения, которых нет.
27. **В векторе — только то, что ядро прототипа отдаёт.** Восстанавливать `canceled` у `runAll` и `merge` по журналу — значит писать в инструменте логику ядра; запись `timer_overridden` и так сравнивается, а Go-поля проверяют свои тесты.
28. **Пределы отбора меньше, чем у CEL.** Вектор перехода в десятки раз больше вектора выражения (весь список и длинная лента); 20 на `op:name` и 4 на исход дают ~300 векторов, около 1–2 МБ, при 15 именах.
29. **Две сверки вместо одной.** Порядок списка у прототипа — порядок набора, у базы — номер (открытый вопрос 3 плана 53). Цепочка «прототип = Go в памяти в порядке вектора» и «Go в памяти в порядке номеров = Go в базе» проверяет и смысл, и SQL полностью, а цену вопроса о порядке показывает числом.
30. **`merged_in*` в ядре Go.** BACKEND.md: переход — одна транзакция с журналом. Запись — часть итога объединения, вектор её ждёт (указание 2 плана 53). Пять — значение `server.js`, а не машины: в Go — константа с комментарием-ссылкой; перенос в машину — открытый вопрос.
31. **UUID у синтетики и два прохода.** База требует UUID, событие и сценарий у каждого инцидента; синтетика 4а с id `s1` в неё не ляжет. Записанные векторы приходят из тестов API с UUID — у них «только память» быть не должно, иначе база проверяет не всё. Внешний ключ `linked_to` требует, чтобы основной уже был в таблице.
32. **Без шага самопроверки.** Самопроверка проверяет то, что видит пользователь; запись векторов — инструмент тестов, как запись векторов CEL в 4а.

## Открытые вопросы

1. Тип события в условии правила — по `uid` или по паре «тип устройства + `uid`» (вопрос от 2026-10-29). План следует `uid`.
2. Число номеров в записи `merged_in` (5, `MERGED_IN_SHOWN` в `server.js`) — оставить константой сервера (план) или перенести в машину (`grouping.mergedInShown`, правка IM)?
3. Отбор: 20 векторов переходов на `op:name`, 4 на исход, файл до 4 МБ — достаточно?
4. Вопросы 2–4 плана 53 (`transition_failed` у прототипа — `422`; порядок списка инцидентов; `countMine` вне блокировки) — ответ на 3 будет с числом из задачи 9.
