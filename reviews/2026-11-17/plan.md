# План исправлений по ревью 2026-11-17

Основание: [review.md](review.md) — формальная проверка обеих машин после RULE-142. Коммит `102d5df`, ветка `feature/im_operator`.

Как вести:

- Пункт из таблицы решений — в работу, только когда заполнено «Решение».
- Выполняется по прямой просьбе («сделай этап 1», «исправь BUG-125»).
- Коммитов на пункт два: исправление (сообщение начинается с номера пункта) и отметка `[x]` с хэшем в этом плане.
- Возражение — цитатой под пунктом, с именем.
- Пункт меняет контракт или сервер — то же в сервере стенда (im-server) и конфигураторе. Перед коммитом — выкат на стенд и проверка там. Сервер и конфигуратор выкатываются вместе.

Проверить после каждого пункта:

- быстрые проверки из CLAUDE.md;
- самопроверка `prototype/index.html?selftest`, тесты API `tests/api.html`;
- если правили машину — ещё `node tools/cel_vectors.mjs --update` и затронутые порчи `python3 tools/check_mutations.py <имя>`;
- если правили `prototype/*.js` — порчи кода не устарели (скилл im-fix);
- если правили `app.js` — `python3 tools/check_ui.py --only очередь` и `check_guide.py`.

## Таблица решений

| Пункт | Вопрос | Варианты | Предложение | Решение | Кто, дата |
|---|---|---|---|---|---|
| RULE-143 | Что сверяет «Сменить приоритет» | а) состояние и уровень: `expects: ["state","priority"]`, поле `expectedPriority`, отказ `changed: priority` «Приоритет уже изменён: {priority}»; б) состояние, адресат и уровень; в) как сейчас, в §14.1 записать, что смены наперегонки не сверяются | а): решение зависит от уровня, а не от того, кто ведёт инцидент | а) | joynickray, 2026-11-17 |
| RULE-144 | Какие итоги макроса и команды останавливают закрытие | а) любой итог (`macro`, `external`) при любом авторе — новое поле машины; б) только неуспех — «не выполнен», «просрочен», «прерван», «нет макрокоманды», «не доставлен» — через уже имеющийся список `templates`, новых полей нет; в) никакие, из §14.1 итог макроса убрать | б): «выполнен» нового оператору не говорит, а неуспех — то, ради чего сверка | в) никакие: из §14.1 итог макроса и ответ на шаг убрать | joynickray, 2026-11-17 |
| RULE-146 | По чему сверять ответ на шаг | а) порядковый номер ответа в прохождении (`seq`), `seenAnswer` — число; б) оставить время, записать, что совпадение в одну миллисекунду не различается | а): как у журнала в §14.1 — по номеру, не по времени | а) | joynickray, 2026-11-17 |
| RULE-147 | Сверяет ли курсор сценария, что видел оператор | а) нет, так и записать в контракте; б) `expectedOwner` у курсора, другой владелец — 412 «Инцидент уже ведёт …» | б): одна смена — одно объяснение, как у ответа на шаг | б) | joynickray, 2026-11-17 |

## Этап 1 — без решений

