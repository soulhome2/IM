// Модель Quint из машины (Specification/Workflow_machine/CEL.md, «Перевод в Quint»; ARCH-07.6).
// Из машины переводятся типы, значения настроек, определения, условия и эффекты каждого перехода и таблицы
// переходов; руками пишутся мир модели, ядро исполнения, действия окружения и инварианты — части
// quint/src/*.qnt. Итог — quint/im.qnt, руками его не править.
// Запуск из корня репозитория: node tools/gen_quint.mjs; --check — im.qnt совпадает со сгенерированным;
// --machine=путь --out=путь — другая машина и другой файл (порчи машины, tools/check_quint_mutations.mjs);
// --src=папка — другие ручные части
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const Q = path.join(ROOT, "Specification/Workflow_machine/quint");
const opt = (name) => (process.argv.find((a) => a.startsWith(`--${name}=`)) || "").slice(name.length + 3) || null;
const W = JSON.parse(fs.readFileSync(opt("machine") || path.join(ROOT, "Specification/Workflow_machine/workflow_schema.v1.json"), "utf8"));
const g = { console, TextEncoder, TextDecoder };
g.window = g;
vm.createContext(g);
vm.runInContext(fs.readFileSync(path.join(ROOT, "prototype/vendor/cel-js/cel.js"), "utf8"), g);
const parse = (expr) => g.CEL.parse(expr).ast;

const own = (o) => Object.entries(o || {}).filter(([k]) => !k.startsWith("$"));
const spec = W.cel;
const TYPES = Object.fromEntries(own(spec.types));
const DEFS = Object.fromEntries(own(spec.definitions));
const WORLD = Object.fromEntries(own(spec.world));
const SETTINGS = Object.fromEntries(own(spec.settings).map(([n, s]) => [n, typeof s === "string" ? { type: s, from: n } : s]));
const GUARDS = Object.fromEntries(W.registries.guards.map((x) => [x.fn, x]));
const EFFECTS = Object.fromEntries(W.registries.effects.map((x) => [x.fn, x]));
const fail = (msg) => {
  throw new Error(msg);
};

/* ===== Типы ===== */

// Тип машины → тип Quint: opt<T> — список из нуля или одного значения (CEL.md)
function qt(t) {
  let m;
  if (t === "string") return "str";
  if (t === "int" || t === "bool") return t;
  if ((m = /^(?:list|opt)<(.+)>$/.exec(t))) return `List[${qt(m[1])}]`;
  if ((m = /^map<(string|int), ?(.+)>$/.exec(t))) return `${qt(m[1] === "int" ? "int" : "string")} -> ${qt(m[2])}`;
  if (TYPES[t]) return t;
  fail(`тип ${t} не переводится в Quint`);
}
const elem = (t) => {
  const m = /^(?:list|opt)<(.+)>$/.exec(t || "");
  return m ? m[1] : null;
};
const mapOf = (t) => /^map<(string|int), ?(.+)>$/.exec(t || "");

// Значение данных машины → литерал Quint по типу: пусто — "" и 0 (CEL.md, «Типы»)
function lit(t, v) {
  let m;
  if (t === "string") return JSON.stringify(v == null ? "" : String(v));
  if (t === "int") return String(v == null ? 0 : Math.trunc(Number(v)));
  if (t === "bool") return v ? "true" : "false";
  if ((m = /^opt<(.+)>$/.exec(t))) return v == null ? "[]" : `[${lit(m[1], v)}]`;
  if ((m = /^list<(.+)>$/.exec(t))) return `[${(v || []).map((x) => lit(m[1], x)).join(", ")}]`;
  if ((m = mapOf(t))) {
    const e = Object.entries(v || {});
    return e.length ? `Map(${e.map(([k, x]) => `${m[1] === "int" ? k : JSON.stringify(k)} -> ${lit(m[2], x)}`).join(", ")})` : "Map()";
  }
  if (TYPES[t]) return `{ ${own(TYPES[t]).map(([f, ft]) => `${f}: ${lit(ft, v ? v[f] : undefined)}`).join(", ")} }`;
  fail(`значение типа ${t} не переводится`);
}

/* ===== Выражения ===== */

