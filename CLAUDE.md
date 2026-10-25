# Incident Manager (МИ) — памятка для Claude Code

Репозиторий этапа проектирования: правила жизненного цикла инцидента, машина состояний, кликабельный прототип.
Production-кода нет. Обзор и порядок чтения — [README.md](README.md); там же полный список проверок («Проверки»).

## Источник истины

- Правила — [States rules IM.md](Specification/State_rules/States%20rules%20IM.md), один действующий файл, журнал — `State_rules/CHANGELOG.md`. `State_rules/archive/` не править.
- Машина — `Specification/Workflow_machine/workflow_schema.v1.json` (условия и эффекты — выражения CEL, [CEL.md](Specification/Workflow_machine/CEL.md)) и контракт `openapi.json`. Прототип исполняет машину и своей логики правил не держит: правило меняется в машине, а не в `prototype/*.js`.
- Руководство оператора расходится с правилами — верны правила.
- Ревью и планы — `reviews/<дата>/`, порядок и нумерация пунктов — [reviews/README.md](reviews/README.md).

## Сгенерированные файлы — руками не править

| Файл | Исходник | Собрать |
|---|---|---|
| `prototype/workflow.js`, `openapi.js`, `fixture.js`, `strings.js`, `tests/scenario-examples.js`, `Specification/Workflow_machine/TRANSITIONS.md`, `SETTINGS.md` | машина, контракт, эталонный набор, строки, примеры сценариев | `python3 tools/build_workflow.py` |
| `Specification/Workflow_machine/quint/im.qnt` | машина + `quint/src/*.qnt` | `node tools/gen_quint.mjs` |
| `tools/mutations/MACHINE.md` | `tools/mutations/machine.json` + итоги прогонов порч | `python3 tools/mutation_table.py` |

## Что поменял → что проверить

Быстрые (доли секунды) — после любой правки: `python3 tools/build_workflow.py --check`, `python3 tools/check_machine.py`, `node tools/check_cel.mjs`, `node tools/gen_quint.mjs --check`, `python3 tools/check_links.py`.

| Поменял | Дополнительно |
|---|---|
| машину, контракт, эталонный набор | сборка (выше), самопроверка и тесты API; затронутые мутации машины — `python3 tools/check_mutations.py <имя> …` |
| `strings/*.json`, переводы | `python3 tools/check_i18n.py`, `python3 tools/check_guide.py` |
| сценарии, `Scenario_machine/` | `python3 tools/check_scenarios.py`, `tests/scenario.html` |
| `prototype/*.js` | самопроверка и тесты API; порчи кода не устарели (скилл im-fix) |
| `app.js`, `styles.css`, `bridge.css`, `index.html` | плюс `python3 tools/check_ui.py` (~2 мин), `check_guide.py` |
| `quint/src/` | `quint test im_test.qnt`, `quint run im.qnt --invariant inv` — [README модели](Specification/Workflow_machine/quint/README.md) |

Самопроверка и тесты — headless Chrome, временные файлы в scratchpad:
`google-chrome --headless=new --disable-gpu --no-first-run --user-data-dir=<tmp> --virtual-time-budget=180000 --dump-dom "file://$PWD/prototype/index.html?selftest"` — итог `data-selftest="pass|fail"`, отчёт в `<pre id="selftest-log">`. Тесты API — то же с `tests/api.html` (бюджет 120000, `data-apitest`, `apitest-log`), исполнитель сценариев — `tests/scenario.html` (20000, `data-scenariotest`, `scenariotest-log`).

Полные прогоны мутаций кода (`check_code_mutations.py`, ~6–15 мин) по умолчанию не запускать — их гоняет CI; предложить, запускать по просьбе. Не прогнал проверку — так и сказать, с причиной.

## Договорённости

- Работают двое, оба пушат прямо в `main`, без pull request. Перед правкой — `git fetch`; есть новое на GitHub — предложить подтянуть.
- Коммит и push — только по просьбе. Коммитов на пункт плана два: исправление (`BUG-01: …` — сообщение начинается с номера пункта) и отметка `[x]` с хэшем в `plan.md` (`Хэш <коммит> в плане ревью <дата>`).
- Пункт из таблицы решений плана — в работу, только когда заполнено «Решение».
- Новый функционал — вместе с шагом самопроверки в `prototype/selftest.js`.
- `Specification/Workflow_machine/README.md` и `openapi.json` — в CRLF, так и держать.
- Экранный диктор интерфейс не поддерживает (решение 2026-10-17) — находок о нём не записывать.
- Язык документов и сообщений коммитов — русский, простыми словами.

## Скиллы

`/im-review [роль]` — ревью; `/im-fsm` — формальная проверка машин; `/im-fix <пункт>` — выполнить пункт плана.

Сценарии из нескольких агентов — `.claude/workflows/`, промпты к ним — `prompts/`. `verification-audit` — консилиум «хватает ли проверок логики машин» (`prompts/verification-pipeline-audit.md`), запуск — только по просьбе, с датой: `args = {date: "ГГГГ-ММ-ДД"}`; дата не названа — сегодняшняя.
