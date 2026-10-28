# Деплой, шлюз, раздача `/im/` и общие пакеты с конфигуратором

Дата: 2026-10-28. Второй круг, тема — боевой деплой и шлюз, раздача конфигуратора, вторая точка входа, общий код с конфигуратором, локальный стенд.

| Репозиторий | Как читали | Снимок |
|---|---|---|
| `IT/axxoncloud-deploy` (боевой деплой, найден в этом круге) | Bitbucket MCP | `master` = `91d1e6d25f3e5ff4273fc1277bf109970a8fcaec` (последний коммит 2026-10-28, CLOUD-23864) |
| `PROJ/incident-manager` (конфигуратор) | локально, только чтение | `master` `1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0` |
| `PROJ/axxoncloudgo` | Bitbucket MCP | `develop` `0228c7a9b1acf8faa62aa1097d6ec085882e8cf3` |
| `NEW/incident-manager-server` | локально, только чтение | `develop` `b743797a38daeb3beaa44ef901b26c3ce924290f` |
| Прочие репозитории проекта `IT` (`k3s-test`, `axxoncloud-local`, `axxoncloud-dc-local`, `etisalat-deploy`, `itvcloud-package`) | только поиск Bitbucket по `master` | — |

Обозначения: без пометки — факт со ссылкой; **Вывод:** — следует из фактов; **Предположение:** — не проверено. Поиск Bitbucket ищет по ветке по умолчанию; всё найденное в `axxoncloud-deploy` перечитано на снимке `91d1e6d`.

Ссылки на деплой: `D:` = `https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/`, суффикс `?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec`. Ссылки собраны внизу файла.

## Коротко

