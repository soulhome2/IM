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
9. **Браузер.** `~/Work/stand/two-windows.html` читает поток через `fetch` с `Authorization`, сам разбирает кадры, запоминает `id` и из кадра без `data`, после обрыва возвращается с `Last-Event-ID`; кнопки «Взять» и «Закрыть» работают по инциденту из поля. `~/Work/stand/ui-check/check-two-windows.mjs` открывает её в двух контекстах браузера. Страницу он отдаёт сам, перехватом запроса на адресе `https://axxonnet.test`: запросы идут с того же адреса, CORS не участвует, в каталог облака ничего не кладётся. Без файла итог — `SKIP`; в этапе 5а уровень Г под разными пользователями не выполнялся, первый прогон — [шаг 10](#шаг-10-фильтр-выборка-второй-оператор-этап-5б).
10. **Проба кода второго пользователя.** Чтобы ветки не остались неисполненными, скрипты один раз запущены с `SECOND_EMAIL=test@axxonnet.test` и временным файлом с паролем этого же пользователя: `check-two-windows.mjs` — `OK 19`, `check-operator-stream.sh` — `OK 54`, `FAIL 0`. Это проверка кода скриптов, а не критерия: пользователь в обоих окнах один. Ветки отказа проверены отдельно: поддельный сервер, временные копии скриптов с заглушкой входа, настоящие `second-operator.sh`, `second-verdict.mjs` и `two-windows.html` в настоящем Chrome; 52 случая, каждый дал итог из таблицы п. 8 и верный код выхода. Обмен событиями через шлюз под разными пользователями так не проверить, это остаётся за настоящим файлом. Когда он появится, запустить `check-operator-stream.sh`, `check-operator-transitions.sh` и `node check-two-windows.mjs` из `ui-check`. Если `user@gmail.com` не в группе 1, итог будет `SKIP` «нет правил», и понадобится решение пользователя.
11. **Следы на стенде.** Двенадцать новых закрытых инцидентов в `imdb`: 9 — проверки и пробы задачи, 1 — повторный прогон при ревью, 2 — контрольные прогоны после правок. Сколько добавляет один запуск:

   | Скрипт | Без файла пароля | Со вторым оператором |
   |---|---|---|
   | `check-operator-api.sh` | 0 | 0 |
   | `check-operator-transitions.sh` | 1 | 1 |
   | `check-operator-stream.sh` | 1 | 3 |
   | `ui-check/check-two-windows.mjs` | 0 | 2 |

   Сессия `test@axxonnet.test` — `ready`. Лента `stream_events` хранит сообщения прогонов. Сервер МИ запущен из `~/Work/stand/bin/im` новой сборкой. Копия `imdb-before-019.sql` — временная, как и прежние копии базы.

Итог уровней на стенде в этапе 5а: В — один пользователь, две сессии, все проверки `OK`; разные пользователи — `SKIP`. Г — `SKIP`. Разные пользователи тогда были подтверждены только уровнями А и Б (тесты сервера). Теперь это не так: 2026-11-02 файл пароля появился, уровень Г пройден под разными пользователями, без `FAIL` и `SKIP`, см. [шаг 10](#шаг-10-фильтр-выборка-второй-оператор-этап-5б).

## Шаг 8: один пользователь не проходит как разные (этап 5б, задача 4)

Находка: в п. 10 шага 7 скрипты со вторым оператором `test@axxonnet.test` давали `OK` в шагах «разные пользователи», хотя оба оператора были одним пользователем. Воспроизведено до правки: `check-operator-stream.sh` — `OK 54`, `FAIL 0`, `SKIP 0`; `check-operator-transitions.sh` — `FAIL test@axxonnet.test нет среди адресатов инцидента` (себя среди адресатов нет), `SKIP transfer`, `SKIP accept`; `check-two-windows.mjs` — `OK 19`, `FAIL 0`.

Правка (файлы стенда вне git, копии — `*.before-5b`):

- `second-operator.sh`, `second_on_line`: после чтения `.operator.guid` второго читается `GET /operator/session` первого (`TOKEN`); код не 200 — отказ через `second_refused`, равный `operator.guid` — `SECOND_WHY="второй оператор — тот же пользователь"`, второй оператор не принимается. Сравнение здесь, а не с `FIRST_ID`: тот есть только в `check-operator-stream.sh`.
- `ui-check/second-verdict.mjs`: новая `sameUserVerdict(oneGuid, twoGuid)` — `{ skip: 'второй оператор — тот же пользователь' }` при равных guid, иначе `{ ok: true }`. `check-two-windows.mjs` вызывает её сразу после `connectVerdict`.

Запуск того же случая после правки (`SECOND_EMAIL=test@axxonnet.test`, временный файл пароля, удалён): `check-operator-stream.sh` — `OK 34`, `FAIL 0`, `SKIP 1` (`SKIP разные пользователи: второй оператор — тот же пользователь; …`); `check-operator-transitions.sh` — `SKIP второй оператор: …`, `SKIP transfer`, `SKIP accept`, `итого ошибок: 0`; `check-two-windows.mjs` — `SKIP разные пользователи в браузере: второй оператор — тот же пользователь`, `OK 2`. Без переменных причина прежняя: `нет файла …`. `sameUserVerdict('a','a')` — `skip`, `('a','b')` — `ok`.

Итог уровней эта правка не меняла: без файла пароля разные пользователи на стенде дают `SKIP`, теперь честно. С файлом они проверены через шлюз и в браузере, см. [шаг 10](#шаг-10-фильтр-выборка-второй-оператор-этап-5б).

## Шаг 9: точка входа оператора (этап 8)

План — [58](58-plan-stage8.md). Конфигуратор `~/Work/incident-manager`, ветка `feature/im_operator`. Случаи 1–14 прошли на `4018b91`, последний прогон всех 16 — на `36e4b93` (следующий коммит, тема ONE PSIM этапа 9, Vite отдаёт рабочее дерево; `http.ts` и `tokens.ts` те же). Адрес: `https://axxonnet.test/dev-login.html?to=/im/operator/`.

**Шлюз.** В `~/Work/stand/apply-nginx-dev.sh` после блока `/im/` добавлен второй блок (файлы облака не меняются, копия скрипта — `apply-nginx-dev.sh.before-8`):

```nginx
location /im/operator/ {
    proxy_pass http://<шлюз docker_gwbridge>:5173;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection $connection_upgrade_im;
    proxy_set_header Host localhost:5173;
    proxy_read_timeout 1h;
    expires off;
    add_header Cache-Control "no-cache";
    absolute_redirect off;
}
```

`absolute_redirect off;` убирать нельзя. До правки адрес без слэша `/im` наблюдался как `301`, `Location: http://axxonnet.test:8082/im/`: чужой незащищённый origin с пустым `localStorage`, как и предсказывало решение 122. С этой строкой `/im/operator?x=1` даёт `301`, `Location: /im/operator/?x=1`, запасной путь решения 122 не понадобился. У блока `/im/` такой строки нет, поэтому сам `/im` без слэша на стенде и сейчас уводит на порт 8082. Меню облака ведёт на `/im/`, этапу это не мешает.

**Запуск.** `~/Work/stand/apply-nginx-dev.sh` — один раз после `make deploy`, на секунды перезапускает `ac_nginx`. `~/Work/stand/run-vite.sh` — в фоне, порт 5173. `~/Work/stand/sync-im-proto.sh` — копия прототипа для встроенного сервера, `/im-proto/`, повторять после правок `prototype/`. Сервер МИ не нужен.

**Встроенный сервер.** `https://axxonnet.test/im/operator/?api=embedded`: страница работает на ответах прототипа, без облака и сервера МИ. Только под Vite: боевая сборка эту ветку выбрасывает.

**Проверка.** `cd ~/Work/stand/ui-check && node check-operator-entry.mjs` (номера случаев после имени — только они). Вход через `dev-login.html`, токены настоящие. Подделки только в браузере: короткий `exp` в `localStorage` и ответ `/me` для развилки, разных пользователей на стенде не заводим. Скрипт пишет в облако только то, что пишет само облако при входе и обновлении токена.

| # | Случай | Итог | Что наблюдалось |
|---|---|---|---|
| 1 | вход `/im/operator/` | `OK` | `ready`, нет `pageerror`; на снимке «Место оператора», «Сервер МИ недоступен», ссылка «Конфигуратор» |
| 2 | глубокая ссылка `/im/operator/incidents/42` | `OK` | `ready`, вкладки «Группы устройств» нет |
| 3 | адрес без слэша `/im/operator` | `OK` | итоговый адрес `https://axxonnet.test/im/operator/` |
| 4 | вызов API | `SKIP` | сервер МИ не запущен: шлюз 502, `authorization` равен `Bearer` + текущий токен, страница `ready`, `data-operator-api="error"` |
| 5 | встроенный сервер | `OK` | `ok`, `embedded`, на снимке «Иванов А. С.», 14 прав, ни одного запроса к `/api/v1/im-backend/` и `/ac-backend/me` |
| 6 | обновление заранее, заход на страницу | `OK` | `exp` через 60 с: один `POST …/auth/tokens` с 200, обе половины пары сменились, `ready`; `/me` ни разу не ответил 401 и не ушёл с поддельным токеном |
| 7 | два окна | `OK` | один `POST` на обе вкладки, одна из них скрыта; в обеих `ready`, пара одна |
| 8 | 401 | `OK` | `/me` 401, один `POST`, последний `/me` 200, `ready` |
| 9 | конец сессии | `OK` | второй `POST` с отработавшим refresh — 401, `session-ended`, ноль запросов `/users/logout`, пара в хранилище не тронута |
| 10 | только оператор | `OK` | `/im/` привёл на `/im/operator/`, `ready` |
| 11 | только конфигуратор | `OK` | `/im/operator/` привёл на `/im/…`, вкладка «Группы устройств» |
| 12 | нет прав | `OK` | `no-rights`, адрес не сменился |
| 13 | оба набора | `OK` | настоящий `/me`: `/im/` — конфигуратор, ссылка на `/im/operator/` есть |
| 14 | облако молчит | `OK` | `/me` 503: `cloud-unavailable` |
| 15 | открытая страница: обновление | `OK` | страница `ready`, в `localStorage` кладётся поддельный access с `exp` через 60 с. Через 18,7 с один `POST` с 200, обе половины пары сменились; других запросов к `/api/` нет, перезагрузки нет, `ready` |
| 16 | открытая страница: выход портала | `OK` | страница `ready`, пара стирается из `localStorage`, как при выходе из портала. Через 18,3 с `session-ended`; ноль запросов `/users/logout`, ни одного `POST`, перезагрузки нет |

Случаи 15 и 16 — хранитель токена на открытой пустой странице, он срабатывает раз в 20 с. Это единственные случаи, где страницу держат открытой: в 6–9 обновление идёт от запроса `/me` при заходе.

Что случаи могут упасть, проверено на копии скрипта: Chrome получал изменённый модуль через перехват запроса, файлы конфигуратора не менялись.

| Изменение в браузере | Случай 6 | Случай 15 | Случай 16 |
|---|---|---|---|
| без изменений | `OK` | `OK` | `OK` |
| `isRefreshDue` всегда `false` | `FAIL`: `/me` ответил 401 два раза и два раза ушёл с поддельным токеном | `FAIL`: за 25 с нет `POST`, пара не сменилась | `OK` |
| хранитель не смотрит на конец сессии | `OK` | `OK` | `FAIL`: за 25 с нет `session-ended` |

В строке с `isRefreshDue` случай 6 упал только на проверках `/me`: один `POST`, новая пара и `ready` при этом были, их даёт ветка 401, как в случае 8. Поэтому прежняя версия случая 6 обновления заранее не доказывала.

Итог уровней: Б — `OK`, В — `OK`, Г — `SKIP`. Ответ 200 настоящего сервера МИ на стенде не наблюдался: сервер лежит, и этот этап его не поднимал. Доказано другое: запрос ушёл через шлюз с настоящим токеном, а 502 страница показала как «Сервер МИ недоступен», не как конец сессии. Как только сервер поднимут, случай 4 сам даст `OK` или `FAIL`.

Здесь не проверено: срок токена буквально (решение 138): в случаях 6 и 15 подделан `exp`, страницу не держали дольше настоящего срока. Выход настоящего портала: в случае 16 пару стирает скрипт. Что один `POST` в случае 7 дал именно замок: скрытая вкладка могла просто прийти позже; замок проверен отдельным прогоном Chrome в задаче 1. Разные пользователи (развилка проверена подменой `/me`). Экран `operator:pageMissing` и уход в облако при `failed` (стенд отдаёт страницу оператора, а под Vite ухода в облако нет; это закрыто тестами и прогоном Chrome на сборке, задача 7).

Две особенности Chrome, из-за них скрипт отступает от буквы плана:

- Скрытая вкладка: `waitForSelector` опрашивает страницу через `requestAnimationFrame` и на ней стоит, хотя страница уже `ready`. В случае 7 первая вкладка скрыта, так что ожидание идёт через `waitForFunction` с опросом раз в 250 мс.
- `net::ERR_CERT_VERIFIER_CHANGED`: свежий Chrome изредка обрывает все запросы в полёте, примерно на 1 заход из 20. Упавший модуль оставляет пустую страницу. Скрипт повторяет случай с новым входом, до двух раз, и только при этой ошибке, с пометкой `ПОВТОР`. Другие падения не повторяются. В прогонах это было на случаях 11 и 14.

**Что удалить по окончании:** `~/Work/stand/ui-check/check-operator-entry.mjs`, снимки `shots/operator-*.png`, `apply-nginx-dev.sh.before-8`, копию прототипа `~/Work/axxoncloudgo/tools/compose/ui/im-proto`, если она больше никому не нужна, и остановить Vite.

**Откат:** `cp ~/Work/stand/apply-nginx-dev.sh.before-8 ~/Work/stand/apply-nginx-dev.sh`, затем `~/Work/stand/apply-nginx-dev.sh`. Блок `/im/` остаётся и ведёт на тот же Vite, пропадает только `301` с `/im/operator` на адрес со слэшем. `make deploy` сбрасывает подмену целиком.

## Шаг 10: фильтр, выборка, второй оператор (этап 5б)

Прогон 2026-11-02, задача 19 плана [57](57-plan-stage5b.md). Сервер МИ собран из `7aae579`, в `im_db_migrations` 21 запись, запуск — `~/Work/stand/run-im-server.sh`. Перед запуском снят дамп `~/Work/stand/imdb-before-5b-check.sql`, 304 788 байт. Второй оператор — настоящий вход `user@gmail.com` через облако, скрипты сами читают `~/Work/stand/second-operator.pass`, файл создал пользователь.

**Новая проверка.** `~/Work/stand/check-operator-filter.sh`, вне git, по образцу `check-operator-api.sh`: шлюз, настоящий токен, строки `OK`, `FAIL`, `SKIP`, в конце `итого ошибок: N`, код выхода равен числу `FAIL`. Скрипт проверяет `filter` (без токена, без условий, по типу устройства, событию и устройству, два условия через «ИЛИ», отказы `422` и `404`, `sameScenario`), `selection` (`explicit`, `all_in_filter`, пустой список `422`, не-guid и неизвестный `mode` `400`), отказ `400` на не-guid в массовом `hold`, адресатов `transfer` и уход закрытого инцидента из обоих списков. Он создаёт один инцидент через `replay` и сам его закрывает. Правильность классов он не доказывает: это уровень А, здесь только форма ответов и арифметика вариантов.

| Проверка | `OK` | `FAIL` | `SKIP` |
|---|---|---|---|
| `check-operator-filter.sh`, первый запуск после старта сервера | 55 | 0 | 1 |
| `check-operator-api.sh` | 19 | 0 | 0 |
| `check-operator-transitions.sh` | 33 | 0 | 0 |
| `check-operator-stream.sh` | 54 | 0 | 0 |
| `ui-check/check-two-windows.mjs` | 19 | 0 | 0 |
| `check-operator-filter.sh`, второй запуск, сервер уже видел второго оператора | 56 | 0 | 0 |

Запуск при ревью дал `OK 55`, `FAIL 0`, `SKIP 0`. В скрипте 56 строк итога, откуда разница в одну строку, не выяснено.

**Порядок запусков важен.** Адресаты идут из памяти процесса (решение 75 плана 56). Сразу после старта сервера второго оператора в ней нет, поэтому `check-operator-filter.sh` даёт `SKIP адресаты transfer`. Запускать его надо после `check-operator-stream.sh` или `check-operator-transitions.sh`, тогда строка становится `OK transfer доступен, адресатов: 1`.

**Разные пользователи.** Передача и приём впервые прошли на настоящем адресате через шлюз. `claim` и `close` каждого оператора дошли до другого за 23–33 мс, задержки за весь прогон 23–39 мс. В браузере каждое окно видело чужие `claim` и `close` без перезагрузки, поток открылся один раз. Это страница стенда `two-windows.html`: экран оператора на настоящем API — этапы 8–9.

**Следы на стенде.** В `imdb` прибавилось 8 закрытых инцидентов: фильтр 2, переходы 1, поток 3, два окна 2, и ещё 1 при ревью. Выросли `stream_events` и `operator_sessions`. В облаке ничего не менялось: пользователи не создавались, у группы 1 те же 8 правил. Сервер оставлен запущенным новой сборкой.

## Шаг: экраны оператора на встроенном сервере (этап 9)

Прогон 2026-11-03, задача 23 плана [59](59-plan-stage9.md). Части 1–3 этапа: очередь, карточка, выборка. Экраны идут на встроенном сервере прототипа, сервер МИ и базы не нужны и не трогаются.

**Запуск.** `~/Work/stand/run-vite.sh` — Vite на 5173, в фоне. `~/Work/stand/sync-im-proto.sh` — копия `prototype/`, `tests/` и `theme/` в `/im-proto/`, повторять после правок прототипа. Каталог `theme` копируется с задачи 2б: без него образец на стенде открывается без оформления. Адрес экранов — `https://axxonnet.test/im/operator/?api=embedded&colleagues=off`: встроенный сервер, коллеги прототипа не берут инциденты сами. Без `colleagues=off` поток живой, это сцена `stream`.

**Проверки.** Все — из `~/Work/stand/ui-check`, вне git, без входа в облако (кроме случая 5 точки входа, он входит через `dev-login.html`).

| Команда | Что | Итог прогона |
|---|---|---|
| `node check-operator-screens.mjs [сцена…]` | сверка стилей и текстов с прототипом, снимки `shots/op/`, контраст | все сцены, `итого ошибок: 0` |
| `node check-operator-flows.mjs [номер…]` | 18 проходов оператора, каждый с чистой страницы; подписи кнопок — слова руководства | `OK` 18, `FAIL` 0, `SKIP` 0 |
| `node check-operator-entry.mjs 5` | точка входа на встроенном сервере, имя из `[data-operator-name]` | `OK` |

**Точка входа и сервер МИ.** Случаи `check-operator-entry.mjs`, кроме 5, идут через вход и при поднятом сервере МИ пишут `Directory.Remember` в `imdb`. Поэтому при слушающем порте 5000 (`ss -ltn`) скрипт отвечает на них `SKIP сервер МИ поднят, вход записал бы в imdb`. Полный прогон — только при лежащем сервере. В случае 4 ответ `session` 200 и упавшая загрузка места (`data-api-status` 501, 502–504 или 0 — нет ответа за 30 с) — `SKIP`, а не `FAIL`; плохой ответ 200 остаётся `FAIL`.

**Ловушки.** Два прогона Chrome разом (снимки и проходы) дают `Navigation timeout`: запускать по очереди. На ширине 1020 у новой страницы панель групп 260 и без разделителя (задача 22а), а сцены `selection` и `filter-window` снимают прототип на 1440. Панель групп эти сцены поэтому не сверяют, её сверяет `shell-mid`.

**Что удалить по окончании:** `check-operator-flows.mjs`, `check-operator-screens.mjs`, копии `check-operator-screens.mjs.before-9` и `check-operator-entry.mjs.before-9`, снимки `shots/op/`.

## Шаг 11: планировщик и сценарий (этап 6)

Прогон 2026-11-03, задача 18 плана [60](60-plan-stage6.md). Сервер МИ собран из `9a17562` и запускается через `~/Work/stand/run-im-binary.sh ~/Work/stand/bin/im`. Прежний бинарник — `~/Work/stand/bin/im.before-6`. Перед первым стартом снят дамп `~/Work/stand/backup/imdb-before-024.sql`, 345 624 байт, сервер при этом был остановлен. В `im_db_migrations` теперь 24 записи: добавились 024, 025 и 026.

**Новые скрипты** (`~/Work/stand`, вне git). Пишут строки `OK`/`FAIL`/`SKIP` и в конце `итого ошибок: N`.
- `snapshot-operator-queue.sh [файл]` — снимок очереди через шлюз, только чтение.
- `im-machine-patch.sh` — пишет `im-machine-patch.json` по решению 210. Уровень 1 эскалации — второй оператор с `reactionSec` 60, потолок 1, алерты — первому, `idleHoldSec` 60, `idleReleaseSec` 120. id обоих берутся из `GET /operator/session`.
- `check-operator-scheduler.sh` — эскалация и молчание.
- `check-operator-scenario.sh` — сценарий из конфигуратора.

**Первый старт без патча.** Снимок до старта: 98 строк, из них 63 открытых.
- 31 открытая строка с просроченным таймером и `breaches: []`. После старта у всех 31 есть нарушение реакции, его `at` совпадает с прежним дедлайном. В журнале у каждой две записи `escalation_ceiling`, ключи `escalation_ceiling` и `alert_no_recipient`: уровни машины (`petrova`, `noc`) — не люди стенда. `escalationLevel` остался 0.
- 32 строки без таймера не изменились.
- `scenarioProgress.total` был 0 у всех открытых, стал больше 0 у всех. Например, INC-0012 — 2, INC-0017 — 5.
- Инцидентов `in_progress` и `on_hold` до старта не было, поэтому уход в `on_hold` после `Restart` ничего не задел.
- В логе нет отдельных строк о каждой миграции, только `all migrations applied without error`.

**С патчем.** Запуск: `IM_TEST_SUPPORT=true IM_MACHINE_PATCH=~/Work/stand/im-machine-patch.json run-im-binary.sh ~/Work/stand/bin/im`. В логе `Warn` «the machine is patched by IM_MACHINE_PATCH» с путём и sha256 итоговой машины.

| Проверка | `OK` | `FAIL` | `SKIP` |
|---|---|---|---|
| `check-operator-scheduler.sh`, первый запуск, ожидание 260 с | 5 | 1 | 0 |
| `check-operator-scheduler.sh`, ожидание 480 с | 9 | 0 | 0 |
| `check-operator-scenario.sh` | 15 | 0 | 0 |

**Эскалация ждёт до 480 с.** Уровень 1 наступает по нарушению реакции. У события эмулятора приоритет 75, норматив реакции у него 7 мин. Окна в 260 с не хватило. Повторный запуск: эскалация через 431 с, адресат — второй, уровень 1. Второй сделал `accept` и замолчал: через 70 с `on_hold` с причиной `no_link`, ещё через 60 с `new`.

**Сценарий.** Взят «Демо: Медпомощь при пожаре», шаги `RadioButton`, `Message`, `Comment`, без `Image`. Шаги:
- `claim`;
- три ответа, `filled` 0 → 1 → 2 → 3. `total` по пути вырос с 2 до 3: ответ «да» добавил шаг `ambulance`;
- `completedAt`, `requiredStepsFilled.closing` — истина;
- `close` с `processed` — 200;
- строка очереди: 3 из 3;
- второй открывает сценарий — 200, отвечает — 403 `PERMISSION_DENIED`.

**Патч снят.** Сервер остановлен, `rm ~/Work/stand/im-machine-patch.json`, запуск `IM_TEST_SUPPORT= IM_MACHINE_PATCH= run-im-binary.sh ~/Work/stand/bin/im`. `readlink /proc/<pid>/exe` — `bin/im`. Переменных в окружении процесса нет, `Warn` патча в логе нет. Этапы 7–9 работают без патча.

**Следы на стенде.**
- INC-0100 (`01a1a123-…`) из первого запуска проверки остался в `pending_acceptance` с адресатом `user@gmail.com`, уровень 1. Закрыт через API оператора 2026-11-03 (переход `close`, результат «Массовый сбой»), дамп `imdb-before-p62t1.sql`.
- Инцидент повторного запуска вернулся в `new`.
- Инцидент сценария закрыт.
- 31 строка с нарушениями и записями `escalation_ceiling`.

**Откат** — командами раздела «Откат сборки», по порядку:
1. Остановить сервер.
2. `DROP DATABASE imdb`, затем `CREATE DATABASE imdb OWNER im`.
3. Залить `~/Work/stand/backup/imdb-before-024.sql`.
4. `cp ~/Work/stand/bin/im.before-6 ~/Work/stand/bin/im`.
5. Запустить `run-im-binary.sh ~/Work/stand/bin/im`.
6. `rm -f ~/Work/stand/im-machine-patch.json`.

`Down` миграций 026–024 вернёт схему, но не данные планировщика: нарушения, записи `escalation_ceiling` и строки журнала у 31 строки. Их вернёт только дамп.

## Шаг 12: справочники, этап 7

Прогон 2026-11-03, задача 24 плана [61](61-plan-stage7.md). Сервер МИ собран из ветки `feature/im_operator_s7` (`daf3317`, в ней весь этап 6 до `9a17562`) обычной сборкой, без тега `imtest`. Запуск: `IM_TEST_SUPPORT= IM_MACHINE_PATCH= run-im-binary.sh ~/Work/stand/bin/im`. Прежний бинарник (сборка шага 11) — `~/Work/stand/bin/im.before-7`, sha256 `af1257c6…7237`. Перед первым стартом снят дамп `~/Work/stand/backup/imdb-before-030.sql`, 402 304 байт, сервер при этом был остановлен.

- `readlink /proc/<pid>/exe` — `bin/im`. `IM_MACHINE_PATCH` в окружении процесса нет.
- В `im_db_migrations` 27 записей: добавились `030_duty_groups`, `031_help_and_camera_links`, `032_priority_labels`. В логе, как и раньше, только `all migrations applied without error`.
- `check-operator-api.sh` — ошибок 0. В обычной сборке `POST /test/reset` теперь отвечает `404 NOT_FOUND` (решение 186), а не `501`. Ожидание в скрипте поправлено, прежний скрипт — `check-operator-api.sh.before-7`.
- `ui-check/check-queue-real.mjs raw` — FAIL 0. Справочники очереди (`priorities`, `device-types`, `event-types`, `scenarios`, `help-links`, `source-groups`, `transfer-targets`) — `200`.

**Откат** — командами раздела «Откат сборки», по порядку:
1. Остановить сервер (по pid с порта 5000).
2. `sg docker -c "docker exec \$(docker ps -qf name=ac_db) psql -U postgres postgres -c 'DROP DATABASE imdb'"`, затем `sg docker -c "docker exec \$(docker ps -qf name=ac_db) psql -U postgres postgres -c 'CREATE DATABASE imdb OWNER im'"`.
3. `sg docker -c "docker exec -i \$(docker ps -qf name=ac_db) psql -U im imdb" < ~/Work/stand/backup/imdb-before-030.sql`.
4. `cp ~/Work/stand/bin/im.before-7 ~/Work/stand/bin/im`, `cp ~/Work/stand/check-operator-api.sh.before-7 ~/Work/stand/check-operator-api.sh`.
5. `IM_TEST_SUPPORT= IM_MACHINE_PATCH= run-im-binary.sh ~/Work/stand/bin/im`.

Сборка шага 11 на базе с 030–032 не стартует (решение 192), поэтому без шагов 2–3 откат не работает.

## Шаг: экраны оператора на сервере МИ (этап 9)

Прогон 2026-11-03, задачи 25–27 плана [59](59-plan-stage9.md), часть 4 этапа.

**Сервер.** Экраны работают против сервера МИ сборки этапа 7 (`fb6f6d8`, миграции до 032). Сервер поднят потоком сервера, без `IM_TEST_SUPPORT` и `IM_MACHINE_PATCH`; этот этап его не перезапускал. Адрес — `https://axxonnet.test/im/operator/`, вход через `dev-login.html`.

**Записи в `imdb`.** Их разрешил пользователь 2026-11-03, условие — дамп перед каждой задачей: `~/Work/stand/backup/imdb-before-s9t25.sql`, `imdb-before-s9t25b.sql`, `imdb-before-s9t26.sql`, `imdb-before-s9t26b.sql`, `imdb-before-s9t27.sql`.
- Без `IM_STAND_WRITES=1` скрипты только читают.
- С записями — действуют только на свои инциденты: их создаёт `agent-emulator event` (`IM_STAND_EMIT=1`) или их называет `IM_STAND_INCIDENT`. Чужие строки очереди скрипты не трогают.
- Кнопки ищутся по точному имени. После каждой записи состояние сверяется через `GET /operator/incidents/{guid}`.
- В `finally` всё созданное прогоном закрывается без обработки.

**Проверки** — из `~/Work/stand/ui-check`, вне git.

| Команда | Что | Итог прогона |
|---|---|---|
| `node check-operator-server.mjs base` | таблица операций, очередь, дерево, карточка, журнал | `OK` 18, `FAIL` 0, `SKIP` 9 (записи не разрешены) |
| `IM_STAND_WRITES=1 IM_STAND_INCIDENT=INC-0032 node check-operator-server.mjs base` | плюс «Взять», «Отложить», «Возобновить», «Закрыть без обработки», перерыв, поток во втором окне | `OK` 26, `FAIL` 0, `SKIP` 1 (передать: адресатов нет) |
| `IM_STAND_WRITES=1 IM_STAND_EMIT=1 node check-operator-server.mjs selection` | отметка, «Все в фильтре», «Выделить по фильтру» с применением, «Взять в работу», «Отсоединить», массовое «Отложить» | `OK` 26, `FAIL` 0, `SKIP` 0 |
| `IM_STAND_WRITES=1 IM_STAND_EMIT=1 node check-operator-server.mjs scenario` | ответ, «Назад», новая ветка, «Итог», «Завершить инцидент» | `OK` 22, `FAIL` 0, `SKIP` 0 |
| `IM_STAND_WRITES=1 node check-operator-guide.mjs` | сценарий руководства, разделы 3–5 и 10, снимки `shots/op/guide-*.png` | `OK` 20, `FAIL` 0, `SKIP` 1 (передать: адресатов нет) |
| `IM_STAND_WRITES=1 IM_STAND_INCIDENT=… node check-operator-server.mjs close` | уборка: закрыть названные инциденты без обработки | — |

**Ловушки.**
- Место оператора держит поток открытым, и `networkidle0` не наступает. Поэтому вход идёт на `/favicon.ico`, а переход — с `domcontentloaded`.
- Vite стенда иногда не отдаёт модуль с первого раза (`ERR_FAILED`). Скрипт руководства делает одну повторную загрузку.
- Под открытой карточкой очередь скрыта, но её кнопки остаются в DOM. Невидимые кнопки пропускаются.
- Список шага Select множественный, меню после выбора не закрывается: его закрывает Escape.
- «Выделить по фильтру» применяется, только если «Подходит» равно числу своих инцидентов. Для этого события идут от «Торговый зал», у которого нет чужих открытых инцидентов.
- Предел `maxOnHold` 5 у оператора `test@axxonnet.test` занят чужими отложенными (INC-0042, INC-0017, INC-0047). Массовое «Отложить» упрётся в него, если накопится больше.

**Следы на стенде.**
- Созданы и закрыты без обработки инциденты INC-0102…INC-0141.
- INC-0032 из набора закрыт проходом задачи 25.
- Ранние прогоны задачи 25 (до правки скрипта) брали чужие строки. Состояние до них — в `imdb-before-s9t25.sql`.

**Что удалить по окончании:** `check-operator-server.mjs` с копией `.before-9`, `check-operator-guide.mjs`, снимки `shots/op/server-*.png` и `shots/op/guide-*.png`, дампы `imdb-before-s9t2*.sql`.

## Шаг: миграция 040 и передача двумя операторами (план 62, задача 8)

Прогон 2026-11-03. Сервер МИ собран из `6514b7d` и запускается через `~/Work/stand/run-im-binary.sh ~/Work/stand/bin/im` без `IM_MACHINE_PATCH`. Прежний бинарник — `~/Work/stand/bin/im.before-62`.

1. **Миграция 040.** Сначала копия базы: `~/Work/stand/backup/imdb-before-p62t8.sql` (711 460 байт), проверка `test -s`. Затем остановка старого процесса (порт 5000) и запуск новой сборки, сервер применяет миграцию сам. В `im_db_migrations` последняя запись — `040_operator_identity.sql`. У `operator_sessions` появились колонки `identity_ms` и `seen_ms`. В журнале ошибок `NewStore` нет.
2. **Откат миграции 040.** Остановить сервер. Вернуть `bin/im.before-62` на место `bin/im`. Затем одно из двух:
   - снять колонки и запись миграции (только база `imdb`):
     `sg docker -c "docker exec \$(docker ps -qf name=ac_db) psql -U im imdb -c 'ALTER TABLE operator_sessions DROP COLUMN IF EXISTS seen_ms, DROP COLUMN IF EXISTS identity_ms'"`,
     `sg docker -c "docker exec \$(docker ps -qf name=ac_db) psql -U im imdb -c \"DELETE FROM im_db_migrations WHERE id = '040_operator_identity.sql'\""`;
   - или залить дамп `imdb-before-p62t8.sql` по разделу «Откат сборки» ниже. Всё, что записано после дампа, теряется.

   Запустить старую сборку.
3. **Новый скрипт** `~/Work/stand/check-operator-transfer.sh` (вне git). Что делает: вход обоих, один инцидент от `agent-emulator replay --limit 1`, первый берёт его (claim), второй принимает передачу (transfer, затем accept). После каждого шага — `GET` карточки. Адресатов передачи первый смотрит до входа второго. `trap` на `EXIT` закрывает созданный инцидент без обработки и отдельной строкой проверяет `closed`. `IM_STAND_FAIL_AFTER=claim` — выход сразу после claim. Нет файла второго — `SKIP` и код 2.
4. **Итоги.** После перезапуска сервера второй оператор ещё не входил, а первый уже видел его в `GET /operator/transfer-targets?incidentGuid=…`. Адресаты теперь берутся из `operator_sessions` (задача 6). В `check-operator-filter.sh` строка `SKIP` о пустом списке адресатов заменена на `check` (FAIL). Результаты прогонов:
   - `check-operator-transfer.sh` — OK 15, FAIL 0, SKIP 0, код 0;
   - с `IM_STAND_FAIL_AFTER=claim` — выход после claim, уборка `closed`, код 0;
   - `check-operator-filter.sh` — 57/0/0;
   - `check-operator-api.sh` — 19/0/0;
   - `check-operator-transitions.sh` — 33/0/0;
   - `check-operator-scheduler.sh` — 5 OK, 1 FAIL: эскалации нет. Скрипту нужен сервер с патчем машины (`im-machine-patch.json`), а сервер запущен без патча. Инцидент этого прогона INC-0145 закрыт через API руками.
5. **Следы на стенде (план 62).** Все созданные инциденты закрыты по API. Task 1: INC-0100 закрыт. Task 8: два инцидента основного прогона и раннего выхода, плюс INC-0145 (планировщик). Task 11: INC-0147…0168 (image, отладка merge-skipped, ранний выход), все `closed`. Дампы базы: `imdb-before-p62t1.sql`, `imdb-before-p62t8.sql`, `imdb-before-p62t11.sql`, `imdb-before-p62t11b.sql`. В облаке остались сценарий «Демо: снимок» и тип события `snapshot`; правило «Демо: снимок — проверка стенда» удалено по имени, остальные «Демо: …» пересозданы. Скрипты стенда вне git, копии до правки — `*.before-62`.

## Откат сборки

Старая сборка на базе с новыми миграциями не стартует. Откат делается так:

1. Остановить сервер МИ.
2. Снять дамп базы (`sg docker -c "docker exec \$(docker ps -qf name=ac_db) pg_dump -U im imdb" > ~/Work/stand/backup/imdb-before-rollback.sql`), проверить `test -s` на файл.
3. Вернуть базу одним из двух способов. Оба относятся только к базе `imdb` и никогда не делаются в `ac_db` или другой базе облака.
   - **Залить дамп нужного этапа.** Простой `pg_dump` не заливается в живую базу: будет «already exists». Поэтому базу пересоздают и заливают дамп (команды той же формы, что дамп выше):
     `sg docker -c "docker exec \$(docker ps -qf name=ac_db) psql -U postgres postgres -c 'DROP DATABASE imdb'"`,
     `sg docker -c "docker exec \$(docker ps -qf name=ac_db) psql -U postgres postgres -c 'CREATE DATABASE imdb OWNER im'"`,
     У роли `im` нет права создавать базы, поэтому первые две команды идут под `postgres`, а заливка — под `im`.
     `sg docker -c "docker exec -i \$(docker ps -qf name=ac_db) psql -U im imdb" < ~/Work/stand/backup/imdb-before-019.sql`.
     Всё, что записано после снятия этого дампа (инциденты, сессии, лента), теряется. Какой дамп к какой сборке: `imdb-before-019.sql` (до миграций 019–021) подходит сборкам до 5а. Сборки 5а и 5б стоят на одной схеме (21 миграция), откат с 5б на 5а базы не трогает. Дамп перед этапом 6 (миграции 024–026) — `~/Work/stand/backup/imdb-before-024.sql`, он подходит сборкам 5а и 5б. Номера 022 и 023 не берутся никем (решение 193 плана 60), файла `imdb-before-022.sql` не будет: отложенные Task 8 и Task 21 плана 57 при возврате берут номера от 040, их дамп — `imdb-before-040.sql`.
   - **Выполнить `Down` лишних миграций** в обратном порядке и убрать их записи из `im_db_migrations`: колонка с именем миграции называется `id` (`DELETE FROM im_db_migrations WHERE id = '<имя файла миграции>'`). `Down` у 019 удаляет таблицу `operator_sessions`, у 021 — таблицу `stream_events`: **данные этих таблиц пропадут** (сообщения ленты, состояния и настройки операторов).
4. Запустить старую сборку.

Честная оговорка: защита есть только у сборок, начиная с той, где появилась проверка «database is newer than this build». Сборка 5а на стенде на такой базе упадёт паникой `index out of range` при старте. База при этом не портится: проверка стоит до применения миграций.

## Что дальше

Шаг 2 — сервер МИ и конфигуратор на стенде: план — [15, п. 6](15-deploy-configurator.md); сервер регистрирует каталог прав (`PUT /ac/v1/global-permissions/catalog` есть на ветке прав), после чего роли `incident_manager.*` назначаются группе. Для разработки — nginx стека проксирует `/im/` на Vite на машине, `/api/v1/im-backend/` — на сервер МИ из IDE.
