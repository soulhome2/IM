# Этап 8: точка входа оператора в конфигураторе — план работ

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `https://axxonnet.test/dev-login.html?to=/im/operator/` открывает пустое место оператора: вход, права, токен и один вызов API доказаны, токен обновляется сам и одно обновление идёт на все окна, а пункт меню `/im/` по правам ведёт к оператору или в конфигуратор.

**Architecture:** В том же репозитории и том же архиве появляется вторая страница Vite `operator/index.html` с кодом в `src/operator/`. Общий клиент `src/shared/api/` (`tokens.ts` — пара токенов и одно обновление, `http.ts` — `apiFetch`) заменяет свои `fetch` конфигуратора и служит оператору. Оператор говорит с API через `OperatorTransport`: настоящий по HTTP или, только в разработке, встроенный сервер прототипа. Проигрыватели шагов переезжают из `features/preview` в `features/step-player`.

**Tech Stack:** React 19, TypeScript, Vite 8 (rolldown), Vitest 4, jsdom, Testing Library, MUI 9, zod 4, i18next, puppeteer-core (только `~/Work/stand/ui-check`).

**Spec:** [40-plan.md](40-plan.md), этапы 8 и 9, строка «Два потока работ», решения 3 и 6; [20-decisions.md](20-decisions.md), п. 3.1 и 3.3; [11-auth-session.md](11-auth-session.md), п. 1–3 и «Рекомендация»; [15-deploy-configurator.md](15-deploy-configurator.md), п. 2, 4, 5; [13-cloud-ui-menu-video.md](13-cloud-ui-menu-video.md), п. 1; [10-permissions.md](10-permissions.md), дерево `/me`; [30-local-stand.md](30-local-stand.md), шаги 2 и 4; `Specification/Workflow_machine/FRONTEND.md`, «Главное», «Что не переносится», «Как говорить с бэкендом»; контракт `openapi.json`, `getOperatorSession`, `OperatorSession`, `Problem`.

---

## Размер

Этап был оценён в M, план подтверждает: 9 задач, 8 коммитов конфигуратора и 1 коммит IM. Новых зависимостей нет. Самая рискованная часть — Task 1 и Task 2, самая скучная — Task 3 (38 вызовов `fetch`).

Этап идёт параллельно с этапами сервера и от незаконченного там не зависит: ему нужны только контракт, уже рабочий `GET /operator/session` и встроенный сервер прототипа.

## Критерий готовности

Критерий `40-plan.md`: `dev-login.html?to=/im/operator/` открывает пустое место оператора, токен обновляется сам, вход держится дольше срока access-токена.

| Уровень | Что доказывает | Где | От чего зависит |
|---|---|---|---|
| **А** | токены, гонки окон, 401, права, развилка, страницы, состояния | Vitest, `tsc` без новых ошибок, `eslint`, `vite build`, Task 1–8 | ни от чего |
| **Б** | вся цепочка клиента на ответах по контракту, без облака и сервера МИ | `?api=embedded`, случай 5 `check-operator-entry.mjs` | свой стенд: шлюз, Vite, копия прототипа |
| **В** | настоящий токен облака: вход, права `/me`, обновление заранее, 401, два окна, конец сессии, развилка | `check-operator-entry.mjs`, остальные случаи | свой стенд: облако, Vite |
| **Г** | `GET /operator/session` настоящего сервера МИ отвечает 200 | случай 4 того же скрипта | сервер МИ запущен кем-то другим, иначе `SKIP` |

Что будет сказано честно:

- Уровень Г, скорее всего, даст `SKIP`: сервер МИ на стенде лежит и этот этап его не поднимает (решение 137). Тогда доказано другое: запрос ушёл через шлюз с настоящим свежим токеном, шлюз ответил 502, страница показала «Сервер МИ недоступен» и не сочла это концом сессии. Ответ 200 проверен на встроенном сервере.
- «Вход держится дольше срока access-токена» буквально не ждали: срок на стенде по умолчанию сутки (решение 138). Проверено подменой короткого `exp` в браузере: клиент сам идёт в облако и получает настоящую новую пару.
- Разные пользователи на стенде не проверяются: пользователей не заводим. Развилка проверена подменой ответа `/me` в браузере и тестами.

Этап готов, когда: уровни А и В зелёные, уровень Б зелёный, у уровня Г итог `OK` или честный `SKIP`, задачи 1–9 закрыты, `30-local-stand.md` и `40-plan.md` обновлены.

## Global Constraints

- Весь код этапа — `~/Work/incident-manager`, ветка `feature/im_operator`, план сверен с `1fcfa25`. IM: `/mnt/hgfs/VmWareShared/soul2home/IM`, ветка `feature/im_operator`, только документы в Task 9.
- `~/Work/incident-manager-server` не трогаем, даже не собираем. База `im-test-db` и база стенда `imdb` не используются. `run-im-server.sh` не запускаем: он собирает незаконченное рабочее дерево и применяет миграции. Если сервер МИ поднял кто-то другой, случай 4 Task 9 вызовет его, а сервер сам пишет в свою базу на каждый запрос (решение 137); это единственное касание `imdb`, и сервер поднят не нами.
- `~/Work/axxoncloudgo` не менять. Шлюз меняем только на запущенном стенде, через `~/Work/stand/apply-nginx-dev.sh`. `sync-im-proto.sh` пишет в каталог `tools/compose/ui/im-proto/`, он в `.gitignore` облака и уже числится во временном на стенде.
- Этот проект сам ничего не пишет в `ac_db`: ни SQL, ни `ensure-dev-login.sh`, ни `grant-im-permissions.sh`, ни `PATCH /roles/global`. Пользователей облака не создаём. Вход через облако разрешён: обычный вход и обновление токена в Task 9 сменяют токены и меняют `user_session` руками самого облака, ровно как каждая проверка стенда и `dev-login.html`.
- Вход и токены не переделываем: берём то, что облако даёт на стенде. Экрана входа нет, свой `clientId` не заводим, повторный вход не вызываем, `POST /users/logout` не вызываем никогда.
- Своего тайм-аута бездействия нет ни в каком виде. AxxonData вне этапа.
- Только локально, `git push` никогда. Каждая задача — один коммит: файл `.git/COMMIT_MSG_STAGE8`, первая строка начинается с `Этап 8: `, по-русски и простыми словами, последняя строка `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`, команда `git commit -q -F .git/COMMIT_MSG_STAGE8`.
- **Хук.** `.husky/pre-commit` гоняет `eslint . --fix` и `prettier --write .` по всему репозиторию, поэтому коммит идёт долго и правит чужие файлы. На `1fcfa25` не отформатированы четыре файла, хук тронет их при каждом коммите: `src/app/redirectToCloud.ts`, `src/features/role-assignments/api/imBackendRoleAssignments.ts`, `src/features/role-assignments/api/imBackendRoleAssignments.test.ts`, `vite.config.ts`. После каждого коммита `git status --short`: чужие правки хука вернуть через `git restore <файл>`, в коммит их не включать. Задачи 3, 5 и 7 сами правят по одному из этих файлов, шум форматирования в их диффе ожидаем. Правки хука в файлах из `git mv` в коммит не попадают: `.husky/pre-commit` берёт `--diff-filter=ACM`, без `R`. Поэтому в Task 4 и Task 8 после коммита `git add` своих файлов и `git commit -q --amend --no-edit`, а не `git restore`. Хук не обходить.
- Команды конфигуратора идут из `cd ~/Work/incident-manager`. Один файл: `npx vitest run <путь>`. Всё: `npm run test:run`, `npm run lint`, `npm run build`. `npx tsc -p tsconfig.app.json` — всегда отдельной командой, не в цепочке `&&`: он красный, и цепочка на нём оборвётся молча. Каталог `dist` в `.gitignore`.
- **База `tsc` красная.** На `1fcfa25` код выхода 2, две ошибки: `src/features/role-assignments/components/RoleUserGroupsPage.test.tsx:117` и `:125`, `toHaveAttribute`. Причина: `tests/setup.ts:3` подключает типы jest-dom, а `tsconfig.app.json:29` включает только `src` и `oem`. Чужое, не чинить. Ожидание в каждой задаче: те же две ошибки, новых нет. Матчеры jest-dom (`toHaveAttribute`, `toBeInTheDocument`) не использовать: `getAttribute`, `not.toBeNull`, как `providers.test.tsx`. Иначе Vitest зелёный, а у `tsc` новые ошибки.
- Вне проверки типов остаются `tools/operatorDevRoute.ts`, `tests/entry-no-loop.test.ts`, `vite.config.ts`; `tools/` ещё и вне ESLint (`tsconfig.app.json:29`, `eslint.config.js:18`). Принято: их покрывает Vitest, опечатка типа всплывёт только в тесте.
- Импорты через `@/`. Комментарии и имена тестов — по-английски, как в коде конфигуратора. Документы IM — по-русски.
- Каждая задача, что меняет структуру, поведение или маршруты, правит `PROJECT.md`: этого требует `AGENTS.md`.
- `graphify-out` в конфигураторе нет, `graphify update .` не нужен.
- Правки только через Edit и Write, без здесь-документов и `sed -i`. Временные файлы — в scratchpad.
- Скрипты стенда вне git: перед правкой копия `*.before-8`. `.pass` и `.env` не читать, пароли в отчёты не печатать.
- Журнал работы: `.superpowers/sdd/58-plan-stage8/progress.md` в IM. Сообщение коммита IM: `.superpowers/sdd/58-plan-stage8/commit-msg.txt`.
- Рабочее дерево IM делится с потоком сервера. В Task 9 файл перечитать прямо перед правкой, `git add` только своих трёх файлов; `session-prompts-2026-10-28.md` не трогать.

**Решения пользователя (обязательны):** этап идёт параллельно с сервером. Вход и токены отложены. Экраны — отдельный план этапа 9. ONE PSIM — тема экранов этапа 9. Прав 14, `manage` не надмножество операторских (решение 3 плана 40).

## Review Focus

1. **Часы пульта спешат на сутки.** Любой токен кажется истекающим. Ждём, что обновление не пойдёт на каждый запрос, а страница работает. Тест — Task 2, `does not rotate on every request when the clock runs ahead`.
2. **Облако молчит, а срок подходит.** Ждём, что запросы уходят со старым ещё живым токеном, не стоят по 8 с каждый и сессия не считается законченной. Тест — Task 2, `keeps working on the old token while the cloud is down`.
3. **Шлюз отдаёт HTML вместо JSON.** Сервер МИ лежит, nginx отвечает 502 страницей. Ждём «Сервер МИ недоступен», а не падение на разборе и не «сессия завершена». Тест — Task 6, `reports a gateway html error as a plain status`.
4. **Портал или другое окно сменили пару в середине обновления.** Наш запрос получил 401, хотя сессия жива. Ждём, что оператор останется внутри. Тест — Task 1, `treats 401 as a lost race when storage already changed`.
5. **Петля переходов между `/im/` и `/im/operator/`.** Ждём, что ни один набор прав не гоняет браузер по кругу, в том числе под Vite, где `redirectToCloud` ничего не делает. Тест — Task 7, `never sends a user back and forth`.

---

## Решения этого плана (обязательны для задач)

*Вторая точка входа*

