# План 87б: звук (встроенный)

> **Для агентов-исполнителей:** обязательный навык — superpowers:subagent-driven-development (рекомендуется) или superpowers:executing-plans. Шаги — чекбоксы `- [ ]`. Тест — до кода (superpowers:test-driven-development).

**Цель:** оператор слышит то, что требует действия: новый инцидент высокого приоритета, переданное ему, оповещение §9. Звук и повтор настраивает администратор во вкладке «Звук» настроек поста. «Тихо» глушит. Свёрнутая вкладка повторяет звук по графику. Звучит одна вкладка из открытых.

**Архитектура:** сервер про звук ничего не решает. Новое на сервере — только проверка раздела `sound` машины при публикации. Решение «звучать или нет» — чистая функция клиента от события потока, настроек, состояния оператора и «только важного». Её проверяют векторы (`fixtures/sound-vectors.json`), общие для прототипа и конфигуратора. Звук синтезируется Web Audio из тонов, файлов нет. Повтор ставится на часы `AudioContext` с запасом вперёд, а не на `setTimeout`. Ведущая вкладка выбирается через `navigator.locks`, команды между вкладками идут через `BroadcastChannel`.

**Спецификация:** [87-notifications.md](87-notifications.md), разделы «Звук» (§1–7), «Решения по звуку (2026-11-15)» и «Шапка — состояние поста» (строка «звук не включён»). Картинки 11–15 — [87-notifications/](87-notifications/).

**Где:**
- IM: `/mnt/hgfs/VmWareShared/soul2home/IM` — правила, машина, контракт, прототип. Проверки — по CLAUDE.md;
- сервер: `~/Work/incident-manager-server`;
- конфигуратор и экран оператора: `~/Work/incident-manager` — AGENTS.md, PROJECT.md;
- стенд: `~/Work/stand`, проверки интерфейса — `~/Work/stand/ui-check/`.

Везде ветка `feature/im_operator`.

## Общие ограничения

