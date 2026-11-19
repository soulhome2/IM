# Локальный стенд МИ: скрипты

Здесь лежат скрипты, которыми на одной машине поднимают облако, сервер МИ и конфигуратор и проверяют операторский API. Подробное описание стенда, ловушки и история прогонов — [30-local-stand.md](../../research/integration/30-local-stand.md). Скрипты нагрузки — в соседней папке, [tools/stand-load/README.md](../stand-load/README.md).

## Где что лежит

Скрипты берут пути из переменных. Если переменная не задана, берётся значение по умолчанию:

| Переменная | По умолчанию | Что там |
|---|---|---|
| `STAND_DIR` | `~/Work/stand` | данные стенда: `im-server.env`, файлы паролей, `bin/`, `im-dist/`, журналы |
| `CLOUD_REPO` | `~/Work/axxoncloudgo` | облако; корневой сертификат стенда — `tools/util/rootCA.axxonnet.test.pem` |
| `IM_SERVER_REPO` | `~/Work/incident-manager-server` | сервер МИ |
| `IM_CONFIGURATOR_REPO` | `~/Work/incident-manager` | конфигуратор и экран оператора |
| `IM_REPO` | этот репозиторий (на две папки выше скрипта) | прототип и эталонный набор |

Запускать можно прямо отсюда: `tools/stand/check-operator-api.sh`. Общие части (`test-operator.sh`, `second-operator.sh`, `seen-body.sh`) скрипты берут из своей папки. Если скопируете скрипты в другое место, задайте `IM_REPO`.

Клоны держите на диске машины, а не в общей папке виртуальной машины: там сборка и Docker медленнее.

## 1. Репозитории и ветки

| Репозиторий | Ветка | Зачем |
|---|---|---|
| `axxoncloudgo` | `epic/CLOUD-23284-perms-i18n` | облако: `make deploy`, Docker Swarm, сервисы `ac_*`. В ветке есть приём каталога прав МИ |
| `incident-manager-server` | `feature/im_operator` | сервер МИ, бинарник на машине, порт 5000; там же эмулятор агента `tools/agent-emulator` |
| `incident-manager` | `feature/im_operator` | конфигуратор и экран оператора, отдаются на порт 5173 |
| этот репозиторий (IM) | рабочая ветка | скрипты стенда, прототип для `/im-proto/` |

