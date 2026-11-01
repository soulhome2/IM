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
3. Go-модули без VPN: `source ~/go/offline-env.sh` (ставит `GOPROXY=file://$HOME/go/offline-proxy,https://proxy.golang.org` и `GONOSUMDB=src.axxonsoft.dev/*`). Цели `make dep` и `gen-bp-prepare` жёстко прописывают `GOPROXY=http://npm.itvgroup.ru:3000` — их не вызывать; `go mod download` выполнить вручную. Проверка: `go mod verify` — «all modules verified».
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

## Шаг 4: операторский API (этап 2)

Дата: 2026-10-29. Сервер: `~/Work/incident-manager-server`, ветка `feature/im_operator`. План этапа — [50-plan-stage2.md](50-plan-stage2.md), решение о пакете — `docs/adr/002-operator-api-package.md` в репозитории сервера.

**Тесты сервера локально.** База — отдельный контейнер `im-test-db` (`postgres:9.6`, `127.0.0.1:55432`), не база стенда:

```
cd ~/Work/incident-manager-server && source ~/go/offline-env.sh
make test-db-up        # из группы docker: sg docker -c "make test-db-up"
make test-local        # go test ./... с IM_TEST_DB_URL
```

**Контракт и генерация.** `make vendor-operator-contract` копирует контракт и машину из этого репозитория в `api/im/operator/` (коммит-источник — в файле `SOURCE`). `make gen-api-operator` перегенерирует пакет `operatorgen` форком `oapi-codegen` v0.11.0 без сети; `GOTOOLCHAIN=local`. Умолчание `GEN_GOPROXY` — корпоративный прокси, без VPN его не достать, а `~` в `file://` не раскрывается. Установка генератора без VPN: `source ~/go/offline-env.sh && make get-generator GEN_GOPROXY="$GOPROXY"` (в `$GOPROXY` уже раскрытый путь файлового прокси). Если генератор от форка уже стоит, `make get-generator` ничего не переустанавливает.

**Каталог и права.** Сервер при старте отправляет в облако ровно 14 прав машины (`PUT /ac/v1/global-permissions/catalog`; `filter.edit` и `track` убраны, `assign` → `assign.own`). Стенд после перезапуска сервера: процесс жив — облако каталог приняло (иначе сервер выходит при старте, причина — в конце `im-server.log`); `GET /operator/session` без токена → 401.

**Скрипты стенда** (`~/Work/stand/`, вне репозиториев):

| Скрипт | Что делает |
|---|---|
| `grant-im-permissions.sh` | Входит как `test@axxonnet.test`, читает `GET /roles/global`, у роли `cloud-admin` заменяет `incident_manager.*` на 14 имён из `workflow_schema.v1.json` (`permissions[].cloud`), `PATCH /roles/global`, затем печатает права `incident_manager` из `/me`. Повторный запуск безопасен. Запускать после очистки томов БД облака |
| `check-operator-api.sh` | 8 запросов через шлюз `https://axxonnet.test/api/v1/im-backend`: `/operator/session` без токена → 401 `UNAUTHENTICATED` (`problem+json`), с токеном → 200, 14 прав, `agentState` `offline`; `POST /test/reset` → 501 `NOT_IMPLEMENTED`; `GET /operator/incidents` → 501; `take` без `If-Match` → 428 `PRECONDITION_REQUIRED`; `/operator/me` → 404 `problem+json`; старый `GET /incidents` → 200, без токена → 401 с `key`. Строки `OK`/`FAIL`, код выхода — число `FAIL` |
| `sync-im-proto.sh` | `rsync` каталогов `prototype/` и `tests/` этого репозитория в `~/Work/axxoncloudgo/tools/compose/ui/im-proto/` (каталог `ui` в `.gitignore` облака, nginx стенда раздаёт его как есть) |

Права после `grant-im-permissions.sh` (`GET /api/v3/ac-backend/me`, `capabilities.incident_manager`) — 14: `manage`, `incidents.take.own`/`.any`, `incidents.assign.own`/`.any`, `incidents.process`, `incidents.suspend`, `incidents.close`, `incidents.unprocessed.close`, `incidents.release.use`, `incidents.reopen.use`, `incidents.bulk.use`, `incidents.actions.run`, `agent.not_ready.use`. Прав `filter.edit` и `track` нет.

