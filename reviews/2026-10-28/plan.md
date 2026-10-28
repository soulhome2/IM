# Этап 1 встраивания в облако: контракт, права и правила — план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Каждая задача — через superpowers:test-driven-development: сначала падающий тест, потом код.

**Goal:** Контракт, машина и правила готовы к серверу МИ в облаке: копия контракта в OpenAPI 3.0 для генератора сервера, права машины с именами облака, правила и `BACKEND.md` по решениям 2026-10-28.

**Architecture:** Пункт `ARCH-14` из трёх подзадач. Копию контракта в 3.0 собирает `build_workflow.py` модулем `tools/openapi30.py` с юнит-тестами; годность копии проверяется генератором самого сервера МИ. Имена прав облака — новое поле `cloud` у прав машины; `check_machine.py` сверяет их с правилом имён облака и с колонкой §5 правил. Правила и `BACKEND.md` — по решениям из [40-plan.md](../../research/integration/40-plan.md).

**Вне этапа (решение 2026-10-28):** вход и токены не трогаем — на стенде работает тестовый пользователь. `prototype/api.js` и поток событий (`EventSource`) не меняются; задачи о входе по токену облака — в [11-auth-session.md](../../research/integration/11-auth-session.md), вернёмся к ним отдельно.

**Tech Stack:** Python 3 (`unittest`), JSON машины и контракта, Go — только для проверки копии генератором сервера.

**Spec:** [research/integration/40-plan.md](../../research/integration/40-plan.md), этап 1 и таблица «Решения»; подробности — [10-permissions.md](../../research/integration/10-permissions.md) (права), [14-im-backend-operator.md](../../research/integration/14-im-backend-operator.md) п. 5 (OpenAPI 3.0), [20-decisions.md](../../research/integration/20-decisions.md) раздел 6.

Ветка — `feature/im_operator` (не `main`: решение 2026-10-28). Коммит — после каждой задачи, сообщение с номером подзадачи (`ARCH-14.1: …`); push — по просьбе.

## Global Constraints

- `Specification/Workflow_machine/openapi.json` и `Specification/Workflow_machine/README.md` — в CRLF, так и держать.
- Сгенерированные файлы руками не править: `prototype/openapi.js`, `workflow.js`, `Specification/Workflow_machine/quint/im.qnt` и новый `Specification/Workflow_machine/openapi.v30.json` — только сборкой (`python3 tools/build_workflow.py`, `node tools/gen_quint.mjs`).
- Правило меняется в машине и правилах, не в `prototype/*.js`. Быстрые проверки из `CLAUDE.md` — после каждой задачи: `python3 tools/build_workflow.py --check`, `python3 tools/check_machine.py` (и `--mutations`), `node tools/check_cel.mjs`, `node tools/gen_quint.mjs --check`, `python3 tools/check_links.py`.
- Облако не меняем. Глаголы облака — ровно `create view edit delete manage use run share export import download apply bind encrypt block take close track assign suspend process`; области — `own any`; пространство — `incident_manager`; сегмент — `[a-z][a-z0-9_]*`; последний сегмент — глагол, либо область, перед которой глагол (`axxoncloudgo` `model/permissions/permissions.go#287`, `methods.go` `IsValidPermissionName`, ветка `epic/CLOUD-23284-perms-i18n`).
- Генератор сервера МИ — форк `src.axxonsoft.dev/bitbucket/proj/oapi-codegen@v0.11.0` на `kin-openapi v0.117.0`, OpenAPI 3.1 не понимает. Без VPN — `source ~/go/offline-env.sh` (прокси модулей из `libs.zip`).
- Язык текстов, комментариев и сообщений коммитов — русский, простыми словами.

## Review Focus