- **Порядок работы:** правила → `CHANGELOG.md` → машина и `openapi.json` → `python3 tools/build_workflow.py` → прототип и самопроверка → сервер → конфигуратор → стенд.
- **Логика правил живёт в машине.** В `prototype/*.js` и в коде клиента нет имён состояний и переходов (решение 151, тест `tests/operator-no-rule-names.test.ts`). Классифицировать событие можно только по полям и перечням контракта: `stateCategory`, `ownership`, `addressee`, `maintenanceWindowId`, `payload.state.from/to` (сравнивать только «равно / не равно»), `payload.addressedToMe`.
- **Поля частей «Источник и адрес» и «М1» не трогать** — их сервер делает параллельно. Это адреса устройства и группы, поле «Дежурная группа» у правила, `intake`, миграции, `IncidentSummary`, `IncidentRule*`. Звук правит в контракте только `WorkflowDefinition.sound` и новые схемы `SoundSettings`, `SoundCue`. Перед каждым коммитом — `git fetch`: если в `openapi.json`, правилах или `CHANGELOG.md` пришло чужое, подтянуть, сливать по месту и пересобрать.
- **Шапку раскладка потом переставит.** Звук встаёт в нынешнюю шапку минимально: в средний кластер `TopBar` и в шапку прототипа. Список мест, которые тронет раскладка, — в конце плана.
- `openapi.json` и `Specification/Workflow_machine/README.md` хранятся в CRLF — так и держать. После правки — `file` должен показать «CRLF».
- Сгенерированные файлы руками не правятся: `workflow.js`, `openapi.js`, `strings.js`, `SETTINGS.md`, `openapi.v30.json`, а в конфигураторе — копии в `src/operator/testing/`.
- Коммиты только локальные, без push. Сообщение начинается с «Звук: …» и кончается строкой `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. В каждом репозитории свои коммиты.
- В конце каждой задачи конфигуратора и сервера — выкладка на стенд (память «Deploy to stand before commit»), потом коммит.
- Отчёты в Telegram — по памяти «Telegram progress reports».

## Раздел машины `sound` — точная форма

```json
"sound": {
  "$comment": "раздел 21 «Звук» оператора: решает клиент по событиям потока, сервер только проверяет раздел при публикации...",
  "patterns": [
    { "id": "siren",  "labelKey": "workflow.sound.pattern.siren" },
    { "id": "alarm",  "labelKey": "workflow.sound.pattern.alarm" },
    { "id": "double", "labelKey": "workflow.sound.pattern.double" },
    { "id": "bell",   "labelKey": "workflow.sound.pattern.bell" },
    { "id": "soft",   "labelKey": "workflow.sound.pattern.soft" }
  ],
  "byPriority": {
    "100": { "pattern": "siren",  "repeat": "until_taken", "repeatSec": 15 },
    "75":  { "pattern": "double", "repeat": "once" },
    "50":  { "pattern": "soft",   "repeat": "none" },
    "25":  { "pattern": "soft",   "repeat": "none" }
  },
  "personal":  { "pattern": "bell", "repeat": "until_taken", "repeatSec": 30 },
  "alert":     { "pattern": "bell", "repeat": "once" },
  "busyHears": { "minPriority": 100, "personal": true, "alert": false },
  "muteMinutes": 5,
  "volumeFloor": 30
}
```

Что означают поля и какие значения допустимы. Эти же правила проверяют `check_machine.py` и сервер.
- **`patterns`** — каталог встроенных звуков: `id` и `labelKey`. Рецепт звука (тоны, ритм) живёт в коде клиента под тем же `id`. Каталог — модель, а не настройка: он в `adminSettings.notSettings`, патч поста его не меняет.
- **`SoundCue`** — `{ pattern, repeat, repeatSec? }`:
  - `pattern` — `id` из `patterns`;
  - `repeat` ∈ `none | once | until_taken`;
  - `repeatSec` — целое 5…300. Обязательно при `until_taken`, при других `repeat` допускается и не читается. Иначе слияние патча поверх машины ломает переключение `until_taken → once`.
- **`byPriority`** — ключ — десятичная запись целого 0…100 без ведущих нулей, значение — `SoundCue`. Уровень без своей строки берёт строку ближайшего уровня ниже: 90 → 75. Ниже самой низкой строки — без звука. `repeat: none` — без звука.
- **`personal`** — «лично вам», `SoundCue`.
- **`alert`** — оповещение §9, `SoundCue`, `repeat` ∈ `none | once`: инцидент оповещения получатель не «берёт», повторять до взятия нечего.
- **`busyHears`** — что слышит «Занят»:
  - `minPriority` — целое 0…100 или `null`; `null` значит, что по приоритету «Занят» не слышит ничего;
  - `personal`, `alert` — логические.
- **`muteMinutes`** — целое 1…60, срок «только важного».
- **`volumeFloor`** — целое 0…100, нижний порог громкости в процентах.
- Других ключей в `sound` и в `SoundCue` нет, кроме `$comment…`.

В `adminSettings`:
- `sections` дополняется `"sound"`;
- новая вкладка `{ "id": "sound", "labelKey": "workflow.settings.tab.sound", "rules": "<номер нового раздела>", "items": [...] }` встаёт **после `operator`**, «Хранение» остаётся последней из вкладок настроек;
- пункты вкладки: `sound.byPriority`, `sound.personal`, `sound.alert`, `sound.busyHears.minPriority`, `sound.busyHears.personal`, `sound.busyHears.alert`, `sound.muteMinutes`, `sound.volumeFloor`. У каждого `labelKey` / `whatKey` вида `workflow.settings.sound.<…>`;
- в `notSettings`: `{ "path": "sound.patterns", "why": "каталог встроенных звуков — рецепты в коде клиента, модель" }`.

## Функция решения — общий интерфейс

Прототип (`prototype/sound.js`, `window.IMSound`) и конфигуратор (`src/operator/sound/decide.ts`) реализуют одно и то же и проходят одни векторы:

```ts
type SoundCue = { pattern: string; repeat: 'none' | 'once' | 'until_taken'; repeatSec?: number };
type SoundKind = 'priority' | 'personal' | 'alert';
type Sounding = { guid: string; number: string; kind: SoundKind; priority: number; cue: SoundCue; since: number };
type SoundState = { sounding: Sounding[]; attention: string[] };  // attention — guid непринятых «повторяющихся» и «лично вам»
type SoundCtx = { settings: SoundSettings; agentState: 'ready'|'busy'|'not_ready'|'offline';
                  meGuid: string; onlyImportantUntil: number | null; now: number };