**Страница тестов на стенде.** С того же адреса, что и облако (виден `localStorage.accessToken` от `dev-login.html`, CORS не участвует):

```
~/Work/stand/sync-im-proto.sh && D=$(mktemp -d) && google-chrome --headless=new --disable-gpu --no-first-run --ignore-certificate-errors --user-data-dir=$D --virtual-time-budget=60000 --dump-dom "https://axxonnet.test/dev-login.html?to=/im-proto/tests/api.html?api=https://axxonnet.test/api/v1/im-backend" | grep -o 'Тестовый стенд доступен — [^<]*'
```

Или в браузере: `https://axxonnet.test/dev-login.html?to=/im-proto/tests/api.html?api=https://axxonnet.test/api/v1/im-backend`. Ожидание после этапа 1 (прототип шлёт `Authorization: Bearer`): `POST /test/reset → 501`.

**Результат 2026-10-29: `→ 401`.** `prototype/api.js` пока ходит с cookie (`credentials: "include"`), заголовок `Authorization` не шлёт: пользователь отложил это вместе со входом. Страница доходит до сервера, но без токена получает 401, поэтому критерий «вход проходит» закрывает `check-operator-api.sh` (все проверки `OK`, код 0), а прогон `api.html` с ожидаемым `→ 501` переносится на момент, когда `api.js` начнёт слать токен.

**Временное на стенде** (удалить по окончании работ): копия прототипа `~/Work/axxoncloudgo/tools/compose/ui/im-proto/` (пересоздаётся `sync-im-proto.sh`; пропадает при новой распаковке `ui-AxxonNet.zip`) и контейнер `im-test-db` (`make test-db-down`); с этапа 3 — копии базы `~/Work/stand/backup/` (если их снимали) и скрипты `~/Work/stand/load-demo.sh`, `check-demo-intake.sh`.

## Шаг 5: событие → инцидент (этап 3)

Дата: 2026-10-29. План — [51-plan-stage3.md](51-plan-stage3.md), решение — `docs/adr/003-event-intake.md` в репозитории сервера. `POST /events` теперь сразу, одной транзакцией, создаёт инциденты события (выбор правил по §14.5, номера, переход `create`, журнал, отметка события); фонового обработчика нет.

1. **Миграции 014–016** сервер применяет сам при старте. Перед ними нужна копия базы: `sg docker -c "docker exec \$(docker ps -qf name=ac_db) pg_dump -U im imdb" > ~/Work/stand/backup/imdb-before-014.sql`. На этом стенде копию до миграций не сняли (сервер перезапускали без неё); перед следующими миграциями — снять. Миграция 014 нашла в `imdb` одну пару-дубль «событие + сценарий» и мягко удалила из неё инцидент №3 (строка осталась в базе, помечена удалённой). Живых дублей пары «тип устройства + `uid`» типа события не было, 016 ничего не сняла. Миграция 017 (убирает связи правил с архивными сценариями) дойдёт до стенда при следующем перезапуске сервера.
2. **Загрузка демо:** `~/Work/stand/load-demo.sh --replace-rules` — вход `test@axxonnet.test`, `agent-emulator sync` (6 типов устройств, 10 типов событий, 49 устройств), `agent-emulator demo-config` (приоритеты, группы источников, 9 сценариев «Демо: …», 10 правил «Демо: …»; правило «Стенд: тревога в офисе» удалено). Скрипт меняет данные стенда, не код. Нужен зарегистрированный агент (`enroll`, шаг 3).
3. **Повтор набора:** `~/Work/stand/bin/agent-emulator replay --run <метка>` — по событию на каждый `eventGuid` набора, с его `occurredAt`; guid события = `uuid5(eventGuid, метка)`, новая метка — новый прогон. Итог: `отправлено 27, пропущено 0`. Ответ `404 error.source.event.type.not.found` теперь ошибка (нужен `sync`), а не пропуск: тип события — пара «тип устройства + `uid`», `fire` камеры и `fire` датчика — две записи, поэтому принимаются все 27 событий.
4. **Проверка очереди:** `~/Work/stand/check-demo-intake.sh <метка>` — по базе сверяет каждое событие: номер тревоги, `processed`, инциденты по порядку (сценарий · приоритет · правило), номера внутри события подряд, между событиями растут. Строки `OK`/`FAIL`, код выхода — число `FAIL`.
5. **Ожидание «как в демо» — по правилам набора (§14.5), а не по снимку `demo.json`:** 27 событий → 30 инцидентов. По два инцидента у `…1834`, `…1847`, `…1851` (медпункт «Пожар в торговом центре» первым, номер тревоги — его, затем «Пожарная тревога»; группа «Торговый центр» содержит их устройства); у `…1838` побеждает правило датчика `…0a` (приоритет 100). Остальные — по одному, по правилу типа события. Номера начинаются не с 1: на стенде уже были инциденты прежних проверок.
6. **Повтор:** второй `replay` с той же меткой — `отправлено 27, пропущено 0`, число инцидентов не меняется; повтор одного события через `agent-emulator event --guid …` — 200, не 500; `panic` в `im-server.log` нет.