// scope: имя → { t: тип машины, q: текст Quint }; типы выводятся по типам машины, сигнатурам и литералам
function typeOf(n, scope) {
  switch (n.op) {
    case "id":
      if (scope[n.args]) return scope[n.args].t;
      if (SETTINGS[n.args]) return SETTINGS[n.args].type;
      return fail(`неизвестное имя ${n.args}`);
    case "value":
      return typeof n.args === "string" ? "string" : typeof n.args === "boolean" ? "bool" : "int";
    case ".": {
      const t = typeOf(n.args[0], scope);
      const f = TYPES[t] && TYPES[t][n.args[1]];
      return f || fail(`у ${t} нет поля ${n.args[1]}`);
    }
    case "[]": {
      const t = typeOf(n.args[0], scope);
      const m = mapOf(t);
      return m ? m[2] : elem(t) || fail(`[] у ${t}`);
    }
    case "list":
      return `list<${n.args.length ? typeOf(n.args[0], scope) : "string"}>`;
    case "map":
      return "map";
    case "?:":
      return typeOf(n.args[1], scope) === "map" ? typeOf(n.args[2], scope) : typeOf(n.args[1], scope);
    case "call": {
      const [fn] = n.args;
      if (fn === "size") return "int";
      return (DEFS[fn] || WORLD[fn] || fail(`нет функции ${fn}`)).returns;
    }
    case "rcall": {
      const [m, recv, args] = n.args;
      if (m === "bind") return typeOf(args[2], Object.assign({}, scope, { [args[0].args]: { t: typeOf(args[1], scope), q: "" } }));
      if (m === "exists" || m === "all") return "bool";
      if (m === "filter") return typeOf(recv, scope);
      if (m === "map") return `list<${typeOf(args[1], Object.assign({}, scope, { [args[0].args]: { t: elem(typeOf(recv, scope)), q: "" } }))}>`;
      return fail(`метод ${m}`);
    }
    case "+":
    case "-":
    case "*":
    case "-_":
      return "int";
    default:
      return "bool";
  }
}
let fresh = 0;
const nextName = (p) => `${p}${++fresh}`;
const BIN = { "==": "==", "!=": "!=", "&&": "and", "||": "or", "<": "<", "<=": "<=", ">": ">", ">=": ">=", "+": "+", "-": "-", "*": "*" };
function q(n, scope, want) {
  switch (n.op) {
    case "id":
      if (scope[n.args]) return scope[n.args].q;
      if (SETTINGS[n.args]) return `settings.${n.args}`;
      return fail(`неизвестное имя ${n.args}`);
    case "value":
      return typeof n.args === "string" ? JSON.stringify(n.args) : String(n.args);
    case ".":
      return `${q(n.args[0], scope)}.${n.args[1]}`;
    case "[]": {
      const t = typeOf(n.args[0], scope);
      return mapOf(t) ? `${q(n.args[0], scope)}.get(${q(n.args[1], scope)})` : `${q(n.args[0], scope)}[${q(n.args[1], scope)}]`;
    }
    case "list":
      return `[${n.args.map((a) => q(a, scope)).join(", ")}]`;
    case "map": {
      // Словарь-литерал — запись типа, куда его записывают (в8): поля сверяет проверка машины
      if (!n.args.length) return "Map()";
      return `{ ${n.args.map(([k, v]) => `${k.args}: ${q(v, scope)}`).join(", ")} }`;
    }
    case "!_":
      return `not(${q(n.args, scope)})`;
    case "-_":
      return `(0 - ${q(n.args, scope)})`;
    case "?:":
      return `(if (${q(n.args[0], scope)}) ${q(n.args[1], scope)} else ${q(n.args[2], scope)})`;
    case "in": {
      const t = typeOf(n.args[1], scope);
      const x = q(n.args[0], scope);
      if (mapOf(t)) return `${q(n.args[1], scope)}.keys().contains(${x})`;
      const v = nextName("y");
      return `${q(n.args[1], scope)}.foldl(false, (acc, ${v}) => acc or ${v} == ${x})`;
    }
    case "call": {
      const [fn, args] = n.args;
      if (fn === "size") return `${q(args[0], scope)}.length()`;
      // Без аргументов — значение мира модели
      if (!args.length) return fn;
      // Факт мира со смыслом ref (ARCH-12) — определение над списком инцидентов этого вычисления
      if (WORLD[fn] && WORLD[fn].ref != null) {
        if (!scope.incidents) fail(`${fn}(): факт над инцидентами — только в условиях, эффектах и правилах, не в определениях`);
        return `${fn}(${[scope.incidents.q, ...args.map((a) => q(a, scope))].join(", ")})`;
      }
      return `${fn}(${args.map((a) => q(a, scope)).join(", ")})`;
    }
    case "rcall": {
      const [m, recv, args] = n.args;
      if (m === "bind") {
        const name = args[0].args;
        const v = nextName(`${name}_`);
        const inner = Object.assign({}, scope, { [name]: { t: typeOf(args[1], scope), q: v } });
        return `{ val ${v} = ${q(args[1], scope)}  ${q(args[2], inner)} }`;
      }
      const r = q(recv, scope);
      const name = args[0].args;
      const v = nextName(`${name}_`);
      const inner = Object.assign({}, scope, { [name]: { t: elem(typeOf(recv, scope)), q: v } });
      const body = q(args[1], inner);
      if (m === "exists") return `${r}.foldl(false, (acc, ${v}) => acc or ${body})`;
      if (m === "all") return `${r}.foldl(true, (acc, ${v}) => acc and ${body})`;
      if (m === "filter") return `${r}.select(${v} => ${body})`;
      if (m === "map") return `${r}.foldl([], (acc, ${v}) => acc.append(${body}))`;
      return fail(`метод ${m}`);
    }
    default:
      if (BIN[n.op]) return `(${q(n.args[0], scope)} ${BIN[n.op]} ${q(n.args[1], scope)})`;
      return fail(`узел ${n.op} не переводится`);
  }
}
const expr = (s, scope) => q(parse(s), scope);
const exprType = (s, scope) => typeOf(parse(s), scope);