- **Боевой деплой найден:** `IT/axxoncloud-deploy` — Ansible (`ansible-hc/`) + consul-template; nginx и haproxy стоят на хостах (apt), сервисы — docker-контейнеры с `network_mode: host`, адреса upstream берутся из Consul. Конфиг nginx свой на каждого заказчика и стенд: `ansible-hc/config/<владелец>/<стенд|common>/nginx/nginx.conf.ctmpl[.j2]`.
- **МИ в бою уже есть** — на стендах Bezeq: `location /api/v1/im-backend` → upstream `im-backend` (сервис Consul `imbackend`, порт 5000) и `location /im` с `try_files $uri $uri/ /im/index.html` ([pos1#373][p373], [pos1#460][p460]; так же в `bezeq/common`). В `itv/common` есть только API-маршрут, раздачи `/im` нет ([itv#385][itv385]). В остальных ~15 конфигах (axxoncloud, inaxsys, safaricom…) МИ нет.
- **Кто раздаёт `ui-Default.zip`:** Bamboo-деплой «Incident Manager UI Deploy» (план-источник `ASIP-IN`, артефакт `ui-Default.zip`) → `deploy-im-ui.sh` → плейбук `deploy-im-ui.yml`: распаковать в `/data/axxoncloud/`, **удалить** `/data/axxoncloud/im/`, переименовать `ui` → `im` ([deploy-im-ui.yml#21][dimu21]). Окружения: Docker Hub, `d.itdep.net`, Bezeq POS1, Bezeq Test2. Бэкенд МИ — отдельный деплой «Incident Manager Deploy» из плана `ASIP-IM` (образ `imbackend.img`).
- **Вторая точка входа `/im/operator/`:** если положить её в тот же zip, деплой не меняется; но для глубоких ссылок нужен ещё один `location /im/operator` в каждом конфиге nginx с МИ (иначе `/im/operator/incidents/42` отдаст `index.html` конфигуратора). Отдельный zip в `/im/operator/` не выживет: каждый деплой конфигуратора удаляет весь `/data/axxoncloud/im/`.
- **Тайм-ауты в бою:** у `server` nginx `proxy_read_timeout 300s`; буферизация ответа для `/api/v1/im-backend` **включена** (по умолчанию nginx), в отличие от локального стенда (`proxy_buffering off` на весь `http`). Haproxy: роль `haproxy` — `timeout client 50s`, `server 300s`, `tunnel 1h`; роль `haproxy-like-bezeq` — `client 50000`, `server 1m`, без `tunnel`. Какая роль стоит на Bezeq — из кода не видно.
- **Общий код с конфигуратором:** формат сценария, Zod и JSONLogic уже лежат в `src/shared/` за барелем `@/shared/scenario`. Проигрыватели шагов и движок — в `features/preview`. ESLint запрещает импорт `preview` **только** из `editor` и `scenarios`, новая фича может импортировать его без ошибки линтера. Четыре правила «только через `@/shared/scenario`» написаны с перепутанными `target`/`from` и ничего не запрещают. Связки, которые мешают вынести код в пакет: синглтон `i18n` внутри Zod, валидации и движка; глобальные `add_operation` JSONLogic.
- **Рекомендация:** вторая точка входа (Vite multi-page) в том же репозитории, тот же zip; общий код — в `src/shared/` (движок и проигрыватели — в отдельный модуль), без npm-пакета на первом этапе. Отдельный репозиторий — только при отдельной команде и своём цикле релизов.
- **Тема и 401:** тёмной темы нет (`palette.mode: 'light'`, 83 цвета зашиты в 20 файлах). OEM-тема — алиас `@/theme` → `oem/<VITE_VENDOR_NAME>/theme.ts`, в репозитории только `Default`. Общего HTTP-клиента нет: `authHeaders` повторён в 4 файлах плюс свой `fetch` в `/me`; 401 не обрабатывается.
- **Локальный стенд:** план из 9 шагов (раздел 6). Главные ловушки: `IM_CLOUD_URL` — всегда `https://`, контейнеру нужны имя `axxonnet.test` и доверие к сертификату стенда; zip конфигуратора распаковывается в папку `ui/` — если распаковать его в `tools/compose`, он смешается с порталом; `make clear-test` сервера МИ удаляет **все** контейнеры машины.

## 1. Боевой конфиг шлюза: где `/api/v1/monitoring`, есть ли `/im/` и `/api/v1/im-backend/`

**Ответ.**

Где искал: глобальный поиск Bitbucket по `"api/v1/monitoring"`, `im-backend`, `"location /im"`, `"/im/index.html"`, `incidentmanager`, `"timeout server"`; список проектов (11 шт.). Боевой деплой — в проекте `IT`:

| Репозиторий | Что это | `/api/v1/monitoring` | `/api/v1/im-backend` | `/im` |
|---|---|---|---|---|
| `IT/axxoncloud-deploy` | Ansible-деплой облака на заказчиков (Bezeq, ITV, Axxoncloud, Safaricom, Inaxsys, Zaintech, Grundig2…), Bamboo-specs деплоев | есть во всех ~17 конфигах nginx | `bezeq/common`, `bezeq/pos1`, `itv/common` | `bezeq/common`, `bezeq/pos1` |
| `IT/etisalat-deploy` | ответвление того же Ansible для Etisalat | есть | нет | нет |
| `IT/k3s-test` | Helm-чарт `helm/axxoncloud` (k3s) | есть | нет | нет |
| `IT/axxoncloud-local`, `IT/axxoncloud-dc-local` | docker-compose стенды | есть | нет | нет |
| `IT/itvcloud-package` | пакет on-prem | есть | нет | нет |
| `PROJ/axxoncloudgo` | локальный стек | нет | нет | нет |

Как устроен боевой шлюз (на примере Bezeq POS1 — того самого стенда, на который по умолчанию проксирует dev-сервер конфигуратора, [vite.config.ts#43][vite43]):

- haproxy на хосте (`apt`, роль `haproxy` или `haproxy-like-bezeq`) → `nginx-pool-http` / `nginx-pool-http2` → nginx на хостах группы `name-nginx-cluster`.
- nginx тоже ставится из `apt` ([roles/nginx/tasks/main.yml#19][ngxrole19]); конфиг — шаблон consul-template `/etc/nginx/nginx.conf.ctmpl`. Роль `nginx-conf-update` берёт файл стенда `config/<владелец>/<стенд>/nginx/…`, а если его нет — `config/<владелец>/common/nginx/…` ([nginx-conf-update#8][ncu8], [#47][ncu47]).
- upstream собираются из Consul: `{{range service "imbackend"}} server {{.Address}}:{{.Port}} …{{else}}server 127.0.0.1:65535; # force a 502{{end}}` ([pos1#147][p147]). Пока сервиса нет в Consul, маршрут отвечает 502.
- Маршруты POS1: `/api/v1/monitoring` → `monitoring` ([pos1#349][p349]); `/api/v1/im-backend` → `im-backend` ([pos1#373][p373]); `/api/v1/configsync/internal` → `return 403` (закрыт снаружи); `/api/` → `backend`; статика: `/` из `/data/axxoncloud/html`, `/im`, `/reports-ui`, `/update-service`, `/dd` из `/data/axxoncloud/<имя>` с `try_files … /<имя>/index.html` ([pos1#460][p460]).
- Сервер МИ запускается ролью `incidentmanager`: образ `im/backend`, контейнер `imbackend`, порт 5000, регистрация в Consul с проверкой `api/v1/im-backend/heartbeat` ([incidentmanager/tasks#17][imrole17]). Контейнер стартует, только если у стенда есть файл `docker/imbackend.env` ([service-container-starter#10][scs10]); сеть — `network_mode: host` ([scs#74][scs74]).
- `imbackend.env` есть у `bezeq/pos1` (не демо: `IM_CLOUD_URL=bezeq-pos1.axxoncloud.com`, отдельная база в общем `db:5432`; логин и пароль БД лежат в файле открытым текстом, `IM_S2S_CLOUD_URL=backend:8000`, порт 5000) и у `bezeq/stage2` (`IM_CLOUD_URL=demo` — демо-режим) ([pos1 imbackend.env][penv], [stage2 imbackend.env][s2env]).

**Вывод:** маршрут `/api/v1/im-backend` и раздача `/im` уже есть в бою, но только у Bezeq. Чтобы включить МИ у другого заказчика, DevOps добавляет в его `nginx.conf.ctmpl` upstream `im-backend` и оба `location`, кладёт `docker/imbackend.env` и добавляет окружение в Bamboo-specs `IncidentManager*.yaml`.

**Вывод:** POS1 работает не в демо-режиме, значит при старте сервер МИ регистрирует каталог прав через `PUT /ac/v1/global-permissions/catalog` ([03](03-im-server.md#устройство-и-запуск)). Если на POS1 сервер МИ поднят, то облако там собрано с этим маршрутом (видимо, из ветки прав) — проверить у DevOps.

**Не по теме, но заметно:** в `axxoncloud-deploy` открытым текстом лежат логин и пароль БД МИ, ключ `IM_AES_ENCRYPTION_KEY` (одинаковый на POS1 и Test2) и закрытый ключ сервисного аккаунта Google (`bezeq/pos1/rc.json`). Значения сюда не переношу.

**Доказательства:** [pos1 nginx][p373], [bezeq/common#358][bc358], [bezeq/common#453][bc453], [itv/common#147][itv147], [incidentmanager/tasks][imrole17], [service-container-starter][scs10], [nginx-conf-update][ncu8].

**Уверенность:** подтверждено кодом (снимок `91d1e6d`). Что реально развёрнуто на хостах сейчас — из репозитория не видно.

**Что спросить у людей.** DevOps облака (последние коммиты в `axxoncloud-deploy` — Feliks Fanziev; права на деплой МИ UI — `stanislav.lapshansky`, группа `cloudDvpsEdit`, [IncidentManagerUI-p.yaml#6][imuip6]):
1. На каких стендах МИ сейчас реально работает (POS1, Test2, `d.itdep.net`)? Где он будет у первого заказчика с оператором?
2. Какая роль haproxy стоит на Bezeq: `haproxy` или `haproxy-like-bezeq`?
3. Почему в `itv/common` есть `/api/v1/im-backend`, но нет `/im`?
4. Убрать ключи из репозитория в хранилище секретов (Bamboo/Vault)?

## 2. Кто раздаёт `ui-<вендор>.zip` под `/im/`, где fallback; как добавить `/im/operator/`

**Ответ.**

Цепочка от кода до браузера:

1. Конфигуратор: `make build` → для каждого каталога в `oem/` `vite build` и `zip -r ui-<вендор>.zip /ui`, где `/ui` — смонтированный `dist/` ([Makefile#61][mk61], [#68][mk68]). В архиве один корневой каталог `ui/`. В `oem/` на `1fcfa25` только `Default`, значит архив один — `ui-Default.zip`.
2. Bamboo: план сборки `ASIP-IN` (имя — из `source-plan` деплоя). Деплой «Incident Manager UI Deploy» берёт артефакт `ui-Default.zip` ([IncidentManagerUI.yaml#5][imui5], [#25][imui25]).
3. Окружения деплоя: «Docker Hub» — образ `docker/ui/Dockerfile` (alpine, копирует `ui/` в том `/ui`, [Dockerfile][uidock]); «d.itdep.net» — выгрузка `upload-d.itdep.net.sh incidentmanager-ui`; «Bezeq POS1» и «Bezeq Test2» — `deploy-im-ui.sh pos1|2 bezeq` ([#63][imui63]).
4. `deploy-im-ui.yml` на хостах `name-nginx-cluster`: `unarchive` в `/data/axxoncloud/` → удалить `/data/axxoncloud/im/` → `mv /data/axxoncloud/ui /data/axxoncloud/im` ([deploy-im-ui.yml#21][dimu21], [#27][dimu27], [#32][dimu32]). Портал выкладывается так же, только в `html` ([deploy-ui.yml#27][dui27]).
5. nginx раздаёт `/im` из `/data/axxoncloud` с fallback `try_files $uri $uri/ /im/index.html`, `expires 15m` ([pos1#460][p460]).

В локальном стеке облака (`axxoncloudgo` `develop`) ни `/im`, ни `/api/v1/im-backend` нет; `location /` отдаёт `index.html` портала на любой путь ([nginx.anticonsul.conf#276][ngx276]); `include servers/*;` стоит на уровне `http`, после `server` — туда можно положить только целый `server {}` ([#362][ngx362]).

**Как добавить вторую точку входа.** Три варианта и что меняется в деплое:

| Вариант | Сборка | Деплой (`deploy-im-ui.yml`) | nginx |
|---|---|---|---|
| Раздел того же SPA (`/im/operator/*` — маршрут того же роутера) | без изменений | без изменений | без изменений: `location /im` уже отдаёт `/im/index.html` |
| Вторая точка входа в том же zip (`dist/operator/index.html`) | Vite multi-page (раздел 4) | без изменений: каталог `operator/` приедет внутри `ui/` | добавить `location /im/operator { root /data/axxoncloud; try_files $uri $uri/ /im/operator/index.html; }` в каждый конфиг с МИ (`bezeq/common`, `bezeq/pos1`, далее у новых заказчиков). Без него `/im/operator/` откроется (сработает `$uri/` + `index`), а глубокая ссылка `/im/operator/incidents/42` получит `index.html` конфигуратора |
| Отдельный бандл, свой zip | свой репозиторий или своя цель Makefile | **нельзя** класть в `/im/operator/`: каждый деплой конфигуратора удалит `/data/axxoncloud/im/` целиком. Нужен свой каталог (например `/data/axxoncloud/im-operator`), копия плейбука и своё окружение Bamboo | свой `location /im-operator {…}`. Внимание: `location /im` без `/` на конце — префикс, он ловит и `/im-operator`, поэтому свой `location` обязателен |

Ещё две вещи, которые стоит поменять вместе с точкой входа:

- `expires 15m` стоит на весь `/im`, включая `index.html` ([pos1#460][p460]). После релиза браузер до 15 минут держит старый `index.html`, а старые файлы с хэшами плейбук уже удалил. Страницы конфигуратора грузятся лениво ([router.tsx#14][router14]), поэтому открытая вкладка получит 404 на чанк. У портала в локальном конфиге для `index.html` есть отдельный `location` с `Cache-Control: no-cache` ([nginx.anticonsul.conf#237][ngx237]). Для оператора нужно то же (`location = /im/operator/index.html`) и обработчик `vite:preloadError` с перезагрузкой страницы.
- Обходной путь без правки nginx — hash-история роутера для оператора (`/im/operator/#/incidents/42`). TanStack Router это умеет, но адреса становятся некрасивыми, а ссылки из уведомлений — длиннее. Это запасной вариант, если DevOps не успевает.

**Доказательства:** выше по тексту.

**Уверенность:** подтверждено кодом; кто именно нажимает деплой и как часто — не видно.

**Что спросить у людей.**
- DevOps: согласны ли добавить `location /im/operator` (и `location` для потока событий, раздел 3) в шаблоны Bezeq и в шаблон для новых заказчиков? Можно ли убрать кэширование `index.html` под `/im`?
- Команде конфигуратора: Bamboo-план `ASIP-IN` собирает только `master` или и ветки? Планируются ли OEM-вендоры кроме `Default`?

## 3. Тайм-ауты шлюза для долгих соединений (боевые конфиги)

**Ответ.** Факты по `axxoncloud-deploy`:

| Звено | Настройка | Где |
|---|---|---|
| nginx, `server` | `proxy_read_timeout 300s`, `keepalive_timeout 65` | [pos1#248][p248] |
| nginx, `location /api/v1/im-backend` | только `common-api-header-directives.conf` и `common-gzip-directives.conf`; **нет** `proxy_buffering off`, `proxy_http_version 1.1`, своего `proxy_read_timeout` | [pos1#373][p373], [api-header][hdr], [gzip][gz] |
| nginx, WebSocket вебклиента | `proxy_read_timeout 86400` | [ws-proxy-pass][wspp] |
| nginx, `arp-gateway` WS и события | `proxy_read_timeout 300s` | pos1, рядом с `#arpgateway` |
| haproxy, роль `haproxy` | `timeout client 50s`, `timeout server 300s`, `timeout tunnel 1h`; 443 — `mode tcp` | [haproxy#38][ha38] |
| haproxy, роль `haproxy-like-bezeq` | `timeout client 50000`, `timeout server 50000`; у `nginx-pool-http` и `-http2` — `timeout server 1m`; `tunnel` не задан; 443 — `mode tcp` | [like-bezeq#38][hb38], [#98][hb98] |
| `api-header` (на все API) | `Cache-control: no-store`, CORS с `$http_origin`, в `Allow-Headers` нет `Last-Event-ID` и `If-Match` | [api-header][hdr] |

**Вывод** (по документации nginx/haproxy, не из кода):
1. Без `proxy_buffering off` nginx буферизует ответ upstream, и события SSE могут доходить пачками. Есть два способа: сервер МИ шлёт заголовок `X-Accel-Buffering: no` — nginx его учитывает без правки конфига; или DevOps добавляет отдельный `location /api/v1/im-backend/operator/stream` с `proxy_buffering off; proxy_http_version 1.1; proxy_set_header Connection ""; proxy_read_timeout 1h;`.
2. Самое короткое ожидание бездействия на пути — 50 с (`timeout client` haproxy, если `tunnel` не задан). Пустой комментарий в поток каждые 20–25 с перекрывает все звенья, включая 300 с у nginx. Это сходится с выводом 00-summary («чаще 30 с»).
3. `gzip_types` не включает `text/event-stream`, поток сжиматься не будет — это хорошо.
4. Локальный стенд не покажет проблему буферизации: там `proxy_buffering off` на весь `http` ([nginx.anticonsul.conf#31][ngx31]). На стенде стоит включить буферизацию в `location` МИ, чтобы вести себя как в бою.
5. Same-origin, поэтому отсутствие `Last-Event-ID` в CORS-заголовках не мешает.

**Уверенность:** значения — подтверждено кодом; поведение буферизации — вывод по документации; какая роль haproxy стоит на Bezeq — не найдено.

**Что спросить у людей.** DevOps: роль haproxy на Bezeq; согласны ли на отдельный `location` для потока или на заголовок `X-Accel-Buffering` (второе не требует их правки).

## 4. Общий пакет с конфигуратором

### 4.1 Что где лежит и насколько легко вынести

| Что | Где | Размер | Зависимости, мешающие выносу |
|---|---|---|---|
| Типы сценария | `src/shared/types/scenario.ts` | 178 строк | нет |
| Zod-схема сценария | `src/shared/schema/scenario.zod.ts` | 165 | `import i18n from '@/shared/i18n/config'` — тексты ошибок через глобальный `i18n` ([scenario.zod.ts#3][zod3]) |
| Валидация | `src/shared/lib/validation.ts` | 332 | тот же синглтон `i18n` ([validation.ts#2][val2]) |
| JSONLogic с переопределениями `in`, `==`, `!=` | `src/shared/lib/jsonLogic.ts` | 100 | `jsonLogic.add_operation` при загрузке модуля, глобально ([jsonLogic.ts#34][jl34], [#53][jl53], [#59][jl59]) |
| Барель домена | `src/shared/scenario/index.ts` | 12 | — ([index.ts#5][bar5]) |
| Движок предпросмотра | `features/preview/lib/playerEngine.ts`, `playerNavigation.ts`, `playerTypes.ts`, `selectDefaults.ts`, `previewDatetime.ts` | ~450 | `playerEngine` берёт глобальный `i18n` для текста значений ([playerEngine.ts#3][pe3]) |
| Проигрыватели 7 типов шагов + карточка + диспетчер | `features/preview/components/step-player/*` | ~630 | MUI, `react-i18next` (пространство `preview`), `@/shared/lib/styles` |
| HTTP-клиент | нет: `authHeaders` повторён в 4 файлах + свой `fetch` в `/me` | — | раздел 5 |

**Вывод:** домен (типы, Zod, валидация, JSONLogic) уже вынесен в `shared` и отделён барелем — его можно отдать второй точке входа без перемещений. Чтобы сделать из него npm-пакет, нужно:
- убрать синглтон `i18n` из Zod, валидации и движка (передавать функцию перевода параметром или возвращать коды ошибок);
- объявить `json-logic-js` как `peerDependency`. Если на странице окажутся две копии `json-logic-js`, переопределения встанут не в ту копию, и условия выбора молча начнут считаться по-старому.

Проигрыватели шагов вынести просто: они зависят только от домена, MUI, своего пространства переводов и `createStyles`. Остальной предпросмотр (`ScenarioPlayer`, `FinishPreviewScreen`, таймлайн, диаграмма) — специфичен для предпросмотра, его не трогать.

**Вывод:** для оператора годятся не все правила движка предпросмотра: значения по умолчанию у `Select` «для предпросмотра» ([scenario.ts, `default`][types13]), `userId: null` в протоколе, навигация «назад» по истории. Правила прохождения в IM задаёт машина сценариев (`Specification/Scenario_machine/`). Перед повторным использованием `playerNavigation` его надо сверить с ней.

### 4.2 Запрет ESLint на `preview` — что на самом деле запрещено

Правило — `import/no-restricted-paths` в `eslint.config.js` ([#43][es43]). В нём `target` — файлы, **в которых** запрещён импорт, `from` — откуда импортировать нельзя.

| Зона | Что делает на деле |
|---|---|
| `shared` ← `features`, `features` ← `app`, `shared` ← `app` | работает |
| `editor` ← `preview`, `preview` ← `editor` | работает; исключение — `eslint-disable` в `StepPreviewModal.tsx` ([StepPreviewModal.tsx#2][spm2]) |
| `scenarios` ← `editor`, `scenarios` ← `preview` | работает |
| `shared/types`, `shared/lib/validation*`, `shared/lib/jsonLogic*`, `shared/schema/scenario.zod*` ← `features` (сообщения «import … via src/shared/scenario») | **не делает того, что написано**: `target` и `from` перепутаны, правило запрещает файлам `shared/types` и т. п. импортировать `features` (это уже запрещено первой зоной). Глубокий импорт из фич линтер пропустит ([#82–#101][es82]) |
| `diagram` ← `editor`/`preview` (есть в PROJECT.md и AGENTS.md) | в конфиге **нет** |

**Зачем запрет.** Спецификация границ модулей (одобрена 2026-05-14) говорит: `Step` и `Scenario` — мост между фичами через типы и чистые функции в `shared`, а не повод для UI редактора импортировать UI предпросмотра; цель — разбить слабо связанные части на вертикальные срезы ([spec, разделы 1.2–1.3][spec]). Это архитектурная гигиена, а не безопасность.

**Что сломается, если снять запрет.** Сборка и тесты — ничего: это только линтер. Новая фича `features/operator` может импортировать `features/preview` уже сейчас — правило её не касается, `app/router.tsx` тоже импортирует предпросмотр ([router.tsx#40][router40]), а сам `preview` импортирует `features/scenarios` ([ScenarioPlayerPage.tsx#12][spp12]). Риск в другом: оператор начнёт зависеть от кода, который команда конфигуратора меняет под предпросмотр (тексты, значения по умолчанию, раскладка). **Вывод:** правильнее не снимать запрет, а вынести проигрыватели и движок в отдельный модуль (например `src/features/step-player/` или `src/shared/scenario-player/`), разрешить его editor, preview и operator, а preview оставить приватным. Спецификация (раздел 1.1) просит держать `shared` без UI, но `shared/ui` уже есть — решать команде конфигуратора.

**Где спецификация.** `docs/` в `.gitignore`, файла нет в рабочем дереве на `1fcfa25`, но он есть в истории: добавлен в `2286944`/`976f443`, правился в `38004f4`, убран из git в `541f9d9` («stop tracking docs», 2026-07-30). Прочитать: `git -C ../incident-manager show 541f9d9^:docs/superpowers/specs/2026-05-14-module-boundaries-design.md`. Фазы 0–5 спецификации: домен → `scenarios` → `editor` → `preview` → проверки в CI.

### 4.3 Вторая точка входа в Vite: что поменять

Факты: `base: '/im/'` ([vite.config.ts#82][vite82]); один `index.html` со скриптом `/src/main.tsx` ([index.html#18][html18]); роутер — `createRouter({ …, basepath: '/im' })` ([router.tsx#109][router109]); dev-сервер на `/` отдаёт заглушку ([vite.config.ts#61][vite61]); алиас темы `@/theme` → `oem/<вендор>/theme.ts` ([#54][vite54]).

Что нужно (**вывод**, сверить с документацией Vite 8):
1. Файл `operator/index.html` со своим `<script type="module" src="/src/operator/main.tsx">`.
2. В `vite.config.ts` — `build.rollupOptions.input = { main: 'index.html', operator: 'operator/index.html' }` (в Vite 8 сборщик — rolldown; проверить, называется ли опция ещё `rollupOptions`). `base: '/im/'` оставить: общие чанки лягут в `/im/assets/`, страница — в `dist/operator/index.html`.
3. Свой роутер с `basepath: '/im/operator'` и свои провайдеры: проверка прав оператора, поток событий, обновление токена, таймер бездействия.
4. Dev-сервер: для глубоких ссылок `/im/operator/...` нужен fallback на `operator/index.html` (`appType: 'mpa'` + своё middleware по образцу `dev-root-not-spa`), иначе Vite отдаст основной `index.html`.
5. `tsconfig.app.json` уже включает `src` и `oem`; ESLint — добавить зоны для `src/operator/**` (не импортировать `app/`, `features/editor`).
6. Makefile и `deploy-im-ui.yml` не меняются: `dist/operator/` попадёт в тот же `ui-<вендор>.zip`.
7. nginx — `location /im/operator` (раздел 2).

Что тянет общий вход: все 13 языков × 10 пространств переводов импортируются статически ([resources.ts][res]) — второй вход получит их тоже, если не разделить ресурсы.

### 4.4 Рекомендация: раздел, вторая точка входа или отдельный репозиторий

| | Раздел того же SPA | Вторая точка входа, тот же репозиторий | Отдельный репозиторий |
|---|---|---|---|
| Деплой и шлюз | ничего не менять | +1 `location` на заказчика | свой план Bamboo, плейбук, каталог, `location` |
| Общий код | напрямую | напрямую через `@/shared/...` | npm-пакет в Artifactory (`@axxon-web/…` уже есть у портала, [06](06-axxoncloud-ui.md#как-подключаются-приложения-и-im)); версии, публикация, `peerDependencies` |
| Отдельные провайдеры (поток, токен, бездействие, права) | через отдельный корневой layout; общий `prepareAppSession` пускает по любому праву `incident_manager` ([PROJECT.md#126][pm118]) | свои с нуля | свои |
| Шапка конфигуратора | убирать для маршрутов оператора | нет | нет |
| Релиз | общий с конфигуратором | общий (один zip) | независимый |
| Изоляция сбоев и размера | общий вход, общий `main` | общие чанки, свой вход | полная |
| Кто владеет | команда конфигуратора | общая | отдельная команда |

**Рекомендация (вывод):** **вторая точка входа в том же репозитории**. Общий код остаётся в `src/shared/` (домен — как есть, проигрыватели и движок — в отдельный модуль, HTTP-клиент и тема — в `src/shared/`). npm-пакет не нужен, пока нет второго потребителя вне репозитория. Цена — одна строка `location` в nginx у каждого заказчика с МИ. Если DevOps не может поменять nginx к первому показу — начать **разделом** с отдельным корневым layout (ноль изменений в деплое), а потом перенести в отдельную точку входа: маршруты и компоненты те же. Отдельный репозиторий — только если операторскую часть ведёт другая команда со своим циклом релизов; тогда сначала нужен пакет домена без синглтона `i18n`.

Это совпадает с 00-summary («один репозиторий, отдельная точка входа») с одной поправкой: «шлюзу хватит одного `location /im/`» — неверно для глубоких ссылок (раздел 2).

**Уверенность:** структура и правила — подтверждено кодом; шаги Vite — вывод.

**Что спросить у людей.** Команде конфигуратора (автор границ — Timur Saifetdinov): (1) согласны ли вынести проигрыватели и движок в модуль, доступный оператору, и в какой — `features/step-player` или `shared/`? (2) починить зоны ESLint с перепутанными `target`/`from` и добавить зоны `diagram`? (3) убрать синглтон `i18n` из Zod и валидации? (4) кто ведёт `src/operator/` — та же команда?

## 5. Тема и общий HTTP-клиент с обработкой 401

**Ответ.**

*HTTP-клиент сейчас.* Каждая фича держит свои `ACCESS_TOKEN_KEY = 'accessToken'`, `getAccessToken()` (читает только `localStorage`) и `authHeaders()`: [scenarios#36][sc36], [source-groups#35][sg35], [role-assignments#48][ra48], [incident-rules#57][ir57]; `/me` — свой `fetch` ([acBackendUsers.ts#21][me21]). Ошибка — `throw new Error('Failed … (status)')`, разбор ответа — Zod (`parse…Response`). `QueryClient`: `retry: 1`, `staleTime` 5 мин, общего `onError` нет ([providers.tsx#60][prov60]). PROJECT.md сам называет это долгом: «Duplicated fetch helpers; no shared HTTP client / refresh» ([PROJECT.md#429][pm428]).

*Как добавить обновление токена (вывод).* Один модуль `src/shared/api/http.ts`:
- `apiFetch(url, init)` читает токен перед каждым запросом из того же хранилища, что портал: `localStorage`, а если там нет пары — `sessionStorage` (портал так делает при входе через DomaAI OIDC, [06](06-axxoncloud-ui.md#авторизация));
- заранее обновляет токен, если до `exp` меньше ~7 мин, как портал; на 401 — одно обновление и один повтор. Обновление — `POST /api/v3/ac-backend/auth/tokens` с refresh-токеном в `Authorization`; новую пару писать туда же, откуда прочитали ([06](06-axxoncloud-ui.md#авторизация));
- одно обновление на браузер: `navigator.locks.request('im-token-refresh', …)` или `BroadcastChannel`, плюс перечитать хранилище после ожидания — другая вкладка могла уже обновить (одноразовость refresh-токена — открытый вопрос облаку);
- если обновить не вышло — сохранить черновик ответов и уйти на `/` портала (как `redirectToCloud`);
- в `QueryClient` не повторять запрос на 401 и ловить его централизованно (`QueryCache.onError`);
- поток событий (SSE через `fetch`) берёт токен из того же модуля.

Замена — 5 мест плюс 4 копии `withQuery`/`authHeaders`. Конфигуратор получает обработку 401 бесплатно.

*Тема.* Тема одна — `oem/Default/theme.ts`, `palette.mode: 'light'`, синий MUI `#1976d2`, шрифт Inter ([theme.ts#5][th5]). Подключается через алиас `@/theme` при сборке ([vite.config.ts#54][vite54]) и `createTheme(baseTheme, muiLocale)` в `ThemeProvider` ([providers.tsx#77][prov77]). `colorSchemes`, `cssVariables`, `useColorScheme` не используются (поиск по `src`). В 20 файлах 83 литерала цвета (`'#…'`, `rgba(…)`): `source-groups/lib/prototypeTheme.ts`, `diagram/*`, `AppShell.tsx` и др. Шрифт Inter грузится с `fonts.googleapis.com` ([index.html#10][html10]).

**Вывод:** тёмная тема для оператора — это (1) `colorSchemes: { light, dark }` в OEM-файле темы (MUI 9 это умеет); (2) выбор режима из `localStorage['theme-mode']` портала ([06](06-axxoncloud-ui.md#стек)) и подписка на событие `storage`; (3) замена захардкоженных цветов на токены палитры. Файлы `features/preview` и проигрыватели шагов в список 20 файлов с литералами цвета не попали — общий модуль проигрывателей переносится в тёмную тему без переделки цветов. Для конфигуратора это заметная работа (диаграмма, прототипная тема групп), для оператора — с нуля и дёшево, если сразу писать на токенах.

**Уверенность:** подтверждено кодом; план клиента — вывод.

**Что спросить у людей.** Облаку — одноразовый ли refresh-токен и можно ли обновлять из двух окон (вопрос уже в 00-summary). Продукту — нужна ли оператору тёмная тема с первого релиза и должна ли она следовать выбору в портале.

## 6. Локальный стенд: план добавления МИ в стек `ac` (без запуска)

Исходное — [04, Локальный запуск](04-axxoncloudgo.md#локальный-запуск) и `docs/run_cloud_on_local_machine.md` облака. Ниже — что добавить. Ничего из этого не запускалось.

**0. Ветка облака.** Сервер МИ вне демо-режима при старте шлёт `PUT /ac/v1/global-permissions/catalog`; в `develop` облака его нет ([00-summary](00-summary.md#коротко)). Для полного стенда — собрать облако из `epic/CLOUD-23284-perms-i18n`. Без этого — только демо-режим сервера МИ (`IM_CLOUD_URL=demo`): пользователи 1–4 зашиты в `main.go`, токен портала не проверяется, конфигуратор с настоящим входом работать не будет ([03](03-im-server.md#устройство-и-запуск)).

**1. Образ сервера МИ.** В `incident-manager-server`: `make dep` (VPN), `make bs-build-image` → образ `im/backend` ([Makefile][imsmk]). **Не запускать** `make bs-test`/`clear-test` на машине со стеком: `clear-test` делает `docker stop $(docker ps -aq)` и `docker rm … -f` — удалит все контейнеры облака.

**2. База.** Как в бою на POS1 — отдельная база в общем `db` ([pos1 imbackend.env][penv]); имена и пароль ниже — заглушки, задать свои для стенда (не брать из боевого env): `docker exec $(docker ps -q -f name=ac_db) psql -U postgres -c "CREATE USER <im_db_user> PASSWORD '<im_db_password>'" -c "CREATE DATABASE <im_db_name> OWNER <im_db_user>"`. Миграции сервер применит сам при старте ([03](03-im-server.md#устройство-и-запуск)). Отдельный postgres из `im.docker-stack.yml` сервера МИ не подходит: там сервис тоже называется `db` и публикует 5432, а 5432 уже занят `ac_db`.

**3. Сервис в стеке.** В локальной копии `tools/compose/anticonsul-ac.docker-stack.yml` (не коммитить) или отдельным стеком с `networks: ac: {external: true, name: ac_ac}`:

```yaml
  imbackend:
    image: im/backend
    networks: [ac]
    ports: ["5000:5000"]
    environment:
      - IM_DB_URL=postgresql://<im_db_user>:<im_db_password>@db:5432/<im_db_name>?sslmode=disable   # заглушки
      - IM_SERVER_PORT=5000
      - IM_LOG_LEVEL=debug
      - IM_CLOUD_URL=axxonnet.test        # или demo
      - IM_S2S_CLOUD_URL=backend:8000
      - IM_AES_ENCRYPTION_KEY=<свой 64-символьный hex>
      - SSL_CERT_FILE=/certs/axxonnet.test.pem
    volumes:
      - ../../tools/docker/axxonnet.test.pem:/certs/axxonnet.test.pem
```

Почему так:
- `IM_CLOUD_URL` всегда превращается в `https://<значение>/api/v1/auth/introspect-user-token` ([client.go#191][cl191]), `http://backend:8000` туда не подставить. Внутри Swarm имя `axxonnet.test` из `/etc/hosts` хоста не видно — дать его сервису `haproxy` как сетевой псевдоним: `networks: ac: aliases: [axxonnet.test]`.
- Проверка сертификата в клиенте сервера МИ включена (`http.Client{Timeout: 10s}` без своих TLS-настроек, [client.go#10][hc10]). Go читает `SSL_CERT_FILE`. **Предположение:** `axxonnet.test.pem` (в нём и сертификат, и ключ — nginx берёт оба из одного файла, [nginx.anticonsul.conf#58][ngx57]) самоподписанный и подойдёт как корень; проверить.
- `IM_S2S_CLOUD_URL` — `http://`, внутренние `/ac/v1/*`; в бою — тоже `backend:8000`.
- Обязательные переменные — `IM_DB_URL`, `IM_CLOUD_URL`, `IM_S2S_CLOUD_URL` ([config.go#10][cfg10]); в `im.docker-stack.yml` сервера МИ двух последних нет — сервис по нему не стартует ([03](03-im-server.md#устройство-и-запуск)).

**4. nginx.** Правка `tools/docker/nginx.anticonsul.conf` (локально) перед `location /api/` (~[#172][ngx171]), затем `make redeploy-ng` ([local.mk][lmk]); либо смонтировать свой конфиг в `/etc/nginx/nginx.conf`.

```nginx
        location /api/v1/im-backend {
            include common-api-header-directives.conf;
            resolver 127.0.0.11 valid=10s;          # как у uploader: nginx стартует и без МИ
            set $im_up imbackend:5000;
            proxy_pass http://$im_up;               # с переменной URI уходит как есть: /api/v1/im-backend/...
            proxy_buffering on;                     # как в бою (на стенде по умолчанию off)
            proxy_read_timeout 300s;                # как в бою
        }
        location /im/operator {                     # если оператор — отдельная точка входа
            root html;
            try_files $uri $uri/ /im/operator/index.html;
        }
        location /im {
            root html;
            index index.html;
            try_files $uri $uri/ /im/index.html;
        }
```

Образец `resolver 127.0.0.11` + `set $upstream` уже есть в этом конфиге ([#111][ngx111]). Базовый путь сервера — `/api/v1/im-backend` ([common.go#5][imbase]).

**5. Статика.** nginx отдаёт `tools/compose/ui` как `/etc/nginx/html` ([stack, nginx volumes][stk]). Конфигуратор: `npm ci && npm run build` (или `VENDOR_NAME=Default make build-oem`) → скопировать **содержимое** `dist/` в `tools/compose/ui/im/`. Не распаковывать `ui-Default.zip` в `tools/compose`: в архиве корень `ui/`, он сольётся с портальным `ui-AxxonNet.zip`. Операторская точка входа окажется в `ui/im/operator/` сама. Прототип IM можно положить рядом (`ui/im-proto/`) для сравнения — ему нужен свой `location` по той же схеме.

**6. Пользователь и права.** `make create-db-users` (`user@gmail.com` / `password`, [04](04-axxoncloudgo.md#локальный-запуск)); роль с правами `incident_manager.*` — после регистрации каталога (шаг 0). Без прав конфигуратор уведёт на `/`.

**7. События.** Источник инцидентов — агенты МИ: выпустить токен регистрации `POST /agents/tokens`, зарегистрировать тестового агента и слать `POST /events` ([03](03-im-server.md#авторизация-арендность-связь-с-облаком)). SQL с демо-группами и устройствами — `internal/im/tools/test_sql/` сервера.

**8. Проверка.** `curl -k https://axxonnet.test/api/v1/im-backend/heartbeat`; войти в портал, открыть `https://axxonnet.test/im/`; глубокая ссылка `/im/scenarios/<id>` должна открыться без 404; затем `tests/api.html` прототипа против стенда — по мере появления операций.

**9. Отладка с хоста.** Запускать бинарник на хосте: `IM_DB_URL=postgresql://<im_db_user>:<im_db_password>@localhost:5432/<im_db_name>`, `IM_S2S_CLOUD_URL=localhost:8000`, `IM_CLOUD_URL=axxonnet.test` (на хосте имя есть в `/etc/hosts`). В nginx вместо `imbackend:5000` — адрес шлюза `docker_gwbridge` хоста. Порт dlv — свободный, например 40010 ([04](04-axxoncloudgo.md#локальный-запуск)).

**Уверенность:** состав сервисов и переменных — подтверждено кодом; сам план — вывод, не запускался.

## Поправки к первому кругу

| Файл | Что написано | Как на самом деле |
|---|---|---|
| [04, Сервисы и шлюз](04-axxoncloudgo.md#сервисы-и-шлюз) | «Маршрута `/api/v1/monitoring` в nginx этого репозитория нет. Предположение: боевые конфиги в другом репозитории» | Подтверждено: `IT/axxoncloud-deploy`, Ansible + consul-template, конфиг nginx на каждого заказчика ([pos1#349][p349]) |
| [04, Коротко](04-axxoncloudgo.md#коротко), [00-summary, Коротко](00-summary.md#коротко) | «Слов `incident`/`im` в деплое нет», «Операторской части… нет нигде» | Для `axxoncloudgo` верно. В боевом деплое МИ есть: роль `incidentmanager`, Bamboo-деплои `ASIP-IM` (сервер) и `ASIP-IN` (UI), маршруты и раздача на Bezeq |
| [00-summary, шаг 6](00-summary.md#карта-связей) | «Маршрута `/api/v1/im-backend/` в nginx облака нет» | Нет только в локальном стеке; в бою у Bezeq есть ([pos1#373][p373], [bezeq/common#358][bc358], [itv/common#385][itv385]) |
| [02, Стек и выкладка](02-im-configurator.md#стек-и-выкладка), [02, Открытые вопросы №2](02-im-configurator.md#открытые-вопросы) | «Кто раздаёт zip под `/im/` — вопрос»; «fallback — неизвестно» | Bamboo-деплой → `deploy-im-ui.yml` → `/data/axxoncloud/im`; fallback — `try_files … /im/index.html` в nginx заказчика (раздел 2) |
| [02, Коротко](02-im-configurator.md#коротко) | «CI собирает по zip-архиву на каждого OEM-вендора» | В `oem/` только `Default`; собирается и выкладывается один `ui-Default.zip` |
| [02, Есть ли что-то операторское](02-im-configurator.md#есть-ли-что-то-операторское) | «ESLint запрещают брать `preview` откуда-либо, кроме `StepPreviewModal.tsx`… без перестройки границ взять проигрыватель нельзя» | ESLint запрещает это только `editor` и `scenarios`; `app` и новые фичи могут импортировать `preview` уже сейчас. Зоны «домен только через `@/shared/scenario`» не работают (перепутаны `target`/`from`), зоны `diagram` в конфиге нет (раздел 4.2) |
| [02, Что повторить, п. 11](02-im-configurator.md#что-повторить-для-операторской-части) | «Спецификация границ… в git на этом коммите отсутствует» | В рабочем дереве нет, в истории есть: `git show 541f9d9^:docs/superpowers/specs/2026-05-14-module-boundaries-design.md` |
| [00-summary, «Варианты встраивания фронта»](00-summary.md#варианты-встраивания-фронта) | «Тогда шлюзу хватит одного `location /im/`» | Для отдельной точки входа нужен ещё `location /im/operator` (глубокие ссылки), иначе `/im/operator/<путь>` получит `index.html` конфигуратора. Отдельный zip в `/im/operator/` стирается деплоем конфигуратора |
| [00-summary, «Риски и находки»](00-summary.md#риски-и-находки) | Факты по шлюзу — только локальный стек (`proxy_buffering off`, haproxy `client 50000`, `server 1m`) | В бою буферизация для `/api/v1/im-backend` включена, `proxy_read_timeout 300s`; haproxy `client 50s` и `server 300s` + `tunnel 1h` (роль `haproxy`) либо `client 50000` и `server 1m` (роль `haproxy-like-bezeq`). Вывод «пустой комментарий чаще 30 с» остаётся верным; нужен ещё `X-Accel-Buffering: no` (раздел 3) |
| [04, Что добавить для МИ, п. 1](04-axxoncloudgo.md#локальный-запуск) | «адрес облака для introspect (`http://backend:8000` внутри сети или `https://axxonnet.test`)» | Сервер МИ всегда строит `https://<IM_CLOUD_URL>` ([client.go#191][cl191]); `http://backend:8000` невозможен. Нужны имя `axxonnet.test` внутри сети и доверенный сертификат (раздел 6) |
| [04, Что добавить для МИ, п. 3](04-axxoncloudgo.md#локальный-запуск) | «положить сборки в `tools/compose/ui/im/`» | Верно, но копировать содержимое `dist/`; zip конфигуратора имеет корень `ui/` и при распаковке в `tools/compose` смешается с порталом |
| [04, Сервисы и шлюз](04-axxoncloudgo.md#сервисы-и-шлюз), [00-summary][ngx-root] | Номер строки `location /` — `#269`, `/api/` — `#168` | На `0228c7a` `location /` — строка 276, `location /api/` — 172 (сверено постраничным чтением) |

## Открытые вопросы

К DevOps облака (`axxoncloud-deploy`):
1. [важно] На каких стендах МИ развёрнут сейчас и где будет у первого заказчика с оператором?
2. [важно] Добавить `location /im/operator` и `location` для потока событий (или принять `X-Accel-Buffering: no` от сервера); убрать кэш `index.html` под `/im`.
3. [важно] Какая роль haproxy стоит на Bezeq (`haproxy` с `tunnel 1h` или `haproxy-like-bezeq` без него)?
4. [позже] Почему в `itv/common` есть API МИ, но нет `/im`?
5. [позже] Перенести пароль БД МИ, `IM_AES_ENCRYPTION_KEY` и ключ Google из репозитория в хранилище секретов.

К команде конфигуратора:
6. [важно] Вторая точка входа `src/operator/` в этом репозитории — согласны? Кто ведёт?
7. [важно] Вынести проигрыватели шагов и движок в модуль, доступный оператору; убрать синглтон `i18n` из Zod/валидации; починить зоны ESLint.
8. [важно] Общий `src/shared/api/http.ts` с обновлением токена и обработкой 401 — делаем вместе?
9. [позже] Будут ли OEM-вендоры кроме `Default`; собирает ли `ASIP-IN` ветки?

К облаку — без изменений относительно 00-summary (одноразовость refresh-токена, каталог прав в `develop`).

<!-- ссылки: деплой -->
[p147]: https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/ansible-hc/config/bezeq/pos1/nginx/nginx.conf.ctmpl.j2?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec#147
[p248]: https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/ansible-hc/config/bezeq/pos1/nginx/nginx.conf.ctmpl.j2?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec#248
[p349]: https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/ansible-hc/config/bezeq/pos1/nginx/nginx.conf.ctmpl.j2?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec#349
[p373]: https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/ansible-hc/config/bezeq/pos1/nginx/nginx.conf.ctmpl.j2?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec#373
[p460]: https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/ansible-hc/config/bezeq/pos1/nginx/nginx.conf.ctmpl.j2?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec#460
[bc358]: https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/ansible-hc/config/bezeq/common/nginx/nginx.conf.ctmpl.j2?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec#358
[bc453]: https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/ansible-hc/config/bezeq/common/nginx/nginx.conf.ctmpl.j2?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec#453
[itv147]: https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/ansible-hc/config/itv/common/nginx/nginx.conf.ctmpl.j2?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec#147
[itv385]: https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/ansible-hc/config/itv/common/nginx/nginx.conf.ctmpl.j2?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec#385
[penv]: https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/ansible-hc/config/bezeq/pos1/docker/imbackend.env?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec
[s2env]: https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/ansible-hc/config/bezeq/stage2/docker/imbackend.env?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec
[imrole17]: https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/ansible-hc/roles/incidentmanager/tasks/main.yml?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec#17
[scs10]: https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/ansible-hc/roles/service-container-starter/tasks/main.yml?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec#10
[scs74]: https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/ansible-hc/roles/service-container-starter/tasks/main.yml?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec#74
[ncu8]: https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/ansible-hc/roles/nginx-conf-update/tasks/main.yml?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec#8
[ncu47]: https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/ansible-hc/roles/nginx-conf-update/tasks/main.yml?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec#47
[ngxrole19]: https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/ansible-hc/roles/nginx/tasks/main.yml?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec#19
[hdr]: https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/ansible-hc/roles/nginx/files/common-api-header-directives.conf?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec
[gz]: https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/ansible-hc/roles/nginx/files/common-gzip-directives.conf?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec
[wspp]: https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/ansible-hc/roles/nginx/files/common-webclient-ws-proxy-pass.conf?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec#5
[ha38]: https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/ansible-hc/roles/haproxy/templates/haproxy.cfg.ctmpl.j2?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec#38
[hb38]: https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/ansible-hc/roles/haproxy-like-bezeq/templates/haproxy.cfg.ctmpl.j2?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec#38
[hb98]: https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/ansible-hc/roles/haproxy-like-bezeq/templates/haproxy.cfg.ctmpl.j2?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec#98
[imui5]: https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/bamboo-specs/IncidentManagerUI.yaml?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec#5
[imui25]: https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/bamboo-specs/IncidentManagerUI.yaml?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec#25
[imui63]: https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/bamboo-specs/IncidentManagerUI.yaml?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec#63
[imuip6]: https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/bamboo-specs/IncidentManagerUI-p.yaml?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec#6
[dimu21]: https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/ansible-hc/deploy-im-ui.yml?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec#21
[dimu27]: https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/ansible-hc/deploy-im-ui.yml?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec#27
[dimu32]: https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/ansible-hc/deploy-im-ui.yml?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec#32
[dui27]: https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/ansible-hc/deploy-ui.yml?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec#27
[uidock]: https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/docker/ui/Dockerfile?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec

<!-- ссылки: облако develop -->
[ngx31]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/tools/docker/nginx.anticonsul.conf?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#31
[ngx57]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/tools/docker/nginx.anticonsul.conf?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#58
[ngx111]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/tools/docker/nginx.anticonsul.conf?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#111
[ngx171]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/tools/docker/nginx.anticonsul.conf?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#172
[ngx237]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/tools/docker/nginx.anticonsul.conf?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#237
[ngx276]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/tools/docker/nginx.anticonsul.conf?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#276
[ngx362]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/tools/docker/nginx.anticonsul.conf?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#362
[ngx-root]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/tools/docker/nginx.anticonsul.conf?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#276
[stk]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/tools/compose/anticonsul-ac.docker-stack.yml?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3
[lmk]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/local.mk?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3

<!-- ссылки: конфигуратор -->
[mk61]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/Makefile?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#61
[mk68]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/Makefile?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#68
[vite43]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/vite.config.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#43
[vite54]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/vite.config.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#54
[vite61]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/vite.config.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#61
[vite82]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/vite.config.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#82
[html10]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/index.html?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#10
[html18]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/index.html?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#18
[router14]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/app/router.tsx?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#14
[router40]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/app/router.tsx?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#40
[router109]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/app/router.tsx?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#109
[prov60]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/app/providers.tsx?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#60
[prov77]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/app/providers.tsx?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#77
[th5]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/oem/Default/theme.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#5
[es43]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/eslint.config.js?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#43
[es82]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/eslint.config.js?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#82
[spm2]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/features/editor/components/StepPreviewModal.tsx?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#2
[spp12]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/features/preview/components/ScenarioPlayerPage.tsx?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#12
[zod3]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/shared/schema/scenario.zod.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#3
[val2]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/shared/lib/validation.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#2
[jl34]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/shared/lib/jsonLogic.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#34
[jl53]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/shared/lib/jsonLogic.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#53
[jl59]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/shared/lib/jsonLogic.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#59
[bar5]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/shared/scenario/index.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#5
[pe3]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/features/preview/lib/playerEngine.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#3
[types13]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/shared/types/scenario.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#13
[res]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/shared/i18n/resources.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#1
[sc36]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/features/scenarios/api/imBackendScenarios.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#36
[sg35]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/features/source-groups/api/imBackendSourceGroups.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#35
[ra48]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/features/role-assignments/api/imBackendRoleAssignments.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#48
[ir57]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/features/incident-rules/api/imBackendIncidentRules.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#57
[me21]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/shared/api/ac-backend/acBackendUsers.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#21
[pm118]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/PROJECT.md?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#126
[pm428]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/PROJECT.md?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#429
[spec]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/docs/superpowers/specs/2026-05-14-module-boundaries-design.md?at=f4665b129ea727a9d172aa4e3f2b65d886c7ba29

<!-- ссылки: сервер МИ -->
[imsmk]: https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/Makefile?at=b743797a38daeb3beaa44ef901b26c3ce924290f#69
[cfg10]: https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/model/config.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#10
[cl191]: https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/externalclient/cloud/client.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#191
[hc10]: https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/util/httputils/client.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#10
[imbase]: https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/model/common.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#5