Результат 2026-10-29: `check-demo-intake.sh` — все 28 строк `OK`, код 0; число инцидентов до и после второго прогона одинаково.

## Шаг 6: переходы через HTTP (этап 4в)

Дата: 2026-10-31. План — [55-plan-stage4c.md](55-plan-stage4c.md) (уровень Г), решения — ADR-002 и ADR-005 сервера. Базы `imdb` и `ac_db` скрипты напрямую (SQL) не трогают.

1. **`check-operator-api.sh`** (обновлён): `agentState` теперь `ready`; запрос по случайному guid идёт `transitions/claim` без `If-Match` и ждёт `404` с `code = NOT_FOUND` (404 раньше 428); `GET /operator/incidents` по-прежнему `501`. Итог: `OK 16`, `FAIL 0`.
2. **`check-operator-transitions.sh`** (новый, `~/Work/stand/`, вне git; запускается руками, это не тест): настоящий токен `test@axxonnet.test` через шлюз, один инцидент от `agent-emulator`, дальше только HTTP: карточка, действия, `claim`, `hold`, `resume`, `transfer`, `accept`, `close`. Строки `OK`/`FAIL`/`SKIP`, код выхода — число `FAIL`. Итог: `OK 24`, `FAIL 0`, `SKIP 3`.
3. **Второй оператор** — `user@gmail.com` (переменная `SECOND_EMAIL`). Пароль скрипт берёт из файла `SECOND_PASS_FILE` (по умолчанию `~/Work/stand/second-operator.pass`, права `600`); в чат и в скрипт пароль не кладут. Вошёл — проверяются передача и приём; нет файла или вход не удался — `SKIP`. **Файла нет:** вход не пробовали, ветка двух операторов не выполнялась ни разу, три `SKIP` — это второй оператор, `transfer` и `accept`. Передача и приём на стенде **не проверены**; покрыты потоками через маршрутизатор и векторами (уровни А и Б).
4. **Правило доступа.** У `cloud-admin` не было правил, поэтому оператор не видел бы инциденты. Скрипт при первом запуске создал одно правило через старый HTTP API (`POST /access-rules`): guid `01a18ef7-cb72-7049-9109-bd03b0bcb516`, группа 1 `cloud-admin`, корень «Все камеры» (одна из 8 корневых групп источников). Оно **остаётся на стенде**: через операторский API `cloud-admin` видит только инциденты под этим корнем. Удалить (`TOKEN` — токен `test@axxonnet.test`; скрипт печатает ту же команду): `curl --cacert ~/Work/axxoncloudgo/tools/util/rootCA.axxonnet.test.pem -X DELETE -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '["01a18ef7-cb72-7049-9109-bd03b0bcb516"]' https://axxonnet.test/api/v1/im-backend/access-rules`.
5. **`IM_TEST_SUPPORT`.** Маршрут `POST /test/clock` и часы операторских маршрутов включаются только переменной окружения `IM_TEST_SUPPORT=true` сервера МИ (по умолчанию выключено; при включении сервер пишет предупреждение, и любой вошедший может двигать часы). На стенде переменная не нужна и не включена.
6. **Следы на стенде.** Три закрытых тестовых инцидента остались в `imdb`. Сервер МИ запущен из `~/Work/stand/bin/im` через `run-im-server.sh`.

