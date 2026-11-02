/* Векторы CEL для бэкенда (PROC-44, план этапа 4а встраивания): «вход + мир → результат» каждого вычисления
   выражения машины на исполнителе прототипа (prototype/cel-runtime.js). Бэкенд повторяет каждый вектор своим
   исполнителем и сверяет ответ.

   Запись — tests/api.html?celVectors=1 (без ?api=): часы и случайные числа зафиксированы, IMCel.create обёрнут.
   Записываются только вычисления на исходной машине (window.IM_WORKFLOW или её копия с тем же JSON); машина
   с workflowPatch тестов — как есть, без записи. Условие (guard), правило интерфейса (rule), определение (call)
   и эффект (effect) — каждый вызов своим вектором, вложенный вызов — тоже своим:
   - вход — до вызова: аргументы, usage условия, имена верхнего уровня (scope);
   - мир — лента: каждый вызов факта мира без ref — функция, аргументы, ответ; на один вызов — одна запись, мир
     ответил на тот же вызов по-разному — вектор не пишется (stats.tapeRepeat);
   - список инцидентов — только если вычисление его спросило; инциденты — ссылками в общий пул;
   - ответ — значение или текст исключения (исключение пробрасывается дальше).
   Итог — <pre id="celvectors-out"> в конце прогона (tests/harness.js): {incidents, vectors}. Записанное уже
   прорежено так, что lib.select даёт то же, что на полной записи; собирает файл tools/cel_vectors.mjs.

   Формат — план этапа 4а, «Формат векторов»; описание для бэкенда — CEL.md, «Векторы». Файл грузится и в Node
   (tools/test_cel.mjs, vm), там записи нет. */
