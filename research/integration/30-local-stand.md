# Локальный стенд облака: как подняли

Дата: 2026-10-28. Машина: виртуальная Ubuntu 26.04, 16 ядер, 30 ГБ памяти, диск 100 ГБ. Корпоративного VPN нет. Основа — инструкция облака `docs/run_cloud_on_local_machine.md`, её пересказ — в [04-axxoncloudgo.md](04-axxoncloudgo.md#локальный-запуск). Ниже — что пришлось сделать иначе и почему.

## Что где

| Что | Где | Откуда |
|---|---|---|
| Облако `axxoncloudgo` | `~/Work/axxoncloudgo`, ветка `epic/CLOUD-23284-perms-i18n` (`e51bd55`) | клон по https |
| Фронт облака `axxoncloud-ui` | `~/Work/axxoncloud-ui`, ветка `CLOUD-23284-epic-perms-catalog` (`83a04e5`) | клон по https, только для чтения |
| Интерфейс облака (собранный) | `~/Work/axxoncloudgo/tools/compose/ui` | Bamboo, сборка `ASIP-AX1047-3`, файл `ui-AxxonNet.zip`; копия и заметка — `~/Work/ui-artifacts/ASIP-AX1047-3/` |
| Образ `up/uploader` | загружен в Docker | Bamboo, сборка `ASIP-UP-22`, файл `uploader.img`; копия — `~/Work/ui-artifacts/ASIP-UP-22/` |
| Приватные Go-модули | `~/go/offline-proxy` (файловый GOPROXY) | архив `libs.zip` от коллег, распакован в `~/go/src/src.axxonsoft.dev/bitbucket/proj` |

Клоны лежат на диске машины, а не в общей папке `/mnt/hgfs`: там `vmhgfs-fuse`, права `777` у всех файлов, сборка и Docker медленнее.

## Шаги

1. Docker CE 29, buildx, compose, `docker swarm init --advertise-addr 127.0.0.1` (у машины два интерфейса — `ens33` и туннель `amn0`, без адреса Swarm не выберет). Пользователь в группе `docker`.
2. `/etc/hosts`: только `127.0.0.1 axxonnet.test`. Остальные имена из инструкции нужны, лишь если запускать сервис облака на машине вне Swarm.
3. Go-модули без VPN: `source ~/go/offline-env.sh` (ставит `GOPROXY=file://~/go/offline-proxy,https://proxy.golang.org` и `GONOSUMDB=src.axxonsoft.dev/*`). Цели `make dep` и `gen-bp-prepare` жёстко прописывают `GOPROXY=http://npm.itvgroup.ru:3000` — их не вызывать; `go mod download` выполнить вручную. Проверка: `go mod verify` — «all modules verified».
4. Генерация кода (`make gen-bp`, `make gen`) не нужна: сгенерированные файлы в репозитории, все сервисы `build-all` компилируются как есть.
5. Подмена базового образа `debian:bullseye` — см. «Ловушки», п. 1.
6. `sg docker -c "source ~/go/offline-env.sh && make build-all"` — 10 образов `ac/*`, около 10 минут.
7. `docker load -i ~/Work/ui-artifacts/ASIP-UP-22/uploader.img`.
8. `make deploy` — стек `ac`, 16 сервисов.
9. Пользователи — см. «Ловушки», п. 4. Пароль хранится как `hex(sha512(соль + пароль))` (`service/user/user_service.go`, `hashPasswordWithSalt`), так что пользователя с любым паролем можно завести прямо в базе. Заведены, оба в группе `cloud-admin`:
   - `user@gmail.com` / `password` (как в `local.mk`);
   - `test@axxonnet.test` / `Test12345!`, имя «Тест Оператор», язык `ru`.
   **Вход без ввода пароля (временно, удалить после работы со стендом):** `https://axxonnet.test/dev-login.html` — входит как `test@axxonnet.test` и открывает портал (`?to=/im/` — куда перейти после входа). Страница кладёт токены в `localStorage` под теми же ключами, что портал (`accessToken`, `refreshToken`, `isSocialAuth`; `axxoncloud-ui` `app/utils/storageHelper.ts`). Пользователя и страницу восстанавливает `~/Work/stand/ensure-dev-login.sh` — запускать после `make deploy`, очистки томов БД и новой распаковки `ui-AxxonNet.zip` (каталог `ui` при этом пересоздаётся).
10. Проверка: `https://axxonnet.test/` → 200; `POST /api/v3/ac-backend/users/login` с `{"email","password"}` → пара токенов; `GET /api/v3/ac-backend/me` с токеном → права `axxon_data, core, monitoring, sip, update_server` (`incident_manager` появится после регистрации каталога сервером МИ).

## Ловушки

1. **Debian 11 ушёл в архив.** `ac/backend` (`tools/docker/cloud.debug.Dockerfile`) ставит пакеты на `debian:bullseye`; `deb.debian.org` отдаёт 404 на `bullseye-security`. Решение без правки репозитория: локальный образ с тем же именем, у которого apt смотрит в `archive.debian.org` — Dockerfile в `~/Work/ui-artifacts/bullseye-archive.Dockerfile`, собрать `docker build -t debian:bullseye <папка>`. Остальные образы `build-all` на alpine/buster и apt не используют.
2. **`up/uploader` `build-all` не собирает**, а стек его ждёт. Образ — артефакт плана Bamboo `ASIP-UP`. Без хранилища (MinIO в стеке закомментирован) сервис падает при старте: `Endpoint: does not follow ip address or domain name standards`. Для МИ не нужен — `docker service scale ac_uploader=0`.
3. **Сборка `arpagent` оставляет мусор** в репозитории: `arpagent_with_cover`, `axxonrp/main/arpagent/pkgs.txt` — удалить.
4. **`make create-db-users` устарел**: колонка `users.user_group_id` переименована в `user_group_id_deprecated`, группа пользователя теперь в `users_user_groups`. Рабочая запись — по образцу `tools/k8s/configs/scripts_sql.sql`: `users` → `user_nodes` (`path = '1.u' || id`) → `users_user_groups` (группа 1 = `cloud-admin`); хэш пароля и соль — из `local.mk`.
5. **Bamboo API** — только по `https://build2.axxonsoft.dev/bamboo/rest/api/latest/…`; без `/bamboo` запрос висит без ответа. Нужен личный токен (`Authorization: Bearer`).
6. **Свою сборку фронта облака не сделать** без доступа к Artifactory: `@axxon-web/cloud-menu@1.4.5` → 401. Нам она и не нужна: портал не меняем, готовый `ui-AxxonNet.zip` из Bamboo достаточен. Конфигуратор МИ (`incident-manager`) зависит только от публичных npm-пакетов.

## Шаг 2: сервер МИ на стенде

Рабочие копии — `~/Work/incident-manager-server` и `~/Work/incident-manager`, ветка `feature/im_operator` (база — `develop` `b743797` и `master` `1fcfa25`).

1. База: роль `im` (пароль `im_local_dev`, локальный) и база `imdb` в `ac_db` (PostgreSQL 9.6). Миграции сервер применяет сам.
2. Запуск на машине: `~/Work/stand/run-im-server.sh` (настройки — `~/Work/stand/im-server.env`, журнал — `~/Work/stand/im-server.log`), порт 5000. `IM_CLOUD_URL=axxonnet.test` — сервер всегда ходит по `https://` (introspect), `IM_S2S_CLOUD_URL=127.0.0.1:8000` — служебные `/ac/v1/*` по `http://`. Сертификат стенда — `SSL_CERT_FILE=tools/util/rootCA.axxonnet.test.pem` только для этого процесса (закрытого ключа корневого сертификата в репозитории нет).
3. При старте сервер отправил каталог: `PUT /ac/v1/global-permissions/catalog` → 200, в облаке 9 прав `incident_manager.*` (на ветке прав облака; в `develop` маршрута нет).
4. Права роли `cloud-admin`: `PATCH /api/v3/ac-backend/roles/global` — тело **массив** ролей `[{id, name, permissions: [полный список], deprecated}]`, список прав заменяется целиком. После этого `/me` отдаёт `incident_manager` (`manage`, `incidents.assign/close/process/suspend/track`, `take` с областями `any`/`own`, `incidents.filter.edit`).
5. Проверка: сервер МИ с токеном облака — `GET /api/v1/im-backend/scenarios`, `/priorities`, `/incidents` → 200; без токена → 401.
6. **Сеть Docker → машина.** `vpn-killswitch` ставит `INPUT DROP` и пропускает только `lo`, туннели и локальную подсеть — контейнеры (`172.16.0.0/12`) до машины не доходят. Правило: `iptables -I KS_IN 1 -s 172.16.0.0/12 -p tcp -m multiport --dports 5000,5173 -j ACCEPT`; постоянно — строка в `/usr/local/bin/vpn-killswitch.sh` после правил `LOCAL_SUBNET` (скрипт вставки делает резервную копию).
7. **Шлюз.** `~/Work/stand/apply-nginx-dev.sh` берёт `tools/docker/nginx.anticonsul.conf`, вставляет перед `location /api/` два блока и подменяет `/etc/nginx/nginx.conf` сервиса `ac_nginx` через Swarm config (файл репозитория не меняется; после `make deploy` повторить):
   - `/api/v1/im-backend/` → сервер МИ `http://<шлюз docker_gwbridge>:5000`, без буферизации, `proxy_read_timeout 1h` — на будущее для потока событий;
   - `/im/` → Vite `:5173` с `Upgrade`/`Connection` для HMR, `Host: localhost:5173` (проверка хоста Vite).
8. **Конфигуратор.** `npm ci` (только публичные пакеты), `~/Work/stand/run-vite.sh` — Vite на 5173 с `VITE_API_URL=https://axxonnet.test`. **Важно:** без этой переменной прокси Vite по умолчанию шлёт `/api` в боевое облако заказчика `bezeq-pos1.axxoncloud.com` (`vite.config.ts`); через `axxonnet.test` до прокси Vite запросы не доходят, но при открытии `localhost:5173` — дошли бы.
9. Проверка: `https://axxonnet.test/dev-login.html?to=/im/source-groups` — конфигуратор внутри облака, вкладки «Группы устройств», «Сценарии», «Правила», «Группы доступа»; сервер МИ отдал ему `/sources` и `/sources/groups/tree` → 200.

10. Запись через интерфейс (2026-10-28, `test@axxonnet.test`): группа устройств «Стенд: Офис» (`POST /sources/groups`), сценарий «Стенд: проверка тревоги» с одним финальным шагом Comment (`POST /scenarios`, затем `PATCH /scenarios/{id}`), правило «Стенд: тревога в офисе» (`POST /incidents/rules`) — все 200, всё на месте после перезагрузки. В колонке «Пользователь» правила — «Тест Оператор»: сервер МИ берёт имя из облака по служебному `/ac/v1/users/{id}`.

Находки при проверке:
- **Приоритетов нет, и завести их в конфигураторе негде** (вкладок только четыре). На чистой установке правило не создать: поле «Приоритет*» пустое. Завели через API — `POST /api/v1/im-backend/priorities {name, value}` — четыре из эталонного набора прототипа: Критический 100, Высокий 75, Средний 50, Низкий 25.
- В списке приоритетов правила порядок по алфавиту, а не по значению.
- В консоли — предупреждение React о `key` внутри spread у пунктов выпадающего списка (Autocomplete) — безвредно.
- Кнопку «Сохранить» сценария закрывает открытая боковая панель шага — сначала закрыть панель.

Проверка интерфейса со щелчками: `~/Work/stand/ui-check` (puppeteer-core с установленным Chrome; `lib.mjs` — вход через `dev-login.html`, снимки в `shots/`, журнал ответов API ≥ 400 и ошибок консоли; примеры — `check-group.mjs`, `check-rule.mjs`).

Проверка интерфейса без окна: `google-chrome --headless=new --ignore-certificate-errors --user-data-dir=<tmp> --window-size=1440,900 --virtual-time-budget=30000 --screenshot=<файл.png> "https://axxonnet.test/dev-login.html?to=/im/…"`.

Сервер МИ (5000) и Vite (5173) слушают все интерфейсы, а killswitch пропускает входящие из локальной подсети — в домашней сети они видны. Для стенда допустимо; при работе в чужой сети запускать Vite с `--host 172.18.0.1`.

## Шаг 3: агент-эмулятор

Код — `~/Work/incident-manager-server/tools/agent-emulator/main.go` (ветка `feature/im_operator`, не закоммичен). Использует клиент сервера из `internal/im/handler/v1` — подпись HMAC и запросы те же, что в тестах сервера. Сборка: `source ~/go/offline-env.sh && go build -o ~/Work/stand/bin/agent-emulator ./tools/agent-emulator`.

| Команда | Что делает |
|---|---|
| `enroll --token <t>` | `POST /agents`; ключ (`agentGuid`, `keyId`, `secret`) — `~/.config/im-agent-emulator/key.json`, права 600 |
| `sync` | из `demo.json`: 6 типов устройств, 8 типов событий (тип устройства события — самый частый первый прибор инцидентов этого типа), 49 устройств |
| `event --device <id\|имя> --type <id> [--text] [--guid]` | одно событие; `payload`: `occurredAt`, `deviceName`, `text`, `site`, `emulator: true` |
| `replay [--limit N]` | по событию на каждый инцидент `demo.json` (источник — первое устройство инцидента) |

Флаги до команды: `--server` (по умолчанию `127.0.0.1:5000`), `--scheme https --server axxonnet.test` — через шлюз облака, `--fixture`, `--key-file`.

Токен регистрации — пользователем облака: `POST /api/v1/im-backend/agents/tokens` с телом `{"count":1}` (без тела создаётся ноль токенов, ответ всё равно 200), затем `GET /agents/tokens`.

Проверка 2026-10-28: камеры «Главный вход» и «Стойка ресепшн» — в группе «Стенд: Офис» (`POST /sources/groups/{guid}/memberships {sourceGuids}`), у правила «Стенд: тревога в офисе» условие «группа Стенд: Офис + тип события Проникновение» (`POST /incidents/conditions`).

| Событие | Ожидание | Результат |
|---|---|---|
| intrusion, «Главный вход» (в группе) | инцидент | инцидент за ~1 с: сценарий «Стенд: проверка тревоги», версия 2; имя — склейка «правило сценарий устройство» |
| intrusion, «Витрина у входа» (вне группы) | нет | нет |
| fire, «Стойка ресепшн» (камера) | — | **404** `error.source.event.type.not.found`: у типа события на сервере ровно один тип устройства (fire → fire-detector), событие от прибора другого типа отклоняется |
| повтор события с тем же `guid` | идемпотентно | **500** `duplicate key … events_pkey` — подтверждена находка [14, п. 2](14-im-backend-operator.md) |
| одно событие под два условия одного правила | один инцидент | **два инцидента** — подтверждена находка [14, п. 4](14-im-backend-operator.md) (второе условие после проверки удалено) |

Попутно: клиент сервера (`CodegenReqExec`) пишет в тексте ошибки `error %!w(<nil>)` — оборачивает пустую ошибку.

## Что дальше

Шаг 2 — сервер МИ и конфигуратор на стенде: план — [15, п. 6](15-deploy-configurator.md); сервер регистрирует каталог прав (`PUT /ac/v1/global-permissions/catalog` есть на ветке прав), после чего роли `incident_manager.*` назначаются группе. Для разработки — nginx стека проксирует `/im/` на Vite на машине, `/api/v1/im-backend/` — на сервер МИ из IDE.
