# Фронтенд облака: axxoncloud-ui

- Репозиторий: `PROJ/axxoncloud-ui` (Bitbucket `src.axxonsoft.dev`), в `package.json` называется `axxonnet-ui` 3.30.0
- Ветка: `develop`, коммит `d436dd1c24cde57170db56143b8b17e7fc820b23` (на 2026-10-28 это вершина `develop`)
- Дата изучения: 2026-10-28
- Как читали: только Bitbucket MCP, без клонирования. Поиск Bitbucket ищет по ветке по умолчанию с отставанием: например, `incidentManager` поиском не находится, хотя на нашем коммите он есть в коде. Поэтому всё найденное перепроверено чтением на коммите выше; номера строк — по нашему коммиту.

Обозначения: «Вывод:» — наше заключение из фактов; «Предположение:» — не проверено кодом. Ссылки — в конце файла, все на коммит `d436dd1`.

## Коротко

- Портал облака — одно React-приложение (React 18, MUI 9, Redux + redux-saga, react-intl, Vite 8). Один код собирается в 62 OEM-варианта; каждый — свой zip со статикой. Своего nginx в репозитории нет.
- Меню облака — внешний npm-пакет `@axxon-web/cloud-menu` 1.6.0 (исходников в `PROJ` нет). В нём есть пункт `incidentManager`. Портал помечает его как внешний маршрут, то есть переход уводит со страницы портала ([AppMenu:18][menu18]). Адреса `/im/` в коде портала нет — он зашит в пакете меню.