С 2026-11-01 правил у `cloud-admin` восемь, по одному на корень: см. шаг 7, п. 3. Команда удаления из п. 4 снимает только первое.

## Шаг 7: поток через шлюз (этап 5а)

Дата: 2026-11-01. План — [56-plan-stage5.md](56-plan-stage5.md), уровни В и Г. Сервер: `~/Work/incident-manager-server`, коммит `69981c8`. SQL на запись руками не выполнялся, `ac_db` не менялась, пользователи облака не заводились.

1. **Миграции 019–021.** Сначала копия базы: `sg docker -c "docker exec \$(docker ps -qf name=ac_db) pg_dump -U im imdb" > ~/Work/stand/backup/imdb-before-019.sql` и проверка `test -s`. Затем остановка старого процесса и `run-im-server.sh`, сервер применяет миграции сам. В `im_db_migrations` стало 21 запись, последние — `019_operator_sessions.sql`, `020_queue_index.sql`, `021_stream_events.sql`. Журнал прежнего процесса — `~/Work/stand/im-server.before-019.log`.
2. **Поиск по кириллице.** `lc_ctype` базы `imdb` — `en_US.utf8`, как у `im-test-db`, а не `C`. Поиск `Проникновение`, `проникновение`, `ПРОНИКНОВЕНИЕ` даёт одно и то же число строк (28).
3. **Правила доступа.** Решение пользователя 2026-11-01: `cloud-admin` получает все 8 корневых групп, только на этом стенде. Правило в старом API — одна запись с одной целью, поэтому добавить группу в правило `01a18ef7-cb72-7049-9109-bd03b0bcb516` нельзя, можно завести рядом новые: `GET /access-rules` до, `POST /access-rules` с телом `{"userGroupId":1,"rules":[{"sourceGroupGuid":"<guid>"}, …]}` на 7 других корней, `GET /access-rules` после. Итог — 8 правил у группы 1, все 8 корней покрыты, первое правило на месте.

   **Откат только этого шага** снимает 7 новых правил поимённо, `01a18ef7-…` остаётся (`TOKEN` — токен `test@axxonnet.test`). Список из `GET /access-rules` сюда не подставлять: там все 8, и откатится ещё и шаг 6.

   ```
   curl --cacert ~/Work/axxoncloudgo/tools/util/rootCA.axxonnet.test.pem -X DELETE -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '["01a1957e-7ac1-770f-b44d-9e6450350fc1","01a1957e-7ac1-7710-8831-dd10b83f5cb7","01a1957e-7ac2-7710-9245-060f0979cbc7","01a1957e-7ac2-7711-9414-790aa88bfa0e","01a1957e-7ac2-7712-b0b2-9c93810960b4","01a1957e-7ac2-7713-983d-baa2cb976ac7","01a1957e-7ac3-7713-8cf2-13a243b479a6"]' https://axxonnet.test/api/v1/im-backend/access-rules
   ```

