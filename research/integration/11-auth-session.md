# Вход, токены, сессия и вход в поток событий

Дата: 2026-10-28. Второй круг, тема 11.

Что читал (только чтение):

| Репозиторий | Снимок |
|---|---|
| PROJ/axxoncloudgo, ветка прав `epic/CLOUD-23284-perms-i18n` | `e51bd552b593db9fdedba16505808bde48b1db96` (основной) |
| PROJ/axxoncloudgo, `develop` | `0228c7a9b1acf8faa62aa1097d6ec085882e8cf3` (сравнение) |
| PROJ/axxoncloudgo, `feature/CLOUD-22056-epic-keycloak` | `f55e91d893ed2d6f463700d20cc3c67078f34595` |
| PROJ/axxoncloud-ui, `CLOUD-23284-epic-perms-catalog` | `83a04e587c90809e10c4efb4b5a57ce29a335174` (основной) |
| PROJ/axxoncloud-ui, `develop` | `d436dd1c24cde57170db56143b8b17e7fc820b23` (сравнение) |
| IT/axxoncloud-deploy (боевые конфиги ansible: env, nginx, haproxy) | `91d1e6d25f3e5ff4273fc1277bf109970a8fcaec` (ветка по умолчанию) |
| NEW/incident-manager-server, локально | `develop` `b743797` |
| IM (прототип), локально | `887f7db` (в `openapi.json`, `api.js`, README машины разницы с `d891125` нет) |

Обозначения: без пометки — факт со ссылкой; **Вывод:** — следует из фактов; **Предположение:** — не проверено. Секреты из env-файлов деплоя сюда не переносил.

## Коротко

1. **Refresh-токен одноразовый.** Обновление меняет его в строке сессии Postgres условием «старый refresh совпал». Второй запрос с тем же старым токеном получает 401, но сессия остаётся живой. Старые access-токены действуют до своего `exp`. Ветка прав и `develop` устроены одинаково.
2. **Сроки задаёт каждая установка отдельно.** По умолчанию access — 1 сутки, refresh — 1 месяц. Комментарий «15 минут / 2 недели» устарел. Основной прод `axxoncloud/prod`: 1 сутки и 1 месяц. Есть установки с 15 минутами (`selectel2/prod`).
3. **Внешнее SPA на `/im/` может само обновлять пару** запросом `POST /api/v3/ac-backend/auth/tokens`, где refresh-токен идёт в `Authorization`. Пара лежит в Web Storage, а не в cookie. Портал перечитывает хранилище на каждом цикле, поэтому запись из `/im/` подхватит. Событие `storage` и `BroadcastChannel` портал не использует.
4. **Гонка двух окон.** Если окна берут пару из одного `localStorage`, проигравший восстанавливается на следующем цикле. Если у окон разные копии (`sessionStorage` при входе DomaAI, токен в памяти), проигравший в итоге получает 401. Тогда портал выходит, и сессия завершается у всех.
5. **Тайм-аут бездействия работает только во фронте портала.** Срок задаётся глобально (env), у пользователя (`inactiveLogoutTTLMin`) и максимумом группы. Отключить его для роли нельзя. Главный риск: вкладка портала, открытая в фоне, сама выходит по таймеру. Этот выход завершает общую сессию и стирает токены, поэтому выбивает и оператора на `/im/`.
6. **Поток событий.** Рекомендую `fetch` + `ReadableStream` с заголовком `Authorization`. Токен в адресе плох: боевой nginx пишет в журнал всю строку запроса, а `arpserver` кэширует проверку до 4 часов. Своей cookie сессии облако не ставит.
7. **Шлюз в бою.** У haproxy `timeout client 50s`, у nginx `proxy_read_timeout 120s`. Буферизация в боевом nginx включена. Нужен отдельный `location` с `proxy_buffering off` и пустой комментарий в потоке не реже раза в 15–20 с.
8. **Keycloak** в ветке — только ещё один внешний вход (OIDC) и синхронизация блокировок. Облако по-прежнему выпускает свои HS256-токены, introspect остаётся. JWKS используется только для проверки id_token от Keycloak. Открытого PR в `develop` нет.

---

## 1. Refresh-токен: одноразовый или нет, где хранится, гонка, сроки

**Ответ.**

- **Как устроено.** Маршрут `POST /api/v3/ac-backend/auth/tokens` берёт refresh-токен из заголовка `Authorization` ([auth_handlers.go:1256–1266][v3-refresh]). Дальше `RenewTokenByRefreshToken` ([appservices/user/auth.go:2247][app-renew]):
  1. проверяет блокировку по IP;
  2. разбирает refresh-токен и проверяет, что сессия `(clientId, userId)` активна ([:2299][app-getuser]);
  3. в транзакции выпускает новую пару и заменяет сессию ([services/auth/service.go:710–723][svc-renew]).
- **Замена — условная.** `UPDATE user_session SET refresh_token=<новый>, expires_at=… WHERE client_id=$1 AND user_id=$2 AND refresh_token=<старый> AND expires_at > now()` ([session_service_queries.go:120–128][upd-sess]). Если строк 0, это `ErrNoSuchSession` → 401 ([service.go:723][svc-renew]). В `develop` то же самое ([develop :128][upd-sess-dev], [develop auth.go:2281][app-renew-dev]).
- **Тест облака подтверждает одноразовость.** Повторное обновление старым refresh — ошибка, а оба access-токена (старый и новый) остаются действительными ([auth_service_test.go:203–228][t-renew]). Новый вход с тем же `clientId` тоже делает старый refresh недействительным ([:236–260][t-relogin]).
- **Где хранится.**
  - Сессия — строка Postgres `user_session` на пару `(client_id, user_id)` с текущим refresh-токеном.
  - Проверка «сессия жива» кэшируется в памяти экземпляра backend на 60 с ([services/auth/session.go:47][sess-check]; memoizer 60 с — [service.go:267][svc-memo]).
  - Redis используется только ограничителем неудачных обновлений. Счёт идёт по IP клиента ([auth.go:2277–2295][app-limit]). Окно равно `AccessTokenTTL`, предел — 5000 неудач, блокировка — 5 минут ([config.go:168–170][cfg-limit], [auth_service.go:84, 127–133][svc-limit]).