/* ===== Определения ===== */

const out = [];
const emit = (s) => out.push(s);
function definitions() {
  emit("  /* ===== Определения машины (cel.definitions) ===== */\n");
  for (const [name, d] of Object.entries(DEFS)) {
    const scope = Object.fromEntries(own(d.params).map(([p, t]) => [p, { t, q: p }]));
    if (d.$comment) emit(`  // ${d.$comment}`);
    emit(`  def ${name}(${own(d.params).map(([p, t]) => `${p}: ${qt(t)}`).join(", ")}): ${qt(d.returns)} =\n    ${expr(d.expr, scope)}`);
  }
  // Факты мира над множеством инцидентов (ARCH-12): смысл — выражение ref над списком инцидентов
  for (const [name, f] of Object.entries(WORLD).filter(([, f]) => f.ref != null)) {
    const scope = Object.assign({ incidents: { t: "list<Incident>", q: "incidents" } }, Object.fromEntries(own(f.params).map(([p, t]) => [p, { t, q: p }])));
    if (f.$comment) emit(`  // ${f.$comment}`);
    emit(`  def ${name}(${["incidents: List[Incident]", ...own(f.params).map(([p, t]) => `${p}: ${qt(t)}`)].join(", ")}): ${qt(f.returns)} =\n    ${expr(f.ref, scope)}`);
  }
}

/* ===== Условия и эффекты переходов ===== */

// Контекст перехода в модели: Ctx — кто, когда, форма, инцидент до перехода; World — инциденты и ответы сценария
const TOP = (w, iid) => ({
  me: { t: "string", q: "c.me" },
  actor: { t: "string", q: "c.actor" },
  form: { t: "Form", q: "c.form" },
  surface: { t: "string", q: "c.surface" },
  now: { t: "int", q: "c.now" },
  deadline: { t: "int", q: "c.deadline" },
  before: { t: "Incident", q: "c.before" },
  incident: { t: "Incident", q: `${w}.inc.get(${iid})` },
  incidents: { t: "list<Incident>", q: `incs(${w})` },
});
// Аргумент условия или эффекта в переходе → значение: литерал, путь к настройке, выражение
function argValue(type, v, scope) {
  const m = /^expr<(.+)>$/.exec(type || "");
  if (m) return { t: m[1] === "dyn" ? exprType(v, scope) : m[1], q: expr(v, scope) };
  if (type === "setting") return { t: settingType(v), q: settingQ(v) };
  if (type === "dyn") return { t: typeof v === "boolean" ? "bool" : typeof v === "number" ? "int" : "string", q: typeof v === "string" ? JSON.stringify(v) : String(v) };
  const t = type || "string";
  return { t, q: lit(t, Array.isArray(v) || !/^list</.test(t) ? v : [v]) };
}
function settingQ(p) {
  const [head, ...rest] = String(p).split(".");
  const s = Object.entries(SETTINGS).find(([, x]) => x.from === head);
  if (!s) fail(`настройка ${p}: раздела ${head} нет в cel.settings`);
  return [`settings.${s[0]}`, ...rest].join(".");
}
function settingType(p) {
  const [head, ...rest] = String(p).split(".");
  const s = Object.entries(SETTINGS).find(([, x]) => x.from === head);
  let t = s[1].type;
  rest.forEach((f) => (t = TYPES[t][f]));
  return t;
}
function guardCall(use, w, iid) {
  const reg = GUARDS[use.fn];
  const scope = TOP(w, iid);
  (reg.args || []).forEach((name, i) => {
    scope[name] = argValue((reg.argTypes || {})[name], (use.args || [])[i], scope);
  });
  own(reg.usage).forEach(([f, t]) => (scope[f] = { t, q: lit(t, use[f]) }));
  return expr(reg.expr, scope);
}

