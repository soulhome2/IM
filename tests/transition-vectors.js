/* Векторы переходов для бэкенда (план этапа 4б-2 встраивания): «инциденты + лента мира + действие → инциденты,
   журнал, действия после фиксации» на ядре прототипа (prototype/engine.js). Формат — план 4б-2, «Формат векторов
   переходов»; правила сравнения — решение 41.

   Запись (решения 24–27, 39, 40) — обёртка IMEngine.create, как IMCel.create у векторов CEL (tests/cel-vectors.js):
   - только ядра исходной машины (window.IM_WORKFLOW или её копия с тем же JSON); прочие — как есть;
   - run, runAll, create — вектор на вызов: снимок «до» (celView, длины журналов, записи журнала в момент now),
     кадр записи CEL на время вызова (лента фактов cel.world), функции сервера ctx.* — в ту же ленту, действия
     сценария и после фиксации — в ожидаемое; снимок «после» — тоже только celView;
   - снимки зовут только celView (cel.value, cel.plain): условия, правила и определения в снимке дали бы лишние
     векторы CEL;
   - merge (решение 39): кадр закрыт и «после» снято на возврате; вектор открыт, пока его не закроет меняющий вызов
     любого обёрнутого ядра — run, runAll, merge, create, tick, startTimer…resumeTimer — или take(); чтение (isDone,
     availability, badge…) идёт насквозь: server.js после merge зовёт isDone раньше, чем пишет merged_in. На закрытии
     у основного может быть одна новая запись merged_in* от me — в ожидаемое с server: true; прочее — вектора нет;
   - отбор — при закрытии (решение 40): на op:name не больше PER_NAME исходов, на исход не больше PER_OUTCOME
     векторов; lib.select в take() даёт то же, что на полной записи; пул — только инциденты оставленных.
   Файл грузится и в Node (tools/test_cel.mjs, vm). */