- **Access-токен после ротации жив.** Проверка доступа сверяет только сессию по `clientId`, сам токен с сессией не сравнивается ([auth.go:2313–2323][app-resolve]). **Вывод:** поток событий, открытый со старым access-токеном, ротацию переживёт.

**Что будет, если два окна обновят пару одновременно.**

- Сервер. Оба запроса несут один и тот же старый refresh R0. Первый меняет строку. Второй ждёт блокировку строки, после неё условие `refresh_token = R0` уже ложно, и он получает 401 ([upd-sess]). Сессия при этом жива, новая пара у победителя.
- Портал. Обновление идёт через `fetchWithoutLogout`, поэтому 401 при обновлении не ведёт к выходу. Портал только показывает ошибку ([sagas.ts:16–28][ui-renew-saga], [api/auth.ts:17–34][ui-auth]). Через 20 с портал снова читает access и refresh из хранилища ([sagas.ts:30–43][ui-renew-saga]).
  - **Вывод:** если оба окна работают с одним `localStorage`, проигравший на следующем цикле возьмёт пару, которую записал победитель, и разлогина не будет. Останется только всплывающая ошибка.
- Если копии пары разные. Так бывает с `sessionStorage` в разных вкладках или когда клиент держит токен у себя в памяти. Проигравший тогда навсегда остаётся с устаревшим refresh.
  - **Вывод:** когда его access истечёт, любой обычный запрос получит 401. Портал выйдет ([request.ts:95–101][ui-401]). Выход вызывает API выхода и завершает сессию по `clientId` ([BaseApp/sagas.ts:42–47][ui-logout], [session.go:61][sess-finish]). Через ≤60 с кэша backend и ≤30 с кэша МИ выбит и победитель.
- Каждая проигранная гонка — +1 неудача в счётчике по IP. При общем NAT зала операторов счётчик у всех один, но 5000 за окно — далеко.

**Сроки.**

| Где | Access | Refresh |
|---|---|---|
| Умолчание в коде ([config.go:124–125][cfg-ttl]; `develop` [:130–131][cfg-ttl-dev]) | `P1D` | `P1M` (30 суток) |
| Комментарий в [model/auth/auth.go:63–65][model-ttl] | «currently 15 minutes» | «currently 2 weeks» — устарел |
| `tools/env/dev.env` ([:176, :181][devenv]) | `P1D` | `P1M` |
| `axxoncloud/prod` ([docker.env:16][dep-prod]) | `P1D` | не задан → `P1M` |
| `selectel2/prod` ([:16][dep-sel-a], [:26][dep-sel-r]) | `PT15M` | `P1D` |
| `safaricom/prod` ([:17][dep-saf-a], [:36][dep-saf-r]) | `P15M` | `P30M` |
| `bezeq/stage4` ([:18][dep-bz4-a], [:47][dep-bz4-r]) | `PT4H` | `PT12H` |
| прочие из поиска (`bezeq/stage3` `P7D`, `axxon/bridge2` `P2D`, `inaxsys/prod` `P24D`, большинство — `P1D`) | — | обычно не задан |

- Разбор срока: `P<n>M` до буквы `T` — это **месяцы**, считаются как 30 суток ([time_util.go:217–230][iso]).
  - **Вывод:** у `safaricom/prod` access живёт 15 месяцев, а refresh — 30 месяцев. Похоже на ошибку конфигурации (имели в виду минуты, `PT15M`), но это вопрос к людям.
- **Вывод:** клиент МИ не должен закладывать конкретный срок. Срок надо читать из `exp` токена и правило «обновлять заранее» строить от него.
- **Уверенность:** подтверждено кодом и конфигами деплоя. Какой заказчик МИ на какой установке — не знаю.

**Спросить у людей** (команда облака, backend):

1. Допустимо ли, что внешнее SPA на том же origin обновляет общую пару тем же запросом?
2. Будет ли «окно повтора» для старого refresh (несколько секунд считать R0 действительным и отдавать ту же новую пару)? Это сняло бы гонку окон.
3. `safaricom/prod`: `P15M`/`P30M` задуманы как месяцы?

## 2. Обновление пары из внешнего SPA; как это делает портал; DomaAI

**Ответ: да, может.**

- Запрос: `POST /api/v3/ac-backend/auth/tokens`, заголовок `Authorization: Bearer <refreshToken>`, тело не нужно. Ответ — `{accessToken, refreshToken}` ([api/auth.ts:17–34][ui-auth], [v3-refresh]).
- Маршрут `/api/v3/ac-backend/` у nginx уже есть ([nginx.anticonsul.conf:179][ngx-v3]).
- Refresh-токен лежит в Web Storage. Его читает любой скрипт того же origin: он не в cookie и не `HttpOnly` ([storageHelper.ts:66–80][ui-sh-store]).

Что нужно `/im/`, чтобы обновлять пару как портал:

1. **Выбрать хранилище так же, как портал.** Если в `sessionStorage` лежат оба ключа `accessToken` и `refreshToken`, берётся `sessionStorage`, иначе `localStorage` ([storageHelper.ts:136–141][ui-sh-mode]).
2. **Ключи те же.** Писать `accessToken` и `refreshToken`, оба сразу. `isSocialAuth` и `clientId` не трогать ([storageHelper.ts:5–13, 66–80][ui-sh-store]).
3. **Своего `clientId` не заводить** и не вызывать вход повторно. Новый вход с тем же `clientId` сделает пару портала недействительной ([t-relogin]). С другим `clientId` вход потребует от пользователя пройти его заново.
4. **Не вызывать API выхода при неудачном обновлении.** Выход завершит общую сессию и выбьет портал ([sess-finish]).

**Как портал обновляет токен** (ветка `83a04e5`; в `develop` файлы те же по размеру).

- Компонент `OAuthTokensRenewal` при старте приложения запускает сагу ([index.ts:28–36][ui-renew-idx]).
- Цикл саги ([sagas.ts:13–43][ui-renew-saga]):
  1. раз в 20 с (`SYNC_INTERVAL = 20e3`) читает `accessToken` из хранилища;
  2. если `willTokenExpireSoon` (до `exp` меньше `softLimit` = 7 мин — [other.ts:38][ui-other]; тест — [other.test.ts:28–43][ui-other-t]), закрывает «ворота» `tokenRenewalGate` — остальные запросы ждут;
  3. шлёт обновление;
  4. при успехе вызывает `storageHelper.storeTokens(...)`, при ошибке — `displayError` и `renewOAuthTokensError`, без выхода.