4. **Начальное состояние `offline`** (решение 76). Первым шагом каждого входа теперь идёт `PUT /operator/session/agent-state` с `{"agentState":"ready"}`, у второго оператора — до проверки `agentState`, иначе скрипт молча дал бы `SKIP`. Копии прежних скриптов — `~/Work/stand/backup/*.before-5a`.
5. **`check-operator-api.sh`** (обновлён): `GET /operator/incidents` теперь `200`, а не `501`; добавлены `PUT agent-state`, поля `items` и `total` страницы очереди, `GET /operator/incidents/counters`. Итог: `OK 19`, `FAIL 0`, это 16 прежних и 3 новых.
6. **`check-operator-transitions.sh`** (обновлён): итог `OK 25`, `FAIL 0`, `SKIP 3`. Это прежние 24 и строка `PUT agent-state`.
7. **`check-operator-stream.sh`** (новый, `~/Work/stand/`, вне git; запускается руками, это не тест): две `curl -N` через шлюз, настоящие токены, SQL нет. Строки `OK`/`FAIL`/`SKIP`, код выхода — число `FAIL`. Что проверяет:
   - событие от `agent-emulator` даёт `incident.created` в обоих потоках, переход `claim` — `incident.transitioned`, быстрее 2 с, значит, шлюз кадры не копит;
   - пинг приходит за 20 с;
   - первый кадр без `Last-Event-ID` — один `id`, без `data`; у каждого сообщения `id:` равен его `id`, строк `event:` нет;
   - обрыв: поток закрыт, инцидент закрывается, поток возвращается с `Last-Event-ID` и получает ровно пропущенное, сверено с другим потоком;
   - выдуманный `Last-Event-ID` (большое число и не число): первым идёт `stream.reset` с `id` конца ленты.

   **`X-Accel-Buffering` через шлюз не виден:** это указание шлюзу, nginx читает его и клиенту не передаёт (`proxy_hide_header` по умолчанию). Скрипт смотрит заголовок на прямом ответе сервера `127.0.0.1:5000`, а работу шлюза показывают задержки. Итог: `OK 34`, `FAIL 0`, `SKIP 1`; задержки 22–50 мс.
8. **Разные пользователи.** Файл `SECOND_PASS_FILE` есть и права `600` — второй вход, `PUT ready`, свой поток и обмен событиями: у каждого свой инцидент, `claim` и `close` одного приходят другому. Передача для этого не нужна. **Файла нет, поэтому разные пользователи через шлюз не проверены:** здесь оба потока — две сессии `test@axxonnet.test`.

   Что считается `SKIP`, а что `FAIL`, решает один файл на оба скрипта — `~/Work/stand/second-operator.sh`; в браузере то же правило в `ui-check/second-verdict.mjs`:

   | Случай | Итог |
   |---|---|
   | нет файла или права файла не `600` | `SKIP` |
   | вход отказал, ответ `4xx` | `SKIP` |
   | ответ `403`; в сессии нет нужного права | `SKIP` |
   | карточка `404` и у групп второго нет правил: группы — из `introspect-user-token`, как у сервера МИ, правила — из `GET /access-rules` | `SKIP` |
   | вход с `5xx`, `200` без токена, обрыв | `FAIL` |
   | `PUT` или сессия: `401`, `409`, `5xx`, обрыв | `FAIL` |
   | `agentState` не `ready` после удачного `PUT` | `FAIL` |
   | карточка `404`, когда правила есть или их не удалось узнать; карточка `401`, `5xx` | `FAIL` |
   | второго нет среди адресатов, а правила есть или их не удалось узнать (только `check-operator-transitions.sh`) | `FAIL` |
   | поток второго в браузере ответил не `200` и не `403` | `FAIL` |

   `FAIL` даёт ненулевой код выхода. Проверено на поддельном сервере, без файла пароля: п. 10.
9. **Браузер.** `~/Work/stand/two-windows.html` читает поток через `fetch` с `Authorization`, сам разбирает кадры, запоминает `id` и из кадра без `data`, после обрыва возвращается с `Last-Event-ID`; кнопки «Взять» и «Закрыть» работают по инциденту из поля. `~/Work/stand/ui-check/check-two-windows.mjs` открывает её в двух контекстах браузера. Страницу он отдаёт сам, перехватом запроса на адресе `https://axxonnet.test`: запросы идут с того же адреса, CORS не участвует, в каталог облака ничего не кладётся. Без файла итог — `SKIP`, **уровень Г под разными пользователями не выполнялся ни разу**.
10. **Проба кода второго пользователя.** Чтобы ветки не остались неисполненными, скрипты один раз запущены с `SECOND_EMAIL=test@axxonnet.test` и временным файлом с паролем этого же пользователя: `check-two-windows.mjs` — `OK 19`, `check-operator-stream.sh` — `OK 54`, `FAIL 0`. Это проверка кода скриптов, а не критерия: пользователь в обоих окнах один. Ветки отказа проверены отдельно: поддельный сервер, временные копии скриптов с заглушкой входа, настоящие `second-operator.sh`, `second-verdict.mjs` и `two-windows.html` в настоящем Chrome; 52 случая, каждый дал итог из таблицы п. 8 и верный код выхода. Обмен событиями через шлюз под разными пользователями так не проверить, это остаётся за настоящим файлом. Когда он появится, запустить `check-operator-stream.sh`, `check-operator-transitions.sh` и `node check-two-windows.mjs` из `ui-check`. Если `user@gmail.com` не в группе 1, итог будет `SKIP` «нет правил», и понадобится решение пользователя.
11. **Следы на стенде.** Двенадцать новых закрытых инцидентов в `imdb`: 9 — проверки и пробы задачи, 1 — повторный прогон при ревью, 2 — контрольные прогоны после правок. Сколько добавляет один запуск:

   | Скрипт | Без файла пароля | Со вторым оператором |
   |---|---|---|
   | `check-operator-api.sh` | 0 | 0 |
   | `check-operator-transitions.sh` | 1 | 1 |
   | `check-operator-stream.sh` | 1 | 3 |
   | `ui-check/check-two-windows.mjs` | 0 | 2 |

   Сессия `test@axxonnet.test` — `ready`. Лента `stream_events` хранит сообщения прогонов. Сервер МИ запущен из `~/Work/stand/bin/im` новой сборкой. Копия `imdb-before-019.sql` — временная, как и прежние копии базы.