> Поправка (второй круг, 2026-10-28): исходники — `NEW/axxon-web/packages/cloud-menu`; на ветке портала `83a04e5` стоит 1.4.5, на `develop` — 1.6.0. Пункт `/im/` виден при любом действии в `incident_manager`. См. [13, поправки](13-cloud-ui-menu-video.md#поправки-к-первому-кругу), [13, п. 1](13-cloud-ui-menu-video.md#1-пакет-axxon-webcloud-menu).

- В портале три способа показать чужое приложение:
  1. **iframe** (`EmbeddedInterface`): вебклиент VMS домена, плеер на карте камер, «пользовательские веб-приложения» `/custom-apps/:slug` → `/apps/<slug>/index.html`. Токен уходит в адресе `?authToken=…`, новый токен — через `postMessage`.
  2. **npm-пакет React-компонента**: мини-конфигуратор `@axxonsoft/mini-configurator` рисуется прямо внутри портала.
  3. **Внешний маршрут меню**: `analytics`, `demoDashboard`, `updateService`, `incidentManager` — обычный переход, страница портала закрывается.
- Токены лежат в `localStorage` (или в `sessionStorage` — при входе через DomaAI OIDC) под ключами `accessToken` / `refreshToken`. Обновляет их сам портал раз в 20 с, если до истечения меньше ~7 мин. **Вне портала (например, на `/im/`) токен никто не обновляет.**
- Права — дерево `capabilities` из `GET /api/v3/ac-backend/me`. Пространство `incident_manager` во фронте уже есть; есть и константа `CAP.incidentManager = 'incident_manager'`. Но разбор прав понимает только действия `create/view/edit/…`. Действия МИ (`take`, `close`, `assign`…) он считает неверными.
- Для оператора готового нет: ни списка тревог, ни уведомлений в реальном времени (WebSocket есть только у терминала устройства), ни звука, ни планов объектов. Видео живое и архив — только через iframe вебклиента домена (`embedded.html` + `postMessage init`). Карта — mapbox-gl с камерами из `configsync`.
- **Рекомендация:** операторскую часть делать отдельным SPA в том же origin, рядом с конфигуратором (вариант А ниже). Обновление токена, тайм-аут бездействия и меню облака придётся сделать у себя: меню — через тот же пакет `@axxon-web/cloud-menu`.

## Стек

| Что | Факт |
|---|---|
| Фреймворк | React 18.3.1, react-dom, react-router-dom 7.18 (история браузера, не hash — [routerConfig][router]) ([package.json][pkg]) |
| Сборка | Vite 8.2 + `@vitejs/plugin-react`, свои плагины `oemOverlay/oemHtml/oemPublic/tsv/markdown` ([vite.config.ts][vite]). Цель `es2020`, в dev — прокси `/api` → `PROXY_TARGET` ([vite.config.ts:76][vite76]). `API_ORIGIN` подставляется при сборке ([vite.config.ts:40][vite40]) |
| OEM | 62 папки в `oem/`. При сборке файлы OEM подменяют файлы `app/` с тем же путём. Makefile собирает `ui-<VENDOR>.zip` с корнем `/ui` ([Makefile][make]). Сборка в docker `node:24-alpine` ([Dockerfile][docker]), CI — Bamboo ([bamboo.json][bamboo]) |
| UI-кит | MUI 9 (`@mui/material`, `icons-material`, `x-date-pickers`), emotion. Своей дизайн-системы нет. Тема — `createTheme` в `config/muiThemes.ts`, OEM переопределяет: AxxonNet — синий `blue[600]`, оранжевый `deepOrange[500]`, фон `#e8e8e8` ([oem AxxonNet muiThemes][oemtheme]). Токенов дизайна (CSS-переменных) нет |
| Темы | Светлая и тёмная. Выбор хранится в `localStorage['theme-mode']` и `localStorage['theme']` (JSON). Комментарий в коде: ключ «also used in reports, dashboards, webconfigurator» ([constants.ts:3][tm3]). По умолчанию тема следует `prefers-color-scheme` ([utils.ts:11][tmu11]). На `body` ставится класс тёмной темы ([index.tsx:48][tmi48]) |
| i18n | react-intl 6. Переводы — TSV `id<TAB>текст`: общие `app/common-translations/common-<lang>.tsv` (34 файла, в том числе `ru`) и OEM `oem/<V>/app/translations/<lang>.tsv`, грузятся лениво ([i18n.ts:9][i18n9]). RTL для `ar/he/…` |
| Язык | Сначала язык браузера ([reducer.ts:13][lang13]), потом `user.locale` из `/me`. Смена сохраняется на сервере в настройках пользователя ([sagas.ts:13][langs13]). В `localStorage` язык не хранится |
| Состояние | Redux 5 + RTK 2 + redux-saga 1.5. Редьюсеры и саги подгружаются вместе со страницей ([Routes/index.tsx][routesidx]) |
| Тесты | Jest 30 + jsdom, `redux-saga-test-plan`. `npm test` всегда завершается с кодом 0 (в конце стоит `exit 0` на случай ошибки) ([package.json][pkg]). Линт — eslint airbnb + prettier, husky |
| Прочее | Cordova-сборка (DomaAI), PWA service worker `sw.js`, `nonce` для CSP ([create-nonce.ts][nonce]) |

## Как подключаются приложения (и /im/)

**Меню.** `AppMenu` рисует компонент `AppMenu` из пакета `@axxon-web/cloud-menu` и передаёт ему `locale`, `capabilities`, `settings`, списки `externalRoutes`, `hiddenRoutes` и `extraAppMenu` ([AppMenu:39][menu39]). Внешние маршруты: `analytics`, `demoDashboard`, `updateService`, `incidentManager` ([AppMenu:18][menu18], [AppMenu:22][menu22]). Шаблоны путей тоже берутся из пакета: `cloudMenuRoutes.pattern('…')` ([routes.tsx][routes]). Пакет ставится из Artifactory `@axxon-web` ([.npmrc][npmrc]). Репозитория `cloud-menu` в проекте `PROJ` нет (искал в списке репозиториев).
- Вывод: пункт «Incident Manager» и его адрес (`/im/`) задаёт пакет меню. Портал только говорит: «это внешний маршрут». Как пакет решает, показывать ли пункт (по `capabilities.incident_manager`?), из этого репозитория не видно.
- OEM может добавить свои пункты через `config/extraAppMenu.tsx` (`{condition, label, routeName, pattern, onClick}`, пример — [ZainTechBank][zain]), а маршруты — через `config/extraRoutes.tsx` ([extraRoutes][extra], пример — [AxxonNet][extraaxx]). Это расширение во время сборки, а не плагины во время работы.

**Как сейчас открыт конфигуратор `/im/`.** В портале нет маршрута `/im`. Страница `/configurator` — это **другое**: мини-конфигуратор VMS из пакета `@axxonsoft/mini-configurator` ([Configurator:3][conf3]), его права `core.mini_configurator.use` скрыты в настройках прав ([permissions.ts:13][perm13]). Значит, `/im/` открывается как внешняя ссылка из меню, с полной загрузкой страницы. Это совпадает с [02-im-configurator.md](02-im-configurator.md). Раздачу `/im/` делает шлюз облака, а не этот репозиторий (см. [04-axxoncloudgo.md](04-axxoncloudgo.md)). Похожий случай есть прямо в коде: для `multidomainClient` комментарий «если multidomain развёрнут, запрос обработает nginx, иначе пустая страница» ([Routes:820][routes820]).

**Встраивание через iframe — компонент `EmbeddedInterface`** ([EmbeddedInterface][emb]):
- `src` задаётся один раз. К адресу добавляется `?authToken=<accessToken>` и, если нужно, `proxyPrefix` ([EmbeddedInterface:76][emb76]).
- Когда токен обновился, в iframe уходят `postMessage({type:'authToken', token})` и `{type:'AxxonCloudToken', token}` ([EmbeddedInterface:102][emb102]). Произвольное сообщение `message` уходит после загрузки.

> Поправка (второй круг, 2026-10-28): вебклиент слушает только `authToken` (и `nextToken`); `AxxonCloudToken` в нём не встречается. См. [13, поправки](13-cloud-ui-menu-video.md#поправки-к-первому-кругу).

- Атрибуты iframe: только `allowFullScreen` и `frameBorder=0` ([EmbeddedInterface:193][emb193]). `allow="autoplay; microphone; …"` и `sandbox` нет.

Кто так встроен:
| Где | Что в iframe | Что передаётся |
|---|---|---|
| `/dashboard/domain/:id/webclient` | вебклиент VMS домена `domain.webClientURL` (+`wsURL`, `show_cloud_export`) | токен, `{type:'cloudLocale', cloudLocale}` ([Webclient:32][wc33]) |
| `/cameras-map` (плеер у камеры) | `<webClientURL>/embedded.html` | `{type:'init'\|'reInit', mode:'live'\|'archive', origin: accessPoint, options:{eventsPanel:false, alertReview:false, …}}`. Ждёт от iframe `{type:'embeddedLoad', value:true}`, иначе через 5 с шлёт init сам ([EmbeddedInterfaceWrapper:102][eiw102], [:166][eiw166]) |
| `/custom-apps/:slug` | `${origin}/apps/<slug>/index.html` | только токен; язык и тема не передаются ([CustomAppPage:40][cap40]) |
| Webconfigurator, Supervisor (Failover), веб-конфигуратор устройства | аналогично, по URL домена или устройства | токен |

**Пользовательские веб-приложения (custom apps)** — механизм появился в `develop` 26–27.10.2026 (PR #1452, #1470, #1471, #1472):
- список, загрузка, обновление и удаление zip — `GET/POST/PUT/PATCH/DELETE /api/v1/ad-backend/custom-apps[/slug]` ([api/customApps.ts][capi]); обслуживает их не `axxoncloudgo`, а отдельный сервис вне этого исследования;
- права: `axxon_data.custom_web_apps.view` / `.edit` ([constants.ts:67][cap67]); страница закрыта для тех, у кого нет `view` ([RedirectCustomApps][capredir]);
- маршруты `/custom-apps` и `/custom-apps/:slug` ([routes.tsx:129][routes129], [Routes:791][routes791]).
- Вывод: это ближайший к «плагинам» механизм. Но приложение живёт в iframe внутри страницы портала, получает только токен, а его API живёт в сервисе вне этого исследования.

**Токен, язык, тема, организация — как сейчас получают встроенные приложения:**
- Токен — `?authToken=` и `postMessage` (iframe). Приложение на том же origin (`/im/`) может прочитать его из `localStorage` само.
- Язык — `postMessage cloudLocale` только у вебклиента. Иначе — самим из `/me`.
- Тема — общего канала нет. В том же origin можно читать `localStorage['theme-mode']`.
- «Текущей организации» в портале нет. Есть домены (VMS) с правами на каждый, деревья пользователей и доменов (`/user-rights/...`). Домен выбирается маршрутом `/dashboard/domain/:domainId/...` ([routes.tsx:29][routes29]). Глобального «выбранного домена» в хранилище не нашёл (искал в `Domains`, `BaseApp`, `routes`).

## Авторизация

- **Вход:** формы портала. Двухшаговый «auth-flow» `GET/POST /api/v3/ac-backend/auth-flow/...` (OTP, TOTP, телефон), в ответе `{accessToken, refreshToken}` ([auth-flow.ts][authflow]). Есть ещё соцсети, SAML (`/auth/saml`) и DomaAI OIDC.
- **Хранение:** `storageHelper` — `localStorage` по умолчанию, `sessionStorage`, если там уже есть пара токенов ([storageHelper.ts:137][sh137]). Ключи `accessToken`, `refreshToken`, `isSocialAuth`, `clientId`, `authFlowToken` ([storageHelper.ts:6][sh6], [:66][sh66]). При входе DomaAI OIDC включается `sessionStorage` ([DomaAIOidcCallback][oidc]).
  - Вывод: приложение, которое читает только `localStorage.accessToken` (так делает конфигуратор МИ), при входе через sessionStorage токена не найдёт.
- **Запросы:** `Authorization: Bearer <accessToken>` ([api-utils.ts:46][au46]), плюс заголовок `Time-Zone`. Базовые пути: `/api/v1`, `/api/v3`, `/api/v1/ad-backend` ([api-utils.ts:17][au17]). Если токена нет — выход.
- **Обновление:** сага раз в 20 с проверяет `exp` и, если до него меньше `softLimit` (по тесту — 7 мин), шлёт `POST /api/v3/ac-backend/auth/tokens` с **refresh-токеном** в `Authorization`. Новую пару пишет в хранилище ([OAuthTokensRenewal/sagas.ts:14][rt14], [api/auth.ts:19][auth19]). Пока идёт обновление, остальные запросы ждут (`tokenRenewalGate`). Обновление работает, только пока открыта страница портала ([App/index.tsx:36][app36]).

> Поправка (второй круг, 2026-10-28): refresh одноразовый; срок access задаёт установка (по умолчанию сутки). Портал перечитывает хранилище каждый цикл, поэтому пару, записанную `/im/`, подхватит. См. [11, п. 1](11-auth-session.md#1-refresh-токен-одноразовый-или-нет-где-хранится-гонка-сроки), [11, п. 2](11-auth-session.md#2-обновление-пары-из-внешнего-spa-как-это-делает-портал-domaai), [11, поправки](11-auth-session.md#поправки-к-первому-кругу).

- **Выход:** `logoutSaga` шлёт запрос выхода (`api/users.logoutUser`, путь не смотрел), выходит из соцсетей и чистит токены ([BaseApp/sagas.ts:22][bs22]). Любой ответ 401 на обычный запрос сразу ведёт к выходу ([request.ts:94][rq94]).
- **Бездействие:** портал считает минуты без событий `mousemove/keydown/wheel/mousedown/touch*` на своём `window` ([IdleTime/index.tsx:39][idle39]) и разлогинивает по `user.inactiveLogoutTTLMin` ([IdleTime/sagas.ts:45][idles45]). Предупреждение показывается за минуту.
  - Вывод: события внутри iframe до `window` портала не доходят. Оператор, который работает только внутри встроенного iframe, будет разлогинен по таймеру портала.

> Поправка (второй круг, 2026-10-28): отключить тайм-аут для роли нельзя; фоновая вкладка портала по таймеру завершит общую сессию и выбьет и отдельное SPA на `/im/`. См. [11, п. 3](11-auth-session.md#3-тайм-аут-бездействия-inactivelogoutttlmin).

- Синхронизации между вкладками нет (искал `BroadcastChannel`; обработчик события `storage` не нашёл). Две вкладки обновляют токен каждая сама.

> Поправка (второй круг, 2026-10-28): при общем `localStorage` проигравшая гонку вкладка восстанавливается на следующем цикле; разлогин — только при разных копиях пары. См. [11, поправки](11-auth-session.md#поправки-к-первому-кругу).

- **Переключение организации/домена:** отдельного механизма нет — см. выше. Есть «многодоменный клиент» (`multidomainClient`), его отдаёт nginx.

## Права в интерфейсе

- Источник — `GET /api/v3/ac-backend/me` → `capabilities` (глобальное дерево), а в доменах — `userCapabilities` на каждый домен ([api/me.ts:8][me8], [Domains/types.ts:93][dt88]). OEM может переопределить права (`overridePermissions`) и спрятать их из редакторов ролей ([permissions.ts][perm], [UserCapabilities/sagas.ts:11][ucs11]).
- Формат строки: `пространство[.ресурс…].действие[.own|.any]`. Известные пространства: `core, domains, axxon_data, monitoring, update_server, incident_manager, sip` ([capabilities.ts:33][caps33]). Строка из одного пространства (`incident_manager`) — «истина, если в пространстве включено хоть одно действие» ([capabilities.ts:55][caps55]).
- Известные действия: `create, view, edit, delete, manage, use, run, share, export, import, download, apply, bind, encrypt, block` ([capabilities.ts:7][caps7]). **`take, close, track, assign, suspend, process` (их облако заводит для МИ — [04-axxoncloudgo.md](04-axxoncloudgo.md)) здесь нет**, и `hasCapability('incident_manager.incidents.take')` вернёт `false`.
- Константа `CAP.incidentManager = 'incident_manager'` ([constants.ts:66][cap66]). В самом портале она нигде не проверяется (по поиску, но индекс отстаёт). Предположение: её проверяет пакет меню, чтобы показать пункт МИ.

> Поправка (второй круг, 2026-10-28): подтверждено: пакет меню проверяет `incident_manager` (любое действие). На ветке `CLOUD-23284-epic-perms-catalog` экран глобальных ролей строится по каталогу с сервера: права МИ там видны и назначаются; `capabilities.ts` тот же. См. [13, поправки](13-cloud-ui-menu-video.md#поправки-к-первому-кругу), [10, поправки](10-permissions.md#поправки-к-первому-кругу).

- Как прячут: обёртки маршрутов `Redirect…`/`CanView…` уводят на `/`, если права нет ([RedirectCustomApps][capredir]). Пункты меню прячет пакет меню по `capabilities` и `hiddenRoutes`. Действия на страницах — через `useHasCapability(...)` и `useHasDomainCapability(domainId, ...)` ([UserCapabilities/index.tsx][ucidx]).

## Видео, карты, события, уведомления

| Нужно оператору | Что есть в портале | Можно ли взять |
|---|---|---|
| Живое видео и архив | Своего плеера нет. Видео показывает вебклиент VMS домена в iframe: целиком (`/webclient`) или облегчённый `embedded.html` с `postMessage init {mode:'live'\|'archive', origin: accessPoint}` ([EmbeddedInterfaceWrapper][eiw]). Протокол (WebRTC/HLS/MSE) внутри вебклиента — в этом репозитории не видно | Да, тем же способом: iframe `<webClientURL>/embedded.html` + тот же протокол сообщений. Нужен `domain.webClientURL` (`ServerDomain.webClientURL` — [Domains/types.ts:63][dt63]) и `accessPoint` камеры. Протокол стоит сверить с репозиторием `axxonnext.webclient` |
| Список камер | `GET /api/v1/configsync/cameras?filter[name]=&enabledOnly=true` ([api/configsync.ts][cs]) | Да, это API облака |
| Карта | `react-map-gl` 7 + `mapbox-gl` 1.13: камеры кластерами, всплывающие окна, геокодер, полноэкранный режим. Ключ и тайлы из `settings.mapboxAPIKey/mapboxTilesSrc` ([Map.tsx:3][map3], [:55][map55]). Есть Google Maps и Yandex ymaps3 (типы и nonce-комментарий) — где используются, не смотрел | Код не вынесен в пакет. Можно повторить на тех же библиотеках и ключах из `settings` |
| Планы объектов (поэтажные) | Не найдено (искал: plan, floor, layout в `components/`) | — |
| Список событий/тревог и обработка | Не найдено (искал `alarm`, `incident`, `event`; у вебклиента в карте `eventsPanel:false`, `alertReview:false` — тревоги есть в вебклиенте VMS, портал их выключает) | — |
| Уведомления в реальном времени | Нет. WebSocket — только терминал устройства `wss://<ptyURL>?authToken=` ([DeviceTerminal][term53]); `EventSource` не найден. «Подписки» на детекторы и отключения у пользователя домена — это настройки доставки (почта, пуш), а не поток в браузер ([SubscriptionForm][subs]) | — |
| Звук тревоги | Не найдено (искал `new Audio`, `alarm`) | — |
| Полный экран | хук `useFullScreen` (`requestFullscreen` с префиксами) ([useFullScreen.ts][fs19]) | Тривиально повторить |

> Поправка (второй круг, 2026-10-28): протокол видео сверен с `PROJ/axxonnext.webclient`: WebSocket + MSE (fMP4) или MJPEG, без WebRTC и HLS; команды `embedded.html` — [13, п. 3](13-cloud-ui-menu-video.md#3-протокол-embeddedhtml-вебклиента-vms). Ключ mapbox — из `GET /api/v3/ac-backend/settings`; эпик `map-layers` планов не даст ([13, п. 4](13-cloud-ui-menu-video.md#4-карта-ключ-mapbox-и-слои)).

Общей библиотеки компонентов, web components или module federation нет: всё внутри `app/`. Пакеты наружу: `@axxon-web/cloud-menu` и `@axxonsoft/mini-configurator` (пакет с компонентом страницы, его ест портал).

## Упоминания МИ

| Где | Что |
|---|---|
| [AppMenu/index.tsx:22][menu22] | `'incidentManager'` во внешних маршрутах меню |
| [UserCapabilities/constants.ts:66][cap66] | `incidentManager: 'incident_manager'` |
| [utils/capabilities.ts:33][caps33], [:55][caps55] | пространство `incident_manager`, пример «Namespace-only capability (e.g. `incident_manager`)» |
| Маршруты, переводы, `/im/` | не найдено: поиск `incident`, `incidentManager`, `incident-manager` даёт 0. По `"/im/"` — только шум. Подпись пункта меню, видимо, в пакете меню |

## Ограничения для операторского места

- **Полный экран:** у iframe портала есть `allowFullScreen`. Отдельной страницы «киоска» без шапки и меню нет. Предположение: внешняя страница вроде `/im/` эту проблему снимает.
- **Несколько мониторов и окон:** в портале нет ни `window.open`-сценариев, ни координации вкладок. Окна одного origin видят общий `localStorage` с токенами, но каждое обновляет токен само. Если сервер выдаёт одноразовый refresh-токен, два окна могут выбить друг друга — надо спросить у облака (см. вопросы).
- **Бездействие:** тайм-аут по `inactiveLogoutTTLMin` из профиля пользователя — для оператора на смене это критично. В iframe портал активность не видит. В отдельном SPA тайм-аут надо делать самим (или сознательно не делать).
- **Автовоспроизведение и звук:** у iframe нет `allow="autoplay"`. Звук тревоги из iframe без жеста пользователя браузер может заблокировать.
- **CSP:** в `index.html` есть `<meta property="csp-nonce" content="CSP_NONCE">`, Vite проставляет `nonce` ([index.html:7][html7], [vite.config.ts:68][vite68]). Сам заголовок CSP (и `frame-src`/`frame-ancestors`) ставит сервер, в репозитории его нет. Предположение: замена `CSP_NONCE` на nonce запроса делается на шлюзе.

> Поправка (второй круг, 2026-10-28): в `IT/axxoncloud-deploy` подстановки `CSP_NONCE` и заголовка CSP нет; есть `X-Frame-Options sameorigin`. См. [13, п. 5](13-cloud-ui-menu-video.md#5-csp-и-frame-src).

- **CORS:** запросы идут на тот же origin (`getApiOrigin()` = текущий host, если `API_ORIGIN` не задан при сборке, — [request.ts][rq]). Отдельное приложение в том же origin CORS не требует.
- **OEM:** портал собирается в 62 варианта со своими темами. Операторской части тоже понадобится OEM-тема (у конфигуратора своя OEM-схема, см. 02).
- Не по теме, но заметно: в `.npmrc` лежат учётные данные реестра в открытом виде ([.npmrc][npmrc]).

## Варианты встраивания операторской части

**А. Отдельное SPA в том же origin, переход из меню** (как конфигуратор `/im/`; например, `/im/operator` или `/im-operator/`).
- Плюсы: полный экран без шапки портала; свои окна и мониторы; свой цикл релизов; портал менять почти не нужно — нужен пункт в пакете меню и `location` на шлюзе. Тот же подход, что у конфигуратора: общий стек, сборка и OEM.
- Минусы: самим обновлять токен (тот же `POST /api/v3/ac-backend/auth/tokens`, писать в то же хранилище, учитывать `sessionStorage`), делать тайм-аут бездействия и выход по 401. Тема — читать `localStorage['theme-mode']`. Меню облака — если нужно, подключить `@axxon-web/cloud-menu` (нужен доступ к Artifactory и `capabilities` из `/me`). Видео — iframe `embedded.html` вебклиента по образцу карты камер.

**Б. Страница внутри портала с iframe** (по образцу `/custom-apps/:slug` или `/webclient`: новый маршрут в axxoncloud-ui → iframe на статику МИ).
- Плюсы: шапка, меню, вход и обновление токена — портальные; токен приходит готовым (`?authToken`, `postMessage`); единый вид с облаком.
- Минусы: правка axxoncloud-ui и релиз облака на все OEM. Таймер бездействия портала не видит работу внутри iframe — оператора разлогинит. Токен в URL (попадает в логи и историю). Нет `allow="autoplay"` для звука. Второе окно на другой монитор всё равно уходит с портала. Как «пользовательское веб-приложение» AD без доработки не годится: язык и тема не передаются, а API МИ из iframe AD закрыт (по 05).

**В. Модуль в бандле портала** (npm-пакет с React-страницей, как `@axxonsoft/mini-configurator`).
- Плюсы: самая плотная интеграция — общие store, токен, тема MUI, язык, права, таймер.
- Минусы: прототип на чистом JS — переписывать под React 18 + MUI 9 + redux-saga портала. Релиз МИ привязан к релизу облака и 62 OEM. Зависимость от команды облака. Тяжёлое рабочее место (видео, карта, звук) внутри общего бандла.

**Рекомендация:** вариант **А**. Сначала — на базе того же SPA или того же стека, что конфигуратор. Обновление токена, тайм-аут и обработку 401 вынести в общий для конфигуратора и оператора модуль. Видео — через `embedded.html` вебклиента. Меню облака — пакетом `@axxon-web/cloud-menu`, если продукту нужна навигация облака на экране оператора. Вариант Б оставить как запасной: «открыть МИ внутри портала» для редких пользователей, не для смены оператора.

## Открытые вопросы

1. Где исходники `@axxon-web/cloud-menu` и кто их ведёт? Какой адрес у пункта `incidentManager` и по какому праву он показывается? Можно ли добавить второй пункт («Оператор МИ») или подпункты?
2. Можно ли подключить `@axxon-web/cloud-menu` во внешнее SPA (лицензия, доступ к Artifactory, какие `settings` ему нужны)?
3. Refresh-токен одноразовый (ротация)? Что будет, если два окна оператора обновят токен одновременно? Какое время жизни у access-токена?
4. Нужен ли оператору тайм-аут бездействия `inactiveLogoutTTLMin` или для операторов его надо отключать (настройкой пользователя или роли)?
5. Протокол `embedded.html` вебклиента: полный список сообщений (`init`/`reInit`, `options`, переход к времени архива, несколько камер, события из iframe). Как вебклиент показывает видео (WebRTC/HLS/MSE) — смотреть в `axxonnext.webclient`.
6. Будет ли в облаке поток событий в браузер (WebSocket/SSE) для тревог МИ или МИ даёт свой?
7. Действия `take/close/assign…` в `utils/capabilities.ts` портала: добавлять ли их, если портал должен проверять права МИ (например, чтобы показывать пункт меню только оператору)?
8. Кто и где ставит заголовок CSP и заменяет `CSP_NONCE`? Разрешены ли `frame-src` на адреса вебклиентов доменов для приложения под `/im/`?
9. Что считать «организацией» для МИ: домен VMS, узел дерева доменов или группу пользователей? В портале глобального выбора нет.
10. Карта: какой ключ и тайлы mapbox в облаке (`settings.mapboxAPIKey`) и можно ли брать их операторской части? Где взять планы объектов?

> Поправка (второй круг, 2026-10-28): ответы: 1, 2 — [13, п. 1](13-cloud-ui-menu-video.md#1-пакет-axxon-webcloud-menu), [13, п. 2](13-cloud-ui-menu-video.md#2-можно-ли-подключить-axxon-webcloud-menu-во-внешнее-spa); 3 — [11, п. 1](11-auth-session.md#1-refresh-токен-одноразовый-или-нет-где-хранится-гонка-сроки); 4 — [11, п. 3](11-auth-session.md#3-тайм-аут-бездействия-inactivelogoutttlmin); 5 — [13, п. 3](13-cloud-ui-menu-video.md#3-протокол-embeddedhtml-вебклиента-vms); 6 — поток делает МИ, [11, п. 4](11-auth-session.md#4-вход-в-поток-событий-sse); 7 — [10, п. 3](10-permissions.md#3-фронт-облака-на-ветке-каталога); 8 — [13, п. 5](13-cloud-ui-menu-video.md#5-csp-и-frame-src); 9 — [12, п. 1](12-tenancy-users.md#1-что-считать-арендатором-ми); 10 — [13, п. 4](13-cloud-ui-menu-video.md#4-карта-ключ-mapbox-и-слои).

<!-- ссылки -->
[pkg]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/package.json?at=d436dd1c24cde57170db56143b8b17e7fc820b23
[npmrc]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/.npmrc?at=d436dd1c24cde57170db56143b8b17e7fc820b23
[vite]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/vite.config.ts?at=d436dd1c24cde57170db56143b8b17e7fc820b23
[vite40]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/vite.config.ts?at=d436dd1c24cde57170db56143b8b17e7fc820b23#40
[vite68]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/vite.config.ts?at=d436dd1c24cde57170db56143b8b17e7fc820b23#68
[vite76]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/vite.config.ts?at=d436dd1c24cde57170db56143b8b17e7fc820b23#76
[make]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/Makefile?at=d436dd1c24cde57170db56143b8b17e7fc820b23
[docker]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/docker/Dockerfile?at=d436dd1c24cde57170db56143b8b17e7fc820b23
[bamboo]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/bamboo.json?at=d436dd1c24cde57170db56143b8b17e7fc820b23
[router]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/config/routerConfig.ts?at=d436dd1c24cde57170db56143b8b17e7fc820b23#6
[oemtheme]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/oem/AxxonNet/app/config/muiThemes.ts?at=d436dd1c24cde57170db56143b8b17e7fc820b23
[tm3]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/containers/ThemeModeContextProvider/constants.ts?at=d436dd1c24cde57170db56143b8b17e7fc820b23#3
[tmu11]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/containers/ThemeModeContextProvider/utils.ts?at=d436dd1c24cde57170db56143b8b17e7fc820b23#11
[tmi48]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/containers/ThemeModeContextProvider/index.tsx?at=d436dd1c24cde57170db56143b8b17e7fc820b23#48
[i18n9]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/utils/i18n.ts?at=d436dd1c24cde57170db56143b8b17e7fc820b23#9
[lang13]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/containers/LanguageProvider/reducer.ts?at=d436dd1c24cde57170db56143b8b17e7fc820b23#13
[langs13]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/containers/LanguageProvider/sagas.ts?at=d436dd1c24cde57170db56143b8b17e7fc820b23#13
[routesidx]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/containers/Routes/index.tsx?at=d436dd1c24cde57170db56143b8b17e7fc820b23
[routes791]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/containers/Routes/index.tsx?at=d436dd1c24cde57170db56143b8b17e7fc820b23#791
[routes820]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/containers/Routes/index.tsx?at=d436dd1c24cde57170db56143b8b17e7fc820b23#820
[nonce]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/create-nonce.ts?at=d436dd1c24cde57170db56143b8b17e7fc820b23#9
[html7]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/oem/AxxonNet/app/index.html?at=d436dd1c24cde57170db56143b8b17e7fc820b23#7
[menu18]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/components/AppMenu/index.tsx?at=d436dd1c24cde57170db56143b8b17e7fc820b23#18
[menu22]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/components/AppMenu/index.tsx?at=d436dd1c24cde57170db56143b8b17e7fc820b23#22
[menu39]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/components/AppMenu/index.tsx?at=d436dd1c24cde57170db56143b8b17e7fc820b23#39
[routes]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/routes.tsx?at=d436dd1c24cde57170db56143b8b17e7fc820b23
[routes29]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/routes.tsx?at=d436dd1c24cde57170db56143b8b17e7fc820b23#29
[routes129]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/routes.tsx?at=d436dd1c24cde57170db56143b8b17e7fc820b23#129
[zain]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/oem/ZainTechBank/app/config/extraAppMenu.tsx?at=d436dd1c24cde57170db56143b8b17e7fc820b23
[extra]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/config/extraRoutes.tsx?at=d436dd1c24cde57170db56143b8b17e7fc820b23
[extraaxx]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/oem/AxxonNet/app/config/extraRoutes.tsx?at=d436dd1c24cde57170db56143b8b17e7fc820b23
[conf3]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/containers/Configurator/index.tsx?at=d436dd1c24cde57170db56143b8b17e7fc820b23#3
[perm]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/config/permissions.ts?at=d436dd1c24cde57170db56143b8b17e7fc820b23
[perm13]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/config/permissions.ts?at=d436dd1c24cde57170db56143b8b17e7fc820b23#13
[emb]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/components/EmbeddedInterface/index.tsx?at=d436dd1c24cde57170db56143b8b17e7fc820b23
[emb76]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/components/EmbeddedInterface/index.tsx?at=d436dd1c24cde57170db56143b8b17e7fc820b23#76
[emb102]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/components/EmbeddedInterface/index.tsx?at=d436dd1c24cde57170db56143b8b17e7fc820b23#102
[emb193]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/components/EmbeddedInterface/index.tsx?at=d436dd1c24cde57170db56143b8b17e7fc820b23#193
[wc33]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/containers/Webclient/index.tsx?at=d436dd1c24cde57170db56143b8b17e7fc820b23#32
[eiw]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/components/CamerasMap/EmbeddedInterfaceWrapper.tsx?at=d436dd1c24cde57170db56143b8b17e7fc820b23
[eiw102]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/components/CamerasMap/EmbeddedInterfaceWrapper.tsx?at=d436dd1c24cde57170db56143b8b17e7fc820b23#102
[eiw166]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/components/CamerasMap/EmbeddedInterfaceWrapper.tsx?at=d436dd1c24cde57170db56143b8b17e7fc820b23#166
[cap40]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/components/CustomAppPage/index.tsx?at=d436dd1c24cde57170db56143b8b17e7fc820b23#40
[capi]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/api/customApps.ts?at=d436dd1c24cde57170db56143b8b17e7fc820b23
[capredir]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/containers/Routes/redirects/RedirectCustomApps.tsx?at=d436dd1c24cde57170db56143b8b17e7fc820b23
[cap66]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/containers/UserCapabilities/constants.ts?at=d436dd1c24cde57170db56143b8b17e7fc820b23#66
[cap67]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/containers/UserCapabilities/constants.ts?at=d436dd1c24cde57170db56143b8b17e7fc820b23#67
[ucidx]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/containers/UserCapabilities/index.tsx?at=d436dd1c24cde57170db56143b8b17e7fc820b23
[ucs11]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/containers/UserCapabilities/sagas.ts?at=d436dd1c24cde57170db56143b8b17e7fc820b23#11
[caps7]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/utils/capabilities.ts?at=d436dd1c24cde57170db56143b8b17e7fc820b23#7
[caps33]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/utils/capabilities.ts?at=d436dd1c24cde57170db56143b8b17e7fc820b23#33
[caps55]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/utils/capabilities.ts?at=d436dd1c24cde57170db56143b8b17e7fc820b23#55
[authflow]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/api/auth-flow.ts?at=d436dd1c24cde57170db56143b8b17e7fc820b23
[sh6]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/utils/storageHelper.ts?at=d436dd1c24cde57170db56143b8b17e7fc820b23#6
[sh66]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/utils/storageHelper.ts?at=d436dd1c24cde57170db56143b8b17e7fc820b23#66
[sh137]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/utils/storageHelper.ts?at=d436dd1c24cde57170db56143b8b17e7fc820b23#137
[oidc]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/containers/DomaAIOidcCallback/sagas.ts?at=d436dd1c24cde57170db56143b8b17e7fc820b23
[au17]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/api/api-utils.ts?at=d436dd1c24cde57170db56143b8b17e7fc820b23#17
[au46]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/api/api-utils.ts?at=d436dd1c24cde57170db56143b8b17e7fc820b23#46
[rt14]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/containers/OAuthTokensRenewal/sagas.ts?at=d436dd1c24cde57170db56143b8b17e7fc820b23#14
[auth19]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/api/auth.ts?at=d436dd1c24cde57170db56143b8b17e7fc820b23#19
[app36]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/containers/App/index.tsx?at=d436dd1c24cde57170db56143b8b17e7fc820b23#36
[bs22]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/containers/BaseApp/sagas.ts?at=d436dd1c24cde57170db56143b8b17e7fc820b23#22
[rq]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/utils/request.ts?at=d436dd1c24cde57170db56143b8b17e7fc820b23
[rq94]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/utils/request.ts?at=d436dd1c24cde57170db56143b8b17e7fc820b23#94
[idle39]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/containers/IdleTime/index.tsx?at=d436dd1c24cde57170db56143b8b17e7fc820b23#39
[idles45]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/containers/IdleTime/sagas.ts?at=d436dd1c24cde57170db56143b8b17e7fc820b23#45
[me8]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/api/me.ts?at=d436dd1c24cde57170db56143b8b17e7fc820b23#8
[dt63]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/containers/Domains/types.ts?at=d436dd1c24cde57170db56143b8b17e7fc820b23#63
[dt88]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/containers/Domains/types.ts?at=d436dd1c24cde57170db56143b8b17e7fc820b23#93
[cs]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/api/configsync.ts?at=d436dd1c24cde57170db56143b8b17e7fc820b23
[map3]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/components/CamerasMap/Map.tsx?at=d436dd1c24cde57170db56143b8b17e7fc820b23#3
[map55]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/components/CamerasMap/Map.tsx?at=d436dd1c24cde57170db56143b8b17e7fc820b23#55
[term53]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/components/DevicesListPage/DeviceTerminal.tsx?at=d436dd1c24cde57170db56143b8b17e7fc820b23
[subs]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/components/DomainUserItem/SubscriptionForm.tsx?at=d436dd1c24cde57170db56143b8b17e7fc820b23
[fs19]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/hooks/useFullScreen.ts?at=d436dd1c24cde57170db56143b8b17e7fc820b23