- Refresh-токен читается из хранилища в момент запроса ([api/auth.ts:18][ui-auth]), access — перед каждым API-запросом ([request.ts:243][ui-req-token]).
- Обработчика события `storage` и `BroadcastChannel` в портале нет (поиск по репозиторию). **Вывод:** синхронизации нет, но запись из `/im/` в то же хранилище портал увидит на следующем запросе или цикле.

**Вход через DomaAI OIDC.**

- После обратного вызова портал переключает хранилище на `sessionStorage` ([DomaAIOidcCallback/sagas.ts:27][ui-doma]). Это делает один OEM (ещё `oem/DomaAICordova`).
- `sessionStorage` свой у каждой вкладки.
  - **Вывод:** если пункт меню открывает `/im/` в той же вкладке (внешний маршрут, тот же origin), пара в `sessionStorage` сохранится, и `/im/` её найдёт. Для этого `/im/` нужно правило выбора хранилища из п. 1.
  - Если `/im/` открыт в новой вкладке по ссылке или вручную, `sessionStorage` пуст. Через `window.open` браузер копирует `sessionStorage` в новое окно, но это уже отдельная копия.
- **Вывод:** при DomaAI несколько окон (второй монитор оператора, вкладка портала рядом) расходятся после первой же ротации. Получается ситуация из п. 1 — разлогин всех.
  - Окна МИ между собой МИ может согласовать сам: `BroadcastChannel` и Web Locks работают между вкладками одного origin при любом хранилище.
  - Вкладку портала в режиме `sessionStorage` без правки портала согласовать нельзя.