// Операции эффекта → блок Quint над World: каждая операция — новое значение мира (CEL.md, «Операции эффектов»)
function ops(list, ctx) {
  const lines = [];
  let w = ctx.w;
  let scope = ctx.scope;
  const sub = ctx.sub;
  const ref = (name) => {
    if (name === "incident") return ctx.iid;
    if (ctx.ids[name]) return ctx.ids[name];
    fail(`set / append — у ${name}: менять можно инцидент перехода или элемент forEach`);
  };
  const rebind = (nw) => {
    w = nw;
    scope = Object.assign({}, scope, { incident: { t: "Incident", q: `${w}.inc.get(${ctx.iid})` } });
    Object.entries(ctx.ids).forEach(([n, id]) => (scope[n] = { t: "Incident", q: `${w}.inc.get(${id})` }));
  };
  for (const op of list || []) {
    if ("let" in op) {
      const v = nextName(`${op.let}_`);
      const s = sub(op.value);
      lines.push(`val ${v} = ${expr(s, scope)}`);
      scope = Object.assign({}, scope, { [op.let]: { t: exprType(s, scope), q: v } });
    } else if ("set" in op || "append" in op) {
      const kind = "set" in op ? "set" : "append";
      const m = /^([A-Za-z_]\w*)((?:\.\w+|\[\w+\])+)$/.exec(sub(op[kind]));
      const id = ref(m[1]);
      const segs = [...m[2].matchAll(/\.(\w+)|\[(\w+)\]/g)].map(([, f, k]) => (f ? { f } : { k: scope[k].q }));
      const val = expr(sub(op.value), scope);
      const upd = (x, i) => {
        if (i === segs.length) return kind === "set" ? val : `${x}.append(${val})`;
        const s = segs[i];
        return s.f ? `{ ...${x}, ${s.f}: ${upd(`${x}.${s.f}`, i + 1)} }` : `${x}.set(${s.k}, ${upd(`${x}.get(${s.k})`, i + 1)})`;
      };
      const nw = nextName("w");
      lines.push(`val ${nw} = { ...${w}, inc: ${w}.inc.set(${id}, ${upd(`${w}.inc.get(${id})`, 0)}) }`);
      rebind(nw);
    } else if ("if" in op) {
      const nw = nextName("w");
      const branch = (b) => block(ops(b, Object.assign({}, ctx, { w, scope })), w);
      lines.push(`val ${nw} = if (${expr(sub(op.if), scope)}) ${branch(op.then)} else ${branch(op.else)}`);
      rebind(nw);
    } else if ("forEach" in op) {
      const nw = nextName("w");
      const acc = nextName("wf");
      const id = nextName(`${op.forEach}Id`);
      const x = nextName("x");
      const inner = Object.assign({}, ctx, { w: acc, ids: Object.assign({}, ctx.ids, { [op.forEach]: id }) });
      inner.scope = Object.assign({}, scope, { [op.forEach]: { t: "Incident", q: `${acc}.inc.get(${id})` }, incident: { t: "Incident", q: `${acc}.inc.get(${ctx.iid})` } });
      Object.entries(ctx.ids).forEach(([n, i]) => (inner.scope[n] = { t: "Incident", q: `${acc}.inc.get(${i})` }));
      const body = block(ops(op.do, inner), acc);
      lines.push(`val ${nw} = ${expr(sub(op.in), scope)}.foldl([], (acc, ${x}) => acc.append(${x}.id)).foldl(${w}, (${acc}, ${id}) => ${body})`);
      rebind(nw);
    } else if ("call" in op) {
      const callee = EFFECTS[op.call];
      const nw = nextName("w");
      const args = (callee.args || []).map((a) => expr((op.args || {})[a], scope));
      lines.push(`val ${nw} = ec_${op.call}(${[w, "c", ctx.iid, ...args].join(", ")})`);
      rebind(nw);
    } else if ("world" in op) {
      // Действия мира — не меняют инциденты модели, кроме переноса ответов сценария (пролог)
      if (op.world === "shareAnswers") {
        const nw = nextName("w");
        lines.push(`val ${nw} = shareAnswers(${w}, ${expr(op.args.from, scope)}.id, ${expr(op.args.to, scope)})`);
        rebind(nw);
      }
    }
  }
  return { lines, w };
}
const block = (r) => (r.lines.length ? `{\n${r.lines.map((l) => `      ${l}`).join("\n")}\n      ${r.w}\n    }` : r.w);

