// Тесты исполнителя выражений машины prototype/cel-runtime.js (CEL.md, PROC-44): смысл, который должен повторить
// исполнитель сервера. let в эффекте — снимок значения; элемент forEach — инцидент черновика по id; в разрешённой
// части CEL — без повтора ключа в словаре и без макросов по словарю. Пробы — на копии машины репозитория.
// Запуск: node tools/test_cel.mjs. Итог — «test_cel: N из M», код выхода — число упавших
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const W = JSON.parse(fs.readFileSync(path.join(ROOT, "Specification/Workflow_machine/workflow_schema.v1.json"), "utf8"));

const g = { console, TextEncoder, TextDecoder };
g.window = g;
vm.createContext(g);
for (const f of ["prototype/vendor/cel-js/cel.js", "prototype/cel-runtime.js"]) vm.runInContext(fs.readFileSync(path.join(ROOT, f), "utf8"), g, { filename: f });
const { IMCel } = g;

const results = [];
function test(name, fn) {
  try {
    fn();
    results.push([name, null]);
  } catch (e) {
    results.push([name, e]);
  }
}
function ok(cond, msg) {
  if (!cond) throw new Error(msg);
}

// Копия машины с пробами: эффекты — в registries.effects, условия — в registries.guards
function machine({ effects = [], guards = [] } = {}) {
  const w = structuredClone(W);
  w.registries.effects.push(...effects);
  w.registries.guards.push(...guards);
  return w;
}
const probeGuard = (fn, expr) => ({ fn, args: [], argTypes: {}, expr, failKeys: ["workflow.guard.probe"], onFail: "hide" });
const probeEffect = (fn, ops, args = [], argTypes = {}) => ({ fn, kind: "transactional", args, argTypes, do: ops });
const errorsOf = (cel, where) => cel.errors.filter((e) => e.startsWith(`${where}.`) || e.startsWith(`${where}:`));

// Инцидент x и мост к данным пробы: один инцидент, черновик — он сам
function world(cel) {
  const x = cel.value("Incident", { id: "x", timers: { reaction: { due: 100 }, resolution: {}, hold: {} } });
  const list = [x];
  const store = { incidents: () => list, instance: (id) => list.find((i) => i.id === id), touch() {}, world() {} };
  const scope = { me: "me", actor: "me", incident: x, form: {}, surface: "", now: 1000, world: {} };
  return { x, store, scope };
}

test("let — снимок: запись после let значение не меняет", () => {
  const cel = IMCel.create(
    machine({
      effects: [
        probeEffect(
          "_letSnapshot",
          [
            { let: "t", value: "incident.timers[timerId]" },
            { set: "incident.timers[timerId].due", value: "now + 5" },
            { set: "incident.escalationLevel", value: "t.due" },
          ],
          ["timerId"],
          { timerId: "string" }
        ),
      ],
    })
  );
  const { x, store, scope } = world(cel);
  cel.effect("_letSnapshot", ["reaction"], scope, store);
  ok(errorsOf(cel, "registries.effects._letSnapshot").length === 0, cel.errors.join("; "));
  ok(x.timers.get("reaction").due === 1005n, `due = ${x.timers.get("reaction").due}, а нужно 1005`);
  ok(x.escalationLevel === 100n, `escalationLevel = ${x.escalationLevel}, а нужно 100 (значение на момент let)`);
});

test("forEach — элемент читается из черновика по id", () => {
  const cel = IMCel.create(
    machine({
      effects: [
        probeEffect("_forEachLive", [
          { let: "ps", value: "incidentById(incident.id)" },
          { forEach: "p", in: "ps", do: [{ set: "p.transferCount", value: "p.transferCount + 1" }] },
          { set: "incident.escalationLevel", value: "incident.transferCount" },
        ]),
      ],
    })
  );
  const { x, store, scope } = world(cel);
  cel.effect("_forEachLive", [], scope, store);
  ok(errorsOf(cel, "registries.effects._forEachLive").length === 0, cel.errors.join("; "));
  ok(x.transferCount === 1n, `transferCount = ${x.transferCount}, а нужно 1`);
  ok(x.escalationLevel === 1n, `escalationLevel = ${x.escalationLevel}, а нужно 1: запись через элемент forEach не видна incident`);
});