Итог уровней на стенде: В — один пользователь, две сессии, все проверки `OK`; разные пользователи — `SKIP`. Г — `SKIP`. Разные пользователи подтверждены только уровнями А и Б (тесты сервера).

## Откат сборки

Старая сборка на базе с новыми миграциями не стартует. Откат делается так:

1. Остановить сервер МИ.
2. Снять дамп базы (`sg docker -c "docker exec \$(docker ps -qf name=ac_db) pg_dump -U im imdb" > ~/Work/stand/backup/imdb-before-rollback.sql`), проверить `test -s` на файл.
3. Вернуть базу одним из двух способов. Оба относятся только к базе `imdb` и никогда не делаются в `ac_db` или другой базе облака.
   - **Залить дамп нужного этапа.** Простой `pg_dump` не заливается в живую базу: будет «already exists». Поэтому базу пересоздают и заливают дамп (команды той же формы, что дамп выше):
     `sg docker -c "docker exec \$(docker ps -qf name=ac_db) psql -U im postgres -c 'DROP DATABASE imdb'"`,
     `sg docker -c "docker exec \$(docker ps -qf name=ac_db) psql -U im postgres -c 'CREATE DATABASE imdb OWNER im'"`,
     `sg docker -c "docker exec -i \$(docker ps -qf name=ac_db) psql -U im imdb" < ~/Work/stand/backup/imdb-before-019.sql`.
     Всё, что записано после снятия этого дампа (инциденты, сессии, лента), теряется. Какой дамп к какой сборке: `imdb-before-019.sql` (до миграций 019–021) подходит сборкам до 5а; `imdb-before-022.sql` подходит сборке 5а (21 миграция). Второго файла сейчас нет: он появится, только когда будет применена миграция 022 (Task 19 этапа 5б), и снимать его надо до применения.
   - **Выполнить `Down` лишних миграций** в обратном порядке и убрать их записи из `im_db_migrations`: колонка с именем миграции называется `id` (`DELETE FROM im_db_migrations WHERE id = '<имя файла миграции>'`). `Down` у 019 удаляет таблицу `operator_sessions`, у 021 — таблицу `stream_events`: **данные этих таблиц пропадут** (сообщения ленты, состояния и настройки операторов).
4. Запустить старую сборку.

Честная оговорка: защита есть только у сборок, начиная с той, где появилась проверка «database is newer than this build». Сборка 5а на стенде на такой базе упадёт паникой `index out of range` при старте. База при этом не портится: проверка стоит до применения миграций.

## Что дальше

Шаг 2 — сервер МИ и конфигуратор на стенде: план — [15, п. 6](15-deploy-configurator.md); сервер регистрирует каталог прав (`PUT /ac/v1/global-permissions/catalog` есть на ветке прав), после чего роли `incident_manager.*` назначаются группе. Для разработки — nginx стека проксирует `/im/` на Vite на машине, `/api/v1/im-backend/` — на сервер МИ из IDE.