(() => {
  const PER_NAME = 30;
  const PER_OUTCOME = 5;
  // Часы записи: 2026-10-01T09:00:00Z
  const NOW = 1790845200000;
  const own = (o) => Object.entries(o || {}).filter(([k]) => !k.startsWith("$"));
  const isMap = (v) => Object.prototype.toString.call(v) === "[object Map]";
  const isIncident = (v) => Boolean(v && typeof v === "object" && v.constructor && v.constructor.name === "Incident");

  /* ===== sha256 — синхронно, по байтам UTF-8 (ключ пула и id вектора) ===== */

  const K = new Uint32Array([
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe,
    0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
    0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ]);
  const ror = (x, n) => (x >>> n) | (x << (32 - n));
  function sha256(str) {
    const bytes = new TextEncoder().encode(str);
    const n = ((bytes.length + 9 + 63) >> 6) << 6;
    const buf = new Uint8Array(n);
    buf.set(bytes);
    buf[bytes.length] = 0x80;
    const dv = new DataView(buf.buffer);
    dv.setUint32(n - 8, Math.floor((bytes.length * 8) / 0x100000000));
    dv.setUint32(n - 4, (bytes.length * 8) >>> 0);
    const h = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19];
    const w = new Uint32Array(64);
    for (let i = 0; i < n; i += 64) {
      for (let t = 0; t < 16; t++) w[t] = dv.getUint32(i + t * 4);
      for (let t = 16; t < 64; t++) {
        const x = w[t - 15];
        const y = w[t - 2];
        w[t] = (w[t - 16] + (ror(x, 7) ^ ror(x, 18) ^ (x >>> 3)) + w[t - 7] + (ror(y, 17) ^ ror(y, 19) ^ (y >>> 10))) | 0;
      }
      let [a, b, c, d, e, f, g, hh] = h;
      for (let t = 0; t < 64; t++) {
        const t1 = (hh + (ror(e, 6) ^ ror(e, 11) ^ ror(e, 25)) + ((e & f) ^ (~e & g)) + K[t] + w[t]) | 0;
        const t2 = ((ror(a, 2) ^ ror(a, 13) ^ ror(a, 22)) + ((a & b) ^ (a & c) ^ (b & c))) | 0;
        hh = g;
        g = f;
        f = e;
        e = (d + t1) | 0;
        d = c;
        c = b;
        b = a;
        a = (t1 + t2) | 0;
      }
      [a, b, c, d, e, f, g, hh].forEach((x, k) => (h[k] = (h[k] + x) | 0));
    }
    return h.map((x) => (x >>> 0).toString(16).padStart(8, "0")).join("");
  }

  /* ===== Канонический JSON: ключи по алфавиту, без пробелов, числа — только безопасные целые ===== */

  function canonical(v, at = "") {
    if (v === null) return "null";
    if (typeof v === "string" || typeof v === "boolean") return JSON.stringify(v);
    if (typeof v === "number") {
      if (!Number.isSafeInteger(v)) throw new Error(`cel-vectors: ${at || "значение"} — число ${v} не безопасное целое`);
      return String(v);
    }
    if (Array.isArray(v)) {
      return `[${v
        .map((x, i) => {
          if (x === undefined) throw new Error(`cel-vectors: ${at}[${i}] — undefined в списке`);
          return canonical(x, `${at}[${i}]`);
        })
        .join(",")}]`;
    }
    if (typeof v === "object" && !isMap(v)) {
      const keys = Object.keys(v)
        .filter((k) => v[k] !== undefined)
        .sort();
      return `{${keys.map((k) => `${JSON.stringify(k)}:${canonical(v[k], `${at}.${k}`)}`).join(",")}}`;
    }
    throw new Error(`cel-vectors: ${at || "значение"} — ${typeof v}, не значение JSON`);
  }
  // Хэш канона инцидента повторяется часто (одни и те же инциденты в каждом вычислении): кэш с пределом
  const digests = new Map();
  function keyOf(plainIncident) {
    const s = canonical(plainIncident);
    let k = digests.get(s);
    if (!k) {
      if (digests.size > 20000) digests.clear();
      k = sha256(s).slice(0, 16);
      digests.set(s, k);
    }
    return k;
  }

  /* ===== Значение CEL ↔ данные вектора ===== */

  function int(v, where) {
    if (typeof v !== "bigint") throw new Error(`cel-vectors: ${where || "int"} — ${typeof v} вместо целого CEL`);
    const n = Number(v);
    if (!Number.isSafeInteger(n)) throw new Error(`cel-vectors: ${where || "int"} — ${v} не безопасное целое`);
    return n;
  }
  // CEL → данные по объявленному типу: инцидент — в пул (pool) ссылкой {$ref}, opt<T> — список, ключи
  // map<int, T> — строки цифр. Тип не известен (dyn, null) — по самому значению
  // cache — у записи: инцидент → его запись пула, пока эффект его не менял (WeakMap; запись снимает touch)
  function encode(cel, type, v, pool, cache) {
    if (type == null || type === "dyn") return generic(cel, v, pool, cache);
    if (type === "string" || type === "bool") {
      if (typeof v !== (type === "bool" ? "boolean" : "string")) throw new Error(`cel-vectors: ${type} — а значение ${typeof v}`);
      return v;
    }
    if (type === "int") return int(v);
    let m = /^(?:opt|list)<(.+)>$/.exec(type);
    if (m) {
      if (!Array.isArray(v)) throw new Error(`cel-vectors: ${type} — а значение не список`);
      return v.map((x) => encode(cel, m[1], x, pool, cache));
    }
    m = /^map<(string|int), ?(.+)>$/.exec(type);
    if (m) {
      if (!isMap(v)) throw new Error(`cel-vectors: ${type} — а значение не словарь`);
      const o = {};
      v.forEach((x, k) => (o[String(k)] = encode(cel, m[2], x, pool, cache)));
      return o;
    }
    const fields = cel.types[type];
    if (!fields) throw new Error(`cel-vectors: нет типа ${type}`);
    if (!v || typeof v !== "object") throw new Error(`cel-vectors: ${type} — а значение ${v}`);
    if (type === "Incident" && cache && cache.has(v)) {
      const [key, plain] = cache.get(v);
      pool[key] = plain;
      return { $ref: key };
    }
    const o = {};
    own(fields).forEach(([f, t]) => (o[f] = encode(cel, t, v[f], pool, cache)));
    if (type !== "Incident") return o;
    const key = keyOf(o);
    pool[key] = o;
    if (cache) cache.set(v, [key, o]);
    return { $ref: key };
  }
  function generic(cel, v, pool, cache) {
    if (typeof v === "bigint") return int(v);
    if (v === undefined) return null;
    if (v === null || typeof v !== "object") return v;
    if (Array.isArray(v)) return v.map((x) => generic(cel, x, pool, cache));
    if (isMap(v)) {
      const o = {};
      v.forEach((x, k) => (o[String(k)] = generic(cel, x, pool, cache)));
      return o;
    }
    const type = v.constructor && v.constructor.name;
    if (type && cel.types[type]) return encode(cel, type, v, pool, cache);
    return Object.fromEntries(Object.entries(v).map(([k, x]) => [k, generic(cel, x, pool, cache)]));
  }
  // Аргументы фактов мира на ленте и действий эффекта: инцидент — {$incident: id} (факты о нём — из записи
  // сервера, а не из полей), остальное — по значению
  function encodeArg(v) {
    if (typeof v === "bigint") return int(v);
    if (v === undefined) return null;
    if (v === null || typeof v !== "object") return v;
    if (isIncident(v)) return { $incident: v.id };
    if (Array.isArray(v)) return v.map(encodeArg);
    const o = {};
    if (isMap(v)) v.forEach((x, k) => (o[String(k)] = encodeArg(x)));
    else Object.entries(v).forEach(([k, x]) => (o[k] = encodeArg(x)));
    return o;
  }
  // Данные → CEL по типу: null — как value() исполнителя ('', 0, false, [], запись из пустых)
  function revive(cel, type, data, pool) {
    if (data == null) return cel.value(type || "dyn", null);
    if (type == null || type === "dyn") return cel.value("dyn", data && data.$ref ? revive(cel, "Incident", data, pool) : data);
    if (type === "string" || type === "int" || type === "bool") return cel.value(type, data);
    let m = /^(?:opt|list)<(.+)>$/.exec(type);
    if (m) return Array.from(data, (x) => revive(cel, m[1], x, pool));
    m = /^map<(string|int), ?(.+)>$/.exec(type);
    if (m) return new Map(Object.entries(data).map(([k, x]) => [m[1] === "int" ? BigInt(k) : k, revive(cel, m[2], x, pool)]));
    if (data.$ref != null) {
      if (!pool || !pool[data.$ref]) throw new Error(`cel-vectors: в пуле нет ${data.$ref}`);
      data = pool[data.$ref];
    }
    const fields = cel.types[type];
    if (!fields) throw new Error(`cel-vectors: нет типа ${type}`);
    // Экземпляр типа с пустыми полями, затем поля — уже значениями CEL (value() второй раз opt<T> испортил бы)
    const inst = cel.value(type, {});
    own(fields).forEach(([f, t]) => (inst[f] = revive(cel, t, data[f], pool)));
    return inst;
  }
  // Ответ условия: null — выполнено; иначе ключ причины и подстановки
  const guardOut = (cel, r, pool) => (r == null ? null : r.length > 1 ? { key: r[0], vars: generic(cel, r[1], pool) } : { key: r[0] });

  /* ===== Отбор: не больше PER_NAME на имя, не больше PER_OUTCOME на один ответ ===== */

  // Ответы имени — по кругу в порядке первого появления, внутри ответа — в порядке записи. Порядок итога — как на входе
  function select(vectors) {
    const byName = new Map();
    vectors.forEach((v) => {
      const name = `${v.kind}:${v.name}`;
      if (!byName.has(name)) byName.set(name, new Map());
      const answers = byName.get(name);
      const e = canonical(v.expect);
      if (!answers.has(e)) answers.set(e, []);
      answers.get(e).push(v);
    });
    const chosen = new Set();
    byName.forEach((answers) => {
      const lists = [...answers.values()];
      let n = 0;
      for (let round = 0; round < PER_OUTCOME && n < PER_NAME; round++) {
        for (const list of lists) {
          if (n >= PER_NAME) break;
          if (round < list.length) {
            chosen.add(list[round]);
            n++;
          }
        }
      }
    });
    return vectors.filter((v) => chosen.has(v));
  }

  /* ===== Повтор вектора по ленте (tools/cel_vectors.mjs --check) ===== */

  // id вектора: вид, имя и первые 10 hex sha256 канона входа — args, use (если есть), scope, world
  function idOf(vector) {
    const input = { args: vector.args, scope: vector.scope, world: vector.world };
    if (vector.use) input.use = vector.use;
    const at = `${vector.kind}:${vector.name}`;
    return `${at}:${sha256(canonical(input, at)).slice(0, 10)}`;
  }

  // Лента: вызов ищется по fn и аргументам, равным по значению; на один вызов — один ответ, сколько бы раз его ни
  // спросили (так же повторяет бэкенд). Вызова нет на ленте или на нём два ответа — промах. Запись векторов с двумя
  // ответами на один вызов не пишет (tapeRepeat)
  function tapeWorld(tape, misses) {
    const calls = new Map();
    const twice = new Set();
    (tape || []).forEach((e) => {
      const k = `${e.fn}|${canonical(e.args)}`;
      if (calls.has(k)) twice.add(k);
      calls.set(k, e.out);
    });
    return new Proxy(
      {},
      {
        get: (_, fn) =>
          typeof fn !== "string"
            ? undefined
            : (...a) => {
                const args = a.map(encodeArg);
                const k = `${fn}|${canonical(args)}`;
                if (!calls.has(k) || twice.has(k)) {
                  misses.push(fn);
                  throw new Error(`cel-vectors: на ленте ${twice.has(k) ? "два ответа на" : "нет"} ${fn}(${canonical(args).slice(1, -1)})`);
                }
                return calls.get(k);
              },
      }
    );
  }
  function replay(cel, vector, pool) {
    const W = cel.machine;
    const misses = [];
    const world = tapeWorld(vector.world, misses);
    const sc = vector.scope || {};
    const scope = { me: sc.me, actor: sc.actor, surface: sc.surface, now: sc.now, deadline: sc.deadline, form: sc.form ? revive(cel, "Form", sc.form, pool) : {}, world };
    if ("incident" in sc) scope.incident = revive(cel, "Incident", sc.incident, pool);
    if ("before" in sc) scope.before = revive(cel, "Incident", sc.before, pool);
    if (sc.incidents) scope.incidents = () => sc.incidents.map((d) => revive(cel, "Incident", d, pool));
    const local = {};
    let got;
    try {
      if (vector.kind === "guard") {
        const g = (W.registries.guards || []).find((x) => x.fn === vector.name) || {};
        const use = Object.fromEntries(own(g.usage).map(([f, t]) => [f, revive(cel, t, (vector.use || {})[f], pool)]));
        got = { value: guardOut(cel, cel.guard(vector.name, vector.args, scope, use), local) };
      } else if (vector.kind === "rule") {
        scope.actions = sc.actions;
        got = { value: generic(cel, cel.rule(vector.name, scope, sc.option), local) };
      } else if (vector.kind === "definition") {
        const d = W.cel.definitions[vector.name];
        if (!d) throw new Error(`cel-vectors: нет определения ${vector.name}`);
        const args = own(d.params).map(([, t], i) => revive(cel, t, vector.args[i], pool));
        got = { value: encode(cel, d.returns, cel.call(vector.name, args, world), local) };
      } else if (vector.kind === "effect") {
        // Черновик пробы: инциденты по id — incident эффекта, остальные из списка на начало эффекта
        const live = new Map(scope.incident ? [[scope.incident.id, scope.incident]] : []);
        const idOf = (d) => (d && d.$ref != null ? (pool[d.$ref] || {}).id : d && d.id);
        const instance = (id) => {
          if (live.has(id)) return live.get(id);
          const d = (sc.incidents || []).find((x) => idOf(x) === id);
          if (!d) throw new Error(`cel-vectors: в векторе нет инцидента ${id}`);
          live.set(id, revive(cel, "Incident", d, pool));
          return live.get(id);
        };
        const touched = new Map();
        const actions = [];
        const store = {
          incidents: () => {
            if (!sc.incidents) throw new Error("cel-vectors: эффект спросил список инцидентов, а в векторе его нет");
            return sc.incidents.map((d) => instance(idOf(d)));
          },
          instance,
          touch: (x) => touched.set(x.id, x),
          world: (action, args) => actions.push({ action, args: encodeArg(args) }),
        };
        cel.effect(vector.name, vector.args, scope, store);
        got = { value: { incidents: Object.fromEntries([...touched].map(([id, x]) => [id, encode(cel, "Incident", x, local)])), actions } };
      } else throw new Error(`cel-vectors: вид ${vector.kind}`);
    } catch (e) {
      got = { error: String((e && e.message) || e) };
    }
    return { ok: !misses.length && canonical(got) === canonical(vector.expect), got, misses };
  }

  /* ===== Запись ===== */

  // Сырые данные на входе int (из сервера, фактов мира, часов): только целое или пусто. Прототип молча отбросил бы
  // дробную часть и прочёл бы строку, бэкенд так не делает (решение 10 плана этапа 4а) — в векторах таких входов нет
  function checkRaw(cel, type, v, where) {
    if (v == null || type == null || type === "dyn") return;
    if (type === "int") {
      if (typeof v === "bigint" || Number.isSafeInteger(v)) return;
      throw new Error(`cel-vectors: ${where} — на входе int ${JSON.stringify(v)}`);
    }
    let m = /^(?:opt|list)<(.+)>$/.exec(type);
    if (m) {
      if (Array.isArray(v)) v.forEach((x, i) => checkRaw(cel, m[1], x, `${where}[${i}]`));
      return;
    }
    m = /^map<(string|int), ?(.+)>$/.exec(type);
    if (m) {
      Object.entries(isMap(v) ? Object.fromEntries(v) : v).forEach(([k, x]) => checkRaw(cel, m[2], x, `${where}[${k}]`));
      return;
    }
    const fields = cel.types[type];
    if (fields && typeof v === "object" && v.constructor && !cel.types[v.constructor.name]) own(fields).forEach(([f, t]) => checkRaw(cel, t, v[f], `${where}.${f}`));
  }

  // create — IMCel.create; reference — исходная машина. Возвращает create (обёрнутый) и take() — записанное
  function recorder(create, reference) {
    const refJSON = JSON.stringify(reference);
    const isReference = new WeakMap();
    const wrapped = new WeakMap();
    const answers = new Map(); // id → канон ответа: один вход — один ответ
    const names = new Map(); // вид:имя → (канон ответа → векторы); только то, что может выбрать select
    const kept = [];
    const pool = {};
    // Пропущенные вычисления: skipped — факт мира бросил исключение; tapeRepeat — на один вызов факта мира
    // (fn и аргументы) мир ответил по-разному (менялся посреди вычисления): по ленте с одним ответом на вызов
    // такой вектор не повторить
    const stats = { evaluations: 0, distinct: 0, kept: 0, skipped: 0, tapeRepeat: 0 };
    // Стек вычислений: факт мира пишется на ленту верхнего. Исполнитель держит мир в одной переменной, и после
    // вложенного вычисления он бывает чужим — лента от этого не путается
    const stack = [];
    // Кадры записи (frame): открыт кадр — каждый вызов факта мира без ref в любом вычислении идёт и в его ленту.
    // Один кадр — один вызов ядра (переходы, PROC-44, этап 4б). Кадр вычислений не трогает: ни векторов, ни stats
    const open = [];

    function reference_(W) {
      if (W === reference) return true;
      if (!isReference.has(W)) isReference.set(W, JSON.stringify(W) === refJSON);
      return isReference.get(W);
    }
    function keep(frame, vector) {
      stats.evaluations++;
      if (frame.broken) {
        stats.skipped++;
        return;
      }
      if (frame.repeat) {
        stats.tapeRepeat++;
        return;
      }
      vector.world = frame.tape;
      const at = `${vector.kind}:${vector.name}`;
      vector.id = idOf(vector);
      const e = canonical(vector.expect, `${at}.expect`);
      // Длинный ответ — хэшем: входов за прогон сотни тысяч
      const short = e.length > 64 ? sha256(e) : e;
      if (answers.has(vector.id)) {
        if (answers.get(vector.id) !== short) throw new Error(`cel-vectors: один вход — два ответа: ${vector.id}`);
        return;
      }
      answers.set(vector.id, short);
      stats.distinct++;
      const name = `${vector.kind}:${vector.name}`;
      if (!names.has(name)) names.set(name, new Map());
      const byAnswer = names.get(name);
      if (!byAnswer.has(e)) {
        // Ответы сверх PER_NAME-го по счёту select не возьмёт никогда: по кругу до них очередь не дойдёт
        if (byAnswer.size >= PER_NAME) return;
        byAnswer.set(e, 0);
      }
      if (byAnswer.get(e) >= PER_OUTCOME) return;
      byAnswer.set(e, byAnswer.get(e) + 1);
      Object.assign(pool, frame.pool);
      const ordered = { id: vector.id, kind: vector.kind, name: vector.name, args: vector.args };
      if (vector.use) ordered.use = vector.use;
      Object.assign(ordered, { scope: vector.scope, world: vector.world, expect: vector.expect });
      kept.push(ordered);
      stats.kept++;
    }

    function wrap(cel, W) {
      const facts = own(W.cel.world).filter(([, f]) => f.ref == null);
      const guardSpec = Object.fromEntries((W.registries.guards || []).map((g) => [g.fn, g]));
      const effectSpec = Object.fromEntries((W.registries.effects || []).map((e) => [e.fn, e]));
      const cache = new WeakMap();
      // inline — определение, вызванное из выражения: его факты мира нужны и вычислению, которое его вызвало.
      // В стек кадр кладёт run — уже после кодирования входа: исключение при кодировании кадра в стеке не оставляет
      const frameOf = (inline) => ({ tape: [], pool: {}, broken: false, repeat: false, inline: Boolean(inline) });
      const leave = (frame) => stack.splice(stack.lastIndexOf(frame), 1);
      // Кадры, которым нужен факт мира: верхний и вверх по стеку, пока кадр — определение из выражения
      const frames = () => {
        const out = [];
        for (let i = stack.length - 1; i >= 0; i--) {
          out.push(stack[i]);
          if (!stack[i].inline) break;
        }
        return out;
      };
      // Мир вычисления: факты без ref — с записью на ленту; ответ — как есть, на ленте — значением CEL
      function worldOf(w) {
        if (!w) return w;
        const o = Object.assign({}, w);
        facts.forEach(([fn, f]) => {
          if (typeof w[fn] !== "function") return;
          o[fn] = (...a) => {
            const to = frames();
            let raw;
            try {
              raw = w[fn](...a);
            } catch (e) {
              to.forEach((x) => (x.broken = true));
              throw e;
            }
            checkRaw(cel, f.returns, raw, `cel.world.${fn}`);
            if (to.length || open.length) {
              const entry = { fn, args: a.map(encodeArg), out: encode(cel, f.returns, cel.value(f.returns, raw), {}) };
              to.forEach((x) => x.tape.push(entry));
              open.forEach((x) => x.note(entry));
            }
            return raw;
          };
        });
        return o;
      }
      // Определение из выражения — своим вектором, когда идёт записываемое вычисление (вне его — повтор, без записи)
      if (cel.observeDefinitions) {
        cel.observeDefinitions((name, a, compute) => {
          const d = (W.cel.definitions || {})[name];
          if (!stack.length || !d) return compute();
          const frame = frameOf(true);
          const vector = { kind: "definition", name, args: own(d.params).map(([, t], i) => encode(cel, t, a[i], frame.pool, cache)), scope: {} };
          const r = run(frame, vector, compute);
          vector.expect = { value: encode(cel, d.returns, r, frame.pool, cache) };
          keep(frame, vector);
          return r;
        });
      }
      // Ленту собрать: на один вызов (fn и аргументы) — одна запись, первая. Разные ответы на один вызов — кадр
      // помечен repeat, вектор не пишется (keep, tapeRepeat)
      function finishTape(frame) {
        const first = new Map();
        frame.tape = frame.tape.filter((e) => {
          const k = `${e.fn}|${canonical(e.args)}`;
          if (!first.has(k)) {
            first.set(k, canonical(e.out));
            return true;
          }
          if (first.get(k) !== canonical(e.out)) frame.repeat = true;
          return false;
        });
      }
      // Имена верхнего уровня — значениями CEL, как их видит выражение
      function scopeOf(scope, frame) {
        checkRaw(cel, "int", scope.now, "scope.now");
        checkRaw(cel, "int", scope.deadline, "scope.deadline");
        const s = {
          me: cel.value("string", scope.me),
          actor: cel.value("string", scope.actor),
          surface: cel.value("string", scope.surface),
          now: int(cel.value("int", scope.now), "scope.now"),
          deadline: int(cel.value("int", scope.deadline != null ? scope.deadline : scope.now), "scope.deadline"),
          form: encode(cel, "Form", cel.value("Form", scope.form || {}), frame.pool),
        };
        if (scope.incident != null) s.incident = encode(cel, "Incident", scope.incident, frame.pool, cache);
        if (scope.before != null) s.before = encode(cel, "Incident", scope.before, frame.pool, cache);
        return s;
      }
      // Список инцидентов — при первом обращении вычисления
      function listOf(scope, s, frame) {
        if (typeof scope.incidents !== "function") return scope.incidents;
        return () => {
          const l = scope.incidents();
          if (!s.incidents) s.incidents = Array.from(l, (x) => encode(cel, "Incident", x, frame.pool, cache));
          return l;
        };
      }
      const failed = (e) => ({ error: String((e && e.message) || e) });
      function run(frame, vector, fn) {
        stack.push(frame);
        let result;
        try {
          result = fn();
        } catch (e) {
          leave(frame);
          finishTape(frame);
          vector.expect = failed(e);
          keep(frame, vector);
          throw e;
        }
        leave(frame);
        finishTape(frame);
        return result;
      }

      return Object.assign({}, cel, {
        value(type, v, source) {
          checkRaw(cel, type, v, `value(${type})`);
          return cel.value(type, v, source);
        },
        guard(fn, args, scope, use) {
          const g = guardSpec[fn] || {};
          const frame = frameOf();
          const s = scopeOf(scope, frame);
          const vector = { kind: "guard", name: fn, args: args || [], scope: s };
          if (own(g.usage).length) {
            vector.use = Object.fromEntries(
              own(g.usage).map(([f, t]) => {
                checkRaw(cel, t, use ? use[f] : undefined, `use.${f}`);
                return [f, encode(cel, t, cel.value(t, use ? use[f] : undefined), frame.pool)];
              })
            );
          }
          const sc = Object.assign({}, scope, { world: worldOf(scope.world), incidents: listOf(scope, s, frame) });
          const r = run(frame, vector, () => cel.guard(fn, args, sc, use));
          vector.expect = { value: guardOut(cel, r, frame.pool) };
          keep(frame, vector);
          return r;
        },
        rule(where, scope, option) {
          const frame = frameOf();
          const s = Object.assign(scopeOf(scope, frame), { option: cel.value("string", option), actions: encode(cel, "list<string>", cel.value("list<string>", scope.actions || []), frame.pool) });
          const vector = { kind: "rule", name: where, args: [], scope: s };
          const sc = Object.assign({}, scope, { world: worldOf(scope.world), incidents: listOf(scope, s, frame) });
          const r = run(frame, vector, () => cel.rule(where, sc, option));
          vector.expect = { value: generic(cel, r, frame.pool) };
          keep(frame, vector);
          return r;
        },
        call(name, args, w) {
          const d = (W.cel.definitions || {})[name];
          if (!d) return cel.call(name, args, w);
          const frame = frameOf();
          const vector = { kind: "definition", name, args: own(d.params).map(([, t], i) => encode(cel, t, args[i], frame.pool, cache)), scope: {} };
          const r = run(frame, vector, () => cel.call(name, args, worldOf(w)));
          vector.expect = { value: encode(cel, d.returns, r, frame.pool, cache) };
          keep(frame, vector);
          return r;
        },
        effect(fn, args, scope, store) {
          const frame = frameOf();
          const s = scopeOf(scope, frame);
          // Пропущенный аргумент (undefined) исполнитель берёт из defaults реестра — в векторе он тем же значением
          const e = effectSpec[fn] || {};
          const given = (args || []).map((a, i) => (a !== undefined ? a : (e.defaults || {})[(e.args || [])[i]]));
          const vector = { kind: "effect", name: fn, args: given, scope: s };
          const touched = new Map();
          const actions = [];
          const incidentId = scope.incident != null ? scope.incident.id : null;
          // Список — на начало эффекта: до первого обращения меняется только incident (его запись — та, что на входе),
          // остальные инциденты эффект берёт только из списка
          const st = Object.assign({}, store, {
            incidents: () => {
              const l = store.incidents();
              if (!s.incidents) s.incidents = Array.from(l, (x) => (x.id === incidentId ? s.incident : encode(cel, "Incident", x, frame.pool, cache)));
              return l;
            },
            // Запись в инцидент: его запись пула устарела
            touch: (x) => {
              cache.delete(x);
              touched.set(x.id, x);
              return store.touch(x);
            },
            world: (action, a) => {
              actions.push({ action, args: encodeArg(a) });
              return store.world(action, a);
            },
          });
          const sc = Object.assign({}, scope, { world: worldOf(scope.world) });
          const r = run(frame, vector, () => cel.effect(fn, args, sc, st));
          vector.expect = { value: { incidents: Object.fromEntries([...touched].map(([id, x]) => [id, encode(cel, "Incident", x, frame.pool, cache)])), actions } };
          keep(frame, vector);
          return r;
        },
      });
    }

    // Открыть кадр. close() снимает его и возвращает {tape, tapeRepeat}: лента — на один вызов (fn и аргументы) одна
    // запись, первая; тот же вызов с другим ответом не добавляется, а считается в tapeRepeat. Повторный close() —
    // тот же итог. opts.omit — факты, которых в этом кадре нет вовсе (векторы переходов: idleSec выводит ядро)
    function frame(opts) {
      const omit = new Set((opts && opts.omit) || []);
      const tape = [];
      const first = new Map();
      let tapeRepeat = 0;
      let closed = false;
      const f = {
        note(e) {
          if (omit.has(e.fn)) return;
          const k = `${e.fn}|${canonical(e.args)}`;
          const out = canonical(e.out);
          if (!first.has(k)) {
            first.set(k, out);
            tape.push(e);
          } else if (first.get(k) !== out) tapeRepeat++;
        },
        close() {
          if (!closed) {
            closed = true;
            const i = open.lastIndexOf(f);
            if (i >= 0) open.splice(i, 1);
          }
          return { tape: tape.slice(), tapeRepeat };
        },
      };
      open.push(f);
      return { close: f.close };
    }

    return {
      frame,
      create(W) {
        const cel = create(W);
        if (!reference_(W)) return cel;
        if (!wrapped.has(cel)) wrapped.set(cel, wrap(cel, W));
        return wrapped.get(cel);
      },
      take: () => ({ incidents: Object.assign({}, pool), vectors: kept.slice() }),
      stats: () => Object.assign({}, stats),
    };
  }

  // Случайные числа записи: mulberry32
  function mulberry32(seed) {
    let a = seed >>> 0;
    return () => {
      a = (a + 0x6d2b79f5) | 0;
      let t = Math.imul(a ^ (a >>> 15), 1 | a);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }

  const lib = { PER_NAME, PER_OUTCOME, NOW, sha256, canonical, keyOf, idOf, encode, encodeArg, revive, replay, select, recorder };
  const params = typeof location !== "undefined" && location.search ? new URLSearchParams(location.search) : null;
  const recording = Boolean(params && params.get("celVectors") === "1" && !params.has("api") && window.IMCel);
  let rec = null;
  if (recording) {
    // Часы: Date.now и new Date() без аргументов (тест «Основного не назвали…» берёт время так, когда в ответе
    // сессии нет serverTime) — иначе в векторы попадает настоящее время и два прогона дают разное
    const RealDate = Date;
    const FixedDate = function (...a) {
      if (!new.target) return new RealDate(NOW).toString();
      return new RealDate(...(a.length ? a : [NOW]));
    };
    FixedDate.prototype = RealDate.prototype;
    Object.assign(FixedDate, { now: () => NOW, parse: RealDate.parse, UTC: RealDate.UTC });
    window.Date = FixedDate;
    Math.random = mulberry32(1);
    rec = recorder(window.IMCel.create, window.IM_WORKFLOW);
    window.IMCel.create = rec.create;
  }
  window.IMCelVectors = {
    lib,
    recording,
    // Кадр активной записи; без записи (Node, vm) — пустой кадр, чтобы вызывающему не ветвиться
    frame: (opts) => (rec ? rec.frame(opts) : { close: () => ({ tape: [], tapeRepeat: 0 }) }),
    take: () => (rec ? rec.take() : { incidents: {}, vectors: [] }),
    stats: () => (rec ? rec.stats() : null),
  };
})();