- **119.** Страница — `operator/index.html` в корне репозитория, код — `src/operator/`. Вход в сборке — `build.rolldownOptions.input: { main: 'index.html', operator: 'operator/index.html' }`. Почему: в Vite 8 `rollupOptions` помечен устаревшим, а исследование писало как раз о нём. `base: '/im/'` не меняется: страница ляжет в `dist/operator/index.html`, чанки — в `/im/assets/`, тот же архив и тот же `Makefile`. Предполётная проверка подтвердила это только чтением исходника Vite, поэтому первый шаг Task 5 смотрит на настоящую сборку.
- **120.** Роутера в этапе 8 нет. Почему: на пустой странице нечего маршрутизировать, а `declare module '@tanstack/react-router' { interface Register }` в `src/app/router.tsx` на весь проект привязывает типы к роутеру конфигуратора, и второй роутер в том же `tsconfig` надо проектировать вместе с экранами. Это передача этапу 9.
- **121.** Глубокие ссылки под Vite решает чистая функция `operatorDevRoute(url)` в `tools/operatorDevRoute.ts` и плагин в `vite.config.ts` рядом с `dev-root-not-spa`. Почему: `htmlFallbackMiddleware` Vite на `/operator/incidents/42` отдаёт корневой `/index.html`, то есть конфигуратор. Свой файл — чтобы проверить тестом без запуска Vite.
- **122.** Шлюз стенда получает отдельный `location /im/operator/` с тем же адресом Vite. Честно: на стенде блок `/im/` и так ведёт туда же. Отдельный блок нужен по этапу 8 плана 40, он повторяет форму боевого конфига и даёт 301 с `/im/operator` на `/im/operator/` (особый случай `proxy_pass` при префиксе со слэшем). Поэтому плагин из решения 121 адрес без слэша не обрабатывает. В блоке обязателен `absolute_redirect off;`: по конфигам `port_in_redirect` и `absolute_redirect` не заданы, nginx за haproxy соберёт `Location` из своего порта, `http://axxonnet.test:8082/im/operator/`, то есть чужой незащищённый origin с пустым `localStorage`, а порт 8081 для HTTP/1.1 на машине вообще не слушается. С этой строкой `Location` относительный. Вывод сделан из конфигов, поэтому первый шаг Task 9 смотрит настоящий ответ на `/im`. Запасной путь: `location = /im/operator { absolute_redirect off; return 301 /im/operator/$is_args$args; }`.

*Токены*

- **123.** Пара читается на каждый запрос и в памяти не хранится. Хранилище как у портала: `sessionStorage`, если там оба ключа, иначе `localStorage`; новая пара пишется туда же, откуда прочитана. Почему: портал меняет пару сам, копия в памяти после первой ротации устаревает и выбивает окно.
- **124.** «Обновить заранее» — когда до `exp` осталось не больше `min(7 мин, (exp − iat) / 2)`. Нет `iat` — 7 минут. Нет `exp` или токен не разбирается — заранее не обновляем, работает ветка 401. Почему: сроки разные на установках, правило из 11-auth, облако кладёт `iat` в токен (`services/auth/service.go`).
- **125.** Одно обновление на все окна — `navigator.locks.request('axxon-cloud-token-refresh', …)`, внутри замка хранилище перечитывается. В окне дополнительно один общий промис на все параллельные запросы. Нет `navigator.locks` — обновляем без межоконной защиты: так бывает только вне защищённого контекста.
- **126.** Исход обновления — `'ok' | 'ended' | 'failed'`. `ok`: в хранилище новая пара, наша или чужая. `ended`: нет refresh-токена; либо срок `exp` самого refresh-токена прошёл, тогда запроса нет; либо облако ответило 401, и refresh в хранилище не сменился и после паузы 400 мс. `failed`: сеть, тайм-аут, 5xx, 200 без пары; сессия, возможно, жива, хранилище не трогаем. Почему: облако отвечает 401 только в двух случаях: сессия неактивна (`services/auth/session.go:48-59`) и refresh уже использован при живой сессии (`services/auth/service.go:725`). На мусорный и просроченный refresh оно отвечает 500: ошибка `ParseRefreshToken` не обёрнута (`service.go:642-646`), неопознанное становится 500 (`util/errorsutil/httperror/error.go:129`). Поэтому просрочку клиент узнаёт сам, иначе вернувшийся после срока refresh оператор навсегда видел бы «Облако не отвечает». Цена: спешащие часы на установке с коротким refresh дадут ложный `ended`, но только в ветке 401, решение 129. Пауза 400 мс — портал мог выиграть гонку, но ещё не записать пару (`OAuthTokensRenewal/sagas.ts:16-28`); ветка 401 длиннее на доли секунды. Неполный ответ не должен затереть пару. Мусорный refresh на стенде отдельно не проверяем: ветку 500 закрывает модульный тест, а случай 9 идёт по настоящему отработавшему refresh.
- **127.** Тайм-аут запроса обновления — 8 с, через `AbortSignal.timeout`. Почему: зависший запрос держал бы замок всех окон, а `prepareSession` сдаётся через 10 с, и ему должно хватить времени узнать об исходе.
- **128.** После попытки обновить заранее 60 с новых попыток заранее нет — при любом исходе, если токен всё ещё выглядит истекающим. Почему: иначе спешащие часы ротируют пару на каждый запрос, а лежащее облако задерживает каждый запрос на 8 с. Ветку 401 это не ограничивает.
- **129.** Неудача обновления заранее сессию не заканчивает, даже `ended`: access-токен ещё жив, конец сессии доказывает только 401 на настоящем запросе.
- **130.** `apiFetch` возвращает обычный `Response`, в том числе 401. На 401: окно видит, что access в хранилище уже другой, — сразу один повтор; иначе обновление и один повтор. Второй 401 — конец сессии. Оговорка: сервер МИ отдаёт 401 на любую ошибку входа, включая сбой обращения в облако (`internal/im/handler/operator/auth.go:18-26`), так что второй 401 от него не всегда конец сессии. Для этапа 8 это принято: такой вызов один, цена — ложный экран. Запись идёт в передачу этапу 9. Почему: конфигуратор продолжает читать `res.ok`, и правка его вызовов механическая. `fetch` вызывается как глобальный в момент запроса: тесты подменяют его через `vi.stubGlobal`.
- **131.** Конфигуратор получает обновление и повтор, но новых экранов и переходов не получает. При конце сессии он ведёт себя как сейчас: ошибка запроса. Почему: автоматический уход с редактора сценария потерял бы несохранённую работу.
- **132.** `startTokenKeeper` раз в 20 с сначала проверяет `isSessionEnded()` и при конце сессии отмечает его, затем вызывает обновление заранее. Запускается только в месте оператора и только в режиме `server`. Активность пользователя не считает. Проверка нужна потому, что портал при выходе стирает токены, а на пустой странице запросов нет и `onSessionEnded` иначе не сработает. Почему: критерий требует обновления без запросов на пустой странице; у конфигуратора запросы сами проверяют срок, фоновый цикл ему не нужен.

*Права и развилка*

- **133.** `readImAccess(capabilities)`: `configurator` — есть действие `manage` у корневого ресурса `""` пространства `incident_manager`; `operator` — есть любое другое действие в этом пространстве. Списка из 13 прав в клиенте нет. Почему: `FRONTEND.md`, «у клиента нет своей модели»; дерево `/me` — [10, п. дерева](10-permissions.md); решение 3 плана 40.
- **134.** `prepareAppSession` переезжает в `src/shared/session/prepareSession.ts` и отдаёт `{kind:'ok',access} | {kind:'no-access'} | {kind:'failed'}`. Почему: `src/operator` не вправе импортировать `src/app`. Язык применяется до проверки прав: экран «нет прав» должен быть на языке пользователя.
- **135.** Развилка стоит в `Providers` конфигуратора, до монтирования роутера, на любом его адресе. Только оператор → `/im/operator/`. Только конфигуратор и оба набора → конфигуратор как сейчас. Ничего → как сейчас. При обоих наборах в шапке конфигуратора ссылка «Место оператора», на странице оператора — ссылка «Конфигуратор». Запоминания выбора нет. Почему: сегодняшние администраторы не замечают изменений, а оператору незачем попадать в конфигуратор по старой закладке.
- **136.** Вход оператора сам никуда в портал не уводит: при отсутствии прав, конце сессии и молчании облака — экран со ссылкой на `/`. Единственный автоматический переход — пользователь только с `manage` идёт на `/im/`. Почему: 20-decisions, п. 3.3.4; под Vite `redirectToCloud` ничего не делает и пустая страница ввела бы в заблуждение; оператор посреди смены должен видеть причину.

*Клиент оператора*

- **137.** Сервер МИ этап не поднимает. Настоящий вызов — `GET /operator/session`, права для входа берутся из `/me` облака, сервер МИ для этого не нужен. Этот вызов не чисто читающий: сервер на каждый запрос пишет в свою базу (`Directory.Remember`, `internal/im/handler/operator/auth.go:29`). Запись та же, что у любого запроса, и случится, только если сервер поднял кто-то другой. `PUT agent-state` и `heartbeat` не вызываем: это экраны этапа 9.
- **138.** Буквальное ожидание срока токена заменено подменой: в `localStorage` кладётся поддельный JWT с `exp` через 60 с, клиент читает из него только срок. Обновление и все следующие запросы настоящие. Срок стенда менять нельзя: это настройка облака. Настоящий ход времени покрыт тестом с поддельными таймерами.
- **139.** Транспорт — функция `OperatorTransport`, реализаций две: `httpTransport` и `embeddedTransport`. Только запрос-ответ: поток событий придёт в этапе 9 своим методом, токен он возьмёт из `getFreshAccessToken`.
- **140.** Встроенный сервер включается адресом `?api=embedded` и только при `import.meta.env.DEV`. Скрипты прототипа грузятся классическими тегами из `/im-proto/prototype/` по порядку `prototype/index.html` без интерфейса. Модуль загрузчика подключается динамическим импортом внутри ветки `DEV`. Что rolldown выбрасывает такую ветку, не наблюдалось: первый шаг Task 6 это смотрит, запасной ход — отдельный модуль, подключаемый только в разработке. Промис загрузки живёт в модуле: `StrictMode` запускает эффект дважды, а двух серверов с таймером 1 с быть не должно. Почему: `FRONTEND.md` — встроенный сервер не переносится в продукт; на стенде Vite работает в режиме разработки, а боевая сборка ветку выбрасывает. Адрес `?api=` — тот же приём, что у прототипа. В режиме `embedded` проверка облака пропускается.
- **141.** Страницы этапа не грузят шрифт Google и держат свои тексты в пространстве `operator`, только `ru` и `en`; остальные языки идут через `fallbackLng: 'en'`. Почему: экраны входа показываются раньше, чем доступен каталог `GET /operator/strings`, а настоящие тексты оператора придут оттуда (`FRONTEND.md`). Тема — обычная `@/theme`, ONE PSIM в этапе 9.

*Общий код*

- **142.** Формат сценария и JSONLogic остаются в `src/shared/scenario`, переносить нечего. Проигрыватели, их карточка, `selectDefaults` и тип `StepValue` едут в `src/features/step-player/`. `playerEngine`, `playerNavigation`, таймлайн и финиш остаются в `features/preview`. Почему: что дальше после ответа считает сервер (`FRONTEND.md`, «Карточка сценария»), оператору нужны только поля шага; условия JSONLogic на клиенте оператора не вычисляются. `features/step-player` разрешён editor, preview и operator, сам он их не импортирует.
- **143.** В ESLint добавляем только новые зоны. Перепутанные `target`/`from` у зон домена (15, п. 4.2) не чиним: это чужой долг и отдельное решение команды конфигуратора.

