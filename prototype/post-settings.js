/* Настройки поста поверх машины (решение 2026-11-15). Машина задаёт устройство справочников причин
   (reasonCatalogs: поле, обязательность, системные причины) и причин перерыва (session.breakReasons), пункты заводит администратор поста.
   Стартовый набор настроек поста — Specification/Workflow_machine/post-defaults.json (window.IM_POST_DEFAULTS,
   prototype/post-defaults.js): его получает новый пост и один раз — существующий, по правилу §20 (withDefaults).
   Версий настроек в прототипе нет (§17): пост стенда — новый пост, его настройки — стартовый набор; раздел settings
   эталонного набора, если появится, — опубликованные настройки существующего поста. Пункты справочника идут после
   пунктов машины, остальное в машине не меняется. Действующая машина прототипа — window.IM_WORKFLOW после этого
   файла, машина без настроек поста — IMPostSettings.base; его же подключают инструменты Node (vm). */
(() => {
  const root = typeof window !== "undefined" ? window : globalThis;
  function apply(W, settings) {
    const catalogs = (settings && settings.reasonCatalogs) || {};
    const ids = Object.keys(catalogs).filter((k) => !k.startsWith("$"));
    // Причины перерыва (session.breakReasons) — тоже пункты поста: в машине список пуст
    const breaks = (settings && settings.session && settings.session.breakReasons) || [];
    if (!ids.length && !breaks.length) return W;
    const out = JSON.parse(JSON.stringify(W));
    breaks.forEach((r) => {
      if (out.session.breakReasons.some((x) => x.id === r.id)) throw new Error(`post-settings: причина перерыва ${r.id} уже есть в машине`);
    });
    out.session.breakReasons = out.session.breakReasons.concat(breaks);
    ids.forEach((id) => {
      const cat = out.reasonCatalogs[id];
      if (!cat) throw new Error(`post-settings: в машине нет справочника ${id}`);
      if (id === "close_result") throw new Error("post-settings: результаты закрытия — модель, пост их не задаёт");
      const own = (catalogs[id].items || []).map((i) => Object.assign({ setBy: "operator" }, i));
      own.forEach((i) => {
        if (cat.items.some((x) => x.id === i.id)) throw new Error(`post-settings: ${id}.${i.id} уже есть в машине`);
      });
      cat.items = cat.items.concat(own);
    });
    return out;
  }

  // Пути списков набора по порядку: "session.breakReasons", "reasonCatalogs.hold.items", …
  function lists(value, prefix) {
    if (Array.isArray(value)) return [prefix];
    if (!value || typeof value !== "object") return [];
    return Object.keys(value)
      .filter((k) => !k.startsWith("$"))
      .flatMap((k) => lists(value[k], prefix ? `${prefix}.${k}` : k));
  }
  const get = (obj, path) => path.split(".").reduce((cur, k) => (cur && typeof cur === "object" && Object.prototype.hasOwnProperty.call(cur, k) ? cur[k] : undefined), obj);
  function put(obj, path, value) {
    const keys = path.split(".");
    const last = keys.pop();
    const at = keys.reduce((cur, k) => {
      if (!cur[k] || typeof cur[k] !== "object") cur[k] = {};
      return cur[k];
    }, obj);
    at[last] = value;
  }

  // Стартовый набор на настройки поста (§20). published — опубликованные настройки поста (патч), null — у поста нет
  // ни одной версии: набор целиком, версией 1 от системы. Иначе ложатся только списки набора, ключа которых в
  // published нет (список ни разу не задавали); заданный — и очищенный [] тоже — остаётся как есть. only — пути
  // списков, которыми ограничиться: черновик администратора пересчитывается от новой версии только по добавленным в
  // неё спискам. Итог — { settings, added }: added — пути добавленных списков; пуст — новой версии нет.
  function withDefaults(published, defaults, only) {
    const paths = lists(defaults || {}, "").filter((p) => !only || only.includes(p));
    if (published == null && !only) return { settings: JSON.parse(JSON.stringify(defaults || {})), added: paths };
    const settings = JSON.parse(JSON.stringify(published || {}));
    const added = paths.filter((p) => get(settings, p) === undefined);
    added.forEach((p) => put(settings, p, JSON.parse(JSON.stringify(get(defaults, p)))));
    return { settings, added };
  }

  root.IMPostSettings = { apply, withDefaults, base: root.IM_WORKFLOW || null };
  if (root.IM_WORKFLOW && root.IM_FIXTURE) {
    if (!root.IM_POST_DEFAULTS) throw new Error("post-settings: нет стартового набора — подключите post-defaults.js до этого файла");
    root.IM_WORKFLOW = apply(root.IM_WORKFLOW, withDefaults(root.IM_FIXTURE.settings || null, root.IM_POST_DEFAULTS).settings);
  }
})();
