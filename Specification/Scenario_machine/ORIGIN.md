# Происхождение машины сценариев

Машина сценариев перенесена в IM из соседних репозиториев 2026-10-19 (ARCH-06, [план](../../reviews/2026-10-19/plan.md)). С этого момента источник — IM, соседние репозитории — только для справки. Что изменилось после переноса — в [CHANGELOG.md](CHANGELOG.md).

## Откуда

| Репозиторий | Коммит | Дата коммита | Что взято |
|---|---|---|---|
| `incident-manager-dsl` | `bbe12d597bc24962a4958f964969a66502b9a89d` | 2026-05-13 | спецификация, схема, примеры — как есть; исполнитель runner-web — переписан на JS |
| `incident-manager` | `1fcfa25880e6cc6daeabcd1fe57dad2b78e57ee0` | 2026-10-04 | ничего: формат продукта сверен и не перенесён (решение ARCH-06 в1) |
| `incident-manager-server` | `b743797a38daeb3beaa44ef901b26c3ce924290f` | 2026-10-13 | ничего: из контракта взяты идентичность и версия сценария, ссылка инцидента на версию и `scenarioResult` (`api/im/backend.openapi.yaml`) |

Файлы взяты из коммита (`git show <коммит>:<путь>`), а не из рабочей копии: в рабочей копии `incident-manager-dsl` переводы строк CRLF, в коммите — LF.

## Скопированы как есть

Совпадают с исходником байт в байт, кроме отступлений из [CHANGELOG.md](CHANGELOG.md): тип шага `Button` переименован в `Message` (схема — `MessageStep`) в спецификации, схеме и примерах. Хэши ниже — исходника. Не правятся: отступление от исходника — только по решению и строкой в CHANGELOG.

| Файл в IM | Путь в `incident-manager-dsl` | sha256 |
|---|---|---|
| `dsl-v1-draft.md` | `dsl-v1-draft.md` | `47b7c0e49602a3216286c7c1936528c623153e48f13b05aa833a4e2c2efede43` |
| `dsl-v1-schema.json` | `dsl-v1-schema.json` | `26bab84c41ee64c594b7f2292b01d3e97130a39bc2e1a0a2f1f9b0d7ad1cd465` |
| `examples/01-perimeter-alarm.json` | то же | `cda5f3ec2708207f70f50806d52de7012a380f5c7f84efb344e82e051596b941` |
| `examples/02-fire-alarm.json` | то же | `263cc84d552c45c7f880f947a20e6dfaa1d369ce665ceb09d5ca07af3fae197a` |
| `examples/03-access-control-violation.json` | то же | `f4f1cb9078abd8114bcba8d70317d4eab9028d6ef187fcbe1bbb5c86161b7e70` |
| `examples/04-suspicious-object.json` | то же | `8493de6300e186ccf21eb295cfb7254d274f2516f7457f0fe3f0fbba62f03ab1` |
| `examples/05-camera-offline.json` | то же | `a04687560bcce41783c6dc440ac1ceff5d77fc1b07e3adc05eae77f8d72e154b` |
| `examples/06-fight-aggressive-behavior.json` | то же | `2f2412b786231cf0ba462cd7b63f4478702244b6d9dac94f58d1d796aaab0e93` |
| `examples/07-restricted-area-breach.json` | то же | `1babc5608b3bbba682722856d2f612a976b0c5d99514f2a442bcf52a9979dda9` |
| `examples/08-evacuation-drill.json` | то же | `f3bdf7d32cf47d90cc00fb9b2671827f3be90094348ddc949a541471108cef96` |
| `examples/09-camera-sabotage-suspicion.json` | то же | `f2c1f9ae08b43349f274612d2f3ece1680a9d33b528d2de7997bc564c7184aa3` |
| `examples/10-mass-event-protocol.json` | то же | `6d66eeefbab8e49c3b7991b1fc61eb4f8622e8677517ea7080a148e796b64e4b` |
| `examples/showcase/00-primitives.json` | то же | `235db0b10399051e4d757e57dbf8ca302f5ab5ac5ea9aaed6c3e63ff4f34039f` |
| `examples/architecture/A1-minimal-valid-scenario.json` | то же | `e73c1d46c6e26a26b8ff2142f08871ce42e431208a2a2a739adab0c29f0d1341` |
| `examples/architecture/A5-anti-patterns/bad-1-schema-broken-goto.json` | то же | `4f1dbc11abd77f6a5dade142b62d2f033ff274d7240954e936ce8c326dd0b25d` |
| `examples/architecture/A5-anti-patterns/bad-3-unknown-action.json` | то же | `75e91aef45409a1ad6c4671d78c4672984086f9139429b378707d188e28a8e2d` |
| `examples/architecture/A5-anti-patterns/bad-4-numeric-option-ids.json` | то же | `f601aa25bce6f5b481dfc0cfaba24933b8cfba3a07724ed623b776a778febf9c` |
| `examples/architecture/A5-anti-patterns/bad-5-deeply-nested-rules.json` | то же | `a40ac62eb1408039017447c301af0e998c19376d65726e017b88530954848c42` |