// Эффект на переход: литералы аргументов — в тексте, выражения — в начале эффекта (CEL.md)
function effectOnUse(e, name) {
  const reg = EFFECTS[e.fn];
  const scope = TOP("w0", "iid");
  const lines = [];
  const literal = {};
  (reg.args || []).forEach((a, i) => {
    const v = (e.args || [])[i] !== undefined ? e.args[i] : (reg.defaults || {})[a];
    const t = (reg.argTypes || {})[a];
    const av = argValue(t, v, scope);
    if (/^expr</.test(t)) {
      const nv = nextName(`${a}_`);
      lines.push(`val ${nv} = ${av.q}`);
      scope[a] = { t: av.t, q: nv };
    } else scope[a] = av;
    if (typeof v === "string" && !/^expr</.test(t)) literal[a] = v;
  });
  const sub = (s) => (typeof s === "string" ? s.replace(/\$\{(\w+)\}/g, (m, n) => literal[n]) : s);
  const r = ops(reg.do, { w: "w0", iid: "iid", ids: {}, scope, sub });
  emit(`  def ${name}(w0: World, c: Ctx, iid: str): World = {\n${[...lines, ...r.lines].map((l) => `    ${l}`).join("\n")}\n    ${r.w}\n  }`);
}
// Эффект, вызванный call: аргументы — значения
function effectOnCall(fn) {
  const reg = EFFECTS[fn];
  const scope = TOP("w0", "iid");
  const params = (reg.args || []).map((a) => {
    const t = (reg.argTypes || {})[a];
    const tt = /^expr<(.+)>$/.exec(t || "") ? /^expr<(.+)>$/.exec(t)[1] : t;
    scope[a] = { t: tt, q: a };
    return `${a}: ${qt(tt)}`;
  });
  const r = ops(reg.do, { w: "w0", iid: "iid", ids: {}, scope, sub: (s) => s });
  emit(`  def ec_${fn}(${["w0: World", "c: Ctx", "iid: str", ...params].join(", ")}): World = {\n${r.lines.map((l) => `    ${l}`).join("\n")}\n    ${r.w}\n  }`);
}
const called = new Set();
function collectCalls(list) {
  (list || []).forEach((op) => {
    if (op.call) {
      if (!called.has(op.call)) {
        called.add(op.call);
        collectCalls(EFFECTS[op.call].do);
      }
    }
    ["then", "else", "do"].forEach((k) => collectCalls(op[k]));
  });
}