(() => {
  const PER_NAME = 20;
  const PER_OUTCOME = 4;
  const FAILED = "workflow.error.transition_failed";
  // Меняющие вызовы ядра: закрывают открытый вектор (решение 39). runScheduler сервера зовёт tick
  const CLOSERS = new Set(["run", "runAll", "merge", "create", "tick", "startTimer", "stopTimer", "pauseTimer", "resumeTimer"]);
  // Записи основному, которые server.js mergeIncidents пишет после engine.merge (MERGED_IN_SHOWN — сколько номеров)
  const MERGED_IN = new Set(["workflow.journal.merged_in", "workflow.journal.merged_in_more"]);

  // Канонический JSON, sha256, ключ пула, аргументы ленты — общие с векторами CEL
  const C = () => {
    if (!window.IMCelVectors) throw new Error("transition-vectors: нет tests/cel-vectors.js (IMCelVectors)");
    return window.IMCelVectors.lib;
  };
  // Данные вектора: значения CEL — как на ленте (BigInt — число, инцидент — {$incident}), копия без общих ссылок
  const data = (v) => (v === undefined ? null : JSON.parse(JSON.stringify(C().encodeArg(v))));
  const blank = (v) => (v == null ? "" : v);
  const ref = (id) => ({ $incident: id });

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

  /* ===== Журнал, исход, отбор ===== */

  // Вид записи журнала — как journalView в server.js: dispatcher и system — system, иначе transition
  // (у Go — model.JournalKindOf)
  const kindOf = (whoId) => (whoId === "dispatcher" || whoId === "system" ? "system" : "transition");
  // Запись журнала прототипа ({at, whoId, k, v}) → запись вектора. Записи набора бывают с kind и who (без whoId) —
  // как в journalView
  const entryOf = (e) => ({
    actor: e.whoId || "",
    at: e.at,
    kind: e.kind || (!e.whoId && e.who ? "system" : kindOf(e.whoId)),
    templateKey: e.k,
    vars: data(e.v || {}),
  });

  // Исход вектора для отбора (решение 28): отказ и его ключ; ошибка; у ok — набор ключей журнала, видов действий
  // после фиксации и есть ли timer_overridden
  function outcomeOf(expect) {
    if (expect.refusal) return `refusal:${expect.refusal.why[0]}`;
    if ("error" in expect) return "error";
    const o = expect.ok || {};
    const keys = new Set();
    Object.values(o.journal || {}).forEach((l) => l.forEach((e) => keys.add(e.templateKey)));
    const after = new Set((o.after || []).map((a) => a.action));
    return `ok:${C().canonical({ after: [...after].sort(), journal: [...keys].sort(), overridden: keys.has("workflow.journal.timer_overridden") })}`;
  }
  const nameOf = (v) => `${v.op}:${v.name}`;

  // Исходы op:name — по кругу в порядке первого появления, внутри исхода — в порядке записи. Порядок итога — как на входе
  function select(vectors, { perName = PER_NAME, perOutcome = PER_OUTCOME } = {}) {
    const byName = new Map();
    vectors.forEach((v) => {
      const name = nameOf(v);
      if (!byName.has(name)) byName.set(name, new Map());
      const outcomes = byName.get(name);
      const e = outcomeOf(v.expect);
      if (!outcomes.has(e)) outcomes.set(e, []);
      outcomes.get(e).push(v);
    });
    const chosen = new Set();
    byName.forEach((outcomes) => {
      const lists = [...outcomes.values()];
      let n = 0;
      for (let round = 0; round < perOutcome && n < perName; round++) {
        for (const list of lists) {
          if (n >= perName) break;
          if (round < list.length) {
            chosen.add(list[round]);
            n++;
          }
        }
      }
    });
    return vectors.filter((v) => chosen.has(v));
  }

  // id вектора: op, имя и первые 10 hex sha256 канона входа — все поля, кроме id, case и expect
  function idOf(vector) {
    const input = Object.fromEntries(Object.entries(vector).filter(([k]) => k !== "id" && k !== "case" && k !== "expect"));
    const at = `transition:${vector.op}:${vector.name}`;
    return `${at}:${C().sha256(C().canonical(input, at)).slice(0, 10)}`;
  }

  /* ===== Запись ===== */

  // create — IMEngine.create; reference — исходная машина (запись только её ядер); frame — открыть кадр записи CEL
  // (IMCelVectors.frame): {close() → {tape, tapeRepeat}}. Возвращает create (обёрнутый) и take() — записанное
  function recorder(create, reference, frame) {
    const refJSON = JSON.stringify(reference);
    const isReference = new WeakMap();
    const answers = new Map(); // id → sha256 канона ожидаемого: один вход — один ответ (и у отброшенных)
    const names = new Map(); // op:name → (исход → сколько оставлено); только то, что может выбрать select
    const kept = []; // [{vector, pool}]
    // Пропущенные вызовы: nowChanged — часы сдвинулись за вызов; outsideEngine — изменилось то, чего ядро не
    // отдаёт (отказ с изменениями, вложенный вызов ядра; у объединения — что-то кроме merged_in* основного до
    // закрытия); tapeRepeat — на один вызов мир ответил по-разному; worldError — функция сервера или факт мира
    // бросили исключение
    const skipped = { nowChanged: 0, outsideEngine: 0, tapeRepeat: 0, worldError: 0 };
    // Идёт записываемый вызов ядра: в него пишут функции ctx любого обёрнутого ядра
    let cur = null;
    // Открытый вектор, который закрывает следующий меняющий вызов любого обёрнутого ядра (CLOSERS) или take()
    // (решение 39): {close()}. Сюда кладётся вектор объединения (mergeClose); run, runAll, create и отказ merge
    // закрываются на возврате
    let pending = null;
    function settle() {
      if (!pending) return;
      const p = pending;
      pending = null;
      p.close();
    }
    function hold(p) {
      settle();
      pending = p;
    }

    function reference_(W) {
      if (W === reference) return true;
      if (!W || typeof W !== "object") return false;
      if (!isReference.has(W)) isReference.set(W, JSON.stringify(W) === refJSON);
      return isReference.get(W);
    }

    function keep(vector, pool) {
      vector.id = idOf(vector);
      const e = C().canonical(vector.expect, `${vector.id}.expect`);
      const short = C().sha256(e);
      if (answers.has(vector.id)) {
        if (answers.get(vector.id) !== short) throw new Error(`transition-vectors: один вход — два ответа: ${vector.id}`);
        return;
      }
      answers.set(vector.id, short);
      const name = nameOf(vector);
      if (!names.has(name)) names.set(name, new Map());
      const byOutcome = names.get(name);
      const outcome = outcomeOf(vector.expect);
      if (!byOutcome.has(outcome)) {
        // Исходы сверх PER_NAME-го по счёту select не возьмёт никогда: по кругу до них очередь не дойдёт
        if (byOutcome.size >= PER_NAME) return;
        byOutcome.set(outcome, 0);
      }
      if (byOutcome.get(outcome) >= PER_OUTCOME) return;
      byOutcome.set(outcome, byOutcome.get(outcome) + 1);
      // id — первым, как в формате
      kept.push({ vector: Object.assign({ id: vector.id }, vector), pool });
    }

    /* --- функции сервера (ctx) --- */

    // Лента функций сервера вызова: на один вызов (fn и аргументы) — одна запись, первая; другой ответ — repeat
    function note(fn, args, out) {
      if (!cur) return;
      const e = data({ fn, args, out });
      const k = `${e.fn}|${C().canonical(e.args)}`;
      const o = C().canonical(e.out);
      if (!cur.first.has(k)) {
        cur.first.set(k, o);
        cur.tape.push(e);
      } else if (cur.first.get(k) !== o) cur.repeat++;
    }
    // Исключение функции сервера или факта мира во время вызова — вектор не пишется (worldError)
    const guarded = (f) =>
      function (...a) {
        try {
          return f.apply(this, a);
        } catch (e) {
          if (cur) cur.worldError = true;
          throw e;
        }
      };
    function wrapCtx(ctx) {
      const out = Object.assign({}, ctx);
      Object.keys(ctx).forEach((k) => {
        if (typeof ctx[k] === "function") out[k] = guarded(ctx[k]);
      });
      if (ctx.world && typeof ctx.world === "object") {
        out.world = Object.fromEntries(Object.entries(ctx.world).map(([k, f]) => [k, typeof f === "function" ? guarded(f) : f]));
      }
      const g = out;
      const on = (k, fn) => {
        if (typeof ctx[k] === "function") out[k] = fn(g[k]);
      };
      // Часы: за вызов не меняются, иначе вектора нет (nowChanged)
      on("now", (f) => () => {
        const t = f();
        if (cur && t !== cur.now) cur.nowChanged = true;
        return t;
      });
      // Функции сервера мимо cel.world — в ленту с приставкой ctx. (решение 26); null в аргументах — ""
      on("actorName", (f) => (id) => {
        const r = f(id);
        note("ctx.actorName", [blank(id)], r);
        return r;
      });
      on("progress", (f) => (ev) => {
        const r = f(ev);
        note("ctx.progress", [ref(ev.id)], { filled: r && r.filled, total: r && r.total });
        return r;
      });
      on("stepNumber", (f) => (ev) => {
        const r = f(ev);
        note("ctx.stepNumber", [ref(ev.id)], r);
        return r;
      });
      // Варианты поля с source: transferTargets (candidates) — факт transferTargets той же ленты
      on("transferTargets", (f) => (...a) => {
        const r = f(...a);
        note("transferTargets", [], Array.from(r || [], (o) => o.id));
        return r;
      });
      // Сценарий внутри транзакции — в ожидаемое по порядку; перенос ответов — ещё и в ленту
      on("setCursor", (f) => (ev) => {
        if (cur) cur.scenario.push({ action: "setCursor", incident: ref(ev.id) });
        return f(ev);
      });
      on("shareAnswers", (f) => (from, to, at) => {
        if (cur) cur.scenario.push({ action: "shareAnswers", from: ref(from.id), to: ref(to.id) });
        const n = f(from, to, at);
        note("ctx.shareAnswers", [ref(from.id), ref(to.id), blank(at)], n);
        return n;
      });
      // Действия после фиксации — в ожидаемое по порядку; пусто — ""
      on("deliver", (f) => (ev, recipients, o) => {
        const { alert, transitionId, about, actor } = o || {};
        if (cur) cur.after.push({ action: "notify", incident: ref(ev.id), recipients: data(Array.from(recipients || [])), alert: Boolean(alert), about: about ? ref(about.id) : "", actor: blank(actor), transitionId: blank(transitionId) });
        return f(ev, recipients, o);
      });
      on("onEvict", (f) => (ev, who, transitionId, by) => {
        if (cur) cur.after.push({ action: "evict", incident: ref(ev.id), who: blank(who), transitionId: blank(transitionId), by: blank(by) });
        return f(ev, who, transitionId, by);
      });
      on("onBreachShared", (f) => (ev, who) => {
        if (cur) cur.after.push({ action: "touch", incident: ref(ev.id), actor: blank(who) });
        return f(ev, who);
      });
      return out;
    }

    /* --- вызов ядра --- */

    // Снимок инцидента — только celView (cel.value и cel.plain): никаких условий, правил и определений
    function snapshot(engine, ev, now) {
      const view = engine.celView(ev);
      const log = ev.log || [];
      return { ev, view, key: C().keyOf(view), len: log.length, atNow: log.filter((e) => e.at === now).map(entryOf) };
    }
    const same = (a, b) => a.key === b.key && a.len === b.len && C().canonical(a.atNow) === C().canonical(b.atNow);

    // spec: op, name, surface, form, target, extra (инциденты вызова вне списка), result(r, done) — external,
    // facts, canceled итога ok. fn — сам вызов ядра
    function record(engine, ctx, spec, fn) {
      settle();
      if (cur) {
        // Ядро внутри вызова ядра: внешний вектор видел бы чужие изменения
        cur.nested = true;
        return fn();
      }
      const now = ctx.now();
      const list = Array.from(ctx.events());
      const tracked = list.concat(spec.extra.filter((e) => e && !list.includes(e)));
      const pool = {};
      const put = (s) => ((pool[s.key] = s.view), { $ref: s.key });
      const before = tracked.map((ev) => snapshot(engine, ev, now));
      const at = new Map(before.map((s) => [s.ev, s]));
      const vector = {
        kind: "transition",
        op: spec.op,
        name: spec.name,
        me: blank(ctx.me),
        now,
        surface: blank(spec.surface),
        form: data(spec.form || {}),
        target: spec.target((ev) => put(at.get(ev))),
        incidents: list.map((ev) => put(at.get(ev))),
        journalAtNow: Object.fromEntries(before.filter((s) => s.atNow.length).map((s) => [s.ev.id, s.atNow])),
      };
      const call = { now, tape: [], first: new Map(), repeat: 0, scenario: [], after: [], nowChanged: false, worldError: false, nested: false };
      let f = null;
      let r;
      let closed;
      try {
        cur = call;
        f = frame();
        r = fn();
      } catch (e) {
        if (call.worldError) skipped.worldError++;
        throw e;
      } finally {
        // Кадр не открылся — вызова не было; cur сбрасывается всегда, иначе следующие вызовы шли бы как вложенные
        closed = f ? f.close() : { tape: [], tapeRepeat: 0 };
        cur = null;
      }
      if (call.worldError) {
        skipped.worldError++;
        return r;
      }
      if (call.nowChanged || ctx.now() !== now) {
        skipped.nowChanged++;
        return r;
      }
      if (call.nested) {
        skipped.outsideEngine++;
        return r;
      }
      // Лента: факты cel.world кадра, затем функции сервера; на один вызов — одна запись
      const world = [];
      const first = new Map();
      let repeat = closed.tapeRepeat + call.repeat;
      closed.tape.concat(call.tape).forEach((x) => {
        const e = JSON.parse(JSON.stringify(x));
        const k = `${e.fn}|${C().canonical(e.args)}`;
        const o = C().canonical(e.out);
        if (!first.has(k)) {
          first.set(k, o);
          world.push(e);
        } else if (first.get(k) !== o) repeat++;
      });
      if (repeat) {
        skipped.tapeRepeat++;
        return r;
      }
      vector.world = world;
      const after = tracked.map((ev) => snapshot(engine, ev, now));
      if (!r || !r.ok) {
        // Отказ и ошибка: ничего не изменилось — иначе это не ядро
        if (after.some((s, i) => !same(s, before[i]))) {
          skipped.outsideEngine++;
          return r;
        }
        const why = data((r && r.why) || []);
        if (why[0] === FAILED) vector.expect = { error: String((why[1] && why[1].error) || "") };
        else {
          const refusal = { why };
          if (r.guard) refusal.guard = r.guard;
          if (r.notFrom) refusal.notFrom = true;
          if (r.code) refusal.code = r.code;
          if (r.ev) refusal.id = r.ev.id;
          vector.expect = { refusal };
        }
      } else {
        const ok = {};
        const changed = after.filter((s, i) => s.key !== before[i].key);
        if (changed.length) ok.incidents = Object.fromEntries(changed.map((s) => [s.ev.id, put(s)]));
        const journal = tracked.map((ev, i) => [ev.id, (ev.log || []).slice(before[i].len).map(entryOf)]).filter(([, l]) => l.length);
        if (journal.length) ok.journal = Object.fromEntries(journal);
        // Записи в момент now, что были до вызова: once меняет их подстановки на месте
        const atNow = tracked.map((ev, i) => [ev.id, before[i].atNow.length ? (ev.log || []).slice(0, before[i].len).filter((e) => e.at === now).map(entryOf) : []]).filter(([, l]) => l.length);
        if (atNow.length) ok.journalAtNow = Object.fromEntries(atNow);
        ok.after = call.after;
        ok.scenario = call.scenario;
        Object.assign(ok, spec.result(r));
        vector.expect = { ok };
        if (spec.mergedIn) {
          hold(mergeClose(engine, ctx, after, spec.mergedIn, vector, pool));
          return r;
        }
      }
      keep(vector, pool);
      return r;
    }

    // Объединение (решение 39): кадр закрыт и «после» снято на возврате, вектор открыт до следующего меняющего вызова
    // любого обёрнутого ядра или take(). Отложено только чтение новой записи основного — merged_in* от me, которую
    // server.js пишет своим log после ядра: она идёт в ожидаемое с server: true. Прочие изменения у любого инцидента
    // списка — не ядро: вектора нет, outsideEngine. after — снимки «после» record (celView, длина журнала)
    function mergeClose(engine, ctx, after, primary, vector, pool) {
      const journal = (ev, len) => C().canonical((ev.log || []).slice(0, len).map(entryOf));
      const at = after.map((s) => journal(s.ev, s.len));
      return {
        close() {
          let row = null;
          const clean = after.every((s, i) => {
            const { ev } = s;
            if (C().keyOf(engine.celView(ev)) !== s.key || journal(ev, s.len) !== at[i]) return false;
            const added = (ev.log || []).slice(s.len);
            if (!added.length) return true;
            if (ev !== primary || added.length > 1 || !MERGED_IN.has(added[0].k) || (added[0].whoId || "") !== blank(ctx.me)) return false;
            row = Object.assign(entryOf(added[0]), { server: true });
            return true;
          });
          if (!clean) {
            skipped.outsideEngine++;
            return;
          }
          if (row) {
            const ok = vector.expect.ok;
            ok.journal = ok.journal || {};
            ok.journal[primary.id] = (ok.journal[primary.id] || []).concat([row]);
          }
          keep(vector, pool);
        },
      };
    }

    const factsOf = (f) => ({
      from: Object.fromEntries(Object.entries(f.from || {}).map(([k, v]) => [k, blank(v)])),
      to: Object.fromEntries(Object.entries(f.to || {}).map(([k, v]) => [k, blank(v)])),
      breach: blank(f.breach),
    });

    function wrap(engine, ctx) {
      const out = {};
      Object.keys(engine).forEach((k) => {
        const v = engine[k];
        // Меняющий вызов сначала закрывает открытый вектор (решение 39); остальное — как есть
        out[k] =
          typeof v === "function" && CLOSERS.has(k)
            ? (...a) => {
                settle();
                return v(...a);
              }
            : v;
      });
      out.run = (id, ev, form, opts) => {
        if (!ev) {
          settle();
          return engine.run(id, ev, form, opts);
        }
        return record(
          engine,
          ctx,
          {
            op: "run",
            name: id,
            surface: opts && opts.surface,
            form,
            extra: [ev],
            target: () => ({ id: ev.id }),
            result: (r) => {
              const o = { external: { [ev.id]: data(r.external || []) }, facts: { [ev.id]: factsOf(r.facts) } };
              if (r.canceled) o.canceled = { [ev.id]: r.canceled };
              return o;
            },
          },
          () => engine.run(id, ev, form, opts)
        );
      };
      out.runAll = (id, list, form, opts) =>
        record(
          engine,
          ctx,
          {
            op: "runAll",
            name: id,
            surface: opts && opts.surface,
            form,
            extra: Array.from(list || []),
            target: () => ({ ids: Array.from(list || [], (ev) => ev.id) }),
            result: (r) => ({
              external: Object.fromEntries(Array.from(list || [], (ev, i) => [ev.id, data((r.external || [])[i] || [])])),
              facts: Object.fromEntries(Array.from(list || [], (ev, i) => [ev.id, factsOf((r.facts || [])[i] || {})])),
            }),
          },
          () => engine.runAll(id, list, form, opts)
        );
      out.create = (ev) =>
        record(
          engine,
          ctx,
          {
            op: "create",
            name: "create",
            surface: "",
            form: {},
            extra: [ev],
            target: (put) => ({ incident: put(ev) }),
            result: (r) => ({ external: { [ev.id]: data((r.external || [])[0] || []) }, facts: { [ev.id]: factsOf(r.facts || {}) } }),
          },
          () => engine.create(ev)
        );
      // Объединение: присоединяемые в порядке вызова, основной — target.primaryId; external — только присоединяемых,
      // facts — присоединяемых и основного, если его взяли. Успех закрывается позже (mergeClose), отказ — на возврате
      const mergeTr = (engine.workflow.transitions || []).find((t) => t.bulk && t.bulk.mode === "merge");
      out.merge = (primary, others) => {
        const list = Array.from(others || []);
        return record(
          engine,
          ctx,
          {
            op: "merge",
            name: mergeTr ? mergeTr.id : "",
            surface: "",
            form: {},
            extra: [primary].concat(list),
            target: () => ({ primaryId: primary.id, ids: list.map((ev) => ev.id) }),
            result: (r) => {
              const facts = Object.fromEntries(list.map((ev, i) => [ev.id, factsOf((r.facts || [])[i] || {})]));
              if (r.taken) facts[primary.id] = factsOf(r.taken.facts || {});
              return { external: Object.fromEntries(list.map((ev, i) => [ev.id, data((r.external || [])[i] || [])])), facts };
            },
            mergedIn: primary,
          },
          () => engine.merge(primary, others)
        );
      };
      return out;
    }

    return {
      create(ctx) {
        if (!ctx || !reference_(ctx.workflow)) return create(ctx);
        return wrap(create(wrapCtx(ctx)), ctx);
      },
      // Открытый вектор {close()} — его закроет следующий меняющий вызов или take(). Для тестов: merge кладёт свой
      // вектор тем же hold
      hold,
      // Записанное: отбор select, пул — только инциденты оставленных векторов
      take() {
        settle();
        const chosen = new Set(select(kept.map((k) => k.vector)));
        const incidents = {};
        kept.filter((k) => chosen.has(k.vector)).forEach((k) => Object.assign(incidents, k.pool));
        return { incidents, vectors: kept.filter((k) => chosen.has(k.vector)).map((k) => k.vector), skipped: Object.assign({}, skipped) };
      },
    };
  }

  const lib = { PER_NAME, PER_OUTCOME, normalize, kindOf, outcomeOf, select, idOf, recorder };
  // Запись — tests/api.html?celVectors=1 (без ?api=), вместе с записью векторов CEL: кадр — её IMCelVectors.frame.
  // Подключение к api.html — задача 7
  const params = typeof location !== "undefined" && location.search ? new URLSearchParams(location.search) : null;
  const recording = Boolean(params && params.get("celVectors") === "1" && !params.has("api") && window.IMEngine && window.IMCelVectors && window.IMCelVectors.recording);
  let rec = null;
  if (recording) {
    rec = recorder(window.IMEngine.create, window.IM_WORKFLOW, window.IMCelVectors.frame);
    window.IMEngine.create = rec.create;
  }
  window.IMTransitionVectors = {
    lib,
    recording,
    take: () => (rec ? rec.take() : { incidents: {}, vectors: [], skipped: { nowChanged: 0, outsideEngine: 0, tapeRepeat: 0, worldError: 0 } }),
  };
})();