## Переписаны или заменены

Исходник на TypeScript; прототип IM — обычный JS без сборки (решение ARCH-06 в2). Перенос сверяется с исходником по этим хэшам.

| Исходник в `incident-manager-dsl` | sha256 | В IM |
|---|---|---|
| `runner-web/src/engine/stateMachine.ts` | `7193c59830621ac8ef0e06d18ecac53da9a5f17d14be80e3915a6c34d0f3d11d` | исполнитель [`prototype/scenario.js`](../../prototype/scenario.js), тесты — [`tests/scenario.html`](../../tests/scenario.html) |
| `runner-web/src/engine/transitionEvaluator.ts` | `2847240696c53da0e0a781db1cc830e519b1167fa02379cddd1f2b5cb17dc1e0` | там же |
| `runner-web/src/types/dsl.ts` | `2a0973e0c7d4516ce264a944c22fe54fec4ba7f71e73cf141457f1e31853e40e` | схема прогона `ScenarioResult` в `openapi.json` вместе с разделом 9 спецификации (ARCH-06.4, решение в17) |
| `runner-web/src/engine/validateScenario.ts` | `ba19ad4dac475d8a7c1f72949ba183f0a102d5744ced40b2ff188cff4d958388` | проверка `tools/check_scenarios.py` (ARCH-06.3) |
| `runner-web/scripts/validate-examples.mjs` | `47a96fb3d2fb3756ff89fff65c88fb47cf2f9b648871c5c873b7192466921757` | там же |

## Копия json-logic-js

Условия JSONLogic в runner-web вычисляет библиотека `json-logic-js` 2.0.5 (`runner-web/package-lock.json`). В IM — её копия той же версии, без изменений (решение в3): `prototype/vendor/json-logic-js/`.

| Что | Значение |
|---|---|
| Пакет | `https://registry.npmjs.org/json-logic-js/-/json-logic-js-2.0.5.tgz`, скачан 2026-10-19 |
| Целостность пакета | `sha512-rTT2+lqcuUmj4DgWfmzupZqQDA64AdmYqizzMPWj3DxGdfFNsxPpcNVSaTj4l8W2tG/+hg7/mQhxjU3aPacO6g==` — совпадает с `package-lock.json` runner-web |
| `logic.js` | sha256 `73a6dc521e8990c2eed330dcfdb35605d7e1065a6e19d26673cb7ad4cd09d881` |
| `LICENSE` (MIT, Jeremy Wadhams) | sha256 `453a163c949bf67cbed175f93d6a57c11df65086dd8e32ea490179cef4033cdf` |

Библиотека знает больше операторов, чем разрешает спецификация (раздел 7); в сценариях МИ — только разрешённые, это проверяет `tools/check_scenarios.py`.

## Не перенесены

| Что | Почему |
|---|---|
| `examples/*.layout.json`, `examples/architecture/A7-diff-readability/` | раскладка узлов редактора и иллюстрация читаемых диффов — не машина |
| `examples/README.md`, `examples/architecture/README.md` | заменены описанием примеров в [README.md](README.md) |
| `runner-web` (интерфейс), `configurator-web` | интерфейс прохождения в IM — карточка прототипа; редактор сценариев — вне IM |
| `runner-web/src/engine/envelope.ts` | выгрузка результата из демо-runner, в IM не нужна |
| `server-analysis.md`, `proposal-versioning.md`, `market-research.md`, обзоры конкурентов | обоснования и предложения команде сервера; на них ссылается спецификация — читать в исходном репозитории |

## Как подтянуть изменения исходника

1. В исходном репозитории: `git diff bbe12d5..<новый коммит> -- dsl-v1-draft.md dsl-v1-schema.json examples runner-web/src/engine runner-web/src/types`.
2. Файлы «как есть» — заменить из нового коммита (`git show`), обновить хэши выше.
3. Изменения исполнителя — перенести руками в `prototype/scenario.js`, обновить хэши.
4. Записать строку в [CHANGELOG.md](CHANGELOG.md) и новый коммит-источник в таблицу «Откуда»; прогнать проверки (README, «Проверки»).