function transitions() {
  emit("  /* ===== Переходы машины: условия (from и guards) и эффекты ===== */\n");
  W.registries.effects.forEach((e) => collectCalls(e.do));
  [...called].forEach(effectOnCall);
  const ok = [];
  const apply = [];
  for (const t of W.transitions) {
    const guards = (t.guards || []).map((x) => guardCall(x, "world", "iid"));
    const from = (t.from || []).length ? `Set(${t.from.map((s) => JSON.stringify(s)).join(", ")}).contains(world.inc.get(iid).state)` : `world.inc.get(iid).state == ""`;
    emit(`  // ${t.id}: ${t.trigger}${t.to ? ` → ${t.to}` : ""}`);
    emit(`  def ok_${t.id}(c: Ctx, iid: str): bool = all {\n    ${[from, ...guards].join(",\n    ")},\n  }`);
    const names = (t.effects || []).map((e, i) => {
      const name = `e_${t.id}_${i}`;
      effectOnUse(e, name);
      return name;
    });
    const steps = [`val c1 = { ...c, before: w0.inc.get(iid) }`];
    let w = "w0";
    if (t.to) {
      steps.push(`val ws = { ...w0, inc: w0.inc.set(iid, { ...w0.inc.get(iid), state: ${JSON.stringify(t.to)} }) }`);
      w = "ws";
    }
    names.forEach((n, i) => {
      steps.push(`val w${i + 1} = ${n}(${w}, c1, iid)`);
      w = `w${i + 1}`;
    });
    emit(`  def apply_${t.id}(c: Ctx, iid: str, w0: World): World = {\n${steps.map((s) => `    ${s}`).join("\n")}\n    ${w}\n  }`);
    ok.push(t.id);
    apply.push(t.id);
  }
  // Значения полей-списков формы — по правилам формы машины, как проверяет сервер (ARCH-09): поле видно
  // (visibleExpr), значение — из источника и проходит optionExpr и enabledExpr; пустое не проверяется
  const sourceQ = (source, v) => {
    if (source === "transferTargets") return `TARGETS.contains(${v})`;
    const cat = W.reasonCatalogs[String(source).replace("reasonCatalog:", "")];
    if (!cat) fail(`источник поля ${source}: нет справочника`);
    return `Set(${cat.items.map((x) => JSON.stringify(x.id)).join(", ")}).contains(${v})`;
  };
  const formOk = [];
  for (const t of W.transitions) {
    const f = t.form && W.forms.find((x) => x.id === t.form);
    const fields = f ? f.fields.filter((x) => x.source) : [];
    if (!fields.length) continue;
    const parts = fields.map((x) => {
      const v = `c.form.${x.name}`;
      const scope = Object.assign(TOP("world", "iid"), { option: { t: "string", q: v } });
      const conds = [x.visibleExpr != null ? expr(x.visibleExpr, scope) : null, sourceQ(x.source, v), x.optionExpr != null ? expr(x.optionExpr, scope) : null, x.enabledExpr != null ? expr(x.enabledExpr, scope) : null];
      return `${v} == "" or all {\n      ${conds.filter(Boolean).join(",\n      ")},\n    }`;
    });
    emit(`  def form_${t.id}(c: Ctx, iid: str): bool = all {\n    ${parts.join(",\n    ")},\n  }`);
    formOk.push(t.id);
  }
  emit(`  def formOk(tid: str, c: Ctx, iid: str): bool =\n    ${formOk.map((id) => `if (tid == ${JSON.stringify(id)}) form_${id}(c, iid)`).join("\n    else ")}\n    else true`);
  // Таблицы для ядра: условия и эффекты по имени перехода, вид, таймер, нарушение в окне после дедлайна
  emit(`  def trOk(tid: str, c: Ctx, iid: str): bool =\n    ${ok.map((id) => `if (tid == ${JSON.stringify(id)}) ok_${id}(c, iid)`).join("\n    else ")}\n    else false`);
  emit(`  def trApply(tid: str, c: Ctx, iid: str, w: World): World =\n    ${apply.map((id) => `if (tid == ${JSON.stringify(id)}) apply_${id}(c, iid, w)`).join("\n    else ")}\n    else w`);
  const timerOf = (t) => ((t.guards || []).find((x) => x.fn === "timerExpired") || { args: [""] }).args[0];
  const idleOf = (t) => ((t.guards || []).find((x) => x.fn === "agentIdleFor") || { args: [] }).args[0];
  emit(`  pure val TRANSITIONS: List[Transition] = [\n${W.transitions
    .map((t) => `    { id: ${JSON.stringify(t.id)}, trigger: ${JSON.stringify(t.trigger)}, actor: ${JSON.stringify(t.actor || "dispatcher")}, from: Set(${(t.from || []).map((x) => JSON.stringify(x)).join(", ")}), timer: ${JSON.stringify(timerOf(t))}, idleSec: ${idleOf(t) ? settingQ(idleOf(t)).replace(/^settings\./, "MACHINE_SETTINGS.") : 0}, ownedByAgent: ${t.scope === "incidents_owned_by_agent"}, surfaces: Set(${((t.ui || {}).surface || []).map((x) => JSON.stringify(x)).join(", ")}), bulkOnly: ${t.trigger === "manual" && !((t.ui || {}).surface || []).length} },`)
    .join("\n")}\n  ]`);
  // Нарушение, которое записал бы отменённый в окне переход: его эффекты recordBreach (CEL.md, «Ядро исполнения»)
  const breach = [];
  W.transitions.forEach((t) =>
    (t.effects || []).forEach((e, i) => {
      if (e.fn === "recordBreach") breach.push([t.id, `e_${t.id}_${i}`]);
    })
  );
  emit(`  def windowBreach(tid: str, c: Ctx, iid: str, w: World): World =\n    ${breach.map(([id, n]) => `if (tid == ${JSON.stringify(id)}) ${n}(w, c, iid)`).join("\n    else ")}\n    else w`);
  emit(`  pure val CONTINUES_ON: str -> Set[str] = Map(${W.timers.map((t) => `${JSON.stringify(t.id)} -> Set(${(t.continuesOn || []).map((x) => JSON.stringify(x)).join(", ")})`).join(", ")})`);
  emit(`  pure val GRACE_MS: int = ${((W.invariants.manualWinsOverTimer || {}).graceSec || 0) * 1000}`);
  emit(`  pure val TAKE_WITH: str = ${JSON.stringify(W.grouping.takeWith)}`);
  emit(`  pure val MERGE: str = ${JSON.stringify((W.transitions.find((t) => t.bulk && t.bulk.mode === "merge") || {}).id || "")}`);
  // Достижимость: переход выполнен — для quint run --witnesses
  emit(W.transitions.map((t) => `  val reached_${t.id} = lastAction.name == ${JSON.stringify(t.id)}`).join("\n"));
  emit(`  def scenarioEditOk(c: Ctx, iid: str): bool = all {\n    ${(W.scenarioEdit.guards || []).map((x) => guardCall(x, "world", "iid")).join(",\n    ")},\n  }`);
}