1. **Копия 3.0 не грузится генератором сервера** — то, ради чего она есть. Юнит-тесты проверяют правила замены, но не то, что `kin-openapi v0.117` её принимает. Тест — задача 14.1, шаг «генератор сервера принимает копию».
2. **Выброшенные `if`/`then`/`const` у `SelectionRequest`** — в копии 3.0 условной проверки нет; сервер должен проверять это сам, иначе примет неполный запрос. Записать в `BACKEND.md` — задача 14.3; тест — `test_if_then_const_dropped` в 14.1 фиксирует, что выброшено именно это и только это.
3. **Новое поле `cloud` ломает разбор машины** — генератор модели Quint, порчи машины, `check_cel.mjs` могут ждать строгий набор ключей у прав. Тест — задача 14.2, шаг «все быстрые проверки и `--mutations` зелёные».
4. **Новая колонка в таблице §5 ломает разбор правил** — `check_machine.py` (`check_rights_and_defaults`) и `check_guide.py` читают эту таблицу. Тест — задача 14.3, `check_guide.py` и порча колонки.
5. **Два права машины с одним именем облака** — облако сольёт их в одно, и разграничение пропадёт молча. Тест — задача 14.2, проверка уникальности и порча-повтор.

---

### Task 14.1: Копия контракта в OpenAPI 3.0

**Files:**
- Create: `tools/openapi30.py`
- Create: `tools/test_openapi30.py`
- Modify: `tools/build_workflow.py` (`outputs()` — новый выход), `CLAUDE.md` (таблица сгенерированных файлов)
- Generate: `Specification/Workflow_machine/openapi.v30.json`

**Interfaces:**
- Produces: `openapi30.convert(spec: dict) -> dict` — новая копия, исходник не меняется; `openapi30.leftovers(spec: dict) -> list[str]` — пути конструкций, которых нет в 3.0.

- [x] **Step 1: Write the failing test** — `tools/test_openapi30.py`, `unittest`:
  - `test_type_array_to_nullable`: `{"type": ["string", "null"]}` → `{"type": "string", "nullable": True}`.
  - `test_anyof_null_ref`: `{"anyOf": [{"$ref": "#/x"}, {"type": "null"}]}` → `{"allOf": [{"$ref": "#/x"}], "nullable": True}`; с не-`$ref` вариантом — сам вариант плюс `"nullable": True`.
  - `test_examples_to_example`: у схемы `{"examples": [1, 2]}` → `{"example": 1}`.
  - `test_if_then_const_dropped`: `if`, `then`, `const` убраны, остальное у схемы на месте.
  - `test_ref_with_siblings`: `{"$ref": "#/x", "description": "d"}` → `{"allOf": [{"$ref": "#/x"}], "description": "d"}`.
  - `test_whole_contract`: для `openapi.json` — `convert(...)["openapi"] == "3.0.3"`, `leftovers(convert(...)) == []`, `leftovers(original)` не пуст, число путей в `paths` и схем в `components.schemas` не изменилось.
- [x] **Step 2: Run test to verify it fails** — `python3 -m unittest tools/test_openapi30.py -v`; ожидание: `ModuleNotFoundError: openapi30`.
- [x] **Step 3: Implement** `convert` и `leftovers` в `tools/openapi30.py` — рекурсивный обход копии; `leftovers` ищет `type`-массив, `anyOf`/`oneOf` с `{"type":"null"}`, `examples` у схем, `const`, `if`/`then`/`else`, `$ref` с соседями.
- [x] **Step 4: Wire into the build** — `build_workflow.outputs()` выдаёт `Specification/Workflow_machine/openapi.v30.json` (JSON, отступ 2, LF, шапка — поле `info.description` с пометкой «собрано из openapi.json, руками не править»); в `CLAUDE.md` — строка в таблице сгенерированных файлов.
- [x] **Step 5: Run tests to verify they pass** — `python3 -m unittest tools/test_openapi30.py -v` — OK; `python3 tools/build_workflow.py && python3 tools/build_workflow.py --check` — все «совпадает»; `python3 tools/check_links.py`.
- [x] **Step 6: Verify with the server generator** — генератор сервера МИ принимает копию: во временной папке (не в репозитории) `source ~/go/offline-env.sh && go install src.axxonsoft.dev/bitbucket/proj/oapi-codegen/cmd/oapi-codegen@v0.11.0`, затем `oapi-codegen -package operatorapi -generate types,custom-gin,custom-strict-server -o <tmp>/operator.gen.go Specification/Workflow_machine/openapi.v30.json` — код выхода 0; сгенерированный файл компилируется в модуле-времянке (`go mod init tmp`, зависимости — как у `~/Work/incident-manager-server/go.mod`). Исходник `openapi.json` тем же генератором — падает или теряет типы (фиксирует, зачем копия). Итог и версии — в сообщение коммита.
- [x] **Step 7: Commit** — `ARCH-14.1: копия контракта в OpenAPI 3.0 для генератора сервера`. Коммит: `e2cd1c9`

