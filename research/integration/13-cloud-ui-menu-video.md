# Фронт облака: меню, видео, карта, CSP, тема (второй круг)

- Дата: 2026-10-28.
- Тема: вопросы из [00-summary.md](00-summary.md#вопросы) про меню облака, протокол `embedded.html`, карту и планы, CSP и `frame-src`, тему. Дополняет [06-axxoncloud-ui.md](06-axxoncloud-ui.md); найденное там не повторяю.
- Как читал: только Bitbucket MCP и локальные копии, ничего не менял.

| Репозиторий | Что это | Ветка | Коммит |
|---|---|---|---|
| `PROJ/axxoncloud-ui` | портал облака (основной снимок) | `CLOUD-23284-epic-perms-catalog` | `83a04e587c90809e10c4efb4b5a57ce29a335174` |
| `PROJ/axxoncloud-ui` | портал облака (сравнение) | `develop` | `d436dd1c24cde57170db56143b8b17e7fc820b23` |
| `PROJ/axxoncloud-ui` | слои карты | `CLOUD-22804-epic-user-map-layers` | `b37ab5381e1c312b11de4c0efb7faf7ab0b5121a` |
| `PROJ/axxoncloudgo` | бэкенд облака | `epic/CLOUD-23284-perms-i18n` / `develop` | `e51bd552…` / `0228c7a9…` |
| `PROJ/axxoncloudgo` | слои карты | `feature/CLOUD-22804-epic-map-layers` | `d16ce312c63aea8630ce7bd21891df9b08a3ac03` |
| **`NEW/axxon-web`** (новый) | монорепозиторий фронт-библиотек: `@axxon-web/cloud-menu`, `auth`, `ui`, `types`, `hooks` | `master` | `5654ae4fbebb914e01789c1ebf66376f26be0397` |
| **`PROJ/axxonnext.webclient`** (новый) | вебклиент VMS, в нём `embedded.html` | `master` | `f1600edcc2208a05cb91d3944b75c8130da24dac` |
| **`IT/axxoncloud-deploy`** (новый) | боевой деплой облака: ansible, шаблоны nginx | `master` | `91d1e6d25f3e5ff4273fc1277bf109970a8fcaec` |
| `PROJ/incident-manager` | конфигуратор МИ | `master` | `1fcfa25` (локально) |
| IM | прототип | `main` | `d891125` (локально) |

Обозначения: без пометки — факт со ссылкой; **Вывод:** — следует из фактов; **Предположение:** — не проверено. Ссылки — в конце файла.

## Коротко

1. **Меню.** Исходники `@axxon-web/cloud-menu` — в `NEW/axxon-web/packages/cloud-menu`. Пункт `incidentManager` ведёт на `/im/` и виден, если у пользователя есть **хоть одно** действие в пространстве `incident_manager`. Отдельного пункта для оператора нет. Добавить его можно только выпуском новой версии пакета и портала. Есть путь без правок облака: один пункт `/im/`, а SPA МИ само решает по правам, что открыть — оператора или конфигуратор.
2. **Меню во внешнем SPA** подключить можно. Нужны React 18/19, MUI 5–9, emotion, `react-intl` и `react-router-dom` (контекст роутера обязателен), сборщик для ESM и доступ к Artifactory. Redux не нужен: внутри effector. У конфигуратора нет ни `react-intl`, ни `react-router-dom` (там i18next и TanStack Router), так что их придётся добавить. Прототип на чистом JS подключить пакет не может.
3. **Видео.** `embedded.html` — один проигрыватель на одну камеру. Команды в iframe: `init`, `reInit`, `setTime`, `play`, `stop`, `getSnapshot`, `setMask`. Ответы: `embeddedLoad`, `feedback`, `archTime`, `speed`, `snapshot`, `stream`, `mask*`. Архив к моменту события открывается так: `init {mode:'archive', archive:{time, storage, utc}}`, дальше `setTime`. Токен облака передаётся в адресе `?authToken=` и сообщением `{type:'authToken'}`; вебклиент сам меняет его на токен VMS. Видео идёт по WebSocket: MSE (fMP4 H.264/H.265), иначе MJPEG. WebRTC и HLS нет. Для монитора на 4 камеры нужно 4 iframe. Другой путь — один iframe `index.html?cams=…&mode=arch&time=…&hideTopBar=true`, но тогда нет протокола команд.
4. **Карта.** Ключ mapbox задаётся переменными окружения бэкенда (`AXXONCLOUD_MAPBOX_API_KEY` / `AXXONCLOUD_MAPBOX_TILES_SRC`), а не OEM-сборкой. Отдаёт его `GET /api/v3/ac-backend/settings`, только с действительным токеном. `/im/` может взять ключ так же. Эпик `map-layers` — это личные слои пользователя с гео-точками (lat/lng, GeoJSON/CSV), без поэтажных планов, без картинок и без привязки устройств. Он не влит в `develop`. **Вывод:** планов объектов от облака по этому эпику не будет.
5. **CSP.** Заголовки ставит nginx из `IT/axxoncloud-deploy`. В основном шаблоне заголовка CSP нет, есть `X-Frame-Options: sameorigin`. Вебклиент домена отдаётся с того же хоста (`/<arpserver>/…`), значит iframe на `/im/` разрешён. В варианте `arpext` стоит `frame-ancestors 'self' https://<default_hostname>`, это тоже разрешает `/im/` на основном хосте. `CSP_NONCE` в `index.html` портала никто не подставляет.
6. **Тема.** OEM-тема MUI портала задаётся при сборке, своя на каждого из 62 вендоров. Общего пакета темы нет, CSS-переменных нет. Светлая или тёмная хранится в `localStorage['theme-mode']` — это негласное соглашение веб-приложений AxxonSoft, внешнее SPA в том же origin может его читать. OEM-цвета во время работы получить нельзя.
7. **Попутно** (`IT/axxoncloud-deploy`): в nginx заказчика `bezeq` уже есть `location /im` (статика конфигуратора), `/api/v1/im-backend` и WebSocket `/api/v1/notifier/connect`. Во всех просмотренных шаблонах `/api/v1/configsync/internal` закрыт ответом 403. См. «Поправки».

## 1. Пакет `@axxon-web/cloud-menu`

**Ответ.**
- Исходники — монорепозиторий `NEW/axxon-web` (pnpm + turbo + changesets), пакет `packages/cloud-menu`, версия 1.6.0 на `master` ([package.json][cm-pkg]). Есть пример подключения `examples/cloud-menu` ([example][cm-ex]). Последние изменения меню вносили Petr Khoraskin (custom apps, 1.6.0) и Vitaly Zakutny (auth) — по журналу коммитов.
- **Адрес пункта:** `incidentManager: {pattern: '/im/'}` ([routes][cm-routes19]). Подпись — `app.incident-manager`, по-русски «Менеджер инцидентов» ([ru.json][cm-ru]).
- **По какому праву виден:** `canIncidentManager = useHasCapability(CAP.incidentManager)`, где `CAP.incidentManager = 'incident_manager'` ([AppMenu:92][cm-menu92], [CAP:30][cm-cap30]). Строка из одного пространства по правилу `hasCapability` значит: «истина, если в пространстве `incident_manager` у какого-нибудь ресурса есть хоть одно действие» ([libs:127][cm-has127]). **Вывод:** пункт видят и администратор, и оператор. Обоих он ведёт на `/im/`, то есть сейчас на конфигуратор.
- Действия, которые понимает разбор прав в пакете: `create, view, edit, delete, manage, use, run, share, export, import, download, apply, bind, encrypt, block` ([libs:10][cm-has10]). Строку вида `incident_manager.incidents.take` разбор отвергнет (`parseCapabilityString` вернёт `null`), и проверка даст `false`. Так же устроен разбор в самом портале ([06](06-axxoncloud-ui.md#права-в-интерфейсе)).
- **Как ходит переход.** Если имя маршрута есть в `externalRoutes`, выполняется `window.location.href = routes.url(name)`. Иначе — `navigate()` роутера внутри приложения ([AppMenu:119][cm-menu119]). Пути абсолютные (`/dashboard`, `/camera/map`, `/im/` …) ([routes][cm-routes19]).
- **Как в портале.** На основном снимке портал ставит `@axxon-web/cloud-menu` **1.4.5** ([pkg:50][ui-pkg50]), на `develop` — **1.6.0** ([pkg dev:50][ui-pkgdev50]). Пункт `incidentManager` есть в обеих версиях: перевод появился в 1.4.1, переход на `capabilities` — в 1.4.0 ([CHANGELOG][cm-chlog]). Портал передаёт `capabilities` из своего store, `settings`, `locale`, `externalRoutes = ['analytics','demoDashboard','updateService','incidentManager']`, `hiddenRoutes` и `extraAppMenu` из OEM-конфигурации ([AppMenu:18][ui-menu18], [AppMenu:39][ui-menu39]).

**Как добавить пункт «Оператор МИ».** Три пути, по возрастанию цены:

| Путь | Что менять | Минусы |
|---|---|---|
| А. Один пункт `/im/`, развилка внутри SPA МИ | ничего в облаке; SPA по правам из `/me` открывает операторскую часть или конфигуратор | одна подпись «Менеджер инцидентов» на обе роли |
| Б. Новый маршрут в пакете меню | `packages/cloud-menu`: маршрут (например, `incidentManagerOperator: '/im/operator/'`), `CAP`, пункт, переводы на 32 языка; выпуск пакета (changeset → Artifactory); в портале — новая версия пакета и имя в `EXTERNAL_ROUTES` | если право оператора — глагол МИ (`take` …), его надо добавить в `ACTIONS` пакета и портала; выделение вкладки ищется через `matchPath(pattern, {end:false})` по порядку, и пункт `/im/`, стоящий раньше, перехватит `/im/operator/` ([AppMenu:302][cm-menu301]); выпуск портала на все OEM |
| В. `extraAppMenu` в OEM-конфигурации портала | `oem/<V>/app/config/extraAppMenu.tsx` | только при сборке и только для одного вендора; 62 вендора; подпись без переводов пакета ([06](06-axxoncloud-ui.md#как-подключаются-приложения-и-im)) |

**Вывод:** путь А не требует ничего от команды облака, и тогда вопрос «можно ли добавить пункт» перестаёт блокировать работу. Путь Б нужен, только если продукт хочет два пункта в меню.

**Доказательства:** ссылки выше.
**Уверенность:** подтверждено кодом (`NEW/axxon-web` `5654ae4`, портал `83a04e5` и `d436dd1`).
**Спросить у людей:**
- Владельцу `@axxon-web/cloud-menu` (по коммитам — Petr Khoraskin): «Примете ли второй пункт МИ (`/im/operator/`) или пункт с подменю? Добавлять ли глаголы МИ (`take`, `close`, `assign` …) в `ACTIONS` пакета, или пункт оператора проверять по действию из стандартного набора?»
- Продукту: «Нужен ли оператору отдельный пункт в меню облака, или хватит одного пункта „Менеджер инцидентов“ с развилкой по ролям?»

## 2. Можно ли подключить `@axxon-web/cloud-menu` во внешнее SPA

**Ответ.**
- **Зависимости.** Peer-зависимости: `@emotion/react`, `@emotion/styled` 11, `@mui/material` и `@mui/icons-material` 5/6/7/9, `react` и `react-dom` 18/19, `react-intl` 6/7, `react-router-dom` 6/7. Собственные зависимости — `effector`, `effector-react` ([package.json][cm-pkg]). Redux и redux-saga не нужны. Сборка — только ESM (`"type":"module"`, `dist/index.es.js`), поэтому нужен сборщик.
- **Контекст.** Компонент вызывает `useLocation`, `useNavigate`, `useHref` ([AppMenu:4][cm-menu4]), значит должен стоять внутри `<Router>` из `react-router-dom`. Тему он берёт из MUI `ThemeProvider` хоста. Переводы приносит с собой: 32 языка, грузятся лениво ([i18n/model][cm-i18n]).
- **Props.** Обязателен только `locale`. Если не передать `capabilities` или `settings`, пакет сам запросит `GET /api/v3/ac-backend/me` и `GET /api/v3/ac-backend/settings` с `Bearer` из `localStorage.accessToken` ([app/index.tsx:13][cm-app13], [app/model:28][cm-model28], [api:5][cm-api5]). README называет prop `userCapabilities` и путь `/users/{userId}`, но в коде это `capabilities` и `/me` ([README:59][cm-readme59]).
- **Хранилище токена.** Пакет читает токен только из `localStorage` ([storageHelper:13][cm-sh13]). При входе через DomaAI OIDC портал держит токен в `sessionStorage` ([06](06-axxoncloud-ui.md#авторизация)) — тогда автозагрузка прав в пакете не сработает. **Вывод:** передавать `capabilities` и `settings` самим.
- **Переходы во внешнем SPA.** Пункты, которых нет в `externalRoutes`, переходят через `navigate()` роутера самого SPA. Под `/im/` с другим роутером это сломает переход в портал. **Вывод:** передавать `externalRoutes={/.*/}` (RegExp поддерживается — [app/index.tsx:15][cm-app13]), тогда все переходы идут полной загрузкой страницы.
- **Реестр.** Пакеты публикуются из `master` в Artifactory `npm-local`, scope `@axxon-web` ([Makefile:3][cm-mk3]); для установки нужна авторизация в реестре. В `.npmrc` портала учётные данные реестра лежат открытым текстом (факт; значения не переписываю). У конфигуратора в `.npmrc` только `legacy-peer-deps=true`, доступа к `@axxon-web` нет.
- **Совместимость с конфигуратором.** Совпадают React 19, MUI 9 и emotion. Нет `react-intl` (у конфигуратора `i18next`/`react-i18next`) и нет `react-router-dom` (у конфигуратора `@tanstack/react-router`) — по `package.json` конфигуратора. **Вывод:** подключить можно, если добавить обе библиотеки и обернуть меню в отдельный `<BrowserRouter>` или `<MemoryRouter>` только для него. Выделение текущей вкладки пакет считает по `window.location.pathname` ([AppMenu:302][cm-menu301]), так что роутер-обёртка ему нужен только как контекст.
- **Прототип** — чистый JS без React. Подключить в него пакет нельзя.

**Уверенность:** подтверждено кодом. Про «отдельный `BrowserRouter` рядом с TanStack Router» — вывод, не проверял запуском.
**Спросить у людей:**
- DevOps / владельцу Artifactory: «Можно ли выдать сборке МИ (Bamboo, планы `ASIP-IM`/`ASIP-IN`) доступ на чтение к `@axxon-web` в `npm-local`?»
- Команде облака: «Есть ли ограничения (лицензия, поддержка) на использование `@axxon-web/cloud-menu` вне портала?»

## 3. Протокол `embedded.html` вебклиента VMS

**Ответ.** Репозиторий — `PROJ/axxonnext.webclient`. Протокол объявлен публичным контрактом: менять и удалять команды запрещено, можно только добавлять ([rules/embedded.md:19][wc-rules], [architecture.md:219][wc-arch219]).

| Направление | Сообщение | Параметры | Источник |
|---|---|---|---|
| в iframe | `init` (live) | `mode:'live'`, `origin` (точка доступа камеры), `domainId?`, `stream?`, `resolution?: 'AUTO'\|'HIGH'\|'LOW'`, `autoplay?`, `options?` | [types:40][wc-types40] |
| в iframe | `init` (archive) | `mode:'archive'`, `origin`, `domainId?`, `archive: {time?: Date\|string, storage: string, utc?: boolean}`, `autoplay?`, `options?` | [types:34][wc-types34] |
| в iframe | `reInit` | то же, что `init`: сменить камеру или режим без перезагрузки | [State:93][wc-state96] |
| в iframe | `setTime` | `time` — в архиве встать на момент | [types:69][wc-types69] |
| в iframe | `play`, `stop`, `getSnapshot`, `setMask {value}` | — | [constants:22][wc-const22] |
| из iframe | `{type:'embeddedLoad', value:true}` | готов к командам; шлётся только **после входа** (`setAppLoaded`) | [embedded.ts:55][wc-emb55] |
| из iframe | `{type:'feedback', data:'success'\|'fail', cmd}` | ответ на каждую команду; неизвестная команда — `fail` | [feedback][wc-fb], [CommandHandler:32][wc-ch32] |
| из iframe | `{status:'archTime', archTime}`, `{status:'speed', speed}`, `{type:'snapshot', data}`, `{status:'stream', data}` | текущее время архива, скорость, кадр, сведения о потоке | [feedback][wc-fb], [CommandHandler:43][wc-ch32] |
| из iframe | `maskChanged`, `maskRemoved`, `maskClicked` | события масок | [constants:15][wc-const15] |

- **Опции `options`** (`AdditionalOpts`): `archivePane`, `intervals`, `alerts`, `keepTimestamp`, `fastSearch`, `exportMenuButton`, `bookmarkButton`, `alertReview`, `bar`, `eventsPanel`, `forceMjpeg`, `playback`, `archPaneInCell`, `showTitles`, `ptzPanel`, `exportManager`, `microphone`, `showTimelinePreviews`, `mask*`, `showDetector*`, `showTracks`, `cellControlsPosition` ([types:5][wc-types5]). По умолчанию включены `archivePane`, `keepTimestamp`, `exportMenuButton`, `bar`, `eventsPanel`, `showTimelinePreviews` ([constants:3][wc-const3]).
- **Момент архива.** `archive.time` — строка или `Date`. При `utc:false` строка читается как местное время ([utils.tsx:83][wc-utils83]). Время ставится, когда камера готова ([State, ArchiveMode][wc-state96]). Поле `storage` по типу обязательно. Если архива с таким `storage` у камеры нет, выбирается `undefined` — что тогда будет, из кода не видно ([State.ts][wc-state96], класс `PreInit`).
- **Несколько камер.** В одном `embedded.html` — одна камера: `init` берёт один `origin`, и состояние у проигрывателя одно ([State][wc-state96]). **Вывод:** 4 камеры — это 4 iframe. Каждый iframe — отдельный экземпляр вебклиента со своим WebSocket. Другой путь — основной `index.html` вебклиента с параметрами адреса `cams=a,b,c`, `mode=live|arch`, `time=…`, `hideTopBar=true` ([url-params][wc-urlp]). Он покажет несколько камер в одном iframe, но протокола команд у него нет: чтобы сменить время, нужно перезагрузить iframe.
- **Авторизация.**
  - Токен облака приходит в адресе `?authToken=` и сообщением `{type:'authToken', token}`. Вебклиент кладёт его в своё `localStorage['cloudToken']` ([useExternalToken:10][aw-ext10]).
  - Затем меняет его на токен VMS: `GET ./vmsToken?authToken=…` относительно пути вебклиента, продлевает через `renewVMSToken` ([auth/api/cloud.ts:9][aw-cloud9]).
  - Обработчик `message` не проверяет `e.origin` ([useExternalToken:10][aw-ext10]).
  - Портал шлёт ещё `{type:'AxxonCloudToken'}` ([06](06-axxoncloud-ui.md#как-подключаются-приложения-и-im)), но в вебклиенте этого слова нет (поиск — 0). **Вывод:** это сообщение устарело.
  - Адрес — `domain.webClientURL` из облака (`…/<arpserver>/<domainId>_<n>/webclient/`). В боевом nginx префикс — имя хоста arpserver из Consul, а не всегда `arpserver` (см. п. 5). Собирать адрес вручную не нужно.
- **Технология видео.**
  - Веб-воркер `MediaConn.wrk` держит WebSocket `<webclient>/ws?authToken=…` ([MediaConn.wrk:66][wc-wrk66]).
  - H.264/H.265 идут в контейнере MP4 через MSE, если браузер поддерживает и не задан `forceMjpeg`. Иначе — кадры JPEG ([misc:179][wc-misc179], [CommandHandler:9][wc-ch9]).
  - Остановленный архив — тоже JPEG.
  - WebRTC и HLS нет (поиск `RTCPeerConnection`, `webrtc` — 0).
- **Хватит ли для видеомонитора оператора** (до 4 камер, архив к моменту события). **Вывод:** функционально хватит: 4 iframe `embedded.html`, `init` с `mode:'archive'` и `archive.time`, переключение кнопкой «живое/архив» через `reInit`, перемотка — `setTime`, обратная связь — `archTime`. Чего нет:
  - события «камера недоступна» или «ошибка» — есть только `feedback fail` на команду;
  - готовности, если токен не принят: `embeddedLoad` не придёт, нужен тайм-аут, как у портала (5 с);
  - данных, откуда взять `storage` для архива: в `configsync` у камеры есть только `coords`, `domainId`, `accessPoint`, `name`, `previewUrl` ([types:3][ui-maptypes3]).
  
  Нагрузка от 4 полных экземпляров вебклиента на одном экране не замерялась.

**Уверенность:** протокол, авторизация и технология видео подтверждены кодом. Поведение без `storage` и нагрузка 4 iframe — не проверены.
**Спросить у людей:**
- Команде вебклиента (по коммитам — Maryia Karelina, Ivan Aheichanka): «Можно ли открыть архив в `embedded.html` без `archive.storage` (архив камеры по умолчанию)? Если нельзя — откуда хосту взять `storage`?»
- Им же: «Есть ли у `embedded.html` событие ошибки или недоступности камеры? Рекомендуете ли вы 4 iframe `embedded.html` на одном экране или `index.html?cams=…&hideTopBar=true`?»
- Им же: «Сообщение `AxxonCloudToken` из портала ещё нужно какому-то вебклиенту?»

## 4. Карта: ключ mapbox и слои

**Ответ: ключ и тайлы.**
- Бэкенд берёт их из переменных окружения: `AXXONCLOUD_MAPBOX_API_KEY`, `AXXONCLOUD_MAPBOX_TILES_SRC`; для Google, Yandex и OSM — свои переменные ([config.go:315][go-cfg315]). В `go-util` есть чтение секрета `maps:mapbox_api_key` из Vault (по тесту `secrets_test.go`). **Вывод:** ключ задаётся на установку, а не на OEM-сборку.
- Отдаёт ключ `GET /api/v3/ac-backend/settings`. Ключи карт в ответе есть **только** с действительным `Authorization: Bearer` ([description_handlers:65][go-set65]). Из Google, Yandex и OSM отдаётся один, по приоритету. Mapbox или `mapboxTilesSrc` отдаётся всегда: «Used on the cameras map, so must be provided regardless» ([description_handlers:111][go-set111]). На ветке прав и на `develop` код одинаковый ([develop:108][go-setdev]).
- Пункт «Карта камер» меню показывает, только если задан `mapboxAPIKey` или `mapboxTilesSrc` ([AppMenu:155][cm-menu155]).
- **Вывод:** операторская часть на `/im/` может взять ключ и тайлы тем же запросом `/settings` со своим токеном и отрисовать карту тем же `mapbox-gl`. Если на установке (on-prem) ключа нет, карты не будет — нужен запасной вариант.

**Ответ: слои карты (`CLOUD-22804`).**
- Ветки: в портале — `CLOUD-22804-epic-user-map-layers`, последний коммит 2026-09-23 (`b37ab53`); в бэкенде — `feature/CLOUD-22804-epic-map-layers`, последний коммит 2026-09-29 (`d16ce31`, слияние `develop` в эпик). В `develop` не влиты. PR бэкенда #2289, #2295, #2303 влиты в ветку эпика.
- Что это: **личные слои пользователя** (`owner_id`) с полями `name`, `color`, `icon`, `visible`. В слое — **гео-точки** `name`, `description`, `lat`, `lng`, автор. Есть поиск, импорт и экспорт GeoJSON/CSV, экспорт всех слоёв zip-архивом ([api/maps.ts][ui-maps], [types:11][ui-maptypes3]). API: `/api/v3/ac-backend/maps/layers[/{id}[/objects|/export]]`, `/maps/objects/{id}`, `/maps/objects/search`, `/maps/layers/import`.
- Право — `core.maps.layer.manage.own` ([PR 2289][go-pr2289]). Привязку к домену из слоёв убрали в PR #2289 (`domain_id` удалён из таблицы `maps_layers`).
- Поэтажных планов, картинок-подложек, привязки камер или устройств к плану **нет**.
- **Вывод:** для решения «планы ждать от облака или хранить в МИ» эпик `map-layers` планов не даст. Это пометки пользователя на географической карте, а не планы объектов.
- **Ещё один источник планов — карты VMS.** Вебклиент умеет `axxonsoft.bl.maps.MapService.DownloadMapImage` ([httpApi:1024][wc-map]): в VMS есть карты с изображением (планы). Облако пропускает gRPC `/axxonsoft.bl.*` к VMS с правом `domains.domain.nativebl.use` ([04](04-axxoncloudgo.md#устройства-видео-события)). **Предположение:** планы с камерами можно читать из VMS домена, но формат, координаты камер на плане и права не проверял.

**Уверенность:** ключ, `/settings` и состав слоёв подтверждены кодом. Карты VMS как источник планов — предположение.
**Спросить у людей:**
- Команде облака (бэкенд слоёв — Mikhail Strunets, фронт — Petr Khoraskin): «Планируются ли в `map-layers` поэтажные планы (растровая подложка, привязка камер и устройств к плану)? Когда эпик пойдёт в `develop`?»
- Команде VMS и вебклиента: «Можно ли через облачный gRPC-прокси получить карты VMS (`MapService`: список, изображение, маркеры камер) для стороннего фронта? Какое право нужно?»
- Продукту и юристам: «Можно ли использовать ключ mapbox облака в операторской части МИ (лицензия, квоты)?»

## 5. CSP и `frame-src`

**Ответ.**
- Заголовки ставит nginx из **`IT/axxoncloud-deploy`**: Ansible-роли и шаблоны `ansible-hc/config/<заказчик>/…/nginx.conf.ctmpl.j2`. В `axxoncloudgo/tools/docker/*.conf` — только локальный стенд ([04](04-axxoncloudgo.md#сервисы-и-шлюз)).
- **Основной шаблон (`axxon/common`).** Статика портала (`location /`), `/multidomain`, `/reports-ui`, `/dd` и прокси arpserver включают `common-security-directives.conf`: `X-XSS-Protection`, `X-Content-Type-Options`, **`X-Frame-Options sameorigin`**, HSTS ([security.conf:3][dep-sec3]). Заголовка `Content-Security-Policy` нет. В прокси arpserver строка `#proxy_hide_header content-security-policy;` закомментирована: заголовок CSP самой VMS (если он есть) проходит к браузеру как есть ([nginx axxon][dep-axxon]). Добавлен `Access-Control-Allow-Origin "https://{{ default_hostname }}"`.
- **Вариант с отдельным nginx на сервере arpserver (`arpext-nginx`).** Здесь CSP самой VMS скрывается (`proxy_hide_header content-security-policy`) и ставится свой: `Content-Security-Policy "frame-ancestors 'self' https://{{ default_hostname }}"` ([arpext security:3][dep-arpsec3], [nginx-arp][dep-arp]).
- **Адрес вебклиента** в боевом шаблоне: `/{{hostname arpserver}}/<domain>_<n>/webclient/...`. Это тот же хост, что и портал, либо хост arpext ([nginx axxon][dep-axxon]).
- **`CSP_NONCE`.** В `index.html` портала стоит `<meta property="csp-nonce" content="CSP_NONCE">`, `create-nonce.ts` читает его в `__csp_nonce__` ([create-nonce][ui-nonce]). Подстановки на шлюзе нет: `sub_filter` в `IT` не найден, а CSP-заголовка, к которому этот nonce относился бы, нет. **Вывод:** nonce сейчас ни на что не влияет.
- **Разрешено ли встраивать вебклиент домена в iframe на `/im/`.** **Вывод:** да, если `/im/` открыт на том же хосте, что портал (`default_hostname`):
  - на основном шаблоне — `X-Frame-Options sameorigin`, тот же origin;
  - на arpext — `frame-ancestors` явно разрешает `https://default_hostname`.
  
  Своего `frame-src` нет, на `/im` в шаблоне `bezeq` заголовки безопасности не подключены вовсе ([bezeq:453][dep-bezeq453]). Не сработает, если операторскую часть вынести на другой поддомен. Неизвестно и то, что пишет в CSP сама VMS, если её заголовок проходит в основном шаблоне.

**Уверенность:** подтверждено кодом деплоя (`IT/axxoncloud-deploy` `91d1e6d`). Какие шаблоны применены на конкретном стенде — не знаю.
**Спросить у людей:**
- DevOps (по коммитам — Feliks Fanziev): «Какой шаблон nginx стоит на основных облаках (AxxonNet, `axxon/common`?) и где arpext? Будет ли `location /im` (и `/api/v1/im-backend`) во всех шаблонах, а не только у `bezeq`?»
- Команде VMS: «Какой `Content-Security-Policy` отдаёт веб-сервер VMS для вебклиента (есть ли `frame-ancestors`)?»

## 6. Тема: OEM-тема MUI и светлая/тёмная

**Ответ.**
- **Портал.**
  - Тема — `createTheme` в `config/muiThemes.ts`. По умолчанию — стандартная MUI ([muiThemes][ui-themes]). Каждый OEM подменяет файл при сборке: у AxxonNet синий `blue[600]`, оранжевый `deepOrange[500]`, фон `#e8e8e8`, кнопки без капса, отдельно `darkTheme` и `blotboxTheme` ([oem AxxonNet][ui-oemtheme]).
  - Цвета карты берутся из той же темы ([config/map.ts][ui-mapcfg]).
  - CSS-переменных и общего пакета темы нет: в `NEW/axxon-web` только `ui`, `auth`, `cloud-menu`, `types`, `hooks`, `host-info`, пакета темы нет ([README][aw-readme]).
- **Светлая/тёмная.** Режим берётся так: `localStorage['theme-mode']` → `localStorage['theme']` (JSON) → `config/themeMode.defaultMode` (OEM может задать, например AxxonAir) → `prefers-color-scheme` ([utils.ts][ui-tmutils]). Переключатель пишет оба ключа ([index.tsx:34][ui-tmidx]). Комментарий: ключ «also used in reports, dashboards, webconfigurator» ([constants:3][ui-tmconst]). Тот же ключ `theme-mode` читают `web-configurator`, `pos-ui`, `supervisor2-webui` и другие (поиск по Bitbucket). **Вывод:** это негласное соглашение веб-приложений AxxonSoft. SPA на `/im/` (тот же origin) может читать и писать `theme-mode`, но смену темы в другой вкладке узнает только при перезагрузке: в портале нет обработчика `storage` ([06](06-axxoncloud-ui.md#авторизация)).
- **Получить OEM-цвета во время работы нельзя**: тема зашита в бандл портала. Чтобы совпасть с порталом, нужно собрать SPA с той же OEM-темой (копия `oem/<V>/app/config/muiThemes.ts`).
- **Конфигуратор.** OEM-тема MUI подставляется при сборке (алиас `@/theme` → `oem/<VITE_VENDOR_NAME>/theme.ts`). Сейчас есть только `oem/Default`: светлая, `#1976d2`, шрифт Inter, без тёмной темы, `theme-mode` не читает (поиск по `src` — 0) ([02](02-im-configurator.md#стек-и-выкладка), [Default theme][im-theme]).
- **Прототип.**
  - Тема — CSS-переменные ONE PSIM `--one-*` в `theme/one-psim.css`, по шапке файла сгенерированы из `ONE.PSIM.Web.DesignSystem/packages/tokens` (коммит `9c75f4e`), со светлым и тёмным набором `[data-theme]` ([one-psim.css](../../theme/one-psim.css)).
  - `prototype/bridge.css` переводит переменные прототипа на эти токены; комментарии ссылаются на `oneTheme.ts MuiButton` дизайн-системы ([bridge.css](../../prototype/bridge.css)) — **вывод:** у ONE PSIM есть и MUI-тема.
  - Режим прототипа хранится в `localStorage['im-theme']`, по умолчанию `dark` ([app.js:4292](../../prototype/app.js#L4292), [app.js:738](../../prototype/app.js#L738)).
  - Репозитория `ONE.PSIM.Web.DesignSystem` на Bitbucket не нашёл: поиск `PSIM.Web.DesignSystem` и `oneTheme` дал только сам прототип.
- **Сравнение для решения.**

| | ONE PSIM (токены + `oneTheme.ts`) | OEM-тема MUI, как у портала и конфигуратора |
|---|---|---|
| Вид рядом с порталом | свой, не совпадает с OEM-цветами портала | совпадает, если собрать с той же OEM-темой |
| OEM-варианты | нет механизма; один вид на всех | есть: файл темы на вендора при сборке (у портала 62, у конфигуратора 1) |
| Тёмная тема | есть в токенах (`[data-theme="dark"]`) | у портала есть (`darkTheme`), у конфигуратора нет |
| Режим из портала | читать `theme-mode` и ставить `data-theme` | читать `theme-mode` и выбирать `theme`/`darkTheme` |
| Где взять | дизайн-система вне Bitbucket (локальная копия) | копировать `muiThemes.ts` из `axxoncloud-ui/oem/<V>` |

**Вывод:** если операторская часть живёт рядом с конфигуратором на одном стеке (React + MUI), то естественный путь — OEM-тема MUI, как у конфигуратора, плюс тёмная тема и чтение `theme-mode`. ONE PSIM имеет смысл, если продукт хочет единый вид PSIM поверх всех OEM — тогда ONE PSIM нужен как MUI-тема (`oneTheme.ts`), а репозиторий дизайн-системы — доступный для сборки. Решать продукту.

**Уверенность:** портал и конфигуратор подтверждены кодом. ONE PSIM — по локальным файлам прототипа; источник дизайн-системы не найден.
**Спросить у людей:**
- Продукту и дизайну: «Операторская часть — в виде ONE PSIM для всех OEM или в OEM-теме портала? Нужна ли тёмная тема по умолчанию (в прототипе по умолчанию тёмная)?»
- Владельцу дизайн-системы ONE PSIM: «Где репозиторий `ONE.PSIM.Web.DesignSystem` (`oneTheme.ts`)? Можно ли подключить его к сборке МИ?»

## Поправки к первому кругу

| Файл | Что там сказано | Как на самом деле |
|---|---|---|
| [06](06-axxoncloud-ui.md#коротко), [00](00-summary.md#вопросы) | исходников `@axxon-web/cloud-menu` в `PROJ` нет; версия 1.6.0 | Исходники — `NEW/axxon-web/packages/cloud-menu`. На основном снимке портала (`83a04e5`) стоит 1.4.5, на `develop` — 1.6.0 |
| [06, Права](06-axxoncloud-ui.md#права-в-интерфейсе) | «Предположение: `CAP.incidentManager` проверяет пакет меню» | Подтверждено: пункт `/im/` виден при любом действии в `incident_manager` ([AppMenu:92][cm-menu92]) |
| [06, Видео](06-axxoncloud-ui.md#видео-карты-события-уведомления) | протокол видео не виден; сверить с `axxonnext.webclient` | Сверено: WebSocket + MSE (fMP4) или MJPEG; полный протокол — п. 3 |
| [06, Ограничения](06-axxoncloud-ui.md#ограничения-для-операторского-места) | «Предположение: замена `CSP_NONCE` делается на шлюзе» | В `IT/axxoncloud-deploy` подстановки нет и заголовка CSP нет; есть `X-Frame-Options sameorigin` (п. 5) |
| [06, Открытые вопросы](06-axxoncloud-ui.md#открытые-вопросы) №1, 2, 5, 8, 10 | открыты | Ответы — пп. 1–5 этого файла |
| [04, Коротко](04-axxoncloudgo.md#коротко), [00](00-summary.md) | слов `incident`/`im` в деплое нет; боевого деплоя нет | В `axxoncloudgo` — так. Но боевой деплой есть — `IT/axxoncloud-deploy`. В шаблоне `bezeq` (`common`, `pos1`) есть `location /im` (статика из `/data/axxoncloud/im`), `location /api/v1/im-backend` → upstream `im-backend` ([bezeq:453][dep-bezeq453]); планы Bamboo «Incident Manager Deploy» и «Incident Manager UI Deploy» (стенды Bezeq POS1, Test2, d.itdep.net, Docker Hub); плейбук `deploy-im-ui.yml` кладёт `ui-Default.zip` в `/data/axxoncloud/im` ([deploy-im-ui][dep-imui]) |
| [04, Устройства](04-axxoncloudgo.md#устройства-видео-события), [00, Риски](00-summary.md) | `configsync /internal/*` наружу через nginx; закрыто ли на боевом шлюзе — неизвестно | В боевых шаблонах (`axxon/common`, `bezeq/common`) `location /api/v1/configsync/internal { return 403; }` ([nginx axxon][dep-axxon]) |
| [04](04-axxoncloudgo.md#устройства-видео-события), [00, Карта связей](00-summary.md#карта-связей) | адрес видео `/arpserver/<domainId>_<n>/webclient/...` | Это локальный стенд. В боевом шаблоне префикс — имя хоста arpserver из Consul (`/{{hostname}}/<…>/webclient/…`). Адрес брать из `domain.webClientURL`, а не собирать |
| [00, Коротко](00-summary.md#коротко), [04, Реальное время](04-axxoncloudgo.md#реальное-время) | реального времени в облаке нет | В шаблоне `bezeq` есть WebSocket `location /api/v1/notifier/connect` → `backend` ([bezeq:383][dep-bezeq383]). В `axxoncloudgo` (ветка по умолчанию, поиск `notifier`) такого обработчика не нашёл. Надо спросить, что это и где код |
| [06, Видео](06-axxoncloud-ui.md#как-подключаются-приложения-и-im) | токен в iframe — `authToken` и `AxxonCloudToken` | Вебклиент слушает только `authToken` (и `nextToken`); `AxxonCloudToken` в вебклиенте не встречается |

<!-- ссылки -->
[cm-pkg]: https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/axxon-web/browse/packages/cloud-menu/package.json?at=5654ae4fbebb914e01789c1ebf66376f26be0397
[cm-ex]: https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/axxon-web/browse/examples/cloud-menu/src/app/index.tsx?at=5654ae4fbebb914e01789c1ebf66376f26be0397#21
[cm-routes19]: https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/axxon-web/browse/packages/cloud-menu/src/entities/routes/constants/index.ts?at=5654ae4fbebb914e01789c1ebf66376f26be0397#19
[cm-ru]: https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/axxon-web/browse/packages/cloud-menu/src/translations/ru.json?at=5654ae4fbebb914e01789c1ebf66376f26be0397#18
[cm-menu4]: https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/axxon-web/browse/packages/cloud-menu/src/widgets/AppMenu/ui/index.tsx?at=5654ae4fbebb914e01789c1ebf66376f26be0397#4
[cm-menu92]: https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/axxon-web/browse/packages/cloud-menu/src/widgets/AppMenu/ui/index.tsx?at=5654ae4fbebb914e01789c1ebf66376f26be0397#92
[cm-menu119]: https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/axxon-web/browse/packages/cloud-menu/src/widgets/AppMenu/ui/index.tsx?at=5654ae4fbebb914e01789c1ebf66376f26be0397#119
[cm-menu155]: https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/axxon-web/browse/packages/cloud-menu/src/widgets/AppMenu/ui/index.tsx?at=5654ae4fbebb914e01789c1ebf66376f26be0397#155
[cm-menu301]: https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/axxon-web/browse/packages/cloud-menu/src/widgets/AppMenu/ui/index.tsx?at=5654ae4fbebb914e01789c1ebf66376f26be0397#302
[cm-cap30]: https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/axxon-web/browse/packages/cloud-menu/src/entities/user-capabilities/constants/index.ts?at=5654ae4fbebb914e01789c1ebf66376f26be0397#30
[cm-has10]: https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/axxon-web/browse/packages/cloud-menu/src/entities/user-capabilities/libs/index.ts?at=5654ae4fbebb914e01789c1ebf66376f26be0397#10
[cm-has127]: https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/axxon-web/browse/packages/cloud-menu/src/entities/user-capabilities/libs/index.ts?at=5654ae4fbebb914e01789c1ebf66376f26be0397#127
[cm-chlog]: https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/axxon-web/browse/packages/cloud-menu/CHANGELOG.md?at=5654ae4fbebb914e01789c1ebf66376f26be0397
[cm-app13]: https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/axxon-web/browse/packages/cloud-menu/src/app/index.tsx?at=5654ae4fbebb914e01789c1ebf66376f26be0397#13
[cm-model28]: https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/axxon-web/browse/packages/cloud-menu/src/app/model/index.ts?at=5654ae4fbebb914e01789c1ebf66376f26be0397#28
[cm-api5]: https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/axxon-web/browse/packages/cloud-menu/src/shared/api/index.ts?at=5654ae4fbebb914e01789c1ebf66376f26be0397#5
[cm-readme59]: https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/axxon-web/browse/packages/cloud-menu/README.md?at=5654ae4fbebb914e01789c1ebf66376f26be0397#59
[cm-sh13]: https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/axxon-web/browse/packages/cloud-menu/src/shared/libs/storageHelper.ts?at=5654ae4fbebb914e01789c1ebf66376f26be0397#13
[cm-i18n]: https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/axxon-web/browse/packages/cloud-menu/src/shared/i18n/model.ts?at=5654ae4fbebb914e01789c1ebf66376f26be0397#9
[cm-mk3]: https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/axxon-web/browse/Makefile?at=5654ae4fbebb914e01789c1ebf66376f26be0397#3
[aw-readme]: https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/axxon-web/browse/README.md?at=5654ae4fbebb914e01789c1ebf66376f26be0397
[aw-ext10]: https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/axxon-web/browse/packages/auth/src/shared/hooks/useExternalToken.ts?at=5654ae4fbebb914e01789c1ebf66376f26be0397#10
[aw-cloud9]: https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/axxon-web/browse/packages/auth/src/shared/api/cloud.ts?at=5654ae4fbebb914e01789c1ebf66376f26be0397#9
[ui-pkg50]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/package.json?at=83a04e587c90809e10c4efb4b5a57ce29a335174#50
[ui-pkgdev50]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/package.json?at=d436dd1c24cde57170db56143b8b17e7fc820b23#50
[ui-menu18]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/components/AppMenu/index.tsx?at=83a04e587c90809e10c4efb4b5a57ce29a335174#18
[ui-menu39]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/components/AppMenu/index.tsx?at=83a04e587c90809e10c4efb4b5a57ce29a335174#39
[ui-nonce]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/create-nonce.ts?at=83a04e587c90809e10c4efb4b5a57ce29a335174#9
[ui-themes]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/config/muiThemes.ts?at=83a04e587c90809e10c4efb4b5a57ce29a335174
[ui-oemtheme]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/oem/AxxonNet/app/config/muiThemes.ts?at=83a04e587c90809e10c4efb4b5a57ce29a335174
[ui-mapcfg]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/config/map.ts?at=83a04e587c90809e10c4efb4b5a57ce29a335174
[ui-tmutils]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/containers/ThemeModeContextProvider/utils.ts?at=83a04e587c90809e10c4efb4b5a57ce29a335174#11
[ui-tmidx]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/containers/ThemeModeContextProvider/index.tsx?at=83a04e587c90809e10c4efb4b5a57ce29a335174#34
[ui-tmconst]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/containers/ThemeModeContextProvider/constants.ts?at=83a04e587c90809e10c4efb4b5a57ce29a335174#3
[ui-maps]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/api/maps.ts?at=b37ab5381e1c312b11de4c0efb7faf7ab0b5121a
[ui-maptypes3]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/containers/CamerasMap/types.ts?at=b37ab5381e1c312b11de4c0efb7faf7ab0b5121a#3
[wc-rules]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxonnext.webclient/browse/.claude/rules/embedded.md?at=f1600edcc2208a05cb91d3944b75c8130da24dac#19
[wc-arch219]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxonnext.webclient/browse/docs/architecture.md?at=f1600edcc2208a05cb91d3944b75c8130da24dac#219
[wc-types5]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxonnext.webclient/browse/src/embedded/types.ts?at=f1600edcc2208a05cb91d3944b75c8130da24dac#5
[wc-types34]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxonnext.webclient/browse/src/embedded/types.ts?at=f1600edcc2208a05cb91d3944b75c8130da24dac#34
[wc-types40]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxonnext.webclient/browse/src/embedded/types.ts?at=f1600edcc2208a05cb91d3944b75c8130da24dac#40
[wc-types69]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxonnext.webclient/browse/src/embedded/types.ts?at=f1600edcc2208a05cb91d3944b75c8130da24dac#69
[wc-const3]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxonnext.webclient/browse/src/embedded/constants.ts?at=f1600edcc2208a05cb91d3944b75c8130da24dac#3
[wc-const15]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxonnext.webclient/browse/src/embedded/constants.ts?at=f1600edcc2208a05cb91d3944b75c8130da24dac#15
[wc-const22]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxonnext.webclient/browse/src/embedded/constants.ts?at=f1600edcc2208a05cb91d3944b75c8130da24dac#22
[wc-emb55]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxonnext.webclient/browse/src/embedded/embedded.ts?at=f1600edcc2208a05cb91d3944b75c8130da24dac#55
[wc-fb]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxonnext.webclient/browse/src/embedded/feedback.ts?at=f1600edcc2208a05cb91d3944b75c8130da24dac
[wc-ch9]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxonnext.webclient/browse/src/embedded/CommandHandler.ts?at=f1600edcc2208a05cb91d3944b75c8130da24dac#9
[wc-ch32]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxonnext.webclient/browse/src/embedded/CommandHandler.ts?at=f1600edcc2208a05cb91d3944b75c8130da24dac#32
[wc-state96]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxonnext.webclient/browse/src/embedded/State.ts?at=f1600edcc2208a05cb91d3944b75c8130da24dac#93
[wc-utils83]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxonnext.webclient/browse/src/embedded/utils.tsx?at=f1600edcc2208a05cb91d3944b75c8130da24dac#83
[wc-urlp]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxonnext.webclient/browse/src/entities/url-params/model/sagas.ts?at=f1600edcc2208a05cb91d3944b75c8130da24dac#8
[wc-wrk66]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxonnext.webclient/browse/src/entities/media/model/MediaConn.wrk.ts?at=f1600edcc2208a05cb91d3944b75c8130da24dac#66
[wc-misc179]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxonnext.webclient/browse/src/shared/lib/utils/misc/index.ts?at=f1600edcc2208a05cb91d3944b75c8130da24dac#179
[wc-map]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxonnext.webclient/browse/src/modules/httpApi.ts?at=f1600edcc2208a05cb91d3944b75c8130da24dac#1024
[go-cfg315]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/util/config/config.go?at=e51bd552b593db9fdedba16505808bde48b1db96#315
[go-set65]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/handler/v3/description_handlers.go?at=e51bd552b593db9fdedba16505808bde48b1db96#65
[go-set111]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/handler/v3/description_handlers.go?at=e51bd552b593db9fdedba16505808bde48b1db96#111
[go-setdev]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/handler/v3/description_handlers.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#108
[go-pr2289]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/pull-requests/2289/diff
[dep-axxon]: https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/ansible-hc/config/axxon/common/nginx/nginx.conf.ctmpl.j2?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec
[dep-sec3]: https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/ansible-hc/roles/nginx/files/common-security-directives.conf?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec#3
[dep-arpsec3]: https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/ansible-hc/roles/arpext-nginx/templates/common-security-directives.conf.j2?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec#3
[dep-arp]: https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/ansible-hc/roles/arpext-nginx/templates/nginx-arp.conf.j2?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec
[dep-bezeq383]: https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/ansible-hc/config/bezeq/common/nginx/nginx.conf.ctmpl.j2?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec#383
[dep-bezeq453]: https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/ansible-hc/config/bezeq/common/nginx/nginx.conf.ctmpl.j2?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec#453
[dep-imui]: https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/ansible-hc/deploy-im-ui.yml?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec
[im-theme]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/oem/Default/theme.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#3
