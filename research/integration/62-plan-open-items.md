# Открытое после этапа 9: уборка стенда, звук, люди в базе, объём, проверки стенда — план работ

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Закрыть открытое после этапа 9 по решениям пользователя от 2026-11-03: убрать следы со стенда и пароль из скриптов, привести правила к «звука нет», перенести людей в `operator_sessions`, чтобы `GET /operator/transfer-targets` отдавал настоящих адресатов, замерить чтение на 800 000 инцидентов и проверить на стенде шаг Image и `skipped` объединения.

**Architecture:** Пять блоков. A (Task 1–3) — мелочи стенда и IM. B (Task 4) — пункт RULE-141 по порядку `reviews/README.md`: только правила и журнал, машина и прототип звука не знают. C (Task 5–8) — Task 8–10 плана 57, переложенные на сервер после этапов 6–7, затем миграция на `imdb` и передача между двумя операторами. D (Task 9–10) — замер на тестовой базе и исправление. E (Task 11) — два прохода в `check-operator-server.mjs`. Task 10 — исправление медленного чтения. Итог — Task 12.

**Tech Stack:** Go 1.27.1, gin, `mgutz/dat`, PostgreSQL 9.6, testify `require`; bash и `jq` скриптов стенда; `puppeteer-core` из `~/Work/stand/ui-check`; Python 3 инструментов IM.

**Spec:** решения пользователя 2026-11-03 (этот план, раздел «Решения»); [57-plan-stage5b.md](57-plan-stage5b.md), «Отложено до публичного запуска», решения 97, 99–102, Task 8–10; [59-plan-stage9.md](59-plan-stage9.md), решение 165, вопросы 5 и 9, «Итог»; [60-plan-stage6.md](60-plan-stage6.md), решение 193; ADR-005 («Carried to stages 6-7 and the public launch»), ADR-006 (пункты 9, 12), ADR-007 (строка 54) сервера; `.superpowers/sdd/59-plan-stage9/task-25-report.md`, `task-26-report.md`; [30-local-stand.md](30-local-stand.md), «Откат».

---

## Размер и разбиение

12 задач.

| Задачи | Блок | После них |
|---|---|---|
| Task 1 | A: INC-0100 закрыт | на `imdb` нет висящего `pending_acceptance` от проверок |
| Task 2 | A: `user-prompts.md` вне `check_links.py` | `check_links.py` — 0 нерабочих |
| Task 3 | A: пароль `test@` из файла | в скриптах стенда пароля нет |
| Task 4 | B: RULE-141, звук | правила, журнал и руководство говорят одно |
| Task 5–7 | C: метка прав, адресаты из таблицы, срок жизни | `transfer-targets` видит людей, которых процесс не видел |
| Task 8 | C: миграция 040 на `imdb`, передача двумя операторами | передача проверена на стенде |
| Task 9 | D: замер на 800 000 | цифры против предела 30 с |
| Task 10 | D: медленный `GET` (≥ 10 с) исправлен | все `GET` на 800 000 < 10 с |
| Task 11 | E: шаг Image, `skipped` объединения | вопрос 5 плана 59 и `skipped` проверены |
| Task 12 | ADR, итог | блоки закрыты |

Task 1–4, 9 и 11 не зависят от C и друг от друга. Task 8 — после Task 7, Task 10 — после Task 9 и Task 5 (номер миграции). Task 11 запускается после Task 3 (скрипт входит по файлу пароля). Запись в `imdb` — только под замком стенда (Global Constraints).

## Global Constraints