## Не в этом этапе

Служит только боевой выкладке или экранам, поэтому не делается:

- боевой `location /im/operator` с `try_files` в конфигах заказчиков, `no-cache` на `index.html`, перезагрузка по `vite:preloadError`, деплой Bamboo;
- `BroadcastChannel` для `sessionStorage`: нужен одному OEM с DomaAI, на стенде не проверить;
- учёт активности порталом и большой `inactiveLogoutTTLMin` у операторов: настройка облака;
- черновики ответов при конце сессии, кнопка «Выход», сброс `retry` на 401 в `QueryClient`;
- роутер оператора, поток событий, `heartbeat`, тема ONE PSIM, экраны, каталог строк — этап 9;
- перевод новых строк на 11 языков, разделение ресурсов i18n по точкам входа, вынос синглтона `i18n` из домена, npm-пакет, второй пункт `cloud-menu`;
- `Authorization` в `prototype/api.js`: новый клиент его не использует.

## Открытые вопросы

| # | Вопрос | Умолчание плана |
|---|---|---|
| 1 | Что открывать на `/im/` при обоих наборах прав (на стенде это единственный случай): конфигуратор, место оператора или страницу выбора | конфигуратор со ссылкой «Место оператора», решение 135 |
| 2 | Только ли `incident_manager.manage` даёт конфигуратор | да, решение 133; на бою ответит команда конфигуратора |
| 3 | Нужен ли настоящий прогон дольше суток на вкладке | нет, решение 138; можно оставить вкладку открытой на ночь без правок кода |
| 4 | Переводить ли новые строки на остальные 11 языков сейчас | нет, решение 141 |

---

## Файлы

| Файл | Отвечает за | Задача |
|---|---|---|
| `src/shared/api/tokens.ts`, `tokens.test.ts`, `tokens.testing.ts` | пара, срок, одно обновление | 1 |
| `src/shared/api/http.ts`, `http.test.ts` | `apiFetch`, конец сессии, хранитель токена | 2 |
| `src/features/*/api/imBackend*.ts`, `acBackendUsers.ts` | вызовы через `apiFetch` | 3 |
| `src/shared/api/ac-backend/capabilities.ts`, `src/shared/session/prepareSession.ts` | права и старт сессии | 4 |
| `operator/index.html`, `tools/operatorDevRoute.ts`, `src/operator/main.tsx`, `OperatorRoot.tsx`, `entry.ts`, `src/shared/ui/MuiLocaleProvider.tsx` | вторая страница и вход | 5 |
| `src/operator/api/operatorApi.ts`, `embeddedServer.ts`, `src/operator/OperatorPage.tsx` | клиент и пустая страница | 6 |
| `src/app/entryAction.ts`, `OperatorPlaceLink.tsx`, `imAccessContext.ts` | развилка `/im/` | 7 |
| `src/features/step-player/**` | проигрыватели шагов | 8 |
| `~/Work/stand/apply-nginx-dev.sh`, `ui-check/check-operator-entry.mjs`, документы IM | стенд и итог | 9 |

---

### Task 1: Пара токенов и одно обновление на все окна

**Files:**
- Create: `src/shared/api/tokens.ts`, `src/shared/api/tokens.test.ts`, `src/shared/api/tokens.testing.ts`
- Create (в IM, вне git конфигуратора): `.superpowers/sdd/58-plan-stage8/progress.md`

**Interfaces:**
- Consumes: ничего.
- Produces:

```ts
export const REFRESH_URL = '/api/v3/ac-backend/auth/tokens';
export const REFRESH_LOCK = 'axxon-cloud-token-refresh';
export const REFRESH_TIMEOUT_MS = 8_000;
export const LOST_RACE_WAIT_MS = 400;
export type StoredTokens = {
  accessToken: string | null;
  refreshToken: string | null;
  storage: Storage | null;
};
export type RefreshResult = 'ok' | 'ended' | 'failed';
export function readTokens(): StoredTokens;
export function isRefreshDue(accessToken: string, nowMs: number): boolean;
export function refreshTokens(seenRefreshToken: string | null): Promise<RefreshResult>;
// tokens.testing.ts
export function makeJwt(claims: Record<string, unknown>): string; // base64url, подпись 'sig'
```

- [ ] **Step 1: Снять базовую линию**

Run: `cd ~/Work/incident-manager && git rev-parse --short HEAD; npm run test:run 2>&1 | tail -5; npx tsc -p tsconfig.app.json; echo tsc=$?; npm run lint 2>&1 | tail -5; echo lint=$?; npx prettier --check . | tail -6`
Expected: `1fcfa25`; 63 файла и 292 теста зелёные; `tsc=2`, две ошибки `RoleUserGroupsPage.test.tsx:117` и `:125`; `lint=0`, 0 ошибок и 6 предупреждений; `prettier` называет те же 4 файла, что в Global Constraints. Числа записать в `progress.md`: это база всех задач. Другие числа — записать, что изменилось, дальше сравнивать с записанным и не чинить чужое.

- [ ] **Step 2: Написать падающие тесты в `tokens.test.ts`**

Состояние модуля сбрасывается в `beforeEach`: `vi.resetModules()` и `await import('@/shared/api/tokens')`. `localStorage` и `sessionStorage` чистятся в `afterEach`, `fetch` подменяется `vi.stubGlobal`. Два окна — два `vi.resetModules()` с импортом, общий `localStorage` и поддельный последовательный `navigator.locks`.

```ts
const DAY = 86_400;
it('prefers sessionStorage only when it holds both keys', ...);
// session: оба ключа → storage === sessionStorage; только accessToken → storage === localStorage

it('is due within seven minutes of exp for a long token', () => {
  const t = makeJwt({ iat: 1000, exp: 1000 + DAY });
  expect(isRefreshDue(t, (1000 + DAY - 421) * 1000)).toBe(false);
  expect(isRefreshDue(t, (1000 + DAY - 420) * 1000)).toBe(true);
});
it('uses half of the lifetime for a short token', () => {
  const t = makeJwt({ iat: 1000, exp: 1600 }); // 10 минут
  expect(isRefreshDue(t, 1299_000)).toBe(false);
  expect(isRefreshDue(t, 1300_000)).toBe(true);
});
it('falls back to seven minutes without iat', ...);
it('is not due for a token without exp or a non-JWT', () => {
  expect(isRefreshDue('token', Date.now())).toBe(false);
  expect(isRefreshDue(makeJwt({ iat: 1 }), Date.now())).toBe(false);
});

it('posts the refresh token and writes the pair to the same storage', ...);
// sessionStorage с парой A0/R0, ответ 200 {accessToken:'A1',refreshToken:'R1'}
// fetch вызван один раз: REFRESH_URL, method POST, Authorization 'Bearer R0', без body
// результат 'ok', sessionStorage A1/R1, localStorage пуст

it('does nothing when another window already rotated', ...); // seen 'R0', в хранилище 'R1' → 'ok', fetch не вызван
it('ends when there is no refresh token', ...);              // 'ended', fetch не вызван
it('ends on 401 when storage did not change', ...);          // 'ended' после паузы, пара на месте, logout не вызван
it('waits before ending in case the winner has not written yet', ...);
// fetch отвечает 401, R1 появляется в хранилище за LOST_RACE_WAIT_MS → 'ok'
it('ends without a request when the refresh token has expired', ...);
// refresh = makeJwt({ exp: прошлое }) → 'ended', fetch не вызван
it('still posts a refresh token that cannot be read', ...);   // 'R0' и JWT без exp → POST идёт
it('treats 401 as a lost race when storage already changed', ...);
// fetch в момент вызова кладёт R1 в localStorage и отвечает 401 → 'ok'
it('fails softly on 500, network error and timeout', ...);   // 'failed', пара на месте; 500 — ответ облака на мусорный refresh
it('fails softly on 200 without a full pair', ...);          // {accessToken:'A1'} → 'failed', пара A0/R0 на месте
it('passes a timeout signal to the request', ...);           // init.signal instanceof AbortSignal
it('shares one request between callers in a tab', ...);      // два вызова подряд → один POST
it('sends one request across two windows', ...);             // два импорта, общий замок → один POST, оба 'ok'
it('works without navigator.locks', ...);                    // locks undefined → 'ok'
it('asks for the shared lock by name', ...);                 // замок вызван с REFRESH_LOCK
```

- [ ] **Step 3: Убедиться, что тесты падают**

Run: `npx vitest run src/shared/api/tokens.test.ts`
Expected: FAIL, модуль `tokens` не найден.

- [ ] **Step 4: Реализовать `tokens.ts` и `tokens.testing.ts`**

Алгоритм `refreshTokens`, остальное определяют тесты и решения 123–127:

```text
если в окне уже идёт обновление — вернуть его промис
иначе под замком REFRESH_LOCK (или сразу, если замка нет):
  now = readTokens()
  нет now.refreshToken → 'ended'
  now.refreshToken !== seen → 'ok'
  у now.refreshToken есть exp и он прошёл → 'ended', без запроса
  POST с Authorization: Bearer now.refreshToken, Accept: application/json,
       signal: AbortSignal.timeout(REFRESH_TIMEOUT_MS)
  200 и оба поля — строки → записать в now.storage оба ключа → 'ok'
  401 → refresh в хранилище сменился → 'ok'
        иначе пауза LOST_RACE_WAIT_MS, снова прочитать: сменился → 'ok', иначе 'ended'
  остальное, исключения, ошибка записи → 'failed'
в конце сбросить промис окна
```

`exp` refresh-токена читается тем же разбором JWT, что и в `isRefreshDue`; нет `exp` или токен не разбирается — запрос идёт. `readTokens` и запись ловят исключения Web Storage. Другие ключи хранилища не трогаем: `isSocialAuth` и `clientId` принадлежат порталу.

- [ ] **Step 5: Убедиться, что тесты проходят**

Run: `npx vitest run src/shared/api/tokens.test.ts`
Run отдельно: `npx tsc -p tsconfig.app.json; echo tsc=$?`
Expected: PASS; `tsc=2`, только две ошибки базы в `RoleUserGroupsPage.test.tsx`, новых нет.

- [ ] **Step 6: Коммит**

```bash
git add src/shared/api/tokens.ts src/shared/api/tokens.test.ts src/shared/api/tokens.testing.ts
git commit -q -F .git/COMMIT_MSG_STAGE8
```
Сообщение: `Этап 8: пара токенов и одно обновление на все окна`.

---

### Task 2: `apiFetch`, конец сессии и хранитель токена

**Files:**
- Create: `src/shared/api/http.ts`, `src/shared/api/http.test.ts`

**Interfaces:**
- Consumes: `readTokens`, `isRefreshDue`, `refreshTokens`, `makeJwt` из Task 1.
- Produces:

```ts
export const JSON_HEADERS = { 'Content-Type': 'application/json' };
export const PROACTIVE_COOLDOWN_MS = 60_000;
export type ApiFetchInit = Omit<RequestInit, 'headers'> & { headers?: Record<string, string> };
export function apiFetch(url: string, init?: ApiFetchInit): Promise<Response>;
export function getFreshAccessToken(): Promise<string | null>;
export function isSessionEnded(): boolean; // флаг конца сессии или нет access-токена
export function onSessionEnded(listener: () => void): () => void;
export function startTokenKeeper(intervalMs?: number): () => void; // по умолчанию 20_000
```

