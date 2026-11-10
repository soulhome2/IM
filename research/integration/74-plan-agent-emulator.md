# План: эмулятор агента с прямым входом

> **Для исполнителя-агента:** выполнять по задачам через superpowers:subagent-driven-development или superpowers:executing-plans. Шаги отмечаются `- [ ]`.

**Цель:** эмулятор агента одной командой без токенов отправляет топологию из своего JSON-файла раз в 10 с и события раз в 1 с, и всё это видно в МИ.

**Устройство:** на сервере — прямой вход агента по заголовку `X-Dev-Agent`, только с этой же машины и только при `IM_AGENT_DEV_AUTH=true`. В существующем `tools/agent-emulator` — команда `run`, свой тестовый файл и README.

**Стек:** Go (модуль сервера), gin, сгенерированный клиент `internal/im/handler/v1`.

**Проект:** [73-agent-emulator.md](73-agent-emulator.md).

**Репозиторий:** `~/Work/incident-manager-server`, ветка `feature/im_operator`. Коммиты — только по просьбе. Перед коммитом сервер собирается на стенд ([30-local-stand.md](30-local-stand.md), `run-im-binary.sh`).

## Общие ограничения

- `IM_AGENT_DEV_AUTH` по умолчанию `false`; выключена — поведение сервера не меняется ни в чём.
- Прямой вход — только если адрес клиента — петля (127.0.0.1, ::1). Иначе — обычная проверка HMAC.
- Вход HMAC через токен остаётся как был; прежние команды эмулятора (`enroll`, `sync`, `event`, `replay`, `demo-config`) работают как раньше.
- Тексты вывода эмулятора и README — по-русски, простыми словами.
- Интервалы по умолчанию: события 1 с, топология 10 с.

## На что смотреть при проверке

1. **Файл испортили во время работы** (ошибка JSON, неизвестный `typeUid`) — эмулятор пишет ошибку, работает дальше на прежних данных, не падает. Тест — задача 3.
2. **Сервер недоступен или ответил ошибкой** — строка в консоль, следующий такт пробует снова, эмулятор не выходит. Тест — задача 3 (ответ 500 от `httptest`).
3. **Из файла убрали устройство, на котором стоит перебор** — перебор продолжается с начала нового списка, без выхода за границу. Тест — задача 3.
4. **Тип устройства без типов событий** — устройство в переборе пропускается; если событий нет вовсе, такт ничего не шлёт и пишет об этом один раз. Тест — задача 3.
5. **Заголовок `X-Dev-Agent` с не-GUID или при выключенной настройке** — 401, агент не заводится. Тест — задача 1.

---

### Задача 1. Сервер: прямой вход агента

**Файлы:**
- Изменить: `internal/im/model/config.go` — поле `AgentDevAuth bool \`envconfig:"IM_AGENT_DEV_AUTH" default:"false"\``.
- Изменить: `internal/im/handler/v1/auth_middleware.go` — константа `DevAgentHeader = "X-Dev-Agent"`, ветка прямого входа в начале `AgentAuthMiddleWare`.
- Изменить: служба входа (`AuthAppService`, `internal/im/appservice/auth/`) — метод заведения агента.
- Изменить: место, где сервер стартует (`cmd/im/main.go` или сборка служб), — предупреждение в журнал.
- Изменить: `internal/im/handler/v1/common_client.go` — `setHMACAuthFunc(nil)` ничего не подписывает.
- Тесты: `internal/im/handler/v1/auth_middleware_test.go` (петля), интеграционный — рядом с тестами `internal/im/handler/test/` (прямой вход).

**Интерфейсы:**
- Даёт: `func isLoopback(remoteAddr string) bool` (`"127.0.0.1:5432"`, `"[::1]:1"` → true; `"10.0.0.5:1"`, `""`, `"мусор"` → false).
- Даёт: `func (s *AppService) EnsureDevAgent(ctx model.AppContext, guid uuid.UUID) (*model.Agent, error)` — агент заказчика установки: есть — вернуть, нет — завести с именем `"Эмулятор (прямой вход)"` и вернуть.
- Даёт: клиент `v1.Client` с `key == nil` шлёт запрос без заголовков HMAC — этим пользуется задача 3.

- [ ] **Шаг 1. Тест `TestIsLoopback`** — таблица значений из «Интерфейсов». Запуск `go test ./internal/im/handler/v1/ -run TestIsLoopback` — не собирается.
- [ ] **Шаг 2. `isLoopback`** через `net.SplitHostPort` и `net.ParseIP(...).IsLoopback()`. Тест проходит.
- [ ] **Шаг 3. Интеграционный тест `TestDevAgentAuth`** в стиле соседних тестов `internal/im/handler/test` (их сервер слушает 127.0.0.1):
  - настройка выключена, `X-Dev-Agent: <guid>` → `POST /sync/sources/types` = 401;
  - настройка включена, `X-Dev-Agent: <guid>` → 200; агент с этим GUID есть в `GET /agents`; повтор — снова 200, агент один;
  - настройка включена, `X-Dev-Agent: not-a-guid` → 401, агентов не прибавилось;
  - настройка включена, без заголовка и без HMAC → 401;
  - настройка включена, обычный HMAC-клиент → 200 (старый путь цел).
  Запуск — как у соседних тестов (см. `Makefile`). Падает.
