/* Векторы переходов для бэкенда (план этапа 4б-2 встраивания): «инциденты + лента мира + действие → инциденты,
   журнал, действия после фиксации» на ядре прототипа (prototype/engine.js). Здесь пока только lib.normalize —
   сравнение «пусто как у cel.value» и правило решения 25 (since у таймеров, кроме hold, — 0). Запись и повтор
   добавляют следующие задачи. Файл грузится и в Node (tools/test_cel.mjs, vm). */
(() => {
  // Нулевое значение типа CEL (cel.types): строка, число, bool, список, словарь, запись
  function zero(W, type) {
    if (type === "string") return "";
    if (type === "int") return 0;
    if (type === "bool") return false;
    if (/^list</.test(type)) return [];
    if (/^map</.test(type)) return {};
    const rec = W.cel.types[type];
    return rec ? Object.fromEntries(Object.keys(rec).sort().map((f) => [f, zero(W, rec[f])])) : null;
  }

  // Значение по объявленному типу: null и недостающее поле — нулевое значение, вложенные записи — так же
  function fill(W, type, v) {
    if (v == null) return zero(W, type);
    let m = /^list<(.+)>$/.exec(type);
    if (m) return v.map((x) => fill(W, m[1], x));
    m = /^map<[^,]+,\s*(.+)>$/.exec(type);
    if (m) return Object.fromEntries(Object.entries(v).map(([k, x]) => [k, fill(W, m[1], x)]));
    const rec = W.cel.types[type];
    if (rec) return Object.fromEntries(Object.keys(rec).sort().map((f) => [f, fill(W, rec[f], v[f])]));
    return v;
  }

  // Инцидент celView к виду для сравнения: пусто как у cel.value, у каждого таймера машины есть запись,
  // since не у hold — 0 (решение 25: прототип хранит since только у удержания)
  function normalize(incident, W) {
    const x = fill(W, "Incident", incident);
    W.timers.forEach((t) => {
      if (!x.timers[t.id]) x.timers[t.id] = zero(W, "Timer");
    });
    Object.keys(x.timers).forEach((id) => {
      if (id !== "hold") x.timers[id].since = 0;
    });
    x.timers = Object.fromEntries(Object.keys(x.timers).sort().map((id) => [id, x.timers[id]]));
    return x;
  }

  window.IMTransitionVectors = { lib: { normalize } };
})();