- [ ] **Step 1: Написать падающие тесты в `http.test.ts`**

Сброс модуля — как в Task 1. Токены: `live = makeJwt({ iat: now, exp: now + DAY })`, `soon = makeJwt({ iat: now - DAY, exp: now + 60 })`.

```ts
it('adds the bearer token and keeps plain headers', async () => {
  localStorage.setItem('accessToken', 'token');
  await apiFetch('/x');
  expect(fetchMock).toHaveBeenCalledWith('/x', { headers: { Authorization: 'Bearer token' } });
});
it('sends no Authorization without a token', ...);
it('refreshes first when the token is due', ...);       // порядок: POST, затем /x с новым токеном
it('retries once with the new token after 401', ...);   // POST body запроса повторён дословно
it('retries without refreshing when another window already changed the token', ...);
it('returns the second 401 and ends the session', ...);  // isSessionEnded() true, слушатель вызван один раз
it('returns 401 and stays alive when refresh failed softly', ...); // refresh 500 → isSessionEnded() false
it('ends the session when refresh is refused', ...);    // refresh 401 → true
it('reports an ended session when tokens are gone', ...); // пустое хранилище → isSessionEnded() true
it('keeps working on the old token while the cloud is down', ...);
// soon + refresh 500: /x ушёл со старым токеном; следующий /x в течение 60 с — без POST;
// после сдвига Date.now на 60 с — POST снова; isSessionEnded() false
it('does not rotate on every request when the clock runs ahead', ...);
// refresh отдаёт снова soon-токен: 5 запросов подряд → один POST
it('does not end the session when a proactive refresh is refused', ...); // soon + refresh 401, /x 200
it('shares one refresh between parallel requests', ...); // 10 запросов → один POST
it('refreshes on the timer with no user activity', ...);
// vi.useFakeTimers: startTokenKeeper(); soon; advance 20 с → POST; событий мыши и клавиш нет
it('stops the keeper', ...);
it('keeper survives a rejected refresh', ...);           // fetch reject → необработанного отказа нет
it('keeper reports an end when the tokens disappear', ...);
// портал стёр пару, запросов нет: через 20 с слушатель onSessionEnded вызван один раз, POST нет
```

- [ ] **Step 2: Убедиться, что тесты падают**

Run: `npx vitest run src/shared/api/http.test.ts`
Expected: FAIL, модуль `http` не найден.

- [ ] **Step 3: Реализовать `http.ts`**

Алгоритм, детали определяют тесты и решения 128–132:

```text
getFreshAccessToken:
  { accessToken, refreshToken } = readTokens()
  нет любого из двух, или срок не подошёл, или идёт пауза → вернуть accessToken
  await refreshTokens(refreshToken); пауза до now + PROACTIVE_COOLDOWN_MS
  вернуть readTokens().accessToken

apiFetch:
  used = await getFreshAccessToken()
  res = await fetch(url, withBearer(init, used))
  не 401 → вернуть res
  now = readTokens()
  now.accessToken есть и !== used → итог 'ok', иначе итог = await refreshTokens(now.refreshToken)
  'ended' → отметить конец, вернуть res
  'failed' → вернуть res
  'ok' → res2 = await fetch(url, withBearer(init, readTokens().accessToken))
         res2.status === 401 → отметить конец
         вернуть res2

startTokenKeeper, такт:
  isSessionEnded() → отметить конец, выйти
  иначе getFreshAccessToken(), отказ проглотить
```

Пауза снимается только временем; при успешном обновлении токен обычно больше не выглядит истекающим, и пауза ничего не меняет. Отметка конца вызывает слушателей один раз. `withBearer` кладёт `Authorization` в обычный объект заголовков; без токена заголовка нет.

- [ ] **Step 4: Убедиться, что тесты проходят**

Run: `npx vitest run src/shared/api/http.test.ts src/shared/api/tokens.test.ts`
Run отдельно: `npx tsc -p tsconfig.app.json; echo tsc=$?`
Expected: PASS; `tsc=2`, только две ошибки базы в `RoleUserGroupsPage.test.tsx`, новых нет.

- [ ] **Step 5: Коммит**

Файлы: `src/shared/api/http.ts`, `src/shared/api/http.test.ts`. Сообщение: `Этап 8: общий HTTP-клиент с обновлением токена и обработкой 401`.

---

### Task 3: Конфигуратор ходит через общий клиент

**Files:**
- Modify: `src/features/scenarios/api/imBackendScenarios.ts` (4 вызова), `src/features/incident-rules/api/imBackendIncidentRules.ts` (14), `src/features/role-assignments/api/imBackendRoleAssignments.ts` (9), `src/features/source-groups/api/imBackendSourceGroups.ts` (10), `src/shared/api/ac-backend/acBackendUsers.ts` (1)
- Modify: `PROJECT.md:130`, `:348`, `:429`

**Interfaces:**
- Consumes: `apiFetch`, `JSON_HEADERS` из Task 2, `readTokens` из Task 1.
- Produces: ни одной копии `ACCESS_TOKEN_KEY`, `getAccessToken`, `authHeaders` в `src/features` и `acBackendUsers.ts`.

- [ ] **Step 1: Написать падающий тест на обновление в конфигураторе**

Новый файл `src/features/scenarios/api/imBackendScenarios.auth.test.ts`:

```ts
it('retries a scenario save after 401 with a refreshed token', async () => {
  localStorage.setItem('accessToken', 'A0');
  localStorage.setItem('refreshToken', 'R0');
  // fetch: первый PATCH → 401, POST /auth/tokens → A1/R1, второй PATCH → 200 с записью сценария
  // проверка: у последнего вызова Authorization 'Bearer A1', тело то же
});
```

Сценарий и ответ взять из соседних тестов разбора.

- [ ] **Step 2: Убедиться, что тест падает**

Run: `npx vitest run src/features/scenarios/api/imBackendScenarios.auth.test.ts`
Expected: FAIL, повтора нет.

- [ ] **Step 3: Заменить вызовы**

В каждом файле: `fetch(url, { headers: authHeaders() })` → `apiFetch(url)`, `headers: authHeaders(true)` → `headers: JSON_HEADERS`, остальные поля без изменений; локальные `ACCESS_TOKEN_KEY`, `getAccessToken`, `authHeaders` удалить. `fetchCurrentUser`: проверку `Missing access token` оставить на `readTokens().accessToken`, сам запрос — `apiFetch`. Разбор ответов и тексты ошибок не трогать.

- [ ] **Step 4: Проверить, что копий не осталось**

Run: `grep -rn "ACCESS_TOKEN_KEY\|authHeaders\|[^a-zA-Z]fetch(" src --include=*.ts --include=*.tsx | grep -v "\.test\.\|src/shared/api/http.ts\|src/shared/api/tokens.ts"`
Expected: пусто.

- [ ] **Step 5: Прогнать весь набор**

Run: `npm run test:run`
Run отдельно: `npx tsc -p tsconfig.app.json; echo tsc=$?`
Expected: PASS, те же тесты, что в базовой линии, плюс новые; `tsc=2`, только две ошибки базы в `RoleUserGroupsPage.test.tsx`, новых нет. Если тест конфигуратора ждёт точный объект `init`, проверить, что поведение то же, и только тогда поправить ожидание.

- [ ] **Step 6: Обновить `PROJECT.md`**

Строку 130: «Токен обновляет `src/shared/api/http.ts`: заранее и на 401; при неудаче конфигуратор показывает ошибку запроса». Пункт 2 в Pitfalls: «Token refresh only via `apiFetch`; don't call `fetch` with a bearer token by hand; don't invent local login». Строку 429 таблицы долгов удалить.

- [ ] **Step 7: Коммит**

Шум форматирования `imBackendRoleAssignments.ts` от хука ожидаем, а `imBackendRoleAssignments.test.ts` этой задаче чужой: `git restore`. Сообщение: `Этап 8: конфигуратор ходит через общий HTTP-клиент`.

---

### Task 4: Права из дерева `/me` и общий старт сессии

**Files:**
- Modify: `src/shared/api/ac-backend/capabilities.ts`, `capabilities.test.ts`, `index.ts` (экспортирует `readImAccess` и тип `ImAccess`: их берут задачи 5–7)
- Rename: `src/app/bootstrapSession.ts` → `src/shared/session/prepareSession.ts`, `src/app/bootstrapSession.test.ts` → `src/shared/session/prepareSession.test.ts` (через `git mv`)
- Modify: `src/app/providers.tsx`, `src/app/providers.test.tsx`, `PROJECT.md`: все упоминания `prepareAppSession` и `bootstrapSession` (`grep -n`), сейчас строки 118, 124 и 350, плюс раздел Entry & bootstrap

**Interfaces:**
- Consumes: `fetchCurrentUser` (уже через `apiFetch`).
- Produces:

```ts
export type ImAccess = { configurator: boolean; operator: boolean };
export function readImAccess(capabilities: AcBackendCapabilitiesTree | undefined): ImAccess;
// hasIncidentManagerAccess остаётся: configurator || operator

export type SessionResult =
  | { kind: 'ok'; access: ImAccess }
  | { kind: 'no-access' }
  | { kind: 'failed' };
export function prepareSession(): Promise<SessionResult>; // не бросает, 10 с максимум
```

- [ ] **Step 1: Написать падающие тесты**

```ts
// capabilities.test.ts
const manage = { '': { actions: { manage: {} } } };
const take = { incidents: { actions: { take: { scopes: ['own'] } } } };
const release = { 'incidents.release': { actions: { use: {} } } };
it('reads manage as the configurator right', () => {
  expect(readImAccess({ incident_manager: manage })).toEqual({ configurator: true, operator: false });
});
it('reads any other action as the operator right', () => {
  expect(readImAccess({ incident_manager: take })).toEqual({ configurator: false, operator: true });
  expect(readImAccess({ incident_manager: release })).toEqual({ configurator: false, operator: true });
});
it('reads both sets', ...);
it('reads an action next to manage on the root resource as operator', ...); // '': {manage, other}
it('reads nothing from an empty namespace, a foreign namespace or undefined', ...);

// prepareSession.test.ts — бывшие случаи с новым результатом
// успех → { kind: 'ok', access: {...} }, язык применён
// нет права → { kind: 'no-access' }, ЯЗЫК ПРИМЕНЁН (новое: i18n.language начинается с 'ru')
// нет capabilities → 'no-access'; ошибка и тайм-аут 10 с → 'failed'
```

- [ ] **Step 2: Убедиться, что тесты падают**

Run: `npx vitest run src/shared/api/ac-backend/capabilities.test.ts src/shared/session/prepareSession.test.ts`
Expected: FAIL: нет `readImAccess`, нет файла.

- [ ] **Step 3: Реализовать**

`readImAccess` — по решению 133. Каталога ещё нет: `mkdir -p src/shared/session`, затем `git mv` обоих файлов, функция называется `prepareSession`. `Providers` пока ведёт себя как раньше: `granted = session.kind === 'ok'`. `providers.test.tsx` мокает `@/shared/session/prepareSession`.

- [ ] **Step 4: Убедиться, что всё зелёное**

Run: `npm run test:run`
Run отдельно: `npx tsc -p tsconfig.app.json; echo tsc=$?`
Expected: PASS; `tsc=2`, только две ошибки базы в `RoleUserGroupsPage.test.tsx`, новых нет.