- [ ] **Шаг 4. Реализация.** В `AgentAuthMiddleWare`: если `AgentDevAuth` включена, заголовок есть и `isLoopback(c.Request.RemoteAddr)` — разобрать GUID (ошибка → 401 как сейчас), `EnsureDevAgent`, положить агента в `AgentCtxKey`, `c.Next()`. Иначе — прежний путь HMAC без изменений. Заказчик агента — тот же, что берёт нынешний путь HMAC. При старте с включённой настройкой — `Warn`: «IM_AGENT_DEV_AUTH: агенты входят без подписи с этой машины — только для стенда». В `setHMACAuthFunc`: `key == nil` → вернуть `nil`, заголовки не ставить.
- [ ] **Шаг 5. Тесты проходят:** `go test ./internal/im/handler/...` и полный набор как в `Makefile`. `go vet ./...` чисто.
- [ ] **Шаг 6. Стенд:** в `~/Work/stand/im-server.env` добавить `IM_AGENT_DEV_AUTH=true`, пересобрать и перезапустить сервер (`run-im-binary.sh`), в журнале — предупреждение. `curl -s -o /dev/null -w '%{http_code}' -H 'X-Dev-Agent: 0193f000-0000-7000-8000-000000000e01' -H 'Content-Type: application/json' -d '[]' http://127.0.0.1:5000/<базовый путь>/sync/sources/types` → `200`.
- [ ] **Шаг 7. Коммит** (по просьбе): `Агент: прямой вход для стенда по X-Dev-Agent (IM_AGENT_DEV_AUTH, только с этой машины)`.

### Задача 2. Эмулятор: тестовый файл и его чтение

**Файлы:**
- Создать: `tools/agent-emulator/testdata/agent-emulator.json` — формат из проекта (раздел «Формат тестового файла»), 4–6 типов устройств, по 2–4 типа событий, 8–12 устройств; GUID агента `0193f000-0000-7000-8000-000000000e01`. Состав — на усмотрение исполнителя, **показать человеку до задачи 3**.
- Создать: `tools/agent-emulator/data.go`, тест `data_test.go`.

**Интерфейсы:**
- Даёт:
  ```go
  type emuEventType struct { UID, Name string; Payload json.RawMessage }
  type emuSourceType struct { UID, Name string; EventTypes []emuEventType }
  type emuSource struct { UID, Name, TypeUID string; IsOnline bool }
  type emuData struct {
      AgentGUID           uuid.UUID
      EventIntervalSec    int
      TopologyIntervalSec int
      SourceTypes []emuSourceType
      Sources     []emuSource
  }
  func loadData(path string) (*emuData, error)
  ```
  JSON-имена полей — как в проекте (`agentGuid`, `eventIntervalSec`, `topologyIntervalSec`, `sourceTypes`, `eventTypes`, `payload`, `sources`, `typeUid`, `isOnline`). Если интервал не задан — 1 и 10.

- [ ] **Шаг 1. Тесты:**
  - `TestLoadDataTestdata` — `testdata/agent-emulator.json` читается без ошибки, у каждого устройства тип есть в `SourceTypes`;
  - `TestLoadDataDefaults` — без интервалов → 1 и 10;
  - `TestLoadDataErrors` — каждая ошибка своим текстом, в котором есть виноватый `uid`: устройство с неизвестным `typeUid`; повтор `uid` типа устройства; повтор `uid` устройства; повтор `uid` типа события внутри одного типа устройства; пустой `uid`; `agentGuid` не GUID; интервал ≤ 0; битый JSON.
  Запуск `go test ./tools/agent-emulator/ -run TestLoadData` — не собирается.
- [ ] **Шаг 2. `loadData`.** Тесты проходят, прежние тесты папки тоже.
- [ ] **Шаг 3. Показать файл человеку**, внести правки.
- [ ] **Шаг 4. Коммит** (по просьбе): `Эмулятор агента: свой тестовый файл и его проверка`.

### Задача 3. Эмулятор: команда `run`

**Файлы:**
- Создать: `tools/agent-emulator/run.go`, тест `run_test.go`.
- Изменить: `tools/agent-emulator/main.go` — команда `run` в `switch` и в `usage`.

**Интерфейсы:**
- Берёт: `loadData`, `emuData` (задача 2); `v1.Client.SyncSourceTypes / SyncSourceEventTypes / SyncSources / CreateEvent` с `key == nil` (задача 1).
- Даёт:
  ```go
  // topology — три списка для sync-запросов; типы событий развёрнуты с SourceType.
  func topology(d *emuData) ([]*model.SourceType, []*model.SourceEventType, []*model.Source)
  // cursor — перебор: устройства по порядку, у каждого все типы событий его типа, по кругу.
  type cursor struct{ /* позиция по uid устройства и типа события */ }
  func (c *cursor) next(d *emuData) (src emuSource, et emuEventType, ok bool)
  ```
  Запуск: `agent-emulator [--server host:port] run [--data <файл>] [--event-interval 1s] [--topology-interval 10s]`; `--data` по умолчанию — `./testdata/agent-emulator.json` относительно текущей папки (запуск из `tools/agent-emulator`); ключи интервалов переопределяют файл.