**Уверенность:** подтверждено кодом. Как именно пункт меню МИ открывает страницу — в той же вкладке или в новой — смотрел первый круг ([06](06-axxoncloud-ui.md#как-подключаются-приложения-и-im)): внешний маршрут.

**Спросить у людей** (команда портала axxoncloud-ui):

1. Готовы ли слушать `storage` или `BroadcastChannel` и принимать новую пару от `/im/`? Для DomaAI без этого окна расходятся.
2. Нужен ли DomaAI именно `sessionStorage`, или можно перейти на `localStorage`?

## 3. Тайм-аут бездействия `inactiveLogoutTTLMin`

**Ответ: где задаётся.** Домен в этом не участвует, уровней три:

| Уровень | Где | По умолчанию |
|---|---|---|
| глобально, для всего портала | `AXXONCLOUD_CLOUDUI_AUTO_LOGOUT_TTL_MIN` ([config.go:388][cfg-idle]), отдаётся фронту в настройках ([description_handlers.go:79][idle-desc]) | 30 мин; `axxoncloud/prod` — 4320 (3 суток) ([docker.env:45][dep-prod-idle]); `inaxsys/prod` — 15 |
| глобально, на странице вебклиента VMS | `AXXONCLOUD_WEBCLIENT_AUTO_LOGOUT_TTL_MIN` ([config.go:387][cfg-idle]) | 15 мин |
| пользователь | `users.inactive_logout_ttl_min` ([user_model.go:83][user-ttl]). Меняет администратор и сам пользователь в профиле ([IdleTime/sagas.ts:59–79][ui-idle-saga]) | пусто |
| максимум группы пользователей | `user_group.max_inactive_logout_ttl_min` ([user_group.go:23][ug-ttl]). Значение пользователя выше максимума не сохраняется ([users.go:1034–1043][users-limit]). При переносе в группу значение пользователя обновляется (CLOUD-23274, [коммит 97e45bf][c23274]). Максимум приходит фронту как `maxLogoutTTLLimit` в `/me` ([users.go:1191, 1214][users-me]) | пусто |

**Можно ли отключить для роли или группы.** Нет.

- Фронт берёт значение пользователя. Если оно `0` или пусто, берётся глобальное ([IdleTime/selectors.ts:12–29][ui-idle-sel]).
- Выхода нет только при глобальном `0` — и тогда для всех.
- Для операторов остаётся поставить большое значение: максимум группе операторов и такое же значение пользователям, например длина смены плюс запас.
- Серверной проверки бездействия не нашёл: поиск по `InactiveLogoutTTLMin` в облаке находит только хранение и проверку лимита.

**Как портал считает активность.**

- Слушает `mousemove, keydown, wheel, mousedown, touchmove, touchstart` на своём `window` с троттлингом 5 с ([IdleTime/index.tsx:38–46, 84–94][ui-idle-idx]).
- Счётчик +1 раз в 60 с ([sagas.ts:25–43][ui-idle-saga]). Смена маршрута перезапускает цикл и обнуляет счётчик ([sagas.ts:82][ui-idle-saga]).
- За минуту до конца — предупреждение.
- Когда счётчик сравнялся с лимитом — `logoutUser` ([sagas.ts:45–52][ui-idle-saga]). Выход шлёт API выхода и стирает токены из хранилища ([BaseApp/sagas.ts:42–47][ui-logout]).

**Что будет с другим SPA на том же origin.**

- Код портала на `/im/` не загружен, таймера там нет.
- **Вывод (главный риск):** если у оператора в том же браузере открыта вкладка портала, её таймер идёт (оператор там мышью не двигает). Через лимит портал выходит:
  - сессия по общему `clientId` завершается на сервере ([sess-finish]);
  - токены удаляются из `localStorage`.
- `/im/` после этого получает 401 (≤60 с кэша backend, ≤30 с кэша МИ) и не находит токенов. Поток событий рвётся, оператор выбит.

**Уверенность:** подтверждено кодом; поведение фоновой вкладки — вывод из кода. Таймер на `delay(60 с)` в фоновой вкладке браузер замедляет, но не останавливает.

**Спросить у людей:**

- Продукт и администраторы: какое значение ставить группе операторов? Допустим ли для операторских установок глобальный `0`?
- Команда портала: может ли портал учитывать активность других вкладок origin — например, ключ `lastActivity` в `localStorage`, который пишет `/im/`? Или не выходить, пока жив такой ключ?

## 4. Вход в поток событий (SSE)

Что известно о сервере МИ:

- Сервер МИ берёт токен только из заголовка `Authorization` ([auth_middleware.go:113][ims-auth]) и проверяет его в облаке через `introspect-user-token` с кэшем 30 с ([client.go:90][im-introspect]).
- `http.Server` создан без `WriteTimeout` ([main.go:64–67][ims-main]), поэтому сам сервер долгий ответ не оборвёт.
- При остановке ждёт 10 с ([main.go:71][ims-main]). **Вывод:** открытые потоки надо закрывать сами (`RegisterOnShutdown`), иначе остановка будет ждать до тайм-аута.

### (а) `fetch` + `ReadableStream` с заголовком `Authorization`

- Тот же origin, тот же Bearer, что у остальных запросов. Серверу МИ ничего менять во входе не нужно ([ims-auth]).
- Токена нет ни в адресе, ни в журнале.
- Переподключение, заголовок `Last-Event-ID` и разбор `text/event-stream` клиент делает сам (~60 строк или готовая библиотека). `EventSource` не нужен.
- Боевой nginx слушает HTTP/2 ([nginx.conf.ctmpl:214–215][dep-ngx-srv]), haproxy объявляет `alpn h2` ([haproxy.cfg.ctmpl.j2][dep-hap]). **Вывод:** ограничение «6 соединений на origin» HTTP/1.1 для нескольких окон оператора не мешает.
- После ротации старый access-токен действует до `exp` (п. 1), поэтому поток не рвётся. Когда поток всё же оборвался, клиент открывает новый со свежим токеном.

### (б) Токен в адресе, как у `arpserver`

- **Как проверяет `arpserver`.**
  1. Берёт токен из `?authToken=`, иначе из `X-Cloud-Auth`, иначе из `Authorization` ([auth_checker.go:72–82][arp-tok]).
  2. Разбирает JWT **без проверки подписи** (`UnverifiedParseToken`) ([:39–55][arp-check]).
  3. Спрашивает backend о доступе к домену и кэширует ответ на **4 часа** по ключу `userID + domainID + md5(token)` ([:26][arp-new], [:170–180][arp-cache]).
  - **Вывод:** адрес с токеном после выхода пользователя или истечения токена открывает вебклиент до 4 часов, пока ответ в кэше.
- **Логируется ли адрес.** Да.
  - Боевой nginx пишет в `access.log` формат `axxoncloud-json` с полем `"request": "$request"`, то есть всю строку запроса с параметрами ([nginx.conf.ctmpl:55–74][dep-ngx-log]). `access_log off` стоит только у статики (`location /` — [:452][dep-ngx-root]).
  - haproxy в бою пишет `%r` (строку запроса) ([haproxy.cfg.ctmpl.j2:36][dep-hap]), но фронт 443 у него в режиме `tcp`. **Вывод:** для HTTPS строки запроса в журнале haproxy нет, есть в журнале nginx.
  - В локальном стеке формата нет, действует умолчание nginx (`combined`, со строкой запроса), плюс `error_log … debug` ([nginx.anticonsul.conf:17–24][ngx-head]).
- Плюс варианта: работает с обычным `EventSource`. Минус: access-токен живёт до суток (п. 1) и окажется в журналах и в истории сети. **Не рекомендую.**

### (в) Одноразовый билет

- Как работает: `POST /operator/stream-ticket` с Bearer возвращает `{ticket, expiresIn: 30}`, затем открывается `EventSource('/operator/stream?ticket=…')`. В журнал попадает одноразовый короткий код.
- Минус: `EventSource` при обрыве сам повторит тот же адрес с использованным билетом. Получит 401 и на этом закроется (на ответ не 200 он не переподключается). **Вывод:** своё переподключение (новый билет) всё равно писать, то есть главное удобство `EventSource` теряется.
- Минус: серверу МИ нужно хранилище билетов, общее для экземпляров (Redis или БД).
- Годится как запасной путь, если по какой-то причине нельзя `fetch`.

### (г) Cookie

- Постоянной cookie сессии облако не ставит.
  - Единственная cookie с токенами — передаточная при входе SAML VSaaS: `accessToken` и `refreshToken` на **10 секунд**, `Secure`, не `HttpOnly`, затем редирект на портал ([handler/rest/auth.go:509–511][rest-cookie]).
  - Ещё есть `okta_session_state` (30 с) и `oauth_session` сервера OAuth ([поиск `SetCookie`: auth_handlers.go:461, oauth/authorize.go:111][v3-okta-cookie]).
  - Портал токены в cookie не держит ([06](06-axxoncloud-ui.md#авторизация)).
- Свою cookie мог бы ставить сервер МИ: `POST /operator/stream-session` с Bearer → `Set-Cookie: im_stream=…; HttpOnly; Secure; SameSite=Strict; Path=/api/v1/im-backend/operator/stream`.
- Минус: срок cookie и её продление при ротации, хранение на сервере — по сути тот же билет из (в), только в cookie.

### Шлюз: тайм-ауты и что нужно для SSE

| Звено | Локальный стек (`axxoncloudgo`) | Бой (`axxoncloud-deploy`, шаблон `axxoncloud/common`) |
|---|---|---|
| haproxy, `defaults` | `timeout client 50000`, `server 50000`; `backend nginx-pool-http` — `timeout server 1m` ([haproxy.anticonsul.cfg:14–16, 56][hap-local]) | `timeout client 50s`, `server 300s`, `tunnel 1h`; у бэкендов nginx `timeout server 15m` ([haproxy.cfg.ctmpl.j2:38–41, 158, 168][dep-hap]) |
| nginx, ожидание ответа | по умолчанию 60 с | `proxy_read_timeout 120s` на весь `server` ([nginx.conf.ctmpl:221][dep-ngx-srv]) |
| nginx, буферизация | `proxy_buffering off` и `proxy_http_version 1.1` на весь `http` ([nginx.anticonsul.conf:30–31][ngx-head]) | в `http` не выключена → **включена по умолчанию**; выключают точечно (поток архива `…/time-on` — [:500–516][dep-ngx-timeon]) |
| WebSocket `arpserver` | отдельные `location ~ …/ws`, `…/events`, `…/webclient/ws`, `…/webclient/events` с `Upgrade`, `Connection "upgrade"`, `proxy_read_timeout 86400` и CORS ([nginx.anticonsul.conf:306–328][ngx-ws], [common-webclient-ws-proxy-pass.conf:5][ngx-ws-pp]) | то же по адресу `/<hostname arpserver>/<домен>_<n>/…`; `webclient/ws` — `proxy_read_timeout 300s` ([nginx.conf.ctmpl:541–547][dep-ngx-ws]); роль nginx — `86400` ([roles/nginx/files][dep-ngx-ws-pp]). Токен вебклиент передаёт в адресе (`authToken`) |

**Вывод: что нужно для SSE через шлюз.**

1. Отдельный `location /api/v1/im-backend/operator/stream` с настройками:
   - `proxy_pass` на сервер МИ;
   - `proxy_http_version 1.1`, `proxy_set_header Connection ''`;
   - `proxy_buffering off` (или ответ сервера МИ с заголовком `X-Accel-Buffering: no` — тогда хватит общего `location`);
   - `proxy_cache off`, без gzip;
   - `proxy_read_timeout` не меньше 60 с.
   
   Образец — `location …/time-on` ([dep-ngx-timeon]).
2. Сервер МИ шлёт пустой комментарий (`: ping`) **не реже раза в 15–20 с**. Тогда поток проходит `timeout client 50s` haproxy и `proxy_read_timeout 120s` nginx с запасом.
3. Заголовки ответа: `Content-Type: text/event-stream`, `Cache-Control: no-cache`, `X-Accel-Buffering: no`.
4. Сервер МИ закрывает поток, когда:
   - при повторной проверке токена (раз в 60 с, через тот же кэш introspect) сессия неактивна;
   - истёк `exp`.
   
   Клиент переподключается с новым токеном. Повторная проверка нужна потому, что выход в портале иначе не прервёт уже открытый поток.

**Уверенность:** конфиги шлюза и `arpserver` подтверждены. Что боевая установка заказчика МИ собрана из шаблона `axxoncloud/common` — **предположение**.

**Спросить у людей** (DevOps облака): какой шаблон и какие установки получат МИ? Кто и как добавит `location` для `/im/` и `/api/v1/im-backend/` (включая поток) в `ansible-hc/config/*/nginx/nginx.conf.ctmpl`? Журналы nginx уходят в Kibana — проверить, что токены в адресах туда не попадают (сейчас попадают от вебклиента).

## 5. Keycloak

**Ответ.**

- Ветка `feature/CLOUD-22056-epic-keycloak`, последний коммит `f55e91d` — слияние PR #2328 «CLOUD-23391 keycloak sync» (автор Mikhail Strunets, ~24.09.2026). До него PR #2316 «CLOUD-23390 oidc keycloak».
- **PR #2316.** Вход через Keycloak по OIDC: `GET /users/loginByKeycloak/auth` и `POST /users/loginByKeycloak/callback`.
  - Backend проверяет id_token от Keycloak по его JWKS (`/protocol/openid-connect/certs`) и nonce.
  - Затем находит или создаёт пользователя по `keycloak_id` (миграция 285) и вызывает **свой** `loginBySocialNetwork` — то есть выдаёт обычные облачные HS256-токены ([PR #2316][pr2316], файл `services/auth/keycloak.go`, `appservices/user/auth.go`).
  - Настройки: `AXXONCLOUD_KEYCLOAK_ENABLED`, `…_ISSUER`, `…_CLIENT_ID`, `…_CLIENT_SECRET`, `…_REQUIRE_VERIFIED_EMAIL`.
- **PR #2328.** Привязка `keycloak_id` к существующему пользователю по почте. Плюс фоновая задача `keycloakSyncJob`: пользователей, отключённых в Keycloak, она блокирует в облаке и вызывает `FinishAllSessions` ([PR #2328][pr2328]).
- **Выдача и проверка облачного токена не меняются**: те же секреты HS256, та же ротация refresh, introspect остаётся. JWKS — только для токенов Keycloak внутри backend.
- Открытых PR в репозитории `axxoncloudgo` по MCP нет — список открытых PR пуст, ветка в `develop` не влита.

**Вывод для МИ:** Keycloak добавит ещё один способ входа в портал, а для `/im/` ничего не меняет. Пара токенов в том же хранилище, обновление и introspect те же. Пользователь, отключённый в Keycloak, теряет сессии, и поток МИ должен это заметить при повторной проверке (п. 4).

**Уверенность:** подтверждено диффами PR. Планов «перевести облачные токены на Keycloak» в коде нет.

**Спросить у людей** (команда облака): когда ветка Keycloak войдёт в `develop`? Будет ли следующий этап, где access-токен выдаёт сам Keycloak (RS256 + JWKS) и introspect уходит?

## 6. Что поменять в прототипе (файлы не правил)

**`Specification/Workflow_machine/openapi.json`**

- [`components.securitySchemes.bearerAuth`, строки 2167–2173](../../Specification/Workflow_machine/openapi.json#L2167). В `description` вместо «из `localStorage.accessToken`» описать:
  - access-токен облака (JWT HS256);
  - хранилище — как у портала: `sessionStorage`, если там есть `accessToken` и `refreshToken`, иначе `localStorage`;
  - срок — по `exp`, он разный на установках;
  - обновление — `POST /api/v3/ac-backend/auth/tokens` с refresh-токеном в `Authorization`, вне этого контракта; refresh одноразовый.
- [`/operator/stream`, строки 1557–1590](../../Specification/Workflow_machine/openapi.json#L1557):
  - в `description` убрать опору на браузерный `EventSource`. Строка «без `event:` — потому что `EventSource` …» перестаёт быть причиной. Правило «без `event:`, тип в `data.type`» можно оставить;
  - добавить: «Клиент читает поток через `fetch` с заголовком `Authorization: Bearer` (как остальные операции). `Last-Event-ID` клиент шлёт заголовком сам при переподключении»;
  - добавить требования к серверу: пустой комментарий не реже раза в 15 с; заголовки `Cache-Control: no-cache` и `X-Accel-Buffering: no`; поток закрывается при неактивной сессии или истёкшем токене (повторная проверка не реже раза в минуту); клиент переподключается с новым токеном;
  - у операции явно записать `"security": [{"bearerAuth": []}]` (сейчас наследуется глобально — [строки 21–25](../../Specification/Workflow_machine/openapi.json#L21));
  - фразу «WebSocket допустим» дополнить: токен — первым сообщением после открытия, не в адресе.
- Тексты, которые советуют cookie или токен в адресе, исправить на «поток через `fetch` с `Authorization`»:
  - [README машины:451](../../Specification/Workflow_machine/README.md?plain=1#L451) (файл в CRLF — так и держать);
  - [BACKEND.md:80](../../Specification/Workflow_machine/BACKEND.md?plain=1#L80).

**`prototype/api.js`**

- `create(opts)` ([строка 10](../../prototype/api.js#L10)): новые параметры.
  - `opts.getToken()` — вернуть текущий access-токен (в облаке — из общего модуля входа, в тестах — постоянный);
  - `opts.refresh()` — обновить пару и вернуть, удалось ли;
  - `opts.onSessionEnded()` — показать «сессия завершена», не вызывая выхода.
- `raw` ([строки 15–28](../../prototype/api.js#L15)):
  - добавить `Authorization: Bearer <getToken()>`;
  - `credentials: "include"` заменить на `"same-origin"` (или `"omit"` для стенда на другом адресе);
  - на 401 — один раз `refresh()` и повтор запроса; не помогло — `onSessionEnded()`.
- `subscribe` ([строки 31–42](../../prototype/api.js#L31)): `new EventSource(…, {withCredentials: true})` заменить на цикл:
  - `fetch(base + "/operator/stream", {headers: {Authorization, Accept: "text/event-stream", "Last-Event-ID": last}, signal})`;
  - `res.body.getReader()` + `TextDecoder`;
  - разбор по пустой строке: `id:`, `data:`, `retry:`; строки с `:` — пропуск;
  - на обрыве — пауза с ростом от 1 до 30 с и повтор; перед повтором — свежий токен; на 401 — `refresh()`.
  
  Смысл `dropped` и `onReconnect` сохранить: после любого переподключения — `onReconnect()`, как сейчас ([app.js:4305](../../prototype/app.js#L4305)). Отписка — `AbortController.abort()`.
- Комментарий в шапке ([строки 5–6](../../prototype/api.js#L5)): «поток событий — по SSE через `fetch`; токен — заголовком `Authorization`».
- `prototype/app.js:612` ([ссылка](../../prototype/app.js#L612)) и `tests/api.html`: передать `getToken`. Для стенда — например `?token=` в адресе страницы теста (только для стенда).
- По правилам репозитория новый функционал идёт вместе с шагом самопроверки в `prototype/selftest.js`: разбор SSE из кусков, переподключение с `Last-Event-ID`, повтор после 401. После правки — самопроверка и тесты API.

## Рекомендация

**Поток событий:** вариант (а) — `fetch` + `ReadableStream` с `Authorization: Bearer`.

- Тот же вход, что у всех запросов МИ, и сервер МИ уже так проверяет токен ([ims-auth]).
- Токен не в адресе. Журнал боевого nginx пишет всю строку запроса ([dep-ngx-log]), а `arpserver` показывает, во что выливается токен в адресе: кэш проверки на 4 часа, разбор без проверки подписи ([arp-cache], [arp-check]).
- Ротация refresh старый access не отзывает, поэтому поток переживает обновление пары.
- Нужны настройки шлюза из п. 4: `proxy_buffering off` или `X-Accel-Buffering: no`, комментарий раз в 15–20 с, повторная проверка сессии на сервере.
- Запасной путь — одноразовый билет (в). Cookie и токен в адресе — нет.

**Обновление токена — общий модуль конфигуратора и оператора:**

1. **Хранилище — как у портала:** `sessionStorage`, если там пара, иначе `localStorage`. Читать при каждом запросе и ничего не кэшировать. `clientId` свой не заводить.
2. **Обновлять заранее.** Когда до `exp` меньше `min(7 мин, половина срока токена)` — правило портала, но безопасное и при `PT15M`. Проверять раз в 20 с и перед запросом.
3. **Одно обновление на все окна МИ:** `navigator.locks.request("axxon-cloud-token-refresh", …)`. Внутри блокировки сначала перечитать хранилище: если refresh уже сменился или access свежий, ничего не делать.
4. **После успеха** записать обе строки в то же хранилище. Разослать пару окнам МИ через `BroadcastChannel` — это обязательно для `sessionStorage` при DomaAI. Слушать событие `storage`.
5. **На 401 при обновлении** перечитать хранилище. Если refresh сменился, значит гонку выиграл кто-то другой (портал или другое окно) — взять его пару. Иначе сессия кончилась: экран «войдите заново» со ссылкой на портал, черновики ответов сохранить. **API выхода не вызывать** — он завершит общую сессию у портала ([sess-finish]).
6. **На 401 от API МИ** — одно обновление и повтор, дальше как в п. 5.
7. **Кнопка «Выход» в МИ** — только явная и с предупреждением, что выйдет и портал.
8. **Тайм-аут бездействия в МИ не делать.** Вместо этого добиться от облака одного из двух: большой `inactiveLogoutTTLMin` у группы операторов или учёт активности `/im/` порталом. Иначе фоновая вкладка портала выбьет оператора (п. 3).

Почему так: облако уже даёт всё нужное — общую пару в Web Storage и рабочий маршрут обновления. Ротация с условной заменой безопасна, если все окна берут пару из одного места и не обновляют одновременно. Пункты 3–5 закрывают это для окон МИ. Гонка с порталом остаётся редкой и самовосстанавливается: портал после неудачи перечитывает хранилище.

## Поправки к первому кругу

- **00-summary, «Токен через 15 минут» и п. «Коротко»; 06, «Авторизация».** Сказано: «access живёт 15 минут, у оператора на `/im/` остаётся 7–15 минут». На деле срок задаёт установка, по умолчанию `P1D`/`P1M` ([cfg-ttl]). На `axxoncloud/prod` — сутки ([dep-prod]), там у `/im/` без портала остаётся от 7 минут до суток. 7–15 минут — только на установках с `PT15M` (`selectel2/prod`). Комментарий «15 минут / 2 недели» в [model/auth/auth.go:63–65][model-ttl] устарел.
- **04, «Авторизация», «Сроки».** «Access — 15 минут, refresh — 2 недели» → умолчание 1 сутки и 1 месяц. «На частое обновление стоит ограничитель (Redis)» → считаются только **неудачные** обновления, по IP: 5000 за окно `AccessTokenTTL`, блок на 5 мин ([cfg-limit], [app-limit]).
- **00-summary, «Риски»** («две вкладки … если refresh одноразовый, выбьют друг друга»; 06, «Ограничения»). Одноразовость подтверждена. Но при общем `localStorage` проигравшая вкладка портала восстанавливается на следующем цикле — портал перечитывает хранилище ([ui-renew-saga]). Выбивает друг друга только при разных копиях пары (`sessionStorage`, токен в памяти) или когда клиент на 401 при обновлении сам вызывает выход.
- **00-summary, «Риски»** («в отдельном SPA тайм-аута нет вовсе»). Добавить: вкладка портала в фоне сама выйдет по таймеру и этим завершит общую сессию у `/im/` (п. 3). Отключить тайм-аут для роли нельзя, только числом у пользователя в пределах максимума группы.
- **00-summary, «Реальное время» и «Локальный стенд», п. 6** (haproxy 50 с / 1 мин, nginx `proxy_buffering off`). Это локальный стек. В бою ([dep-hap], [dep-ngx-srv]): haproxy `client 50s`, `server 300s`, у бэкендов nginx `15m`, `tunnel 1h`; nginx `proxy_read_timeout 120s`, буферизация **включена**.
- **04, «Устройства, видео, события»** («кэш до 4 часов»). Уточнение: ключ кэша включает `md5(token)`, а JWT разбирается без проверки подписи ([arp-cache], [arp-check]).
- **04, «Коротко»** («Боевых Helm-чартов в репозитории нет»). В `axxoncloudgo` их действительно нет, но боевые конфиги есть в `IT/axxoncloud-deploy` (`ansible-hc/config/<заказчик>/…`: env, nginx, haproxy) и Helm в `IT/k3s-test`.

## Что осталось спросить у людей

| Кому | Вопрос |
|---|---|
| Облако, backend | Можно ли внешнему SPA на `/im/` обновлять общую пару? Планируется ли «окно повтора» для старого refresh? Какой `AccessTokenTTL` на установках, где будет МИ? `safaricom/prod` `P15M`/`P30M` — это месяцы намеренно? |
| Облако, портал | Слушать `storage`/`BroadcastChannel` и принимать пару от `/im/`? Учитывать активность `/im/` в таймере бездействия? Для DomaAI — можно ли уйти с `sessionStorage`? |
| Продукт, администраторы | Значение `inactiveLogoutTTLMin` / максимум группы для операторов; допустим ли глобальный `0`. |
| DevOps облака | Шаблон nginx/haproxy для установок с МИ; `location` для `/im/` и `/api/v1/im-backend/` с потоком; журналы nginx и токены в адресах (вебклиент уже пишет их в журнал). |
| Облако, Keycloak | Когда ветка войдёт в `develop`; будет ли этап, где токены выдаёт Keycloak (JWKS вместо introspect). |

<!-- Ссылки -->
[v3-refresh]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/handler/v3/auth_handlers.go?at=e51bd552b593db9fdedba16505808bde48b1db96#1256
[v3-okta-cookie]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/handler/v3/auth_handlers.go?at=e51bd552b593db9fdedba16505808bde48b1db96#461
[app-renew]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/appservices/user/auth.go?at=e51bd552b593db9fdedba16505808bde48b1db96#2247
[app-getuser]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/appservices/user/auth.go?at=e51bd552b593db9fdedba16505808bde48b1db96#2299
[app-limit]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/appservices/user/auth.go?at=e51bd552b593db9fdedba16505808bde48b1db96#2277
[app-resolve]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/appservices/user/auth.go?at=e51bd552b593db9fdedba16505808bde48b1db96#2313
[app-renew-dev]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/appservices/user/auth.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#2281
[svc-renew]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/services/auth/service.go?at=e51bd552b593db9fdedba16505808bde48b1db96#710
[svc-memo]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/services/auth/service.go?at=e51bd552b593db9fdedba16505808bde48b1db96#267
[sess-check]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/services/auth/session.go?at=e51bd552b593db9fdedba16505808bde48b1db96#47
[sess-finish]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/services/auth/session.go?at=e51bd552b593db9fdedba16505808bde48b1db96#61
[upd-sess]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/store/postgres/session_service_queries.go?at=e51bd552b593db9fdedba16505808bde48b1db96#120
[upd-sess-dev]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/store/postgres/session_service_queries.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#128
[t-renew]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/service/test/auth_service_test.go?at=e51bd552b593db9fdedba16505808bde48b1db96#203
[t-relogin]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/service/test/auth_service_test.go?at=e51bd552b593db9fdedba16505808bde48b1db96#236
[svc-limit]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/service/auth/auth_service.go?at=e51bd552b593db9fdedba16505808bde48b1db96#84
[cfg-ttl]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/util/config/config.go?at=e51bd552b593db9fdedba16505808bde48b1db96#124
[cfg-ttl-dev]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/util/config/config.go?at=0228c7a9b1acf8faa62aa1097d6ec085882e8cf3#130
[cfg-limit]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/util/config/config.go?at=e51bd552b593db9fdedba16505808bde48b1db96#168
[cfg-idle]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/util/config/config.go?at=e51bd552b593db9fdedba16505808bde48b1db96#387
[idle-desc]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/handler/v3/description_handlers.go?at=e51bd552b593db9fdedba16505808bde48b1db96#79
[model-ttl]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/model/auth/auth.go?at=e51bd552b593db9fdedba16505808bde48b1db96#63
[devenv]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/tools/env/dev.env?at=e51bd552b593db9fdedba16505808bde48b1db96#176
[iso]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/util/time_util.go?at=e51bd552b593db9fdedba16505808bde48b1db96#217
[user-ttl]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/model/user_model.go?at=e51bd552b593db9fdedba16505808bde48b1db96#83
[ug-ttl]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/model/user_group.go?at=e51bd552b593db9fdedba16505808bde48b1db96#23
[users-limit]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/appservices/user/users.go?at=e51bd552b593db9fdedba16505808bde48b1db96#1034
[users-me]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/appservices/user/users.go?at=e51bd552b593db9fdedba16505808bde48b1db96#1191
[c23274]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/commits/97e45bf3d2c2396ebca3ce9f16d4624d78101eda
[rest-cookie]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/handler/rest/auth.go?at=e51bd552b593db9fdedba16505808bde48b1db96#509
[arp-new]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/axxonrp/server/auth_checker.go?at=e51bd552b593db9fdedba16505808bde48b1db96#26
[arp-check]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/axxonrp/server/auth_checker.go?at=e51bd552b593db9fdedba16505808bde48b1db96#39
[arp-tok]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/axxonrp/server/auth_checker.go?at=e51bd552b593db9fdedba16505808bde48b1db96#72
[arp-cache]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/axxonrp/server/auth_checker.go?at=e51bd552b593db9fdedba16505808bde48b1db96#170
[ngx-head]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/tools/docker/nginx.anticonsul.conf?at=e51bd552b593db9fdedba16505808bde48b1db96#17
[ngx-v3]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/tools/docker/nginx.anticonsul.conf?at=e51bd552b593db9fdedba16505808bde48b1db96#179
[ngx-ws]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/tools/docker/nginx.anticonsul.conf?at=e51bd552b593db9fdedba16505808bde48b1db96#306
[ngx-ws-pp]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/tools/docker/common-webclient-ws-proxy-pass.conf?at=e51bd552b593db9fdedba16505808bde48b1db96#5
[hap-local]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/browse/tools/docker/haproxy.anticonsul.cfg?at=e51bd552b593db9fdedba16505808bde48b1db96#14
[pr2316]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/pull-requests/2316/diff
[pr2328]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloudgo/pull-requests/2328/diff
[ui-renew-idx]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/containers/OAuthTokensRenewal/index.ts?at=83a04e587c90809e10c4efb4b5a57ce29a335174#28
[ui-renew-saga]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/containers/OAuthTokensRenewal/sagas.ts?at=83a04e587c90809e10c4efb4b5a57ce29a335174#13
[ui-auth]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/api/auth.ts?at=83a04e587c90809e10c4efb4b5a57ce29a335174#17
[ui-other]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/utils/other.ts?at=83a04e587c90809e10c4efb4b5a57ce29a335174#38
[ui-other-t]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/utils/other.test.ts?at=83a04e587c90809e10c4efb4b5a57ce29a335174#28
[ui-401]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/utils/request.ts?at=83a04e587c90809e10c4efb4b5a57ce29a335174#95
[ui-req-token]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/utils/request.ts?at=83a04e587c90809e10c4efb4b5a57ce29a335174#243
[ui-sh-store]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/utils/storageHelper.ts?at=83a04e587c90809e10c4efb4b5a57ce29a335174#5
[ui-sh-mode]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/utils/storageHelper.ts?at=83a04e587c90809e10c4efb4b5a57ce29a335174#136
[ui-doma]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/containers/DomaAIOidcCallback/sagas.ts?at=83a04e587c90809e10c4efb4b5a57ce29a335174#27
[ui-logout]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/containers/BaseApp/sagas.ts?at=83a04e587c90809e10c4efb4b5a57ce29a335174#42
[ui-idle-idx]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/containers/IdleTime/index.tsx?at=83a04e587c90809e10c4efb4b5a57ce29a335174#38
[ui-idle-saga]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/containers/IdleTime/sagas.ts?at=83a04e587c90809e10c4efb4b5a57ce29a335174#25
[ui-idle-sel]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/axxoncloud-ui/browse/app/containers/IdleTime/selectors.ts?at=83a04e587c90809e10c4efb4b5a57ce29a335174#12
[dep-prod]: https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/ansible-hc/config/axxoncloud/prod/docker/docker.env?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec#16
[dep-prod-idle]: https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/ansible-hc/config/axxoncloud/prod/docker/docker.env?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec#45
[dep-sel-a]: https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/ansible-hc/config/selectel2/prod/docker/docker.env?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec#16
[dep-sel-r]: https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/ansible-hc/config/selectel2/prod/docker/docker.env?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec#26
[dep-saf-a]: https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/ansible-hc/config/safaricom/prod/docker/docker.env?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec#17
[dep-saf-r]: https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/ansible-hc/config/safaricom/prod/docker/docker.env?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec#36
[dep-bz4-a]: https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/ansible-hc/config/bezeq/stage4/docker/docker.env?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec#18
[dep-bz4-r]: https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/ansible-hc/config/bezeq/stage4/docker/docker.env?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec#47
[dep-hap]: https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/ansible-hc/roles/haproxy/templates/haproxy.cfg.ctmpl.j2?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec#36
[dep-ngx-log]: https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/ansible-hc/config/axxoncloud/common/nginx/nginx.conf.ctmpl?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec#55
[dep-ngx-srv]: https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/ansible-hc/config/axxoncloud/common/nginx/nginx.conf.ctmpl?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec#214
[dep-ngx-root]: https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/ansible-hc/config/axxoncloud/common/nginx/nginx.conf.ctmpl?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec#444
[dep-ngx-timeon]: https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/ansible-hc/config/axxoncloud/common/nginx/nginx.conf.ctmpl?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec#500
[dep-ngx-ws]: https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/ansible-hc/config/axxoncloud/common/nginx/nginx.conf.ctmpl?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec#541
[dep-ngx-ws-pp]: https://src.axxonsoft.dev/bitbucket/projects/IT/repos/axxoncloud-deploy/browse/ansible-hc/roles/nginx/files/common-webclient-ws-proxy-pass.conf?at=91d1e6d25f3e5ff4273fc1277bf109970a8fcaec#5
[ims-auth]: https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/im/handler/v1/auth_middleware.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#113
[ims-main]: https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/cmd/im/main.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#64
[im-introspect]: https://src.axxonsoft.dev/bitbucket/projects/NEW/repos/incident-manager-server/browse/internal/externalclient/cloud/client.go?at=b743797a38daeb3beaa44ef901b26c3ce924290f#90