- [ ] **Step 5: Обновить `PROJECT.md` и закоммитить**

Сообщение: `Этап 8: права конфигуратора и оператора, общий старт сессии`. Хук не добавляет свои правки в файлы из `git mv`: после коммита `git status --short`, `git add src/shared/session` и `git commit -q --amend --no-edit`, если там что-то есть. `git restore` к этим файлам не применять.

---

### Task 5: Вторая точка входа и экран входа оператора

**Files:**
- Create: `operator/index.html`, `tools/operatorDevRoute.ts`, `tools/operatorDevRoute.test.ts`, `src/operator/main.tsx`, `src/operator/OperatorRoot.tsx`, `src/operator/OperatorRoot.test.tsx`, `src/operator/entry.ts`, `src/operator/entry.test.ts`, `src/shared/ui/MuiLocaleProvider.tsx`, `src/shared/i18n/locales/ru/operator.json`, `src/shared/i18n/locales/en/operator.json`
- Modify: `vite.config.ts`, `eslint.config.js`, `src/app/providers.tsx`, `src/shared/i18n/resources.ts`, `src/shared/i18n/config.ts`, `PROJECT.md`
- Вне `tsc`: `tools/operatorDevRoute.ts` и `vite.config.ts`; `tools/` ещё и вне ESLint. Их покрывает Vitest. `vite.config.ts` не отформатирован на базе, шум хука в диффе ожидаем.

**Interfaces:**
- Consumes: `prepareSession`, `SessionResult`, `ImAccess` из Task 4; `isSessionEnded`, `startTokenKeeper`, `onSessionEnded` из Task 2.
- Produces:

```ts
// tools/operatorDevRoute.ts
export function operatorDevRoute(url: string): string | null;

// src/operator/entry.ts
export type ApiMode = 'server' | 'embedded';
export type OperatorEntry =
  | { kind: 'ready'; access: ImAccess }
  | { kind: 'to-configurator' }
  | { kind: 'no-rights' }
  | { kind: 'session-ended' }
  | { kind: 'cloud-unavailable' };
export const CONFIGURATOR_PATH = '/im/';
export function pickApiMode(search: string, isDev: boolean): ApiMode;
export function operatorEntryFrom(session: SessionResult, sessionEnded: boolean): OperatorEntry;

// src/shared/ui/MuiLocaleProvider.tsx — из providers.tsx, вместе с muiLocaleForLanguage
export function MuiLocaleProvider({ children }: { children: ReactNode }): ReactElement;

// src/operator/OperatorRoot.tsx
export function OperatorRoot(props: { mode: ApiMode }): ReactElement;
// корень с data-operator-entry="loading|ready|no-rights|session-ended|cloud-unavailable"
```

Строки `operator.json`:

| Ключ | ru | en |
|---|---|---|
| `title` | Место оператора | Operator workplace |
| `loading` | Загрузка… | Loading… |
| `noRights` | Нет прав на место оператора. Обратитесь к администратору. | You have no access to the operator workplace. Contact your administrator. |
| `sessionEnded` | Сессия завершена. Войдите в облако заново. | Your session has ended. Sign in to the cloud again. |
| `cloudUnavailable` | Облако не отвечает. Проверьте связь и обновите страницу. | The cloud is not responding. Check the connection and reload the page. |
| `toPortal` | Перейти в облако | Go to the cloud |
| `toConfigurator` | Конфигуратор | Configurator |
| `apiUnavailable` | Сервер МИ недоступен. | The Incident Manager server is unavailable. |
| `apiRefused` | Сервер МИ отказал в доступе. | The Incident Manager server denied access. |
| `sourceServer` | Источник: сервер МИ | Source: Incident Manager server |
| `sourceEmbedded` | Источник: встроенный сервер прототипа | Source: prototype built-in server |
| `operatorLine` | {{name}}, состояние: {{agentState}}, прав: {{count}} | {{name}}, state: {{agentState}}, permissions: {{count}} |

- [ ] **Step 1: Увидеть вторую страницу в сборке**

Предполётная проверка читала исходник Vite, но `vite build` не запускала: не наблюдалось, что `dist/operator/index.html` появится. На этом стоит вся задача, поэтому сначала наблюдение.

Создать `operator/index.html` в окончательном виде (Step 4), заглушку `src/operator/main.tsx` из одной строки `document.title = 'operator';` и добавить в `vite.config.ts` только `build.rolldownOptions.input` (Step 4). Эти файлы остаются, Step 4 их дополнит.

Run: `npm run build; echo build=$?; test -f dist/index.html; echo main=$?; test -f dist/operator/index.html; echo operator=$?; grep -o '/im/assets/[^"]*' dist/operator/index.html`
Expected: `build=0`, `main=0`, `operator=0`, адреса чанков начинаются с `/im/assets/`. Итог записать в `progress.md`.

Если иначе:

- `operator=1`, в `dist` одна страница: вход не принят. Заменить на `build.rollupOptions.input`, повторить, отступление записать в `progress.md`.
- страница легла в другой каталог (`find dist -name '*.html'`) или адреса чанков без `/im/`: это не чинится настройкой задачи, потому что сломает раздачу под `/im/`. Стоп, доложить.
- сборка падает или `operator=1` и с `rollupOptions`: стоп, доложить. Задачи 5–7 и 9 не начинать. Запасной ход из [15, п. 4.4](15-deploy-configurator.md) — раздел внутри того же SPA, он меняет решение 119, и выбирает его пользователь, а не исполнитель.

- [ ] **Step 2: Написать падающие тесты**

Матчеры jest-dom (`toHaveAttribute`, `toBeInTheDocument`) не использовать: `getAttribute`, `not.toBeNull`, как `providers.test.tsx`. Иначе Vitest зелёный, а у `tsc` новые ошибки.

```ts
// tools/operatorDevRoute.test.ts
it('rewrites a deep link to the operator page', () => {
  expect(operatorDevRoute('/im/operator/incidents/42')).toBe('/im/operator/index.html');
});
it('keeps the query', () => {
  expect(operatorDevRoute('/im/operator/incidents/42?api=embedded'))
    .toBe('/im/operator/index.html?api=embedded');
});
it('leaves the page itself and files alone', () => {
  expect(operatorDevRoute('/im/operator/')).toBeNull();
  expect(operatorDevRoute('/im/operator/index.html')).toBeNull();
  expect(operatorDevRoute('/im/operator/a.png')).toBeNull();
});
it('leaves other urls alone', () => {
  expect(operatorDevRoute('/im/source-groups')).toBeNull();
  expect(operatorDevRoute('/im/operatorish/x')).toBeNull();
  expect(operatorDevRoute('/im/src/operator/main.tsx')).toBeNull();
});

// src/operator/entry.test.ts
it('enters with the operator right', ...);           // ok + operator → ready с access
it('sends a configurator-only user away', ...);      // ok + только configurator → to-configurator
it('stops without rights', ...);                     // no-access → no-rights
it('separates an ended session from a silent cloud', () => {
  expect(operatorEntryFrom({ kind: 'failed' }, true).kind).toBe('session-ended');
  expect(operatorEntryFrom({ kind: 'failed' }, false).kind).toBe('cloud-unavailable');
});
it('honours embedded only in development', () => {
  expect(pickApiMode('?api=embedded', true)).toBe('embedded');
  expect(pickApiMode('?api=embedded', false)).toBe('server');
  expect(pickApiMode('', true)).toBe('server');
});

// src/operator/OperatorRoot.test.tsx, prepareSession и apiFetch замоканы
// location.replace в jsdom подменять через vi.stubGlobal, spyOn не сработает
it('shows a screen and never leaves on its own without rights', ...);
// data-operator-entry="no-rights", ссылка href="/", location.replace не вызван
it('shows the session-ended screen and does not call logout', ...);
it('goes to the configurator for a configurator-only user', ...); // location.replace('/im/')
it('skips the cloud in embedded mode', ...);          // prepareSession не вызван, keeper не запущен
it('starts the token keeper once and stops it on unmount', ...);
it('turns into the session-ended screen when the session ends later', ...); // слушатель onSessionEnded
```

- [ ] **Step 3: Убедиться, что тесты падают**

Run: `npx vitest run tools/operatorDevRoute.test.ts src/operator`
Expected: FAIL: файлов нет.

- [ ] **Step 4: Собрать страницу и настройку Vite**

- `operator/index.html`: как корневой, но без ссылок на Google Fonts, `<title>Operator</title>`, скрипт `/src/operator/main.tsx`.
- `vite.config.ts`: `build: { rolldownOptions: { input: { main: path.resolve(__dirname, 'index.html'), operator: path.resolve(__dirname, 'operator/index.html') } } }`. Плагин `dev-operator-deep-links`: для `GET` и `HEAD`, если `operatorDevRoute(req.url)` не `null`, заменить `req.url`, затем `next()`. `dev-root-not-spa` не менять.
- `src/operator/main.tsx`: как `src/main.tsx`, без `Providers`; режим `pickApiMode(location.search, import.meta.env.DEV)`.
- `OperatorRoot`: `I18nextProvider` → `MuiLocaleProvider` → экран. Начальное состояние считается в `useState(() => mode === 'embedded' ? { kind: 'ready', access: { configurator: false, operator: true } } : 'загрузка')`. Синхронного `setState` в эффекте и чтения `ref` при рендере нет: `react-hooks/set-state-in-effect` и `react-hooks/refs` в `recommended-latest` стоят ошибками, а без линта не пройдёт хук коммита. Образец — `src/app/providers.tsx:87`, `setState` только в `.then`. В режиме `server` эффект с защитой от размонтирования: `prepareSession()` → в `.then` `operatorEntryFrom(session, isSessionEnded())`; при `to-configurator` — `location.replace(CONFIGURATOR_PATH)`, загрузка остаётся на экране. Отдельный эффект: при `ready` и только в режиме `server` — `startTokenKeeper()` и `onSessionEnded`, со снятием при размонтировании; в `embedded` хранитель не запускается. Загрузка — `CircularProgress` с подписью `loading`. Экраны без прав, конца сессии и молчания облака — текст и ссылка `<a href="/">`. На `ready` пока заголовок `title`; страницу подключит Task 6.
- `MuiLocaleProvider` — вынести из `providers.tsx` дословно, `Providers` импортирует его.
- i18n: пространство `operator` только в `en` и `ru`, в списке `ns`.

- [ ] **Step 5: Добавить зоны ESLint**

В `zones` дописать: `src/operator/**` не импортирует `src/app/**`, `src/features/editor/**`, `src/features/preview/**`, `src/features/scenarios/**`, `src/features/source-groups/**`, `src/features/incident-rules/**`, `src/features/role-assignments/**`, `src/features/diagram/**`; `src/app/**`, `src/features/**`, `src/shared/**` не импортируют `src/operator/**`.

- [ ] **Step 6: Прогнать тесты**

Run: `npx vitest run tools/operatorDevRoute.test.ts src/operator && npm run lint`
Run отдельно: `npx tsc -p tsconfig.app.json; echo tsc=$?`
Expected: PASS, 0 ошибок линта; `tsc=2`, только две ошибки базы в `RoleUserGroupsPage.test.tsx`, новых нет.

- [ ] **Step 7: Проверить зону и сборку**

Временно добавить в `src/operator/entry.ts` строку `import '@/app/AppShell';`, запустить `npx eslint src/operator/entry.ts`, увидеть ошибку `import/no-restricted-paths`, строку убрать.

