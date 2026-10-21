// Выражения машины (Specification/Workflow_machine/CEL.md, ARCH-07): разбор и типы — тем же cel-js и тем же
// кодом prototype/cel-runtime.js, что у прототипа; плюс то, чего не видит CEL: аргументы условий в переходах
// против argTypes реестра, пути к настройкам. Запуск: node tools/check_cel.mjs [машина.json] — по умолчанию машина репозитория
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const W = JSON.parse(fs.readFileSync(process.argv[2] || path.join(ROOT, "Specification/Workflow_machine/workflow_schema.v1.json"), "utf8"));

const g = { console, TextEncoder, TextDecoder };
g.window = g;
vm.createContext(g);
for (const f of ["prototype/vendor/cel-js/cel.js", "prototype/cel-runtime.js"]) vm.runInContext(fs.readFileSync(path.join(ROOT, f), "utf8"), g, { filename: f });

const err = [];
let rt = null;
try {
  rt = g.IMCel.create(W);
  err.push(...rt.errors);
} catch (e) {
  err.push(`раздел cel: ${String(e.message).split("\n")[0]}`);
}

// Аргументы условий с expr — по argTypes реестра (CEL.md, «Где в машине»)
const registry = Object.fromEntries(W.registries.guards.map((x) => [x.fn, x]));
const byPath = (p) => String(p).split(".").reduce((o, k) => (o == null ? undefined : o[k]), W);
const fits = (type, v) => {
  if (type === "string") return typeof v === "string";
  if (type === "bool") return typeof v === "boolean";
  if (type === "int") return Number.isInteger(v);
  if (type === "dyn") return v !== undefined;
  const m = type.match(/^list<(.+)>$/);
  if (m) return Array.isArray(v) && v.every((x) => fits(m[1], x));
  return false;
};
function checkUse(use, where) {
  const reg = registry[use.fn];
  if (!reg || reg.expr == null) return;
  const names = reg.args || [];
  const args = use.args || [];
  if (args.length > names.length) err.push(`${where}: ${use.fn} — аргументов ${args.length}, в реестре ${names.length}`);
  let setting;
  names.forEach((name, i) => {
    const type = (reg.argTypes || {})[name];
    const v = args[i];
    if (v === undefined) return err.push(`${where}: ${use.fn} — нет аргумента ${name}`);
    if (!type) return;
    if (type === "setting") {
      setting = byPath(v);
      if (setting === undefined) err.push(`${where}: ${use.fn} — настройки ${v} в машине нет`);
      return;
    }
    if (!fits(type, v)) err.push(`${where}: ${use.fn} — аргумент ${name} = ${JSON.stringify(v)}, а нужен ${type}`);
    // Значение, с которым сравнивается настройка, — того же типа, что она
    if (type === "dyn" && setting !== undefined && typeof v !== typeof setting) err.push(`${where}: ${use.fn} — ${JSON.stringify(v)} сравнивается с настройкой типа ${typeof setting}`);
  });
}
function walk(node, where) {
  if (Array.isArray(node)) return node.forEach((x, i) => walk(x, `${where}[${i}]`));
  if (!node || typeof node !== "object") return;
  for (const [k, v] of Object.entries(node)) {
    if (k === "guards" && Array.isArray(v)) v.forEach((use, i) => use && use.fn && checkUse(use, `${where}.${node.id || k}[${i}]`));
    else walk(v, `${where}.${k}`);
  }
}
walk(Object.fromEntries(Object.entries(W).filter(([k]) => k !== "registries")), "машина");

// Эффекты переходов: программа эффекта на аргументы перехода,
// литералы — по argTypes реестра
const effects = Object.fromEntries(W.registries.effects.map((x) => [x.fn, x]));
for (const t of W.transitions) {
  (t.effects || []).forEach((e, i) => {
    const reg = effects[e.fn];
    if (!reg || !reg.do || !rt) return;
    const args = e.args || [];
    (reg.args || []).forEach((name, j) => {
      const type = (reg.argTypes || {})[name];
      const v = args[j] !== undefined ? args[j] : (reg.defaults || {})[name];
      if (v === undefined) err.push(`переход ${t.id}: ${e.fn} — нет аргумента ${name}`);
      else if (/^expr</.test(type || "")) {
        if (typeof v !== "string") err.push(`переход ${t.id}: ${e.fn} — ${name} = ${JSON.stringify(v)}, а нужно выражение CEL строкой`);
      } else if (type && type !== "setting" && !fits(type, v)) err.push(`переход ${t.id}: ${e.fn} — ${name} = ${JSON.stringify(v)}, а нужен ${type}`);
    });
    if (args.length > (reg.args || []).length) err.push(`переход ${t.id}: ${e.fn} — аргументов ${args.length}, в реестре ${(reg.args || []).length}`);
    const before = rt.errors.length;
    rt.compileEffect(e.fn, args);
    rt.errors.slice(before).forEach((x) => err.push(`переход ${t.id}, эффект ${i + 1} (${e.fn}): ${x}`));
  });
}

// Правила форм (CEL.md, «Правила интерфейса»): видно ли поле и обязательно ли — может зависеть от одного поля
// той же формы, списка с вариантами: сервер отдаёт интерфейсу таблицу по его вариантам. Варианты, значение
// по умолчанию и пояснение от значений формы не зависят — они считаются до того, как оператор что-то выбрал
for (const f of rt ? W.forms : []) {
  const lists = new Set(f.fields.filter((x) => x.kind === "select" && x.source).map((x) => x.name));
  f.fields.forEach((field) => {
    const at = `forms.${f.id}.fields.${field.name}`;
    const deps = new Set(["requiredExpr", "visibleExpr"].flatMap((k) => rt.formRefs(`${at}.${k}`)));
    if (deps.size > 1) err.push(`${at}: правила читают поля ${[...deps].join(", ")} — можно не больше одного`);
    deps.forEach((d) => {
      if (d === field.name) err.push(`${at}: правило читает само поле`);
      else if (!lists.has(d)) err.push(`${at}: правило читает form.${d} — это не список с вариантами формы ${f.id}`);
      else if (["requiredExpr", "visibleExpr"].some((k) => rt.formRefs(`forms.${f.id}.fields.${d}.${k}`).length)) err.push(`${at}: поле ${d}, от которого зависит правило, само зависит от других`);
    });
    ["optionExpr", "enabledExpr", "defaultExpr"].forEach((k) => {
      if (rt.formRefs(`${at}.${k}`).length) err.push(`${at}.${k}: читает значения формы — варианты и значение по умолчанию от них не зависят`);
    });
    if (field.enabledExpr != null && !field.disabledKey) err.push(`${at}: есть enabledExpr, нет disabledKey — какую причину давать`);
    if ((field.optionExpr != null || field.enabledExpr != null || field.defaultExpr != null) && !field.source) err.push(`${at}: правила вариантов у поля без source`);
  });
  (f.notes || []).forEach((n, i) => rt.formRefs(`forms.${f.id}.notes.${i}.expr`).length && err.push(`forms.${f.id}.notes.${i}: пояснение читает значения формы`));
}
for (const e of err) console.log(e);
const done = rt ? rt.guardNames().length : 0;
const doneEffects = rt ? rt.effectNames().length : 0;
console.log(`Ошибок в выражениях машины: ${err.length} (условий с expr: ${done} из ${W.registries.guards.length}, эффектов с do: ${doneEffects} из ${W.registries.effects.length}, правил интерфейса: ${rt ? rt.ruleNames().length : 0})`);
process.exit(err.length ? 1 : 0);