### Task 14.2: Имена прав облака в машине

**Files:**
- Modify: `Specification/Workflow_machine/workflow_schema.v1.json` (`permissions[].cloud`)
- Modify: `tools/check_machine.py` (новая проверка)
- Rebuild: `prototype/workflow.js`, `Specification/Workflow_machine/quint/im.qnt` (если генератор затронут)

**Interfaces:**
- Produces: у каждого права машины поле `cloud: string` — имя права в облаке.

| `key` | `cloud` |
|---|---|
| `incident:claim` | `incident_manager.incidents.take.own` |
| `incident:accept` | `incident_manager.incidents.process` |
| `incident:hold` | `incident_manager.incidents.suspend` |
| `incident:release` | `incident_manager.incidents.release.use` |
| `incident:close` | `incident_manager.incidents.close` |
| `incident:close:unprocessed` | `incident_manager.incidents.unprocessed.close` |
| `incident:reopen` | `incident_manager.incidents.reopen.use` |
| `incident:transfer:own` | `incident_manager.incidents.assign.own` |
| `incident:transfer:any` | `incident_manager.incidents.assign.any` |
| `incident:reassign` | `incident_manager.incidents.take.any` |
| `incident:bulk` | `incident_manager.incidents.bulk.use` |
| `incident:run_action` | `incident_manager.incidents.actions.run` |
| `incident:schema:admin` | `incident_manager.manage` |
| `agent:set_not_ready` | `incident_manager.agent.not_ready.use` |

- [x] **Step 1: Write the failing test** — в `check_machine.py` функция `check_cloud_permissions(w, err)`, вызов рядом с `check_rights_and_defaults`: у каждого права есть `cloud`; имя проходит правило облака (Global Constraints: пространство `incident_manager`, сегменты по образцу, последний сегмент — глагол или область, перед областью — глагол); имена уникальны. Сообщение: `машина, permissions: <key> — имя облака «<cloud>» не проходит правило облака` / `нет имени облака` / `имя облака повторяется`.
- [x] **Step 2: Run test to verify it fails** — `python3 tools/check_machine.py`; ожидание: 14 ошибок «нет имени облака», код 1.
- [x] **Step 3: Implement** — поле `cloud` у 14 прав по таблице выше; `python3 tools/build_workflow.py`; если `node tools/gen_quint.mjs --check` отстал — `node tools/gen_quint.mjs`.
- [x] **Step 4: Run tests to verify they pass** — `python3 tools/check_machine.py` и `--mutations`, `python3 tools/build_workflow.py --check`, `node tools/check_cel.mjs`, `node tools/gen_quint.mjs --check` — зелёные; проверка падает на порче: временно поставить `incident_manager.incidents.release` (без глагола) — ошибка; вернуть.
- [x] **Step 5: Commit** — `ARCH-14.2: имена прав облака в машине и их проверка`. Коммиты: `19aa5cc`, `f229d52` (исключение для имён облака только в `permissions`)

### Task 14.3: Правила и BACKEND.md по решениям

**Files:**
- Modify: `Specification/State_rules/States rules IM.md` — §5 (таблица прав, абзац о ролях), §8.1, §14.5, §15
- Modify: `Specification/State_rules/CHANGELOG.md` — строки в «Изменения после v10»
- Modify: `Specification/Workflow_machine/BACKEND.md`
- Modify: `tools/check_machine.py` (`check_rights_and_defaults`)

**Interfaces:**
- Consumes: поле `cloud` из 14.2.