Run: `npm run build && test -f dist/operator/index.html && grep -c '/im/assets/' dist/operator/index.html && grep -l 'react-flow' $(grep -o '/im/assets/[^"]*\.js' dist/operator/index.html | sed 's#^/im/#dist/#'); echo grep=$?`
Expected: файл есть, счётчик больше 0, последняя команда ничего не находит, `grep=1`: страница оператора не тянет редактор диаграмм. Vite перечисляет статические чанки входа в `modulepreload`, поэтому этого списка хватает.

- [ ] **Step 8: Обновить `PROJECT.md` и закоммитить**

Дерево каталогов, раздел Entry & bootstrap, границы модулей. Сообщение: `Этап 8: вторая точка входа Vite /im/operator/ и экран входа`.

---

### Task 6: Клиент оператора, встроенный сервер и пустая страница

**Files:**
- Create: `src/operator/api/operatorApi.ts`, `src/operator/api/operatorApi.test.ts`, `src/operator/api/embeddedServer.ts`, `src/operator/api/embeddedServer.test.ts`, `src/operator/OperatorPage.tsx`, `src/operator/OperatorPage.test.tsx`
- Modify: `src/operator/OperatorRoot.tsx`, `src/operator/OperatorRoot.test.tsx`, `PROJECT.md`

**Interfaces:**
- Consumes: `apiFetch` из Task 2, `ApiMode`, `ImAccess`, `CONFIGURATOR_PATH` из Task 4–5.
- Produces:

```ts
export const OPERATOR_API_BASE = '/api/v1/im-backend';
export type OperatorRequest = {
  method: string;
  path: string; // путь контракта, например '/operator/session'
  body?: unknown;
  headers?: Record<string, string>;
};
export type OperatorResponse = {
  status: number; // 0 — ответа не было
  body: unknown;  // null, если тело не JSON
  headers: Record<string, string>; // имена строчными, как у fetch
};
export type OperatorTransport = (request: OperatorRequest) => Promise<OperatorResponse>;
export type OperatorProblem = { code: string; message: string; messageKey?: string };
export class OperatorApiError extends Error {
  readonly status: number;
  readonly problem: OperatorProblem | null;
}
export type OperatorSession = {
  operator: { guid?: string; name?: string; role?: string };
  agentState: 'ready' | 'busy' | 'not_ready' | 'offline';
  permissions: string[];
};
export type EmbeddedServer = {
  handle(method: string, url: string, body: unknown, headers?: Record<string, string>):
    { status: number; body: unknown; headers?: Record<string, string> };
};
export function httpTransport(baseUrl?: string): OperatorTransport;
export function embeddedTransport(server: EmbeddedServer): OperatorTransport;
export function createOperatorClient(transport: OperatorTransport): {
  request<T = unknown>(request: OperatorRequest): Promise<T>; // status 0 или >= 400 → OperatorApiError
  getSession(): Promise<OperatorSession>;
};

// embeddedServer.ts, только разработка
export const PROTOTYPE_BASE = '/im-proto/prototype/';
export const PROTOTYPE_SCRIPTS: readonly string[];
export function loadEmbeddedServer(): Promise<EmbeddedServer>; // один промис на модуль

// OperatorPage.tsx
export function OperatorPage(props: {
  client: ReturnType<typeof createOperatorClient>;
  access: ImAccess;
  mode: ApiMode;
}): ReactElement;
// корень: data-operator-api="pending|ok|error", data-api-status="<код>", data-api-mode="server|embedded"
```

`PROTOTYPE_SCRIPTS`, порядок обязателен: `workflow.js`, `vendor/cel-js/cel.js`, `cel-runtime.js`, `engine.js`, `vendor/json-logic-js/logic.js`, `scenario.js`, `fixture.js`, `strings.js`, `colleagues.js`, `server.js`. Вызов: `window.IMServer.create({ workflow: window.IM_WORKFLOW, fixture: window.IM_FIXTURE, strings: window.IM_STRINGS, colleagues: window.IM_COLLEAGUES, testSupport: false })`.

- [ ] **Step 1: Увидеть, что боевая сборка выбрасывает ветку `DEV`**

Не наблюдалось, что rolldown выбросит динамический импорт внутри `import.meta.env.DEV`, а на этом стоит решение 140.

Временно: файл `src/operator/api/devProbe.ts` со строкой `export const probe = 'im-proto-probe';` и в `src/operator/main.tsx` строка `if (import.meta.env.DEV) void import('@/operator/api/devProbe');`.

Run: `npm run build; echo build=$?; grep -rl 'im-proto-probe' dist; echo grep=$?`
Expected: `build=0`, `grep=1`. Итог записать в `progress.md`, файл пробы удалить, `git restore src/operator/main.tsx`.

Если строка нашлась (`grep=0`), импорт в ветке не отсекается. Тогда встроенный сервер подключается отдельным модулем только в разработке: `src/operator/api/loadEmbedded.ts` реэкспортирует `loadEmbeddedServer` из `embeddedServer.ts`, `src/operator/api/loadEmbedded.stub.ts` экспортирует то же имя и бросает ошибку, а `vite.config.ts` при `command === 'build'` подменяет первый вторым через `resolve.alias`, ключ `@/operator/api/loadEmbedded` стоит раньше `@`. `createClient` из Step 6 импортирует `@/operator/api/loadEmbedded`, остальное решение 140 не меняется. Отступление записать в `progress.md`. Итоговая проверка `grep -rl 'im-proto' dist` в Step 7 остаётся и для этого пути.

- [ ] **Step 2: Написать падающие тесты**

Матчеры jest-dom (`toHaveAttribute`, `toBeInTheDocument`) не использовать: `getAttribute`, `not.toBeNull`, как `providers.test.tsx`. Иначе Vitest зелёный, а у `tsc` новые ошибки.

```ts
// operatorApi.test.ts
it('sends the contract path through apiFetch', ...);
// httpTransport: GET '/api/v1/im-backend/operator/session', JSON в body, заголовки строчными
it('sends json with a content type and keeps custom headers', ...); // If-Match дошёл
it('reports a gateway html error as a plain status', async () => {
  // fetch → new Response('<html>502 Bad Gateway</html>', { status: 502 })
  await expect(client.getSession()).rejects.toMatchObject({ status: 502, problem: null });
});
it('turns a network failure into status 0', ...);
it('reads problem json', ...);        // 403 {code:'PERMISSION_DENIED',message:'…'} → problem.code
it('passes contract errors as they are', ...);      // 501 NOT_IMPLEMENTED → status 501
it('does not let the embedded server share objects with the caller', ...);
// embeddedTransport: body и ответ — копии; изменение ответа не меняет объект сервера
it('lowercases embedded header names', ...);       // ETag → etag
it('calls the embedded server with a contract path', ...); // handle('GET','/operator/session',undefined,{})
it('rejects a session without required fields', ...); // 200 {} → OperatorApiError status 200

// OperatorPage.test.tsx
it('shows the operator from the session', ...);
// getSession → name 'Тест Оператор', ready, 14 прав; data-operator-api="ok"; текст строки operatorLine
it('shows the source of the data', ...);           // sourceServer и sourceEmbedded
it('shows unavailable and the status on 502', ...); // data-operator-api="error", data-api-status="502"
it('does not treat a 403 as an unavailable server', ...); // текст apiRefused
it('shows unavailable on a 401 that did not end the session', ...); // мягкий сбой обновления: текст apiUnavailable
it('links to the configurator only with that right', ...); // href '/im/'
it('asks for the session once', ...);  // без StrictMode; на стенде main.tsx даёт два вызова, это норма

// embeddedServer.test.ts
it('loads the prototype once', ...);
// два вызова loadEmbeddedServer: тегов <script> по одному на файл, IMServer.create один раз, один промис
```

- [ ] **Step 3: Убедиться, что тесты падают**

Run: `npx vitest run src/operator/api src/operator/OperatorPage.test.tsx`
Expected: FAIL: файлов нет.

- [ ] **Step 4: Реализовать `operatorApi.ts`**

Тело ответа читается `res.text()`, разбор JSON — в `try`, при неудаче `null`. Исключение `apiFetch` → `{ status: 0, body: null, headers: {} }`. Копии во встроенном транспорте — `JSON.parse(JSON.stringify(...))` с защитой от `undefined`, как `prototype/api.js`. `getSession` проверяет ответ схемой zod с `.passthrough()` по обязательным полям контракта: `operator`, `permissions`, `agentState`. Лишнее не требуем.

- [ ] **Step 5: Реализовать `embeddedServer.ts`**

`loadEmbeddedServer` добавляет теги `<script>` по одному, ждёт `onload`, при `onerror` отклоняет промис с адресом скрипта. Промис держится в переменной модуля, повторный вызов отдаёт его же: `StrictMode` запускает эффект дважды, а `IMServer.create` заводит таймер 1 с. После отказа промис сбрасывается. Логики правил здесь нет.

- [ ] **Step 6: Реализовать страницу и подключить её**

`OperatorPage`: `useEffect` с защитой от размонтирования, один вызов `getSession`, `setState` только в `.then` и `.catch`. Текст ошибки: `status === 403` → `apiRefused`, всё остальное, включая 401 после мягкого сбоя обновления, → `apiUnavailable`. Если 401 закончил сессию, экран покажет `OperatorRoot` по `onSessionEnded`.

`OperatorRoot` на `ready` получает клиента асинхронной функцией и кладёт его в состояние только в `.then`, чтения `ref` при рендере нет:

```ts
async function createClient(mode: ApiMode) {
  if (import.meta.env.DEV && mode === 'embedded') {
    const { loadEmbeddedServer } = await import('@/operator/api/embeddedServer');
    return createOperatorClient(embeddedTransport(await loadEmbeddedServer()));
  }
  return createOperatorClient(httpTransport());
}
```

Сбой загрузки скриптов прототипа — экран `cloud-unavailable`, причина в `console.error`.

- [ ] **Step 7: Прогнать тесты и сборку**

Run: `npx vitest run src/operator && npm run lint && npm run build; echo chain=$?`
Run отдельно: `npx tsc -p tsconfig.app.json; echo tsc=$?`
Run отдельно: `grep -rl 'im-proto' dist; echo grep=$?`
Expected: `chain=0`; `tsc=2`, только две ошибки базы в `RoleUserGroupsPage.test.tsx`, новых нет; `grep` ничего не находит, `grep=1`: встроенного сервера в боевой сборке нет. Это единственная такая проверка: при `chain` не 0 она ничего не доказывает, сначала чинить цепочку. Если `grep` что-то нашёл — запасной ход из Step 1.

- [ ] **Step 8: Обновить `PROJECT.md` и закоммитить**

Сообщение: `Этап 8: клиент оператора, встроенный сервер прототипа и пустая страница`.

---

### Task 7: Один пункт меню: развилка `/im/` по правам

**Files:**
- Create: `src/app/entryAction.ts`, `src/app/entryAction.test.ts`, `src/app/imAccessContext.ts`, `src/app/OperatorPlaceLink.tsx`, `src/app/OperatorPlaceLink.test.tsx`, `tests/entry-no-loop.test.ts`
- Modify: `src/app/redirectToCloud.ts`, `src/app/redirectToCloud.test.ts`, `src/app/providers.tsx`, `src/app/providers.test.tsx`, `src/app/AppShell.tsx`, `src/shared/i18n/locales/ru/nav.json`, `src/shared/i18n/locales/en/nav.json`, `PROJECT.md`

