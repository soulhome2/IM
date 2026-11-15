/* Настройки поста поверх машины (решение 2026-11-15). Машина задаёт устройство справочников причин
   (reasonCatalogs: поле, обязательность, системные причины) и причин перерыва (session.breakReasons), пункты заводит администратор поста. В прототипе
   настройки поста — раздел settings эталонного набора (fixtures/demo.json): пункты справочника идут после
   пунктов машины, остальное в машине не меняется. Действующая машина прототипа — window.IM_WORKFLOW после
   этого файла; его же подключают инструменты Node (vm), чтобы считать на той же машине. */
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
  root.IMPostSettings = { apply };
  if (root.IM_WORKFLOW && root.IM_FIXTURE) root.IM_WORKFLOW = apply(root.IM_WORKFLOW, root.IM_FIXTURE.settings);
})();
