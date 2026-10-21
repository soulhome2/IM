/* Язык выражений машины: Specification/Workflow_machine/CEL.md (ARCH-07). Из раздела cel машины —
   типы, факты мира, настройки, определения — строит окружение CEL, вычисляет условия реестра (expr) и
   выполняет операции эффектов (do). Правил IM здесь нет: смысл каждого слова записан в машине, здесь — только её разбор,
   проверка «что из CEL можно» и перевод значений. Факты мира даёт тот, кто вычисляет (исполнитель
   engine.js — из данных сервера). Библиотека CEL — window.CEL (vendor/cel-js). Тем же кодом машину
   проверяет tools/check_cel.mjs. */
(() => {
  // Что из CEL можно (CEL.md): узлы дерева разбора cel-js и методы списков
  const OPS = new Set(["id", "value", ".", "[]", "list", "map", "call", "rcall", "?:", "!_", "-_", "in", "==", "!=", "<", "<=", ">", ">=", "&&", "||", "+", "-", "*"]);
  const METHODS = new Set(["exists", "all", "filter", "map"]);
  // Имена в выражениях условий (CEL.md, «Имена в выражениях»)
  const TOP = { me: "string", actor: "string", incident: "Incident", incidents: "list<Incident>", form: "Form", surface: "string", now: "int", deadline: "int" };
  const own = (o) => Object.entries(o || {}).filter(([k]) => !k.startsWith("$"));
  const byPath = (root, path) => String(path).split(".").reduce((o, k) => (o == null ? undefined : o[k]), root);

  const cache = new WeakMap();
  function create(W) {
    if (!cache.has(W)) cache.set(W, build(W));
    return cache.get(W);
  }

  function build(W) {
    const spec = W.cel || {};
    const errors = [];
    const types = Object.fromEntries(own(spec.types));
    const classes = Object.fromEntries(Object.keys(types).map((n) => [n, { [n]: class { constructor(o) { Object.assign(this, o); } } }[n]]));
    // Значение CEL → откуда оно взято: инцидент сервера для фактов мира
    const sources = new WeakMap();

    // Данные → значение CEL по типу: пусто — '' и 0, целые — BigInt (CEL.md, «Типы»). opt<T> — необязательное
    // поле: список из нуля или одного значения. Словарь CEL (Map) читается как объект
    function value(type, v, source) {
      if (v instanceof Map) v = Object.fromEntries(v);
      if (type === "string") return v == null ? "" : String(v);
      if (type === "int") return v == null || v === "" ? 0n : BigInt(Math.trunc(Number(v)));
      if (type === "bool") return Boolean(v);
      if (type === "dyn") return dyn(v);
      let m = type.match(/^opt<(.+)>$/);
      if (m) return v == null ? [] : [value(m[1], v)];
      m = type.match(/^list<(.+)>$/);
      if (m) return Array.from(v || [], (x) => value(m[1], x));
      m = type.match(/^map<(string|int), ?(.+)>$/);
      if (m) return new Map(Object.entries(v || {}).map(([k, x]) => [m[1] === "int" ? BigInt(k) : k, value(m[2], x)]));
      if (!classes[type]) throw new Error(`cel: unknown type ${type}`);
      if (v instanceof classes[type]) return v;
      const fields = {};
      own(types[type]).forEach(([f, t]) => {
        fields[f] = value(t, v ? v[f] : undefined);
      });
      const inst = new classes[type](fields);
      if (source || (v && typeof v === "object")) sources.set(inst, source || v);
      return inst;
    }
    const dyn = (v) => (typeof v === "number" ? BigInt(Math.trunc(v)) : Array.isArray(v) ? Array.from(v, dyn) : v == null ? "" : v);
    // Значение CEL → данные: для подстановок в тексты
    const out = (v) => (typeof v === "bigint" ? Number(v) : Array.isArray(v) ? v.map(out) : v instanceof Map ? Object.fromEntries([...v].map(([k, x]) => [k, out(x)])) : v);
    // То же целиком, вместе с записями типов: для сверки двух исполнений
    const plain = (v) =>
      typeof v === "bigint" ? Number(v) : Array.isArray(v) ? v.map(plain) : v instanceof Map ? Object.fromEntries([...v].map(([k, x]) => [String(k), plain(x)])) : v && typeof v === "object" ? Object.fromEntries(Object.entries(v).map(([k, x]) => [k, plain(x)])) : v;

    // Окружение: типы, факты мира, настройки, определения; у каждого выражения — своя копия (clone)
    const root = new CEL.Environment({ homogeneousAggregateLiterals: false });
    const celType = (t) => t.replace(/opt<([^<>]+)>/g, "list<$1>");
    Object.entries(types).forEach(([n, fields]) => root.registerType(n, { ctor: classes[n], fields: Object.fromEntries(own(fields).map(([f, t]) => [f, celType(t)])) }));
    let world = null;
    own(spec.world).forEach(([name, f]) => {
      root.registerFunction(`${name}(${own(f.params).map(([, t]) => t).join(", ")}): ${f.returns}`, (...a) => {
        if (!world || !world[name]) throw new Error(`cel: world.${name} is not given`);
        return value(f.returns, world[name](...a));
      });
    });
    // Настройка — раздел машины по имени или значение по пути from. Список — переменной, а не константой:
    // у константы-списка cel-js теряет тип элементов; значение подставляется в каждое вычисление
    const lists = {};
    own(spec.settings).forEach(([name, s]) => {
      const type = typeof s === "string" ? s : s.type;
      const v = value(type, typeof s === "string" ? W[name] : byPath(W, s.from));
      if (type.startsWith("list<")) {
        root.registerVariable(name, type);
        lists[name] = v;
      } else root.registerConstant(name, type, v);
    });
    const defs = {};
    const known = new Set(["size", ...own(spec.world).map(([n]) => n), ...own(spec.definitions).map(([n]) => n)]);
    own(spec.definitions).forEach(([name, d]) => {
      const params = own(d.params);
      root.registerFunction(`${name}(${params.map(([, t]) => t).join(", ")}): ${d.returns}`, (...a) => {
        if (!defs[name]) throw new Error(`cel: definition ${name} is not compiled`);
        return defs[name](Object.assign({}, lists, Object.fromEntries(params.map(([p], i) => [p, a[i]]))));
      });
    });

    function subset(n, where) {
      if (!n || typeof n !== "object") return;
      if (!OPS.has(n.op)) errors.push(`${where}: «${n.op}» — не из разрешённой части CEL (CEL.md)`);
      if (n.op === "value" && typeof n.args === "number") errors.push(`${where}: дробное число — в машине только целые`);
      if (n.op === "rcall") {
        const [m, recv, args] = n.args;
        const bind = m === "bind" && recv.op === "id" && recv.args === "cel";
        if (!bind && !METHODS.has(m)) errors.push(`${where}: метод .${m}() — не из разрешённой части CEL (CEL.md)`);
        if (!bind) subset(recv, where);
        args.forEach((a) => subset(a, where));
      } else if (n.op === "call") {
        const [fn, args] = n.args;
        if (!known.has(fn)) errors.push(`${where}: ${fn}() — не факт мира и не определение`);
        args.forEach((a) => subset(a, where));
      } else if (n.op === ".") subset(n.args[0], where);
      else if (n.op === "map") n.args.forEach(([k, v]) => (subset(k, where), subset(v, where)));
      else if (Array.isArray(n.args)) n.args.forEach((a) => subset(a, where));
      else subset(n.args, where);
    }
    // Разбор и проверка выражения; want — тип результата, который нужен
    function compile(where, vars, expr, want) {
      if (typeof expr !== "string" || !expr.trim()) {
        errors.push(`${where}: нет выражения`);
        return null;
      }
      const env = root.clone();
      Object.entries(vars).forEach(([n, t]) => env.registerVariable(n, t));
      try {
        subset(CEL.parse(expr).ast, where);
        const chk = env.check(expr);
        if (!chk.valid) {
          errors.push(`${where}: ${String(chk.error.message).split("\n")[0]}`);
          return null;
        }
        if (want && String(chk.type) !== want) errors.push(`${where}: результат ${chk.type}, а нужен ${want}`);
        const fn = env.parse(expr);
        fn.celType = String(chk.type);
        return fn;
      } catch (e) {
        errors.push(`${where}: ${String(e.message).split("\n")[0]}`);
        return null;
      }
    }
    own(spec.definitions).forEach(([name, d]) => {
      defs[name] = compile(`cel.definitions.${name}`, Object.fromEntries(own(d.params)), d.expr, d.returns);
    });

    // Условия реестра с expr. Аргумент типа setting — путь к настройке: в выражение приходит её значение;
    // usage — поля самого условия в переходе (scopeRule у hasScopedPermission). failVars — подстановки
    // в текст причины: по имени или одним выражением-словарём (пустой — без подстановок)
    const guards = {};
    (W.registries.guards || []).forEach((g) => {
      if (g.expr == null) return;
      const where = `registries.guards.${g.fn}`;
      const argTypes = g.argTypes || {};
      const vars = Object.assign({}, TOP);
      (g.args || []).forEach((a) => {
        if (!argTypes[a]) errors.push(`${where}: нет argTypes.${a}`);
        vars[a] = argTypes[a] === "setting" || !argTypes[a] ? "dyn" : argTypes[a];
      });
      Object.assign(vars, g.usage || {});
      if (!g.failKey && !(g.failKeys || []).length) errors.push(`${where}: нет failKey и failKeys — какую причину давать`);
      guards[g.fn] = {
        g,
        argTypes,
        test: compile(where, vars, g.expr, "bool"),
        key: g.failKey != null ? compile(`${where}.failKey`, vars, g.failKey, "string") : null,
        vars: typeof g.failVars === "string" ? compile(`${where}.failVars`, vars, g.failVars) : own(g.failVars).map(([k, e]) => [k, compile(`${where}.failVars.${k}`, vars, e)]),
      };
    });

    // Контекст выражения: имена верхнего уровня и аргументы слова. incident — значение CEL;
    // incidents — функция: список строится, только если выражение его спрашивает
    function baseContext(scope) {
      world = scope.world;
      const ctx = {
        ...lists,
        me: value("string", scope.me),
        actor: value("string", scope.actor),
        incident: scope.incident,
        form: value("Form", scope.form || {}),
        surface: value("string", scope.surface),
        now: value("int", scope.now),
        deadline: value("int", scope.deadline != null ? scope.deadline : scope.now),
      };
      let list = null;
      Object.defineProperty(ctx, "incidents", { enumerable: true, get: () => list || (list = Array.from(scope.incidents(), (x) => x)) });
      return ctx;
    }
    function contextOf(c, args, scope, use) {
      const ctx = baseContext(scope);
      (c.g.args || []).forEach((a, i) => {
        const t = c.argTypes[a];
        ctx[a] = t === "setting" ? dyn(byPath(W, args[i])) : value(t || "dyn", t && t.startsWith("list<") && !Array.isArray(args[i]) ? [args[i]] : args[i]);
      });
      own(c.g.usage).forEach(([field, t]) => {
        ctx[field] = value(t, use ? use[field] : undefined);
      });
      return ctx;
    }
    // null — условие выполнено; иначе причина [ключ] или [ключ, подстановки], как у функций исполнителя
    function guard(fn, args, scope, use) {
      const c = guards[fn];
      const ctx = contextOf(c, args, scope, use);
      if (c.test(ctx) === true) return null;
      const key = c.key ? c.key(ctx) : c.g.failKeys[0];
      const vars = typeof c.vars === "function" ? out(c.vars(ctx)) : Object.fromEntries(c.vars.map(([k, f]) => [k, out(f(ctx))]));
      return Object.keys(vars).length ? [key, vars] : [key];
    }

    /* ===== Правила интерфейса: бейджи, фильтры очереди, формы (CEL.md, «Правила интерфейса») ===== */

    // Имена — как у условий, у вариантов поля ещё option. Разбираются все при загрузке машины: ошибку в любом
    // видит проверка машины. Ключ правила — путь в машине, например forms.close.fields.comment.requiredExpr
    const rules = {};
    const refs = {};
    // Поля формы, которые читает выражение (form.<поле>): от них зависит, видно ли поле и обязательно ли
    const formRefs = (n, out) => {
      if (!n || typeof n !== "object") return out;
      if (n.op === "." && n.args[0] && n.args[0].op === "id" && n.args[0].args === "form") out.add(n.args[1]);
      (Array.isArray(n.args) ? n.args : [n.args]).forEach((a) => (Array.isArray(a) ? a.forEach((x) => formRefs(x, out)) : formRefs(a, out)));
      return out;
    };
    function uiRule(where, expr, want) {
      rules[where] = compile(where, Object.assign({}, TOP, { option: "string" }), expr, want);
      try {
        refs[where] = [...formRefs(CEL.parse(expr).ast, new Set())];
      } catch (e) {
        refs[where] = [];
      }
    }
    ((W.badges || {}).rules || []).forEach((b, i) => uiRule(`badges.rules.${i}.expr`, b.expr, "bool"));
    (W.queueFilters || []).forEach((q) => uiRule(`queueFilters.${q.id}.expr`, q.expr, "bool"));
    (W.forms || []).forEach((f) => {
      (f.notes || []).forEach((n, i) => uiRule(`forms.${f.id}.notes.${i}.expr`, n.expr, "bool"));
      f.fields.forEach((field) => {
        const at = `forms.${f.id}.fields.${field.name}`;
        uiRule(`${at}.requiredExpr`, field.requiredExpr, "bool");
        [["visibleExpr", "bool"], ["optionExpr", "bool"], ["enabledExpr", "bool"], ["defaultExpr", "string"]].forEach(([k, t]) => {
          if (field[k] != null) uiRule(`${at}.${k}`, field[k], t);
        });
      });
    });
    // Значение правила: scope — как у условий, option — вариант поля
    function rule(where, scope, option) {
      if (!rules[where]) throw new Error(`cel: no rule ${where}`);
      return rules[where](Object.assign(baseContext(scope), { option: value("string", option) }));
    }

    /* ===== Эффекты реестра с do (CEL.md, «Операции эффектов») ===== */

    // Тип аргумента эффекта: литерал (string, bool, int) — значение из перехода; setting — путь к настройке;
    // expr<T> — выражение CEL в переходе, вычисляется в начале эффекта. Литерал-строка подставляется в пути
    // и выражения как ${имя}: так setFlag и increment называют поле инцидента. Аргументы, которых в переходе
    // нет, — из defaults реестра. У вызванного call эффекта аргументы — значения, подстановок нет
    const effectDefs = Object.fromEntries((W.registries.effects || []).filter((e) => e.do).map((e) => [e.fn, e]));
    const EFFECT_TOP = Object.assign({}, TOP, { before: "Incident" });
    const exprOf = (t) => /^expr<(.+)>$/.exec(t || "");
    const varType = (t) => (t === "setting" ? "dyn" : exprOf(t) ? exprOf(t)[1] : t || "dyn");
    const PATH = /^([A-Za-z_]\w*)((?:\.[A-Za-z_]\w*|\[[A-Za-z_]\w*\])+)$/;
    const programs = new Map();

    function argsOf(e, args) {
      return (e.args || []).map((name, i) => [name, args && args[i] !== undefined ? args[i] : (e.defaults || {})[name]]);
    }
    // Тип значения по пути set / append: поле записи, элемент словаря по ключу-переменной
    function pathOf(path, scope, where) {
      const m = PATH.exec(path || "");
      if (!m) return errors.push(`${where}: путь «${path}» — имя и поля через точку или [имя]`), null;
      let t = scope[m[1]];
      if (!t) return errors.push(`${where}: в пути «${path}» нет имени ${m[1]}`), null;
      if (m[1] === "before") return errors.push(`${where}: before — инцидент до перехода, его не меняют`), null;
      const segs = [];
      for (const [, field, index] of m[2].matchAll(/\.(\w+)|\[(\w+)\]/g)) {
        if (field) {
          const f = types[t] && types[t][field];
          if (!f) return errors.push(`${where}: у ${t} нет поля ${field}`), null;
          segs.push({ field });
          t = f;
        } else {
          const mm = /^map<string, ?(.+)>$/.exec(t);
          if (!mm || scope[index] !== "string") return errors.push(`${where}: [${index}] — ключ-строка словаря`), null;
          segs.push({ index });
          t = mm[1];
        }
      }
      return { root: m[1], segs, type: t };
    }
    // Значение по типу: запись — тем же типом или словарём-литералом с теми же полями (в8)
    function fits(where, type, fn, expr, shapes) {
      if (!fn) return;
      const v = fn.celType;
      if (classes[type]) {
        if (v === type) return;
        let ast = CEL.parse(expr).ast;
        if (ast.op === "id" && shapes[ast.args]) ast = CEL.parse(shapes[ast.args]).ast;
        if (ast.op !== "map") return errors.push(`${where}: нужен ${type} или словарь с его полями, а не ${v}`);
        const keys = ast.args.map(([k]) => (k.op === "value" ? k.args : "?")).sort();
        const want = own(types[type]).map(([f]) => f).sort();
        if (keys.join() !== want.join()) errors.push(`${where}: поля словаря ${keys.join(", ")}, а у ${type} — ${want.join(", ")}`);
      } else if (v !== "dyn" && v !== celType(type)) errors.push(`${where}: значение ${v}, а нужно ${type}`);
    }
    function compileOps(ops, scope, where, sub, shapes) {
      scope = Object.assign({}, scope);
      shapes = Object.assign({}, shapes);
      return (ops || []).map((op, i) => {
        const at = `${where}.do[${i}]`;
        const x = (e) => compile(at, scope, sub(e));
        if ("let" in op) {
          const fn = x(op.value);
          scope[op.let] = fn ? fn.celType : "dyn";
          shapes[op.let] = sub(op.value);
          return { kind: "let", name: op.let, fn };
        }
        if ("set" in op || "append" in op) {
          const kind = "set" in op ? "set" : "append";
          const p = pathOf(sub(op[kind]), scope, at);
          const fn = x(op.value);
          if (!p) return { kind: "skip" };
          let type = p.type;
          if (kind === "append") {
            const m = /^list<(.+)>$/.exec(type);
            if (!m) return errors.push(`${at}: append — в список, а ${op.append} — ${type}`), { kind: "skip" };
            type = m[1];
          }
          fits(at, type, fn, sub(op.value), shapes);
          return { kind, path: p, type, fn };
        }
        if ("if" in op) return { kind: "if", fn: compile(at, scope, sub(op.if), "bool"), then: compileOps(op.then, scope, `${at}.then`, sub, shapes), else: compileOps(op.else, scope, `${at}.else`, sub, shapes) };
        if ("forEach" in op) {
          const fn = x(op.in);
          const m = /^list<(.+)>$/.exec(fn ? fn.celType : "");
          if (fn && !m) errors.push(`${at}: forEach — по списку, а ${op.in} — ${fn.celType}`);
          return { kind: "forEach", name: op.forEach, fn, body: compileOps(op.do, Object.assign({}, scope, { [op.forEach]: m ? m[1] : "dyn" }), at, sub, shapes) };
        }
        if ("call" in op) {
          const callee = effectDefs[op.call];
          if (!callee) return errors.push(`${at}: call ${op.call} — нет эффекта с do`), { kind: "skip" };
          return { kind: "call", fn: op.call, args: (callee.args || []).map((a) => [a, x((op.args || {})[a])]) };
        }
        if ("world" in op) return { kind: "world", action: op.world, args: own(op.args).map(([k, e]) => [k, x(e)]) };
        errors.push(`${at}: неизвестная операция ${JSON.stringify(op)}`);
        return { kind: "skip" };
      });
    }
    // Программа эффекта: на переход (use — литералы аргументов из перехода) или на вызов (call)
    function program(fn, args, mode, stack) {
      const key = `${fn}|${mode}|${mode === "use" ? JSON.stringify(args || []) : ""}`;
      if (programs.has(key)) return programs.get(key);
      const e = effectDefs[fn];
      const where = `registries.effects.${fn}`;
      const types_ = e.argTypes || {};
      const vals = argsOf(e, args);
      const scope = Object.assign({}, EFFECT_TOP);
      vals.forEach(([name]) => {
        if (!types_[name]) errors.push(`${where}: нет argTypes.${name}`);
        scope[name] = varType(types_[name]);
      });
      const literal = Object.fromEntries(vals.filter(([n, v]) => mode === "use" && typeof v === "string" && !exprOf(types_[n])).map(([n, v]) => [n, v]));
      const sub = (s) => (typeof s === "string" ? s.replace(/\$\{(\w+)\}/g, (m, n) => (n in literal ? literal[n] : (errors.push(`${where}: \${${n}} — не литерал-строка`), m))) : s);
      const prog = { e, vals, exprs: {}, ops: null };
      programs.set(key, prog);
      if (mode === "use") vals.forEach(([n, v]) => {
        if (exprOf(types_[n])) prog.exprs[n] = compile(`${where}(${n} = ${JSON.stringify(v)})`, EFFECT_TOP, v, exprOf(types_[n])[1] === "dyn" ? null : exprOf(types_[n])[1]);
      });
      Object.entries(prog.exprs).forEach(([n, f]) => {
        if (f) scope[n] = f.celType;
      });
      prog.ops = compileOps(e.do, scope, where, sub);
      return prog;
    }
    function locate(p, ctx) {
      let holder = ctx[p.root];
      const root = holder;
      const get = (o, s) => (s.field ? o[s.field] : o.get(ctx[s.index]));
      p.segs.slice(0, -1).forEach((s) => (holder = get(holder, s)));
      const last = p.segs[p.segs.length - 1];
      if (holder == null || (last.index && !holder.has(ctx[last.index]))) throw new Error(`cel: path ${p.root} → ${JSON.stringify(p.segs)} is empty`);
      return {
        root,
        get: () => get(holder, last),
        put: (v) => (last.field ? (holder[last.field] = v) : holder.set(ctx[last.index], v)),
      };
    }
    function runOps(ops, ctx, store) {
      for (const op of ops) {
        if (op.kind === "let") ctx[op.name] = op.fn(ctx);
        else if (op.kind === "set" || op.kind === "append") {
          const at = locate(op.path, ctx);
          const v = value(op.type, op.fn(ctx));
          at.put(op.kind === "set" ? v : at.get().concat([v]));
          store.touch(at.root);
        } else if (op.kind === "if") runOps(op.fn(ctx) ? op.then : op.else, Object.assign({}, ctx), store);
        else if (op.kind === "forEach") Array.from(op.fn(ctx)).forEach((item) => runOps(op.body, Object.assign({}, ctx, { [op.name]: item }), store));
        else if (op.kind === "call") {
          const base = Object.fromEntries(Object.keys(EFFECT_TOP).map((n) => [n, ctx[n]]));
          runProgram(program(op.fn, null, "call"), Object.assign({}, lists, base, Object.fromEntries(op.args.map(([a, f]) => [a, f ? f(ctx) : undefined]))), store);
        } else if (op.kind === "world") store.world(op.action, Object.fromEntries(op.args.map(([k, f]) => [k, f ? f(ctx) : undefined])));
      }
    }
    function runProgram(prog, ctx, store) {
      runOps(prog.ops, ctx, store);
    }
    // scope — как у условий плюс before; store — мост к данным: instance(id), incidents(), touch(значение), world(действие)
    function effect(fn, args, scope, store) {
      const prog = program(fn, args, "use");
      world = scope.world;
      const ctx = {
        ...lists,
        me: value("string", scope.me),
        actor: value("string", scope.actor),
        incident: scope.incident,
        before: scope.before,
        form: value("Form", scope.form || {}),
        surface: value("string", scope.surface),
        now: value("int", scope.now),
        deadline: value("int", scope.deadline != null ? scope.deadline : scope.now),
      };
      let list = null;
      Object.defineProperty(ctx, "incidents", { enumerable: true, get: () => list || (list = Array.from(store.incidents(), (x) => x)) });
      const t = prog.e.argTypes || {};
      prog.vals.forEach(([n, v]) => {
        ctx[n] = t[n] === "setting" ? dyn(byPath(W, v)) : exprOf(t[n]) ? prog.exprs[n](ctx) : value(t[n] || "dyn", v);
      });
      runProgram(prog, ctx, store);
    }

    return {
      errors,
      types,
      value,
      out,
      plain,
      source: (v) => sources.get(v),
      hasGuard: (fn) => Boolean(guards[fn]),
      guard,
      guardNames: () => Object.keys(guards),
      hasEffect: (fn) => Boolean(effectDefs[fn]),
      effectNames: () => Object.keys(effectDefs),
      // Разбор эффекта на переход без исполнения — для проверки машины
      compileEffect: (fn, args) => program(fn, args, "use"),
      // Определение машины по имени — для сервера и форм: значения CEL на входе и на выходе
      call: (name, args, w) => {
        const d = (spec.definitions || {})[name];
        if (!d || !defs[name]) throw new Error(`cel: no definition ${name}`);
        world = w;
        return defs[name](Object.assign({}, lists, Object.fromEntries(own(d.params).map(([p], i) => [p, args[i]]))));
      },
      effect,
      // Правила интерфейса: есть ли правило, его значение, какие поля формы оно читает
      hasRule: (where) => Boolean(rules[where]),
      rule,
      ruleNames: () => Object.keys(rules),
      formRefs: (where) => refs[where] || [],
    };
  }

  window.IMCel = { create };
})();
