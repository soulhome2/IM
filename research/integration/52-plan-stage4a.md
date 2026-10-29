# Этап 4а: исполнитель CEL на Go и сверка с прототипом по векторам — план работ

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Сервер МИ вычисляет условия, правила интерфейса, определения и эффекты машины тем же смыслом, что прототип, и это доказано: каждый эталонный вектор «вход + мир → результат», записанный на исполнителе прототипа, на Go даёт тот же результат.

**Architecture:** В IM (пункт PROC-44) исполнитель прототипа получает два уточнения из решений PROC-44 (`let` — снимок, элемент `forEach` — инцидент черновика) и запись векторов: `tests/api.html?celVectors=1` пишет каждое вычисление CEL на исходной машине вместе с лентой фактов мира, `tools/cel_vectors.mjs` добавляет синтетику на границах и собирает `fixtures/cel-vectors.json`, `--check` повторяет все векторы на JS за секунды. На сервере новый чистый пакет `internal/im/machine` строит окружение cel-go из раздела `cel` машины (типы, настройки, определения, факты мира, `cel.bind`, проверка разрешённой части CEL), вычисляет условия, правила интерфейса, определения и эффекты на черновике в памяти; мир — значение каждого вычисления, глобального состояния нет. Тест сверки читает копию векторов и прогоняет каждый; затем выбор правил при приёме события (`ruleselect`) переходит на исполнитель.

**Tech Stack:** Go 1.27.1, `github.com/google/cel-go` v0.26.1 (`cel`, `ext.Bindings`), testify `require`, golangci-lint v2.14.0; IM — Node 22 (без зависимостей), cel-js 8.0.0 прототипа, headless Chrome.