- **Ветки.** IM — `feature/im_operator` в `/mnt/hgfs/VmWareShared/soul2home/IM`; сервер — `feature/im_operator` в `~/Work/incident-manager-server` от `cfb0a81`. Перед работой — `git fetch` в обоих; есть новое — остановиться и предложить подтянуть. Рабочих деревьев нет: этапы 6–9 закрыты. Исключение — Task 4: IM-ветка `main` (ответ на вопрос 4), затем `git cherry-pick` двух её коммитов в `feature/im_operator`.
- Только локально, `git push` никогда. Сообщение коммита — на русском, начинается с `После этапа 9: ` (у Task 4 — с `RULE-141: `), файл `$(git rev-parse --git-dir)/COMMIT_MSG_62`, `git commit -q -F`, последняя строка `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- **Замок стенда** — как в планах 60–61: взять `mkdir ~/Work/stand/lock-server && printf 'plan62 Task N %s\n' "$(date -Is)" > ~/Work/stand/lock-server/owner`; отдать `rm -f ~/Work/stand/lock-server/owner && rmdir ~/Work/stand/lock-server`. Замок покрывает порт 5000, `bin/im`, `run-im-binary.sh` и любую запись в `imdb`. Ждать — через `Monitor`, не `sleep`; `owner` старше 2 ч — спросить пользователя.
- **Дамп перед записью в `imdb`:** `sg docker -c "docker exec \$(docker ps -qf name=ac_db) pg_dump -U im imdb" > ~/Work/stand/backup/imdb-before-p62tN.sql && test -s ~/Work/stand/backup/imdb-before-p62tN.sql` (`N` — номер задачи; второй прогон — суффикс `b`). Без дампа записи нет.
- Строки 28–29 `30-local-stand.md` не читать и не печатать. Файлы `*.pass`, `.env`, `telegram.env` не читать и не печатать: только `test -f` и `stat -c %a`. Пароль не писать ни в план, ни в журнал, ни в отчёт.
- Состояние инцидента на стенде — только по API (`GET /operator/incidents/{guid}`), не по базе. Новые инциденты — только от `agent-emulator`. Чужие инциденты (не созданные задачей) не трогать, кроме INC-0100 в Task 1.
- Команды Go начинаются с `source ~/go/offline-env.sh &&`. Новых зависимостей нет, `go.mod` не меняется.
- **С базой:** `source ~/go/offline-env.sh && IM_TEST_DB_URL='postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable' go test -race ./internal/im/handler/test/ -run '<шаблон>'`. Контейнер `im-test-db` поднимает `~/Work/stand/ensure-test-dbs.sh`. Без базы: `go test -race $(go list ./internal/im/... | grep -v /handler/test)`.
- **Замеры:** та же команда без `-race` и с `IM_MEASURE=1`. Замер объёма (Task 9) — только база `im_volume` в `im-test-db`, никогда `imdb`.
- **Миграции:** последняя — 032. Отложенные задачи плана 57 берут номера от 040 (решение 193 плана 60, коммит IM `f666384`): миграция Task 5 — `040_operator_identity.sql`; номер 041 остаётся за Task 21 плана 57; индекс Task 10 — `042_…`. Номер ниже применённого роняет `NewStore`, пропуск — нет.
- `golangci-lint run ./...` и `golangci-lint run --build-tags imtest ./...` — 0 замечаний, `gofmt -l internal/im` пусто. `make gen` не запускать: контракт не меняется.
- Комментарии кода и ADR — английский. Документы IM и коммиты — русский, простыми словами.
- В IM — правила `CLAUDE.md`: собранные файлы руками не править, `openapi.json` и `Workflow_machine/README.md` в CRLF, `State_rules/archive/` не править.
- Скрипты стенда вне git: перед правкой — копия `*.before-62`.
- Полные мутации кода (`check_code_mutations.py`) не запускаются, их гоняет CI.
- Правки — Edit и Write, без `sed -i` и здесь-документов. Временные файлы — в scratchpad.

**Решения пользователя (обязательны, не пересматривать):** звука нет нигде (решение 165 плана 59 распространяется на правила); Task 8–10 плана 57 делаются сейчас, Task 20–25 — по-прежнему до публичного запуска; замер — на тестовой базе; INC-0100 закрывается через API оператора; пароль `test@` — в `~/Work/stand/test-operator.pass` (права 600, создаёт пользователь, файл уже есть).

## Review Focus

1. **Срок жизни прячет человека не только из адресатов.** Строка старше 30 дней не должна исчезать из `Person`, журнала, состава группы для доставки уведомления и кандидатов планировщика (ADR-006, пункт 9: нет строки — `offline`, а старая строка не «нет строки»). Тесты `TestPersonPastKeepFor` (Task 6) и `TestSchedulerSeesPersonPastKeepFor` (Task 7).
2. **Адресат другого клиента или человек без права.** Чтение таблицы по `customer_guid` и `offersTransferTo` машины — список `transfer-targets` не шире формы. Тесты `TestPeopleOtherCustomer`, `TestTransferTargetsFromTableMatchForm` (Task 6).
3. **Поздний запрос со старыми правами.** Любой путь записи строки — запрос, поток, системные переходы планировщика — не опускает `identity_ms`. Тесты `TestLateRequestDoesNotWriteBack`, `TestSchedulerMoveKeepsNewRights` (Task 5), `TestStreamRefreshesRowOnReauth` (Task 7).
4. **Скрипт стенда без файла пароля «зелёный».** Нет файла или права не 600 — `SKIP` с причиной и код выхода не 0 у проверок, которым вход обязателен; не пустой токен и не `FAIL` без причины. Проверка — Task 3, Step 3.
5. **Уборка стенда не сработала при сбое.** Инциденты Task 8 и Task 11 закрываются в `finally` при любом исходе и сверяются по API. Проверка — ранний выход в Task 8, Step 5 и Task 11, Step 4.

## Что входит: разбор источников

| Источник | Что сейчас | Что делает план |
|---|---|---|
| `30-local-stand.md:387`, `60-plan-stage6.md:826` | INC-0100 (`01a1a123-…`) в `pending_acceptance`, адресат `user@gmail.com`, уровень 1 | Task 1 |
| `python3 tools/check_links.py` | 4 нерабочих, все — `user-prompts.md` (локальный, в `.git/info/exclude`) | Task 2. Тестов у инструмента нет — проверка прогоном |
| скрипты стенда | пароль `test@` открытым текстом в 11 `*.sh`: `check-operator-api`, `-scheduler`, `-scenario`, `-filter`, `-stream`, `-transitions`, `snapshot-operator-queue`, `load-demo`, `im-machine-patch`, `grant-im-permissions`, `ensure-dev-login` (дважды); в `ui-check/*.mjs` — нет (вход через `dev-login.html`); в `dev-login.html` — да | Task 3; `dev-login.html` — вопрос 1 |
| `States rules IM.md:452` (§8.1) и `:875` (§17, «Отступления») | «всплывающее уведомление со звуком»; отступление «показывается без звука» | Task 4 |
| машина, контракт, `prototype/*.js`, `strings/` | звука нет (`grep -i 'sound\|звук'` — только названия детектора в наборе) | не меняются |
| `Operator guide.md` | «со звуком» убрано в Task 27 плана 59 | Task 4 только проверяет |
| `appservice/operator/session.go:511` | `SharedDirectory.People` — память процесса (решение 75) | Task 6 |
| `People(customer)` зовут: `world.go:279` (адресаты), `dutygroups.go:164` (состав групп), `handler/operator/admin.go:61`, `access.go:167,203` (память доступа), `feed.go:322` (кому доставить), `session.go:576,661` (снимок), `stand/server.go:178`, `stand/people.go:204` | Task 6, решение 214 |
| `MoveAddressed` | функции с этим именем нет; окно осталось в системных переходах сессии (`SessionMoves`, `session.go:162`) и у планировщика (`addressee_signed_out_*`, ADR-006, пункт 9) | Task 5 |
| `session_queries.go:104-111` | запись при `IS DISTINCT FROM` трёх полей, метки нет | Task 5 |
| `session_queries.go:248` | `open_incident_guid` пишется как прислан | Task 7 |
| ADR-005:208 | на 800 000 `filter=all` 8–9 с на страницу, `QueueClasses` 1,4–2,4 с | Task 9 повторяет на коде после этапов 6–7, Task 10 исправляет ≥ 10 с |
| `task-26-report.md:42-43` | `skipped` не проверен, шага Image в наборе нет | Task 11 |

## Структура файлов

| Файл | Отвечает за |
|---|---|
| `IM/tools/check_links.py` | `SKIP_FILES` + `user-prompts.md` |
| `~/Work/stand/test-operator.sh` (новый) | `operator_login` — вход `test@` по файлу, итог в `$TOKEN` или `$OPERATOR_WHY` |
| `IM/reviews/2026-11-03/plan.md` (новый), `IM/reviews/README.md` | пункт RULE-141 и строка цикла |
| `IM/Specification/State_rules/States rules IM.md`, `CHANGELOG.md` | §8.1, §17 |
| `service/storing/migrations/040_operator_identity.sql` | `identity_ms`, `seen_ms` |
| `service/storing/session_queries.go` | запись с меткой, `OperatorPeople`, `open_incident_guid` |
| `appservice/operator/session.go`, `directory.go` | `Directory.People` из таблицы, `Seen`, срок жизни |
| `handler/test/operator_people_test.go` (новый) | тесты Task 6–7 |
| `handler/test/migration_040_test.go` (новый) | `TestMigration040` |
| `handler/test/operator_volume_test.go` (новый) | замер Task 9 |
| `~/Work/stand/check-operator-transfer.sh` (новый) | передача двумя операторами |
| `~/Work/stand/ui-check/check-operator-server.mjs` | части `image` и `merge-skipped` |

---

### Task 1: INC-0100 закрыт

Пишет Sonnet. Ревью: Sonnet, коротко.

**Files:** нет (стенд); строка в `30-local-stand.md`, «Следы на стенде».

- [ ] **Step 1:** взять замок, снять дамп `imdb-before-p62t1.sql` (Global Constraints), `test -s` — успех.
- [ ] **Step 2:** токен `test@` — через `operator_login` из Task 3, если Task 3 уже сделан, иначе тем же входом, что `check-operator-api.sh`. `GET /operator/incidents/01a1a123-…` (полный guid — из `GET /operator/incidents?filter=all` по номеру `INC-0100`). Ожидается `200`, `state` = `pending_acceptance`. Другое состояние — записать и остановиться.
- [ ] **Step 3:** действие закрытия из `actions[]` карточки (`close_unprocessed` или то, что карточка даёт для `pending_acceptance`; если закрытия нет — сначала то, что машина разрешает: `reclaim`/`accept`, по карточке). `POST /operator/incidents/{guid}/actions/{id}` с `If-Match` из `ETag` карточки. Ожидается `200`.
- [ ] **Step 4:** `GET` карточки — `state` = `closed`. Отдать замок.
- [ ] **Step 5:** в `30-local-stand.md` строка про INC-0100 — «закрыт через API оператора 2026-11-03, дамп `imdb-before-p62t1.sql`». `python3 tools/check_links.py` после Task 2 — 0. Коммит IM `После этапа 9: INC-0100 закрыт на стенде`.

### Task 2: `user-prompts.md` вне `check_links.py`

Пишет Sonnet. Ревью: Sonnet, коротко.

**Files:** Modify `tools/check_links.py:30-36` (`SKIP_FILES`).

- [ ] **Step 1:** `python3 tools/check_links.py` — сейчас «Нерабочих ссылок: 4», все строки `user-prompts.md:`.
- [ ] **Step 2:** добавить `"user-prompts.md"` в `SKIP_FILES` с комментарием «локальный журнал промптов, в git не идёт (`.git/info/exclude`)». Тестов у инструмента нет, отдельный тест не заводим.
- [ ] **Step 3:** `python3 tools/check_links.py` — «Нерабочих ссылок: 0», код 0. Затем временный `tmp-link-check.md` в корне репозитория с `[x](нет.md)`: прогон — 1 нерабочая; файл удалить. Так видно, что пропущен только `user-prompts.md`.
- [ ] **Step 4:** коммит IM `После этапа 9: check_links.py не смотрит локальный user-prompts.md`.

### Task 3: пароль `test@` из файла

Пишет Sonnet. Ревью: Sonnet, коротко; ревьюер проверяет `grep`-ом Step 4, пароль не печатая.

**Files:**
- Create: `~/Work/stand/test-operator.sh`
- Modify: 11 скриптов из разбора (копии `*.before-62`)

**Interfaces:**
- Produces: `source ~/Work/stand/test-operator.sh; operator_login` → `$TOKEN` (токен облака) или пустой `$TOKEN` и `$OPERATOR_WHY` (причина). Переменные `TEST_EMAIL` (по умолчанию `test@axxonnet.test`), `TEST_PASS_FILE` (по умолчанию `~/Work/stand/test-operator.pass`). Пароль — только через `jq --rawfile`, как `second_login` в `second-operator.sh:50-58`; в переменную окружения и в командную строку `curl` не попадает.

- [ ] **Step 1:** `test-operator.sh` по образцу `second_login`: нет файла — `OPERATOR_WHY="нет файла …"`; права не `600` — `OPERATOR_WHY="права файла … — NNN, нужны 600"`; вход не дал токен — `OPERATOR_WHY="вход test@… не дал токен (код …)"`.
- [ ] **Step 2:** в каждом из 11 скриптов строку `EMAIL=…; PASS=…` и свой вход заменить на `source` + `operator_login`. Без токена: проверки (`check-*`, `snapshot-*`) пишут `SKIP вход: $OPERATOR_WHY` и выходят с кодом 2; служебные (`load-demo`, `im-machine-patch`, `grant-im-permissions`) — `echo "$OPERATOR_WHY" >&2; exit 1`. `ensure-dev-login.sh` создаёт пользователя: пароль берёт из того же файла через `--rawfile`, комментарий строки 2 — без пароля.
- [ ] **Step 3: проверка отсутствия файла.** `TEST_PASS_FILE=/nonexistent ~/Work/stand/check-operator-api.sh; echo $?` — строка `SKIP вход: нет файла /nonexistent`, код 2. `TEST_PASS_FILE` на временный файл с правами 644 в scratchpad (содержимое — `x`) — `SKIP … нужны 600`.
- [ ] **Step 4:** `grep -c 'Test12345' ~/Work/stand/*.sh | grep -v ':0$'` — пусто (`*.before-*` не в счёт). `grep -l "PASS='" ~/Work/stand/*.sh` — пусто.
- [ ] **Step 5:** под замком `~/Work/stand/check-operator-api.sh` с настоящим файлом — тот же итог `OK/FAIL/SKIP`, что до правки (записать оба). Коммита нет (стенд вне git); строка в журнале плана.

### Task 4: RULE-141 — звука нет

Пишет Sonnet. Ревью: Sonnet, коротко.

**Files:**
- Create: `reviews/2026-11-03/plan.md`
- Modify: `reviews/README.md` (строка цикла), `Specification/State_rules/States rules IM.md:452` (§8.1), `:875` (§17, «Отступления»), `Specification/State_rules/CHANGELOG.md` («Изменения после v10»)

- [ ] **Step 0: ветка `main`.** `git fetch`; есть новое на GitHub — остановиться и предложить подтянуть (`CLAUDE.md`). `git stash` не нужен: рабочее дерево чистое; `git switch main`.
- [ ] **Step 1: пункт плана.** `reviews/2026-11-03/plan.md` по образцу `reviews/2026-10-28/plan.md`: пункт `RULE-141` — «§8.1: уведомление адресату — без звука», таблица решений с заполненными «Решение» (`звука нет нигде — решение пользователя 2026-11-03, решение 165 плана 59`) и «Кто, дата» (`пользователь, 2026-11-03`). Строка в `reviews/README.md`: дата `2026-11-03`, коммит — текущий `HEAD`, ревью `—`.
- [ ] **Step 2: правила.** §8.1, «Уведомление адресату»: «всплывающее уведомление со звуком» → «всплывающее уведомление без звука». §17: строку отступления «§8.1: уведомление адресату со звуком» убрать, если в ней ничего не остаётся; хвост «уведомлений группе нет — в прототипе один оператор» оставить отдельной строкой «§8.1: уведомление группе всем участникам на месте».
- [ ] **Step 3: журнал.** Строка в `CHANGELOG.md`: «§8.1: уведомление адресату — без звука; отступление §17 о звуке снято. Руководство оператора, раздел 5 (уже без звука)» | `RULE-141, решение 2026-11-03` | коммит Step 5.
- [ ] **Step 4: проверки.** `grep -ci 'со звуком' "Specification/State_rules/States rules IM.md" "Specification/Operator guide.md"` — `0` и `0`. Машина и прототип не меняются, поэтому шага самопроверки нет: поведение прототипа то же (он и так без звука). Быстрые проверки `CLAUDE.md` — все зелёные: `python3 tools/build_workflow.py --check`, `python3 tools/check_machine.py`, `python3 tools/check_machine.py --mutations`, `python3 -m unittest tools/test_openapi30.py`, `node tools/check_cel.mjs`, `node tools/test_cel.mjs`, `node tools/cel_vectors.mjs --check`, `node tools/gen_quint.mjs --check`, `python3 tools/check_links.py`; плюс `python3 tools/check_guide.py` (читает правила и руководство).
- [ ] **Step 5: два коммита** по `CLAUDE.md`: `RULE-141: уведомление адресату без звука` (правила, журнал, план, README), затем `[x]` с хэшем в `reviews/2026-11-03/plan.md` — `Хэш <коммит> в плане ревью 2026-11-03`. Хэш первого вписать и в колонку «Коммит» журнала вторым коммитом. Оба — локально на `main`, без push.
- [ ] **Step 6: в ветку интеграции.** `git switch feature/im_operator && git cherry-pick -x <первый> <второй>` (cherry-pick, а не merge: слияние `main` притянуло бы всё, что разошлось). Конфликт в `CHANGELOG.md` или `reviews/README.md` — разрешить, сохранив обе строки. Быстрые проверки — снова зелёные. В журнал плана — хэши на обеих ветках.

### Task 5: метка прав в строке сессии (Task 8 плана 57)

Пишет Opus. Ревью: Opus с мутантами.

**Files:**
- Create: `service/storing/migrations/040_operator_identity.sql`, `handler/test/migration_040_test.go`
- Modify: `model/user.go`, `model/operator_session.go`, `internal/externalclient/cloud/client.go:50` (`authUser`), `service/storing/session_queries.go:102-126`, `appservice/operator/session.go` (`comeBack`, `SessionMoves`), `handler/test/fake_cloud_client.go`
- Test: `handler/test/operator_session_test.go`

**Interfaces:**
- Produces: `model.User.CheckedAtMs int64`; `model.OperatorSession.IdentityMs int64`, `SeenMs int64`; столбцы `identity_ms BIGINT NOT NULL DEFAULT 0`, `seen_ms BIGINT NOT NULL DEFAULT 0` (заполнен из `last_activity_ms`); `const rememberEvery = 10 * time.Minute` в `appservice/operator`, параметром в `rememberOperatorSQL`.

Шаблон: `TestSchedulerMoveKeepsNewRights|TestSessionMovesKeepNewRights|TestLateRequestDoesNotWriteBack|TestRowNeverGoesBack|TestNewRowHasBothStamps|TestMigration040`.

- [ ] **Step 1: пробы на текущем коде** (решение 213). `TestSessionMovesKeepNewRights`: после чтения строк в `SessionMoves` другой запрос пишет новые права (`[assign.own]` вместо `[take.own, assign.own]`); после ходов в строке новые. `TestSchedulerMoveKeepsNewRights`: то же окно у тика планировщика с `addressee_signed_out_*`. Запуск: ожидается FAIL; PASS — записать «не воспроизводится», тест оставить защитой.
- [ ] **Step 2: падающие тесты решения 97 плана 57.**
  - `TestLateRequestDoesNotWriteBack`: запрос A взял пользователя с меткой 100, B записал новые права с меткой 200, A строит мир — в строке новые.
  - `TestRowNeverGoesBack`: `RememberOperator` с меткой 100 поверх 200 строку не меняет; равная метка и новое имя — меняет; без различий и `seen_ms` старше `rememberEvery` — двигает только `seen_ms`.
  - `TestNewRowHasBothStamps`: первая запись — `identity_ms` и `seen_ms` не 0.
  - `TestMigration040`: столбцы есть, `seen_ms` = `last_activity_ms` у старых строк, `Down` работает, по образцу `migration_018_test.go`; триггер `operator_actions` (миграция 026, строка 63) на `UPDATE` строки сессии по-прежнему пишет `link_restored` только при смене `link_lost_ms`.
- [ ] **Step 3:** прогон шаблона — FAIL.
- [ ] **Step 4: реализовать по решению 97 плана 57.** Условие записи: `operator_sessions.identity_ms <= EXCLUDED.identity_ms AND (поля различаются OR operator_sessions.seen_ms + $n <= EXCLUDED.seen_ms)`, `seen_ms = GREATEST(…)`. Метка ставится в `authUser` при настоящем ответе облака; память токена её не молодит. `fake_cloud_client` — растущий счётчик, если тест его задал, иначе 0.
- [ ] **Step 5:** шаблон, затем `-run 'TestStream|TestSession|TestFlow|TestScheduler'` — PASS. Коммит `После этапа 9: метка проверки прав в строке сессии — старые права не затирают новые`.

### Task 6: адресаты из таблицы (Task 9 плана 57)

Пишет Opus. Ревью: Opus с мутантами (видимость, чужой клиент, точный счёт запросов).

**Files:**
- Create: `handler/test/operator_people_test.go`
- Modify: `appservice/operator/directory.go:21-40`, `session.go:505-665`, `world.go:272-282`, `dutygroups.go:164`, `handler/operator/admin.go:61`, `service/storing/session_queries.go`, `stand/server.go:178`, `stand/people.go:204`
- Test: `handler/test/operator_people_test.go`, `operator_cost_test.go` (точные счёты), `operator_session_test.go` (ограничение решения 75)

**Interfaces:**
- Consumes: `seen_ms` (Task 5).
- Produces: `Directory.People(ctx model.AppContext, customer uuid.UUID, asked []int64) ([]*model.OperatorSession, error)`; `Directory.Seen(customer uuid.UUID) []*model.User` — прежняя память процесса; `Store.OperatorPeople(ctx model.AppContext, customer uuid.UUID, since int64, asked []int64) ([]*model.OperatorSession, error)` — один запрос `seen_ms >= $since OR user_id = ANY($asked)`, `ORDER BY user_id`; `const personKeepFor = 30 * 24 * time.Hour`.

Шаблон: `TestSecondServerOffersPerson|TestPeopleOtherCustomer|TestPersonPastKeepFor|TestOldRowNotRewrittenEveryRequest|TestPeopleReadFailsTheRequest|TestBrokenRowNotInPeople|TestTransferTargetsFromTableMatchForm|TestDutyGroupMemberNotSeenIsCounted|TestListLinkedSQLCount|TestCardSQLCount|TestFormTransfer`.

- [ ] **Step 1: падающие тесты.**
  - `TestSecondServerOffersPerson`: человек записан в таблицу напрямую, процесс его не видел — он в `GET /operator/transfer-targets` и среди вариантов формы.
  - `TestPeopleOtherCustomer`: человека другого клиента нет.
  - `TestPersonPastKeepFor`: `seen_ms` старше 30 дней — в адресатах нет; `Person` находит; имя в журнале есть.
  - `TestOldRowNotRewrittenEveryRequest`: строка за `personKeepFor`, человек спрошен в мире, два запроса — лишней записи нет (`sqlCounter`).
  - `TestPeopleReadFailsTheRequest`: `OperatorPeople` падает — ответ `500`, не пустой список.
  - `TestBrokenRowNotInPeople`: битая строка (права не список) — нет ни в `transfer-targets` без инцидента, ни в форме.
  - `TestTransferTargetsFromTableMatchForm`: для видимого инцидента `transfer-targets` = варианты поля `targetId` формы «Передать», человек без `incident:accept` или без доступа к устройству — нет в обоих.
  - `TestDutyGroupMemberNotSeenIsCounted`: участник дежурной группы из таблицы, процесс его не видел, `agentState` `ready` — группа «на месте» (снимает ограничение ADR-007, строка 54).
- [ ] **Step 2:** прогон — FAIL.
- [ ] **Step 3: реализовать по решениям 99 плана 57 и 214.** Таблицу читают адресаты (`world.go`), состав дежурных групп (`dutygroups.go`) и `admin.go`. Память доступа (`access.go`) и доставка (`feed.go`) остаются на `Seen`. Снимок делает один запрос вместо двух, `comeBack` — после него. Ошибку чтения снимок держит и отдаёт на ближайшем чтении мира. Стенд (`stand/people.go`) отвечает из своего набора.
- [ ] **Step 4:** шаблон — PASS, точные счёты `TestListLinkedSQLCount` и `TestCardSQLCount` прежние (или на один меньше — записать). `-run 'TestTargets|TestForm|TestSession|TestQueue|TestFlow|TestDutyGroup|TestStand'`, с тегом `imtest` — PASS.
- [ ] **Step 5:** коммит `После этапа 9: адресаты передачи и состав групп из operator_sessions, строки старше 30 дней не предлагаются`.

### Task 7: срок жизни, слушатель потока, `open_incident_guid` (Task 10 плана 57)

Пишет Opus. Ревью: Opus с мутантами.

**Files:**
- Modify: `appservice/operator/session.go:472` (`unchanged`), `handler/operator/stream.go:173` (цикл `reauth`), `handler/operator/session.go:282` (`SessionHeartbeat`), `service/storing/session_queries.go:248`
- Test: `handler/test/operator_people_test.go`, `operator_stream_test.go`, `operator_scheduler_test.go`

**Interfaces:**
- Consumes: `Directory.Remember`, `rememberEvery` (Task 5), `personKeepFor` (Task 6).

Шаблон: `TestRememberRefreshesSeen|TestRememberWritesRarely|TestStreamRefreshesRowOnReauth|TestStreamOnlyListenerStaysInPeople|TestHeartbeatKeepsOnlyVisibleIncident|TestSchedulerSeesPersonPastKeepFor`.

- [ ] **Step 1: падающие тесты.**
  - `TestRememberRefreshesSeen`: права те же, часы +11 мин — `seen_ms` обновлён.
  - `TestRememberWritesRarely`: 100 `GET` за минуту — одна запись (`sqlCounter`).
  - `TestStreamRefreshesRowOnReauth`: права в облаке сменились, поток открыт, прошёл `Reauth` — в строке новые права, запросов от человека не было.
  - `TestStreamOnlyListenerStaysInPeople`: человек только слушает поток 31 день (`TestClock`) — в адресатах; поток закрыт, ещё 31 день — нет.
  - `TestHeartbeatKeepsOnlyVisibleIncident`: виден — guid в строке; не виден, другой клиент, нет такого — `NULL`; всегда `204`.
  - `TestSchedulerSeesPersonPastKeepFor`: владелец со строкой старше 30 дней в `ready` и без потока — тик планировщика даёт те же переходы молчания, что при свежей строке (ADR-006, пункт 9): срок жизни на планировщик не влияет.
- [ ] **Step 2:** прогон — FAIL.
- [ ] **Step 3: реализовать по решениям 100–102 плана 57.** `unchanged` смотрит и на время (`rememberEvery`). `Remember` в цикле `reauth` — раз в 60 с, сбой только в журнал, поток живёт. `SessionHeartbeat` проверяет guid через `VisibleAmong`, один запрос.
- [ ] **Step 4:** шаблон, `-run 'TestStream|TestSession|TestScheduler'` — PASS; равенства потока прежние. Линтеры — 0.
- [ ] **Step 5:** коммит `После этапа 9: срок жизни строки, поток обновляет её сам, в heartbeat только видимый инцидент`.

### Task 8: миграция 040 на `imdb`, передача двумя операторами

Пишет Opus. Ревью: Opus (процедура стенда, уборка).

**Files:**
- Create: `~/Work/stand/check-operator-transfer.sh`
- Modify: `30-local-stand.md` (раздел миграции 040 с откатом, образец — «Миграции 019–021»)

**Interfaces:**
- Consumes: `operator_login` (Task 3), `second_login` и `$SECOND`, `$SECOND_ID`, `$SECOND_WHY` (`second-operator.sh`), `~/Work/stand/second-operator.pass`.

- [ ] **Step 1: сборка и миграция.** `source ~/go/offline-env.sh && go build -o ~/Work/stand/bin/im.p62 ./cmd/im`. Замок, дамп `imdb-before-p62t8.sql`, `test -s`. Остановить сервер (по порту 5000), `cp bin/im bin/im.before-62`, `mv bin/im.p62 bin/im`, `~/Work/stand/run-im-binary.sh ~/Work/stand/bin/im`. В логе — применена `040`, ошибок `NewStore` нет. Откат в `30-local-stand.md`: остановить, `bin/im.before-62`, `psql … -c 'ALTER TABLE … DROP COLUMN …'` и строка миграции — или восстановление из дампа.
- [ ] **Step 2: скрипт.** `check-operator-transfer.sh`: вход обоих; один инцидент от `agent-emulator replay --limit 1`; первый берёт (`claim`), передаёт второму (`transfer`, `targetId` = `$SECOND_ID`); второй `accept`; каждое состояние — `GET` карточки (`pending_acceptance` с адресатом второго, затем `in_progress` с `owner` второго). `trap` на `EXIT` закрывает созданный инцидент без обработки и проверяет `closed` по API отдельной строкой. Нет файла второго — `SKIP` с `$SECOND_WHY`, код 2.
- [ ] **Step 3: главная проверка Task 6.** После перезапуска сервера второй оператор не входит; первый: `GET /operator/transfer-targets?incidentGuid=…` — `$SECOND_ID` есть. До Task 6 его не было (`check-operator-filter.sh:183`, решение 75): строку `SKIP` в `check-operator-filter.sh` заменить на `check`.
- [ ] **Step 4:** прогон — `OK N, FAIL 0, SKIP 0`, код 0. Повтор `check-operator-api.sh`, `check-operator-transitions.sh`, `check-operator-scheduler.sh` — итоги не хуже записанных в Task 3.
- [ ] **Step 5: ранний выход.** `IM_STAND_FAIL_AFTER=claim` (переменная скрипта) — скрипт выходит после `claim`, `trap` закрыл инцидент, строка `closed` — OK. Отдать замок.
- [ ] **Step 6:** коммит IM `После этапа 9: миграция 040 на стенде и передача двумя операторами`.

### Task 9: замер на 800 000 инцидентов

Пишет Opus. Ревью: Opus (способ замера и выводы).

**Files:**
- Create: `handler/test/operator_volume_test.go`
- Test: он же

**Interfaces:**
- Consumes: фикстура `newIntakeFixture`, `measure`, `requireMeasure` (`operator_cost_test.go:51-70`).
- Produces: `func TestReadAtVolume(t *testing.T)`; переменная `IM_VOLUME_ROWS` (по умолчанию 800000); `const readLimit = 30 * time.Second` — предел `GET` клиента (план 59, строки 1777, 2193).

- [ ] **Step 1: база.** `docker exec im-test-db psql -U postgres -c 'CREATE DATABASE im_volume'`. Тест отказывается (`t.Fatal`), если имя базы в `IM_TEST_DB_URL` не `im_volume` (решение 215).
- [ ] **Step 2: тест.** Наполнение одним `INSERT … SELECT generate_series` с журналом, таймерами и строками событий: 800 000 инцидентов, 5000 открытых, 1000 групп, 10 людей, 5 сценариев. Перед замером `VACUUM ANALYZE`. Замеры — худшее из 7 после разогрева: `GET /operator/incidents?filter=all&pageSize=100` (первая и последняя страница), `filter=done`, `filter=mine`, `GET /operator/incidents/summary` (счётчики), `GET /operator/reference/source-groups?withCounters=true`, карточка закрытого. Каждый — `require.Less(t, d, readLimit)`; бюджет решения 69 (300 мс) — в журнал теста, без падения.
- [ ] **Step 3:** `IM_MEASURE=1 IM_TEST_DB_URL='postgresql://postgres:postgres@127.0.0.1:55432/im_volume?sslmode=disable' go test ./internal/im/handler/test/ -run TestReadAtVolume -timeout 60m -v` (без `-race`). Ожидается PASS; таблица цифр в журнал плана.
- [ ] **Step 4:** каждый `GET` ≥ 10 с — `EXPLAIN (ANALYZE, BUFFERS)` его запросов в журнал; список таких `GET` — вход Task 10.
- [ ] **Step 5:** `DROP DATABASE im_volume`. Коммит сервера `После этапа 9: замер чтения на 800 000 инцидентов`.

### Task 10: медленное чтение на 800 000

Пишет Opus. Ревью: Opus с мутантами. Пропускается, если в Task 9 все `GET` < 10 с (записать в журнал).

**Files:**
- Create: `service/storing/migrations/042_volume_read.sql` (имя по найденному запросу), `handler/test/migration_042_test.go`
- Modify: запрос из Task 9, Step 4 (`service/storing/*_queries.go`), если без переписывания индекс не выбирается
- Test: `handler/test/operator_volume_test.go`, `operator_cost_test.go`

**Interfaces:**
- Consumes: `TestReadAtVolume`, `readLimit` (Task 9).
- Produces: `const slowRead = 10 * time.Second` в `operator_volume_test.go` — тот же тест падает на каждом `GET` ≥ `slowRead`.

- [ ] **Step 1: тест.** `TestReadAtVolume` получает `require.Less(t, d, slowRead)` для каждого `GET`. Прогон Task 9, Step 3 — FAIL на найденных.
- [ ] **Step 2: причина.** По `EXPLAIN` — какой узел плана читает всю историю (`Seq Scan`, сортировка всех строк). Решение — в журнал плана одной строкой (решение 218).
- [ ] **Step 3: миграция `042`.** Индекс под найденное условие (`CREATE INDEX` — в Postgres 9.6 без `CONCURRENTLY` внутри миграции, как у 020). `TestMigration042`: индекс есть, `Down` его снимает. Если индекс не выбирается — переписать запрос без смены ответа; ответы сверяет прежний набор тестов.
- [ ] **Step 4: повторный замер.** Команда Task 9, Step 3 — PASS: все `GET` < 10 с; цифры до и после — в журнал. Бюджеты решения 69 на малом наборе: `IM_MEASURE=1 … -run 'TestReadBudgets|TestSummariesBudget|TestFilterBudget'` — не хуже прежних (стоимость записи индекса на переход — `TestLockHoldBudget`).
- [ ] **Step 5:** `-run 'TestQueue|TestSummaries|TestFilter|TestListLinkedSQLCount|TestCardSQLCount'` и с тегом `imtest` — PASS. Мутанты: снять индекс в `042` (замер падает), вернуть старый запрос (замер падает), сменить порядок столбцов индекса. Коммит `После этапа 9: чтение на 800 000 укладывается в 10 с — индекс 042`.
- [ ] **Step 6:** миграция `042` на `imdb` — в Task 8 нет; применяется перед Task 11 тем же порядком, что Task 8, Step 1 (замок, дамп `imdb-before-p62t10.sql`, откат в `30-local-stand.md`).

### Task 11: шаг Image и `skipped` объединения на стенде

Пишет Opus. Ревью: Opus (правила Task 25–26 плана 59).

**Files:**
- Modify: `~/Work/stand/ui-check/check-operator-server.mjs:12-16` (`PARTS` + `image`, `merge-skipped`), копия `*.before-62`

**Interfaces:**
- Consumes: `emitIncidents`, `openIncident`, `markRow`, `selectMenu`, `closeIncidents`, `answerStep` того же файла.

Правила Task 25–26 (`task-25-report.md:44-48`, `task-26-report.md:30,72-75`): записи только при `IM_STAND_WRITES=1 IM_STAND_EMIT=1`; инциденты только от эмулятора, каждый запоминается; уборка в `finally` при любом исходе и отдельная строка проверки `closed` по API; кнопки — по точному имени; шаг-кнопку не жать повторно (`aria-pressed`); дамп перед первым прогоном с записями и перед повторным.

- [ ] **Step 1: сценарий с шагом Image.** В демо-наборе его нет. По ответу на вопрос 2 (2026-11-03): сценарий «Демо: снимок» с одним шагом `Image` (`source: operator`) и правило на тип события, которого нет в других правилах, — через `load-demo.sh` (`demo-config`), под замком и с дампом. Откат — удаление правила по имени.
- [ ] **Step 2: часть `image`.** Инцидент по этому правилу; в карточке шаг Image: файл 100 КБ — ответ `200`, вложение в `scenario.result` (API); файл 2 МБ — либо `200`, либо отказ, показанный уведомлением, а шаг остаётся неотвеченным (вопрос 5 плана 59). Какой из двух — записать цифрой: это и есть предел стенда (шлюз `nginx`, `client_max_body_size`).
- [ ] **Step 3: часть `merge-skipped`.** Два инцидента разных сценариев (два типа события эмулятора) и третий того же сценария, что первый. Отметить три, «Взять в работу» с объединением. По API: основной `in_progress`, третий `linked`, второй остаётся в прежнем состоянии; в ответе `skipped` — ровно guid второго (`incidentGuid`); интерфейс сказал об этом уведомлением.
- [ ] **Step 4:** только чтение — `node check-operator-server.mjs image` и `merge-skipped`: `FAIL 0`, записи — `SKIP` с причиной. С записями — `OK N, FAIL 0, SKIP 0`, код 0. Ранний выход (`IM_STAND_FAIL_AFTER=emit`) — все свои инциденты `closed`.
- [ ] **Step 5:** итоги, номера созданных инцидентов и предел вложения — в журнал плана. Коммита нет (стенд вне git).

### Task 12: ADR и итог

Пишет Opus. Ревью: всей работы плана, Opus.

**Files:** Modify `docs/adr/005-transitions-in-transaction.md:262-265`, `docs/adr/007-references-and-test-stand.md:54`; этот план — раздел «Итог».

- [ ] **Step 1:** ADR-005: пункты `People`, окна `comeBack`, срок жизни и `open_incident_guid` перенести из «Before the public launch» в сделанное, с остатком решения 97; Task 20–25 плана 57 остаются. ADR-005, «Volumes» — цифры Task 9 и 10. ADR-007:54 — участники групп из таблицы.
- [ ] **Step 2:** «Итог» плана: по задаче — коммит, итог проверок, что не прогнано и почему. Строки «Следы на стенде» в `30-local-stand.md` — что создано и закрыто.
- [ ] **Step 3:** коммиты сервера и IM `После этапа 9: ADR и итог`.

---

## Глубина ревью по задачам

| Task | Механическая | Пишет | Ревью |
|---|---|---|---|
| 1, 2, 3, 4 | да | Sonnet | Sonnet, коротко |
| 5, 6, 7 | нет | Opus | Opus с мутантами |
| 8, 11 | нет | Opus | Opus (стенд, уборка) |
| 9 | нет | Opus | Opus (способ замера) |
| 10 | нет | Opus | Opus с мутантами |
| 12 | нет | Opus | вся работа плана |

Мутанты Task 5–7: снять `identity_ms <=` из условия; `>=` вместо `>` у `seen_ms >= $since`; убрать `customer_guid` из `OperatorPeople`; `Seen` вместо `People` в `world.go`; `People` вместо `Seen` в `access.go`; убрать `VisibleAmong` из heartbeat; убрать `Remember` из цикла `reauth`. Каждый должен ронять хотя бы один тест шаблона.

## Не в этом этапе

| Что | Куда | Почему |
|---|---|---|
| Task 20–25 плана 57 (таблица повторов, дерево на всех экземплярах, два сервера) | до публичного запуска | решение пользователя 2026-11-01 в силе |
| `dev-login.html` с паролем | список на удаление | ответ на вопрос 1 | страница в браузере, файл ей не прочесть |
| звук в продукте | нет | решение 165 |

## Решения этого плана — обоснования

- **213.** Функции `MoveAddressed` в коде больше нет: ходы адресованного делают `SessionMoves` и тик планировщика (ADR-006, пункт 9). Окно решения 97 плана 57 — там же, поэтому проба пишется на оба пути.
- **214.** `Directory.People` делится надвое. Таблицу читают те, кому нужен список людей клиента: адресаты, состав дежурных групп, админка. Память доступа и доставка потока остаются на памяти процесса (`Seen`): им нужны люди с открытым потоком этого процесса, и чтение таблицы на каждую доставку дало бы запрос на событие.
- **215.** Замер стирает и наполняет базу. Проверка имени `im_volume` до первой записи — та же защита, что `TestCheckDatabaseName` этапа 7.
- **216.** Пароль читает только `jq --rawfile`, как у второго оператора: он не попадает в `ps`, в окружение и в журнал скрипта. Без файла — `SKIP`, а не `FAIL`: нет файла — это не дефект сервера.
- **218.** Медленный `GET` исправляется здесь же (ответ на вопрос 3): индекс отдельной миграцией со следующим свободным номером (042: 040 — Task 5, 041 — за Task 21 плана 57), повторный замер — тот же тест.
- **219.** RULE-141 — на `main` (ответ на вопрос 4): правила общие для двух авторов. В ветку интеграции — `cherry-pick -x`, чтобы не тащить в неё прочее из `main` и видеть исходный хэш.
- **217.** Звук — решение пользователя новее правил (решение 165); правила меняются своим порядком, поэтому пункт RULE-141 с заполненным «Решение», а не правка без пункта.

## Вопросы пользователю (отвечены 2026-11-03)

| № | Вопрос | Умолчание | Решение |
|---|---|---|---|
| 1 | `dev-login.html` держит пароль `test@` открытым текстом, а страница файл прочесть не может | не трогать: файл в списке на удаление (`cleanup-dev-login`) || оставить, файл в списке на удаление — пользователь, 2026-11-03 |
| 2 | Откуда сценарий с шагом Image на стенде | сценарий «Демо: снимок» через `demo-config`, правило снимается по имени после проверки | |
| 3 | Что делать, если `GET` на 800 000 выходит за 10 с | записать `EXPLAIN`, индексы — отдельным решением | исправить в этом плане: Task 10 (EXPLAIN, индекс 042, повторный замер) — пользователь, 2026-11-03 |
| 4 | Ветка IM для RULE-141: `feature/im_operator` или `main` | `feature/im_operator`, как ARCH-14 и ARCH-15 | `main`: `git fetch`, коммиты локально, затем `cherry-pick -x` в `feature/im_operator` — пользователь, 2026-11-03 |

## Самопроверка плана

- Решения пользователя A–E — Task 1–3, Task 4, Task 5–8, Task 9–10, Task 11; ответы на вопросы 1–4 — в таблице и в Task 4, 10, 11. Пробелов нет.
- Имена согласованы: `operator_login`/`$OPERATOR_WHY` (Task 3 → 1, 8, 11), `rememberEvery` (5 → 7), `personKeepFor`, `Directory.People`/`Seen` (6 → 7, 8), `readLimit` (9 → 10), `slowRead` (10), миграции 040 (5) и 042 (10) не пересекаются с 041.
- Review Focus 1–5 закреплены тестами или шагами Task 6, 7, 5, 3, 8 и 11.
- Тел функций нет, только сигнатуры, тесты и команды.

## Итог

Заполняет Task 12.
