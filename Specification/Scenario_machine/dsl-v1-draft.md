# DSL v1 — Формат сценария Менеджера инцидентов

> Спецификация формата документа `scenarios.script` (JSONB) и runtime-документа
> `incidents.scenarioResult` (JSONB).
>
> Парная исполняемая схема: [`dsl-v1-schema.json`](./dsl-v1-schema.json).
>
> Версия документа: **v1.0** (поле `dslVersion` в самой схеме).
> Дата: 2026-04-29. Статус: **черновик архитектора**, требует ревью командой
> сервера до реализации.
>
> Связанные документы:
> - [`market-research.md`](./market-research.md) — обзор рынка с Q-вопросами;
> - [`server-analysis.md`](./server-analysis.md) — анализ существующего
>   `incident-manager-server`;
> - `json-model-web-ui 3.md` — исходный черновик (источник вдохновения,
>   **не** контракт). Лежит вне пакета, у заказчика.
> - `proposal-versioning.md` — отдельное предложение для команды сервера
>   (миграция 005, поле `version` в `scenarios`).

## Содержание

1. [Принципы DSL](#1-принципы-dsl)
2. [Глоссарий и связь с сервером](#2-глоссарий-и-связь-с-сервером)
3. [Что НЕ в DSL](#3-что-не-в-dsl)
4. [Корневая структура `script`](#4-корневая-структура-script)
5. [Шаг (`Step`)](#5-шаг-step)
6. [Семь типов шагов](#6-семь-типов-шагов)
   - [6.1. RadioButton](#61-radiobutton)
   - [6.2. Checkbox](#62-checkbox)
   - [6.3. Select](#63-select)
   - [6.4. Comment](#64-comment)
   - [6.5. Image](#65-image)
   - [6.6. Datetime](#66-datetime)
   - [6.7. Button](#67-button)
7. [Условные переходы (`transitions` + JSONLogic)](#7-условные-переходы-transitions--jsonlogic)
8. [Действия (`actions`)](#8-действия-actions)
9. [Прохождение оператора (`scenarioResult`)](#9-прохождение-оператора-scenarioresult)
10. [Сквозной пример](#10-сквозной-пример)
11. [Что валидируется и кем](#11-что-валидируется-и-кем)
12. [Что отложено в v2](#12-что-отложено-в-v2)
13. [Открытые вопросы](#13-открытые-вопросы)

---

## 1. Принципы DSL

Восемь правил, которыми мы руководствуемся при проектировании и которыми
должны руководствоваться при любом будущем расширении.

> Принципы П1–П8 пронумерованы; нумерация фиксирована и не сдвигается при
> расширении DSL — новые принципы добавляются с возрастающими номерами.

### П1. DSL платформо-независим

Один и тот же `script` рендерится на Web, iOS, Android. В DSL запрещены
любые упоминания DOM, CSS, нативных контролов, callback-функций. Только
семантика. Подробное обоснование — `market-research.md` Q3.

### П2. Только семантические подсказки в `view`

`view.label`, `view.required`, `view.options[]` — да. `view.color`,
`view.padding`, `view.fontSize` — нет. Стиль определяется реестром
компонентов на каждой платформе (паттерн Airbnb GP).

### П3. Все runtime-эффекты выражаются как `Action` с явным `type`

Никаких "магических флагов" типа `is_finish` (как в `IM/`). Если эффект
есть — он `{ "type": "...", "args": {...} }`. Это даёт расширяемость через
Action Registry на каждой платформе без изменения схемы.

### П4. Правило трёх рендереров

Перед добавлением любого нового поля отвечаем: **как это рисует Web,
как это рисует iOS, как это рисует Android?** Если хотя бы для одной
платформы ответа нет — поле не добавляем.

### П5. Стабильные идентификаторы важнее имён

`step.id`, `option.id` — стабильные snake-case строки, **не индексы массива**.
Это устраняет фундаментальный баг `IM/`, где удаление опции `radio.name.0`
сдвигало все ссылки `logic.{i}.item{j}`. Подробности — `market-research.md` Q5
(Schema Evolution Rules).

#### П5.1. У каждого сценария есть собственный identity-блок

`metadata.scenarioGuid` (UUID) + `metadata.version` (integer) + `metadata.name`
— **обязательные** поля корня сценария. Они отвечают на три разных вопроса:

| Поле | Отвечает на | Меняется когда |
| --- | --- | --- |
| `scenarioGuid` | «**какой** это сценарий» | никогда (присваивается один раз при создании) |
| `version` | «**какая ревизия**» | при явном «Save as new version» в конфигураторе (manual bump) |
| `name` | «**как назвать в списке**» | в любой момент, без бампа версии |

Значение `scenarioGuid` — то же самое, что хранится в `scenarios.guid` на
сервере. Это даёт:

- **корректный экспорт/импорт между средами** (dev→staging→prod): сценарий
  переезжает с тем же guid, внешние ссылки на сценарий по guid не ломаются;
- **трассируемость в `scenarioResult` и аудите**: в реальной системе результат
  лежит в `incidents.scenarioResult` рядом со снапшотом `incidents.scenario`,
  но если результат экспортирован отдельно — guid+version в нём
  самодостаточны для восстановления контекста;
- **диффы и git-friendly правки**: имя файла свободное, идентичность не
  завязана на путь или название;
- **client-authoritative identity** — guid генерируется конфигуратором
  (UUIDv7), сервер только проверяет уникальность. Это позволяет редактору
  работать offline, draft'ы не зависят от сетевого вызова. См.
  `proposal-versioning.md`.

`additionalProperties: true` для `metadata` оставлен намеренно: добавление
полей вроде `tags`, `author`, `reviewedBy` не требует правки схемы.

### П6. Граф вычислений объявлен, не запрограммирован

Условные переходы — декларативная JSONLogic-формула, не код. Никаких
`evalJs(...)` или `evalScript(...)`. Это безопасно, переносимо, диффабельно.
Подробности — `market-research.md` Q2.

### П7. Сервер не знает, что такое `script`

Сервер хранит `scenarios.script` как непрозрачный JSONB. Валидация по
JSON Schema опциональна и может быть включена позже. До тех пор пока сервер
не вмешивается в содержимое — DSL может эволюционировать без миграций
кода сервера. Серверу нужно отвечать только за CRUD, multi-tenancy и
запуск инцидентов.

### П8. Совместимость через игнор неизвестного

Если runner получает шаг с неизвестным `type` или action с неизвестным
`type` — он **пропускает с warning'ом**, не падает. Это паттерн Airbnb GP.
Это позволяет серверу и фронту жить на разных версиях без жёсткой
синхронизации (важно для мобильных, где обновления приложения не мгновенны).

---

## 2. Глоссарий и связь с сервером

Сводная таблица «как мы это называем в DSL» ↔ «как это называется
в `incident-manager-server`» ↔ «как это было в legacy `IM/`».

| Понятие | DSL v1 | Сервер | Legacy `IM/` |
| --- | --- | --- | --- |
| Сценарий обработки | `Scenario` | `scenarios` (table) / `scenario` (API) | один из `control_logic` в `Msg` |
| Тело сценария (этот документ) | `script` | `scenarios.script jsonb` | разрозненные ключи `Msg` |
| Триггер срабатывания | (вне DSL) | `incidentRule` + `incidentRuleCondition` | `EventSettings`, `OBJS.*` |
| Связь триггер ↔ сценарий | (вне DSL) | `incident_rule_scenarios` (m2m) | implicit |
| Запущенный инстанс | `Incident` | `incidents` | `EventData` |
| Снапшот сценария в инстансе | (тот же `script`) | `incidents.scenario jsonb` | копия `EventData.CtrlLogics` |
| Прохождение оператора | `scenarioResult` | `incidents.scenarioResult jsonb` | `EventData.Works[]` |
| Шаг сценария | `Step` | (внутри `script`) | строка в `CTRLS.*.{i}` |
| Тип шага | `step.type` | (внутри `script`) | `control_type` |
| Опция выбора | `option` | (внутри `script`) | `radio.name.{j}`, `combo.content.{j}` |
| Стабильный id опции | `option.id` | (внутри `script`) | **отсутствует** (использовался индекс) |
| Условный переход | `transitions.rules[].when` | (внутри `script`) | `logic.{i}.item{j}` matrix |
| Эффект на переходе | `actions[]` | (внутри `script`) | `macro.{i}`, `is_finish`, `is_report` |
| Финал сценария | `actions: [{type: "finish"}]` | (внутри `script`) | `is_finish=1` |
| Вызов MACRO | `actions: [{type: "callMacro", args: {macroId}}]` | (внутри `script`) | `macro.{i}` |
| Эскалация | `actions: [{type: "escalate"}]` | API `/Escalate` | API `/Escalate` |
| Назначение | `actions: [{type: "assign", args: {to}}]` | API `/Assign` | API `/Assign` |
| Текущее значение шага | `scenarioResult.state[stepId].value` | (внутри `scenarioResult`) | derived из `Works` |
| Журнал действий | `scenarioResult.history[]` | (внутри `scenarioResult`) | сами `Works` |
| Журнал статуса инцидента | (вне DSL) | `incident_activities` | partial |
| Жизненный цикл инцидента | (вне DSL) | `statuses` + `incident_action_transitions` | hardcoded |

**Принцип именования:** где сервер уже задал имя — берём его. Где имени нет
(потому что сервер про это не знает) — выбираем своё.

---

## 3. Что НЕ в DSL

Явный список вещей, которые **не** должны попадать в `script`. Если кто-то
в будущем захочет туда что-то из этого добавить — это тревожный звонок,
архитектурное решение требует пересмотра.

| Вне DSL | Где живёт | Почему вне |
| --- | --- | --- |
| **Триггеры** (когда запустить сценарий) | `incidentRule` + `incidentRuleCondition` | сервер уже реализовал это реляционно, m2m; см. `server-analysis.md` Расхождение №2 |
| **RBAC** (кто может что) | `incident_rule_user_group_assignments` + checks в API | DSL не знает про пользователей; принцип «schema is the contract» |
| **Multi-tenancy** | `customer_guid` во всех таблицах + filter в каждом запросе | tenant — слой выше API |
| **Жизненный цикл инцидента** (open → in_progress → closed) | `statuses` + `incident_action_transitions` | другой уровень state machine, конфигурируется отдельно от сценария |
| **Приоритеты** | `priorities` table | справочник, не часть workflow |
| **Источники событий** (camera, sensor, ...) | `sources`, `source_types`, `source_actions` | синхронизируются из Intellect, к script не относятся |
| **CSS / px / шрифты** | platform Component Registry + опциональный Theme | принцип П1 |
| **Текстовая локализация в виде словарей** | v1 — inline; v2 — `labelKey` + словарь (отдельный документ) | v1 single-language |
| **Координаты узлов в редакторе** (`x`, `y` шагов) | в редакторе на фронте, не в DSL | принцип П7; в `IM/` графа не было — преждевременная фича |

---

## 4. Корневая структура `script`

```26:74:dsl-v1-schema.json
  "type": "object",
  "required": ["dslVersion", "initialStepId", "steps"],
  "additionalProperties": false,
  "properties": {
    "dslVersion": {
      "description": "Version of THIS schema (DSL contract), not of the scenario itself. v1 = '1.0'. Used by runners to refuse unknown future versions safely.",
      "type": "string",
      "pattern": "^[0-9]+\\.[0-9]+$"
    },
    "locale": {
      "description": "BCP-47 language tag in which inline `view.label`, `options[].label` etc. are written. v1: single-language scenarios. v2 reserves `labelKey` for dictionary-based i18n.",
      "type": "string",
      "default": "ru",
      "examples": ["ru", "en"]
    },
```

### Поля корня

| Поле | Тип | Обязательное | Описание |
| --- | --- | --- | --- |
| `dslVersion` | string `"\d+.\d+"` | ✓ | версия **формата DSL**, не самого сценария. v1 — `"1.0"`. Если runner Web/iOS/Android видит major-версию выше своей — отказывается рендерить с понятной ошибкой |
| `locale` | BCP-47 string | — | язык inline-меток. По умолчанию `"ru"`. Готовится почва для v2 i18n |
| `metadata` | object | — | свободные метаданные (тэги, owner, ...), runner игнорирует |
| `initialStepId` | StepId | ✓ | id первого шага, который видит оператор |
| `steps` | array of Step | ✓, ≥1 | все шаги сценария |
| `timers` | object | — | `escalateAfterSec`, `maxDurationSec` (см. ниже) |
| `concurrency` | object | — | `stepLockable`, `allowMultitasking` (для сервера) |

### `dslVersion` — почему это не версия сценария

Сценарий имеет **свою** версию (см. `proposal-versioning.md` про `scenarios.version`).
А `dslVersion` — это **версия контракта самого формата**, в котором написан этот
сценарий. Аналогия:

- Сценарий vN = «PDF-документ номер 5».
- `dslVersion` = «PDF спецификация версии 1.7».

Версии сценариев растут часто (после каждой правки). `dslVersion` растёт
редко (раз в несколько лет, при breaking change самого формата DSL).

### `timers`

Маппинг прямой из `IM/EventData.cs`:

| Поле | Legacy `IM/` |
| --- | --- |
| `timers.escalateAfterSec` | `escalate_time` |
| `timers.maxDurationSec` | `max_time` |

Оба — **относительные длительности** (seconds), не timestamp'ы. Абсолютные
`escalate_at`/`max_duration_at` сервер вычислит при создании Incident'а
(колонки в `incidents` уже есть для этого после миграции 005, см. `proposal-versioning.md`).

### `concurrency`

Эти флаги — **подсказки серверу**, не runtime-инструкции. Runner Web/iOS/Android
их игнорирует. Если сервер не реализует locking/multitasking — он тоже их
игнорирует, ничего не ломается.

| Поле | Legacy `IM/` |
| --- | --- |
| `concurrency.stepLockable` | `locker` |
| `concurrency.allowMultitasking` | `multitasking` |

---

## 5. Шаг (`Step`)

Каждый шаг — это узел графа сценария. У него есть `id`, `type` и платформо-независимое
описание `view`. После взаимодействия с оператором шаг порождает переход (`transitions`).

### Общие поля всех шагов

| Поле | Тип | Описание |
| --- | --- | --- |
| `id` | StepId | стабильный идентификатор; snake_case, ASCII, ≤64 |
| `type` | string enum | дискриминатор: `RadioButton` / `Checkbox` / `Select` / `Comment` / `Image` / `Datetime` / `Button` |
| `title` | Label | заголовок карточки (опционально) |
| `editable` | boolean | можно ли вернуться и поменять ответ; default `true` |
| `view` | object | специфично для типа |
| `transitions` | object | куда идти дальше |

### Почему `type` — дискриминатор, а не enum внутри одного `Step`

Каждый из 7 типов имеет **свою** форму `view`. У `RadioButton` — `options[]`,
у `Comment` — `minLength`/`maxLength`, у `Image` — `source`. Если бы они
объединялись через флаги в одном «Step», JSON Schema позволила бы написать
`{ type: "Comment", options: [...] }` — бессмыслицу. Дискриминатор + `oneOf`
гарантируют, что `view` соответствует `type`.

В формате этой проверки помогает паттерн **`oneOf`** в JSON Schema:

```108:118:dsl-v1-schema.json
    "Step": {
      "description": "Discriminated union over `type`. Each variant defines its own `view` shape.",
      "oneOf": [
        { "$ref": "#/$defs/RadioButtonStep" },
        { "$ref": "#/$defs/CheckboxStep" },
        { "$ref": "#/$defs/SelectStep" },
        { "$ref": "#/$defs/CommentStep" },
        { "$ref": "#/$defs/ImageStep" },
        { "$ref": "#/$defs/DatetimeStep" },
        { "$ref": "#/$defs/ButtonStep" }
      ]
    },
```

---

## 6. Семь типов шагов

Семь интерактивных типов (6.1–6.7) **полностью покрывают функционал legacy
`IM/`** — оператор реально работает только с ними.

Расширение списка типов в будущем должно проходить через RFC и пересмотр с
командой сервера.

### 6.1. RadioButton

Один выбор из короткого списка (≤5 вариантов). На дольших списках
используйте [`Select`](#63-select).

```141:170:dsl-v1-schema.json
    "RadioButtonStep": {
      "description": "Single-choice from a fixed list. Operator picks exactly one option.",
      "type": "object",
      "required": ["id", "type", "view"],
      "additionalProperties": false,
      "properties": {
        "id":          { "$ref": "#/$defs/StepId" },
        "type":        { "const": "RadioButton" },
        "title":       { "$ref": "#/$defs/Label" },
        "editable":    { "type": "boolean", "default": true },
        "view": {
          "type": "object",
          "required": ["label", "options"],
          "additionalProperties": false,
          "properties": {
            "label":    { "$ref": "#/$defs/Label" },
            "options": {
              "type": "array",
              "minItems": 2,
              "items": { "$ref": "#/$defs/Option" }
            },
            "required": { "type": "boolean", "default": true,
              "description": "If true, transitions cannot fire until the operator has selected something." },
            "layout":   { "type": "string", "enum": ["vertical", "horizontal"], "default": "vertical",
              "description": "Hint to the runner. Native platforms (iOS/Android) may ignore." }
          }
        },
        "transitions": { "$ref": "#/$defs/Transitions" }
      }
    },
```

**Пример:**
```json
{
  "id": "fire_detected",
  "type": "RadioButton",
  "view": {
    "label": "Подтвердите тип события",
    "options": [
      { "id": "fire",        "label": "Пожар" },
      { "id": "false_alarm", "label": "Ложное срабатывание" },
      { "id": "test",        "label": "Учения / тест" }
    ],
    "required": true
  },
  "transitions": {
    "rules": [
      { "when": { "==": [ {"var": "state.fire_detected.value"}, "fire" ] },
        "goto": "fire_protocol" },
      { "when": { "==": [ {"var": "state.fire_detected.value"}, "false_alarm" ] },
        "goto": "close",
        "actions": [ { "type": "finish", "args": { "resolution": "false_alarm" } } ] }
    ],
    "default": { "goto": "close" }
  }
}
```

**Что хранится в `scenarioResult.state` после ответа:**
```json
{ "fire_detected": { "value": "fire", "answeredAt": "2026-04-29T08:30:12Z" } }
```

Заметь: хранится `option.id`, не индекс. Это устраняет проблему legacy
`IM/`, где удаление опции сдвигало все условия.

**Маппинг с `IM/`:**
- `radio.name.{j}` → `view.options[j].label`;
- индекс `j` → стабильный `view.options[j].id`;
- `logic.{i}.item{j}` → JSONLogic выражение в `transitions.rules[].when`.

### 6.2. Checkbox

Множественный выбор из фиксированного списка.

```172:202:dsl-v1-schema.json
    "CheckboxStep": {
      "description": "Multi-choice from a fixed list. Operator picks zero or more options.",
      "type": "object",
      "required": ["id", "type", "view"],
      "additionalProperties": false,
      "properties": {
        "id":       { "$ref": "#/$defs/StepId" },
        "type":     { "const": "Checkbox" },
        "title":    { "$ref": "#/$defs/Label" },
        "editable": { "type": "boolean", "default": true },
        "view": {
          "type": "object",
          "required": ["label", "options"],
          "additionalProperties": false,
          "properties": {
            "label":    { "$ref": "#/$defs/Label" },
            "options": {
              "type": "array",
              "minItems": 1,
              "items": { "$ref": "#/$defs/Option" }
            },
            "required": { "type": "boolean", "default": false,
              "description": "If true, at least one option must be selected." },
            "minSelected": { "type": "integer", "minimum": 0, "default": 0 },
            "maxSelected": { "type": "integer", "minimum": 1 },
            "layout":   { "type": "string", "enum": ["vertical", "horizontal"], "default": "vertical" }
          }
        },
        "transitions": { "$ref": "#/$defs/Transitions" }
      }
    },
```

**Что хранится в `scenarioResult.state`:** массив id'шников.
```json
{ "damages": { "value": ["broken_window", "smoke"] } }
```

**Условия в JSONLogic** — через оператор `in`:
```json
{ "in": [ "broken_window", { "var": "state.damages.value" } ] }
```

### 6.3. Select

Один выбор из длинного списка (>5 вариантов), рендерится как dropdown / picker.

```204:230:dsl-v1-schema.json
    "SelectStep": {
      "description": "Single-choice from a long list, rendered as a dropdown / picker. Use RadioButton for short lists (<= 5).",
      "type": "object",
      "required": ["id", "type", "view"],
      "additionalProperties": false,
      "properties": {
        "id":       { "$ref": "#/$defs/StepId" },
        "type":     { "const": "Select" },
        "title":    { "$ref": "#/$defs/Label" },
        "editable": { "type": "boolean", "default": true },
        "view": {
          "type": "object",
          "required": ["label", "options"],
          "additionalProperties": false,
          "properties": {
            "label":       { "$ref": "#/$defs/Label" },
            "placeholder": { "type": "string" },
            "options": {
              "type": "array",
              "minItems": 2,
              "items": { "$ref": "#/$defs/Option" }
            },
            "required": { "type": "boolean", "default": true }
          }
        },
        "transitions": { "$ref": "#/$defs/Transitions" }
      }
    },
```

**Почему отдельный тип, а не флаг на `RadioButton`?** На iOS `Radio` обычно
рендерится как список с галочками, `Select` — как picker. Это **разные**
нативные паттерны. На Web — `<input type="radio">` vs `<select>`. Объединять
через флаг — заставлять каждую платформу делать `switch` внутри одного
компонента, что замедляет онбординг новых разработчиков и плодит баги.

### 6.4. Comment

Свободный текстовый ввод.

```232:262:dsl-v1-schema.json
    "CommentStep": {
      "description": "Free-form text input. Maps to legacy IM/ Helper_comment.",
      "type": "object",
      "required": ["id", "type", "view"],
      "additionalProperties": false,
      "properties": {
        "id":       { "$ref": "#/$defs/StepId" },
        "type":     { "const": "Comment" },
        "title":    { "$ref": "#/$defs/Label" },
        "editable": { "type": "boolean", "default": true },
        "view": {
          "type": "object",
          "required": ["label"],
          "additionalProperties": false,
          "properties": {
            "label":       { "$ref": "#/$defs/Label" },
            "placeholder": { "type": "string" },
            "required":    { "type": "boolean", "default": false,
              "description": "Maps to legacy IM/ `mandatory_comment`." },
            "readonly":    { "type": "boolean", "default": false,
              "description": "Step is shown but cannot be edited (display-only). Maps to legacy IM/ `read_only`." },
            "minLength":   { "type": "integer", "minimum": 0, "default": 0,
              "description": "Minimum number of characters." },
            "maxLength":   { "type": "integer", "minimum": 1,
              "description": "Maximum number of characters." },
            "minRows":     { "type": "integer", "minimum": 1, "default": 1,
              "description": "Hint for input height in lines. Distinct from minLength (chars). Maps to legacy IM/ `min_height` (one of its meanings)." },
            "maxRows":     { "type": "integer", "minimum": 1 }
          }
        },
        "transitions": { "$ref": "#/$defs/Transitions" }
      }
    },
```

**Маппинг с `IM/` `Helper_comment`:**

| `IM/` | DSL v1 | Комментарий |
| --- | --- | --- |
| `edit_text` | `view.label` | подпись |
| `mandatory_comment` | `view.required` | переименовано в стандарт HTML |
| `read_only` | `view.readonly` | переименовано в стандарт HTML |
| `min_height` (px) | `view.minRows` (lines) | в `IM/` это поле использовалось для двух разных смыслов; **разделили** на `minRows` (высота поля) и `minLength` (длина текста) |
| `max_height` | `view.maxRows` | то же |
| (отсутствовало) | `view.minLength`, `view.maxLength` | новое: ограничение **длины текста** в символах |

### 6.5. Image

Прикрепление изображения. Источник определяется в DSL семантически, **как
именно** оператор выбирает камеру/файл — забота platform runner'а.

```264:303:dsl-v1-schema.json
    "ImageStep": {
      "description": "Image attachment(s). Source determines where the image comes from. Picker UX is the runner's responsibility.",
      "type": "object",
      "required": ["id", "type", "view"],
      "additionalProperties": false,
      "properties": {
        "id":       { "$ref": "#/$defs/StepId" },
        "type":     { "const": "Image" },
        "title":    { "$ref": "#/$defs/Label" },
        "editable": { "type": "boolean", "default": true },
        "view": {
          "type": "object",
          "required": ["label", "source"],
          "additionalProperties": false,
          "properties": {
            "label": { "$ref": "#/$defs/Label" },
            "source": {
              "type": "string",
              "enum": ["camera", "map", "operator", "fixed"],
              "description": "camera = snapshot from a configured camera; map = screenshot of the map at the incident location; operator = uploaded by operator (paste/file); fixed = pre-attached at design time. Maps to legacy IM/ `img_type` (0/1/2/3 numeric enum, replaced by names)."
            },
            "fixedSrc": {
              "type": "string",
              "format": "uri",
              "description": "Required when source = `fixed`. URL of the pre-attached image."
            },
            "allowMultiple": {
              "type": "boolean",
              "default": false,
              "description": "If true, operator may attach several images. Maps to UserControlImage._images list in IM/."
            },
            "required": { "type": "boolean", "default": false }
          },
          "allOf": [
            {
              "if":   { "properties": { "source": { "const": "fixed" } } },
              "then": { "required": ["fixedSrc"] }
            }
          ]
        },
        "transitions": { "$ref": "#/$defs/Transitions" }
      }
    },
```

**Маппинг с `IM/` `Helper_image`:** числовой enum `img_type=0|1|2|3` заменён
на семантические имена. `0=camera, 1=map, 2=operator, 3=fixed`. Также
`allowMultiple` — это формализация существующей логики `_images[]` из
`UserControlImage.cs`.

**Что хранится в `scenarioResult.state`:** массив id'шников attachments
(метаданные attachments — отдельная таблица `scenario_attachments`, см.
`market-research.md` Q4 / разговор про БД-схему). Сами файлы в blob-store.

```json
{ "scene_photo": { "value": ["att-uuid-1", "att-uuid-2"] } }
```

### 6.6. Datetime

Выбор даты, времени или того и другого.

```305:329:dsl-v1-schema.json
    "DatetimeStep": {
      "description": "Date and/or time picker. Maps to legacy IM/ Helper_datetime.",
      "type": "object",
      "required": ["id", "type", "view"],
      "additionalProperties": false,
      "properties": {
        "id":       { "$ref": "#/$defs/StepId" },
        "type":     { "const": "Datetime" },
        "title":    { "$ref": "#/$defs/Label" },
        "editable": { "type": "boolean", "default": true },
        "view": {
          "type": "object",
          "required": ["label", "kind"],
          "additionalProperties": false,
          "properties": {
            "label":   { "$ref": "#/$defs/Label" },
            "kind": {
              "type": "string",
              "enum": ["date", "time", "datetime"],
              "description": "Maps to legacy IM/ `datetime_type` (0/1/2 numeric enum, replaced by names)."
            },
            "required": { "type": "boolean", "default": true },
            "min":      { "type": "string", "description": "ISO-8601 lower bound. Format depends on `kind`." },
            "max":      { "type": "string", "description": "ISO-8601 upper bound. Format depends on `kind`." }
          }
        },
        "transitions": { "$ref": "#/$defs/Transitions" }
      }
    },
```

**Маппинг с `IM/` `Helper_datetime`:** числовой `datetime_type=0|1|2` заменён
на `kind: "date" | "time" | "datetime"`.

**Что хранится в `scenarioResult.state`:** ISO-8601 строка соответствующего
`kind`:

| `kind` | Формат |
| --- | --- |
| `date` | `"2026-04-29"` |
| `time` | `"14:30:00"` |
| `datetime` | `"2026-04-29T14:30:00+03:00"` |

### 6.7. Button

Кнопка-действие. У кнопки **нет собственного значения** — нажатие просто
запускает `transitions`.

```331:351:dsl-v1-schema.json
    "ButtonStep": {
      "description": "Action button. Has no answer value of its own — pressing the button triggers transitions. Maps to legacy IM/ Helper_button (with `is_finish` / `is_report` replaced by explicit Actions on the transition).",
      "type": "object",
      "required": ["id", "type", "view"],
      "additionalProperties": false,
      "properties": {
        "id":       { "$ref": "#/$defs/StepId" },
        "type":     { "const": "Button" },
        "title":    { "$ref": "#/$defs/Label" },
        "editable": { "type": "boolean", "default": true },
        "view": {
          "type": "object",
          "required": ["label"],
          "additionalProperties": false,
          "properties": {
            "label":    { "$ref": "#/$defs/Label" },
            "emphasis": { "type": "string", "enum": ["primary", "secondary", "destructive"], "default": "primary" }
          }
        },
        "transitions": { "$ref": "#/$defs/Transitions" }
      }
    },
```

**Маппинг с `IM/` `Helper_button`:** флаги `is_finish` и `is_report` **полностью
выкинуты** из шага. Эффекты выражаются через `actions[]` на переходе:

```jsonc
{
  "id": "btn_close",
  "type": "Button",
  "view": { "label": "Закрыть инцидент", "emphasis": "primary" },
  "transitions": {
    "default": {
      "actions": [
        { "type": "generateReport" },
        { "type": "finish", "args": { "resolution": "processed" } }
      ]
    }
  }
}
```

Это даёт расширяемость: нужен новый эффект — добавляешь action в Registry
платформы, не трогая схему DSL. И один и тот же `Button` может в одном
сценарии быть финальным, в другом — нет.

---

## 7. Условные переходы (`transitions` + JSONLogic)

### Семантика first-match

```353:366:dsl-v1-schema.json
    "Transitions": {
      "description": "What happens after the operator finishes interacting with this step. First-match semantics: rules are evaluated top-to-bottom, the first whose `when` is truthy wins. If none match, `default` fires.",
      "type": "object",
      "required": ["default"],
      "additionalProperties": false,
      "properties": {
        "rules": {
          "type": "array",
          "items": { "$ref": "#/$defs/Rule" }
        },
        "default": { "$ref": "#/$defs/RuleOutcome" }
      }
    },
```

**Алгоритм** (это **строго** так, не «один из режимов»):

```pseudo
for rule in transitions.rules:
    if jsonlogic.apply(rule.when, { state: scenarioResult.state }):
        execute(rule.actions ?? [])
        navigateTo(rule.goto)         # null = stay
        return
# ни одно правило не сработало:
execute(transitions.default.actions ?? [])
navigateTo(transitions.default.goto)
```

Это совпадает с поведением `CtrlLogic.GetGoToByLogic` в `IM/Inc_server/run/Entites/CtrlLogic.cs`:
первое сработавшее правило выигрывает, иначе `default_goto`. Никаких
параллельных веток (BPMN-style fork) на v1.

### Структура правила

```368:386:dsl-v1-schema.json
    "Rule": {
      "type": "object",
      "required": ["when"],
      "additionalProperties": false,
      "properties": {
        "when":    { "$ref": "#/$defs/JsonLogicExpr" },
        "goto":    { "anyOf": [ { "$ref": "#/$defs/StepId" }, { "type": "null" } ],
          "description": "Step to navigate to. `null` = stay on current step (rare, used together with side-effecting actions)." },
        "actions": {
          "type": "array",
          "items": { "$ref": "#/$defs/Action" },
          "description": "Optional side effects executed when this rule fires (in array order, sequentially)."
        }
      },
      "anyOf": [
        { "required": ["goto"] },
        { "required": ["actions"] }
      ]
    },
```

Правило **обязано** иметь либо `goto`, либо `actions[]` (а лучше оба).
Чисто декоративное правило `{ when: ..., }` без эффектов запрещено.

### Whitelist JSONLogic-операторов

В DSL v1 разрешены **следующие** операторы JSONLogic:

| Категория | Операторы | Пример |
| --- | --- | --- |
| Доступ к данным | `var` | `{"var": "state.severity.value"}` |
| Сравнение | `==`, `!=`, `>`, `>=`, `<`, `<=` | `{"==": [{"var": "state.s.value"}, "high"]}` |
| Логика | `and`, `or`, `!` | `{"and": [...]}` |
| Условный | `if` | `{"if": [cond, then, else]}` |
| Массивы | `in`, `none`, `some`, `all` | `{"in": ["fire", {"var": "state.damages.value"}]}` |
| Отсутствие данных | `missing`, `missing_some` | `{"missing": ["state.severity.value"]}` |

**Не разрешены в v1:**
- кастомные операторы (`step_equals`, `is_email` и подобные) — потребуют
  реализации на 3 платформах, что противоречит П3;
- арифметика (`+`, `-`, `*`, `/`) — кейсов нет, добавим если появятся;
- работа со строками (`cat`, `substr`) — то же;
- мутации (`merge`) — JSONLogic не должен менять состояние, только читать.

Если кейс действительно требует расширения whitelist'а — это RFC, не
бесшумная правка.

### Доступные данные в `var`

JSONLogic вычисляется в контексте, **который содержит только `state`**:

```jsonc
{
  "state": {
    "<stepId>": { "value": <значение>, "answeredAt": "<ts>", "by": "<userId>" },
    ...
  }
}
```

Базовые пути:
- `state.<stepId>.value` — основное;
- `state.<stepId>.answeredAt` — для условий «если ответили в течение N секунд»;
- `state.<stepId>.by` — для условий с привязкой к оператору, если runner это поле заполнил.

**Намеренно не прокидываются** в v1: `incident.*` (id, priority, createdAt),
`operator.*` (id), `metadata`, `incidentRule`, `customer`. Причина: эти поля
живут вне scope сценария — приходят от сервера в момент запуска инцидента,
их доставка является частью **wire-protocol'а** runner ↔ сервер, который
в v1 **намеренно не специфицирован** (отдельный proposal). Без определённого
протокола обещание «`incident.priority` доступен в JSONLogic» нельзя
выполнить одинаково на трёх платформах. Чтобы не давать обещаний,
которые не можем гарантировать, контекст в v1 заведомо узкий и полностью
покрывается данными, которые runner накапливает сам в `state`.

Если сценарию нужно ветвление по приоритету или метаданным инцидента —
сервер должен **прокинуть это значение в стартовое `state`** при создании
инцидента (например, шаг `incident_priority` с `editable: false` и
предзаполненным `state[incident_priority].value`). Этот паттерн будет
зафиксирован вместе с wire-protocol'ом в v2.

**Расширение контекста в v2** (см. §12) — это совместимое изменение:
добавление новых корневых ключей в контекст не ломает существующие
сценарии, использующие только `state.*`.

### Семантика `goto`

| Значение | Эффект |
| --- | --- |
| `"some_step_id"` | перейти на этот шаг |
| `null` | остаться на текущем (редко, обычно вместе с `actions`) |
| отсутствует (в `rules[]`) | нельзя; правило обязано иметь либо `goto`, либо `actions[]` |
| отсутствует (в `default`) | разрешено **только** если `actions[]` содержит `{type: "finish"}` — см. ниже |

Финал сценария = `actions: [{type: "finish"}]`. Шаг **не** имеет «терминального
флага» (см. П3).

### Завершение сценария — единственный путь

Сценарий завершается **только** через явный `{type: "finish"}` в `actions`.
Это правило закреплено в JSON Schema через `DefaultOutcome`: ветка `default`
обязана удовлетворять одному из двух условий:

| Случай | Что разрешено |
| --- | --- |
| (a) переход на следующий шаг | `goto` присутствует (любая `StepId` или `null`) |
| (b) явное завершение | `goto` отсутствует **и** `actions[]` содержит хотя бы один объект `{type: "finish"}` |

**Запрещено** иметь `default: { actions: [...] }` без `finish` и без `goto` —
это «зависший конец», когда сценарий ни идёт дальше, ни завершается.
Такая структура отвергается схемой при валидации; конструктор обязан её
ловить до сохранения.

Зачем это правило: без него возникал «третий тихий режим», когда runner
доходил до `default` без `goto`, не выполнял `finish` и оставлял
`scenarioResult.completedAt = null` — инцидент висел открытым. Web/iOS/Android
runner'ы реализовывали бы это поведение по-разному, и контракт расходился
бы между платформами. Явное правило закрывает эту неоднозначность на
уровне схемы.

> **Замечание для `Rule`** (не для `default`): отдельные правила в
> `transitions.rules[]` могут иметь `actions` без `finish` и без `goto` —
> это валидно для side-effecting'а (например, «при определённом ответе
> вызвать MACRO и остаться на шаге»). Строгое требование `finish-or-goto`
> относится только к `default`-ветке, потому что именно она — последний
> резерв вычисления переходов и единственное место, где сценарий должен
> гарантированно куда-то прийти.

---

## 8. Действия (`actions`)

5 типов в v1, **полностью покрывают функционал `IM/`**.

```401:411:dsl-v1-schema.json
    "Action": {
      "description": "Side effect on a transition. Discriminated union over `type`. Unknown types are ignored by the runner with a warning (Airbnb GP convention).",
      "oneOf": [
        { "$ref": "#/$defs/CallMacroAction" },
        { "$ref": "#/$defs/FinishAction" },
        { "$ref": "#/$defs/GenerateReportAction" },
        { "$ref": "#/$defs/EscalateAction" },
        { "$ref": "#/$defs/AssignAction" }
      ]
    },
```

### `callMacro`

Вызов Intellect MACRO по id. Прямой маппинг с `IM/` `macro.{i}`.

```jsonc
{ "type": "callMacro", "args": { "macroId": "MACRO_FIRE_ALARM", "params": { "severity": "high" } } }
```

`params` — свободный объект; контракт MACRO определяется на стороне Intellect,
не в DSL.

### `finish`

Закрывает Incident. Replaces `IM/` `is_finish=1`.

```jsonc
{ "type": "finish", "args": { "resolution": "processed" } }
```

`resolution` — опциональный код. Сервер мапит на свой `statuses.code`. Если
оставить пустым — сервер выбирает по умолчанию (например, `closed`).

### `generateReport`

Генерация отчёта. Replaces `IM/` `is_report=1`.

```jsonc
{ "type": "generateReport", "args": { "templateId": "fire_incident_report" } }
```

`templateId` — опционально; если не указан, сервер выбирает шаблон по умолчанию
для типа инцидента.

### `escalate`

Эскалация. Маппится на API `/Escalate` (которое уже есть в legacy `IM/`).

```jsonc
{ "type": "escalate", "args": { "to": "operator-007", "reason": "после рабочих часов" } }
```

Без `to` — сервер применяет своё routing. С `to` — конкретный оператор/группа.

### `assign`

Переназначение оператора. Маппится на API `/Assign`.

```jsonc
{ "type": "assign", "args": { "to": "operator-shift-supervisor" } }
```

### Цепочки

`actions` — **массив**, не одно действие. Выполняются **последовательно, в
порядке записи**:

```jsonc
"actions": [
  { "type": "callMacro", "args": { "macroId": "MACRO_LOCK_DOORS" } },
  { "type": "callMacro", "args": { "macroId": "MACRO_NOTIFY_GUARD" } },
  { "type": "generateReport" },
  { "type": "finish", "args": { "resolution": "processed" } }
]
```

Если шаг middle падает (например, MACRO не отвечает) — поведение зависит
от реализации runner'а. **На v1 рекомендация:** runner логирует ошибку,
продолжает выполнять остальные actions, не блокирует переход. Альтернатива
«fail-fast» — обсуждаемая, но в v1 не блокирует.

### Расширение: добавление нового action type

Добавление action **не требует** правки JSON Schema этого DSL (только
описывает 5 встроенных). Action Registry на каждой платформе позволяет
добавлять кастомные:

```typescript
// Web Runner
actionRegistry.register('sendEmail', (args, ctx) => {
  return ctx.api.sendEmail(args.to, args.subject, args.body);
});
```

При этом:
- сервер про новый action **может** не знать (если эффект чисто клиентский);
- старые runner'ы (без `sendEmail` handler'а) — **игнорируют** action с
  warning'ом (П8);
- если хотим жёсткое требование «runner должен поддерживать» — добавляем
  в action `{required: true}` (это будет в v2, в v1 не реализовано).

---

## 9. Прохождение оператора (`scenarioResult`)

Этот документ хранится в `incidents.scenarioResult jsonb` сервера.
**Сервер про его структуру не знает** (`type: object` в OpenAPI, см.
`server-analysis.md` §4.1). Структуру задаёт **этот DSL**.

### Структура

```jsonc
{
  "dslVersion": "1.0",

  "state": {
    "<stepId>": {
      "value": <значение>,                  // тип зависит от типа шага
      "answeredAt": "2026-04-29T08:30:12Z",
      "by": "operator-uuid"
    },
    ...
  },

  "history": [
    {
      "ts": "2026-04-29T08:30:01Z",
      "stepId": "fire_detected",
      "action": "answer",
      "value": "fire",
      "by": "operator-uuid"
    },
    {
      "ts": "2026-04-29T08:30:01Z",
      "stepId": "fire_detected",
      "action": "transition",
      "to": "fire_protocol",
      "matchedRule": 0
    },
    ...
  ],

  "currentStepId": "fire_protocol",

  "completedAt": null
}
```

### Поля верхнего уровня

| Поле | Назначение |
| --- | --- |
| `dslVersion` | версия DSL, которой соответствует этот результат |
| `state` | **последнее значение** каждого пройденного шага (Map by stepId) |
| `history` | **append-only журнал** всех действий (Array) |
| `attachments` | side-таблица бинарных вложений, на которые ссылается `state` шагов типа `Image` (опционально, отсутствует если в сценарии не было ни одного `Image`-шага) |
| `currentStepId` | где сейчас стоит «токен» (null если завершён) |
| `completedAt` | timestamp финиша (null если в процессе) |

### Структура `state[stepId]` (StepEntry)

| Поле | Тип | Обязательное | Описание |
| --- | --- | --- | --- |
| `value` | depends on step type | ✓ | Канонизированное значение (см. таблицу ниже). Для пропущенного шага — `null` |
| `answeredAt` | ISO-8601 | ✓ | Когда оператор закрыл шаг (ответил или пропустил). UTC рекомендуется |
| `by` | string \| null | — | Идентификатор оператора. Заполняется runner'ом, если он знает (после wire-protocol'а — обязательно) |
| `skipped` | boolean | — | `true`, если оператор закрыл шаг **без** ответа. Допустимо только для шагов с `view.required: false`. См. ниже |

### Семантика «пропущенного шага» (skip)

Поле `skipped` различает три состояния шага в `state`:

| Состояние шага | Что в `state[stepId]` | Когда |
| --- | --- | --- |
| Не достигнут | **ключ отсутствует** в `state` | оператор ещё не дошёл до этого шага |
| Пройден с ответом | `{ value: <ответ>, answeredAt, by }` | оператор ответил |
| Пройден без ответа (skip) | `{ value: null, answeredAt, by, skipped: true }` | оператор нажал «Пропустить» на шаге с `view.required: false` |

Эти три случая **не эквивалентны** для JSONLogic:

```jsonc
{"missing": ["state.optional_comment.value"]}     // true только в первом случае (ключ отсутствует)
{"==": [{"var": "state.optional_comment.value"}, null]}  // true для skip и для отсутствия
{"var": "state.optional_comment.skipped"}         // true только для случая skip
```

Различие важно при ветвлении: «если оператор **сознательно пропустил** —
эскалировать» — это `skipped: true`, а не просто `value === null`.

**Правила записи:**

- Если `view.required: false` и оператор нажал «Пропустить» — runner записывает
  `{ value: null, answeredAt: <ts>, by: <userId>, skipped: true }`.
  В `history` появляется событие `{ ts, stepId, action: "skip", by }` —
  отдельный action-тип, не `answer`.
- Если `view.required: true` — UI runner'а **не должен** показывать «Пропустить».
  Если каким-то образом submit пришёл с `skipped: true` для required-шага,
  runner отвергает его и оставляет шаг текущим.
- Поле `skipped` **не указывается** для шагов, на которые ответили (даже если
  ответ — пустая строка / пустой массив; пустота ≠ skip).

Без явного поля `skipped` различение «не дошли» vs «прошли молча» было бы
невозможно, и три runner'а делали бы это по-разному (одни писали бы пустую
строку, другие — `null`, третьи вообще не записывали ключ). Это закрывает
неоднозначность на уровне формата.

### Соответствие тип шага → тип `state[stepId].value`

| Тип шага | Тип `value` | Пример |
| --- | --- | --- |
| RadioButton | string (option.id) | `"fire"` |
| Checkbox | array of string (option.id) | `["broken_window", "smoke"]` |
| Select | string (option.id) | `"region_north"` |
| Comment | string (текст оператора) | `"Прибыли пожарные..."` |
| Image | array of string (attachment id) | `["att-uuid-1"]` |
| Datetime | ISO-8601 string | `"2026-04-29T14:30:00Z"` |
| Button | `null` (у кнопки нет значения) | `null` |

### Side-таблица `attachments`

`Image`-шаг хранит в `state[stepId].value` только **идентификаторы** вложений
(`["att-uuid-1", "att-uuid-2"]`), а сами бинарные данные лежат в
`scenarioResult.attachments[]`. Это сделано намеренно:

- `state` остаётся компактным и сравнимым на равенство (для JSONLogic, логов,
  diff-ов), не зависимо от размера прикреплённых файлов;
- большие BLOB'ы (фото с камеры, скриншоты) не раздувают индексные структуры
  `state` и не мешают версионному хранению;
- одно и то же вложение можно ссылать из нескольких шагов (редко, но
  бесплатно), а также можно хранить файлы в S3/MinIO и заменять `dataBase64`
  на `url`, не трогая формат `state` (см. ниже про `storage`).

| Поле | Назначение |
| --- | --- |
| `id` | стабильный идентификатор вложения (UUID); тот же id появляется в `state[stepId].value` |
| `stepId` | id шага типа `Image`, к которому это вложение относится |
| `source` | значение `view.source` шага в момент загрузки: `camera` / `map` / `operator` / `fixed` |
| `mime` | MIME-тип (`image/jpeg`, `image/png`, …) |
| `fileName` | оригинальное имя файла (если известно) |
| `size` | размер в байтах |
| `sha256` | хеш бинарного содержимого (для дедупликации/целостности; опционально) |
| `capturedAt` | ISO-8601 timestamp загрузки |
| `dataBase64` | бинарное содержимое, base64-кодированное; используется в демо-runner'е и в self-contained экспортах. На сервере обычно отсутствует — заменяется на `storage` |
| `storage` | альтернатива `dataBase64`: `{ kind: "s3", bucket, key }` или `{ kind: "url", url }`. На сервере хранение через S3/MinIO/CDN; runner получает `url` и грузит ленивым образом |

В одном `attachment'е` присутствует **либо** `dataBase64`, **либо** `storage` —
не оба. На v1 сервер сам решает, где хранить (политика хранения — вне DSL).

**Демо-runner всегда использует `dataBase64`** — это делает экспортированный
`ResultEnvelope` полностью самодостаточным (можно открыть на любой машине,
без сервера, и увидеть все картинки).

**Пример:**

```json
"state": {
  "perimeter_photo": {
    "value": ["att-1f3c"],
    "answeredAt": "2026-04-29T14:32:11Z"
  }
},
"attachments": [
  {
    "id": "att-1f3c",
    "stepId": "perimeter_photo",
    "source": "operator",
    "mime": "image/jpeg",
    "fileName": "fence.jpg",
    "size": 184320,
    "capturedAt": "2026-04-29T14:32:08Z",
    "dataBase64": "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAA…"
  }
]
```

### Семантика `history`

| `action` | Дополнительные поля | Когда |
| --- | --- | --- |
| `answer` | `value` | оператор ответил на шаг (или поменял ответ) |
| `skip` | (нет) | оператор закрыл шаг без ответа (только для `view.required: false`) — см. выше «Семантика skip» |
| `transition` | `to`, `matchedRule` (индекс или `null` для default) | переход между шагами |
| `callMacro` | `macroId`, `params` (опц.) | сработал `CallMacroAction` |
| `generateReport` | `templateId` (опц.) | сработал `GenerateReportAction` |
| `escalate` | `to` (опц.), `reason` (опц.) | сработал `EscalateAction` или server-side эскалация по таймеру |
| `assign` | `to` | сработал `AssignAction` |
| `finish` | `resolution` (опц.) | сработал `FinishAction` |
| `timeout` | (нет) | сервер закрыл по `maxDurationSec` |

`history` **никогда не правится** — только append. Если оператор передумал
и поменял ответ — это новое событие `answer` с тем же `stepId`. История
показывает «он сначала выбрал A, потом передумал и выбрал B».

**Источник записи событий action:** все события `callMacro`,
`generateReport`, `escalate`, `assign`, `finish` записываются **runner'ом**
(фронтом) в момент срабатывания action — это **намерение**, не подтверждение
успеха выполнения на сервере. См. зафиксированное решение Р2 в §13.1.
Серверный аудит — отдельный proposal (на v1 не делаем).

### Почему два поля, а не одно

- `state` — для O(1) чтения «что сейчас выбрано», используется в JSONLogic
  и при перерисовке UI.
- `history` — для аудита и отчётов. Используется только при просмотре
  «лога инцидента», не при рендере.

Хранить **только** `history` — пришлось бы пересчитывать `state` при каждом
действии (последний `answer` для каждого `stepId`). Хранить **только**
`state` — потеряли бы аудит. Стандартный паттерн event-sourcing'а с
снапшотом.

---

## 10. Сквозной пример

Полный сценарий «пожарная сигнализация»: 4 шага, ветвление, кнопка финиша.

```jsonc
{
  "dslVersion": "1.0",
  "locale": "ru",
  "metadata": {
    "owner": "fire-safety-team",
    "tags": ["fire", "alarm"]
  },

  "initialStepId": "confirm_event",
  "timers": {
    "escalateAfterSec": 300,
    "maxDurationSec": 1800
  },
  "concurrency": {
    "stepLockable": true,
    "allowMultitasking": false
  },

  "steps": [

    {
      "id": "confirm_event",
      "type": "RadioButton",
      "title": "Подтверждение события",
      "view": {
        "label": "Подтвердите тип события на основе видео",
        "options": [
          { "id": "fire",        "label": "Пожар" },
          { "id": "false_alarm", "label": "Ложное срабатывание" },
          { "id": "test",        "label": "Учения / тест" }
        ],
        "required": true
      },
      "transitions": {
        "rules": [
          {
            "when": { "==": [ {"var": "state.confirm_event.value"}, "false_alarm" ] },
            "goto": "btn_close",
            "actions": []
          },
          {
            "when": { "==": [ {"var": "state.confirm_event.value"}, "test" ] },
            "goto": "btn_close",
            "actions": []
          }
        ],
        "default": { "goto": "scene_photo" }
      }
    },

    {
      "id": "scene_photo",
      "type": "Image",
      "title": "Фиксация обстановки",
      "view": {
        "label": "Сделайте снимок с камеры или загрузите файл",
        "source": "camera",
        "allowMultiple": true,
        "required": true
      },
      "transitions": {
        "default": { "goto": "operator_comment" }
      }
    },

    {
      "id": "operator_comment",
      "type": "Comment",
      "title": "Описание ситуации",
      "view": {
        "label": "Опишите наблюдаемую обстановку",
        "placeholder": "Например: видны языки пламени в северном крыле...",
        "required": true,
        "minLength": 20,
        "maxRows": 8
      },
      "transitions": {
        "default": {
          "goto": "btn_close",
          "actions": [
            { "type": "callMacro", "args": { "macroId": "MACRO_NOTIFY_FIRE_DEPT" } }
          ]
        }
      }
    },

    {
      "id": "btn_close",
      "type": "Button",
      "title": "Завершение",
      "view": {
        "label": "Закрыть инцидент",
        "emphasis": "primary"
      },
      "editable": false,
      "transitions": {
        "default": {
          "actions": [
            { "type": "generateReport" },
            { "type": "finish", "args": { "resolution": "processed" } }
          ]
        }
      }
    }

  ]
}
```

### Возможный `scenarioResult` после прохождения этого сценария

Оператор: подтвердил пожар, сделал 2 фото, написал комментарий, нажал
«Закрыть». Заняло 2 минуты.

```jsonc
{
  "dslVersion": "1.0",
  "currentStepId": null,
  "completedAt": "2026-04-29T08:32:18Z",

  "state": {
    "confirm_event":    { "value": "fire", "answeredAt": "2026-04-29T08:30:21Z", "by": "op-12" },
    "scene_photo":      { "value": ["att-001", "att-002"], "answeredAt": "2026-04-29T08:31:05Z", "by": "op-12" },
    "operator_comment": { "value": "Видны языки пламени в северном крыле здания. Прибыли первые пожарные.",
                          "answeredAt": "2026-04-29T08:32:10Z", "by": "op-12" },
    "btn_close":        { "value": null, "answeredAt": "2026-04-29T08:32:18Z", "by": "op-12" }
  },

  "history": [
    { "ts": "2026-04-29T08:30:21Z", "stepId": "confirm_event",    "action": "answer",         "value": "fire",                    "by": "op-12" },
    { "ts": "2026-04-29T08:30:21Z", "stepId": "confirm_event",    "action": "transition",     "to": "scene_photo",                "matchedRule": null },
    { "ts": "2026-04-29T08:31:05Z", "stepId": "scene_photo",      "action": "answer",         "value": ["att-001", "att-002"],    "by": "op-12" },
    { "ts": "2026-04-29T08:31:05Z", "stepId": "scene_photo",      "action": "transition",     "to": "operator_comment",           "matchedRule": null },
    { "ts": "2026-04-29T08:32:10Z", "stepId": "operator_comment", "action": "answer",         "value": "Видны языки...",          "by": "op-12" },
    { "ts": "2026-04-29T08:32:10Z", "stepId": "operator_comment", "action": "callMacro",      "macroId": "MACRO_NOTIFY_FIRE_DEPT" },
    { "ts": "2026-04-29T08:32:10Z", "stepId": "operator_comment", "action": "transition",     "to": "btn_close",                  "matchedRule": null },
    { "ts": "2026-04-29T08:32:18Z", "stepId": "btn_close",        "action": "answer",         "value": null,                      "by": "op-12" },
    { "ts": "2026-04-29T08:32:18Z", "stepId": "btn_close",        "action": "generateReport" },
    { "ts": "2026-04-29T08:32:18Z", "stepId": "btn_close",        "action": "finish",         "resolution": "processed" }
  ]
}
```

Заметь:
- `matchedRule: null` означает «сработал `default`», не правило из `rules[]`;
- финальный `transition` отсутствует, потому что `btn_close.transitions.default`
  не имеет `goto` — только `actions`;
- события `callMacro` и `generateReport` записаны в `history` runner'ом
  в момент срабатывания action'ов (см. зафиксированное решение Р2 в §13.1).
  Это запись **намерения**, server-side подтверждение успеха не требуется
  в v1.

---

## 11. Что валидируется и кем

### Уровень 1. JSON Schema (синтаксис)

Файл [`dsl-v1-schema.json`](./dsl-v1-schema.json) — **исполняемый артефакт**.
Может быть использован:

| Где | Чем | Когда |
| --- | --- | --- |
| **Web-конструктор** (фронт) | `ajv` | при сохранении сценария — отказывает заведомо невалидный JSON |
| **Web-runner** | (необязательно) | при загрузке сценария с сервера — sanity check |
| **Сервер Go** | `getkin/kin-openapi` (уже в `go.mod`) | в endpoint'е `POST /scenarios` — отвергает невалидное `script` |
| **Тесты** | стандартные JSON Schema validators | unit-тесты на корректность примеров |

### Уровень 2. Семантика (что схема не ловит)

JSON Schema проверяет **синтаксис**, не **семантику**. Не ловит:

- `goto: "some_step_id"` ссылается на несуществующий шаг;
- `initialStepId` ссылается на несуществующий шаг;
- цикл переходов без выхода (бесконечный loop);
- `JSONLogic.var: "state.foo.value"`, где шаг `foo` отсутствует;
- `Action.callMacro.macroId` ссылается на несуществующий MACRO в Intellect.

Эту проверку делает **Web-конструктор** при сохранении (потому что у него
есть полный контекст: список существующих сценариев, MACRO, …). Сервер
тоже **может** делать sanity-check, но это **не блокирующая** валидация —
схема могла «проехать» из старой версии конструктора.

### Уровень 3. Runtime

Runner на платформе:
- если шаг с неизвестным `type` — пропускает с warning'ом (П8);
- если action с неизвестным `type` — пропускает с warning'ом (П8);
- если JSONLogic условие падает (например, `var` не существует) — рассматривает
  как `false` (стандарт JSONLogic: short-circuit truthy/falsy);
- если ни одно правило не сработало и `default.goto` отсутствует и `actions`
  пусты — runner показывает ошибку оператору и не закрывает шаг.

---

## 12. Что отложено в v2

Эти решения **сознательно** не сделаны в v1, но место под них зарезервировано
в схеме (комментариями `description`). Это означает совместимое расширение
в будущем.

| Фича | Зачем v2 | Где зарезервировано |
| --- | --- | --- |
| **Локализация через ключи** (`labelKey` + словарь) | мульти-язык | `description` поля `Label` упоминает `labelKey` в v2 |
| **Lifecycle-actions** (`onEnter`, `onExit` шага) | автозаполнение, аналитика входа в шаг | новый раздел в `Step` |
| **Validation rules внутри шага** (например, regex для Comment) | сейчас валидация только `required`, `min/maxLength`. Для email/phone — нужно | расширение `view` |
| **Lyft Semantic Components** (сложные шаги с собственным runtime) | карты, видео-плееры, графики | новый `type: "Semantic"` |
| **Параллельные ветки (BPMN fork/join)** | если потребуется true workflow | расширение `transitions` |
| **Custom JSONLogic operators** | если whitelist станет узким | через декларацию в `script` + регистрация на платформах |
| **Migration plan между версиями сценария** | автоматизация перехода живых инцидентов | отдельный документ с маппингом |
| **`required: true` для action** (runner обязан понимать) | критичные эскалации | флаг в `Action` |
| **Editor metadata** (координаты узлов в графе) | визуальный редактор | секция `editor.layout` рядом со `script` (или в отдельной таблице) |
| **Расширение JSONLogic-контекста** (`incident.*`, `operator.*`) | ветвление по приоритету инцидента, по идентификатору оператора | в v1 контекст ограничен `state` (см. §7); расширение требует определения wire-protocol'а runner ↔ сервер, в v1 он намеренно вынесен за scope DSL |
| **`wire-protocol` (PATCH `scenarioResult` runner ↔ сервер)** | согласование как доставлять прогресс на сервер: формат запросов, идемпотентность, поведение при потере сети | в v1 не специфицирован — это API-вопрос, не DSL-вопрос; разрабатывается отдельным proposal'ом параллельно с реализацией iOS/Android-runner'ов |

---

## 13. Зафиксированные решения и оставшиеся открытые вопросы

### 13.1. Зафиксированные решения для v1

Вопросы, которые предметно обсуждались и **закрыты** в v1. Изменение этих
решений в будущем — это RFC, а не «давайте по-тихому переделаем».

#### Р1. `scenarioResult` хранится целиком в `incidents.scenarioResult jsonb`

**Решение:** оставляем как есть. **Не** выносим `history` в отдельную таблицу
`incident_scenario_events`.

**Контекст:** альтернатива — event-sourcing с per-event INSERT в отдельную
таблицу (например, `incident_scenario_events`), снапшот `state` в JSONB.
Это устраняет рост `scenarioResult` на длинных инцидентах и упрощает
аналитику (SQL по событиям).

**Почему всё-таки A:**
- На ожидаемых нагрузках (десятки шагов на инцидент, единицы исправлений
  ответов) объём `history` для одного инцидента — единицы килобайт. Это
  не проблема ни для PATCH'ей по сети, ни для PostgreSQL JSONB.
- Сервер уже умеет работать с `incidents.scenarioResult jsonb` — ничего не
  меняется. Никаких миграций.
- Соответствует принципу П7: сервер не вмешивается в содержимое.

**Когда пересматриваем (= это становится problem'ой):**
- Профайлинг показывает, что PATCH `incidents.scenarioResult` стал значимой
  долей нагрузки на сервер.
- Появляются «инциденты-долгожители» с часами/днями активной работы.
- Потребовалась SQL-аналитика по событиям (например, «сколько раз операторы
  меняли ответ на шаге X»). До этого момента — задача аналитики не стоит,
  это видно из `history` per-incident.
- Перенос механический (см. фоллбэк-вариант B в архивных версиях этого
  документа в git history) и **не** ломает контракт DSL — структура
  `scenarioResult` сохраняется, меняется только то, как сервер её хранит.

#### Р2. `callMacro` / `generateReport` логируются в `scenarioResult.history`

**Решение:** фронт пишет события `callMacro` / `generateReport` в
`scenarioResult.history` сразу после нажатия кнопки. **Не** заводим
отдельный server-side аудит-лог в v1.

**Контекст:** альтернатива — сервер при дёрганье MACRO/Report записывает
событие в `incident_activities` (которая уже существует) или в новую
таблицу. Это «правильнее» с точки зрения accountability: фронт мог послать
запрос, но не знает, **успешно** ли сервер выполнил действие.

**Почему всё-таки A:**
- В v1 нам нужна **простая прослеживаемая история действий оператора**.
  «Оператор нажал Кнопку → намерение вызвать MACRO» — это то, что нужно.
- Server-side аудит требует доработок таблиц и API сервера — выходит за
  рамки текущего scope. Если он понадобится — это отдельный proposal.
- Если MACRO упал — это видно в логах сервера и в `incident_activities`
  при изменении статуса. Двойного учёта в v1 не нужно.

**Что пишем в `history`:**

| `action` | Поля | Когда |
| --- | --- | --- |
| `callMacro` | `macroId`, `params` (опц.) | сразу при выполнении `CallMacroAction` |
| `generateReport` | `templateId` (опц.) | сразу при выполнении `GenerateReportAction` |
| `escalate` | `to` (опц.), `reason` (опц.) | сразу при выполнении `EscalateAction` |
| `assign` | `to` | сразу при выполнении `AssignAction` |
| `finish` | `resolution` (опц.) | сразу при выполнении `FinishAction` |

(см. §9 «Семантика `history`», там это уже учтено)

**Семантика "сразу":** запись в `history` происходит **до** или **параллельно**
с server-side вызовом. Это намерение, не подтверждение успеха. Если
последующий API-вызов упадёт — это отдельное событие на стороне сервера.

**Когда пересматриваем:**
- Появляется compliance-требование «доказать, что MACRO X действительно
  выполнился» — тогда нужен server-side аудит-лог. Это отдельный proposal.
- Появляется retry-семантика для actions (например, эскалация повторяется
  через N сек если не подтверждена) — тогда нужен server-side state.

#### Р3. `dslVersion` хранится только внутри `script jsonb`, не выносится в колонку

**Решение:** оставляем `dslVersion` строго полем внутри `script`. **Не**
добавляем колонку `scenarios.dsl_version`.

**Контекст:** альтернатива — отдельная колонка позволяет SQL-фильтр
`WHERE dsl_version >= '2.0'` без раскручивания JSONB.

**Почему всё-таки A:**
- В v1 версия DSL одна (`1.0`), фильтровать пока нечего.
- Колонка-дубликат значения, лежащего в JSONB, неизбежно расходится при
  правках (классическая проблема denormalized-полей). Решать через триггеры
  — лишний код.
- Соответствует принципу П7: сервер не интерпретирует содержимое `script`.
- Если потом понадобится фильтр по версии — это **read-side** оптимизация:
  можно сделать **generated column** в PostgreSQL (`GENERATED ALWAYS AS
  (script->>'dslVersion') STORED`) или индекс по выражению. Это не требует
  миграции данных, только миграции схемы.

**Когда пересматриваем:**
- Релиз DSL v2 → в БД появляются сценарии разных версий DSL.
- Нужны массовые операции «найти все сценарии на старой версии для миграции».
- В этот момент добавляется generated column или функциональный индекс.

### 13.2. Оставшиеся открытые вопросы

Эти решения **намеренно** не принимаются сейчас — для них нет достаточного
контекста или они выходят за зону ответственности DSL-команды.

#### О3. Что делать, если `dslVersion` runner'а ниже, чем у сценария

Сценарий написан для `dslVersion: "1.5"`, а старый iOS-runner знает только
`"1.0"`. Что делать?

Варианты:
- A. Runner отказывается рендерить, просит обновить app.
- B. Runner пытается отрендерить «как умеет», полагаясь на forward-compat
  через П8 (игнор неизвестных полей).
- C. Сервер при отдаче сценария **down-grade'ит** до версии runner'а
  (по client-version header'у, как Airbnb GP).

**Рекомендую A для major-mismatch'ей**, B для minor. C — отложить в v2.

**Почему пока открытый:** в v1 версия одна, проблема не возникает на
практике. Зафиксируем при первом релизе DSL v2 — там будет реальный
кейс, на котором понятнее. Сейчас принимать решение — это spec'ать
гипотетику.

#### О4. Пагинация `getScenarios`

Сейчас в OpenAPI `GET /scenarios` отдаёт **все** сценарии. На больших
проектах с сотнями сценариев — проблема. Это **не зона DSL**, но всплывёт
при разработке конструктора. Стоит обсудить с командой сервера сейчас, чтобы
не переделывать API позже.

**Почему открытый:** это API-вопрос, не DSL-вопрос. Поднимаем на ревью
с командой сервера вместе с `proposal-versioning.md`.

---

## Приложение А. Соответствие принципам из `market-research.md`

| Принцип / Q-вопрос | Реализация в DSL v1 |
| --- | --- |
| Q1. Версионирование | DSL содержит `dslVersion`; версии **сценариев** — отдельная задача (`proposal-versioning.md`) |
| Q2. Язык условий = JSONLogic | реализовано, whitelist в §7 |
| Q3. Один DSL — три рендера | принципы П1, П2, П4 + Component Registry на платформах |
| Q4. State + history | реализовано в §9 |
| Q5. Эволюция схемы | принципы П5, П7, П8 + раздел «Что отложено в v2» |
| Q6. Action-модель | реализовано в §8 |
| Q7. Граница schema/SDK | DSL описывает «что», SDK описывает «как»; явно в §3 «Что НЕ в DSL» |