**Interfaces:**
- Consumes: `SessionResult`, `ImAccess` из Task 4; `operatorEntryFrom` из Task 5 — только в тесте на петлю: он лежит в `tests/`, потому что `src/app` не вправе импортировать `src/operator`.
- Produces:

```ts
export const OPERATOR_ENTRY_PATH = '/im/operator/';
export function redirectToOperator(): void; // location.replace; работает и под Vite
export type EntryAction = 'mount' | 'operator' | 'cloud';
export function configuratorEntryAction(session: SessionResult): EntryAction;
export const ImAccessContext: React.Context<ImAccess>;
export function OperatorPlaceLink(): ReactElement | null; // <a href="/im/operator/"> при access.operator
```

Строка `nav.operatorPlace`: ru «Место оператора», en «Operator workplace».

- [ ] **Step 1: Написать падающие тесты**

Матчеры jest-dom (`toHaveAttribute`, `toBeInTheDocument`) не использовать: `getAttribute`, `not.toBeNull`, как `providers.test.tsx`. Иначе Vitest зелёный, а у `tsc` новые ошибки. `tests/entry-no-loop.test.ts` лежит вне `tsc`, его покрывает только Vitest.

```ts
// entryAction.test.ts
const ok = (configurator: boolean, operator: boolean): SessionResult =>
  ({ kind: 'ok', access: { configurator, operator } });
it('sends an operator-only user to the operator place', () => {
  expect(configuratorEntryAction(ok(false, true))).toBe('operator');
});
it('keeps a user with both sets in the configurator', () => {
  expect(configuratorEntryAction(ok(true, true))).toBe('mount');
});
it('keeps a configurator-only user', ...);
it('hands everything else to the existing cloud gate', () => {
  expect(configuratorEntryAction({ kind: 'no-access' })).toBe('cloud');
  expect(configuratorEntryAction({ kind: 'failed' })).toBe('cloud');
});

// tests/entry-no-loop.test.ts
it('never sends a user back and forth', () => {
  // для всех четырёх наборов и трёх итогов сессии:
  // configuratorEntryAction === 'operator' влечёт operatorEntryFrom(...).kind === 'ready',
  // operatorEntryFrom(...).kind === 'to-configurator' влечёт configuratorEntryAction === 'mount'
});

// providers.test.tsx
it('redirects an operator-only user before mounting the router', ...);
it('keeps today behaviour in development when access is denied', ...); // MODE — через vi.stubEnv: роутер смонтирован
it('passes access to the context', ...);

// OperatorPlaceLink.test.tsx
it('links to the operator place with the right', ...);  // href '/im/operator/', текст «Место оператора»
it('renders nothing without the right', ...);
```

- [ ] **Step 2: Убедиться, что тесты падают**

Run: `npx vitest run src/app tests/entry-no-loop.test.ts`
Expected: FAIL: нет `entryAction`, нет ссылки.

- [ ] **Step 3: Реализовать развилку**

`Providers`: `configuratorEntryAction(session)`. `'operator'` → `redirectToOperator()`, загрузка остаётся на экране. `'cloud'` → прежняя пара `shouldRedirectToCloud(false)` / `redirectToCloud()`; под Vite приложение монтируется как сейчас, с `{configurator:false, operator:false}`. `'mount'` → монтирование, `access` в `ImAccessContext`. `OperatorPlaceLink` — обычная ссылка `<a>` после `Tabs` в `AppShell`: это другая страница, не маршрут роутера.

- [ ] **Step 4: Прогнать всё**

Run: `npm run test:run && npm run lint && npm run build; echo chain=$?`
Run отдельно: `npx tsc -p tsconfig.app.json; echo tsc=$?`
Expected: `chain=0`; `tsc=2`, только две ошибки базы в `RoleUserGroupsPage.test.tsx`, новых нет.

- [ ] **Step 5: Обновить `PROJECT.md` и закоммитить**

Пункт 3 в Pitfalls («Capability check is coarse») заменить на правило решений 133 и 135. `redirectToCloud.ts` не отформатирован на базе, шум хука в диффе ожидаем. Сообщение: `Этап 8: один пункт меню: /im/ ведёт к оператору или в конфигуратор по правам`.

---

### Task 8: Проигрыватели шагов — общий модуль

**Files:**
- Rename (через `git mv`): `src/features/preview/components/step-player/*.tsx` → `src/features/step-player/components/`, `src/features/preview/lib/selectDefaults.ts` → `src/features/step-player/lib/selectDefaults.ts`
- Create: `src/features/step-player/lib/stepValue.ts`, `src/features/step-player/components/StepPlayer.test.tsx`
- Modify: `src/features/preview/lib/playerEngine.ts`, все импортёры (`ScenarioPlayer.tsx`, `playerNavigation.ts`, `StepPreviewModal.tsx`), `eslint.config.js`, `PROJECT.md`

**Interfaces:**
- Consumes: `@/shared/scenario`.
- Produces: `StepPlayer`, `StepPlayerProps` из `@/features/step-player/components/StepPlayer.tsx`; `StepValue` из `@/features/step-player/lib/stepValue.ts`; `selectDefaultsFromLists` из `@/features/step-player/lib/selectDefaults.ts`. `playerEngine.ts` сохраняет `export type { StepValue }`, чтобы 11 файлов предпросмотра с этим импортом, считая тесты, не менялись.

- [ ] **Step 1: Написать падающий тест на новый адрес**

`StepPlayer.test.tsx`, без роутера, запроса и провайдеров предпросмотра. Ввод — `fireEvent`: `user-event` в зависимостях нет. Матчеры jest-dom (`toHaveAttribute`, `toBeInTheDocument`) не использовать: `getAttribute`, `not.toBeNull`, как `providers.test.tsx`. Иначе Vitest зелёный, а у `tsc` новые ошибки.

```ts
it('renders a Comment step and reports the draft', ...);
// шаг Comment из @/shared/scenario; ввод текста → onDraftChange('текст'); «Далее» → onAdvance('текст')
it('renders a Select step with default options', ...); // value { listId: ['a'] } по default
it('hides advance and disables inputs when asked', ...); // hideAdvance, readOnly
```

- [ ] **Step 2: Убедиться, что тест падает**

Run: `npx vitest run src/features/step-player`
Expected: FAIL: модуля нет.

- [ ] **Step 3: Перенести файлы**

Каталогов ещё нет: `mkdir -p src/features/step-player/components src/features/step-player/lib`. `git mv`, затем поправить импорты. В `stepValue.ts` — тип `StepValue` из `playerEngine.ts` дословно. `StepPreviewModal.tsx` берёт `StepPlayer` и `StepValue` из нового модуля; комментарий-исключение и `eslint-disable` остаются: `defaultStepValue` по-прежнему идёт из `preview`. Поведение и тексты не менять. Пространство переводов `preview` остаётся.

- [ ] **Step 4: Добавить зоны ESLint и разрешить модуль оператору**

Зоны: `src/features/step-player/**` не импортирует `src/features/preview/**`, `src/features/editor/**`, `src/operator/**`. Запрет для `src/operator/**` на `step-player` не добавлять.

- [ ] **Step 5: Проверить, что старых адресов нет**

Run: `grep -rn "features/preview/components/step-player\|preview/lib/selectDefaults" src; echo grep=$?`
Expected: пусто, `grep=1`.

- [ ] **Step 6: Прогнать всё**

Run: `npm run test:run && npm run lint && npm run build; echo chain=$?`
Run отдельно: `npx tsc -p tsconfig.app.json; echo tsc=$?`
Expected: `chain=0`; `tsc=2`, только две ошибки базы в `RoleUserGroupsPage.test.tsx`, новых нет.

- [ ] **Step 7: Обновить `PROJECT.md` и закоммитить**

Дерево, границы модулей, пункт 5 в Pitfalls, строка «New step type» в таблице навигации. Сообщение: `Этап 8: проигрыватели шагов в общем модуле features/step-player`. Хук не добавляет свои правки в файлы из `git mv`: после коммита `git status --short`, `git add src/features/step-player` и `git commit -q --amend --no-edit`, если там что-то есть. `git restore` к этим файлам не применять.

---

### Task 9: Стенд: шлюз, проверка в браузере, итог

**Files:**
- Modify (вне git): `~/Work/stand/apply-nginx-dev.sh`, копия `apply-nginx-dev.sh.before-8`
- Create (вне git): `~/Work/stand/ui-check/check-operator-entry.mjs`
- Modify (IM): `research/integration/30-local-stand.md`, `research/integration/40-plan.md`
- Add (IM): `research/integration/58-plan-stage8.md`, если контролёр ещё не закоммитил его

**Interfaces:**
- Consumes: `data-operator-entry`, `data-operator-api`, `data-api-status`, `data-api-mode` из Task 5–6; `open`, `sleep`, `shot` из `ui-check/lib.mjs`. Адрес `/im/operator/` в `.mjs` пишется строкой, из кода конфигуратора ничего не импортируется.
- Produces: строки `OK`/`FAIL`/`SKIP`, код выхода — число `FAIL`.

- [ ] **Step 1: Проверить стенд только чтением**

Run: `curl -sk -o /dev/null -w 'login %{http_code}\n' https://axxonnet.test/dev-login.html; curl -sk -o /dev/null -w 'me %{http_code}\n' https://axxonnet.test/api/v3/ac-backend/me; ss -ltn | grep -E ':(5000|5173)\b'; echo ports=$?`
Expected: `login 200`, `me 401` (облако живо, токена нет). Порта 5000 может не быть, это ожидаемо, запускать сервер нельзя. Не `200`/`401` — стоп, доложить. `make deploy`, `ensure-dev-login.sh` и `iptables` не запускать: это смена стенда или прямая запись в `ac_db`.

Затем увидеть, куда шлюз ведёт адрес без слэша. Ответ на это не наблюдался, а решение 122 на нём стоит.
Run: `curl -skI https://axxonnet.test/im | grep -iE '^(HTTP|location)'`
Expected: `301` и `Location` на `http://axxonnet.test:8082/im/` или с другим портом: то, что предсказывает решение 122, ответ записать в `progress.md`. Если иначе:

- `Location` уже `https://axxonnet.test/im/` или относительный: предсказание не подтвердилось. `absolute_redirect off;` всё равно ставить, он безвреден, итог записать.
- `200` вместо `301`: блока `/im/` на шлюзе нет, ответил портал. Вывода о редиректе этот запрос не даёт, шаг 2 проверить особенно внимательно, редирект смотреть после Step 4.
- `502` или другой код: стоп, доложить.

- [ ] **Step 2: Поднять Vite и копию прототипа**

Порта 5173 нет — запустить `~/Work/stand/run-vite.sh` в фоне, журнал `~/Work/stand/vite.log`. Затем `~/Work/stand/sync-im-proto.sh`.
Run: `curl -sk -o /dev/null -w '%{http_code}\n' https://axxonnet.test/im/; curl -sk -o /dev/null -w '%{http_code}\n' https://axxonnet.test/im-proto/prototype/server.js`
Expected: `200` и `200`. `502` на `/im/` — проход из Docker к машине пропал (30, шаг 2, п. 6): стоп, доложить, правила не менять.

- [ ] **Step 3: Добавить `location` в скрипт шлюза**

Копия: `cp ~/Work/stand/apply-nginx-dev.sh ~/Work/stand/apply-nginx-dev.sh.before-8`. Через Edit, сразу после закрывающей скобки блока `location /im/ {{ … }}` внутри строки `block`:

