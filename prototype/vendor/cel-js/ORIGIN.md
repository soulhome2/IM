# Копия cel-js

Выражения CEL машины инцидента ([CEL.md](../../../Specification/Workflow_machine/CEL.md), ARCH-07) вычисляет библиотека `@marcbachmann/cel-js`. Она написана модулями ES, а прототип открывается и с диска (`file://`), где браузер модули не загружает. Поэтому здесь — та же библиотека, собранная esbuild в один обычный скрипт без изменений кода: он кладёт `Environment` и `parse` в `window.CEL`.

| Что | Значение |
|---|---|
| Пакет | `https://registry.npmjs.org/@marcbachmann/cel-js/-/cel-js-8.0.0.tgz`, версия 8.0.0 от 2026-07-07, скачан 2026-10-21 |
| sha256 архива | `906a27e01afbdc175a95197d45ebc0ab00f733517ffd5b934e3f066230cc6d5f` |
| Лицензия | MIT, [LICENSE](LICENSE) — из архива |
| Сборка | esbuild 0.28.2: `esbuild entry.mjs --bundle --format=iife --target=es2020 --outfile=cel.js` |
| sha256 `cel.js` | `1ea6830d9b352827898c87e6eaa6621945886c0ba6fb85831b86f02a95c1114e` |

`entry.mjs` сборки — рядом с распакованным архивом (`package/`):

```js
import { Environment, parse } from './package/lib/index.js'
window.CEL = { Environment, parse }
```

**Новая версия.** Скачать архив (`npm pack @marcbachmann/cel-js@<версия>`), распаковать, собрать той же командой, заменить `cel.js` и `LICENSE`, записать версию и оба хэша сюда. Затем `node tools/check_cel.mjs`, самопроверка и тесты API. Версия — не моложе двух недель.

Отличия cel-js от спецификации CEL, которые задевают машину, — в CEL.md, раздел «Библиотека».