// Настройки, от которых зависят ветки автоматических переходов (PROC-43): аргументы типа setting в их условиях.
// Значения — логическая: да и нет; иначе — перечень настройки в adminSettings, значения, с которыми её
// сравнивают условия, и нынешнее. Все сочетания — BRANCH_SETTINGS, init модели берёт любое (withBranches):
// новая такая настройка попадает в перебор сама. Настройка с одним значением (порог молчания) не ветвит
function branchSettings(byPath) {
  const admin = {};
  (W.adminSettings.tabs || []).forEach((tab) => (tab.items || []).forEach((i) => i.values && (admin[i.path] = Object.keys(i.values).filter((k) => !k.startsWith("$")))));
  const values = new Map();
  for (const t of W.transitions.filter((x) => x.trigger === "timer" || x.trigger === "system")) {
    for (const use of t.guards || []) {
      const reg = GUARDS[use.fn] || {};
      (reg.args || []).forEach((name, i) => {
        if ((reg.argTypes || {})[name] !== "setting") return;
        const p = use.args[i];
        if (!settingType(p)) fail(`переход ${t.id}: настройка ${p} — нет её типа в cel.types`);
        if (!values.has(p)) values.set(p, new Set([byPath(p), ...(admin[p] || [])]));
        // Значение, с которым условие сравнивает настройку (settingIs)
        (reg.args || []).forEach((n2, j) => (reg.argTypes || {})[n2] === "dyn" && use.args[j] !== undefined && values.get(p).add(use.args[j]));
      });
    }
  }
  const branches = [...values]
    .map(([p, vs]) => [p, settingType(p) === "bool" ? [true, false] : [...vs]])
    .filter(([, vs]) => vs.length > 1)
    .sort(([a], [b]) => (a < b ? -1 : 1));
  // Ни одной — запись из одного служебного поля: пустой записи в Quint нет
  if (!branches.length) {
    emit("\n  type Branches = { none: bool }\n  pure val BRANCH_SETTINGS: Set[Branches] = Set({ none: true })\n  pure def withBranches(s: Settings, b: Branches): Settings = s");
    return;
  }
  const field = (p) => p.replace(/\./g, "_");
  const rec = `{ ${branches.map(([p]) => `${field(p)}: ${qt(settingType(p))}`).join(", ")} }`;
  let combos = [{}];
  for (const [p, vs] of branches) combos = combos.flatMap((c) => vs.map((v) => ({ ...c, [p]: v })));
  emit("\n  // Настройки, от которых зависят ветки автоматических переходов, — все сочетания (PROC-43)");
  emit(`  type Branches = ${rec}`);
  emit(`  pure val BRANCH_SETTINGS: Set[Branches] = Set(\n${combos.map((c) => `    { ${branches.map(([p]) => `${field(p)}: ${lit(settingType(p), c[p])}`).join(", ")} }`).join(",\n")}\n  )`);
  // Подстановка сочетания в настройки: по пути — вложенные записи
  const tree = {};
  branches.forEach(([p]) => {
    const parts = settingQ(p).split(".").slice(1);
    let node = tree;
    parts.slice(0, -1).forEach((k) => (node = node[k] = node[k] || {}));
    node[parts[parts.length - 1]] = `b.${field(p)}`;
  });
  const put = (node, at) => `{ ...${at}, ${Object.entries(node).map(([k, v]) => `${k}: ${typeof v === "string" ? v : put(v, `${at}.${k}`)}`).join(", ")} }`;
  emit(`  pure def withBranches(s: Settings, b: Branches): Settings = ${put(tree, "s")}`);
}