- [ ] **RULE-145** [средний] Реестр текстов сервера `messages` без ключей RULE-142.

  **Что видно.** В реестре `messages` машины ([workflow_schema.v1.json:1499](https://github.com/soulhome2/IM/blob/102d5df/Specification/Workflow_machine/workflow_schema.v1.json#L1499)) из ключей отказа RULE-142 есть только `workflow.error.changed.family`. В каталогах `strings/*.json` и в контракте есть все.

  **Почему.** RULE-142 убрал из реестра `precondition_required` и добавил `changed.family`. Ключи, которые пишет встроенный сервер ([server.js:1553–1565](https://github.com/soulhome2/IM/blob/102d5df/prototype/server.js#L1553), [:2045](https://github.com/soulhome2/IM/blob/102d5df/prototype/server.js#L2045)), в реестр не внесены. Проверок, которые это ловят, нет (PROC-94).

  **Что сделать.**
  1. Дописать в `messages` с подстановками:
     - `workflow.error.changed.state` `["state"]`;
     - `changed.taken` `["who"]`, `changed.addressed` `["who"]`;
     - `changed.queue`, `changed.news`, `changed.primary` `[]`;
     - `workflow.error.expected_required` `[]`;
     - `workflow.error.scenario.step_changed` `["step","who"]`, `scenario.step_changed_anon` `["step"]`.
  2. Ключи прошлых циклов: `workflow.error.audit_export_too_large`, `filter.bad`, `no_audit_access`. Подстановки — по тексту каталога.
  3. У `workflow.error.version_conflict` — `$comment`: «только черновик схемы и внутренняя сверка сервера (RULE-142)».
  4. Сервер стенда: сверить его список ключей с реестром. Если он берёт подстановки из реестра — проверить отказ 412 с подстановкой на стенде.

  **Где менять.** `workflow_schema.v1.json`, сборка `build_workflow.py`, `cel_vectors.mjs --update`; сервер стенда — по итогу сверки.

  **Готово, когда:** каждый `workflow.error.*`, который пишет встроенный сервер, есть в `messages`, и `vars` совпадают с подстановками текста; проверки зелёные.

- [ ] **PROC-94** [низкий] Реестр `messages` ни с чем не сверяется. Делать после RULE-145, иначе проверка сразу красная.

  **Что видно.** RULE-145 прошёл `check_machine.py`, `check_i18n.py` и тесты API зелёным.

  **Что сделать.**
  1. В `check_machine.py`:
     - каждый ключ `workflow.error.*`, `workflow.guard.*`, `workflow.journal.*`, который встречается строкой в `prototype/server.js` и `prototype/engine.js`, есть в `messages`, в `failKeys` реестра или в `appendLog` переходов;
     - подстановки `{…}` текста в `strings/ru.json` совпадают с `vars` записи.
  2. Порча в `tools/mutations/machine.json`: убрать ключ из `messages` → `check_machine.py --mutations` её ловит. `python3 tools/mutation_table.py`.

  **Где менять.** `tools/check_machine.py`, `tools/mutations/machine.json`, `tools/mutations/MACHINE.md` (собирается).

  **Готово, когда:** на `102d5df` проверка нашла бы RULE-145; порча поймана.

- [ ] **BUG-125** [низкий] Ответ на шаг закрытого инцидента — `changed: addressee` вместо `state`.

  **Что видно.** Я взял, Петрова перехватила и закрыла, я отвечаю на шаг: `412`, `details.changed: addressee`, текст «Инцидент уже в состоянии «Закрыто»». Переход в той же ситуации отвечает `changed: state`.

  **Почему.** Ответ на шаг вызывает `changedProblem(ev, "addressee")` ([server.js:2037](https://github.com/soulhome2/IM/blob/102d5df/prototype/server.js#L2037)). `changedProblem` для закрытого меняет текст, но не `details.changed`. Контракт (`VersionConflict`) и §14.1: «закрытый теперь — всегда `changed: state`».

  **Что сделать.**
  1. В `changedProblem` ([server.js:1553](https://github.com/soulhome2/IM/blob/102d5df/prototype/server.js#L1553)) — закрытый → `what = "state"` до выбора текста и `details`.
  2. Тест API в `tests/api-scenarios.js` рядом с «Ответ на шаг (§14.1, RULE-142)»: перехватили и закрыли → `412`, `changed: state`, `messageKey: workflow.error.changed.state`.
  3. Сервер стенда — проверить тот же случай. Расходится — исправить там же.

  **Где менять.** `prototype/server.js`, `tests/api-scenarios.js`; сервер стенда.

  **Готово, когда:** у всех путей отказа (переход, ответ на шаг, массовое, объединение) закрытый даёт `changed: state`; тест проходит.

- [ ] **DOC-80** [низкий] Исключения из обязательных `expectedState` и `expectedAddressee` в контракте неполны.

  **Что видно.** Описания `expectedState`, `expectedAddressee` ([openapi.json:8746](https://github.com/soulhome2/IM/blob/102d5df/Specification/Workflow_machine/openapi.json#L8746)) и ответа `PreconditionRequired` называют исключением только `comment`. А у `detach` `expects` тоже пуст ([workflow_schema.v1.json:1269](https://github.com/soulhome2/IM/blob/102d5df/Specification/Workflow_machine/workflow_schema.v1.json#L1269)), и через `POST …/transitions/detach` сервер их не требует.

  **Что сделать.** Текст: «обязательны у переходов с непустым `concurrency.expects` машины — сейчас у всех ручных, кроме `comment` и `detach`». То же в `PreconditionRequired`.

  **Где менять.** `openapi.json` (CRLF), сборка `openapi.v30.json`, `test_openapi30.py`.

  **Готово, когда:** контракт называет оба исключения; сборка и `test_openapi30.py` зелёные.

## Этап 2 — машина инцидента, после решений

- [ ] **RULE-143** [средний] «Сменить приоритет» сверяет адресата, а уровень — нет.

  **Что видно.** Запуски на встроенном сервере:
  - оба видели 100, Петрова поставила 75 (200), я — 50 (200), итог 50: смена Петровой затёрта молча;
  - Петрова взяла инцидент, я меняю приоритет по тому, что видел → `412` «Инцидент уже ведёт Петрова М.», хотя владельцем для смены приоритета быть не нужно.

  **Почему.** У `change_priority` `expects: ["state","addressee"]` ([workflow_schema.v1.json:858](https://github.com/soulhome2/IM/blob/102d5df/Specification/Workflow_machine/workflow_schema.v1.json#L858)). Решение основано на уровне: от него зависят `priorityChanged` и `enabledExpr` формы. От адресата оно не зависит.

  **Что сделать** (по решению а).
  1. Машина: `change_priority.concurrency.expects` → `["state","priority"]`, `$comment` перехода — что и почему сверяется.
  2. Контракт:
     - `priority` — в перечень `concurrency.expects`;
     - поле запроса `expectedPriority` (целое; обязательно, если в `expects` есть `priority`);
     - `details.changed: priority`;
     - описание `VersionConflict` и `PreconditionRequired`.
  3. Текст отказа `workflow.error.changed.priority` «Приоритет уже изменён: {priority}» — в `messages` с `vars`, в `strings/ru.json` и `en.json`.
  4. Правила §14.1: «смена приоритета сверяет состояние и уровень». В §2.5 — ссылка на это. Журнал правил `CHANGELOG.md`.
  5. Прототип:
     - `server.js` — `changedOf` сверяет `priority`, `changedProblem` даёт текст;
     - `app.js` ([:1770](https://github.com/soulhome2/IM/blob/102d5df/prototype/app.js#L1770)) — форма смены приоритета шлёт `expectedPriority` с карточки на экране;
     - мягкий текст 412 — как у других отказов.
  6. Тесты API:
     - две смены наперегонки → вторая `412`, `changed: priority`, итог — первая;
     - смена, пока коллега взял, → 200;
     - без `expectedPriority` → 428.
  7. Шаг самопроверки в `prototype/selftest.js`: две смены приоритета наперегонки — вторая получает отказ «Приоритет уже изменён».
  8. Сервер стенда и конфигуратор — то же; выкатывать вместе.

  **Где менять.** `workflow_schema.v1.json`, `openapi.json`, `strings/*.json`, `States rules IM.md` и `CHANGELOG.md`, `prototype/server.js`, `app.js`, `selftest.js`, `tests/api-scenarios.js`, руководство оператора (текст отказа); im-server, конфигуратор.

  **Готово, когда:** смена приоритета не затирает чужую молча и не получает отказа из-за того, кто ведёт инцидент; сборка, самопроверка, тесты API, `check_i18n.py`, `cel_vectors.mjs --check` зелёные.

- [ ] **RULE-144** [средний] Итог макроса по §14.1 — новое событие для закрытия, по машине — «своё».

  **Что видно.** Закрывает только владелец (не владелец — `403 GUARD_FAILED`). На шаги отвечает и макрос запускает тоже он. Встроенный сервер пишет итог макроса от имени ответившего ([server.js:499](https://github.com/soulhome2/IM/blob/102d5df/prototype/server.js#L499)). При `journalNews.ownExcluded` ([workflow_schema.v1.json:2061](https://github.com/soulhome2/IM/blob/102d5df/Specification/Workflow_machine/workflow_schema.v1.json#L2061)) эта запись закрытие не останавливает. «Макрос «Включить сирену» не выполнен» после показа карточки — а закрытие проходит. Виды `macro`, `external` в прототипе не появляются. Ответ на шаг через API в журнал не пишется вовсе.

  **Почему.** §14.1 перечисляет «итог макроса или команды» и «ответ на шаг» среди новых событий, не сверив их с правилом «свои не считаются».

  **Что сделать** (по решению б).
  1. Машина: в `journalNews.templates` — `workflow.journal.macro.failed`, `macro.expired`, `macro.interrupted`, `macro.unknown_macro`, `macro.not_delivered`. Это новое событие при любом авторе. Своих ключей журнала для неуспеха внешней команды (`externalCommand`) в каталоге нет: §14.2 говорит о записи «неуспех» и признаке «команда не доставлена». Если такая запись на стенде есть — завести её ключ в каталоге и добавить сюда же. `$comment` — почему «выполнен» не считается.
  2. Правила §14.1:
     - «итог макроса или команды» → «неуспех макроса или команды — при любом авторе»;
     - «ответ на шаг» из списка убрать: отвечает сам закрывающий;
     - журнал правил.
  3. Встроенный сервер: итог макроса — отдельной записью после запуска, как у агента. Чтобы тест мог прислать неуспех после показа карточки — служебная операция тестового стенда (например, `POST /test/macros/{executionGuid}/result`) с описанием в контракте и README машины, «Тестовый стенд».
  4. Тест API: ответ на шаг с макросом, карточка показана, пришёл неуспех → закрытие `412 news`; пришло «выполнен» → закрытие 200.
  5. Шаг самопроверки в `prototype/selftest.js`: неуспех макроса после показа карточки — закрытие остановлено с текстом «Пришло новое событие — проверьте».
  6. Сервер стенда: проверить, с каким ключом и автором пишется итог от агента. Совпадает с каталогом — ничего не менять, иначе привести к нему.

  **Где менять.** `workflow_schema.v1.json`, `States rules IM.md`, `CHANGELOG.md`, `prototype/server.js`, `selftest.js`, `openapi.json` (служебная операция), README машины, `tests/api-scenarios.js`; im-server.

  **Готово, когда:** неуспех макроса после показа карточки останавливает закрытие у владельца — в прототипе и на стенде; правила и машина говорят одно.

## Этап 3 — стык со сценариями, после решений

- [ ] **RULE-146** [низкий] `seenAnswer` — время ответа: два ответа в одну миллисекунду неразличимы.

  **Что видно.** На часах тестового стенда (между запросами стоят) два переответа на один шаг получают один `answeredAt`. Вкладка с устаревшим ответом проходит (200) и затирает ответ другой вкладки.

  **Почему.** Контракт ([openapi.json:9288](https://github.com/soulhome2/IM/blob/102d5df/Specification/Workflow_machine/openapi.json#L9288)) и сервер ([server.js:2040](https://github.com/soulhome2/IM/blob/102d5df/prototype/server.js#L2040)) сравнивают время, а не номер.

  **Что сделать** (по решению а).
  1. У ответа в прохождении — порядковый номер `seq`: растёт на каждый ответ и пропуск ([scenario.js:224](https://github.com/soulhome2/IM/blob/102d5df/prototype/scenario.js#L224)). В `IncidentScenario` он отдаётся.
  2. `seenAnswer` — номер (`integer | null`), сервер сверяет номер. Профиль МИ в README машины сценариев и §14.5 — что такое номер ответа.
  3. `app.js` ([:1788](https://github.com/soulhome2/IM/blob/102d5df/prototype/app.js#L1788)) шлёт номер; `tests/harness.js` (`answerSeenOf`) — тоже.
  4. Тест стыка в `tests/api-junction.js`: два переответа на одних часах → второй по устаревшему — `409 STEP_CHANGED`.
  5. `scenario_vectors.mjs --update`, если меняется запись прохождения. Сервер стенда и конфигуратор — то же.

  **Где менять.** `prototype/scenario.js`, `server.js`, `app.js`, `openapi.json`, `Specification/Scenario_machine/README.md`, `States rules IM.md` §14.5, `tests/harness.js`, `tests/api-junction.js`; im-server, конфигуратор. Проверки: `check_scenarios.py`, `check_scenario_states.mjs`, `tests/scenario.html`.

  **Готово, когда:** устаревший переответ отклоняется при любых часах; тесты сценариев и стыка зелёные.

- [ ] **RULE-147** [низкий] Курсор сценария не сверяет, что видел оператор.

  **Что видно.** После перехвата `PUT …/scenario/cursor` отвечает `403` «Карточка открыта на просмотр». Ответ на шаг в той же ситуации — `412` «Инцидент уже ведёт …» с карточкой.

  **Почему.** У курсора ([openapi.json:1486](https://github.com/soulhome2/IM/blob/102d5df/Specification/Workflow_machine/openapi.json#L1486), [server.js:2058](https://github.com/soulhome2/IM/blob/102d5df/prototype/server.js#L2058)) полей «что видел» нет. Отказ даёт проверка `canEditScenario`.

  **Что сделать** (по решению б).
  1. Контракт: `SetCursorRequest.expectedOwner` (обязательно, нет — 428), другой владелец — `412 INCIDENT_CHANGED` с карточкой; ответ `412` и `428` в описании операции.
  2. `server.js` — сверка до `canEditScenario`, как у ответа на шаг. `app.js` ([:1757](https://github.com/soulhome2/IM/blob/102d5df/prototype/app.js#L1757)) шлёт владельца с карточки; мягкое «Уже взял {who}», как у ответа.
  3. Тест стыка: курсор после перехвата → `412`, `messageKey: workflow.error.changed.taken`.
  4. Сервер стенда и конфигуратор — то же.

  При решении а) — только строка в описании `setScenarioCursor`: «что видел оператор, не сверяется: курсор ничего не меняет; после смены владельца — `403`».

  **Где менять.** `openapi.json`, `prototype/server.js`, `app.js`, `tests/api-junction.js`; im-server, конфигуратор.

  **Готово, когда:** после перехвата курсор и ответ на шаг объясняют смену одинаково (или контракт прямо говорит, что курсор не сверяется).