**Spec:** [40-plan.md, «4. Исполнитель машины»](40-plan.md#4-исполнитель-машины--сервер-ми-l) (этап делится на 4а, 4б, 4в — решение пользователя 2026-10-29); [CEL.md](../../Specification/Workflow_machine/CEL.md) — язык, факты мира, операции эффектов; [BACKEND.md](../../Specification/Workflow_machine/BACKEND.md) — «Выражения машины — CEL», «Факты над множеством инцидентов»; пункт **PROC-44** и решения в1–в4 — [reviews/2026-10-22/plan.md](../../reviews/2026-10-22/plan.md) (строки 29–32, 40), основание — [review.md, «По ходу»](../../reviews/2026-10-22/review.md); проверенные факты и решения пользователя — `findings.md` обзора этапа 4 (scratchpad сессии 2026-10-29; всё нужное из него перенесено сюда). Образец исполнения — [prototype/cel-runtime.js](../../prototype/cel-runtime.js), мост к данным — `celApply`, `celWorld`, `celIncident` в [prototype/engine.js](../../prototype/engine.js); смысл операций эффектов на значениях — `ops()` в [tools/gen_quint.mjs](../../tools/gen_quint.mjs). Сервер — `3282d96`, IM — `a569c45`; сверено 2026-10-29.

## Global Constraints

- Сервер — `~/Work/incident-manager-server`, ветка `feature/im_operator`, от `3282d96`. IM — `/mnt/hgfs/VmWareShared/soul2home/IM`, ветка `feature/im_operator`, от `a569c45`. Пути в задачах — от корня репозитория задачи. Порядок: задачи 1–3 (IM), затем 4–10 (сервер); задача 4 копирует файлы из IM, поэтому начинается только после коммитов задач 1–3 (в `SOURCE` — хэш IM без `dirty`).
- Только локально. Push — только по просьбе пользователя. `~/Work/axxoncloudgo` не менять; кажется, что нужна правка облака, — **стоп, спросить пользователя**.
- Вход отложен: тестовый пользователь `test@axxonnet.test`; обработку токена не трогать. В 4а нет новых маршрутов HTTP.
- Пакет `internal/im/machine` — без базы и без HTTP. Тесты с базой — только в задаче 9 и только контейнер `im-test-db` (`127.0.0.1:55432`): `make test-local`; база стенда `imdb` — не для тестов. Контейнер не запущен — `sg docker -c "make test-db-up"`.
- Перед любой командой `go` — `source ~/go/offline-env.sh`. Адрес `npm.itvgroup.ru` недоступен, не использовать. Docker — только через `sg docker -c "…"`.
- cel-go — из кэша модулей, без сети. В сервер добавляется одной командой (задача 5): `GOPROXY=off GOFLAGS=-mod=mod go get github.com/google/cel-go@v0.26.1 golang.org/x/exp@v0.0.0-20240613232115-7f521ea00fb8 && GOPROXY=off GOFLAGS=-mod=mod go mod tidy`. `x/exp` указан явно: нужная cel-go версия `v0.0.0-20230905200255` в кэше не лежит, `20240613` лежит. Проверено 2026-10-29 на копии сервера `3282d96`: `go mod tidy` и `go build ./...` проходят; в `go.mod` добавляются только `github.com/google/cel-go v0.26.1` (прямая) и косвенные `cel.dev/expr v0.24.0`, `github.com/antlr4-go/antlr/v4 v4.13.0`, `github.com/stoewer/go-strcase v1.2.0`, `golang.org/x/exp v0.0.0-20240613232115-7f521ea00fb8`, `google.golang.org/genproto/googleapis/{api,rpc} v0.0.0-20240826202546-f6391c0de4c7`; прочие версии не меняются. Пробный модуль вне сервера — так же, `GOPROXY=off GOFLAGS=-mod=mod`.
- `make gen` и `make gen-api-im` не запускать (сгенерированный `v1` отстал). `make gen-api-operator` — можно (задача 4): генератор `~/go/bin/oapi-codegen` (форк v0.11.0). Сгенерированное руками не править.
- `golangci-lint run ./...` — 0 замечаний в каждой серверной задаче (`funlen` 120 строк / 60 операторов, `dupl` 150, `gosec`, `errorlint`, `staticcheck` — значит, без пометки `Deprecated:` у того, чем ещё пользуются).
- Тесты — testify `require`. Комментарии в коде и ADR — по-английски; документы IM — по-русски, простыми словами.
- **Правила IM.** Прототип только исполняет машину: правка `prototype/cel-runtime.js` и `engine.js` — только исполнение (как хранится значение `let`, чем привязан элемент `forEach`), правил IM в коде нет. Машина, правила и `State_rules/CHANGELOG.md` в этапе не меняются; кажется, что нужно, — **стоп, спросить**. Сгенерированные файлы — только своим инструментом (`fixtures/cel-vectors.json` — `node tools/cel_vectors.mjs --update`). `Specification/Workflow_machine/README.md` и `openapi.json` — CRLF; в этапе их не трогаем. Перед первой правкой IM — `git -C /mnt/hgfs/VmWareShared/soul2home/IM fetch`; есть новое на GitHub — сказать пользователю.
- Быстрые проверки IM после каждой задачи 1–3 (из `CLAUDE.md`): `python3 tools/build_workflow.py --check && python3 tools/check_machine.py && python3 tools/check_machine.py --mutations && python3 -m unittest tools/test_openapi30.py && node tools/check_cel.mjs && node tools/gen_quint.mjs --check && python3 tools/check_links.py` — после задачи 3 к ним добавляются `node tools/test_cel.mjs` и `node tools/cel_vectors.mjs --check`.
- Временные файлы — в scratchpad сессии исполнителя; в командах ниже он `$S` (задать `S=…` в той же строке).
- Векторы руками не правятся. Go расходится с вектором — правится Go. Кажется, что неправ прототип (расходится с CEL.md или спецификацией CEL), — **стоп, спросить**: это новый пункт ревью в IM, а не правка вектора.
- Коммиты. Сервер — один на задачу, сообщение по-русски, пишется инструментом записи файла в `.git/COMMIT_MSG_STAGE4A` (без heredoc), последняя строка — `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`; затем `git commit -q -F .git/COMMIT_MSG_STAGE4A`. IM — так же, файл `.superpowers/sdd/52-plan-stage4a/commit-msg.txt` (папка в `.gitignore`), `git commit -q -F .superpowers/sdd/52-plan-stage4a/commit-msg.txt`; сообщения задач 1–3 начинаются с `PROC-44: `; после задачи 3 — по правилу IM второй коммит пункта: отметка `[x]` в плане ревью, сообщение `PROC-44: хэши <к1>, <к2>, <к3> в плане ревью 2026-10-22`. Команды Bash — в одну строку. Журнал работ — `.superpowers/sdd/52-plan-stage4a/progress.md` в IM.

**Решения пользователя (обязательны):**

- Этап 4 — три части со своими планами и итоговым просмотром: 4а — исполнитель CEL на Go и векторы; 4б — столбцы инцидента и переходы в транзакции; 4в — операторский API (карточка, действия, переходы) и минимум из этапов 5–7 (состояние оператора, тестовые операторы, `/test/reset`, `/test/clock`).
- Этап 4 принимается без `tests/api.html` (`prototype/api.js` не шлёт `Authorization`, вход отложен): тесты Go, векторы JS↔Go (4а) и скрипт стенда «взять, отложить, передать, закрыть» (4в).
- PROC-44: в1 — векторы из записи при тестах API **и** синтетики на границах; в2 — файл в репозитории `fixtures/cel-vectors.json`, `--update` по команде, в CI `--check`; в3 — ошибка вычисления выражения — ошибка сервера, не `false`: переход не применяется, в `/actions` — ошибка, не «скрыто»; в4 — `let` в эффектах — снимок, как в модели Quint.
- Тип события в условии правила — по `uid`, как в машине, пока пользователь не ответил на вопрос «uid или пара».
- Копия контракта обновляется в этапе 4 (здесь — задача 4). «404 раньше `If-Match`» — этап 4в.

**Решения этого плана (обязательны для задач; обоснования — в конце):**

1. **Пакет `internal/im/machine`.** Он исполняет машину целиком (условия, эффекты, правила интерфейса, выбор правил), а не «CEL вообще»; `operatorapi` остаётся копией контракта, `ruleselect` уходит (задача 9). Имя — как «исполнитель машины» в 40-plan.md.
2. **Мир — значение вычисления.** Каждый факт мира и каждое определение — глобальный макрос cel-go: вызов `f(a, b)` при разборе становится `__w.f(a, b)`, где `__w` — переменная непрозрачного типа `World`; реализация берёт мир из своего первого аргумента. Программы компилируются один раз при загрузке, мир подаётся в активации каждого вычисления: глобального мира нет, вычисления параллельны. Позднего связывания функций в cel-go v0.26.1 нет (`LateFunctionBinding` там только запрещает свёртку констант). Проверено пробой 2026-10-29: вложенные вызовы в `exists`, `cel.bind`, определение из определения.
3. **Типы — из машины, а не структуры Go.** Свой `types.Provider` по `cel.types` (22 типа), значение записи — `record` (поля в словаре, `traits.Indexer`), как `registerType` в `cel-runtime.js`. Проверено пробой: поля, `timers[id]`, ошибка «нет ключа», переполнение `int` — ошибка.
4. **Факты над инцидентами в 4а — выражениями `ref` машины** над списком: у условий и правил — `Scope.Incidents`, у эффектов — черновик. Так делает прототип; запросы SQL — 4б.
5. **Эффекты — как `ops()` модели Quint:** черновик — инциденты по id в исходном порядке; `set`/`append` — только у `incident` и имени из `forEach`, пишут в черновик по id; после каждой записи `incident` и имена `forEach` перечитываются из черновика (запись видна дальше в том же эффекте и фактам над инцидентами); `let` — значение на момент вычисления; `forEach` сначала берёт id элементов, элемент читается из черновика.
6. **Векторы переходов — в 4б, не в 4а** (обоснование в конце).
7. **Запись — только на исходной машине,** часы и случайные числа в режиме записи зафиксированы; инциденты — в общем пуле файла; факты мира — лентой; отбор — не больше 30 векторов на имя, не больше 5 на один ответ.
8. **`--check` быстрый:** Chrome не запускает. Сверяет хэш машины, канонический вид файла, повторяет каждый вектор на JS по ленте, считает покрытие имён. `--update` — запись в Chrome (~3 мин) и синтетика.
9. **`ruleselect` заменяется в 4а** (задача 9). Файлы тестов этапа 3 (`internal/im/service/intake/service_test.go`, `internal/im/handler/test/intake*_test.go`) не меняются ни на байт; поэтому в `ruleselect` остаётся одна функция-переходник `UniqueKeyFromMachine` с пометкой `STAGE4B: remove`.
10. **Числа — только целые:** `int` — `int64` по объявленному типу; дробное, `float64` и строка на входе `int` — ошибка Go (прототип отбрасывает дробную часть и читает строку — в векторах таких входов нет, запись это проверяет).
11. **Ошибка вычисления — ошибка Go** (`(nil, err)`, не `false` и не «не выполнено»). В приёме события — `500`, ничего не записано (как любая ошибка `Process`).

## Review Focus

1. **`int` против `double`.** Дробных в машине нет, но cel-go с ними работает молча, а JSON по умолчанию читается во `float64`. Ждём: дробная константа и `/`, `%` — ошибка загрузки; на входе `int` — только целое; векторы читаются с `UseNumber`. Тесты — задача 5: `TestToCELIntNeverDouble`, `TestSubset`; задача 8: `TestTapeWorld` (`json.Number` и `int64` равны).
2. **`null` в данных сервера.** Пусто — `''`, `0`, `false`, `[]`, запись из нулей — как `value()` прототипа. Тесты — задача 5: `TestToCELNull`; синтетика «пусто на входе» (задача 3) идёт в задаче 8.
3. **Ошибка — не `false`.** Нет таймера в словаре, нет списка инцидентов, мир вернул ошибку — вычисление даёт ошибку, условие не «не выполнено». Тесты — задача 6: `TestGuardErrorIsNotFalse`, `TestRefFactWithoutIncidentsIsError`, `TestWorldErrorPropagates`; векторы с `expect.error` (задача 3).
4. **Порядок списков.** `members`, `dutyGroups`, `siblingsOf`, первый при равенстве у `mergePrimary` — по порядку входа; черновик хранит исходный порядок. Тесты — задача 6: `TestDefinitionKeepsListOrder`, `TestRecipientsKeepWorldOrder`; задача 7: `TestDraftKeepsOrder`; синтетика `mergePrimary` (задача 3).
5. **`let` — снимок.** На нынешней машине разницу со ссылкой не видно (векторы её не ловят), поэтому — отдельные тесты на эффекте из копии машины. Тесты — задача 1: «let — снимок»; задача 7: `TestEffectLetIsSnapshot`.
6. **Повтор ключа в словаре-литерале.** cel-go v0.26.1, как и cel-js, повтор принимает (берёт последний — проверено пробой), спасает только проверка подмножества при загрузке. Тесты — задача 1 и задача 5, `TestSubset` (одна таблица).
7. **Время — целые миллисекунды.** `now`, `deadline`, таймеры, `Rule.createdAt` — `UnixMilli()`, не секунды и не строки RFC 3339 (строки — только в ответах API, 4б/4в). Тесты — задача 9: `TestIntake_CreatedAtIsMillis`; векторы (задача 8).
8. **Запись эффекта видна дальше в том же вычислении.** `recordBreach` дописывает нарушение инциденту и тут же ищет участников группы по нему же; элемент `forEach` и `incident` — один инцидент черновика. Тесты — задача 7: `TestEffectOverlayVisible`, `TestEffectForEachReadsDraftByID`; векторы эффектов (задача 8).
9. **Параллельные запросы — у каждого свой мир.** Тест — задача 6: `TestWorldIsPerEvaluation` под `-race`.

---

## Формат векторов

Общий для задач 2, 3 и 8; в IM описывается в CEL.md, раздел «Векторы» (задача 3).

```json
{"$comment": "Собрано tools/cel_vectors.mjs --update из записи tests/api.html?celVectors=1 и синтетики. Руками не править",
 "counts": {"definition": 0, "effect": 0, "guard": 0, "rule": 0},
 "format": 1,
 "incidents": {"<ключ>": {"…Incident целиком…": ""}},
 "machineSha256": "<sha256 байтов workflow_schema.v1.json>",
 "vectors": [{"…": ""}]}
```

| Поле вектора | Что |
|---|---|
| `id` | `<kind>:<name>:<первые 10 hex sha256 канонического входа>`; вход — `args`, `use`, `scope`, `world`. Векторы — по `id` |
| `kind` | `guard`, `rule`, `definition`, `effect` |
| `name` | `fn` условия; ключ правила интерфейса, как в `cel-runtime.js` (`forms.close.fields.comment.requiredExpr`, `queueFilters.mine.expr`); имя определения; `fn` эффекта |
| `case` | только у синтетики: название случая по-русски |
| `args` | условие и эффект — аргументы из перехода как есть (литералы, пути к настройкам, выражения `expr<T>`); определение — значения по `params` |
| `use` | условие: поля `usage` из записи условия в переходе (`scopeRule`) |
| `scope` | `me`, `actor`, `surface`, `now`, `deadline` (уже `deadline ?? now`), `form` (Form целиком), `incident`, `before` (эффект), `option` и `actions` (правило), `incidents` — только если вычисление спрашивало список; у эффекта — список на начало эффекта |
| `world` | лента: `[{"fn", "args", "out"}]` — вызовы фактов мира без `ref` |
| `expect` | `{"value": …}` или `{"error": "текст"}`. Условие: `null` — выполнено, иначе `{"key", "vars"?}`. Эффект: `{"incidents": {"<id>": {"$ref": …}}, "actions": [{"action", "args"}]}` — инциденты, в которые писал `set`/`append`, и действия мира по порядку |

Значения: инцидент на входе и в ответе — `{"$ref": "<ключ>"}` в пул `incidents` (ключ — первые 16 hex sha256 канонического JSON инцидента); инцидент в аргументах ленты и действий — `{"$incident": "<id>"}` (факты о нём зависят от записи сервера, а не от полей); числа — только безопасные целые; `opt<T>` — список из 0 или 1; ключи `map<int, T>` — строки цифр; `null` — только в синтетике «пусто на входе». Канонический JSON — ключи по алфавиту, без пробелов; файл: шапка, по строке на инцидент пула, по строке на вектор. Лента: вызов ищется по `fn` и аргументам, равным по значению; вызова нет на ленте — вектор не прошёл («промах ленты»), даже если ждали ошибку; неиспользованная запись ленты — только в итоговом числе.

## Структура файлов

| Файл | Что | Задача |
|---|---|---|
| IM: `prototype/cel-runtime.js`, `prototype/engine.js` | `let` — снимок; элемент `forEach` — инцидент черновика; корень `set`; подмножество без повтора ключей и макросов по словарю; `store.instance` | 1 |
| IM: `tools/test_cel.mjs` | тесты исполнителя и библиотеки векторов (Node, без зависимостей) | 1, 2 |
| IM: `tests/cel-vectors.js`, `tests/api.html`, `tests/harness.js` | библиотека векторов и запись при `?celVectors=1` | 2 |
| IM: `tools/cel_vectors.mjs`, `Specification/Workflow_machine/fixtures/cel-vectors.json` | сборка, синтетика, `--check` | 3 |
| IM: `Specification/Workflow_machine/{CEL.md, BACKEND.md}`, `README.md`, `CLAUDE.md`, `.github/workflows/checks.yml`, `.graphifyignore`, `reviews/2026-10-22/plan.md` | раздел «Векторы», проверки, отметка PROC-44 | 3 |
| `Makefile`, `api/im/operator/*`, `internal/im/handler/operator/generated/{spec,types}.go`, `internal/im/handler/operator/problem.go`, `internal/im/ruleselect/pin_test.go` | копия контракта, машины, строк и векторов с IM HEAD | 4 |
| `api/im/operator/vectors_test.go` | векторы — от этой машины | 4 |
| `internal/im/machine/{doc.go, machine.go, types.go, env.go, subset.go}` (+ тесты), `go.mod`, `go.sum` | загрузка машины, типы, окружение, подмножество | 5 |
| `internal/im/machine/{eval.go, eval_test.go}` | мир, условия, доступность, правила интерфейса, определения | 6 |
| `internal/im/machine/{effect.go, effect_test.go}` | черновик и операции эффектов | 7 |
| `internal/im/machine/vectors_test.go` | лента и сверка по векторам | 8 |
| `internal/im/machine/{intake.go, intake_test.go}`, `internal/im/service/intake/{service.go, world.go}`, `internal/im/appservice/appservice.go`, `internal/im/ruleselect/*` | выбор правил на исполнителе | 9 |
| `docs/adr/004-machine-executor.md`; IM: `research/integration/{40-plan.md, 52-plan-stage4a.md}` | решения этапа, отметки | 10 |

---

### Task 1: IM — `let` снимком, элемент `forEach` из черновика, запреты подмножества

**Files:**
- Modify: `prototype/cel-runtime.js` (`subset`, `compileOps`, `runOps`)
- Modify: `prototype/engine.js` (`celApply`: у `store` — `instance`)
- Create: `tools/test_cel.mjs`

**Interfaces:**
- Produces:
  - контракт `store` эффекта (`cel.effect(fn, args, scope, store)`): `incidents()`, `touch(x)`, `world(action, args)` и новое `instance(id)` — живой CEL-инцидент черновика (в `engine.js` — `inst(id)`);
  - тексты ошибок сборки (в `create(W).errors`): `<где>: set / append — менять можно incident или элемент forEach, а не <имя>`; `<где>: ключ «<k>» в словаре повторяется`; `<где>: .<метод>() по словарю — макросы только по списку (CEL.md)`;
  - `tools/test_cel.mjs`: `test(name, fn)`, итог `test_cel: N из N`, код выхода — число упавших; таблица `SUBSET` (та же, что `TestSubset` задачи 5).

Как сделать (решение 5): `let` — `ctx[name] = snapshot(v)`: запись — новый экземпляр того же класса с копиями полей и тем же `source`, `Map` и массивы — копии, простые значения — как есть. `forEach` — элемент-инцидент (экземпляр `Incident`) заменяется на `store.instance(x.id)`. Корень пути `set`/`append` — `incident` или имя `forEach` из области видимости, иначе ошибка сборки. Повтор ключа — у узла `map` два одинаковых литерала-ключа. Макрос по словарю — у `rcall` из `METHODS` тип получателя (`env.check` над `expr.slice(recv.start, recv.end)` в том же окружении) начинается с `map`.

- [ ] **Step 1: Тесты**

Копия машины — `structuredClone(W)`; эффекты-пробы дописываются в `registries.effects`, условия — в `registries.guards`. `store` пробы: `incidents: () => list`, `instance: (id) => list.find((x) => x.id === id)`, `touch() {}`, `world() {}`. Инцидент `x` — `cel.value("Incident", {id: "x", timers: {reaction: {due: 100}, resolution: {}, hold: {}}})`.

```js
test("let — снимок: запись после let значение не меняет", ...)
  // _letSnapshot(timerId): [let t = incident.timers[timerId]; set incident.timers[timerId].due = now + 5; set incident.escalationLevel = t.due]
  // effect("_letSnapshot", ["reaction"], {incident: x, now: 1000, …}, store) → x.escalationLevel === 100n (не 1005n)
test("forEach — элемент читается из черновика по id", ...)
  // _forEachLive: [let ps = incidentById(incident.id); forEach p in ps: set p.transferCount = p.transferCount + 1; set incident.escalationLevel = incident.transferCount]
  // transferCount 0 → x.escalationLevel === 1n
test("set от имени let — ошибка сборки", ...)        // [let y = incident; set y.owner = 'a'] → errors содержит "менять можно incident или элемент forEach"
test("повтор ключа в словаре — ошибка сборки", ...)  // условие expr "{'a': 1, 'a': 2}['a'] == 1" → "повторяется"
test("макрос по словарю — ошибка сборки", ...)       // условие expr "incident.timers.exists(k, k == 'reaction')" → "по словарю"
test("подмножество — таблица SUBSET", ...)           // каждое выражение — как в таблице задачи 5 (можно / нельзя)
test("машина репозитория собирается без ошибок", ...) // IMCel.create(W).errors → []
```

- [ ] **Step 2: Тесты падают**

Run: `cd /mnt/hgfs/VmWareShared/soul2home/IM && git fetch && node tools/test_cel.mjs`
Expected: FAIL — «let — снимок», «set от имени let», «повтор ключа», «макрос по словарю», таблица `SUBSET`. «forEach» и «машина репозитория» проходят и на старом коде: их дело — не сломаться от снимка.

- [ ] **Step 3: Реализация** в `cel-runtime.js` и `engine.js`.

- [ ] **Step 4: Тесты проходят, прототип ведёт себя как раньше**

Run: `node tools/test_cel.mjs && node tools/check_cel.mjs | tail -1`
Expected: `test_cel: 7 из 7`; `Ошибок в выражениях машины: 0`.

Run: быстрые проверки IM (Global Constraints), затем самопроверка и тесты API по `CLAUDE.md` (headless Chrome, `--user-data-dir=$S/…`): `prototype/index.html?selftest` (бюджет 180000) и `tests/api.html` (120000).
Expected: `data-selftest="pass"`, `data-apitest="pass"`, итог тестов API — то же число, что на `a569c45`. Смысл для нынешней машины не меняется: в её эффектах `let` после записи не читается, а элементы `forEach` и раньше были живыми инцидентами.

Run: `python3 -c "import sys; sys.path.insert(0, 'tools'); import check_code_mutations as m; bad = m.stale(); print(len(m.MUTATIONS), 'порч, устаревших:', len(bad), bad)"`
Expected: устаревших — 0. Если `quint` в PATH — `node tools/check_quint_replay.mjs --traces=100`: 0 расхождений; нет — записать в журнал «не прогнано: нет quint, идёт в CI».

- [ ] **Step 5: Commit**

Сообщение: «PROC-44: let в эффектах — снимок, элемент forEach — инцидент черновика; в разрешённой части CEL — без повтора ключей и макросов по словарю».
Run: `git add prototype/cel-runtime.js prototype/engine.js tools/test_cel.mjs && git commit -q -F .superpowers/sdd/52-plan-stage4a/commit-msg.txt`

---

### Task 2: IM — запись векторов при тестах API

**Files:**
- Create: `tests/cel-vectors.js`
- Modify: `tests/api.html` (`<script src="cel-vectors.js">` сразу после `cel-runtime.js`; `<pre id="celvectors-out" hidden></pre>`), `tests/harness.js` (`finish`: при `window.IMCelVectors.recording` — `textContent` блока `celvectors-out` = `JSON.stringify(IMCelVectors.take())`)
- Modify: `tools/test_cel.mjs`

**Interfaces:**
- Consumes: `store.instance` (задача 1); `IMCel.create(W)` → `guard`, `rule`, `call`, `effect`, `value`, `plain`, `types`.
- Produces — `window.IMCelVectors` (файл грузится и в Node через `vm`, как `cel-runtime.js`):
  - `lib.canonical(v): string` — канонический JSON; не целое и не безопасное целое — исключение;
  - `lib.keyOf(plainIncident): string`; `lib.encode(cel, type, v, pool)` — CEL → данные вектора; `lib.encodeArg(v)` — то же для ленты и действий;
  - `lib.revive(cel, type, data, pool)` — данные вектора → CEL (`opt<T>` из списка, `map<int, T>` из строк, `$ref` из пула, `null` → как `value()`);
  - `lib.replay(cel, vector, pool): {ok, got, misses}` — вычислить вектор по ленте (мир — функции фактов без `ref`, промах — запись в `misses`; у эффекта — свой `store` с `instance` и учётом `touch`/`world`);
  - `lib.select(vectors): vectors` — отбор: по имени не больше `PER_NAME = 30`, на один `expect` не больше `PER_OUTCOME = 5`; ответы берутся по кругу в порядке первого появления, внутри ответа — в порядке записи;
  - `recording: bool`, `take(): {incidents, vectors}`.

Запись (только при `?celVectors=1` и без `?api=`): при загрузке файла — `Date.now = () => 1790845200000` (2026-10-01T09:00:00Z) и `Math.random` — mulberry32 с зерном 1. `IMCel.create` оборачивается: машина — не `window.IM_WORKFLOW` (ни тем же объектом, ни тем же JSON — `workflowPatch` тестов) — возвращается как есть. Иначе `guard`, `rule`, `call`, `effect` пишут вектор: вход — до вызова, мир — обёртка над `scope.world` (у `call` — над `w`) на каждый факт без `ref`, список инцидентов — при первом обращении (у эффекта — снимок `store.incidents()` на начало, в вектор — если эффект его спрашивал), ответ — результат или исключение (исключение пробрасывается дальше). Вложенное вычисление — свой вектор. Один `id` — два разных `expect` — исключение «один вход — два ответа».

- [ ] **Step 1: Тесты библиотеки** (в `tools/test_cel.mjs`)

```js
test("canonical: ключи по алфавиту; 1.5 и 2 ** 60 — ошибка", ...)
test("encode: инцидент — в пул, тот же второй раз — та же запись", ...)    // два encode одного x → один ключ в pool, {$ref: ключ}
test("encodeArg: инцидент на ленте — {$incident: id}", ...)
test("revive: opt<string> из [] и ['a']; map<int, int> из {'25': 1}; null у Incident.owner → ''", ...)
test("select: 40 векторов одного имени с тремя ответами — 30, ни одного ответа больше 5", ...)
test("запись и повтор: условие по ленте даёт тот же expect; вызов не с ленты — промах", ...)
  // обёрнутый create(W), hasPermission ['incident:claim'] с миром can → true; replay → ok; лента без can → misses = ["can"]
```

- [ ] **Step 2: Тесты падают**

Run: `node tools/test_cel.mjs`
Expected: FAIL — `IMCelVectors` не объявлен.

- [ ] **Step 3: Реализация** `tests/cel-vectors.js`, правки `api.html` и `harness.js`.

- [ ] **Step 4: Тесты проходят; запись в Chrome зелёная и повторяется**

Run: `node tools/test_cel.mjs`
Expected: `test_cel: 13 из 13`.

Run: `S=<scratchpad> && cd /mnt/hgfs/VmWareShared/soul2home/IM && for n in 1 2; do google-chrome --headless=new --disable-gpu --no-first-run --user-data-dir=$S/chrome$n --virtual-time-budget=180000 --dump-dom "file://$PWD/tests/api.html?celVectors=1" > $S/rec$n.html; done && python3 -c "import html,re,sys,json,hashlib;[print('pass' if 'data-apitest=\"pass\"' in p else 'FAIL', re.search(r'apitest-summary\">(.*?)<',p).group(1), (lambda d: (len(d['vectors']), sorted({v['kind'] for v in d['vectors']}), hashlib.sha256(json.dumps(d,sort_keys=True).encode()).hexdigest()[:12]))(json.loads(html.unescape(re.search(r'<pre id=\"celvectors-out\"[^>]*>(.*?)</pre>',p,re.S).group(1))))) for p in [open(f,encoding='utf-8').read() for f in sys.argv[1:]]]" $S/rec1.html $S/rec2.html`
Expected: обе строки — `pass`, итог тестов API — то же число, что без параметра; виды — `definition`, `effect`, `guard`, `rule`; число векторов и хэш в двух прогонах совпадают. Тесты API без параметра (`tests/api.html`) — `pass`, блок `celvectors-out` пустой.

- [ ] **Step 5: Commit**

Сообщение: «PROC-44: запись векторов CEL при тестах API — tests/api.html?celVectors=1, лента фактов мира, пул инцидентов».
Run: `git add tests/cel-vectors.js tests/api.html tests/harness.js tools/test_cel.mjs && git commit -q -F .superpowers/sdd/52-plan-stage4a/commit-msg.txt`

---

### Task 3: IM — `tools/cel_vectors.mjs`, файл векторов, раздел «Векторы», проверки

**Files:**
- Create: `tools/cel_vectors.mjs`; `Specification/Workflow_machine/fixtures/cel-vectors.json` (собирает `--update`)
- Modify: `Specification/Workflow_machine/CEL.md` (раздел «Векторы» перед «Библиотека»; во вступлении — «у каждого из 35 условий реестра — `expr`, у каждого из 27 эффектов — `do`»), `Specification/Workflow_machine/BACKEND.md` (в «На что обратить внимание» — пункт «Векторы CEL»; в «Когда готово» — строка про векторы)
- Modify: `README.md` («Проверки»), `CLAUDE.md` (быстрые проверки; таблица сгенерированных файлов; «Что поменял»), `.github/workflows/checks.yml` (шаг «Машина состояний»), `.graphifyignore`
- Modify (отдельный коммит): `reviews/2026-10-22/plan.md` (PROC-44 `[x]`, коммиты)

**Interfaces:**
- Consumes: `IMCelVectors.lib` (задача 2).
- Produces:
  - `node tools/cel_vectors.mjs --update` — Chrome на `tests/api.html?celVectors=1` (бюджет 180000, свой `--user-data-dir` во временной папке), тесты API не `pass` — стоп без записи; плюс синтетика; `select` к записанному (синтетика не отбирается); затем всё, что делает `--check`, и только потом запись файла;
  - `node tools/cel_vectors.mjs --check [--file=путь] [--machine=путь]` — код 0/1; печатает `векторов: N (guard …, rule …, definition …, effect …), расхождений: 0, промахов ленты: 0, без векторов: 0`;
  - формат файла — раздел «Формат векторов» выше.

`--check`, по порядку: файл есть (нет — «нет файла, соберите: node tools/cel_vectors.mjs --update»); `machineSha256` = sha256 байтов машины (иначе — «машина изменилась после сборки векторов: --update»); файл равен своей канонической записи (иначе — «правлен руками»); каждый вектор через `lib.replay` даёт свой `expect` без промахов (иначе — список `id`); у каждого из 35 условий, 27 эффектов, 52 определений и 73 правил интерфейса есть вектор, или имя в списке `UNCOVERED_OK` инструмента с причиной (список заполняется при первом `--update`, каждое имя — с причиной словами); размер файла не больше 8 МБ (больше — уменьшить `PER_NAME`).

Синтетика — на исходной машине (её настройки: `maxActive` пусто, `maxOnHold` 5, `reopenWindowMin` 1440, `idleHoldSec` 300). Инцидент-основа: `id` `s1`, `INC-9001`, `in_progress`, владелец `op1`, приоритет 50, все три таймера машины (`reaction`, `resolution`, `hold`). Мир — лента, записанная тем же `lib`.

| Случай | Что | Ждём |
|---|---|---|
| `timerExpired ['reaction']` | `due` = now − 1; = now; = now + 1; `due` 0; `fired` = `due` | выполнено, выполнено, нет, нет, нет |
| `timerExpired ['nope']` | таймера нет в словаре | `error` |
| `agentIdleFor ['session.idleHoldSec']` | `idleSec` 299; 300 | нет; выполнено |
| `withinHoldLimit` | своих отложенных, кроме этого, 4; 5 | выполнено; нет — ключ и подстановки машины |
| `withinReopenWindow` | `now − closedAt` = 86 400 000; + 1 | выполнено; нет |
| определение `mergePrimary` | два `new`, равные `priority` и `occurredAt`, в порядке [a, b] и [b, a] | `[a]`; `[b]` |
| определение `recipients` | дежурная группа, `members` → `[b, a]`, оба на месте и с доступом | `[b, a]` |
| определения `leftOf`, `spent` | на паузе с остатком 0; `due` = now; `due` = now + 1 | значения машины |
| пусто на входе | инцидент с `null` в `owner`, `closedAt`, `holdReasonId`; форма с `null`: `isOwnerOrUnowned`, `withinReopenWindow`, определение `addressee` | как у `value()`: выполнено; нет (`closedAt` — 0); `''` |

Раздел «Векторы» в CEL.md (по-русски, простыми словами): зачем векторы и откуда (запись + синтетика, решения PROC-44 в1, в2); формат (таблица выше); как их исполняет бэкенд — лента, пул, промах, сравнение по значению; что из этого следует для исполнителя бэкенда: определения — функции окружения, видят только свои параметры, настройки, факты мира и другие определения; `cel.bind` — расширение, его включают (в cel-go — `ext.Bindings()`); числа — `int64` по объявленному типу; в `incident.timers` — все таймеры машины (нет ключа — ошибка); `idleSec` — целые секунды вниз; в эффектах `incident.state` — уже новое (`to` перехода); ошибка вычисления — ошибка сервера (в3); `let` — снимок (в4); элемент `forEach` — инцидент черновика по id; повтор ключа и макросы по словарю — ошибка сборки; векторы переходов — этап 4б. BACKEND.md — коротко и ссылкой на раздел; в «Когда готово» — «векторы `fixtures/cel-vectors.json` проходят у исполнителя бэкенда (CEL.md, «Векторы»)». Чисел машины в новых строках BACKEND.md нет (их сверяет `check_machine.py`).

Регистрация: в CI, шаг «Машина состояний» — `node tools/test_cel.mjs` и `node tools/cel_vectors.mjs --check`; в `CLAUDE.md` — обе команды в быстрых проверках; строка таблицы сгенерированных файлов `Specification/Workflow_machine/fixtures/cel-vectors.json` | машина, запись тестов API, синтетика | `node tools/cel_vectors.mjs --update` (~3 мин, Chrome); в «Что поменял»: машину — `--update`; `prototype/cel-runtime.js`, `engine.js` — `node tools/test_cel.mjs` и `--check`; README, «Проверки» — пункт про `tools/cel_vectors.mjs` и `tools/test_cel.mjs`; `.graphifyignore` — файл векторов.

- [ ] **Step 1: Проверка без файла падает**

Run: `node tools/cel_vectors.mjs --check; echo $?`
Expected: «нет файла, соберите: node tools/cel_vectors.mjs --update», `1`.

- [ ] **Step 2: Реализация** `tools/cel_vectors.mjs` и синтетики.

- [ ] **Step 3: Сборка, повторяемость, проверка**

Run: `S=<scratchpad> && node tools/cel_vectors.mjs --update && sha256sum Specification/Workflow_machine/fixtures/cel-vectors.json > $S/v1 && node tools/cel_vectors.mjs --update && sha256sum -c $S/v1 && time node tools/cel_vectors.mjs --check`
Expected: файл собран; второй `--update` дал те же байты (`OK`); `--check` — код 0, `расхождений: 0, промахов ленты: 0, без векторов: 0`, меньше 10 с. Каждое имя в `UNCOVERED_OK` — с причиной; если там больше 10 имён — добавить синтетику, а не расширять список.

- [ ] **Step 4: Проверка ловит порчу**

Run: `S=<scratchpad> && F=Specification/Workflow_machine/fixtures/cel-vectors.json && python3 -c "import sys;l=open(sys.argv[1],encoding='utf-8').read().split('\n');i=next(k for k,x in enumerate(l) if '\"kind\":\"guard\"' in x and '\"value\":null' in x);l[i]=l[i].replace('\"value\":null','\"value\":{\"key\":\"x\"}');open(sys.argv[2],'w',encoding='utf-8').write('\n'.join(l))" $F $S/bad.json && node tools/cel_vectors.mjs --check --file=$S/bad.json; echo $?; python3 -c "import json,sys;w=json.load(open(sys.argv[1]));w['\$comment']+='.';json.dump(w,open(sys.argv[2],'w'),ensure_ascii=False)" Specification/Workflow_machine/workflow_schema.v1.json $S/w.json && node tools/cel_vectors.mjs --check --machine=$S/w.json; echo $?`
Expected: первый — код `1`, в списке расхождений — `id` испорченного вектора (правка сохраняет канонический вид, её ловит повтор); второй — «машина изменилась после сборки векторов», `1`. Ещё одна проба канона: любая строка файла с лишним пробелом (`--file=` копии) — «правлен руками», `1`.

- [ ] **Step 5: Документы и проверки**

Run: быстрые проверки IM (с `test_cel.mjs` и `--check`) и `python3 tools/check_links.py`.
Expected: всё зелёное; ссылки целы.

- [ ] **Step 6: Commit (два)**

Сообщение: «PROC-44: векторы CEL для бэкенда — tools/cel_vectors.mjs --update | --check, fixtures/cel-vectors.json, синтетика на границах; CEL.md и BACKEND.md — раздел «Векторы»».
Run: `git add tools/cel_vectors.mjs Specification/Workflow_machine/fixtures/cel-vectors.json Specification/Workflow_machine/CEL.md Specification/Workflow_machine/BACKEND.md README.md CLAUDE.md .github/workflows/checks.yml .graphifyignore && git commit -q -F .superpowers/sdd/52-plan-stage4a/commit-msg.txt`

Затем в `reviews/2026-10-22/plan.md` у PROC-44 — `[x]`, коротко что сделано и «Коммит: `<к1>`, `<к2>`, `<к3>`» (хэши задач 1–3). Сообщение: «PROC-44: хэши <к1>, <к2>, <к3> в плане ревью 2026-10-22».
Run: `git add reviews/2026-10-22/plan.md && git commit -q -F .superpowers/sdd/52-plan-stage4a/commit-msg.txt`

---

### Task 4: Сервер — копия контракта, машины, строк и векторов с IM HEAD

**Files:**
- Modify: `Makefile` (`vendor-operator-contract`: ещё `$(OP_SRC_DIR)/fixtures/cel-vectors.json` → `$(OP_API_DIR)/`)
- Modify (make): `api/im/operator/{openapi.v30.json, workflow_schema.v1.json, strings/*.json, SOURCE}`; Create (make): `api/im/operator/cel-vectors.json`
- Modify (make): `internal/im/handler/operator/generated/{spec.go, types.go}` (`make gen-api-operator`; проверено 2026-10-29: меняются только эти два — новые `ProblemCodeUNAUTHENTICATED`, `ProblemCodeBADREQUEST` и тексты)
- Modify: `internal/im/handler/operator/problem.go` (`CodeUnauthenticated = operatorgen.ProblemCodeUNAUTHENTICATED`, `CodeBadRequest = operatorgen.ProblemCodeBADREQUEST`; своим остаётся только `CodeNotImplemented`, комментарий — так же)
- Modify: `internal/im/ruleselect/pin_test.go` (`intakePinSHA256`)
- Create: `api/im/operator/vectors_test.go`; Modify: `internal/im/handler/operator/problem_test.go`

**Interfaces:**
- Produces: `api/im/operator/cel-vectors.json` — копия векторов (не встраивается в бинарник: читают только тесты, по пути).

- [ ] **Step 1: Тесты**

```go
func TestCELVectorsMatchMachine(t *testing.T) // os.ReadFile("cel-vectors.json"); format == 1; machineSha256 == hex(sha256(Machine))
func TestServerCodesFromContract(t *testing.T) // CodeUnauthenticated == operatorgen.ProblemCodeUNAUTHENTICATED; CodeBadRequest == operatorgen.ProblemCodeBADREQUEST
```

- [ ] **Step 2: Тесты падают**

Run: `cd ~/Work/incident-manager-server && source ~/go/offline-env.sh && go test ./api/im/operator/ ./internal/im/handler/operator/ 2>&1 | tail -5`
Expected: FAIL — нет `cel-vectors.json`; `ProblemCodeUNAUTHENTICATED` не объявлен.

- [ ] **Step 3: Копия и генерация**

Run: `git -C /mnt/hgfs/VmWareShared/soul2home/IM status --porcelain -- Specification/Workflow_machine && make vendor-operator-contract && cat api/im/operator/SOURCE && PATH=$PATH:$HOME/go/bin make gen-api-operator && git status --short`
Expected: `status` IM пуст; в `SOURCE` — хэш отметки PROC-44 без `dirty`; изменены четыре файла копии и `cel-vectors.json`, из сгенерированных — только `spec.go` и `types.go`. Затем правка `problem.go`.

- [ ] **Step 4: Замок `ruleselect` — только комментарий**

Run: `python3 -c "import json,subprocess as s;o=json.loads(s.check_output(['git','show','3282d96:api/im/operator/workflow_schema.v1.json']));n=json.load(open('api/im/operator/workflow_schema.v1.json'));D=['conditionMatches','conditionRank','ruleRank','ruleMatches','ruleBeats','ruleFor'];print(all(o['cel']['definitions'][k]==n['cel']['definitions'][k] for k in D), all(o['cel']['world'][k]==n['cel']['world'][k] for k in ['deviceInGroup','groupDepth']), all(o['cel']['types'][k]==n['cel']['types'][k] for k in ['Event','Rule','Condition']), {k:v for k,v in o['intake'].items() if k!='\$comment'}=={k:v for k,v in n['intake'].items() if k!='\$comment'}, o['intake']['\$comment']!=n['intake']['\$comment'])"`
Expected: `True True True True True` — изменился только `intake.$comment` (уточнение PROC-93 про ключ уникальности; сервер так и работает с этапа 3). Иначе — **стоп, спросить**. `intakePinSHA256` = `026a9bafa0cd54864ecf9303e4526ba1285654699f20f4ec1360a0eea1f51c41` (посчитано 2026-10-29 на машине IM `a569c45`; задачи 1–3 машину не меняют), комментарий `// vendored <SOURCE>`.

- [ ] **Step 5: Тесты проходят**

Run: `go build ./... && go test ./api/... ./internal/im/handler/operator/... ./internal/im/ruleselect/ ./internal/im/service/intake/ && make test-local 2>&1 | tail -8 && golangci-lint run ./...`
Expected: PASS всех пакетов (тесты этапов 2 и 3 — без правок); lint — 0.

- [ ] **Step 6: Commit**

Сообщение: «Этап 4а: копия контракта, машины, строк и векторов CEL с IM <SOURCE>; коды 401 и 400 — из контракта».
Run: `git add Makefile api/im/operator internal/im/handler/operator internal/im/ruleselect/pin_test.go && git commit -q -F .git/COMMIT_MSG_STAGE4A`

---

### Task 5: Пакет `machine` — загрузка, типы, окружение, разрешённая часть CEL

**Files:**
- Create: `internal/im/machine/{doc.go, machine.go, types.go, env.go, subset.go}`
- Test: `internal/im/machine/{machine_test.go, types_test.go, subset_test.go}`
- Modify: `go.mod`, `go.sum` (команда — Global Constraints)

**Interfaces:**
- Consumes: `operatorapi.Machine`.
- Produces:
  - `type Machine struct` — после `Load` не меняется, безопасен для параллельных вычислений;
  - `func Load(raw []byte) (*Machine, error)` — все ошибки сборки сразу (`errors.Join`), каждая `<где>: <что>`, `<где>` — как в `cel-runtime.js`: `cel.definitions.norm`, `cel.world.siblingsOf.ref`, `registries.guards.timerExpired`, `registries.guards.withinActiveLimit.failKey`, `forms.close.fields.comment.requiredExpr`;
  - `func Vendored() (*Machine, error)` — `sync.OnceValues` над `Load(operatorapi.Machine)`;
  - `type Counts struct { Types, Settings, WorldFacts, RefFacts, Definitions, Guards, Effects, UIRules int }`, `func (m *Machine) Counts() Counts`;
  - внутри пакета: `func (m *Machine) toCEL(typ string, v any) (ref.Val, error)`, `func toPlain(v ref.Val) (any, error)` (данные: `string`, `int64`, `bool`, `[]any`, `map[string]any`; запись — словарь всех полей), `type record struct{…}` (`ref.Val` + `traits.Indexer`), `func checkSubset(where string, a *cel.Ast) []error`.

Окружение (решения 2, 3): типы — свой `types.Provider` по `cel.types`, `opt<T>` объявляется как `list<T>`, `map<int, T>` — ключ `int`; `__w` — переменная непрозрачного типа `World`; каждый факт мира и определение — глобальный макрос → вызов члена `__w`, перегрузка на `World` с параметрами из машины; определение — своя программа в окружении только из параметров, настроек и `__w`; `ref` — программа с `incidents: list<Incident>` и параметрами; настройки — значения по `cel.settings` (раздел машины или путь `from`) в базовой активации; `ext.Bindings()`; `cel.EnableMacroCallTracking()`; `HomogeneousAggregateLiterals` не включается (как `homogeneousAggregateLiterals: false`). Имена верхнего уровня условий — как `TOP` в `cel-runtime.js` (`me`, `actor`, `incident`, `incidents`, `form`, `surface`, `now`, `deadline`) плюс аргументы по `argTypes` (`setting` и без типа — `dyn`) и поля `usage`; правил интерфейса — `TOP` плюс `option: string`, `actions: list<string>`; результат условия — `bool`, определения — `returns`, правила — тип из таблицы `uiRule`. Ключи правил интерфейса — ровно те, что у `uiRule` в `cel-runtime.js`. Определения, вызывающие друг друга по кругу, и имя определения, совпадающее с функцией CEL, — ошибка загрузки.

Перевод данных в CEL (`toCEL`) — как `value()` прототипа, но строже с числами:

| Тип | `nil` | Принимается | Ошибка |
|---|---|---|---|
| `string` | `''` | `string` | остальное |
| `int` | `0` | `int`, `int64`, целое `json.Number` | дробное, `float64`, строка |
| `bool` | `false` | `bool` | остальное |
| `opt<T>` | `[]` | значение `T` → `[v]`; список из 0 или 1 | список длиннее 1 |
| `list<T>`, `map<string\|int, T>` | пустой | `[]any`; `map[string]any` (ключи `int` — строки цифр) | остальное |
| запись | все поля пустые | `map[string]any`: нет поля — пусто, лишнее — отбрасывается | не словарь |
| `dyn` | `''` | как есть; целые — `int64` | `float64`, дробное |

Проверка подмножества — обход проверенного дерева: можно константы `bool`, `int`, `string`; списки; словари (повтор ключа-литерала — ошибка); поле, `[]`; операторы `== != < <= > >= && || ! ?: + - *`, унарный `-`, `in`; `size`; вызовы членов `__w` из макросов; генераторы (comprehension) — только если их исходный макрос `exists`, `all`, `filter`, `map` над списком (тип `IterRange` — не словарь) или `bind`. Всё прочее — ошибка: `double`, `/`, `%`, методы, `has`, `exists_one`, неизвестная функция, `__w` в тексте выражения.

- [ ] **Step 1: Тесты**

```go
func TestLoadVendoredMachine(t *testing.T)    // NoError; Counts() == Counts{Types: 22, Settings: 8, WorldFacts: 14, RefFacts: 6, Definitions: 52, Guards: 35, Effects: 27, UIRules: 73}
func TestLoadReportsEveryError(t *testing.T)  // копия: isOwner.expr = "incident.nope == me", unowned.expr = "x.owner == 1" → в тексте и "registries.guards.isOwner", и "cel.definitions.unowned"
func TestDefinitionSeesOnlyItsScope(t *testing.T) // unowned.expr = "x.owner == me" → ошибка "cel.definitions.unowned"; "x.owner == '' && now > 0" → ошибка
func TestDefinitionCycle(t *testing.T)        // isDone вызывает closedFinished, closedFinished — isDone → ошибка "cycle"
func TestToCELNull(t *testing.T)              // nil: "string" → "", "int" → 0, "bool" → false, "opt<string>" → [], "list<string>" → [], "Incident" → owner "", timers {} 
func TestToCELIntNeverDouble(t *testing.T)    // json.Number("5"), int64(5), 5 → Int(5); json.Number("1.5"), float64(5), "5" → ошибка
func TestToCELOpt(t *testing.T)               // "opt<string>": "a" → ["a"]; []any{"a"} → ["a"]; []any{"a","b"} → ошибка
func TestToCELRecordDropsUnknownFields(t *testing.T) // Form {"comment": "x", "nope": 1} → comment "x", остальные "", поля nope нет
func TestPlainRoundTrip(t *testing.T)         // полный Incident (все поля, timers reaction/resolution/hold, breaches, leftGroup) → toCEL → toPlain → равен
func TestSubset(t *testing.T)                 // таблица ниже; переменные: xs list<string>, n int, b bool, s string, m map<string, int>, f Form
```

Таблица `SUBSET` (та же в `tools/test_cel.mjs`):

| Можно | Нельзя |
|---|---|
| `xs.exists(x, x == 'a')`, `xs.all(x, x != '')`, `xs.filter(x, x == 'a')`, `xs.map(x, x)` | `1.5 > 0` |
| `cel.bind(p, 1, p + 1) == 2` | `n / 2 == 1`, `n % 2 == 1` |
| `{'k': 1}['k'] == 1`, `size(xs) > 0`, `'a' in xs` | `s.startsWith('a')` |
| `b ? 1 == 1 : false`, `-n < 0`, `!b` | `has(f.comment)`, `xs.exists_one(x, x == 'a')`, `nope(1)` |
| | `{'a': 1, 'a': 2}['a'] == 1`, `m.exists(k, k == 'a')` |

- [ ] **Step 2: Тесты падают**

Run: `cd ~/Work/incident-manager-server && source ~/go/offline-env.sh && go test ./internal/im/machine/ 2>&1 | tail -3`
Expected: FAIL — пакета нет.

- [ ] **Step 3: Зависимость и реализация**

Run: команда добавления cel-go из Global Constraints, затем `git diff go.mod`.
Expected: в `go.mod` — ровно добавления из Global Constraints. Затем — код пакета.

- [ ] **Step 4: Тесты проходят**

Run: `go test ./internal/im/machine/ -v 2>&1 | tail -15 && go build ./... && golangci-lint run ./...`
Expected: PASS; lint — 0.

- [ ] **Step 5: Commit**

Сообщение: «Этап 4а: пакет machine — машина из копии, типы и настройки, окружение cel-go с миром на вычисление, разрешённая часть CEL; cel-go v0.26.1».
Run: `git add go.mod go.sum internal/im/machine && git commit -q -F .git/COMMIT_MSG_STAGE4A`

---

### Task 6: Мир, условия, доступность, правила интерфейса, определения

**Files:**
- Create: `internal/im/machine/eval.go`
- Test: `internal/im/machine/eval_test.go`

**Interfaces:**
- Consumes: задача 5.
- Produces:
  - `type World interface { Fact(name string, args []any) (any, error) }` — факты мира без `ref`; аргументы и ответ — данные (`toPlain`/`toCEL` по сигнатуре из `cel.world`), инцидент — словарь целиком;
  - `type Scope struct { Me, Actor, Surface, Option string; Now, Deadline int64; Incident, Before, Form map[string]any; Incidents []map[string]any; Actions []string; World World }` — `Deadline == 0` → `Now`; `Incident == nil` — имя `incident` не связано (обращение — ошибка); `Form == nil` — все поля `''`; `Incidents` строится в CEL, только если выражение его спросило;
  - `var ErrNoIncidents = errors.New("machine: ref fact needs the incidents list")`;
  - `type Fail struct { Key string; Vars map[string]any }` — `Vars == nil`, если подстановок нет;
  - `func (m *Machine) Guard(fn string, args []any, use map[string]any, s *Scope) (*Fail, error)` — `nil, nil` — выполнено;
  - `type Availability struct { OK, Hidden, NotFrom bool; Fail *Fail; Guard string }`;
  - `func (m *Machine) Availability(actionID string, s *Scope) (Availability, error)`;
  - `func (m *Machine) UIRule(where string, s *Scope) (any, error)`, `func (m *Machine) UIRuleNames() []string`;
  - `func (m *Machine) Definition(name string, args []any, w World) (any, error)`.

Смысл — как `guard`, `contextOf`, `rule`, `call` в `cel-runtime.js` и `availability`, `firstFail` в `engine.js`: аргумент `setting` — значение по пути в машине как `dyn`; аргумент `list<T>` не списком — `[arg]`; условие выполнено, только если результат `true`; иначе ключ — `failKey` (выражение) или `failKeys[0]`, подстановки — `failVars` (выражение-словарь или словарь выражений); ошибка мира — `fmt.Errorf("world %s: %w", name, err)`. `Availability`: переход или `navActions.items` по id; нет такого — `{Hidden: true}`; у перехода `s.Incident["state"]` не из `from` — `{Hidden: true, NotFrom: true, Fail: &Fail{Key: "workflow.guard.wrong_state"}}`; условия по порядку, первое невыполненное — `{Hidden: onFail == "hide", Fail, Guard: fn}`; все выполнены — `{OK: true}`; ошибка любого — `(Availability{}, err)`.

- [ ] **Step 1: Тесты**

Мир теста — `factWorld map[string]func(args []any) (any, error)`, неизвестный факт — ошибка. Инцидент `inc(state, owner)` — полный, все три таймера.

```go
func TestGuardPassesOnlyOnTrue(t *testing.T)    // hasPermission ["incident:claim"]: can → true ⇒ nil; false ⇒ &Fail{Key: "workflow.guard.no_permission", Vars: {"p": "incident:claim"}}
func TestGuardErrorIsNotFalse(t *testing.T)     // timerExpired ["nope"] ⇒ err != nil, fail == nil
func TestGuardSettingArg(t *testing.T)          // agentIdleFor ["session.idleHoldSec"]: idleSec 300 ⇒ nil; 299 ⇒ Key "workflow.guard.agent_online"
func TestGuardFailKeyExpr(t *testing.T)         // копия с limits.maxActive = 1; у op1 в работе INC-1 (не этот), can hold true, отложенных 0
                                                // withinActiveLimit ⇒ Key "workflow.guard.active_limit", Vars {"n": 1, "id": "INC-1"}
func TestRefFactWithoutIncidentsIsError(t *testing.T) // withinHoldLimit, Incidents nil ⇒ errors.Is(err, ErrNoIncidents)
func TestWorldErrorPropagates(t *testing.T)     // can возвращает errBoom ⇒ errors.Is(err, errBoom)
func TestAvailability(t *testing.T)             // claim: state closed ⇒ NotFrom, Hidden; new, can false ⇒ Hidden, Guard "hasPermission";
                                                // agentState "not_ready" ⇒ !Hidden, Guard "agentReady"; иначе OK; "nope" ⇒ Hidden
func TestUIRule(t *testing.T)                   // "queueFilters.mine.expr", мир: isGroup → false, members → []: in_progress и owner == me ⇒ true, owner другой ⇒ false;
                                                // UIRuleNames() — 73, среди них "forms.close.fields.comment.requiredExpr"
func TestDefinitionKeepsListOrder(t *testing.T) // mergePrimary([a, b], "op1"), оба new, priority и occurredAt равны ⇒ [a]; ([b, a]) ⇒ [b]
func TestRecipientsKeepWorldOrder(t *testing.T) // recipients("g", x): isGroup g, members g ⇒ ["b","a"], agentState ready, access true ⇒ ["b","a"]
func TestWorldIsPerEvaluation(t *testing.T)     // 32 горутины × 100 Guard(hasPermission): мир горутины i — can = (i%2 == 0) ⇒ каждая видит своё
```

- [ ] **Step 2: Тесты падают**

Run: `go test ./internal/im/machine/ -run 'Guard|Availability|UIRule|Definition|Recipients|World|RefFact' 2>&1 | tail -3`
Expected: FAIL — не собирается (`Guard` не объявлен).

- [ ] **Step 3: Реализация** `eval.go`.

- [ ] **Step 4: Тесты проходят, гонок нет**

Run: `go test -race ./internal/im/machine/ 2>&1 | tail -5 && golangci-lint run ./...`
Expected: PASS без `DATA RACE`; lint — 0.

- [ ] **Step 5: Commit**

Сообщение: «Этап 4а: исполнитель — условия (первое невыполненное, onFail, failKey и failVars), правила интерфейса, определения; мир — свой у каждого вычисления, ошибка — не false».
Run: `git add internal/im/machine && git commit -q -F .git/COMMIT_MSG_STAGE4A`

---

### Task 7: Эффекты на черновике в памяти

**Files:**
- Create: `internal/im/machine/effect.go`
- Test: `internal/im/machine/effect_test.go`

**Interfaces:**
- Consumes: задачи 5, 6 (`Scope`, `World`, факты над инцидентами).
- Produces:
  - `type Draft struct{…}`; `func NewDraft(incidents []map[string]any) (*Draft, error)` — порядок сохраняется; `func (d *Draft) Incidents() []map[string]any` — в исходном порядке; `func (d *Draft) Get(id string) (map[string]any, bool)`; `func (d *Draft) Changed() []map[string]any` — куда писали `set`/`append`, в порядке первой записи; `func (d *Draft) Actions() []Action`;
  - `type Action struct { Action string; Args map[string]any }` — действия мира по порядку (`log`, `notify`, `command`, `evict`, `setCursor`, `shareAnswers`, `touch`); значение-инцидент в `Args` — `map[string]any{"$incident": id}`;
  - `func (m *Machine) Effect(fn string, args []any, s *Scope, d *Draft) error` — `s.Incident` (уже с `state` = `to` перехода) добавляется в черновик, если его там нет; `s.Incidents` эффект не читает — факты над инцидентами идут по `d`; после ошибки черновик не годится, его выбрасывают (всё или ничего — у вызывающего, 4б).

Сборка программ — как `program`/`compileOps` в `cel-runtime.js`: аргументы перехода, недостающие — из `defaults`; литерал-строка подставляется как `${имя}` в пути и выражения; `expr<T>` — выражение перехода, считается в начале эффекта; `setting` — значение по пути; у `call` аргументы — значения, без подстановок. Программы на каждый эффект каждого перехода машины собираются при `Load` (ошибки — в общий список), остальные — при первом вызове, кэш под `sync.Mutex`. Ошибки сборки — как в JS: путь не к полю, `before` в пути, `append` не в список, словарь-литерал не с полями типа, корень `set`/`append` — не `incident` и не имя `forEach`, имя `let` из ветки `if` после неё, `call` эффекта без `do` или самого себя.

Исполнение (решение 5, образец — `ops()` в `tools/gen_quint.mjs`):

```
let x = e        → x = значение e (снимок)
set p = e        → корень p — incident или имя forEach → id; значение e переводится в тип пути (toPlain → toCEL);
                   черновик[id] = копия с новым значением по пути; затем incident и имена forEach перечитываются из черновика
append p, e      → то же, список + [значение]
if c A else B    → ветка в копии области имён; после — перечитать
forEach x in e   → сначала список id элементов; для каждого: копия области + x = черновик[id]; после — перечитать
call f(a)        → значения аргументов; тело f с me, actor, incident, before, form, surface, now, deadline вызывающего
world a(args)    → Action{a, значения args}
```

- [ ] **Step 1: Тесты**

```go
func TestEffectExprArg(t *testing.T)            // setOwner ["actor"], Actor "op2" ⇒ Changed()[0]["owner"] == "op2"
func TestEffectLiteralSubstitution(t *testing.T) // increment ["transferCount"]: 2 ⇒ 3
func TestEffectSetFlagDynToInt(t *testing.T)    // setFlag ["closedAt", "now"], Now 1790845200000 ⇒ closedAt == int64(1790845200000)
func TestEffectCallAndDefaults(t *testing.T)    // startTimer ["resolution"] (mode и ifStopped — из defaults; startsOnce ⇒ call resumeTimer; pausable):
                                                // resolution due 0, paused true, left 60000, fired 0 ⇒ due == Now+60000, paused false, left 0
func TestEffectOverlayVisible(t *testing.T)     // recordBreach ["reaction", "workflow.journal.group_breach"], Deadline D; P — основной, L — привязан к P, linkedAt < D, не закрыт
                                                // ⇒ Changed: P и L, у обоих breaches == [{kind reaction, at D, owner addressee(before)}], slaBreached true;
                                                //   Actions: log (incident {$incident: L}, actor "dispatcher"), затем touch (L)
func TestEffectLetIsSnapshot(t *testing.T)      // копия с _letSnapshot (задача 1): due 100 ⇒ escalationLevel == 100
func TestEffectForEachReadsDraftByID(t *testing.T) // копия с _forEachLive (задача 1): transferCount 0 ⇒ escalationLevel == 1
func TestEffectBuildErrors(t *testing.T)        // копии: set от имени let; set before.owner; append в incident.owner; append в breaches словаря без owner;
                                                // let в then, чтение после if ⇒ Load: у каждой своя ошибка с "registries.effects.<fn>"
func TestEffectErrorStops(t *testing.T)         // stopTimer ["nope"] ⇒ ошибка
func TestEffectWorldActions(t *testing.T)       // notify ["addressee(incident)"], owner "op2", Actor "op1", members/onDuty/access по миру ⇒
                                                // Actions == [{notify, {incident: {$incident: id}, to: "op2", recipients: ["op2"], alert: false, emptyLog: ""}}]
func TestDraftKeepsOrder(t *testing.T)          // NewDraft([a, b, c]); запись в c, затем в a ⇒ Changed ids [c, a]; Incidents ids [a, b, c]
```

- [ ] **Step 2: Тесты падают**

Run: `go test ./internal/im/machine/ -run 'Effect|Draft' 2>&1 | tail -3`
Expected: FAIL — `Effect` не объявлен.

- [ ] **Step 3: Реализация** `effect.go` (каждая функция — в пределах `funlen`).

- [ ] **Step 4: Тесты проходят**

Run: `go test -race ./internal/im/machine/ 2>&1 | tail -5 && golangci-lint run ./...`
Expected: PASS; lint — 0.

- [ ] **Step 5: Commit**

Сообщение: «Этап 4а: исполнитель — эффекты на черновике в памяти: set, append, let снимком, if, forEach по id, call, действия мира; ${аргумент} и expr<T>».
Run: `git add internal/im/machine && git commit -q -F .git/COMMIT_MSG_STAGE4A`

---

### Task 8: Сверка с прототипом по векторам

**Files:**
- Create: `internal/im/machine/vectors_test.go`

**Interfaces:**
- Consumes: всё из задач 5–7; `api/im/operator/cel-vectors.json` (задача 4) — по пути `../../../api/im/operator/cel-vectors.json`.
- Produces (только тесты): `type vectorFile struct { Format int; MachineSHA256 string; Incidents map[string]map[string]any; Vectors []vector }`; `func loadVectors(t *testing.T) *vectorFile` — `json.Decoder.UseNumber`, `$ref` разворачиваются; `type tapeWorld struct{…}`, `func newTape(entries []tapeEntry) *tapeWorld`, `func (w *tapeWorld) Fact(name string, args []any) (any, error)` — поиск по `fn` и аргументам, равным по значению (`json.Number` и `int64` — одно; инцидент — по `id`); промах — ошибка и запись в `w.misses`; `func runVector(m *Machine, f *vectorFile, v vector) (got any, misses []string, err error)`.

Сравнение — по значению после разворота `$ref` (обе стороны — данные: `int64`, строки, списки, словари). Условие — `nil` ⇒ `null`, иначе `{"key", "vars"}` (`vars` — если есть). Эффект: `NewDraft(scope.incidents)` или `[scope.incident]`, `Effect`, затем `{"incidents": Changed() по id, "actions": Actions()}`. `expect.error` — Go должен вернуть ошибку (текст не сравнивается).

- [ ] **Step 1: Тесты**

```go
func TestTapeWorld(t *testing.T) // попадание — out; json.Number("5") и int64(5) — одно; аргумент-инцидент — по id; вызова нет — ошибка и misses == ["can(...)"]
func TestVectors(t *testing.T)   // vectorFile.MachineSHA256 == sha256(operatorapi.Machine); подтест на каждый id;
                                 // упал — got и expect (по полям у инцидентов) в сообщении; промах ленты — провал, даже при expect.error;
                                 // в конце t.Logf: "vectors N (guard …, rule …, definition …, effect …), mismatches M, tape misses K, unused tape entries U"
```

- [ ] **Step 2: Прогон**

Run: `go test ./internal/im/machine/ -run 'TestVectors|TestTapeWorld' -v 2>&1 | grep -E '^(=== RUN|--- FAIL|ok|FAIL)|vectors [0-9]' | tail -30`
Expected сначала: FAIL — `runVector` не объявлен; затем — расхождения, если есть. Каждое разобрать: правится исполнитель (задачи 5–7), а не вектор; похоже на ошибку прототипа — **стоп, спросить**. Каждую причину — в журнал работ.

- [ ] **Step 3: Тесты проходят**

Run: `go test -race ./internal/im/machine/ -v -run TestVectors 2>&1 | grep -E 'vectors [0-9]|^ok|FAIL' && golangci-lint run ./...`
Expected: `ok`; итог `mismatches 0, tape misses 0`; число векторов — как `counts` файла; lint — 0.

- [ ] **Step 4: Commit**

Сообщение: «Этап 4а: сверка исполнителя Go с прототипом — все векторы CEL совпадают, мир — по ленте, промах ленты — провал».
Run: `git add internal/im/machine && git commit -q -F .git/COMMIT_MSG_STAGE4A`

---

### Task 9: Выбор правил при приёме события — на исполнителе

**Files:**
- Create: `internal/im/machine/intake.go`; Test: `internal/im/machine/intake_test.go` (тесты из `ruleselect_test.go` и `pin_test.go` — с теми же именами и проверками)
- Modify: `internal/im/service/intake/service.go` (`machine.Vendored()` в `NewService`, `Intake`, `ApplyUniqueKey`), `internal/im/service/intake/world.go` (`newTreeWorld` возвращает `machine.IntakeWorld`), `internal/im/appservice/appservice.go:318` (`machine.UniqueKeyFromMachine`)
- Delete: `internal/im/ruleselect/{ruleselect_test.go, pin_test.go}`; Modify: `internal/im/ruleselect/ruleselect.go` — остаётся только `UniqueKeyFromMachine`, переходник на `machine`, комментарий `STAGE4B: remove together with the stage-3 test that imports it`
- Не меняются: `internal/im/service/intake/service_test.go`, `internal/im/handler/test/intake*_test.go`

**Interfaces:**
- Consumes: `Definition` (задача 6).
- Produces:
  - `type IntakeEvent struct { GUID, EventType, Device, DeviceType string }`;
  - `type IntakeCondition struct { EventType, Device, DeviceType, Group string }` — `""` — поле не задано (`opt` пустой);
  - `type IntakeRule struct { GUID string; Priority, CreatedAt int64 /* ms */; Scenarios []string; Conditions []IntakeCondition }`;
  - `type IntakeWorld interface { DeviceInGroup(device, group string) bool; GroupDepth(group string) int }`;
  - `type Pick struct { Scenario string; Rule *IntakeRule }`;
  - `func OrderRules(rules []*IntakeRule) []*IntakeRule` — копия по `strings.ToLower(GUID)`;
  - `func (m *Machine) Intake(w IntakeWorld, rules []*IntakeRule, e IntakeEvent) ([]Pick, error)`;
  - `func ApplyUniqueKey(picks []Pick, key []string) ([]Pick, error)`, `func UniqueKeyFromMachine(raw []byte) ([]string, error)` — смысл и ошибки прежние (из `ruleselect`).

`Intake` — тот же порядок, что `ruleselect.Intake` (`intake.$comment` машины), но каждое суждение — определение машины: `ruleMatches(r, e)`, `ruleFor(ordered, e, s)` (победитель — первый, правило — по `guid`), `ruleBeats(x, y, e)`. Мир — переходник: `deviceInGroup`, `groupDepth` → `IntakeWorld`, любой другой факт — ошибка. Сортировка ошибок не возвращает, поэтому `ruleBeats` для пар победителей считается до `sort.SliceStable`. Ошибка вычисления → `Intake` возвращает ошибку → `Process` — `fmt.Errorf("intake: %w", err)` (`500`, ничего не записано).

- [ ] **Step 1: Тесты**

Перенести 16 тестов `ruleselect_test.go` с прежними именами и проверками (`TestIntake_IncidentPerScenarioOfMatchedRules` … `TestOrderRules`; `TestConditionMatches`, `TestConditionRank`, `TestRuleRank*`, `TestRuleBeats_Strict` — через `m.Definition`) и из `pin_test.go` — `TestMachineIntakeShape`, `TestUniqueKeyFromMachine_Errors`. Новые:

```go
func TestMachineIntakeSectionPinned(t *testing.T) // sha256 json.Marshal(раздел intake без uniqueKey, с $comment) == intakeSectionSHA256 (посчитать в этой задаче);
                                                  // сообщение: "machine intake section changed: check Intake against intake.$comment and update this hash"
func TestIntake_CreatedAtIsMillis(t *testing.T)   // два правила одного ранга и приоритета, createdAt 1790845200000 и 1790845200001 ⇒ победитель — первое
func TestIntake_EvalErrorIsError(t *testing.T)    // копия: ruleMatches.expr = "r.conditions[5].eventType == []" ⇒ Intake возвращает ошибку, Picks nil
```

- [ ] **Step 2: Тесты падают**

Run: `go test ./internal/im/machine/ -run 'Intake|RuleFor|Condition|RuleRank|RuleBeats|OrderRules|UniqueKey|ApplyUnique' 2>&1 | tail -3`
Expected: FAIL — `Intake` не объявлен.

- [ ] **Step 3: Реализация и переключение сервиса**

- [ ] **Step 4: Тесты этапа 3 — без правок и зелёные**

Run: `git diff --exit-code 3282d96 -- internal/im/service/intake/service_test.go internal/im/handler/test/ && go test -race ./internal/im/machine/ ./internal/im/service/intake/ && make test-local 2>&1 | tail -10 && grep -rn 'ruleselect\.' --include=*.go internal | grep -v '^internal/im/ruleselect/' && golangci-lint run ./...`
Expected: `git diff` пуст; PASS всех пакетов, тесты с базой (`TestEvent*`, `TestProcess_*`, `TestTreeWorld*`) — тоже; `ruleselect.` — только в `service_test.go:350`; lint — 0.

- [ ] **Step 5: Commit**

Сообщение: «Этап 4а: выбор правил при приёме события — определения машины на исполнителе вместо зеркала ruleselect; тесты этапа 3 без правок».
Run: `git add -A internal/im && git commit -q -F .git/COMMIT_MSG_STAGE4A`

---

### Task 10: ADR, документы, последний прогон

**Files:**
- Create: `docs/adr/004-machine-executor.md` (сервер, по-английски, по образцу ADR-003)
- Modify (IM): `research/integration/40-plan.md` («Что уже готово» — строка «Исполнитель CEL и векторы (этап 4а)» со ссылкой на этот план; в разделе этапа 4 — что 4а сделан, 4б и 4в впереди), `research/integration/52-plan-stage4a.md` (отметки, «Итог этапа 4а» — таблица задач и коммитов)

**Interfaces:**
- Consumes: всё из задач 1–9.

- [ ] **Step 1: ADR-004** — пакет `machine` и почему так: мир через макросы и `__w` (поздних функций в cel-go v0.26.1 нет), типы из машины, `ref` над списком в 4а и SQL в 4б, эффекты как `ops()` Quint, числа и ошибки, векторы и лента, `ruleselect` → исполнитель и переходник до 4б, что дальше (4б: переходы в транзакции, векторы переходов; 4в: API).

- [ ] **Step 2: Документы IM** — перед правкой `git -C /mnt/hgfs/VmWareShared/soul2home/IM fetch`; новое — сказать пользователю.
Run: `cd /mnt/hgfs/VmWareShared/soul2home/IM && python3 tools/check_links.py && node tools/cel_vectors.mjs --check`
Expected: ссылки целы; векторы — 0 расхождений.

- [ ] **Step 3: Последний прогон сервера**

Run: `cd ~/Work/incident-manager-server && source ~/go/offline-env.sh && go test -race ./internal/im/machine/ && make test-local 2>&1 | tail -15 && go vet ./... && golangci-lint run ./...`
Expected: всё PASS; `go vet` чисто; lint — 0.

- [ ] **Step 4: Commit (два репозитория)**

Сервер — «Этап 4а: ADR об исполнителе машины». Run: `git add docs/adr/004-machine-executor.md && git commit -q -F .git/COMMIT_MSG_STAGE4A`
IM — «Этап 4а встраивания: исполнитель CEL на Go и векторы — план отмечен». Run: `cd /mnt/hgfs/VmWareShared/soul2home/IM && git add research/integration/40-plan.md research/integration/52-plan-stage4a.md && git commit -q -F .superpowers/sdd/52-plan-stage4a/commit-msg.txt`

---

## Не в этом этапе

| Что | Когда |
|---|---|
| Столбцы инцидента под машину: владелец, адресат, причина удержания, уровень эскалации, число передач, результат и причина закрытия, нарушения, три таймера, связи, курсор сценария; `kind` у журнала | 4б |
| Переход в транзакции: доступность → форма → окно после дедлайна → эффекты → журнал → версия; всё или ничего в PostgreSQL; несколько шагов одной транзакцией (объединение, «Взять» основного) | 4б |
| Факты над инцидентами — запросами SQL с черновиком транзакции поверх | 4б |
| Эффекты перехода `create` при приёме события (`startTimer reaction`) | 4б (запуск таймера), срок — 6 |
| Векторы переходов (`kind: transition`) | 4б |
| Операторский API: карточка, действия с `fieldOptions`/`fieldRules`, переходы, `transfer-targets`, причины, список; 404 раньше `If-Match`; идемпотентность | 4в |
| Состояние оператора, тестовые операторы, `/test/reset`, `/test/clock`, скрипт стенда «взять, отложить, передать, закрыть» | 4в (минимум из этапов 5–7) |
| Планировщик переходов по таймеру | 6 (для `/test/clock` — минимум в 4в) |
| Поток событий, сессии, очередь | 5 |
| `stepsFilled`, курсор и перенос ответов сценария | 6 |
| Вход и токены | отложено |

## Решения этого плана — обоснования (на подтверждение)

1. **Векторы переходов — в 4б.** Вектор перехода сравнивает итог ядра: доступность, проверку формы, окно после дедлайна, все эффекты перехода на общем черновике, журнал с подстановками сервера, внешние действия после фиксации, групповые операции и объединение. Это и есть содержание 4б, там же — запись в базу. В 4а сравнивать их не с чем, а формат, придуманный до 4б, скорее всего придётся переделать. Векторы эффектов уже ловят смысл каждой операции и видимость записей внутри эффекта: каждый начинается с черновика, каким его оставили предыдущие эффекты.
2. **`ruleselect` заменяется сейчас.** Зеркало определений на Go — второй источник смысла: правка машины ловится только замком-хэшем, и править приходится руками. Исполнитель вычисляет те же определения из машины, а тесты этапа 3 (сервис и тесты с базой — без правок) доказывают, что поведение не изменилось. Риск ранней замены — ошибка вычисления там, где раньше было «не подошло», — закрыт решением в3: это `500`, событие не записано, агент повторит. Оставить до 4б — значит в 4б менять и приём события, и переходы разом. Переходник `ruleselect.UniqueKeyFromMachine` нужен только чтобы файл тестов этапа 3 не менялся ни на байт.
3. **Мир через макросы, типы из машины, `ref` над списком** — решения 2–4 в начале плана; проверено пробой cel-go v0.26.1 в scratchpad 2026-10-29. Мир-аргумент вместо глобального — потому что запросы сервера параллельны, а глобальный мир прототипа нереентерабелен (`call` сохраняет и восстанавливает его вручную).
4. **Хэш — байтов машины целиком.** Любая правка машины, даже `$comment`, требует `--update` (~3 мин) — как сборка `build_workflow.py`. Зато Go проверяет то же одним `sha256` копии, без канонического JSON на двух языках.
5. **Дробное и строка на входе `int` — ошибка Go,** хотя прототип их принимает: данные сервера типизированы, а молча отброшенная дробная часть — та самая ошибка «int против double». В векторах таких входов нет.

## Открытые вопросы

1. Тип события в условии правила — по `uid` (как сейчас в машине и на сервере) или по паре «тип устройства + `uid`» (вопрос от 2026-10-29). План следует машине; ответ «по паре» меняет `conditionMatches` в машине (IM), векторы пересобираются, сервер подхватывает из копии.
2. Переходник `ruleselect.UniqueKeyFromMachine` до 4б (решение 9) — или поправить одну строку импорта в `service_test.go` и убрать пакет сейчас?
3. Хэш по байтам машины (каждая правка машины — `--update`) — или по машине без `$`-ключей (правка комментария векторы не будит, но Go и JS должны одинаково строить канонический JSON)?
4. Отбор записи: 30 векторов на имя, 5 на ответ, файл до 8 МБ — достаточно? Больше — дольше `--check` и шумнее история.