function header() {
  emit("  /* ===== Типы машины (cel.types) ===== */\n");
  for (const [n, f] of Object.entries(TYPES)) emit(`  type ${n} = { ${own(f).map(([k, t]) => `${k}: ${qt(t)}`).join(", ")} }`);
  emit(`  type Settings = { ${Object.entries(SETTINGS).map(([n, s]) => `${n}: ${qt(s.type)}`).join(", ")} }`);
  emit("\n  /* ===== Настройки — значения машины (cel.settings) ===== */\n");
  const byPath = (p) => p.split(".").reduce((o, k) => (o == null ? o : o[k]), W);
  emit(`  pure val MACHINE_SETTINGS: Settings = {\n${Object.entries(SETTINGS).map(([n, s]) => `    ${n}: ${lit(s.type, byPath(s.from))},`).join("\n")}\n  }`);
  emit(`  pure val STATES: Set[str] = Set(${W.states.map((s) => JSON.stringify(s.id)).join(", ")})`);
  // Смены состояния оператора (session.transitions): право — у состояния, куда переходят (ARCH-08 в4)
  const perm = (id) => (W.session.states.find((st) => st.id === id) || {}).permission || "";
  emit(`  pure val AGENT_MOVES: Set[{ id: str, from: Set[str], to: str, permission: str }] = Set(${W.session.transitions.map((t) => `{ id: ${JSON.stringify(t.id)}, from: Set(${t.from.map((x) => JSON.stringify(x)).join(", ")}), to: ${JSON.stringify(t.to)}, permission: ${JSON.stringify(perm(t.to))} }`).join(", ")})`);
  // С чего начинает оператор (RULE-99): начальное состояние машины или то, куда из него ведёт вход, — модель
  // проверяет и вход, не тратя на него шаги истории
  const initial = (W.session.states.find((st) => st.initial) || {}).id;
  if (!initial) fail("session.states: нет начального состояния (initial)");
  const starts = new Set([initial, ...W.session.transitions.filter((t) => t.from.includes(initial)).map((t) => t.to)]);
  emit(`  pure val AGENT_STARTS: Set[str] = Set(${[...starts].map((x) => JSON.stringify(x)).join(", ")})`);
  branchSettings(byPath);
  emit(`  pure val HOLD_REASONS_BY_OPERATOR: Set[str] = Set(${W.reasonCatalogs.hold.items.filter((i) => i.setBy !== "system").map((i) => JSON.stringify(i.id)).join(", ")})`);
  emit(`  pure val CLOSE_RESULT_IDS: Set[str] = Set(${W.reasonCatalogs.close_result.items.map((i) => JSON.stringify(i.id)).join(", ")})`);
  // Права, которые спрашивают условия машины и справочник результатов закрытия, — их перебирает модель
  const perms = new Set(["agent:set_not_ready"]);
  const walk = (o) => {
    if (Array.isArray(o)) return o.forEach(walk);
    if (!o || typeof o !== "object") return;
    if (o.fn === "hasPermission" || o.fn === "hasScopedPermission") (o.args || []).forEach((a) => perms.add(a));
    Object.values(o).forEach(walk);
  };
  walk(W.transitions);
  walk(W.navActions);
  W.reasonCatalogs.close_result.items.forEach((i) => perms.add(i.permission));
  emit(`  pure val USED_PERMISSIONS: Set[str] = Set(${[...perms].sort().map((p) => JSON.stringify(p)).join(", ")})`);
  emit(`  pure val TIMER_IDS: Set[str] = Set(${W.timers.map((t) => JSON.stringify(t.id)).join(", ")})`);
  emit(`  pure val NO_TIMER: Timer = ${lit("Timer", {})}`);
  emit(`  pure val NO_INCIDENT: Incident = { ...${lit("Incident", {})}, timers: Map(${W.timers.map((t) => `${JSON.stringify(t.id)} -> NO_TIMER`).join(", ")}) }`);
  emit(`  pure val NO_FORM: Form = ${lit("Form", {})}`);
  const mass = W.reasonCatalogs.close_result.items.find((i) => i.causeCatalog);
  emit(`  pure val CAUSE_FOR: str -> str = Map(${mass ? `${JSON.stringify(mass.id)} -> ${JSON.stringify(W.reasonCatalogs[mass.causeCatalog].items[0].id)}` : ""})`);
}

header();
definitions();
transitions();
// Ручные части — quint/src; --src=папка — другие (порчи ручных частей, tools/check_quint_mutations.mjs)
const part = (n) => fs.readFileSync(path.join(opt("src") || path.join(Q, "src"), n), "utf8").replace(/\s+$/, "");
const text = [
  "// -*- mode: Bluespec; -*-",
  "// Собрано скриптом tools/gen_quint.mjs из Specification/Workflow_machine/workflow_schema.v1.json и частей quint/src/.",
  "// Руками не править: правится машина или часть в src/, затем сборка.",
  part("head.qnt"),
  "",
  out.join("\n\n"),
  "",
  part("world.qnt"),
  "",
  part("core.qnt"),
  "",
  part("invariants.qnt"),
  "}",
  "",
].join("\n");
const target = opt("out") || path.join(Q, "im.qnt");
if (process.argv.includes("--check")) {
  const same = fs.existsSync(target) && fs.readFileSync(target, "utf8") === text;
  console.log(same ? "quint/im.qnt совпадает с машиной" : "quint/im.qnt устарел: node tools/gen_quint.mjs");
  process.exit(same ? 0 : 1);
}
fs.writeFileSync(target, text);
console.log(`Собран ${path.relative(ROOT, target)}`);