- [ ] **Шаг 1. Тесты:**
  - `TestTopologyFlattens` — на маленьком `emuData`: число записей в трёх списках, у каждого типа события `SourceType.UID` — его тип устройства;
  - `TestCursorOrder` — 2 устройства (типы с 2 и 1 событием): 6 вызовов `next` дают (d1,e1),(d1,e2),(d2,e3),(d1,e1),(d1,e2),(d2,e3);
  - `TestCursorSourceRemoved` — после двух шагов `next` вызывается с данными без текущего устройства: без паники, дальше по новому списку с начала;
  - `TestCursorNoEvents` — у всех типов нет событий → `ok == false`; у одного нет — его устройства пропускаются;
  - `TestRunAgainstServer` — `httptest.Server` записывает запросы; `run` с интервалами 20 мс и 100 мс за ~250 мс: первые три запроса — `/sync/sources/types`, `/sync/sources/event-types`, `/sync/sources` по порядку; затем есть `/events`; у каждого запроса заголовок `X-Dev-Agent` = GUID из файла, заголовков `X-Signature` нет; `guid` событий все разные;
  - `TestRunSurvivesErrors` — сервер отвечает 500 на первые два запроса `/events`, затем 200: `run` не выходит, потом события доходят; файл подменяется на битый JSON — следующий такт топологии пишет ошибку, события продолжают идти по прежним данным.
  `run` для тестов принимает `context.Context` (отмена — выход) и `io.Writer` для вывода. Запуск `go test ./tools/agent-emulator/ -run 'TestTopology|TestCursor|TestRun'` — не собирается.
- [ ] **Шаг 2. Реализация.** Клиент — `v1.NewClientWithHTTPClient` с `http.Client`, транспорт которого добавляет `X-Dev-Agent`; ключ HMAC — `nil`. При старте — сразу топология, затем два `time.Ticker`. Такт топологии: перечитать файл (ошибка — строка `файл: …`, остаются прежние данные), три sync-запроса по порядку. Такт события: `cursor.next`, `CreateEvent` с новым `uuid.New()`, `payload` — из типа события или `{}`, в `payload` добавить `occurredAt` (текущее время UTC, RFC3339) и `"emulator": true`, как у прежней `send`. Каждый запрос — строка в вывод: время, что ушло, ответ (`ok` или ошибка). Ctrl+C (`signal.NotifyContext`) — выход с кодом 0.
- [ ] **Шаг 3. Тесты проходят**, `go vet ./tools/agent-emulator/` чисто, прежние тесты папки проходят.
- [ ] **Шаг 4. Коммит** (по просьбе): `Эмулятор агента: команда run — топология и события по таймеру, прямой вход`.

### Задача 4. README и проверка на стенде

**Файлы:**
- Создать: `tools/agent-emulator/README.md`.

- [ ] **Шаг 1. README**, разделы:
  - что это и зачем (только для тестов, будет сведён с настоящим агентом);
  - быстрый старт: на сервере `IM_AGENT_DEV_AUTH=true`, сборка `go build -o ~/Work/stand/bin/agent-emulator ./tools/agent-emulator`, запуск `agent-emulator run` из папки `tools/agent-emulator`;
  - тестовый файл: поля, пример, правило «`uid` не менять», что будет, если убрать устройство (помечается удалённым, история остаётся);
  - ключи `run`;
  - прямой вход: как работает, почему только с этой машины, что он будет убран после перехода на схему `updateagent`;
  - прежние команды (`enroll`, `sync`, `event`, `replay`, `demo-config`) — по строке и ссылка на `usage`.
- [ ] **Шаг 2. Проверка на стенде** (сервер из задачи 1 уже стоит):
  - `agent-emulator run` 30 с — в конфигураторе видны типы устройств, типы событий и устройства из файла;
  - в журнале событий конфигуратора (§12.5) идут события по кругу;
  - убрать устройство из файла, подождать 10 с — в конфигураторе устройства нет; события по нему в журнале остались;
  - вернуть устройство — записать, что делает сервер (новая запись или прежняя), — в техдолг (шаг 4);
  - сервер без `IM_AGENT_DEV_AUTH` — `run` пишет 401 и не падает. Вернуть настройку.
- [ ] **Шаг 3. Коммит** (по просьбе): `Эмулятор агента: README`.
- [ ] **Шаг 4. Техдолг** — в `research/integration/TECH-DEBT.md` (репозиторий IM): «Убрать прямой вход `IM_AGENT_DEV_AUTH` после перехода на вход `updateagent`»; «Вернувшийся датчик — снимать отметку удаления, а не заводить новый» (с результатом шага 2); «Предупреждение у правил, ссылающихся на удалённый датчик». Затем — отметка в [72-remaining-work.md](72-remaining-work.md), п. 2.
