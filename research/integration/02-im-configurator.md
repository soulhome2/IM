# Конфигуратор МИ (`PROJ/incident-manager`)

| | |
|---|---|
| Репозиторий | `PROJ/incident-manager` (Bitbucket) |
| Ветка | `master` |
| Коммит | `1fcfa25` (`1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0`, 2026-10-04, PR #79 CLOUD-23586) |
| Как читали | локальная копия `../incident-manager`, HEAD сверен с `1fcfa25`; только чтение |
| Дата | 2026-10-28 |

Ссылки ведут на Bitbucket на этом коммите. «Вывод:» — наше заключение по коду, «Предположение:» — то, что из кода не следует и требует проверки.

## Коротко

- Отдельное SPA: React 19 + MUI 9 + TanStack Router/Query + Zod. Vite собирает его в статику с путём `/im/`. CI собирает по zip-архиву `ui-<вендор>.zip` на каждого OEM-вендора. Своего nginx и контейнера для работы в репозитории нет, есть только контейнер для сборки.

> Поправка (второй круг, 2026-10-28): в `oem/` только `Default` — собирается и выкладывается один `ui-Default.zip`. См. [15, поправки](15-deploy-configurator.md#поправки-к-первому-кругу).

- Приложение живёт в портале по адресу: тот же origin, путь `/im/`. Это не iframe и не микрофронтенд. Шапка и навигация (вкладки) свои, шапки и меню облака внутри нет.
- Авторизация — JWT портала из `localStorage.accessToken`. Токен читается перед каждым запросом и уходит в `Authorization: Bearer`. Приложение его не разбирает и не обновляет, ответ 401 в ходе работы никак не обрабатывает.
- На входе один запрос — `GET /api/v3/ac-backend/me`: язык пользователя и дерево прав (capabilities). Приложение пускает, если в пространстве `incident_manager` есть хоть одно действие, иначе уводит на `/` портала. Других проверок прав в SPA нет.
- Все данные МИ идут только через `im-backend` (`/api/v1/im-backend/...`). Из API облака напрямую вызывается только `/me`. Клиент написан руками (fetch + Zod), не сгенерирован из OpenAPI. Реального времени нет.
- Операторской части нет. Есть только «предпросмотр» сценария — проигрыватель в браузере без сервера. JSON, который он показывает в конце, — заготовка протокола прохождения.
- Формат сценария (шаги, флаги, переходы JSONLogic с переопределёнными операторами) уже взят машиной сценариев IM. Поэтому операторская часть должна исполнять его ровно так же.
- Документация отстаёт от кода: раздел «Правила» в README и в таблицах PROJECT.md назван заглушкой, а он рабочий. README расходится с кодом и в методах API.

## Стек и выкладка

| Слой | Что | Где |
|---|---|---|
| Сборка | Vite 8, TypeScript 6, React Compiler (Babel) | [package.json][pkg], [vite.config.ts:58][vite58] |
| UI | React 19, MUI 9 (+ `@mui/x-date-pickers`), Emotion; шрифт Inter с Google Fonts | [package.json:22][pkg22], [index.html:6][html6] |
| Роутер | TanStack Router, страницы грузятся лениво, `basepath: '/im'` | [router.tsx:109][router109] |
| Данные с сервера | TanStack Query, `staleTime` 5 мин, `retry: 1` | [providers.tsx:60][prov60] |
| Состояние редактора | Zustand + Immer; формы — TanStack Form | [PROJECT.md:24][pm24] |
| Диаграмма, DnD | `@xyflow/react` + Dagre; `@dnd-kit` | [PROJECT.md:34][pm34] |
| Схемы | Zod 4: разбор всех ответов API и схема сценария | [scenario.zod.ts][zod] |
| Условия | `json-logic-js`, операторы `in`, `==`, `!=` переопределены глобально | [jsonLogic.ts:34][jl34] |
| i18n | i18next, 13 языков (те же, что локали ac-backend), 10 пространств, все словари в бандле | [locales.ts:1][loc1], [i18n/config.ts:20][i18n20] |
| Тесты | Vitest + Testing Library + jsdom, 63 файла `*.test.ts(x)`; архитектурные тесты в `tests/`; границы модулей проверяет ESLint | [PROJECT.md:325][pm325], [eslint.config.js][eslint] |

Playwright есть в devDependencies, но в коде не используется.

**UI-кит.** Чистый MUI. Тема подставляется при сборке: алиас `@/theme` указывает на `oem/<VITE_VENDOR_NAME>/theme.ts` ([vite.config.ts:54][vite54]). Тема `Default` светлая, основной цвет — стандартный синий MUI `#1976d2`, шрифт Inter, мелкие размеры полей ([oem/Default/theme.ts:3][theme3]). Тёмной темы нет. Пакетов дизайн-системы облака в зависимостях нет.
Вывод: дизайн-система у конфигуратора своя (MUI + OEM-тема), с облаком она не общая. На облако он похож, только если OEM-тема повторяет его цвета.

**Выкладка.**
- `docker/Dockerfile` — образ для сборки (node:lts-alpine + zip), а не для работы; по умолчанию запускает `npm run build` ([Dockerfile][docker]).
- `make build` = clean → docker-proxy-prepare → replace-vars (подставляет переменные Bamboo в `src/bamboo.json`) → npm-install → build-all ([Makefile:78][mk78]). Для каждого каталога в `oem/` вызывается `build-oem`: `vite build` с `VITE_VENDOR_NAME`, затем `dist/` упаковывается в `ui-<вендор>.zip` ([Makefile:48][mk48], [Makefile:61][mk61], [Makefile:72][mk72]).
- CI — Bamboo (переменные `bamboo_*`). Файл `src/bamboo.json` в коде не импортируется.
- В `package.json` есть `deploy: gh-pages` ([package.json:18][pkg18]). Предположение: это остаток, к облаку он отношения не имеет.
- Конфига nginx, правила «все пути под `/im/` → `index.html»` и Dockerfile для работы в репозитории нет. Кто раздаёт zip под `/im/` — вопрос.

> Поправка (второй круг, 2026-10-28): раздаёт Bamboo-деплой «Incident Manager UI Deploy» → `deploy-im-ui.yml`: распаковать, удалить `/data/axxoncloud/im/`, переименовать `ui` → `im`; fallback — `try_files … /im/index.html` в nginx заказчика (`IT/axxoncloud-deploy`). См. [15, п. 2](15-deploy-configurator.md#2-кто-раздаёт-ui-вендорzip-под-im-где-fallback-как-добавить-imoperator).

- При разработке Vite проксирует `/api` на `VITE_API_URL`, по умолчанию это стенд `https://bezeq-pos1.axxoncloud.com` ([vite.config.ts:40][vite40], [vite.config.ts:84][vite84]). На `/` dev-сервер отдаёт заглушку, чтобы не было бесконечного редиректа ([vite.config.ts:61][vite61]).

## Встраивание в портал

**Факты:**
- `base: '/im/'` в Vite ([vite.config.ts:82][vite82]) и `basepath: '/im'` в роутере ([router.tsx:112][router112]): все файлы сборки и маршруты лежат под `/im/`.
- Маршруты ([router.tsx:55][router55], [navItems.ts:6][nav6]):

| URL | Раздел (название в меню, ru) |
|---|---|
| `/im/` | редирект на `/im/source-groups` |
| `/im/source-groups` | «Группы устройств» |
| `/im/scenarios`, `/im/scenarios/:id`, `/im/scenarios/:id/preview` | «Сценарии»: список, редактор, предпросмотр |
| `/im/incident-rules` | «Правила» — рабочий раздел, хотя README и таблица маршрутов в PROJECT.md называют его заглушкой ([README.md:78][rd78], [PROJECT.md:145][pm145]) |
| `/im/role-user-groups` | «Группы доступа» |

- Приложение работает в том же origin, что и портал. Оно читает токен портала из `localStorage`, а `localStorage` у каждого origin свой. При отказе приложение уходит на `${location.origin}/` ([redirectToCloud.ts:2][redir2]). Все запросы к API идут по относительным путям `/api/...`.
- Нет iframe, `postMessage`, `window.parent`, module federation или общей оболочки (поиск по `src/` пуст). У приложения свой `index.html`, свой корень React ([main.tsx:34][main34]) и своя шапка `AppBar` с вкладками разделов ([AppShell.tsx:70][shell70]). Кнопки «в облако» в шапке нет.
- Как пункт МИ появляется в меню облака — в этом репозитории ничего нет.
- Тема задаётся при сборке (OEM), от портала тема не приходит. Язык берётся из `/me` (`user.locale`), поэтому совпадает с языком пользователя в облаке. До ответа `/me` используется язык браузера ([detectInitialLanguage.ts:15][det15], [bootstrapSession.ts:52][bs52]).
- В общий с порталом `localStorage` приложение пишет свои ключи без общего префикса: `im.drawerDisplayMode`, `diagram:positions:<id>`, `diagram:positions:preview:<id>` ([drawerDisplayMode.ts:1][ddm1], [ScenarioDiagram.tsx:47][sd47]).

Вывод: это отдельное приложение, которое портал открывает обычным переходом по ссылке, с полной перезагрузкой страницы. Перед приложением стоит тот же обратный прокси или шлюз, что и перед порталом (он маршрутизирует `/im/` и `/api/...`). Внутри `/im/` пользователь не видит шапку, меню и уведомления облака.
Предположение: пункт меню рисует axxoncloud-ui и показывает его по тому же признаку — capability `incident_manager`.

## Авторизация и пользователь

- **Откуда токен.** `localStorage.accessToken`, его записывает портал ([README.md:34][rd34], [PROJECT.md:13][pm13]). Ключ объявлен отдельной константой в каждом из пяти клиентов API ([acBackendUsers.ts:5][acu5], [imBackendScenarios.ts:17][sc17], [imBackendSourceGroups.ts:25][sg25], [imBackendIncidentRules.ts:40][ir40], [imBackendRoleAssignments.ts:31][ra31]).
- **Как используется.** Токен читается заново при каждом запросе (`getAccessToken()` внутри `authHeaders()`, например [imBackendScenarios.ts:28][sc28]). Если токена нет, заголовок просто не ставится. Исключение — `/me`: там без токена сразу ошибка ([acBackendUsers.ts:15][acu15]).
  Вывод: если портал перезапишет токен в том же ключе, следующий запрос возьмёт новый.
- **Обновление.** Приложение токен не обновляет: «portal owns auth» ([PROJECT.md:130][pm130], подводный камень 2 — [PROJECT.md:348][pm348]).
- **Запуск.** `Providers` ждёт `prepareAppSession()` и до этого показывает загрузку ([providers.tsx:84][prov84]). `prepareAppSession` делает `GET /api/v3/ac-backend/me` с таймаутом 10 с ([bootstrapSession.ts:34][bs34]). В пяти случаях — нет токена, ошибка, таймаут, ответ не прошёл Zod, нет права — результат `false`. Тогда в production выполняется `location.replace(origin + '/')`, а при разработке приложение всё равно открывается ([redirectToCloud.ts:13][redir13]). Сама функция никогда не бросает исключений.
- **Токен истёк посреди работы.** Обработки нет. Клиенты бросают `Error('Failed … (401)')` ([imBackendScenarios.ts:153][sc153]), Query повторяет запрос один раз, раздел показывает ошибку загрузки.
  Вывод: пользователь видит «не удалось загрузить» до перезагрузки страницы. После перезагрузки `/me` не проходит, и приложение уводит его в портал.
- **Кто пользователь.** JWT не декодируется: поиск `jwt`, `atob`, `tenant`, `organization`, `domain` по `src/` ничего не нашёл. Всё о пользователе приходит из `/me`: `user.userId` (число), `locale`, `login`, `email`, `timezone` и другие поля ([acBackendUsers.dto.ts:3][acdto3]), плюс `capabilities` в виде «пространство → ресурс → actions» ([acBackendUsers.dto.ts:18][acdto18]). Используются только `locale` и `capabilities`; `userId`, `email` и `timezone` нигде не применяются.
- **Аудит.** Колонка «Пользователь» в списках берётся из поля `updatedUser {name, surname, email}`, которое возвращает im-backend ([formatAudit.ts:28][fa28], [PROJECT.md:290][pm290]).
  Вывод: бэкенд МИ сам узнаёт пользователя по токену.
- **Мультиарендность.** В клиенте нет ни арендатора, ни домена, ни организации: ни заголовков, ни параметров.
  Вывод: арендатора определяет бэкенд — по JWT или по хосту стенда.
- **Время.** Даты в списках форматируются в часовом поясе браузера ([formatAudit.ts:2][fa2]), `timezone` из `/me` не учитывается.

## Права

- Единственная проверка — `hasIncidentManagerAccess`: в пространстве `incident_manager` хотя бы у одного ресурса есть хотя бы одно действие ([capabilities.ts:3][cap3]). Это права облака из ac-backend, а не отдельный каталог прав МИ.
- Других проверок прав нет: кто прошёл вход, видит и меняет всё ([PROJECT.md:292][pm292], [PROJECT.md:349][pm349], [PROJECT.md:432][pm432]). Какие ресурсы и действия бывают в `incident_manager`, в коде не перечислено.
- Кнопки по правам не скрываются. У сценария в ответе API есть флаг `readOnly` ([imBackendScenarios.dto.ts:49][scdto49]), но в коде он не используется.
- **Правила доступа групп пользователей** (раздел «Группы доступа», `features/role-assignments`):
  - группы пользователей берутся из `GET /im-backend/user-groups`; у группы числовой `id` ([imBackendRoleAssignments.dto.ts:10][radto10]);
  - привязка (access rule) — четыре необязательных поля: группа источников, тип источника, источник, тип события; хотя бы одно должно быть заполнено ([imBackendRoleAssignments.dto.ts:47][radto47]);
  - внутри привязки условия соединяются по И, между привязками — по ИЛИ ([ru/roleAssignments.json:20][raru20]);
  - запись: `POST /access-rules {userGroupID, rules[]}`, `PUT /access-rules/{guid}`, `DELETE /access-rules` с массивом guid в теле ([imBackendRoleAssignments.ts:91][ra91]); изменения сохраняются автоматически ([PROJECT.md:250][pm250]).

Вывод: привязки задают, какие источники и события видит группа пользователей, то есть какие инциденты попадут оператору. Конфигуратор их только хранит, применять их должен бэкенд.
Предположение: `user-groups` — группы пользователей облака, которые бэкенд МИ отдаёт как есть: `id` числовой, как `userId` в `/me`.

## Какие API вызывает

Все пути ниже, кроме первой строки, начинаются с `/api/v1/im-backend`.

| Сервис | Эндпоинт | Зачем | Где |
|---|---|---|---|
| ac-backend (облако) | `GET /api/v3/ac-backend/me` | пользователь, язык, права | [acBackendUsers.ts:21][acu21] |
| im-backend | `GET /scenarios` | список сценариев вместе с полным `script` | [imBackendScenarios.ts:151][sc151] |
| im-backend | `POST /scenarios` `{name, description}` | создать (ответ `{guid, name, description}`) | [imBackendScenarios.ts:186][sc186] |
| im-backend | `PATCH /scenarios/{guid}` `{name, description, script}` | сохранить | [imBackendScenarios.ts:171][sc171] |
| im-backend | `DELETE /scenarios/{guid}` | удалить | [imBackendScenarios.ts:244][sc244] |
| im-backend | `GET /sources`, `GET /sources/{guid}` | все источники; один источник с его группами и путями к ним | [imBackendSourceGroups.ts:84][sg84], [imBackendSourceGroups.ts:115][sg115] |
| im-backend | `GET /sources`, `/sources/types`, `/sources/event-types` с `?byGroupGuid&byTypeGuid&bySourceGuid&byEventTypeGuid` | варианты для условий правил и привязок | [imBackendIncidentRules.ts:135][ir135] |
| im-backend | `GET /sources/groups/tree?parentGroupGuid=`, `GET /sources/groups/tree/search?query=` | дерево групп по уровням, поиск | [imBackendSourceGroups.ts:59][sg59], [imBackendSourceGroups.ts:94][sg94] |
| im-backend | `POST /sources/groups`, `PATCH`/`DELETE /sources/groups/{guid}` | группы источников | [imBackendSourceGroups.ts:133][sg133] |
| im-backend | `POST`/`DELETE /sources/groups/{guid}/memberships` `{sourceGuids}`, `POST /sources/groups/memberships/move` | состав групп | [imBackendSourceGroups.ts:224][sg224] |
| im-backend | `GET`/`POST /incidents/rules`, `PATCH`/`DELETE /incidents/rules/{guid}` | правила инцидентов | [imBackendIncidentRules.ts:95][ir95], [imBackendIncidentRules.ts:194][ir194] |
| im-backend | `GET`/`POST /incidents/conditions`, `PUT`/`DELETE /incidents/conditions/{guid}` | условия правил | [imBackendIncidentRules.ts:105][ir105], [imBackendIncidentRules.ts:251][ir251] |
| im-backend | `GET /priorities` | справочник приоритетов | [imBackendIncidentRules.ts:115][ir115] |
| im-backend | `GET /user-groups` | группы пользователей | [imBackendRoleAssignments.ts:71][ra71] |
| im-backend | `GET`/`POST`/`DELETE /access-rules`, `PUT /access-rules/{guid}` | правила доступа | [imBackendRoleAssignments.ts:81][ra81] |

**Что важно:**
- Напрямую к API облака за камерами, устройствами, сайтами, доменами или пользователями приложение не ходит, всё идёт через im-backend. Видео, кадров, карт и событий в реальном времени нет.
- Отдельного `GET /scenarios/{guid}` нет: редактор ищет сценарий в полном списке ([useScenarios.ts:60][us60]). Импорт и копия делаются на клиенте как `POST` + `PATCH` ([imBackendScenarios.ts:229][sc229]). README пишет про `PUT` и отдельные эндпоинты ([README.md:218][rd218]), а также про `memberships/:sourceGuid` ([README.md:232][rd232]) — это расходится с кодом.
- Странности контракта: при создании правила поле со сценариями называется `scenarios`, при изменении — `scenarioGuids` ([imBackendIncidentRules.dto.ts:108][irdto108]). Бэкенд на Go опускает пустые поля (omitempty), поэтому `name` может прийти пустым, и такие строки списка нужно сохранять ([PROJECT.md:364][pm364]). `PATCH` группы может вернуть пустое тело ([imBackendSourceGroups.ts:189][sg189]).
- Клиент написан руками: в каждой фиче свой `fetch` и свой `authHeaders()`, ответы проверяются Zod, ошибки разбора пишутся в консоль ([PROJECT.md:288][pm288]). Из ошибки достаётся текст полей `Message`, `message` или `key` ([imBackendSourceGroups.ts:44][sg44]). OpenAPI в репозитории нет. DTO источников продублированы в `incident-rules` и `role-assignments`.
- Реального времени нет: WebSocket и EventSource не используются. Свежесть данных держится за счёт `refetchOnMount: 'always'` у списка сценариев и `staleTime` 5 мин.

## Данные, которые нужны оператору

**Сценарий** ([scenario.ts:18][st18]; схема — [scenario.zod.ts:21][zod21]):
- Структура `{scenario: {id, name, description, version, createdAt, updatedAt, initialStep}, steps[]}`. Типов шагов семь: `Message`, `Comment`, `Datetime`, `Image`, `RadioButton`, `Select`, `Checkbox`. У шага есть флаги `revisitable`, `multitasking`, `report`, `finish` и переходы `transitions.default {goto, macro}` + `rules[] {condition, goto, macro}`.
- Правила переходов бывают только у `RadioButton`, `Select` и `Checkbox`, у остальных типов они удаляются ([PROJECT.md:169][pm169]). Данные для условия: `RadioButton` → `{value}`, `Select` → `{<listId>: [ids]}`, `Checkbox` → `{selected: [ids]}` ([jsonLogic.ts:89][jl89]).
- Порядок перехода: на шаге `finish` сценарий заканчивается, иначе срабатывает первое подошедшее непустое правило, иначе `default.goto` ([playerEngine.ts:15][pe15]). Операторы `in`, `==`, `!=` переопределены для массивов ([jsonLogic.ts:34][jl34]).
  Вывод: исполнитель оператора обязан считать так же, иначе ветки разойдутся с предпросмотром.
- `macro {name, args}` в редакторе — просто текстовое поле ([MacroField.tsx:11][mf11]), проигрыватель его не исполняет.
- `multitasking` и `report` хранятся, но в проигрывателе не используются. Подпись `multitasking` в редакторе закомментирована ([StepBasicTab.tsx:21][sbt21]).
- У `Image.source` четыре значения: `camera`, `map`, `operator`, `fixed`. Предпросмотр показывает картинку только для `fixed`, для остальных — иконку ([ImageStepPlayer.tsx:74][isp74]).
- Номер `version` в сценарии есть, но кто и когда его увеличивает — по клиенту не видно: при сохранении клиент отправляет то, что у него было.
- Машина сценариев IM с 2026-10-19 приведена к формату этого редактора ([Specification/Scenario_machine/ORIGIN.md](../../Specification/Scenario_machine/ORIGIN.md)), так что формат у них общий.
- **Протокол прохождения.** В конце предпросмотра собирается JSON `{scenario: {id, version}, finishedAt, history: [{stepId, startedAt, completedAt, userId: null, value?}]}` ([FinishPreviewScreen.tsx:110][fps110]).
  Предположение: это черновик будущего результата сценария в инциденте; `userId` пока не заполняется.
- Поведение навигации в предпросмотре: шаг без `revisitable` после «Далее» замораживается, при смене ветки хвост истории отбрасывается, черновые ответы сохраняются ([playerTypes.ts:4][pt4], [playerNavigation.ts][pn]). Это уже готовое решение для оператора. Его надо сверить с машиной сценариев IM.

**Правило инцидента** ([imBackendIncidentRules.dto.ts:69][irdto69]):
- `IncidentRule {guid, name, priorityGuid, scenarios: guid[], updatedAt, updatedUser}`;
- `IncidentCondition {guid, incidentRuleGuid, groupGuid?, sourceTypeGuid?, sourceGuid?, sourceEventTypeGuid?}`;
- `Priority {guid, name, value}`.

Вывод: правило говорит, какие события каких источников порождают инцидент, с каким приоритетом и с какими сценариями (их может быть несколько). Оператору из этого нужны приоритет (название + число для сортировки) и сценарии инцидента.

**Источники и группы** ([imBackendSourceGroups.dto.ts:17][sgdto17]):
- `Source {guid, uid, name, type {guid, name, uid}, agent {guid, name}, isOnline?}`. Группы образуют дерево. Один источник может входить в несколько групп: `GET /sources/{guid}` возвращает `groups[{group, path}]` ([imBackendSourceGroups.dto.ts:44][sgdto44]).
- Оператору это нужно, чтобы показать, где произошло событие (имя, группа, путь), отметить, в сети ли источник, и фильтровать очередь.
  Предположение: `uid` и `agent` — идентификаторы устройства и сервера в облаке, через них можно получить видео и кадр. Нужно проверить.

**Права доступа** — см. «Права»: по ним бэкенд отбирает, какие инциденты видит оператор.

## Есть ли что-то операторское

- Очереди, карточки, взятия в работу, истории инцидентов и эндпоинтов `/incidents` нет. Есть только `/incidents/rules` и `/incidents/conditions`. Поиск `operator` и `оператор` находит только источник изображения «оператор» и оператор в условиях.
- Заделы:
  - движок предпросмотра — `resolveNextStep`, `playerNavigation`, по одному `StepPlayer` на каждый из 7 типов шагов ([features/preview][prev]): это готовые формы ввода для шагов сценария;
  - формат протокола прохождения (выше);
  - флаги шага, рассчитанные на оператора: `revisitable` («Оператор может снова открыть этот шаг», [ru/editor.json:44][edru44]), `multitasking`, `report`;
  - источники изображения `camera`, `map` и `operator`.
- Ограничение: правила импорта (ESLint) запрещают брать `preview` откуда-либо, кроме `StepPreviewModal.tsx`, а домен — только через `@/shared/scenario` ([PROJECT.md:95][pm95]).
  Вывод: без перестройки границ модулей взять проигрыватель в другую фичу нельзя.

> Поправка (второй круг, 2026-10-28): ESLint запрещает импорт `preview` только из `editor` и `scenarios`; `app` и новые фичи могут импортировать его уже сейчас. Зоны «домен только через `@/shared/scenario`» не работают (перепутаны `target`/`from`), зон `diagram` в конфиге нет. См. [15, п. 4.2](15-deploy-configurator.md#42-запрет-eslint-на-preview--что-на-самом-деле-запрещено).

## Что повторить для операторской части

**Повторить (вывод):**
1. Способ встраивания: SPA на своём пути в том же origin, относительные `/api/...`. Это либо новый раздел внутри `/im/`, либо соседнее приложение (например, `/im-operator/`). Решение — после ответа облака про меню и раздачу файлов.
2. Вход: `/me` → проверка прав → при отказе уход в портал; язык берётся из `/me`; есть таймаут, функция не бросает исключений.
3. Токен читать перед каждым запросом и не хранить у себя.
4. Тот же стек: React + MUI + TanStack Query + Zod, OEM-тема через `@/theme`, 13 языков. Тогда конфигуратор и операторская часть будут выглядеть и собираться одинаково (Makefile/Bamboo/zip по вендорам).
5. Формат сценария и JSONLogic с теми же операторами — не переписывать, а взять тот же код. Лучше вынести `shared/scenario`, `jsonLogic` и проигрыватели шагов в общий пакет или держать оператора в этом же репозитории.
6. Zod-разбор ответов, устойчивый к omitempty (пустые `name`, `null` вместо массивов).

**Мешает и хрупко:**
1. Нет обработки 401 и обновления токена ([PROJECT.md:348][pm348]). Конфигуратору это терпимо, оператору со сменой 8–12 часов — нет. Нужен перехват 401: перечитать токен, а если не помогло — аккуратно уйти в портал, не теряя введённые ответы. Это надо согласовать с порталом.
2. Права слишком грубые: всё пространство `incident_manager` целиком ([PROJECT.md:349][pm349]). Администратору и оператору нужны разные действия.
3. Нет реального времени. Очереди нужен push (WebSocket или SSE) или частый опрос, образца в конфигураторе нет.
4. Внутри `/im/` нет шапки и уведомлений облака. Для оператора нужно решить, допустимо ли это.
5. Шрифт Inter грузится с `fonts.googleapis.com` ([index.html:8][html8]). В закрытой сети он не загрузится.
6. Переопределения JSONLogic глобальны и ставятся при загрузке модуля ([PROJECT.md:353][pm353]). В общем пакете они затронут любое другое использование `json-logic-js` на странице.
7. Раздача файлов и fallback на `index.html` настроены вне репозитория, как именно — неизвестно.

> Поправка (второй круг, 2026-10-28): отвечено: `deploy-im-ui.yml` и `location /im` в `IT/axxoncloud-deploy`. См. [15, п. 2](15-deploy-configurator.md#2-кто-раздаёт-ui-вендорzip-под-im-где-fallback-как-добавить-imoperator).

8. Код клиентов продублирован: `authHeaders` в пяти файлах, DTO источников в двух фичах ([PROJECT.md:429][pm429]). Не копировать, а сделать общий HTTP-клиент.
9. Нет `GET /scenarios/{guid}`, сценарий достаётся из полного списка. Оператору нужна конкретная версия сценария инцидента, поэтому нужен отдельный эндпоинт.
10. `timezone` из `/me` не используется. Для времени событий у оператора это важно.
11. Документации нельзя верить на слово. Раздел «Правила» в README и таблицах PROJECT.md назван заглушкой; README расходится с кодом в методах API. Нормативная спецификация границ модулей `docs/superpowers/specs/2026-05-14-module-boundaries-design.md`, на которую ссылаются AGENTS.md и PROJECT.md, в git на этом коммите отсутствует: `docs/` в `.gitignore`, в git есть только один файл про группы источников.

> Поправка (второй круг, 2026-10-28): спецификации границ модулей нет в рабочем дереве, но она есть в истории: `git show 541f9d9^:docs/superpowers/specs/2026-05-14-module-boundaries-design.md`. См. [15, п. 4.2](15-deploy-configurator.md#42-запрет-eslint-на-preview--что-на-самом-деле-запрещено).

12. Ключи в общем `localStorage` без общего префикса.

## Открытые вопросы

К облаку (axxoncloud-ui / axxoncloudgo) — вглубь не ходили:
1. Как пункт «Incident Manager» попадает в меню портала и по какому признаку показывается? Как добавить пункт для оператора?
2. Кто раздаёт `ui-<вендор>.zip` под `/im/` — nginx портала, отдельный контейнер? Где настроен fallback на `index.html`?

> Поправка (второй круг, 2026-10-28): отвечено, см. [15, п. 2](15-deploy-configurator.md#2-кто-раздаёт-ui-вендорzip-под-im-где-fallback-как-добавить-imoperator).

3. Как и когда портал обновляет `localStorage.accessToken`, какой срок жизни у токена? Чего портал ждёт от встроенного приложения при истечении — ухода на `/` или какого-то события?
4. Что лежит в claims JWT: пользователь, домен или организация, роль? По чему ac-backend и im-backend определяют арендатора?
5. Какие ресурсы и действия есть в `incident_manager`, где они назначаются (роли облака)? Можно ли завести отдельные действия для оператора?
6. Можно ли показать шапку и меню облака внутри приложения МИ? Есть ли общая дизайн-система или OEM-темы облака, к которым стоит привязаться?

К бэкенду МИ (подробно — в 03-im-server.md):

7. Применяет ли im-backend правила доступа (`access-rules`) при выдаче инцидентов оператору?
8. Растёт ли `version` сценария при `PATCH`, хранятся ли старые версии, можно ли получить сценарий по guid и версии?
9. Что значат для оператора `multitasking`, `report` и `macro`? Кто исполняет макросы?
10. У правила может быть несколько сценариев — как оператор выбирает, какой запускать?
11. Есть ли или планируется канал реального времени для инцидентов?
12. Откуда берутся `user-groups` (из облака?) и как пользователь привязан к группе?

По самому конфигуратору:

13. Операторская часть — раздел этого же SPA (общие проигрыватель, тема, сборка) или отдельный бандл?
14. Для чего флаг `readOnly` у сценария в ответе API, если в UI он не используется?

[pkg]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/package.json?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0
[pkg18]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/package.json?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#18
[pkg22]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/package.json?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#22
[html6]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/index.html?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#6
[html8]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/index.html?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#8
[vite40]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/vite.config.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#40
[vite54]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/vite.config.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#54
[vite58]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/vite.config.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#58
[vite61]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/vite.config.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#61
[vite82]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/vite.config.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#82
[vite84]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/vite.config.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#84
[theme3]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/oem/Default/theme.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#3
[docker]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/docker/Dockerfile?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0
[mk48]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/Makefile?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#48
[mk61]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/Makefile?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#61
[mk72]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/Makefile?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#72
[mk78]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/Makefile?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#78
[eslint]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/eslint.config.js?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0
[rd34]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/README.md?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#34
[rd78]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/README.md?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#78
[rd218]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/README.md?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#218
[rd232]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/README.md?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#232
[pm13]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/PROJECT.md?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#13
[pm24]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/PROJECT.md?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#24
[pm34]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/PROJECT.md?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#34
[pm95]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/PROJECT.md?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#95
[pm130]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/PROJECT.md?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#130
[pm145]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/PROJECT.md?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#145
[pm169]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/PROJECT.md?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#169
[pm250]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/PROJECT.md?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#250
[pm288]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/PROJECT.md?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#288
[pm290]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/PROJECT.md?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#290
[pm292]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/PROJECT.md?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#292
[pm325]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/PROJECT.md?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#325
[pm348]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/PROJECT.md?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#348
[pm349]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/PROJECT.md?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#349
[pm353]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/PROJECT.md?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#353
[pm364]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/PROJECT.md?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#364
[pm429]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/PROJECT.md?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#429
[pm432]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/PROJECT.md?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#432
[main34]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/main.tsx?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#34
[prov60]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/app/providers.tsx?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#60
[prov84]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/app/providers.tsx?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#84
[bs34]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/app/bootstrapSession.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#34
[bs52]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/app/bootstrapSession.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#52
[redir2]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/app/redirectToCloud.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#2
[redir13]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/app/redirectToCloud.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#13
[router55]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/app/router.tsx?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#55
[router109]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/app/router.tsx?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#109
[router112]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/app/router.tsx?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#112
[shell70]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/app/AppShell.tsx?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#70
[nav6]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/shared/navigation/navItems.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#6
[acu5]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/shared/api/ac-backend/acBackendUsers.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#5
[acu15]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/shared/api/ac-backend/acBackendUsers.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#15
[acu21]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/shared/api/ac-backend/acBackendUsers.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#21
[acdto3]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/shared/api/ac-backend/acBackendUsers.dto.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#3
[acdto18]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/shared/api/ac-backend/acBackendUsers.dto.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#18
[cap3]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/shared/api/ac-backend/capabilities.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#3
[loc1]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/shared/api/ac-backend/locales.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#1
[i18n20]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/shared/i18n/config.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#20
[det15]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/shared/i18n/detectInitialLanguage.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#15
[raru20]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/shared/i18n/locales/ru/roleAssignments.json?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#20
[edru44]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/shared/i18n/locales/ru/editor.json?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#44
[ddm1]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/shared/lib/drawerDisplayMode.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#1
[fa2]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/shared/lib/formatAudit.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#2
[fa28]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/shared/lib/formatAudit.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#28
[jl34]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/shared/lib/jsonLogic.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#34
[jl89]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/shared/lib/jsonLogic.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#89
[st18]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/shared/types/scenario.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#18
[zod]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/shared/schema/scenario.zod.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0
[zod21]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/shared/schema/scenario.zod.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#21
[sc17]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/features/scenarios/api/imBackendScenarios.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#17
[sc28]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/features/scenarios/api/imBackendScenarios.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#28
[sc151]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/features/scenarios/api/imBackendScenarios.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#151
[sc153]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/features/scenarios/api/imBackendScenarios.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#153
[sc171]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/features/scenarios/api/imBackendScenarios.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#171
[sc186]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/features/scenarios/api/imBackendScenarios.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#186
[sc229]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/features/scenarios/api/imBackendScenarios.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#229
[sc244]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/features/scenarios/api/imBackendScenarios.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#244
[scdto49]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/features/scenarios/api/imBackendScenarios.dto.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#49
[us60]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/features/scenarios/api/useScenarios.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#60
[sg25]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/features/source-groups/api/imBackendSourceGroups.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#25
[sg44]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/features/source-groups/api/imBackendSourceGroups.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#44
[sg59]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/features/source-groups/api/imBackendSourceGroups.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#59
[sg84]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/features/source-groups/api/imBackendSourceGroups.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#84
[sg94]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/features/source-groups/api/imBackendSourceGroups.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#94
[sg115]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/features/source-groups/api/imBackendSourceGroups.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#115
[sg133]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/features/source-groups/api/imBackendSourceGroups.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#133
[sg189]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/features/source-groups/api/imBackendSourceGroups.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#189
[sg224]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/features/source-groups/api/imBackendSourceGroups.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#224
[sgdto17]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/features/source-groups/api/imBackendSourceGroups.dto.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#17
[sgdto44]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/features/source-groups/api/imBackendSourceGroups.dto.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#44
[ir40]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/features/incident-rules/api/imBackendIncidentRules.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#40
[ir95]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/features/incident-rules/api/imBackendIncidentRules.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#95
[ir105]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/features/incident-rules/api/imBackendIncidentRules.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#105
[ir115]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/features/incident-rules/api/imBackendIncidentRules.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#115
[ir135]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/features/incident-rules/api/imBackendIncidentRules.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#135
[ir194]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/features/incident-rules/api/imBackendIncidentRules.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#194
[ir251]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/features/incident-rules/api/imBackendIncidentRules.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#251
[irdto69]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/features/incident-rules/api/imBackendIncidentRules.dto.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#69
[irdto108]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/features/incident-rules/api/imBackendIncidentRules.dto.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#108
[ra31]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/features/role-assignments/api/imBackendRoleAssignments.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#31
[ra71]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/features/role-assignments/api/imBackendRoleAssignments.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#71
[ra81]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/features/role-assignments/api/imBackendRoleAssignments.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#81
[ra91]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/features/role-assignments/api/imBackendRoleAssignments.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#91
[radto10]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/features/role-assignments/api/imBackendRoleAssignments.dto.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#10
[radto47]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/features/role-assignments/api/imBackendRoleAssignments.dto.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#47
[mf11]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/features/editor/components/transitions/MacroField.tsx?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#11
[sbt21]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/features/editor/components/StepBasicTab.tsx?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#21
[sd47]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/features/editor/components/ScenarioDiagram.tsx?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#47
[prev]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/features/preview?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0
[pe15]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/features/preview/lib/playerEngine.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#15
[pt4]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/features/preview/lib/playerTypes.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#4
[pn]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/features/preview/lib/playerNavigation.ts?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0
[isp74]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/features/preview/components/step-player/ImageStepPlayer.tsx?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#74
[fps110]: https://src.axxonsoft.dev/bitbucket/projects/PROJ/repos/incident-manager/browse/src/features/preview/components/FinishPreviewScreen.tsx?at=1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0#110