Интерфейс облака (`ui-AxxonNet.zip`) и образ `up/uploader` — готовые сборки из Bamboo, см. «Что где» в [30-local-stand.md](../../research/integration/30-local-stand.md#что-где).

## 2. Порядок запуска

Сначала заведите папку стенда и файлы в ней:

```
mkdir -p ~/Work/stand/bin ~/Work/stand/im-dist
cp tools/stand/im-server.env.example ~/Work/stand/im-server.env
```

Пароль `test@axxonnet.test` положите в `~/Work/stand/test-operator.pass` с правами `600` (`chmod 600`). Пароль второго оператора, если он нужен, — в `~/Work/stand/second-operator.pass`, тоже `600`. Другие пути — через `TEST_PASS_FILE` и `SECOND_PASS_FILE`, другой адрес второго — через `SECOND_EMAIL`. Скрипты читают пароль только из файла и не печатают его.

### Шаг 1. Облако

В `axxoncloudgo`: Docker Swarm, `/etc/hosts` с `127.0.0.1 axxonnet.test`, `make build-all`, `make deploy` — по [30-local-stand.md, «Шаги»](../../research/integration/30-local-stand.md#шаги). Там же ловушки: архивный Debian 11, `up/uploader`, устаревший `make create-db-users`. Пользователь `test@axxonnet.test` (и второй, если нужен) — в группе `cloud-admin`.

Для входа в портал без страницы входа нужен свой способ: здесь его нет.

Проверка: `https://axxonnet.test/` отвечает 200, `POST /api/v3/ac-backend/users/login` даёт токены.

### Шаг 2. Сеть: из Docker на машину

Шлюз облака работает в контейнере и ходит на порты машины 5000 (сервер МИ) и 5173 (конфигуратор). Если входящие на машине закрыты (на стенде их закрывает `vpn-killswitch`), откройте их для сетей Docker:

```
sudo iptables -I KS_IN 1 -s 172.16.0.0/12 -p tcp -m multiport --dports 5000,5173 -j ACCEPT
```

`KS_IN` — цепочка `vpn-killswitch`. У вас может быть своя, тогда правило ставится в неё. Чтобы правило не пропадало, его добавляют в скрипт файервола ([30-local-stand.md, «Шаг 2», п. 6](../../research/integration/30-local-stand.md#шаг-2-сервер-ми-на-стенде)).

### Шаг 3. nginx облака

```
tools/stand/apply-nginx-dev.sh
```

Скрипт добавляет в конфиг `ac_nginx` маршруты `/api/v1/im-backend/` → `:5000` и `/im/`, `/im/operator/` → `:5173`. **После каждого `make deploy` его надо запустить снова** — почему, см. раздел 4.

### Шаг 4. База и сервер МИ

1. База: роль `im` с паролем `im_local_dev` и база `imdb` в контейнере `ac_db` ([30-local-stand.md, «Шаг 2», п. 1](../../research/integration/30-local-stand.md#шаг-2-сервер-ми-на-стенде)). Миграции сервер применяет сам при старте.
2. Настройки — `~/Work/stand/im-server.env` (образец — `im-server.env.example`).
3. Сборка — **без `-tags imtest`**: с этим тегом сервер отказывается работать на базе `imdb`.
   ```
   (cd ~/Work/incident-manager-server && go build -o ~/Work/stand/bin/im ./cmd/im)
   ```
   Без корпоративного VPN частные Go-модули берут из локальной копии (`source ~/go/offline-env.sh`, [30-local-stand.md, «Шаги», п. 3](../../research/integration/30-local-stand.md#шаги)).
4. Запуск. Лучше как юнит systemd — тогда сервер не упадёт, когда закроется терминал или редактор:
   ```
   loginctl enable-linger "$USER"     # один раз: юниты живут без входа в систему
   systemd-run --user --collect --unit=im-stand-server "$PWD/tools/stand/run-im-binary.sh" ~/Work/stand/bin/im
   ```
   Команды здесь и дальше — из корня этого репозитория. Если папка стенда не `~/Work/stand`, добавьте `--setenv=STAND_DIR=…` (и так же для других переменных). Остановить — `systemctl --user stop im-stand-server`. Можно и без systemd: `tools/stand/run-im-binary.sh ~/Work/stand/bin/im` в отдельном терминале. Журнал — `~/Work/stand/im-server.log`. `run-im-server.sh` собирает и сразу запускает, в том же терминале.

При старте сервер отправляет в облако каталог прав МИ. Если облако его не приняло, сервер выходит, причина — в конце журнала.

### Шаг 5. Права

```
tools/stand/grant-im-permissions.sh
```

Выдаёт роли `cloud-admin` все права `incident_manager.*` из машины сервера и печатает, что видно в `/me`. Повторять после очистки томов базы облака.

### Шаг 6. Конфигуратор

```
(cd ~/Work/incident-manager && npm ci && npm run build && rsync -a --delete dist/ ~/Work/stand/im-dist/)
systemd-run --user --collect --unit=im-stand-dist bash -c "exec node $PWD/tools/stand/serve-im-dist.mjs >> $HOME/Work/stand/serve-im-dist.log 2>&1"
```

После правок конфигуратора — снова `npm run build` и `rsync`, перезапуск не нужен. Для живых правок вместо сборки — `run-vite.sh` (Vite на том же 5173; `serve-im-dist.mjs` перед этим остановить). Адреса: `https://axxonnet.test/im/` — конфигуратор, `https://axxonnet.test/im/operator/` — экран оператора.

### Шаг 7. Эмулятор агента

Готовый эмулятор есть в образе сервера `im/backend` (`imbackend.img` из Bamboo, начиная с коммита сервера `cf155c4`): `/bin/agent-emulator`, запуск из образа — README эмулятора в сервере, раздел «Из образа сервера». Для стенда на машине его собирают из исходников:

```
(cd ~/Work/incident-manager-server && go build -o ~/Work/stand/bin/agent-emulator ./tools/agent-emulator)
tools/stand/run-agent.sh
```

`run-agent.sh` шлёт топологию и события без ключа (нужен `IM_AGENT_DEV_AUTH=true`). Для `load-demo.sh` и `replay` агента надо зарегистрировать (`agent-emulator enroll`, [30-local-stand.md, «Шаг 3»](../../research/integration/30-local-stand.md#шаг-3-агент-эмулятор)).

### Шаг 8. Проверка

```
tools/stand/check-operator-api.sh
```

Каждая строка — `OK` или `FAIL`, в конце `итого ошибок: 0`, код выхода — число `FAIL`. Код 2 и `SKIP вход` — нет файла пароля или вход не прошёл.

## 3. Что делает каждый скрипт

**Запуск**
- `apply-nginx-dev.sh` — подменяет `nginx.conf` сервиса `ac_nginx` копией конфига облака с маршрутами МИ (через Swarm config, файлы облака не меняются).
- `gateway.d/im.conf` — те же маршруты отдельным куском для `include` в шлюзе; `@HOST@` — адрес машины из Docker. Скрипты его не читают.
- `run-im-binary.sh <бинарник>` — запускает готовый сервер МИ с `im-server.env` и сертификатом стенда, журнал — `im-server.log`.
- `run-im-server.sh` — собирает сервер из `IM_SERVER_REPO` в `bin/im` и сразу запускает.
- `serve-im-dist.mjs` — отдаёт сборку конфигуратора из `im-dist/` на 5173, `/im/operator/…` — страница оператора.
- `run-vite.sh` — Vite конфигуратора на 5173 с `VITE_API_URL=https://axxonnet.test`, для живых правок.
- `run-agent.sh` — эмулятор агента в фоне, журнал — `agent-emulator.log`.
- `sync-im-proto.sh` — копирует `prototype/`, `tests/` и `theme/` этого репозитория в каталог интерфейса облака: `https://axxonnet.test/im-proto/tests/api.html`.

**Данные и права**
- `grant-im-permissions.sh` — права `incident_manager.*` роли `cloud-admin`.
- `load-demo.sh [флаги demo-config]` — демо-настройка: типы и устройства агента, приоритеты, группы, сценарии, правила. Меняет данные стенда.
- `enable-queue-sort.sh` — включает «Оператор может менять порядок» в «Настройках поста». Пишет в `imdb`, перед запуском снимите дамп.
- `im-machine-patch.sh` — пишет `im-machine-patch.json`: эскалация на второго оператора за 60 с и короткие таймеры молчания, для `check-operator-scheduler.sh`.

**Вход** (подключаются через `source`, сами не запускаются)
- `test-operator.sh` — вход `test@axxonnet.test`, пароль из `TEST_PASS_FILE`.
- `second-operator.sh` — вход второго оператора (`SECOND_EMAIL`, `SECOND_PASS_FILE`) и правило, когда это `SKIP`, а когда `FAIL`.
- `seen-body.sh` — тело перехода с тем, что видел оператор (RULE-142).

**Проверки** — строки `OK`/`FAIL`/`SKIP`, код выхода — число `FAIL`
- `check-operator-api.sh` — каркас операторского API через шлюз: 401 без токена, сессия, 20 прав, очередь, `POST /test/reset` → 404.
- `check-operator-transitions.sh` — путь инцидента: `claim`, `hold`, `resume`, `transfer`, `accept`, `close`.
- `check-operator-transfer.sh` — передача двумя операторами; созданный инцидент закрывает сам.
- `check-operator-filter.sh` — фильтр и выборка очереди, адресаты передачи.
- `check-operator-stream.sh` — поток событий SSE через шлюз: задержка, пинг, повтор с `Last-Event-ID`, сброс.
- `check-operator-scenario.sh` — прохождение сценария по шагам до закрытия.
- `check-operator-scheduler.sh` — эскалация по нормативу и молчание оператора; нужен сервер с патчем машины.
- `check-settings-publish.sh` — версия «Настроек поста»: черновик, проверка, публикация, откат. Пишет в `imdb`.

Скрипты с `agent-emulator replay` создают инциденты на стенде. Для двух операторов нужен файл пароля второго, без него эти шаги дают `SKIP`.

Сервер с патчем машины (только для `check-operator-scheduler.sh`):

```
tools/stand/im-machine-patch.sh
IM_TEST_SUPPORT=true IM_MACHINE_PATCH=$HOME/Work/stand/im-machine-patch.json tools/stand/run-im-binary.sh ~/Work/stand/bin/im
```

Снять патч: `rm ~/Work/stand/im-machine-patch.json` и запуск с `IM_TEST_SUPPORT= IM_MACHINE_PATCH=`.

## 4. Почему nginx подменяется скриптом

В `axxoncloudgo` нет маршрута на МИ: шлюз облака не знает ни `/api/v1/im-backend/`, ни `/im/`. В боевой выкладке маршрут есть, он лежит в `axxoncloud-deploy`. Чтобы не править репозиторий облака, `apply-nginx-dev.sh` собирает свою копию конфига и подкладывает её сервису `ac_nginx` через Swarm config. `make deploy` заново разворачивает стек и возвращает исходный конфиг, поэтому после него скрипт надо запустить снова.

## Ссылки

- [30-local-stand.md](../../research/integration/30-local-stand.md) — как подняли стенд, ловушки, прогоны проверок.
- [tools/stand-load/README.md](../stand-load/README.md) — скрипты нагрузки.