- [x] **Step 1: Write the failing test** — в `check_rights_and_defaults`: у таблицы §5 `| Право | Что разрешает |` появляется колонка `Право в облаке`; для каждой строки имя в ней (в обратных кавычках) равно `cloud` права машины; иначе `правила, §5: <key> — в облаке «<в правилах>», в машине «<cloud>»`; нет колонки — ошибка «колонка не найдена — сверка не работает».
- [x] **Step 2: Run test to verify it fails** — `python3 tools/check_machine.py`: ошибка «колонка не найдена».
- [x] **Step 3: Implement the rules** —
  - §5: колонка «Право в облаке»; абзац о ролях — «роль» = группа пользователей облака; права и группы вошедшего — из облака (проверка токена отдаёт `userGroupIds` и права); права настройки (`incident:schema:admin`, в облаке `incident_manager.manage`) операторских прав не дают; прав `filter.edit` и `track` у МИ нет.
  - §8.1: дежурная группа — группы пользователей облака и люди.
  - §14.5: как выбирается один сценарий — самое точное условие (устройство точнее типа устройства, тип — группы), при равенстве — выше приоритет правила, у правила — первый сценарий; второго инцидента на то же событие нет; правило без сценария инцидента не создаёт.
  - §15: вопрос о выборе сценария — решён (ссылка на §14.5); вопрос «как МИ получает права и группы остальных пользователей» — из облака служебными запросами с периодической сверкой, события об изменении прав у облака нет.
  - CHANGELOG: по строке на §5/§8.1/§15 и на §14.5, основание — «решения 2026-10-28, research/integration/40-plan.md», коммит — после коммита.
  - `BACKEND.md`: «Что ещё не решено» — вопрос выбора сценария закрыть правилом §14.5 и уникальностью по `event_guid` в одной транзакции с отметкой события; новые требования — арендатор = установка (`customer_guid` из настроек), `problem+json` только на `/operator/*`, `occurredAt` — время события от агента, каталог прав — по полю `cloud` машины (`filter.edit`, `track` убрать; `manage` операторских прав не даёт); копия контракта для генератора — `openapi.v30.json`, в ней нет условной проверки `SelectionRequest` (`if`/`then`) — сервер проверяет её сам; поток событий через шлюз облака — пустой комментарий не реже раза в 15 с, `Cache-Control: no-cache`, `X-Accel-Buffering: no` (шлюз буферизует и рвёт простой). Вход и токены не меняются (решение 2026-10-28, вне этапа).
- [x] **Step 4: Run tests to verify they pass** — `python3 tools/check_machine.py`, `python3 tools/check_guide.py`, `python3 tools/check_links.py` — зелёные.
- [x] **Step 5: Commit** — `ARCH-14.3: правила и BACKEND.md — роли, права облака, выбор сценария`; вторым коммитом — хэш в CHANGELOG. Коммиты: `dc1dbd3`, хэш — `01d63b0`; `f9225f5` (точность выбора правила, сверка ролей, вопросы облаку в §15), хэш — `10173f9`; `0399a38` (правила без сценария не участвуют в выборе; «Событие» в словаре), хэш — `ff6a2a8`

### После этапа

- [x] Итоговый просмотр всей ветки свежим агентом (superpowers:requesting-code-review). Исправления по нему: `eba53b3` (сборка копии 3.0 падает на остатках 3.1, тесты перевода в CI), `5944a3c` (в контракте имя права облака обязательно), `b9cead8` (проверка имён облака целиком, две новые порчи), `e69df50` (§15 — ранжирование условий и источник приоритета; UUID каталога прав в `BACKEND.md`), хэш в журнале правил — `0dc0757`. Отложено без исправления: мелочи перевода в 3.0, которых в контракте нет (их ловит остановка сборки), закрепление исключения `len(path)==3`, «облако» и «внешняя система» вперемешку, цепочки двоеточий в §5 и `BACKEND.md`, строка README §15 в журнале правил, «один» → «не больше одного» в словаре
- [x] Полные мутации кода (`check_code_mutations.py`) не нужны: `prototype/*.js` не менялись (кроме собранного `openapi.js`).
- [x] Строка в таблицу [reviews/README.md](../README.md): «2026-10-28 — этап 1 встраивания в облако (ARCH-14)». Сделано вместе с этой отметкой.