cueForPriority(byPriority, level: number): SoundCue | null
decideSound(state: SoundState, event: StreamEvent, ctx: SoundCtx): { state: SoundState; play: Sounding | null }
silence(state: SoundState): SoundState   // «Тихо»: sounding пуст, attention не трогается
topSounding(state: SoundState): Sounding | null   // кому звучать повтором
```

Порядок решения:
1. **Снятие.** Если событие касается инцидента из `sounding` или `attention` и инцидент больше не подходит под свой вид, он оттуда уходит. Событие при этом может быть **моим**.
   - вид `priority`: инцидент подходит, пока `stateCategory === 'pending'` и `addressee == null`;
   - вид `personal`: пока `pending` и `ownership === 'target'`;
   - `incident.access_lost` и `incident == null` снимают всегда.
2. **Своё не звучит.** Если `actor.id === meGuid`, звука нет.
3. **Вид события:**
   - `incident.created`: `pending` и `ownership === 'target'` — `personal`, это и адресация правилом М1. `pending` и `addressee == null` — `priority`;
   - `incident.transitioned`: `payload.addressedToMe` и `ownership === 'target'` и `pending` — `personal`. Если `payload.state.from !== payload.state.to`, `pending` и `addressee == null` — `priority`: «снова в очереди»;
   - `incident.alert` — `alert`;
   - остальное не звучит. Не звучит и инцидент с `maintenanceWindowId != null`, и инцидент категории `linked`.
4. **Кто слышит:**
   - `not_ready` и `offline` не слышат ничего;
   - `busy` слышит `priority`, только если `minPriority != null` и `priority ≥ minPriority`, а `personal` и `alert` — по флагам `busyHears`;
   - пока `now < onlyImportantUntil`, звучат только `priority` с `repeat: until_taken` и `personal`.
5. **Звук:** `repeat: none` — без звука и без `attention`. `until_taken` (и `personal` с ним) — запись в `sounding` и `attention`; запись по тому же `guid` заменяется. `once` — только `play`.
6. **`topSounding`:** выбирается наибольший `priority`; при равном — `personal` раньше `priority`; дальше — раньше по `since`. Повтор идёт только у верхнего, по его `repeatSec`. Одиночные звуки (`once`) играют поверх сразу.

Повтор — `planRepeats(top, startCtxTime, horizonSec=120) → number[]`: моменты на часах `AudioContext` с шагом `repeatSec` на 120 с вперёд. Расписание дополняется на каждом событии и таймером раз в 5 с. В скрытой вкладке таймер срабатывает раз в минуту — запаса в 120 с хватает. При снятии, «Тихо», перерыве и выходе запланированные узлы останавливаются (`stop(0)`, `disconnect`).

## Задачи

### Задача 1. Правила и журнал — IM
- [ ] `Specification/State_rules/States rules IM.md` (номер нового раздела в плане пишется словами «раздел 21»: `check_links.py` не знает раздела, пока его нет):
  - §8.1, строка «Уведомление адресату»: вместо «всплывающее уведомление без звука» — «всплывающее уведомление, счётчик «Мне на принятие» и звук «лично вам» (новый раздел 21)». Всплывающее уведомление раскладка потом заменит строкой блока;
  - новый **раздел 21 «Звук»**: когда звучит (таблица §1 спецификации), что не звучит, «по приоритету» по числу уровня с правилом «ближайший ниже», кто слышит (§12), «Тихо», «только важное», громкость не ниже порога, разблокировка первым нажатием и «Включить звук» с проверочным сигналом, одна вкладка, заголовок «(N) …», уведомление браузера при свёрнутой вкладке. Отдельно сказать: «Тихо» в журнал не пишется; эскалация на старшего — это «лично вам»; выключить звук совсем оператор не может;
  - §20 — абзац о вкладке «Звук»;
  - §17 — отступления прототипа: одна вкладка (у каждой вкладки прототипа свой встроенный сервер — выбирать ведущую не из чего);
  - в шапке правил — `sound` в списке разделов машины.
- [ ] `CHANGELOG.md` — строка: «§8.1, §20, §17, раздел 21 (новый): звук…». Основание: решение пользователя 2026-11-15, 87-notifications.md, «Решения по звуку». Отменяет RULE-141 (решение 2026-11-03, «звука нет нигде»; решение 165 плана 59) и снятие звука в ARCH-15.9 (2026-10-29). Хэш вписывается вторым коммитом.
- [ ] Проверка: `python3 tools/check_links.py` → 0 ошибок.
- Модель: opus. Ревью: полное — смысл правил, согласие с 87 и с §12.

### Задача 2. Машина, строки, контракт — IM
- [ ] Сначала тест: `tools/check_machine.py` — новая `check_sound(w, err)` проверяет допустимые значения из раздела выше. Ещё она проверяет, что `byPriority` задаёт строку каждому уровню эталонного справочника приоритетов. Добавить мутации в `tools/mutations/machine.json`: `repeatSec` 0, `pattern` не из каталога, ключ `"75.0"`, `alert.repeat` `until_taken`, `volumeFloor` 101. До раздела машины `check_machine.py` падает.
- [ ] `workflow_schema.v1.json` — раздел `sound` (форма выше) и `adminSettings` (вкладка, `sections`, `notSettings`).
- [ ] Строки `Specification/Workflow_machine/strings/ru.json`, `en.json`:
  - `workflow.sound.pattern.{siren,alarm,double,bell,soft}` — «Сирена», «Тревога», «Двойной сигнал», «Колокол», «Мягкий»;
  - `workflow.settings.tab.sound` — «Звук»;
  - `workflow.settings.sound.*` и `.what`;
  - `workflow.sound.repeat.{none,once,until_taken}` — «Без звука», «Один раз», «Пока не взят».
- [ ] `openapi.json` (CRLF): `components.schemas.SoundCue` и `SoundSettings`, закрытые (`additionalProperties: false`, кроме `^\$comment` через `patternProperties`). Ссылка — из `WorkflowDefinition.properties.sound`. `sound` в `required` не вносить: старый сервер без раздела по-прежнему отвечает по контракту, а клиент без раздела молчит.
- [ ] `python3 tools/build_workflow.py`. Затем быстрые проверки из CLAUDE.md и `python3 tools/check_mutations.py <новые мутации>`, `python3 tools/mutation_table.py`, `node tools/cel_vectors.mjs --update` (~6 мин, `--tmp=<scratchpad>`), `node tools/gen_quint.mjs --check`, `python3 tools/check_i18n.py`. Ожидается: всё зелёное, `SETTINGS.md` с вкладкой «Звук». Для таблиц звука может понадобиться форматтер в `tools/settings_doc.py`.
- [ ] Самопроверка и тесты API (headless Chrome, CLAUDE.md) → `pass`: контракт сверяет `GET /operator/workflow/active` с `WorkflowDefinition`.
- Модель: opus. Ревью: полное.

### Задача 3. Векторы и функция решения — IM *(конфигуратор может начать параллельно, задача 7)*
- [ ] Сначала тест: `Specification/Workflow_machine/fixtures/sound-vectors.json` — источник, правится руками. Каждый вектор — `{ name, settings?, ctx, steps: [{ event | silence | tick, expect: { play, sounding, attention } }] }`. Минимум 30 векторов:
  - уровень 90 → как 75, уровень 10 → тишина, новый уровень 100 после 75;
  - Критический повторяется → его берёт **сам оператор** (событие моё) → снят;
  - берёт коллега → снят; «Тихо» → `sounding` пуст, `attention` на месте;
  - «Занят»: Высокий молчит, Критический и «лично вам» звучат, оповещение молчит;
  - «только важное»: Высокий и оповещение молчат, повторяющиеся звучат; срок истёк → всё как обычно;
  - перерыв и выход — тишина; `access_lost`; инцидент в окне работ; `change_priority` внутри «Нового» (`from === to`) не звучит;
  - отклонён → снова в очереди → звучит; создан сразу на мою группу (М1) → `personal`;
  - два звучат → верхний по правилу `topSounding`;
  - `planRepeats` — шаг и запас вперёд.
- [ ] `prototype/sound.js` — `IMSound.{cueForPriority, decideSound, silence, topSounding, planRepeats}`, без DOM. Подключается в `index.html` перед `app.js`.
- [ ] `tools/sound_vectors.mjs` — гонит векторы через `prototype/sound.js` в `vm`; `--check` даёт код 1 при расхождении. До `sound.js` падает, после — `sound vectors: N/N`. Шаг добавить в `.github/workflows/checks.yml` рядом с `cel_vectors.mjs --check`, а в README «Проверки» и таблицу CLAUDE.md — строку про `prototype/sound.js` и `sound-vectors.json`.
- Модель: opus. Ревью: полное — векторы против таблиц 87.

### Задача 4. Прототип: синтез, шапка, меню, настройки, самопроверка — IM
- [ ] Сначала тест: шаги `prototype/selftest.js`, через `?selftest`, без слуха. Синтез идёт через адаптер `IMSound.output`, самопроверка подменяет его записью `{pattern, at}`, часы — поддельные:
  - до первого нажатия строка «Звук не включён», значок 🔇, ничего не играет;
  - «Включить звук» → одна запись проверочного сигнала;
  - событие Критического от встроенного сервера → запись `siren`; сдвиг часов на 45 с → ещё 3; «Тихо» → строка ушла, новых нет;
  - «лично вам» после передачи коллегой → `bell`, «Принять» → снято;
  - «Только важное — 5 мин» → значок 🔉, строка «Только важное до ЧЧ:ММ · Вернуть»; Высокий молчит;
  - заголовок `(1) …` при непринятом Критическом; уходит после «Взять»;
  - громкость в меню не опускается ниже `volumeFloor`;
  - вкладка «Звук» настроек: строки уровней справочника, ▶ «Прослушать» даёт запись.
- [ ] `prototype/sound.js` — синтез пяти звуков. Ритм различается, ~0,3–2 с:
  - «Сирена» — качание 600↔1200 Гц, 2 качания;
  - «Тревога» — 5 коротких по 0,1 с, 1400 Гц;
  - «Двойной сигнал» — 2 × 0,15 с, 880 Гц;
  - «Колокол» — 660 Гц с обертонами, затухание 1,5 с;
  - «Мягкий» — один 440 Гц 0,3 с.

  Ещё в `sound.js`: разблокировка (`AudioContext.resume` на первом `pointerdown` / `keydown`), расписание `planRepeats`, громкость `max(volumeFloor, выбор)`. Выбор хранится в `localStorage` `im-sound-volume`, по умолчанию 80.
- [ ] `app.js`, `index.html`, `styles.css`:
  - `onServerEvent` зовёт `decideSound` **до** выхода по «своему» переходу;
  - в шапке строка «🔊 Звучит: Критический, INC-… · Тихо»: номер прокручивает к строке, при нескольких — «Звучит: N (Критический)»;
  - строка «Звук не включён · Включить звук»;
  - значок 🔊/🔉/🔇 с меню: громкость, «Проверить звук», «Только важное — 5 мин», «Разрешить уведомления» (пока `Notification.permission === 'default'`);
  - заголовок `(N) ` + прежний заголовок;
  - уведомление браузера, когда `document.hidden`;
  - вкладка «Звук» в окне настроек: таблица уровней со звуком и повтором и ▶ «Прослушать».
- [ ] Строки интерфейса — в `i18n-ui.js` (en).
- [ ] Проверка: самопроверка `pass`, тесты API `pass`, `python3 tools/check_ui.py` (~2 мин), `python3 tools/check_i18n.py`, `node tools/sound_vectors.mjs --check`.
- Модель: sonnet. Ревью: полное.

### Задача 5. Руководство и памятки — IM
- [ ] `Specification/Operator guide.md`:
  - раздел 1 «Экран» — значок звука, «Звучит … · Тихо», «Звук не включён» и **Включить звук**, «Проверить звук», «Только важное — 5 мин» и «Вернуть», заголовок вкладки;
  - раздел 5 — у переданного вам звучит «Колокол», пока не примете или не отклоните;
  - раздел 10 — на перерыве не звучит, «Занят» слышит только важное.
- [ ] `FRONTEND.md` — раздел «Звук»: функция решения, векторы, одна вкладка, расписание Web Audio, где синтез. `BACKEND.md` — проверка `sound` при публикации. Машинный `README.md` (CRLF) — строка о разделе.
- [ ] Проверка: `python3 tools/check_guide.py`, `python3 tools/check_links.py` → 0.
- Модель: sonnet. Ревью: короткое.

### Задача 6. Сервер: проверка `sound` при публикации — сервер
- [ ] `make vendor-operator-contract` (машина, `openapi.v30.json`, строки) и `make gen-api-operator`. Если генерация затронула чужие файлы, остановиться и разобраться.
- [ ] Сначала тест: `internal/im/service/transition/core_sound_test.go` (`package transition_test`, тег `imtest` — помощник `replaced` из `core_swap_test.go`). `TestPrepareRefusesBadSound` проверяет таблицей, что `transition.Prepare` возвращает ошибку на:
  - `sound` нет или `null`;
  - `repeatSec` 0, 4 или 301 при `until_taken`;
  - `until_taken` без `repeatSec`;
  - `pattern` не из каталога;
  - `repeat` `loud`;
  - ключ `"75.0"`, `"abc"`, `"-5"`, `"101"`, `"075"`;
  - `alert.repeat` `until_taken`;
  - `busyHears.minPriority` `"100"` или 101;
  - `muteMinutes` 0 или 61;
  - `volumeFloor` −1 или 101;
  - лишний ключ в `SoundCue`.

  `TestPrepareWithSound` проверяет `PrepareWith(base, patch)`:
  - `{"sound":{"byPriority":{"75":{"repeat":"once"}}}}` принимается: остаток `repeatSec` из машины допустим;
  - `{"sound":{"patterns":[…]}}` с другим каталогом — ошибка;
  - `{"sound":{"byPriority":{"90":null}}}` принимается;
  - `{"sound":null}` — ошибка.
- [ ] `internal/im/service/transition/core_sound.go`: `checkSound(m *machine.Machine) error` по `m.Data("sound")` (числа — `json.Number`), вызов в `Prepare` после `checkLimits`. В `PrepareWith` — `checkSoundPatterns(base, raw)`: каталог равен каталогу общей машины, по образцу `checkMaintenance`.
- [ ] Ручка: в `internal/im/handler/test/operator_workflow_schemas_test.go` — публикация черновика с `"volumeFloor": 101` → 422 `SCHEMA_VALIDATION_FAILED`, опубликованная версия не меняется.
- [ ] Проверка: `GOTOOLCHAIN=local go test -tags imtest -race ./internal/im/service/transition/ ./internal/im/handler/test/ -run 'Sound|WorkflowSchemas|Swap'` → ok. Затем `make test-local` и `go vet -tags imtest ./...`.
- [ ] Стенд: собрать и перезапустить (`im-stand-server`). `~/Work/stand/check-settings-publish.sh` → 0 FAIL. Черновик с `volumeFloor: 101` → 422.
- Модель: opus. Ревью: полное — слияние патча и опасные входы 1–2.

### Задача 7. Конфигуратор: синтез и функция решения как чистые модули *(можно начинать до IM-уровня — на черновике векторов задачи 3)*
- [ ] Сначала тест:
  - `src/operator/sound/decide.test.ts` гонит копию `src/operator/testing/sound-vectors.json` (копия из IM, не править; `PROJECT.md` — в список копий);
  - `src/shared/sound/synth.test.ts` с поддельным `AudioContext` (записывает `createOscillator`/`start`/`stop` со временем): у каждого из 5 `id` своя последовательность, длительность ≤ 2,5 с, `gain` = громкость / 100. Ещё тест сверяет ключи рецептов с `sound.patterns` копии машины.
- [ ] `src/operator/sound/decide.ts` — интерфейс раздела «Функция решения», один в один с `prototype/sound.js`.
- [ ] `src/shared/sound/synth.ts` — `PATTERNS: Record<string, Recipe>`, `playPattern(ctx: BaseAudioContext, id: string, at: number, volume: number): AudioScheduledSourceNode[]`. Рецепты в `src/shared`: их берут и вкладка настроек, и экран оператора, а `src/operator` не держит имён машины.
- [ ] Типы: `src/operator/api/contract.ts` — `SoundCue`, `SoundSettings`, `WorkflowDefinition.sound?`. Копии `openapi.json` / `workflow_schema.v1.json` в `src/operator/testing/` обновить, хэш в `tests/operator-fake-contract.test.ts` — тоже (LF через `tr -d '\r'`).
- [ ] Проверка: `npx vitest run src/operator/sound src/shared/sound tests/` → зелёно, `npm run lint`, `npx tsc -p tsconfig.app.json --noEmit`.
- Модель: opus — decide; sonnet — synth. Ревью: полное — decide, короткое — synth.

### Задача 8. Конфигуратор: вкладка «Звук» настроек поста — конфигуратор
- [ ] Сначала тест: `src/features/post-settings/lib/editorKind.test.ts` и новый `components/PostSettingsSound.test.tsx`:
  - `compositeKind('sound.byPriority', …)` даёт `'soundByPriority'`, а **не** `'byPriority'` нормативов: значения — объекты, не секунды;
  - `sound.personal` / `sound.alert` дают `'soundCue'`, `sound.busyHears.minPriority` — `'priorityAtLeast'`;
  - строки — уровни справочника по убыванию, уровень без строки — «как <ближайший ниже>» / «без звука» с кнопкой «Задать»;
  - смена «Пока не взят» показывает поле повтора (секунды, 5…300);
  - у `alert` нет «Пока не взят»;
  - ▶ «Прослушать» вызывает `playPattern` с выбранным `id`;
  - `muteMinutes` — поле минут, `volumeFloor` — проценты 0…100;
  - сохранение отправляет патч только раздела `sound`.
- [ ] `lib/compositeKind.ts` — новые виды проверяются раньше `.endsWith('.byPriority')`. `components/CompositeEditor.tsx` — `SoundByPriorityEditor`, `SoundCueEditor`, `PriorityAtLeastPicker`. `lib/formatSetting.ts` — вид для чтения. Строки — `src/shared/i18n/locales/{ru,en}/postSettings.json`; kk и zh — английский текст, как принято в репозитории.
- [ ] Проверка: `npx vitest run src/features/post-settings` → зелёно, lint, tsc. Стенд: `npm run build && rsync -a --delete dist/ ~/Work/stand/im-dist/`. Скрипт `ui-check/check-sound-tab.mjs` по образцу `check-draft.mjs`: вкладка «Звук» есть, строк — по числу уровней, ▶ без ошибок консоли.
- Модель: sonnet. Ревью: полное.

### Задача 9. Конфигуратор: движок звука на экране оператора
- [ ] Сначала тест: `src/operator/sound/soundEngine.test.ts` (поддельные `AudioContext`, `navigator.locks`, `BroadcastChannel`, часы) и `src/operator/shell/useServerEvents.test.tsx`:
  - моё событие, которое снимает звук, доходит до движка **до** выхода по `isMine`;
  - заблокированный контекст ничего не копит: после разблокировки звучит только проверочный сигнал;
  - повтор Критического планируется на 120 с вперёд и дополняется таймером; снятие останавливает запланированные узлы;
  - вторая вкладка без замка молчит; «Тихо» во второй приходит ведущей через канал; ведущая закрылась — замок берёт другая;
  - без `navigator.locks` звучит каждая вкладка (решение 4);
  - `workflow.schema_published` обновляет настройки звука без потери `sounding`;
  - `stream.reset` и переподключение ничего не проигрывают задним числом;
  - перерыв или выход — всё смолкает.
- [ ] `src/operator/sound/soundEngine.ts`:
  - `createSoundEngine({ audio, locks, channel, clock, log })` → `{ onEvent, silence, setOnlyImportant, setVolume, unlock, test, dispose }`;
  - ведущая — `navigator.locks.request('im-sound:' + operatorGuid, …)`, канал — `BroadcastChannel('im-sound:' + operatorGuid)`;
  - отладочный журнал включается `localStorage['im-sound-log'] = '1'`: тогда `window.__imSound = { log: [{kind, pattern, guid, ctxTime, wall, ended?}] }`.
- [ ] `src/operator/sound/useSound.ts` — хук в `Workplace`.
- [ ] Срез `sound` в `state/workplaceStore.ts`: `unlocked`, `sounding`, `attention`, `onlyImportantUntil`, `volume`. Громкость хранится в `localStorage` `im-sound-volume` (решение 5).
- [ ] Проверка: `npx vitest run src/operator` → зелёно, lint, tsc.
- Модель: opus. Ревью: полное — опасные входы 3–5.

### Задача 10. Конфигуратор: шапка, меню, заголовок, уведомление браузера
- [ ] Сначала тест: `src/operator/shell/SoundLine.test.tsx`, `SoundMenu.test.tsx`, `useTabTitle.test.ts`, `useBrowserNotice.test.ts`:
  - «Звучит: Критический, INC-… · Тихо»: щелчок по номеру ставит `selectedId` и `jumpPending`, как `NoticeSummary`;
  - несколько звучащих — «Звучит: N (Критический)»;
  - «Звук не включён · Включить звук» → `unlock` + `test`;
  - «Только важное до ЧЧ:ММ · Вернуть»;
  - значок 🔊/🔉/🔇 с `aria-label`;
  - ползунок громкости не опускается ниже `volumeFloor`;
  - «Проверить звук»; «Разрешить уведомления» только при `permission === 'default'`;
  - заголовок `(N) ` + прежний и мигание значка вкладки, пока `N > 0`;
  - `Notification` — только у ведущей вкладки и только при `document.hidden`; щелчок фокусирует окно и выбирает инцидент.
- [ ] `shell/SoundLine.tsx`, `shell/SoundMenu.tsx` — в `TopBar` в средний кластер после `GroupsButton` и в `actions` перед `HelpMenu`. Строки — `locales/{ru,en}/operator.json`; `tests/operator-locale-keys.test.ts` и `tests/operator-guide-names.test.ts` должны пройти. `PROJECT.md` — строки о модулях звука.
- [ ] Проверка: `npx vitest run` → всё зелёно, lint, tsc, `npm run build`.
- Модель: sonnet. Ревью: полное.

### Задача 11. Стенд: проверка без слуха — автоматически
- [ ] Выкладка: сервер (задача 6) и `npm run build && rsync -a --delete dist/ ~/Work/stand/im-dist/`. Перед событиями — копия `imdb` (`pg_dump` в `~/Work/stand/backup/imdb-before-sound-2026-11-1x.sql`).
- [ ] `~/Work/stand/ui-check/check-sound.mjs` (копия — IM `tools/stand-load/`). В `lib.mjs` `open()` добавить необязательные `args`, Chrome запускать с `--autoplay-policy=no-user-gesture-required`. До загрузки — `localStorage['im-sound-log'] = '1'`; `Browser.grantPermissions(['notifications'])`; `window.Notification` обёрнут счётчиком. События — `~/Work/stand/bin/agent-emulator event --device … --type …` по правилу с приоритетом 100 из демо-настройки: найти его в `demo-config`, а если нет — SKIP с причиной, правила не менять. Каждая строка вывода — `OK|FAIL …`, код выхода — число FAIL:
  1. Без нажатия — «Звук не включён», журнал пуст.
  2. «Включить звук» — 1 запись `test`.
  3. Событие Критического — запись `siren` ≤ 3 с. За 46 с ≥ 3 записи с шагом 15 ± 0,5 с по `ctxTime`.
  4. Вторая вкладка того же оператора — записи только у одной.
  5. Свёрнутая: другая вкладка вперёд (`bringToFront`), `document.visibilityState === 'hidden'` у первой, 11 мин. Затем записей `ended` 44 ± 2, наибольший промежуток ≤ 16 с, `Notification` создано ≥ 1.
  6. Взять инцидент запросом из страницы — новых `ended` нет через 2 с, заголовок без `(N)`.
  7. Перерыв — Критический не звучит, после «Вернуться» — звучит.
- [ ] Если headless Chrome не замедляет скрытые вкладки, как настоящий, пункт 5 повторить в окне под `xvfb-run`, если он есть. Если нет — так и записать в итоге: замедление не воспроизведено, проверено только расписание.
- [ ] Проверка на слух — утром, пользователем, по списку из итога.
- Модель: sonnet. Ревью: короткое.

### Задача 12. Итог
- [ ] В этом файле — раздел «Итог»: коммиты по репозиториям, что проверено и чем, что не прогнано и почему.
- [ ] В 87-notifications.md, в таблицу «Работы», — ссылку на этот план. В `TECH-DEBT.md` — пункт 87, звук сделан.
- [ ] `graphify update .` в IM и конфигураторе.
- Модель: sonnet. Ревью: короткое.

**Что можно начинать сразу, без IM-уровня:**
- задача 7 — синтез и `decide.ts` на черновике векторов; рецепты не зависят от машины;
- задача 9 без `useServerEvents` — движок с поддельными зависимостями;
- задача 6 — тест и `checkSound` на копии машины с разделом `sound` из этого плана, вендор — после задачи 2.

## Что потом переставит раскладка (план после звука)

- `TopBar` в конфигураторе и шапка в прототипе. Строки «Звук не включён», «Звучит … · Тихо» и «Только важное до …» переезжают в строку состояния поста: порядок «нет связи → звук не включён → работы → только важное», «и ещё N». Значок звука с меню остаётся справа.
- `eventNotice` для `addressedToMe` и всплывающее «Оповещение: …» — заменяются строкой блока «Мне на принятие» и журналом колокольчика. Звук «лично вам» остаётся. В §8.1 «всплывающее уведомление» меняется на строку блока.
- Число в заголовке: сейчас оно считается из событий с начала загрузки (решение 3). Раскладка может брать его из счётчиков `/operator/incidents/counters` с разбивкой по приоритетам.
- Ссылка номера в «Звучит» и «скрыт фильтром · Показать» — после того как раскладка введёт показ скрытого фильтром.
- `MaintBanner` над очередью переезжает в строку поста. Звук его не трогает.

## Фокус ревью — 5 опасных входов

1. **Слияние патча поста с `sound` (JSON Merge Patch).** Переключение `until_taken → once` оставляет `repeatSec` из машины. Ещё опасны `null` у строки уровня, `null` у всего `sound` и патч, который подменяет `patterns`. Сервер, `check_machine.py` и конфигуратор должны вести себя одинаково.
2. **Ключи `byPriority` и уровни справочника.** `"75.0"`, `"075"`, `"-5"`, `"101"`, нечисло; уровень вне справочника (90 → 75, 10 → тишина); пустой `byPriority`. Справочник меняется без публикации схемы (`reference.priorities_changed`). Отдельно: `compositeKind` не должен отдать `sound.byPriority` редактору нормативов.
3. **Порядок и автор событий потока.** Моё событие, которое снимает звук, отбрасывается `isMine` раньше движка — тогда повтор вечный. Ещё: `stream.reset` и переподключение (без проигрыша задним числом), `access_lost`, `workflow.schema_published` посреди повтора, `change_priority` внутри «Нового», событие инцидента в окне работ.
4. **Несколько вкладок.** Ведущая закрыта или зависла, замок освобождается; «Тихо», «только важное» и громкость из ведомой должны дойти до ведущей. Нет `navigator.locks` или `BroadcastChannel`. Уведомление браузера только от ведущей.
5. **Часы и `AudioContext`.** Скрытая вкладка: таймер раз в минуту при запасе 120 с. `suspended` или `interrupted` контекст. Узлы, запланированные вперёд, после взятия, «Тихо», перерыва и выхода должны остановиться. Громкость ниже порога. Звуки, накопленные до разблокировки, не должны выстрелить залпом.

## Решения исполнителя (ночь 2026-11-15)

1. **`busyHears` — порог, не CEL:** `{ minPriority, personal, alert }`. CEL исполняет только сервер, а у экрана оператора своего исполнителя CEL нет. Порог 100 и `alert: false` — буквально по таблице «Кто слышит»: «Занят» слышит только Критический и «лично вам».
2. **Строки 50 и 25 в `byPriority` заданы явно, `repeat: none`.** «Средний, Низкий — без звука» видно в таблице, а новый уровень 60 по правилу «ближайший ниже» берёт строку 50 и тоже молчит.
3. **Звук без восстановления после перезагрузки.** Звук решается по событиям потока. После перезагрузки страницы повтор Критического не возобновляется, а число в заголовке считается с загрузки. Инцидент виден в очереди, его ведут норматив и эскалация. Раскладка может взять число из счётчиков.
4. **Без `navigator.locks` звучит каждая вкладка** — эхо, но не тишина.
5. **Громкость и «только важное» — в браузере** (`localStorage` и канал вкладок), не в `session.preferences`: так контракт сессии не меняется. По умолчанию громкость 80 %.
6. **Проверочный сигнал — «Двойной сигнал».** Отдельного шестого звука нет.
7. **Повтор — только у одного звука, верхнего.** Порядок: приоритет, затем «лично вам», затем раньше появившийся. Одиночные звуки играют сразу поверх. Без какофонии из нескольких сирен.
8. **Оповещение §9 не повторяется** (`repeat` без `until_taken`): получатель оповещения инцидент не берёт.
9. **Классификация без имён машины** — по `stateCategory`, `ownership`, `addressee`, `maintenanceWindowId` и неравенству `state.from/to` (решение 151). Создание сразу на мою группу по правилу М1 звучит как «лично вам», полей М1 звук не читает.
10. **Вкладка «Звук» стоит после «Оператор»;** «Хранение» остаётся последней из вкладок настроек (решение 2026-11-15).
11. **`sound` не входит в `required` контракта,** но сервер требует его при публикации. Клиент без раздела молчит и показывает 🔇 без строки.
12. **Одна вкладка в прототипе — отступление §17:** у каждой вкладки прототипа свой встроенный сервер.
13. **Рецепты звуков — в коде клиента** (`prototype/sound.js` и `src/shared/sound/synth.ts`, одни параметры). Машина держит только каталог `id` и подписей, как сказано в 87.