```nginx
        location /im/operator/ {{
            proxy_pass http://{gw}:5173;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection $connection_upgrade_im;
            proxy_set_header Host localhost:5173;
            proxy_read_timeout 1h;
            expires off;
            add_header Cache-Control "no-cache";
            absolute_redirect off;
        }}
```

В шапочный комментарий дописать строку про `/im/operator/`. `absolute_redirect off;` не убирать: без него 301 уведёт браузер на `http://axxonnet.test:8082/…` (решение 122).

- [ ] **Step 4: Применить к запущенному шлюзу**

`docker service update` на секунды перезапускает `ac_nginx`, а поток сервера гоняет свои проверки через шлюз. Запускать, когда контролёр подтвердил, что проверок стенда сейчас нет.
Run: `~/Work/stand/apply-nginx-dev.sh`, затем `curl -sk -o /dev/null -w '%{http_code} %{redirect_url}\n' 'https://axxonnet.test/im/operator?x=1'`
Expected: `test is successful` (скрипт печатает только последнюю строку `nginx -t`), строка `ac_nginx: конфиг …`; второй запрос ровно `301 https://axxonnet.test/im/operator/?x=1`. Другой адрес или порт — не идти дальше: заменить добавку на запасной путь решения 122, отдельный блок `location = /im/operator { absolute_redirect off; return 301 /im/operator/$is_args$args; }`, применить ещё раз и повторить запрос. Файлы `~/Work/axxoncloudgo` не меняются: `git -C ~/Work/axxoncloudgo status --short` пусто.

- [ ] **Step 5: Написать `check-operator-entry.mjs`**

Печатает `OK <случай>`, `FAIL <случай>: <что>`, `SKIP <случай>: <почему>`, в конце `итого ошибок: N`, `process.exit(N)`. Токены и пароль не печатает: только длину и совпало или нет. `open(path)` сам открывает целевой адрес и возвращается, когда он уже загружен, поэтому счётчики и подмена на его странице опоздали бы. Порядок каждого случая, по образцу `check-two-windows.mjs:51`: `open('/favicon.ico')` — вход на лёгкий файл; подписать счётчики `page.on('request')`, `page.on('response')` и, если нужна подмена, `page.setRequestInterception(true)`; положить подделку токена через `page.evaluate` с `localStorage.setItem`; затем `page.goto(адрес, { waitUntil: 'domcontentloaded', timeout: 60000 })`. `page.reload` не нужен: хранитель не успевает сработать между шагами. В конце случая браузер закрывается. `lib.mjs` не менять. Ожидание страницы — `waitForSelector('[data-operator-entry]:not([data-operator-entry="loading"])', { timeout: 30000 })`: первый заход Vite долгий. Два окна — две страницы одного `browser`, контекст и `localStorage` общие. На стенде работает `StrictMode` (`src/main.tsx:26`): эффект идёт дважды, `/ac-backend/me` и `/operator/session` уходят по два раза. Поэтому в случаях 6–9 точно считаются только `POST …/auth/tokens`, а `authorization` в случае 4 сверяется у последнего запроса.

| # | Случай | Как | Ожидание |
|---|---|---|---|
| 1 | вход | `/im/operator/` | `data-operator-entry="ready"`, нет `pageerror` |
| 2 | глубокая ссылка | `/im/operator/incidents/42` | то же, нет вкладки «Группы устройств» |
| 3 | адрес без слэша | `/im/operator` | итоговый адрес `/im/operator/` |
| 4 | вызов API | запрос `/api/v1/im-backend/operator/session` со страницы | заголовок `authorization` равен `Bearer` + текущий `localStorage.accessToken`. Ответ 200 и `data-operator-api="ok"` → `OK`. 502, 503, 504 и `data-operator-api="error"`, `data-operator-entry="ready"` → `SKIP сервер МИ не запущен`. Иначе `FAIL` |
| 5 | встроенный сервер | `/im/operator/?api=embedded` | `data-operator-api="ok"`, `data-api-mode="embedded"`, имя непустое, ни одного запроса к `/api/v1/im-backend/` и `/ac-backend/me` |
| 6 | обновление заранее | поддельный access `exp` через 60 с, `iat` на час раньше, настоящий refresh | ровно один `POST …/auth/tokens` с 200, токен и refresh сменились, `ready` |
| 7 | два окна | та же подделка, две страницы открыты `Promise.all` | один `POST` на обе, в обеих `ready`, пара одна |
| 8 | 401 | поддельный access с `exp` через сутки | есть `/ac-backend/me` 401, ровно один `POST`, последний `/ac-backend/me` 200, `ready` |
| 9 | конец сессии | запомнить настоящий `R0`; подделка как в случае 6, `goto`, дождаться `ready` и смены пары; затем положить поддельный access с `exp` через сутки и старый `R0`, снова `goto` | второй `POST …/auth/tokens` ответил 401 (refresh отработан, сессия жива), `session-ended`, ноль запросов `/users/logout`, в хранилище та же поддельная пара. Ответ не 401 напечатать в `FAIL`: значит, облако ведёт себя иначе, чем в решении 126 |
| 10 | только оператор | `/me` подменён: только ресурс `incidents` с действием `take` | `/im/` приводит на `/im/operator/`, `ready` |
| 11 | только конфигуратор | `/me` подменён: только ресурс `""` с действием `manage` | `/im/operator/` приводит на `/im/…`, вкладка «Группы устройств» |
| 12 | нет прав | `/me` подменён: пусто | `no-rights`, адрес не сменился |
| 13 | оба набора | настоящий `/me` | `/im/` — конфигуратор, ссылка `a[href="/im/operator/"]` есть |
| 14 | облако молчит | `/me` подменён: 503 | `cloud-unavailable` |

Случай 10–14 — ответ `/me` вида `{ user: { userId: 1, locale: 'ru' }, capabilities: { incident_manager: … } }`.

- [ ] **Step 6: Запустить проверку**

Run: `cd ~/Work/stand/ui-check && node check-operator-entry.mjs; echo code=$?`
Expected: `итого ошибок: 0`, `code=0`, 13 `OK` и случай 4 `OK` либо `SKIP`. Вход `dev-login.html` идёт без `clientId`, и поток сервера входит тем же пользователем: если случай 6, 7 или 8 неожиданно дал `session-ended`, повторить один раз, прежде чем искать причину. Если упал случай 5, сначала `git diff prototype/` в IM: `sync-im-proto.sh` копирует рабочее дерево с незакоммиченными правками потока сервера. Случай 13 на настоящем `/me` без права `manage` или случай 1 с `no-rights` значат, что права `test@axxonnet.test` на стенде пропали: стоп, доложить, `grant-im-permissions.sh` не запускать.

- [ ] **Step 7: Посмотреть снимки**

В `check-operator-entry.mjs` случай 1 и 5 делают `shot(page, 'operator-entry')` и `shot(page, 'operator-embedded')`. Открыть оба `~/Work/stand/ui-check/shots/*.png`. Expected: страница с заголовком, строка источника, на втором снимке имя оператора из набора. На первом снимке заголовок «Место оператора»: `/me` даёт язык `ru`. На втором `/me` нет, язык берётся из `navigator`, в Chrome без окна заголовок скорее `Operator workplace`, это не ошибка.

- [ ] **Step 8: Записать итог в документы IM**

Перечитать оба файла прямо перед правкой: их может менять поток сервера.

- `30-local-stand.md`: перед «Откат сборки» раздел «Шаг 9: точка входа оператора (этап 8)»: блок шлюза, запуск `run-vite.sh` и `sync-im-proto.sh`, адрес `?api=embedded`, таблица случаев с настоящими итогами, что случай 4 дал на самом деле, что удалить по окончании, откат `apply-nginx-dev.sh.before-8`.
- `40-plan.md`: строка в «Что уже готово» со ссылкой на этот план; у этапа 8 — абзац «Как проверен критерий» с заменой буквального ожидания (решение 138) и итогом уровня Г. Передача этапу 9: роутер и `Register` (решение 120), поток через `getFreshAccessToken` (решение 139), второй 401 от сервера МИ не всегда конец сессии (решение 130), клиент уже работает со встроенным сервером.

- [ ] **Step 9: Закоммитить документы IM**

```bash
cd /mnt/hgfs/VmWareShared/soul2home/IM
python3 tools/check_links.py
git add research/integration/30-local-stand.md research/integration/40-plan.md research/integration/58-plan-stage8.md
git commit -q -F .superpowers/sdd/58-plan-stage8/commit-msg.txt
```
`check_links.py` должен дать 0 нерабочих ссылок: `40-plan.md` ссылается на этот план, без файла в git на другой машине ссылка повиснет. Сообщение: `Этап 8: стенд и итог точки входа оператора`.

- [ ] **Step 10: Полный прогон и обзор ветки**

Run: `cd ~/Work/incident-manager && npm run test:run && npm run lint && npm run build; echo chain=$?`
Run отдельно: `npx tsc -p tsconfig.app.json; echo tsc=$?`
Run отдельно: `git status --short; git log --oneline 1fcfa25..HEAD`
Expected: `chain=0`; `tsc=2`, только две ошибки базы в `RoleUserGroupsPage.test.tsx`, новых нет; дерево чистое, кроме чужих правок хука, которые вернуть; 8 коммитов `Этап 8: …`, ни одного push. Затем ревью всей ветки конфигуратора, отдельным проходом по токенам: `tokens.ts`, `http.ts` и `check-operator-entry.mjs`, случаи 6–9.

---

## Самопроверка плана

- **Охват:** вторая точка входа — Task 5; `location` на шлюзе — Task 9; один пункт меню — Task 7; общий клиент, одно обновление, 401, отсутствие тайм-аута — Task 1–3; формат, JSONLogic, проигрыватели — решение 142 и Task 8; встроенный сервер — Task 6; пустая страница, доказывающая вход, права, токен и вызов API, — Task 5, 6, 9.
- **Параллельность:** задач на сервер МИ, `im-test-db` и `imdb` нет; сервер лежит — случай 4 даёт `SKIP`, остальное не зависит.
- **Предполётная проверка** (`.superpowers/sdd/58-plan-stage8/preflight.md`): C1, C2, H1, H2, M1–M3 и L1–L10 внесены в решения, задачи и тесты.
- **Имена:** `getFreshAccessToken`, `isSessionEnded`, `onSessionEnded`, `startTokenKeeper`, `readImAccess`, `prepareSession`, `operatorEntryFrom`, `configuratorEntryAction` сверены между задачами.
- **Сверено с кодом на `1fcfa25`:** 38 вызовов `fetch`, `rolldownOptions` в типах Vite 8.0.10, `htmlFallbackMiddleware`, зависимости проигрывателей, `.husky/pre-commit`, нет `/im/operator` в шлюзе, копия прототипа и `dev-login.html` лежат в `tools/compose/ui`.
- **Не проверено при написании:** Vite не запускался ни разу, стенд не трогали. База Vitest, `tsc`, линта и `prettier` снята предполётной проверкой, Task 1 её повторяет. Наблюдают первыми шагами: вторую страницу под `vite build` — Task 5, выброс ветки `DEV` — Task 6, редирект шлюза — Task 9, Step 1. Ответы облака на отработавший и просроченный refresh выведены из кода; первый проверяет случай 9, второй на стенде не проверяется, он закрыт тестом Task 1.