test("set от имени let — ошибка сборки", () => {
  const cel = IMCel.create(
    machine({
      effects: [
        probeEffect("_letWrite", [
          { let: "y", value: "incident" },
          { set: "y.owner", value: "'a'" },
        ]),
      ],
    })
  );
  cel.compileEffect("_letWrite", []);
  const errs = errorsOf(cel, "registries.effects._letWrite");
  ok(
    errs.some((e) => e.includes("set / append — менять можно incident или элемент forEach, а не y")),
    `нет ошибки о корне пути: ${JSON.stringify(errs)}`
  );
});

test("повтор ключа в словаре — ошибка сборки", () => {
  const cel = IMCel.create(machine({ guards: [probeGuard("_dupKey", "{'a': 1, 'a': 2}['a'] == 1")] }));
  const errs = errorsOf(cel, "registries.guards._dupKey");
  ok(errs.some((e) => e.includes("ключ «a» в словаре повторяется")), `нет ошибки о повторе ключа: ${JSON.stringify(errs)}`);
});

test("макрос по словарю — ошибка сборки", () => {
  const cel = IMCel.create(machine({ guards: [probeGuard("_mapMacro", "incident.timers.exists(k, k == 'reaction')")] }));
  const errs = errorsOf(cel, "registries.guards._mapMacro");
  ok(errs.some((e) => e.includes(".exists() по словарю — макросы только по списку (CEL.md)")), `нет ошибки о макросе по словарю: ${JSON.stringify(errs)}`);
});

// Таблица SUBSET — та же, что TestSubset задачи 5 плана этапа 4а (сервер): переменные xs list<string>, n int,
// b bool, s string, m map<string, int>, f Form. Выражение — значение let пробы: тип результата любой
const SUBSET = {
  allowed: [
    "xs.exists(x, x == 'a')",
    "xs.all(x, x != '')",
    "xs.filter(x, x == 'a')",
    "xs.map(x, x)",
    "cel.bind(p, 1, p + 1) == 2",
    "{'k': 1}['k'] == 1",
    "size(xs) > 0",
    "'a' in xs",
    "b ? 1 == 1 : false",
    "-n < 0",
    "!b",
  ],
  denied: [
    "1.5 > 0",
    "n / 2 == 1",
    "n % 2 == 1",
    "s.startsWith('a')",
    "has(f.comment)",
    "xs.exists_one(x, x == 'a')",
    "nope(1)",
    "{'a': 1, 'a': 2}['a'] == 1",
    "m.exists(k, k == 'a')",
  ],
};
test("подмножество — таблица SUBSET", () => {
  const vars = { xs: "list<string>", n: "int", b: "bool", s: "string", m: "map<string, int>", f: "Form" };
  const rows = [...SUBSET.allowed.map((e) => [e, true]), ...SUBSET.denied.map((e) => [e, false])];
  const cel = IMCel.create(machine({ effects: rows.map(([e], i) => probeEffect(`_subset${i}`, [{ let: "v", value: e }], Object.keys(vars), vars)) }));
  const bad = [];
  rows.forEach(([e, allowed], i) => {
    cel.compileEffect(`_subset${i}`, []);
    const errs = errorsOf(cel, `registries.effects._subset${i}`);
    if (allowed && errs.length) bad.push(`можно, а ошибка: ${e} — ${errs.join("; ")}`);
    if (!allowed && !errs.length) bad.push(`нельзя, а ошибки нет: ${e}`);
  });
  ok(!bad.length, bad.join("\n    "));
});

test("машина репозитория собирается без ошибок", () => {
  const cel = IMCel.create(W);
  ok(cel.errors.length === 0, cel.errors.join("; "));
  // И эффекты — так, как их зовут переходы: корни путей set / append, let, forEach
  W.transitions.forEach((tr) => (tr.effects || []).forEach((e) => cel.hasEffect(e.fn) && cel.compileEffect(e.fn, e.args)));
  ok(cel.errors.length === 0, cel.errors.join("; "));
});

results.forEach(([name, e]) => console.log(e ? `FAIL ${name}\n    ${String(e.message || e)}` : `ok   ${name}`));
const failed = results.filter(([, e]) => e).length;
console.log(`test_cel: ${results.length - failed} из ${results.length}`);
process.exitCode = failed;
