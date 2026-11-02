// Тесты исполнителя выражений машины prototype/cel-runtime.js (CEL.md, PROC-44): смысл, который должен повторить
// исполнитель сервера. let в эффекте — снимок значения; элемент forEach — инцидент черновика по id; в разрешённой
// части CEL — без повтора ключа в словаре и без макросов по словарю. Пробы — на копии машины репозитория.
// Вторая часть — библиотека векторов tests/cel-vectors.js (PROC-44): канонический JSON, пул инцидентов, лента
// фактов мира, отбор и повтор вектора.
// Запуск: node tools/test_cel.mjs. Итог — «test_cel: N из M», код выхода — число упавших
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const W = JSON.parse(fs.readFileSync(path.join(ROOT, "Specification/Workflow_machine/workflow_schema.v1.json"), "utf8"));

const g = { console, TextEncoder, TextDecoder };
g.window = g;
vm.createContext(g);
for (const f of ["prototype/vendor/cel-js/cel.js", "prototype/cel-runtime.js", "prototype/engine.js", "tests/cel-vectors.js", "tests/transition-vectors.js"]) {
  // Библиотеки векторов может не быть — тогда падают только её тесты
  if (f.startsWith("tests/") && !fs.existsSync(path.join(ROOT, f))) continue;
  vm.runInContext(fs.readFileSync(path.join(ROOT, f), "utf8"), g, { filename: f });
}
const { IMCel } = g;
const vectors = () => {
  if (!g.IMCelVectors) throw new Error("IMCelVectors не объявлен: нет tests/cel-vectors.js");
  return g.IMCelVectors.lib;
};

const tvectors = () => {
  if (!g.IMTransitionVectors) throw new Error("IMTransitionVectors не объявлен: нет tests/transition-vectors.js");
  return g.IMTransitionVectors.lib;
};

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
    errs.some((e) => e.includes("set / append — y — значение let, а не инцидент черновика: менять можно только incident и элемент-инцидент forEach")),
    `нет ошибки о корне пути: ${JSON.stringify(errs)}`
  );
});

test("set через имя forEach по списку не инцидентов — ошибка сборки", () => {
  const cel = IMCel.create(
    machine({ effects: [probeEffect("_forEachBreach", [{ forEach: "b", in: "incident.breaches", do: [{ set: "b.owner", value: "'a'" }] }])] })
  );
  cel.compileEffect("_forEachBreach", []);
  const errs = errorsOf(cel, "registries.effects._forEachBreach");
  ok(
    errs.some((e) => e.includes("set / append — b — элемент forEach не из списка инцидентов: менять можно только incident и элемент-инцидент forEach")),
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

test("макрос по словарю от переменной внешнего макроса — ошибка сборки", () => {
  // Тип получателя x.timers известен только внутри all: отрывок текста без x не проверить, нужно дерево целиком
  const cel = IMCel.create(machine({ guards: [probeGuard("_nestedMapMacro", "incidents.all(x, x.timers.exists(k, k == 'reaction'))")] }));
  const errs = errorsOf(cel, "registries.guards._nestedMapMacro");
  ok(errs.some((e) => e.includes(".exists() по словарю — макросы только по списку (CEL.md)")), `нет ошибки о макросе по словарю: ${JSON.stringify(errs)}`);
});

// Таблица SUBSET — общий файл fixtures/cel-subset.json: его же читает TestSubset сервера (задача 5 плана этапа 4а),
// копия — без переписывания руками. Выражение — значение let пробы: тип результата любой
const SUBSET_FILE = path.join(ROOT, "Specification/Workflow_machine/fixtures/cel-subset.json");
test("подмножество — таблица SUBSET", () => {
  ok(fs.existsSync(SUBSET_FILE), `нет ${path.relative(ROOT, SUBSET_FILE)}`);
  const SUBSET = JSON.parse(fs.readFileSync(SUBSET_FILE, "utf8"));
  const vars = SUBSET.vars;
  ok(SUBSET.allowed.length > 0 && SUBSET.denied.length > 0 && vars && Object.keys(vars).length > 0, "таблица пустая");
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

/* ===== Библиотека векторов tests/cel-vectors.js ===== */

const throws = (fn) => {
  try {
    fn();
  } catch (e) {
    return true;
  }
  return false;
};
const sha256 = (s) => crypto.createHash("sha256").update(s, "utf8").digest("hex");

test("canonical: ключи по алфавиту; 1.5 и 2 ** 60 — ошибка", () => {
  const lib = vectors();
  const s = lib.canonical({ b: 1, a: [2, { d: "й", c: true }], e: null });
  ok(s === '{"a":[2,{"c":true,"d":"й"}],"b":1,"e":null}', `canonical: ${s}`);
  ok(throws(() => lib.canonical({ a: 1.5 })), "1.5 — не ошибка");
  ok(throws(() => lib.canonical([2 ** 60])), "2 ** 60 — не ошибка");
  ok(throws(() => lib.canonical(5n)), "BigInt — не ошибка: в данных вектора только числа JSON");
});

test("encode: инцидент — в пул, тот же второй раз — та же запись", () => {
  const lib = vectors();
  const cel = IMCel.create(W);
  const x = cel.value("Incident", { id: "x", priority: 50, timers: { reaction: { due: 100 }, resolution: {}, hold: {} } });
  const pool = {};
  const a = lib.encode(cel, "Incident", x, pool);
  const b = lib.encode(cel, "Incident", x, pool);
  const keys = Object.keys(pool);
  ok(keys.length === 1, `в пуле ${keys.length} записей`);
  ok(JSON.stringify(a) === JSON.stringify({ $ref: keys[0] }) && JSON.stringify(b) === JSON.stringify(a), `ссылки ${JSON.stringify(a)} и ${JSON.stringify(b)}`);
  // Ключ — первые 16 hex sha256 канонического JSON инцидента: так же его посчитает бэкенд
  ok(keys[0] === sha256(lib.canonical(pool[keys[0]])).slice(0, 16) && keys[0] === lib.keyOf(pool[keys[0]]), `ключ ${keys[0]}`);
  const p = pool[keys[0]];
  ok(p.priority === 50 && p.timers.reaction.due === 100 && p.owner === "" && Array.isArray(p.breaches), `запись пула: ${JSON.stringify(p)}`);
  // Список инцидентов — ссылками, словарь map<int, T> — ключами-строками
  const list = lib.encode(cel, "list<Incident>", [x, x], pool);
  ok(JSON.stringify(list) === JSON.stringify([a, a]), `список: ${JSON.stringify(list)}`);
  const m = lib.encode(cel, "map<int, int>", new Map([[25n, 1n]]), pool);
  ok(JSON.stringify(m) === '{"25":1}', `словарь: ${JSON.stringify(m)}`);
});

test("encodeArg: инцидент на ленте — {$incident: id}", () => {
  const lib = vectors();
  const cel = IMCel.create(W);
  const x = cel.value("Incident", { id: "x" });
  const a = lib.encodeArg([x, 5n, "a", true]);
  ok(JSON.stringify(a) === '[{"$incident":"x"},5,"a",true]', `аргументы: ${JSON.stringify(a)}`);
  ok(JSON.stringify(lib.encodeArg({ incident: x, recipients: ["b"], vars: new Map([["n", 2n]]) })) === '{"incident":{"$incident":"x"},"recipients":["b"],"vars":{"n":2}}', "аргументы действия");
});

test("revive: opt<string> из [] и ['a']; map<int, int> из {'25': 1}; null у Incident.owner → ''", () => {
  const lib = vectors();
  const cel = IMCel.create(W);
  ok(JSON.stringify(lib.revive(cel, "opt<string>", [], {})) === "[]", "opt<string> из []");
  ok(JSON.stringify(lib.revive(cel, "opt<string>", ["a"], {})) === '["a"]', "opt<string> из ['a']");
  const m = lib.revive(cel, "map<int, int>", { 25: 1 }, {});
  ok(m.get(25n) === 1n && m.size === 1, `map<int, int>: ${[...m]}`);
  const pool = { k: { id: "n", owner: null, priority: 7, timers: { reaction: { due: 5 } } } };
  const x = lib.revive(cel, "Incident", { $ref: "k" }, pool);
  ok(x.owner === "" && x.priority === 7n && x.timers.get("reaction").due === 5n && x.timers.get("reaction").fired === 0n, `инцидент: ${JSON.stringify(cel.plain(x))}`);
  ok(cel.value("Incident", x) === x, "не значение типа Incident");
  // Override: поля opt<T> — списком
  const o = lib.revive(cel, "Override", { eventType: ["fire"], priority: [], sec: 60 }, {});
  ok(JSON.stringify(cel.plain(o)) === JSON.stringify({ eventType: ["fire"], priority: [], sourceGroup: [], scenario: [], sec: 60 }), `Override: ${JSON.stringify(cel.plain(o))}`);
});

test("select: 40 векторов одного имени с тремя ответами — 30, ни одного ответа больше 5", () => {
  const lib = vectors();
  const v = (i, answer, name = "a") => ({ id: `guard:${name}:${i}`, kind: "guard", name, expect: { value: answer } });
  // Три ответа: каждый — не больше 5; по кругу в порядке первого появления (B раньше A), внутри — в порядке записи
  const three = Array.from({ length: 40 }, (_, i) => v(i, ["B", "A", "C"][i % 3]));
  const s3 = lib.select(three);
  const per = (s) => s.reduce((o, x) => ((o[x.expect.value] = (o[x.expect.value] || 0) + 1), o), {});
  ok(s3.length === 15 && Object.values(per(s3)).every((n) => n === 5), `три ответа: ${s3.length}, ${JSON.stringify(per(s3))}`);
  ok(s3.filter((x) => x.expect.value === "A").map((x) => x.id).join() === "guard:a:1,guard:a:4,guard:a:7,guard:a:10,guard:a:13", "внутри ответа — не первые по записи");
  // Сорок разных ответов: по имени — не больше 30, первые 30 ответов по порядку появления
  const forty = Array.from({ length: 40 }, (_, i) => v(i, `r${i}`));
  const s40 = lib.select(forty);
  ok(s40.length === lib.PER_NAME && s40.every((x, i) => x.id === `guard:a:${i}`), `сорок ответов: ${s40.length}`);
  // Имена — отдельно: у другого имени свой предел
  const two = lib.select(forty.concat(Array.from({ length: 3 }, (_, i) => v(i, "x", "b"))));
  ok(two.length === 33, `два имени: ${two.length}`);
});

test("запись и повтор: условие по ленте даёт тот же expect; вызов не с ленты — промах", () => {
  const lib = vectors();
  const rec = lib.recorder(IMCel.create, W);
  const cel = rec.create(W);
  ok(cel !== IMCel.create(W), "исходная машина не обёрнута");
  // Другая машина (workflowPatch тестов) — как есть, без записи
  const patched = structuredClone(W);
  patched.limits.maxOnHold = 7;
  ok(rec.create(patched) === IMCel.create(patched), "изменённая машина обёрнута");
  const x = cel.value("Incident", { id: "x", timers: { reaction: {}, resolution: {}, hold: {} } });
  const scope = { me: "me", actor: "me", incident: x, incidents: () => [x], form: {}, surface: "card", now: 1000, world: { can: (who, p) => who === "me" && p === "incident:claim" } };
  ok(cel.guard("hasPermission", ["incident:claim"], scope, { fn: "hasPermission", args: ["incident:claim"] }) === null, "условие не выполнено");
  const { incidents, vectors: vs } = rec.take();
  ok(vs.length === 1, `векторов ${vs.length}`);
  const [vec] = vs;
  ok(vec.kind === "guard" && vec.name === "hasPermission" && vec.id.startsWith("guard:hasPermission:") && vec.id.length === "guard:hasPermission:".length + 10, `вектор: ${vec.id}`);
  ok(JSON.stringify(vec.expect) === '{"value":null}', `expect: ${JSON.stringify(vec.expect)}`);
  ok(lib.canonical(vec.world) === '[{"args":["me","incident:claim"],"fn":"can","out":true}]', `лента: ${JSON.stringify(vec.world)}`);
  ok(!("incidents" in vec.scope), "список инцидентов в векторе, хотя условие его не спрашивало");
  ok(vec.scope.incident && incidents[vec.scope.incident.$ref] && incidents[vec.scope.incident.$ref].id === "x", "инцидента нет в пуле");
  // Повтор — на исполнителе без записи
  const plainCel = IMCel.create(W);
  const r = lib.replay(plainCel, vec, incidents);
  ok(r.ok && r.misses.length === 0, `повтор: ${JSON.stringify(r)}`);
  const bare = Object.assign({}, vec, { world: [] });
  const miss = lib.replay(plainCel, bare, incidents);
  ok(!miss.ok && JSON.stringify(miss.misses) === '["can"]', `без can: ${JSON.stringify(miss)}`);
  // Тот же вход ещё раз — та же запись
  cel.guard("hasPermission", ["incident:claim"], Object.assign({}, scope, { world: { can: () => true, agentState: () => "available", isGroup: () => false, members: () => [], dutyGroups: () => [], idleSec: () => 0, access: () => true, isOperator: () => true } }), {});
  ok(rec.take().vectors.length === 1, "тот же вход записан дважды");
  // Один вход — два ответа: исключение. Копия машины с тем же JSON — исходная машина, она записывается; настройку
  // по пути условие читает из машины при вычислении, а в векторе её нет — правка после сборки даёт другой ответ
  const same = structuredClone(W);
  const sameCel = rec.create(same);
  ok(sameCel !== IMCel.create(same), "копия исходной машины не обёрнута");
  ok(sameCel.guard("settingIs", ["limits.maxOnHold", W.limits.maxOnHold], scope, {}) === null, "settingIs не выполнено");
  same.limits.maxOnHold += 1;
  let err = null;
  try {
    sameCel.guard("settingIs", ["limits.maxOnHold", W.limits.maxOnHold], scope, {});
  } catch (e) {
    err = e;
  }
  ok(err && /один вход — два ответа/.test(err.message), `нет исключения «один вход — два ответа»: ${err && err.message}`);
});

test("определение из выражения — свой вектор; его факты мира — и на ленте условия", () => {
  const lib = vectors();
  const w = structuredClone(W);
  const rec = lib.recorder(IMCel.create, w);
  const cel = rec.create(w);
  const x = cel.value("Incident", { id: "x", assignmentGroup: "g1", timers: { reaction: {}, resolution: {}, hold: {} } });
  const scope = { me: "me", actor: "me", incident: x, form: {}, surface: "card", now: 1000, world: { isGroup: (id) => id === "g1", members: (g) => (g === "g1" ? ["me"] : []) } };
  ok(cel.guard("isTarget", [], scope, {}) === null, "isTarget не выполнено");
  const { incidents, vectors: vs } = rec.take();
  const names = vs.map((v) => `${v.kind}:${v.name}`).sort();
  ok(names.join() === "definition:addressee,definition:isSelf,definition:isTarget,guard:isTarget", `векторы: ${names}`);
  const tape = (n) => lib.canonical(vs.find((v) => `${v.kind}:${v.name}` === n).world.map((e) => e.fn));
  ok(tape("guard:isTarget") === '["isGroup","members"]' && tape("definition:isTarget") === '["isGroup","members"]' && tape("definition:addressee") === "[]", "ленты");
  const isSelf = vs.find((v) => v.name === "isSelf");
  ok(lib.canonical(isSelf.args) === '["me","g1"]' && lib.canonical(isSelf.expect) === '{"value":true}', `isSelf: ${lib.canonical(isSelf)}`);
  // Повтор без записи: наблюдатель определений вне записываемого вычисления не пишет
  const bad = vs.map((v) => [v.id, lib.replay(IMCel.create(w), v, incidents)]).filter(([, r]) => !r.ok);
  ok(!bad.length, `повтор: ${JSON.stringify(bad)}`);
  ok(rec.take().vectors.length === vs.length, "повтор записал векторы");
});

test("лента: на один вызов разные ответы — вектор не записан, счётчик tapeRepeat", () => {
  // Повтор по ленте у бэкенда — один ответ на вызов (fn и аргументы): вектор, где мир ответил на тот же вызов
  // по-разному, повторить нельзя, и запись его пропускает
  const lib = vectors();
  const w = machine({ guards: [probeGuard("_twice", "idleSec(me) > 0 && idleSec(me) > 1")] });
  const rec = lib.recorder(IMCel.create, w);
  const cel = rec.create(w);
  let n = 0;
  const scope = { me: "me", actor: "me", form: {}, surface: "card", now: 1000, world: { idleSec: () => ++n } };
  ok(cel.guard("_twice", [], scope, {}) === null, "условие пробы не выполнено");
  ok(!rec.take().vectors.some((v) => v.name === "_twice"), "вектор с разными ответами на один вызов записан");
  ok(rec.stats().tapeRepeat === 1, `tapeRepeat = ${rec.stats().tapeRepeat}`);
  // Тот же вызов дважды с одним ответом — одна запись ленты, вектор записан
  cel.guard("_twice", [], Object.assign({}, scope, { world: { idleSec: () => 5 } }), {});
  const v = rec.take().vectors.find((x) => x.name === "_twice");
  ok(v && lib.canonical(v.world) === '[{"args":["me"],"fn":"idleSec","out":5}]', `лента: ${v && lib.canonical(v.world)}`);
});

test("повтор: на ленте два ответа на один вызов — промах, а не ответы по очереди", () => {
  const lib = vectors();
  const w = machine({ guards: [probeGuard("_twice", "idleSec(me) > 0 && idleSec(me) > 1")] });
  const vec = {
    id: "guard:_twice:0",
    kind: "guard",
    name: "_twice",
    args: [],
    scope: { me: "me", actor: "me", surface: "card", now: 1000, deadline: 1000, form: {} },
    world: [
      { fn: "idleSec", args: ["me"], out: 1 },
      { fn: "idleSec", args: ["me"], out: 2 },
    ],
    expect: { value: null },
  };
  const r = lib.replay(IMCel.create(w), vec, {});
  // && в CEL при ошибке слева вычисляет и правую часть: промахов — по вызову
  ok(!r.ok && r.misses.length > 0 && r.misses.every((f) => f === "idleSec"), `повтор: ${JSON.stringify(r)}`);
});

test("запись: вход не кодируется — исключение, кадр записи не остаётся", () => {
  // Брошенное при кодировании аргументов не должно оставлять кадр в стеке записи: иначе следующие вычисления
  // вне записи (повтор, обычный вызов) пишутся как вложенные
  const lib = vectors();
  const w = structuredClone(W);
  const rec = lib.recorder(IMCel.create, w);
  const cel = rec.create(w);
  ok(throws(() => cel.call("addressee", ["не инцидент"], {})), "кодирование не того типа — без исключения");
  const x = IMCel.create(w).value("Incident", { id: "x", assignmentGroup: "g1", timers: { reaction: {}, resolution: {}, hold: {} } });
  const scope = { me: "me", actor: "me", incident: x, form: {}, surface: "card", now: 1000, world: { isGroup: (id) => id === "g1", members: () => ["me"] } };
  // Вычисление на исполнителе без записи: определения из выражения пишутся, только если стек записи не пуст
  IMCel.create(w).guard("isTarget", [], scope, {});
  ok(rec.take().vectors.length === 0, `после исключения записано вне записи: ${rec.take().vectors.map((v) => v.id)}`);
});

test("idOf: id вектора — вид, имя и 10 hex sha256 канона входа", () => {
  const lib = vectors();
  const v = { kind: "guard", name: "a", args: [1], scope: { now: 1 }, world: [], expect: { value: null } };
  const want = `guard:a:${sha256(lib.canonical({ args: [1], scope: { now: 1 }, world: [] })).slice(0, 10)}`;
  ok(lib.idOf(v) === want, `${lib.idOf(v)} ≠ ${want}`);
  const u = Object.assign({}, v, { use: { scopeRule: "x" } });
  ok(lib.idOf(u) === `guard:a:${sha256(lib.canonical({ args: [1], scope: { now: 1 }, use: { scopeRule: "x" }, world: [] })).slice(0, 10)}`, "use — во входе");
});

/* ===== Стыки ядра прототипа для векторов переходов: fromView и ctx.world ===== */

// Ядро прототипа в vm; мир — словарь (как в check_quint_replay.mjs)
function engineWith(extra = {}) {
  const events = [];
  const ctx = Object.assign({ workflow: structuredClone(W), me: "me", now: () => 1000, events: () => events, scenarioKey: (ev) => ev.scenarioGuid, can: () => false, permsOf: () => [], isGroup: () => false, stepsFilled: () => true, inGroup: () => false, log() {} }, extra);
  return { engine: g.IMEngine.create(ctx), events };
}

test("fromView: celView(fromView(x)) == x для инцидентов пула fixtures/cel-vectors.json", () => {
  const lib = tvectors();
  const pool = JSON.parse(fs.readFileSync(path.join(ROOT, "Specification/Workflow_machine/fixtures/cel-vectors.json"), "utf8")).incidents;
  const { engine } = engineWith();
  const ids = Object.keys(pool);
  ok(ids.length > 1000, `в пуле ${ids.length}`);
  ids.forEach((key) => {
    const x = pool[key];
    const ev = engine.fromView(x, {});
    const back = engine.celView(ev);
    const a = JSON.stringify(lib.normalize(back, W));
    const b = JSON.stringify(lib.normalize(x, W));
    ok(a === b, `${key}: ${a} ≠ ${b}`);
    ok(ev.scenarioGuid === x.scenario, `${key}: scenarioGuid ${ev.scenarioGuid} ≠ ${x.scenario}`);
  });
});

test("fromView: base сохраняется, поля celView перезаписываются", () => {
  const { engine } = engineWith();
  const x = JSON.parse(fs.readFileSync(path.join(ROOT, "Specification/Workflow_machine/fixtures/cel-vectors.json"), "utf8")).incidents;
  const plain = x[Object.keys(x)[0]];
  const ev = engine.fromView(plain, { log: [1], version: 7, state: "junk" });
  ok(JSON.stringify(ev.log) === "[1]" && ev.version === 7, "base потерян");
  ok(ev.state === plain.state && ev.id === plain.id, "поля celView не перезаписаны");
});

test("ctx.world: факт мира берётся из ctx.world", () => {
  const { engine, events } = engineWith({ can: () => false, world: { can: () => true, agentState: () => "available", isGroup: () => false, members: () => [], dutyGroups: () => [], idleSec: () => 0, access: () => true, isOperator: () => true } });
  const x = JSON.parse(fs.readFileSync(path.join(ROOT, "Specification/Workflow_machine/fixtures/cel-vectors.json"), "utf8")).incidents;
  const plain = Object.values(x).find((i) => i.state === "new" && !i.owner && !i.linkedTo);
  ok(plain, "нет подходящего инцидента");
  const ev = engine.fromView(plain, {});
  events.push(ev);
  ok(engine.availability("claim", ev).ok === true, "claim недоступен при ctx.world.can → true");
  const off = engineWith({ can: () => false });
  const ev2 = off.engine.fromView(plain, {});
  off.events.push(ev2);
  ok(off.engine.availability("claim", ev2).ok !== true, "без ctx.world claim доступен при can → false");
});

test("lib.normalize: null в поле — нулевое значение типа поля", () => {
  const lib = tvectors();
  const n = lib.normalize({ owner: null, closedAt: null, slaBreached: null, priority: null, holdReasonId: null, timers: {}, breaches: null, leftGroup: null }, W);
  ok(n.owner === "" && n.closedAt === 0 && n.slaBreached === false && n.priority === 0 && n.holdReasonId === "", JSON.stringify(n));
  ok(Array.isArray(n.breaches) && n.breaches.length === 0, "breaches");
  ok(JSON.stringify(n.leftGroup) === '{"at":0,"linkedAt":0,"primaryId":""}', JSON.stringify(n.leftGroup));
});

test("lib.normalize: недостающий таймер — нулевая запись, since не у hold — 0", () => {
  const lib = tvectors();
  const t = (since) => ({ due: 5, fired: 0, left: 0, paused: false, since });
  const n = lib.normalize({ timers: { hold: t(7), resolution: t(9) } }, W);
  ok(JSON.stringify(Object.keys(n.timers).sort()) === JSON.stringify(W.timers.map((x) => x.id).sort()), Object.keys(n.timers));
  ok(n.timers.hold.since === 7 && n.timers.hold.due === 5, "hold изменён");
  ok(n.timers.resolution.since === 0 && n.timers.resolution.due === 5, "since resolution не обнулён");
  ok(JSON.stringify(n.timers.reaction) === '{"due":0,"fired":0,"left":0,"paused":false,"since":0}', JSON.stringify(n.timers.reaction));
});

test("кадр: факты мира всех вычислений внутри кадра — в его ленте; повтор с тем же ответом — одна запись, с другим — tapeRepeat", () => {
  const lib = vectors();
  const w = machine({ guards: [probeGuard("_fr", "idleSec(me) > 0 && size(linkedOf(me)) >= 0"), probeGuard("_fr2", "idleSec(me) > 0 && idleSec(me) > 1")] });
  const rec = lib.recorder(IMCel.create, w);
  const cel = rec.create(w);
  ok(typeof rec.frame === "function", "rec.frame нет");
  const x = cel.value("Incident", { id: "x", timers: { reaction: {}, resolution: {}, hold: {} } });
  const mk = (world) => ({ me: "me", actor: "me", incident: x, incidents: () => [x], form: {}, surface: "card", now: 1000, world });
  const same = mk({ idleSec: () => 5, linkedOf: () => [] });
  const f = rec.frame();
  cel.guard("_fr", [], same, {});
  cel.guard("_fr", [], same, {}); // то же с тем же ответом
  let n = 0;
  cel.guard("_fr2", [], mk({ idleSec: (who) => (who === "me" ? 5 + ++n : 0) }), {}); // idleSec(me): 6 и 7 — разные ответы на один вызов
  cel.guard("_fr", [], mk({ idleSec: () => 5, linkedOf: () => [] }), {});
  const r = f.close();
  ok(lib.canonical(r.tape.map((e) => e.fn)) === '["idleSec"]', `лента: ${lib.canonical(r.tape)}`);
  ok(r.tape.length === 1 && lib.canonical(r.tape[0]) === '{"args":["me"],"fn":"idleSec","out":5}', `первая запись остаётся: ${lib.canonical(r.tape)}`);
  ok(r.tapeRepeat === 2, `tapeRepeat = ${r.tapeRepeat}`); // ответы 6 и 7 против записанного 5
  ok(!r.tape.some((e) => e.fn === "linkedOf"), "факт с ref на ленте кадра");
  // Закрытый кадр больше не пишется; повторное закрытие — тот же итог
  cel.guard("_fr", [], mk({ idleSec: () => 9, linkedOf: () => [] }), {});
  ok(lib.canonical(f.close()) === lib.canonical(r), "закрытый кадр изменился");
  // Два разных вызова — две записи, в порядке вызовов
  const f2 = rec.frame();
  cel.guard("_fr2", [], mk({ idleSec: () => 8 }), {});
  cel.guard("_fr", [], mk({ idleSec: () => 8, linkedOf: () => [] }), {});
  ok(f2.close().tape.length === 1, "один вызов idleSec(me) → 8 дважды — одна запись");
});

test("кадр не меняет запись CEL: те же векторы с открытым кадром и без", () => {
  const lib = vectors();
  const w = structuredClone(W);
  const run = (withFrame) => {
    const rec = lib.recorder(IMCel.create, w);
    const cel = rec.create(w);
    const x = cel.value("Incident", { id: "x", assignmentGroup: "g1", timers: { reaction: {}, resolution: {}, hold: {} } });
    const scope = { me: "me", actor: "me", incident: x, incidents: () => [x], form: {}, surface: "card", now: 1000, world: { isGroup: (id) => id === "g1", members: (g) => (g === "g1" ? ["me"] : []), can: () => true } };
    const f = withFrame ? rec.frame() : null;
    cel.guard("isTarget", [], scope, {});
    cel.guard("hasPermission", ["incident:claim"], scope, {});
    const tape = f ? f.close().tape : null;
    return { out: lib.canonical(rec.take()), stats: lib.canonical(rec.stats()), tape };
  };
  const a = run(false);
  const b = run(true);
  ok(a.out === b.out && a.stats === b.stats, "запись с кадром отличается");
  ok(b.tape.length > 0 && b.tape.every((e) => e.fn && "out" in e), `лента кадра: ${lib.canonical(b.tape)}`);
  ok(typeof g.IMCelVectors.frame === "function", "IMCelVectors.frame в Node не достижим");
  const none = g.IMCelVectors.frame();
  ok(lib.canonical(none.close()) === '{"tape":[],"tapeRepeat":0}', "без записи кадр не пустой");
});

/* ===== Запись векторов переходов: обёртка IMEngine.create (tests/transition-vectors.js) ===== */

let celPool = null;
const newPlain = () => {
  if (!celPool) celPool = JSON.parse(fs.readFileSync(path.join(ROOT, "Specification/Workflow_machine/fixtures/cel-vectors.json"), "utf8")).incidents;
  return Object.values(celPool).find((i) => i.state === "new" && !i.owner && !i.linkedTo);
};
// Ядро прототипа под записью переходов. frame — кадр записи CEL (по умолчанию пустой кадр Node); cel — запись CEL,
// через которую ядро получает исполнитель выражений (тогда кадр видит факты мира)
function trEngine({ frame, cel, ctx: extra = {}, machineW } = {}) {
  const lib = tvectors();
  const w = machineW || structuredClone(W);
  const rec = lib.recorder(g.IMEngine.create, w, frame || g.IMCelVectors.frame);
  const events = [];
  const ctx = Object.assign(
    {
      workflow: w,
      me: "me",
      now: () => 1000,
      events: () => events,
      scenarioKey: (ev) => ev.scenarioGuid,
      can: () => true,
      permsOf: () => [],
      isGroup: () => false,
      stepsFilled: () => true,
      inGroup: () => false,
      agentState: () => "available",
      agentStateOf: () => "available",
      idleSec: () => 0,
      log: (ev, who, k, v, at) => ev.log.push({ at, whoId: who, k, v }),
      actorName: (id) => (id ? `name:${id}` : ["workflow.label.unassigned"]),
      progress: () => ({ filled: 0, total: 2 }),
      stepNumber: () => 1,
      setCursor() {},
    },
    extra
  );
  const real = g.IMCel.create;
  if (cel) g.IMCel.create = cel.create;
  let engine;
  try {
    engine = rec.create(ctx);
  } finally {
    g.IMCel.create = real;
  }
  const mk = (id, more = {}) => engine.fromView(Object.assign({}, newPlain(), { id }, more), { log: [] });
  return { rec, engine, events, mk, w, ctx };
}
const ZERO_SKIPPED = '{"nowChanged":0,"outsideEngine":0,"tapeRepeat":0,"worldError":0}';

test("запись run: вектор с журналом и неизменённым остальным", () => {
  const C = vectors();
  const w = structuredClone(W);
  const celRec = C.recorder(IMCel.create, w);
  const { rec, engine, events, mk } = trEngine({ machineW: w, cel: celRec, frame: celRec.frame });
  const x = mk("x");
  const y = mk("y");
  events.push(x, y);
  const r = engine.run("claim", x, {}, { surface: "card" });
  ok(r.ok, `claim: ${JSON.stringify(r)}`);
  const { incidents, vectors: vs, skipped } = rec.take();
  ok(vs.length === 1, `векторов ${vs.length}`);
  const [v] = vs;
  ok(v.kind === "transition" && v.op === "run" && v.name === "claim" && v.me === "me" && v.now === 1000 && v.surface === "card", `вектор: ${C.canonical(Object.assign({}, v, { world: [], expect: {} }))}`);
  ok(C.canonical(v.target) === '{"id":"x"}' && C.canonical(v.form) === "{}" && C.canonical(v.journalAtNow) === "{}", `target ${C.canonical(v.target)}`);
  ok(v.incidents.length === 2 && incidents[v.incidents[0].$ref].id === "x" && incidents[v.incidents[1].$ref].id === "y", "список инцидентов");
  const { id, case: _c, expect, ...input } = v;
  ok(id === `transition:run:claim:${sha256(C.canonical(input)).slice(0, 10)}`, `id ${id}`);
  const o = expect.ok;
  ok(o, `expect: ${C.canonical(expect)}`);
  ok(Object.keys(o.incidents).join() === "x", `изменённые: ${Object.keys(o.incidents)}`);
  const after = incidents[o.incidents.x.$ref];
  ok(after.state === "in_progress" && after.owner === "me", `x после: ${after.state} ${after.owner}`);
  ok(Object.keys(o.journal).join() === "x" && o.journal.x.length === 1, `журнал: ${C.canonical(o.journal)}`);
  const j = o.journal.x[0];
  ok(j.templateKey === "workflow.journal.claim" && j.kind === "transition" && j.actor === "me" && j.at === 1000 && j.vars && typeof j.vars === "object", `запись: ${C.canonical(j)}`);
  ok(C.canonical(o.scenario) === '[{"action":"setCursor","incident":{"$incident":"x"}}]', `scenario: ${C.canonical(o.scenario)}`);
  ok(C.canonical(o.after) === "[]", `after: ${C.canonical(o.after)}`);
  ok(C.canonical(o.external) === '{"x":[]}', `external: ${C.canonical(o.external)}`);
  ok(o.facts.x.from.owner === "" && o.facts.x.from.addressee === "" && o.facts.x.to.owner === "me" && o.facts.x.breach === "", `facts: ${C.canonical(o.facts)}`);
  ok(!("canceled" in o) && !("journalAtNow" in o), "canceled или journalAtNow без причины");
  const has = (fn, args) => v.world.some((e) => e.fn === fn && C.canonical(e.args) === args);
  ok(has("ctx.actorName", '[""]') && !v.world.some((e) => e.fn === "ctx.actorName" && e.args[0] === null), `ctx.actorName: ${C.canonical(v.world)}`);
  ok(has("ctx.stepNumber", '[{"$incident":"x"}]') && has("ctx.progress", '[{"$incident":"x"}]'), `ctx.*: ${C.canonical(v.world)}`);
  // Факты cel.world — кадром записи CEL
  ok(v.world.some((e) => e.fn === "can" && C.canonical(e) === '{"args":["me","incident:claim"],"fn":"can","out":true}') && has("agentState", '["me"]'), `факты мира: ${C.canonical(v.world)}`);
  ok(C.canonical(skipped) === ZERO_SKIPPED, `skipped: ${C.canonical(skipped)}`);
  ok(Object.keys(incidents).length === 3, `пул: ${Object.keys(incidents).length}`); // x до, y, x после
});

test("запись runAll с пустым списком — вектор ok без изменений", () => {
  const C = vectors();
  const { rec, engine, events, mk } = trEngine();
  events.push(mk("x"));
  const r = engine.runAll("detach", [], {}, { surface: "card" });
  ok(r.ok, `runAll: ${JSON.stringify(r)}`);
  const vs = rec.take().vectors;
  ok(vs.length === 1 && vs[0].op === "runAll" && vs[0].name === "detach", `векторы: ${vs.map((v) => v.id)}`);
  ok(C.canonical(vs[0].target) === '{"ids":[]}', `target ${C.canonical(vs[0].target)}`);
  const o = vs[0].expect.ok;
  ok(o && !("incidents" in o) && !("journal" in o) && !("journalAtNow" in o) && !("canceled" in o), `expect: ${C.canonical(vs[0].expect)}`);
  ok(C.canonical(o) === '{"after":[],"external":{},"facts":{},"scenario":[]}', `expect.ok: ${C.canonical(o)}`);
});

test("отказ: expect.refusal, инциденты не изменились", () => {
  const C = vectors();
  const { rec, engine, events, mk } = trEngine({ ctx: { can: () => false } });
  const x = mk("x");
  const y = mk("y");
  events.push(x, y);
  ok(!engine.run("claim", x, {}, { surface: "card" }).ok, "claim без права прошёл");
  ok(!engine.runAll("claim", [x, y], {}, { surface: "card" }).ok, "runAll без права прошёл");
  const vs = rec.take().vectors;
  ok(vs.length === 2, `векторов ${vs.length}`);
  ok(C.canonical(vs[0].expect) === '{"refusal":{"why":["workflow.guard.no_permission",{"p":"incident:claim"}]}}', `run: ${C.canonical(vs[0].expect)}`);
  // runAll называет, кто не прошёл, и какое условие
  ok(C.canonical(vs[1].expect) === '{"refusal":{"guard":"hasPermission","id":"x","why":["workflow.guard.no_permission",{"p":"incident:claim"}]}}', `runAll: ${C.canonical(vs[1].expect)}`);
  ok(x.state === "new" && !x.owner && x.log.length === 0, "x изменился");
});

test("отбор при записи: 25 одинаковых claim — 4 вектора, пул — только их инциденты", () => {
  const { rec, engine, events, mk, w } = trEngine();
  for (let i = 0; i < 25; i++) {
    events.length = 0;
    const x = mk(`x${i}`);
    events.push(x);
    ok(engine.run("claim", x, {}, {}).ok, `claim x${i}`);
  }
  const { incidents, vectors: vs } = rec.take();
  ok(vs.length === 4, `векторов ${vs.length}`);
  ok(vs.map((v) => v.target.id).join() === "x0,x1,x2,x3", `оставлены: ${vs.map((v) => v.target.id)}`);
  const refs = new Set(vs.flatMap((v) => v.incidents.map((d) => d.$ref).concat(Object.values(v.expect.ok.incidents).map((d) => d.$ref))));
  ok(Object.keys(incidents).length === refs.size && Object.keys(incidents).every((k) => refs.has(k)), `пул: ${Object.keys(incidents).length}, ссылок ${refs.size}`);
  ok(Object.values(incidents).every((p) => ["x0", "x1", "x2", "x3"].includes(p.id)), `в пуле чужие: ${Object.values(incidents).map((p) => p.id)}`);
  // Тот же вход и тот же ответ — без исключения; тот же вход, другой ответ — исключение и у отброшенного вектора
  events.length = 0;
  events.push(mk("x10"));
  engine.run("claim", events[0], {}, {});
  const claim = w.transitions.find((t) => t.id === "claim");
  claim.effects = claim.effects.filter((e) => e.fn !== "setCursor");
  events.length = 0;
  events.push(mk("x10"));
  let err = null;
  try {
    engine.run("claim", events[0], {}, {});
  } catch (e) {
    err = e;
  }
  ok(err && /один вход — два ответа/.test(err.message), `нет исключения «один вход — два ответа»: ${err && err.message}`);
});

test("now меняется во время вызова — вектора нет, skipped.nowChanged 1", () => {
  let t = 1000;
  const { rec, engine, events, mk } = trEngine({ ctx: { now: () => t++ } });
  const x = mk("x");
  events.push(x);
  ok(engine.run("claim", x, {}, {}).ok, "claim");
  const { vectors: vs, skipped } = rec.take();
  ok(vs.length === 0 && skipped.nowChanged === 1, `векторов ${vs.length}, skipped ${JSON.stringify(skipped)}`);
});

test("запись create: новый инцидент — target, список — без него, журнал от dispatcher — system", () => {
  const C = vectors();
  const { rec, engine, events, mk } = trEngine();
  events.push(mk("x"));
  const n = mk("n", { state: "", owner: "" });
  ok(engine.create(n).ok, "create");
  const { incidents, vectors: vs } = rec.take();
  ok(vs.length === 1 && vs[0].op === "create" && vs[0].name === "create", `векторы: ${vs.map((v) => v.id)}`);
  const [v] = vs;
  ok(incidents[v.target.incident.$ref].id === "n" && incidents[v.target.incident.$ref].state === "", "target — не новый до перехода");
  ok(v.incidents.length === 1 && incidents[v.incidents[0].$ref].id === "x", "в списке новый");
  ok(v.surface === "" && C.canonical(v.form) === "{}", "surface или form");
  const o = v.expect.ok;
  ok(Object.keys(o.incidents).join() === "n" && incidents[o.incidents.n.$ref].state === "new", `изменённые: ${C.canonical(o.incidents)}`);
  ok(o.journal.n.length > 0 && o.journal.n.every((e) => e.actor === "dispatcher" && e.kind === "system"), `журнал: ${C.canonical(o.journal)}`);
  ok(o.facts.n && o.facts.n.to.state === "new" && Array.isArray(o.external.n), `facts / external: ${C.canonical(o.facts)} ${C.canonical(o.external)}`);
});

test("запись: машина не исходная — как есть; ошибка мира, исключение ядра, повтор на ленте — вектора нет, кадр закрыт", () => {
  const patched = structuredClone(W);
  patched.limits.maxOnHold = 7;
  const lib = tvectors();
  const rec0 = lib.recorder(g.IMEngine.create, W, g.IMCelVectors.frame);
  const base = trEngine({ machineW: patched });
  const plainEngine = rec0.create(base.ctx);
  const p = base.mk("p");
  base.events.push(p);
  ok(plainEngine.run("claim", p, {}, {}).ok && rec0.take().vectors.length === 0, "машина не исходная — записана");
  // Кадры считаются: открыт — закрыт
  let opened = 0;
  let closed = 0;
  let repeat = 0;
  const frame = () => {
    opened++;
    return { close: () => (closed++, { tape: [], tapeRepeat: repeat }) };
  };
  let broken = false;
  const { rec, engine, events, mk } = trEngine({
    frame,
    ctx: {
      agentState: () => {
        if (broken) throw new Error("мир сломан");
        return "available";
      },
    },
  });
  const x = mk("x");
  events.push(x);
  broken = true;
  let err = null;
  try {
    engine.run("claim", x, {}, {});
  } catch (e) {
    err = e;
  }
  const s1 = rec.take();
  // Исключение пробрасывается (cel-js заворачивает его в своё — текст не сравнивается)
  ok(err && s1.vectors.length === 0 && s1.skipped.worldError === 1, `ошибка мира: ${err && err.message}, ${JSON.stringify(s1.skipped)}, векторов ${s1.vectors.length}`);
  ok(opened === 1 && closed === 1, `кадры: открыто ${opened}, закрыто ${closed}`);
  broken = false;
  // Ошибка перехода (transition_failed) — expect.error
  const bad = mk("b");
  delete bad.log;
  events.length = 0;
  events.push(bad);
  const r = engine.run("claim", bad, {}, {});
  ok(!r.ok && r.why[0] === "workflow.error.transition_failed", `без журнала: ${JSON.stringify(r)}`);
  const s2 = rec.take();
  ok(s2.vectors.length === 1 && typeof s2.vectors[0].expect.error === "string" && s2.vectors[0].expect.error.length > 0, `error: ${JSON.stringify(s2.vectors.map((v) => v.expect))}`);
  // Мир ответил на один вызов по-разному — skipped.tapeRepeat
  repeat = 1;
  events.length = 0;
  events.push(mk("z"));
  engine.run("claim", events[0], {}, {});
  ok(rec.take().skipped.tapeRepeat === 1, "tapeRepeat не посчитан");
  ok(opened === closed && opened === 3, `кадры: открыто ${opened}, закрыто ${closed}`);
  // Прочие методы ядра — насквозь, без записи и без кадра (tick пишется — тесты «запись tick» ниже)
  ok(engine.availability("claim", events[0]).hidden === true, "availability");
  ok(engine.workflow && engine.session && typeof engine.merge === "function" && typeof engine.resumeTimer === "function", "методы ядра");
  ok(rec.take().vectors.length === 1 && opened === 3, "прочие методы записали вектор или открыли кадр");
});

test("запись переходов не меняет запись CEL: те же векторы CEL с обёрткой ядра и без", () => {
  const C = vectors();
  const run = (wrapped) => {
    const w = structuredClone(W);
    const celRec = C.recorder(IMCel.create, w);
    const real = g.IMCel.create;
    g.IMCel.create = celRec.create;
    let t;
    try {
      t = wrapped ? trEngine({ machineW: w, cel: celRec, frame: celRec.frame }) : null;
      if (!wrapped) {
        const events = [];
        const base = trEngine({ machineW: w });
        const engine = g.IMEngine.create(Object.assign({}, base.ctx, { events: () => events }));
        t = { engine, events, mk: (id) => engine.fromView(Object.assign({}, newPlain(), { id }), { log: [] }) };
      }
    } finally {
      g.IMCel.create = real;
    }
    const x = t.mk("x");
    t.events.push(x, t.mk("y"));
    t.engine.run("claim", x, {}, { surface: "card" });
    t.engine.runAll("detach", [], {}, {});
    return { out: C.canonical(celRec.take()), stats: C.canonical(celRec.stats()), n: celRec.take().vectors.length };
  };
  const a = run(false);
  const b = run(true);
  ok(a.n > 0, "запись CEL пустая — сравнивать нечего");
  ok(a.stats === b.stats, `stats: ${a.stats} ≠ ${b.stats}`);
  ok(a.out === b.out, "векторы CEL с обёрткой ядра другие");
});

test("открытый вектор закрывают только меняющие вызовы ядра и take(); чтение — насквозь", () => {
  const { rec, engine, events, mk } = trEngine();
  const x = mk("x");
  events.push(x);
  let closed = 0;
  const hold = () => rec.hold({ close: () => closed++ });
  hold();
  engine.isDone(x);
  engine.availability("claim", x);
  engine.badge(x);
  engine.actions(x, "card");
  engine.celView(x);
  engine.queueFilters(x);
  ok(closed === 0, `чтение закрыло вектор: ${closed}`);
  engine.tick();
  ok(closed === 1, `tick не закрыл: ${closed}`);
  hold();
  engine.run("claim", null, {}, {}); // run без инцидента — тоже меняющий вызов
  ok(closed === 2, `run без инцидента не закрыл: ${closed}`);
  hold();
  engine.startTimer(x, "reaction", "start");
  ok(closed === 3, `startTimer не закрыл: ${closed}`);
  hold();
  rec.take();
  ok(closed === 4, `take не закрыл: ${closed}`);
  rec.take();
  ok(closed === 4, "закрыт дважды");
});

test("кадр не открылся — вызова нет, следующий вызов записывается (не как вложенный)", () => {
  let n = 0;
  const frame = () => {
    if (n++ === 0) throw new Error("кадр сломан");
    return { close: () => ({ tape: [], tapeRepeat: 0 }) };
  };
  const { rec, engine, events, mk } = trEngine({ frame });
  const x = mk("x");
  events.push(x);
  ok(throws(() => engine.run("claim", x, {}, {})), "исключение кадра не проброшено");
  ok(x.state === "new", "ядро вызвано без кадра");
  ok(engine.run("claim", x, {}, {}).ok, "claim");
  const { vectors: vs, skipped } = rec.take();
  ok(vs.length === 1 && JSON.stringify(skipped) === ZERO_SKIPPED, `векторов ${vs.length}, skipped ${JSON.stringify(skipped)}`);
});

test("journalAtNow и once: запись в момент now до вызова — во входе, с новыми подстановками — в ожидаемом", () => {
  const C = vectors();
  const w = machine({ effects: [probeEffect("_once", [{ world: "log", args: { incident: "incident", key: "'k.once'", vars: "{'n': 2}", once: "true" } }])] });
  w.transitions.find((t) => t.id === "claim").effects.push({ fn: "_once", args: [] });
  const { rec, engine, events, mk } = trEngine({ machineW: w });
  const x = mk("x");
  x.log.push({ at: 900, whoId: "me", k: "k.once", v: { n: 0 } }, { at: 1000, whoId: "dispatcher", k: "k.once", v: { n: 1 } });
  events.push(x);
  ok(engine.run("claim", x, {}, {}).ok, "claim");
  const [v] = rec.take().vectors;
  ok(C.canonical(v.journalAtNow) === '{"x":[{"actor":"dispatcher","at":1000,"kind":"system","templateKey":"k.once","vars":{"n":1}}]}', `вход: ${C.canonical(v.journalAtNow)}`);
  const o = v.expect.ok;
  ok(C.canonical(o.journalAtNow) === '{"x":[{"actor":"dispatcher","at":1000,"kind":"system","templateKey":"k.once","vars":{"n":2}}]}', `после: ${C.canonical(o.journalAtNow)}`);
  // Заменённая запись — не в хвосте журнала
  ok(o.journal.x.map((e) => e.templateKey).join() === "workflow.journal.claim", `хвост: ${C.canonical(o.journal)}`);
});

test("canceled: ручной переход в окне после дедлайна отменяет переход по таймеру", () => {
  const C = vectors();
  const w = structuredClone(W);
  w.escalation.enabled = false;
  const { rec, engine, events, mk } = trEngine({ machineW: w });
  const x = mk("x");
  Object.assign(x, { reactionDueAt: 900, reactionLeftMs: null, firedTimers: {} });
  events.push(x);
  const r = engine.run("claim", x, {}, {});
  ok(r.ok && r.canceled === "reaction_overdue", `claim: ${JSON.stringify(r)}`);
  const o = rec.take().vectors[0].expect.ok;
  ok(C.canonical(o.canceled) === '{"x":"reaction_overdue"}', `canceled: ${C.canonical(o.canceled)}`);
  ok(o.journal.x[0].templateKey === "workflow.journal.timer_overridden" && o.journal.x[0].actor === "dispatcher" && o.journal.x[0].kind === "system", `журнал: ${C.canonical(o.journal)}`);
});

test("лента: transferTargets (варианты поля) и ctx.shareAnswers; after: null — \"\"", () => {
  const C = vectors();
  const w = machine({
    effects: [
      probeEffect("_after", [
        { world: "notify", args: { incident: "incident", to: "'lead'", recipients: "['a']", alert: "false" } },
        { world: "evict", args: { incident: "incident" } },
        { world: "shareAnswers", args: { from: "incident", to: "form.primaryId" } },
      ]),
    ],
  });
  const form = w.forms.find((f) => f.fields.some((x) => x.source === "transferTargets"));
  const field = form.fields.find((x) => x.source === "transferTargets");
  w.transitions.push({ id: "_probe", trigger: "manual", from: ["new"], to: null, guards: [], effects: [{ fn: "_after", args: [] }], labelKey: "x", ui: { surface: [], navigate: null } });
  w.transitions.push({ id: "_probeForm", trigger: "manual", from: ["new"], to: null, guards: [], effects: [], form: form.id, labelKey: "x", ui: { surface: [], navigate: null } });
  let delivered = 0;
  const { rec, engine, events, mk } = trEngine({
    machineW: w,
    ctx: { me: null, shareAnswers: () => 1, deliver: () => delivered++, onEvict() {}, transferTargets: () => [{ id: "a", label: "A" }, { id: "g1", label: "G" }] },
  });
  const x = mk("x");
  const y = mk("y");
  events.push(x, y);
  ok(engine.run("_probe", x, { primaryId: "y" }, {}).ok, "_probe");
  engine.run("_probeForm", x, { [field.name]: "a" }, {});
  const vs = rec.take().vectors;
  ok(vs.length === 2, `векторов ${vs.length}`);
  const [p, f] = vs;
  ok(p.me === "", `me: ${p.me}`);
  const o = p.expect.ok;
  ok(delivered === 1, "deliver сервера не вызван");
  ok(
    C.canonical(o.after) ===
      '[{"about":"","action":"notify","actor":"","alert":false,"incident":{"$incident":"x"},"recipients":["a"],"transitionId":"_probe"},{"action":"evict","by":"","incident":{"$incident":"x"},"transitionId":"_probe","who":""}]',
    `after: ${C.canonical(o.after)}`
  );
  ok(C.canonical(o.scenario) === '[{"action":"shareAnswers","from":{"$incident":"x"},"to":{"$incident":"y"}}]', `scenario: ${C.canonical(o.scenario)}`);
  ok(p.world.some((e) => C.canonical(e) === '{"args":[{"$incident":"x"},{"$incident":"y"},1000],"fn":"ctx.shareAnswers","out":1}'), `лента: ${C.canonical(p.world)}`);
  ok(C.canonical(o.external) === '{"x":[{"fn":"notify","target":"lead"}]}', `external: ${C.canonical(o.external)}`);
  ok(f.world.some((e) => C.canonical(e) === '{"args":[],"fn":"transferTargets","out":["a","g1"]}'), `лента формы: ${C.canonical(f.world)}`);
});

test("outsideEngine: отказ, который что-то изменил; ядро внутри ядра", () => {
  let x;
  const { rec, engine, events, mk } = trEngine({
    ctx: {
      can: () => {
        x.priority = 99;
        return false;
      },
    },
  });
  x = mk("x");
  events.push(x);
  ok(!engine.run("claim", x, {}, {}).ok, "claim без права прошёл");
  const s1 = rec.take();
  ok(s1.vectors.length === 0 && s1.skipped.outsideEngine === 1, `отказ с изменением: ${JSON.stringify(s1.skipped)}, векторов ${s1.vectors.length}`);
  // Ядро внутри ядра: setCursor сервера зовёт runAll — внешнего вектора нет, внутренний идёт насквозь
  let inner = null;
  const t = trEngine({ ctx: { setCursor: () => (inner = t.engine.runAll("detach", [], {}, {})) } });
  const z = t.mk("z");
  t.events.push(z);
  ok(t.engine.run("claim", z, {}, {}).ok && inner && inner.ok, "claim или вложенный runAll");
  const s2 = t.rec.take();
  ok(s2.vectors.length === 0 && s2.skipped.outsideEngine === 1, `вложенный: ${JSON.stringify(s2.skipped)}, векторов ${s2.vectors.length}`);
  // Следующий вызов — снова записывается
  const z2 = t.mk("z2");
  t.events.length = 0;
  t.events.push(z2);
  inner = null;
  t.engine.runAll("detach", [], {}, {});
  ok(t.rec.take().vectors.length === 1, "после вложенного запись не идёт");
});

/* --- объединение: лента закрыта на возврате, запись merged_in* server.js — в ожидаемом (решение 39) --- */

// Запись основному, как log в server.js mergeIncidents после engine.merge
const mergedIn = (ev, k = "workflow.journal.merged_in", v = { ids: "INC-0002, INC-0003" }, whoId = "me") => ev.log.push({ at: 1000, whoId, k, v });

test("запись merge: merged_in после ядра — в expect с server: true", () => {
  const C = vectors();
  const { rec, engine, events, mk } = trEngine();
  const p = mk("p");
  const a = mk("a");
  const b = mk("b");
  events.push(p, a, b);
  const r = engine.merge(p, [a, b]);
  ok(r.ok && r.taken, `merge: ${JSON.stringify(r)}`);
  // server.js: isDone (чтение) — до записи merged_in, вектор не закрывает
  engine.isDone(p);
  mergedIn(p);
  // «Сервер» вызывает ядро ещё раз — вектор объединения закрыт
  ok(engine.runAll("detach", [], {}, {}).ok, "runAll");
  const { incidents, vectors: vs, skipped } = rec.take();
  ok(vs.length === 2 && vs[0].op === "merge" && vs[1].op === "runAll", `векторы: ${vs.map((v) => v.id)}`);
  const [v] = vs;
  ok(v.name === "merge" && v.me === "me" && v.now === 1000 && v.surface === "" && C.canonical(v.form) === "{}", `вектор: ${v.id} ${v.surface} ${C.canonical(v.form)}`);
  ok(C.canonical(v.target) === '{"ids":["a","b"],"primaryId":"p"}', `target ${C.canonical(v.target)}`);
  ok(v.incidents.map((d) => incidents[d.$ref].id).join() === "p,a,b", "список инцидентов");
  const o = v.expect.ok;
  ok(o, `expect: ${C.canonical(v.expect)}`);
  ok(Object.keys(o.incidents).sort().join() === "a,b,p", `изменённые: ${Object.keys(o.incidents)}`);
  ok(incidents[o.incidents.a.$ref].linkedTo === "p" && incidents[o.incidents.p.$ref].state === "in_progress", "a не привязан или p не взят");
  const last = o.journal.p[o.journal.p.length - 1];
  ok(C.canonical(last) === '{"actor":"me","at":1000,"kind":"transition","server":true,"templateKey":"workflow.journal.merged_in","vars":{"ids":"INC-0002, INC-0003"}}', `последняя запись основного: ${C.canonical(last)}`);
  // Записи ядра — без пометки
  ok(o.journal.p.slice(0, -1).some((e) => e.templateKey === "workflow.journal.claim") && Object.values(o.journal).flat().filter((e) => e.server).length === 1, `журнал: ${C.canonical(o.journal)}`);
  ok(o.journal.a && o.journal.b, `журнал присоединяемых: ${C.canonical(o.journal)}`);
  // external — только присоединяемые; facts — присоединяемые и основной, которого взяли
  ok(Object.keys(o.external).join() === "a,b", `external: ${C.canonical(o.external)}`);
  ok(Object.keys(o.facts).sort().join() === "a,b,p" && o.facts.p.to.owner === "me" && o.facts.a.to.state === "linked", `facts: ${C.canonical(o.facts)}`);
  ok(C.canonical(skipped) === ZERO_SKIPPED, `skipped: ${C.canonical(skipped)}`);
});

test("закрытие merge вызовом ядра коллеги и tick", () => {
  const C = vectors();
  const { rec, engine, events, mk, ctx } = trEngine();
  const colleague = rec.create(Object.assign({}, ctx, { me: "colleague" }));
  const p = mk("p");
  const a = mk("a");
  const c = mk("c");
  events.push(p, a, c);
  ok(engine.merge(p, [a]).ok, "merge 1");
  mergedIn(p, "workflow.journal.merged_in_more", { ids: "INC-0002", more: 3 });
  // Ядро коллеги (другой me) закрывает вектор: изменение основного после — уже не наше
  ok(colleague.run("claim", c, {}, {}).ok, "claim коллеги");
  p.priority = 99;
  const q = mk("q");
  const d = mk("d");
  events.push(q, d);
  ok(engine.merge(q, [d]).ok, "merge 2");
  mergedIn(q);
  engine.tick(); // runScheduler сервера
  q.log.push({ at: 1000, whoId: "me", k: "workflow.journal.comment", v: null });
  const { vectors: vs, skipped } = rec.take();
  // tick сначала закрыл открытый merge, потом записал свой вектор
  ok(vs.map((v) => `${v.op}:${v.me}`).join() === "merge:me,run:colleague,merge:me,tick:me", `векторы: ${vs.map((v) => `${v.op}:${v.me}`)}`);
  ok(C.canonical(skipped) === ZERO_SKIPPED, `skipped: ${C.canonical(skipped)}`);
  const tail = (v, id) => v.expect.ok.journal[id][v.expect.ok.journal[id].length - 1];
  ok(tail(vs[0], "p").templateKey === "workflow.journal.merged_in_more" && tail(vs[0], "p").server === true && C.canonical(tail(vs[0], "p").vars) === '{"ids":"INC-0002","more":3}', `merged_in_more: ${C.canonical(tail(vs[0], "p"))}`);
  ok(tail(vs[2], "q").templateKey === "workflow.journal.merged_in" && tail(vs[2], "q").server === true, `merged_in: ${C.canonical(tail(vs[2], "q"))}`);
  // Изменения после закрытия в вектор не вошли
  ok(!Object.values(vs[2].expect.ok.journal).flat().some((e) => e.templateKey === "workflow.journal.comment"), "запись после tick — в векторе");
});

test("лента merge закрыта на возврате: факт мира после merge в ленту не идёт", () => {
  const C = vectors();
  const w = structuredClone(W);
  const celRec = C.recorder(IMCel.create, w);
  let late = false;
  // После возврата мир отвечает иначе: попади эти ответы в ленту — tapeRepeat или лишние факты
  const { rec, engine, events, mk } = trEngine({ machineW: w, cel: celRec, frame: celRec.frame, ctx: { can: () => !late, actorName: (id) => (late ? "late" : `name:${id}`) } });
  const p = mk("p");
  const a = mk("a");
  events.push(p, a);
  ok(engine.merge(p, [a]).ok, "merge");
  late = true;
  // Как emitTransition и card(primary) в server.js
  engine.addressee(p);
  engine.actions(p, "card");
  engine.availability("hold", p);
  engine.badge(p);
  mergedIn(p);
  const { vectors: vs, skipped } = rec.take();
  ok(vs.length === 1 && C.canonical(skipped) === ZERO_SKIPPED, `векторов ${vs.length}, skipped ${C.canonical(skipped)}`);
  const [v] = vs;
  ok(v.world.some((e) => e.fn === "can" && C.canonical(e.args) === '["me","incident:bulk"]' && e.out === true), `факты merge: ${C.canonical(v.world)}`);
  ok(v.world.every((e) => e.out !== false && e.out !== "late"), `факт после возврата в ленте: ${C.canonical(v.world)}`);
  const hold = w.transitions.find((t) => t.id === "hold");
  const holdPerms = (hold.guards || []).filter((x) => x.fn === "hasPermission").map((x) => x.args[0]);
  ok(!v.world.some((e) => e.fn === "can" && holdPerms.includes(e.args[1])), `право hold в ленте: ${C.canonical(v.world)}`);
});

test("запись: запись журнала вне ядра с другим ключом или изменение другого инцидента списка — вектора нет, skipped.outsideEngine 1", () => {
  const C = vectors();
  const cases = {
    "другой ключ": ({ p }) => mergedIn(p, "workflow.journal.comment"),
    "две записи merged_in": ({ p }) => (mergedIn(p), mergedIn(p)),
    "merged_in не от me": ({ p }) => mergedIn(p, undefined, undefined, "colleague"),
    "запись присоединяемому": ({ p, a }) => (mergedIn(p), mergedIn(a)),
    "изменён присоединяемый": ({ p, a }) => (mergedIn(p), (a.priority = 99)),
    "изменён другой инцидент списка": ({ p, y }) => (mergedIn(p), (y.priority = 99)),
    "запись другому инциденту списка": ({ y }) => y.log.push({ at: 1000, whoId: "me", k: "workflow.journal.comment", v: null }),
    "изменён основной": ({ p }) => (mergedIn(p), (p.priority = 99)),
    "прежняя запись основного заменена": ({ p }) => (p.log[0] = Object.assign({}, p.log[0], { v: { x: 1 } })),
  };
  Object.entries(cases).forEach(([name, change]) => {
    const { rec, engine, events, mk } = trEngine();
    const t = { p: mk("p"), a: mk("a"), y: mk("y") };
    events.push(t.p, t.a, t.y);
    ok(engine.merge(t.p, [t.a]).ok, `${name}: merge`);
    change(t);
    const { vectors: vs, skipped } = rec.take();
    ok(vs.length === 0 && skipped.outsideEngine === 1, `${name}: векторов ${vs.length}, skipped ${C.canonical(skipped)}`);
  });
  // Отказ объединения закрыт на возврате: изменения после — уже не его
  const { rec, engine, events, mk } = trEngine({ ctx: { can: () => false } });
  const p = mk("p");
  const a = mk("a");
  events.push(p, a);
  ok(!engine.merge(p, [a]).ok, "merge без права прошёл");
  mergedIn(p, "workflow.journal.comment");
  const { vectors: vs, skipped } = rec.take();
  ok(vs.length === 1 && vs[0].expect.refusal && vs[0].expect.refusal.id === "a" && C.canonical(skipped) === ZERO_SKIPPED, `отказ: ${vs.map((v) => C.canonical(v.expect))}, skipped ${C.canonical(skipped)}`);
});

test("merge без присоединяемых — только «Взять», без merged_in", () => {
  const C = vectors();
  const { rec, engine, events, mk } = trEngine();
  const p = mk("p");
  const y = mk("y");
  events.push(p, y);
  const r = engine.merge(p, []);
  ok(r.ok && r.taken, `merge: ${JSON.stringify(r)}`);
  const { vectors: vs, skipped } = rec.take();
  ok(vs.length === 1 && C.canonical(skipped) === ZERO_SKIPPED, `векторов ${vs.length}, skipped ${C.canonical(skipped)}`);
  const [v] = vs;
  ok(v.op === "merge" && v.name === "merge" && C.canonical(v.target) === '{"ids":[],"primaryId":"p"}', `target ${C.canonical(v.target)}`);
  const o = v.expect.ok;
  ok(Object.keys(o.incidents).join() === "p" && Object.keys(o.journal).join() === "p", `изменённые: ${C.canonical(o.incidents)}, журнал ${C.canonical(o.journal)}`);
  ok(o.journal.p.map((e) => e.templateKey).join() === "workflow.journal.claim" && !o.journal.p.some((e) => e.server), `журнал основного: ${C.canonical(o.journal.p)}`);
  ok(C.canonical(o.external) === "{}" && Object.keys(o.facts).join() === "p" && o.facts.p.to.state === "in_progress", `external / facts: ${C.canonical(o.external)} ${C.canonical(o.facts)}`);
});

/* --- повтор по ленте на ядре прототипа (lib.replay, lib.engines): мир — лента вектора, сравнение — решение 41 --- */

test("повтор: run по ленте даёт тот же expect; лента без can — промах", () => {
  const C = vectors();
  const lib = tvectors();
  const w = structuredClone(W);
  const celRec = C.recorder(IMCel.create, w);
  let allowed = true;
  const { rec, engine, events, mk } = trEngine({ machineW: w, cel: celRec, frame: celRec.frame, ctx: { can: () => allowed } });
  const x = mk("x");
  const y = mk("y");
  events.push(x, y);
  ok(engine.run("claim", x, {}, { surface: "card" }).ok, "claim");
  allowed = false;
  ok(!engine.run("claim", y, {}, { surface: "card" }).ok, "claim без права прошёл");
  const { incidents, vectors: vs } = rec.take();
  ok(vs.length === 2 && vs[0].expect.ok && vs[1].expect.refusal, `векторы: ${vs.map((v) => C.canonical(v.expect).slice(0, 40))}`);
  // Ядро повтора — одно на me: мир отвечает по ленте того вектора, который повторяется сейчас
  const engineFor = lib.engines(g.IMEngine.create, w);
  ok(engineFor("me") === engineFor("me"), "ядро повтора создано дважды");
  vs.forEach((v) => {
    const r = lib.replay(engineFor, v, incidents);
    ok(r.ok && r.misses.length === 0, `${v.id}: ${JSON.stringify({ misses: r.misses, diffs: r.diffs, got: r.got }).slice(0, 600)}`);
  });
  const [v] = vs;
  const without = (fn) => Object.assign({}, v, { world: v.world.filter((e) => e.fn !== fn) });
  const miss = lib.replay(engineFor, without("can"), incidents);
  ok(!miss.ok && JSON.stringify(miss.misses) === '["can"]', `без can: ${JSON.stringify({ misses: miss.misses, got: miss.got })}`);
  // Функция сервера мимо cel.world — тоже по ленте: нет записи — промах, а не undefined
  const noName = lib.replay(engineFor, without("ctx.actorName"), incidents);
  ok(!noName.ok && noName.misses.includes("ctx.actorName"), `без ctx.actorName: ${JSON.stringify({ misses: noName.misses, got: noName.got })}`);
  // Другой ответ ленты — другой итог, без промахов
  const denied = lib.replay(engineFor, Object.assign({}, v, { world: v.world.map((e) => (e.fn === "can" ? Object.assign({}, e, { out: false }) : e)) }), incidents);
  ok(!denied.ok && denied.misses.length === 0 && denied.got.refusal, `can — false: ${JSON.stringify(denied.got)}`);
  // То же ядро после промахов снова повторяет вектор
  ok(lib.replay(engineFor, v, incidents).ok, "после промаха повтор не проходит");
  ok(x.state === "in_progress" && incidents[v.incidents[0].$ref].state === "new", "повтор изменил инциденты записи или пул");
});

test("повтор: transfer — варианты поля targetId из ленты transferTargets", () => {
  const C = vectors();
  const lib = tvectors();
  const w = structuredClone(W);
  const celRec = C.recorder(IMCel.create, w);
  const { rec, engine, events, mk } = trEngine({
    machineW: w,
    cel: celRec,
    frame: celRec.frame,
    ctx: {
      permsOf: () => ({ includes: () => true }),
      hasAccess: () => true,
      // b — первым и тоже может принять: условие hasTransferTarget находит его, факты о b — на ленте
      isOperator: (id) => id === "a" || id === "b",
      transferTargets: () => [{ id: "b", label: "B" }, { id: "a", label: "A" }],
      deliver() {},
      onEvict() {},
    },
  });
  const x = mk("x");
  events.push(x);
  ok(engine.run("claim", x, {}, { surface: "card" }).ok, "claim");
  const r = engine.run("transfer", x, { targetId: "a", comment: "смена" }, { surface: "card" });
  ok(r.ok, `transfer: ${JSON.stringify(r)}`);
  const { incidents, vectors: vs } = rec.take();
  const v = vs.find((u) => u.name === "transfer");
  ok(v && v.expect.ok && incidents[v.expect.ok.incidents.x.$ref].owner === "a", `вектор transfer: ${v && C.canonical(v.expect).slice(0, 200)}`);
  ok(v.world.some((e) => C.canonical(e) === '{"args":[],"fn":"transferTargets","out":["b","a"]}'), `лента: ${C.canonical(v.world)}`);
  const engineFor = lib.engines(g.IMEngine.create, w);
  const same = lib.replay(engineFor, v, incidents);
  ok(same.ok && same.misses.length === 0, `повтор: ${JSON.stringify({ misses: same.misses, diffs: same.diffs })}`);
  // Варианты поля — только с ленты: на ленте нет a — значение формы недопустимо (условия перехода те же и проходят)
  const tape = (out) => Object.assign({}, v, { world: v.world.map((e) => (e.fn === "transferTargets" ? Object.assign({}, e, { out }) : e)) });
  const noA = lib.replay(engineFor, tape(["b"]), incidents);
  ok(!noA.ok && noA.misses.length === 0 && noA.got.refusal && noA.got.refusal.code === "FORM_FIELD_INVALID", `без a на ленте: ${JSON.stringify({ misses: noA.misses, got: noA.got })}`);
  const none = lib.replay(engineFor, Object.assign({}, v, { world: v.world.filter((e) => e.fn !== "transferTargets") }), incidents);
  ok(!none.ok && none.misses.includes("transferTargets"), `без transferTargets: ${JSON.stringify({ misses: none.misses, got: none.got })}`);
});

test("повтор merge: записи server: true не сравниваются", () => {
  const C = vectors();
  const lib = tvectors();
  const w = structuredClone(W);
  const celRec = C.recorder(IMCel.create, w);
  const { rec, engine, events, mk } = trEngine({ machineW: w, cel: celRec, frame: celRec.frame, ctx: { shareAnswers: () => 0 } });
  const p = mk("p");
  const a = mk("a");
  const b = mk("b");
  events.push(p, a, b);
  ok(engine.merge(p, [a, b]).ok, "merge");
  mergedIn(p);
  const { incidents, vectors: vs } = rec.take();
  ok(vs.length === 1 && vs[0].op === "merge", `векторы: ${vs.map((u) => u.id)}`);
  const [v] = vs;
  const rows = v.expect.ok.journal.p;
  ok(rows[rows.length - 1].server === true, `журнал основного: ${C.canonical(rows)}`);
  const engineFor = lib.engines(g.IMEngine.create, w);
  const r = lib.replay(engineFor, v, incidents);
  ok(r.ok && r.misses.length === 0, `повтор: ${JSON.stringify({ misses: r.misses, diffs: r.diffs })}`);
  ok(!r.got.ok.journal.p.some((e) => e.templateKey === "workflow.journal.merged_in"), "ядро прототипа записало merged_in");
  // Сравнение для Go (server: true) — запись server.js сравнивается: итога ядра прототипа без неё мало
  const go = lib.compare(v, r.got, { pool: incidents, W: w, server: true });
  ok(go.diffs.length === 1 && go.diffs[0] === "journal.p", `server: true — ${JSON.stringify(go.diffs)}`);
  // Запись ядра без пометки server — сравнивается и в повторе
  const cut = structuredClone(v);
  cut.expect.ok.journal.p = rows.slice(1);
  const c = lib.replay(engineFor, cut, incidents);
  ok(!c.ok && c.diffs.includes("journal.p"), `без записи ядра основного: ${JSON.stringify(c.diffs)}`);
});

test("lib.compare: since только у hold, null — \"\", vars nil — {}, Transition и ID записи журнала, closeResultLabel, отказ и ошибка", () => {
  const lib = tvectors();
  const base = Object.assign({}, newPlain(), { id: "x" });
  const after = structuredClone(base);
  Object.assign(after, { state: "in_progress", owner: "me" });
  after.timers.reaction = Object.assign({}, after.timers.reaction, { since: 500 });
  const pool = { before: base, after };
  const row = { actor: "me", at: 1000, kind: "transition", templateKey: "k", vars: { closeResultLabel: "", n: 1 } };
  const v = {
    op: "run",
    incidents: [{ $ref: "before" }],
    target: { id: "x" },
    expect: {
      ok: {
        incidents: { x: { $ref: "after" } },
        journal: { x: [row, { actor: "me", at: 1000, kind: "transition", templateKey: "s", vars: {}, server: true }] },
        after: [{ action: "evict", incident: { $incident: "x" }, who: "", transitionId: "t", by: "" }],
        scenario: [],
        external: { x: [] },
        facts: { x: { from: { state: "new", owner: "", addressee: "", breaches: 0 }, to: { state: "in_progress", owner: "me", addressee: "me", breaches: 0 }, breach: "" } },
      },
    },
  };
  const got = structuredClone(v.expect);
  got.ok.incidents.x = structuredClone(after);
  got.ok.incidents.x.timers.reaction.since = 777; // since не у hold — не сравнивается
  got.ok.incidents.x.owner = "me";
  got.ok.journal.x = [Object.assign({}, row, { vars: { closeResultLabel: [""], n: 1 }, Transition: "t", ID: 5 })];
  got.ok.after[0].who = null;
  got.ok.facts.x.from.owner = null;
  got.ok.facts.x.breach = null;
  got.ok.canceled = { x: "y" }; // у run — сравнивается
  const cmp = (g2, opts = {}) => lib.compare(v, g2, Object.assign({ pool, W, server: false }, opts));
  let r = cmp(got);
  ok(JSON.stringify(r.diffs) === '["canceled"]' && r.closeResultLabel === 1, `нормализации: ${JSON.stringify(r)}`);
  delete got.ok.canceled;
  ok(cmp(got).diffs.length === 0, `без canceled: ${JSON.stringify(cmp(got).diffs)}`);
  ok(lib.compare(Object.assign({}, v, { op: "runAll" }), Object.assign({}, got, { ok: Object.assign({}, got.ok, { canceled: { x: "y" } }) }), { pool, W, server: false }).diffs.length === 0, "canceled у runAll сравнивается");
  // since у hold — сравнивается
  const held = structuredClone(got);
  held.ok.incidents.x.timers.hold = Object.assign({}, held.ok.incidents.x.timers.hold, { since: 9 });
  ok(JSON.stringify(cmp(held).diffs) === '["incidents.x"]', `since у hold: ${JSON.stringify(cmp(held).diffs)}`);
  // Изменился только since не у hold — как не изменился: инцидента может не быть с одной стороны
  const onlySince = structuredClone(v);
  onlySince.expect.ok.incidents.x = Object.assign(structuredClone(base), { timers: Object.assign({}, base.timers, { reaction: Object.assign({}, base.timers.reaction, { since: 3 }) }) });
  const noInc = structuredClone(got);
  delete noInc.ok.incidents;
  ok(lib.compare(onlySince, noInc, { pool, W, server: false }).diffs.length === 0, "since не у hold считается изменением");
  // vars: null и нет — {}
  const nilVars = { ok: { journal: { x: [{ actor: "me", at: 1, kind: "system", templateKey: "k", vars: null }] } } };
  ok(lib.compare({ op: "create", incidents: [], target: {}, expect: { ok: { journal: { x: [{ actor: "me", at: 1, kind: "system", templateKey: "k", vars: {} }] } } } }, nilVars, { pool, W }).diffs.length === 0, "vars null ≠ {}");
  // server: true — запись server.js сравнивается
  ok(JSON.stringify(cmp(got, { server: true }).diffs) === '["journal.x"]', `server: true: ${JSON.stringify(cmp(got, { server: true }).diffs)}`);
  // external — только у инцидентов ожидаемого
  const ext = structuredClone(got);
  ext.ok.external.y = [{ fn: "notify", target: "z" }];
  ok(cmp(ext).diffs.length === 0, `external чужого: ${JSON.stringify(cmp(ext).diffs)}`);
  ext.ok.external.x = [{ fn: "notify", target: "z" }];
  ok(JSON.stringify(cmp(ext).diffs) === '["external.x"]', `external: ${JSON.stringify(cmp(ext).diffs)}`);
  // Отказ: поля, которые есть в ожидаемом; ничего не записано
  const refusal = { op: "run", incidents: [], target: {}, expect: { refusal: { why: ["k", { p: 1 }], guard: "g" } } };
  const rc = (gotR) => lib.compare(refusal, gotR, { pool, W }).diffs;
  ok(rc({ refusal: { why: ["k", { p: 1 }], guard: "g", code: "C", id: "x" } }).length === 0, "лишние поля отказа сравниваются");
  ok(rc({ refusal: { why: ["k", { p: 2 }], guard: "g" } }).length === 1 && rc({ refusal: { why: ["k", { p: 1 }], guard: "h" } }).length === 1, "подстановки или guard отказа не сравниваются");
  ok(rc({ refusal: { why: ["k", { p: 1 }], guard: "g" }, writes: 1 }).length === 1 && rc({ error: "x" }).length === 1 && rc(got).length === 1, "отказ с записью, ошибка или ok вместо отказа");
  // Ошибка: текст не сравнивается
  const error = { op: "run", incidents: [], target: {}, expect: { error: "a" } };
  ok(lib.compare(error, { error: "b" }, { pool, W }).diffs.length === 0 && lib.compare(error, { refusal: { why: ["k"] } }, { pool, W }).diffs.length === 1, "ошибка");
});

test("повтор: неиспользованная запись ленты — только счёт unused; closeResultLabel — в ответе", () => {
  const C = vectors();
  const lib = tvectors();
  const w = structuredClone(W);
  const celRec = C.recorder(IMCel.create, w);
  const { rec, engine, events, mk } = trEngine({ machineW: w, cel: celRec, frame: celRec.frame });
  const x = mk("x");
  events.push(x);
  ok(engine.run("claim", x, {}, { surface: "card" }).ok, "claim");
  const { incidents, vectors: [v] } = rec.take();
  const engineFor = lib.engines(g.IMEngine.create, w);
  const same = lib.replay(engineFor, v, incidents);
  ok(same.ok && same.unused === 0 && same.closeResultLabel === 0, `повтор: ${JSON.stringify({ unused: same.unused, closeResultLabel: same.closeResultLabel, diffs: same.diffs })}`);
  // Лишняя запись на ленте — не провал, только счёт
  const extra = lib.replay(engineFor, Object.assign({}, v, { world: v.world.concat([{ fn: "can", args: ["nope"], out: true }]) }), incidents);
  ok(extra.ok && extra.misses.length === 0 && extra.unused === 1, `лишняя запись: ${JSON.stringify({ ok: extra.ok, unused: extra.unused, misses: extra.misses })}`);
});

test("lib.compare: исключение повтора — всегда расхождение thrown, и при пустом или битом expect", () => {
  const lib = tvectors();
  const thrown = { thrown: "в списке нет x" };
  [undefined, {}, { ok: {} }, { refusal: { why: ["k"] } }, { error: "e" }, { nope: 1 }].forEach((expect) => {
    const r = lib.compare({ op: "run", incidents: [], target: { id: "x" }, expect }, thrown, { W });
    ok(JSON.stringify(r.diffs) === '["thrown"]', `expect ${JSON.stringify(expect)}: ${JSON.stringify(r.diffs)}`);
  });
  // replay: цель вне списка — исключение ядра повтора, вектор не проходит и с пустым expect
  const engineFor = lib.engines(g.IMEngine.create, structuredClone(W));
  const r = lib.replay(engineFor, { op: "run", me: "me", name: "claim", incidents: [], target: { id: "x" }, world: [], now: 1, expect: {} }, {});
  ok(!r.ok && r.got.thrown && JSON.stringify(r.diffs) === '["thrown"]', `replay: ${JSON.stringify(r)}`);
});

test("lib.recordedProblem: skipped — все четыре счётчика и все 0, векторы не пусты", () => {
  const lib = tvectors();
  const zero = { nowChanged: 0, outsideEngine: 0, tapeRepeat: 0, worldError: 0 };
  const rec = (over) => Object.assign({ incidents: {}, vectors: [{ id: "t" }], skipped: Object.assign({}, zero) }, over);
  ok(lib.recordedProblem(rec()) === "", `целая запись: ${lib.recordedProblem(rec())}`);
  const without = (k) => {
    const s = Object.assign({}, zero);
    delete s[k];
    return rec({ skipped: s });
  };
  [
    [rec({ skipped: undefined }), "skipped"],
    [without("worldError"), "skipped.worldError"],
    [without("nowChanged"), "skipped.nowChanged"],
    [rec({ skipped: Object.assign({}, zero, { tapeRepeat: 2 }) }), "skipped.tapeRepeat = 2"],
    [rec({ vectors: [] }), "vectors"],
    [rec({ vectors: undefined }), "vectors"],
  ].forEach(([r, want]) => {
    const p = lib.recordedProblem(r);
    ok(p.includes(want), `${JSON.stringify(r).slice(0, 120)}: «${p}», ждали «${want}»`);
  });
});

test("lib.kindOf: dispatcher и system — system, остальные — transition", () => {
  const lib = tvectors();
  ok(lib.kindOf("dispatcher") === "system" && lib.kindOf("system") === "system", "system");
  ok(lib.kindOf("me") === "transition" && lib.kindOf("") === "transition" && lib.kindOf(null) === "transition", "transition");
});

test("lib.select: не больше 20 на op:name, 4 на исход, по кругу исходов", () => {
  const lib = tvectors();
  const v = (i, outcome, name = "claim") => ({ id: `transition:run:${name}:${i}`, op: "run", name, expect: { refusal: { why: [`k${outcome}`] } } });
  // Шесть исходов по 10: по кругу — 4 круга по 6 = 24 > 20, берётся 20; ни одного исхода больше 4
  const all = Array.from({ length: 60 }, (_, i) => v(i, i % 6));
  const s = lib.select(all, { perName: 20, perOutcome: 4 });
  const per = s.reduce((o, x) => ((o[x.expect.refusal.why[0]] = (o[x.expect.refusal.why[0]] || 0) + 1), o), {});
  ok(s.length === 20 && Object.values(per).every((n) => n <= 4), `${s.length}, ${JSON.stringify(per)}`);
  ok(s.every((x, i, a) => i === 0 || Number(a[i - 1].id.split(":")[3]) < Number(x.id.split(":")[3])), "порядок итога не как на входе");
  // Одинаковые исходы — 4; другое имя — свой предел; по умолчанию — 20 и 4
  const same = lib.select(Array.from({ length: 25 }, (_, i) => v(i, 0)).concat([v(0, 0, "hold")]));
  ok(same.length === 5 && same.filter((x) => x.name === "hold").length === 1, `одинаковые: ${same.length}`);
  // ok: исход — ключи журнала, виды after и timer_overridden
  const okv = (i, keys, after = []) => ({ id: `t:${i}`, op: "run", name: "x", expect: { ok: { journal: { a: keys.map((k) => ({ templateKey: k })) }, after: after.map((a) => ({ action: a })) } } });
  ok(lib.outcomeOf(okv(0, ["a", "b"]).expect) === lib.outcomeOf(okv(1, ["b", "a"]).expect), "порядок ключей журнала меняет исход");
  ok(lib.outcomeOf(okv(0, ["a"]).expect) !== lib.outcomeOf(okv(1, ["a"], ["notify"]).expect), "after не меняет исход");
  ok(lib.outcomeOf({ refusal: { why: ["a", { x: 1 }] } }) === lib.outcomeOf({ refusal: { why: ["a", { x: 2 }] } }), "подстановки отказа меняют исход");
  ok(lib.outcomeOf({ error: "a" }) === lib.outcomeOf({ error: "b" }), "текст ошибки меняет исход");
});

/* ===== Векторы tick (решение 194 плана 60): такт планировщика на ядре прототипа ===== */

const TICK_NOW = 10000000;
// Ядро под записью переходов и записью CEL (её кадр видит факты мира), часы — TICK_NOW
function tickEngine(ctx = {}) {
  const C = vectors();
  const w = structuredClone(W);
  const celRec = C.recorder(IMCel.create, w);
  // deliver, onEvict, onBreachShared — как у сервера: действия после фиксации — в after вектора
  const t = trEngine({ machineW: w, cel: celRec, frame: celRec.frame, ctx: Object.assign({ now: () => TICK_NOW, deliver() {}, onEvict() {}, onBreachShared() {} }, ctx) });
  return Object.assign(t, { C, lib: tvectors(), engineFor: tvectors().engines(g.IMEngine.create, w) });
}
const firedOf = (list) => list.map((f) => ({ at: f.at, id: f.id, transition: f.transition }));

test("tick: у каждого сработавшего — at, момент перехода (runAt), а не now; external — его внешние эффекты", () => {
  const { engine, events, mk } = tickEngine();
  events.push(mk("x", { number: "INC-0001", timers: { reaction: { due: TICK_NOW - 60000 } } }));
  const fired = engine.tick();
  ok(fired.length >= 1, `не сработало ничего: ${JSON.stringify(fired)}`);
  // Переход по таймеру без готового системного — через graceSec (3 с) после дедлайна
  ok(fired[0].at === TICK_NOW - 60000 + 3000, `at: ${fired[0].at}`);
  ok(Array.isArray(fired[0].external) && fired.every((f) => typeof f.at === "number"), `external: ${JSON.stringify(fired[0].external)}`);
});

test("запись tick: вход — весь список до вызова; ожидаемое — fired по порядку с at, facts и external по каждому; повтор по ленте — тот же итог", () => {
  const { C, lib, engineFor, rec, engine, events, mk } = tickEngine();
  // Порядок по моменту, а не по списку: y просрочен раньше
  const x = mk("x", { number: "INC-0002", timers: { reaction: { due: TICK_NOW - 60000 } } });
  const y = mk("y", { number: "INC-0001", timers: { reaction: { due: TICK_NOW - 90000 } } });
  const z = mk("z", { number: "INC-0003", timers: {} });
  events.push(x, y, z);
  const fired = engine.tick();
  const { incidents, vectors: vs, skipped } = rec.take();
  ok(C.canonical(skipped) === ZERO_SKIPPED, `skipped: ${C.canonical(skipped)}`);
  ok(vs.length === 1, `векторов ${vs.length}`);
  const [v] = vs;
  ok(v.kind === "transition" && v.op === "tick" && v.name === fired[0].transition && v.me === "me" && v.now === TICK_NOW && v.surface === "" && C.canonical(v.form) === "{}", `вектор: ${C.canonical(Object.assign({}, v, { world: [], expect: {}, incidents: [] }))}`);
  ok(C.canonical(v.target) === '{"agentOnly":false}' && C.canonical(v.changedAt) === "{}" && C.canonical(v.journalAtNow) === "{}", `target ${C.canonical(v.target)}, changedAt ${C.canonical(v.changedAt)}`);
  const first = incidents[v.incidents[0].$ref];
  ok(v.incidents.map((d) => incidents[d.$ref].id).join() === "x,y,z" && first.state === "new" && first.timers.reaction.due === TICK_NOW - 60000 && !first.breaches.length, `список до вызова: ${C.canonical(first).slice(0, 300)}`);
  const { id, case: _c, expect, ...input } = v;
  ok(id === `transition:tick:${v.name}:${sha256(C.canonical(input)).slice(0, 10)}`, `id ${id}`);
  const o = expect.ok;
  ok(o && C.canonical(o.fired) === C.canonical(firedOf(fired)), `fired: ${C.canonical(o && o.fired)} ≠ ${C.canonical(firedOf(fired))}`);
  ok(o.fired.map((f) => f.id).join() === "y,x" && o.fired[0].at === TICK_NOW - 87000 && o.fired[1].at === TICK_NOW - 57000, `порядок и at: ${C.canonical(o.fired)}`);
  ok(o.facts.length === 2 && o.facts[0].to.breaches === 1 && o.facts[0].breach === "reaction" && o.external.length === 2 && Array.isArray(o.external[0]), `facts / external: ${C.canonical(o.facts)} ${C.canonical(o.external)}`);
  ok(Object.keys(o.incidents).sort().join() === "x,y" && o.journal.y.length > 0 && o.journal.y.every((e) => e.at === TICK_NOW - 87000 && e.actor === "dispatcher"), `журнал y: ${C.canonical(o.journal)}`);
  const nows = v.world.filter((e) => e.fn === "ctx.now");
  ok(nows.length === 1 && nows[0].out === TICK_NOW && C.canonical(nows[0].args) === "[]", `ctx.now на ленте: ${C.canonical(nows)}`);
  ok(v.world.some((e) => e.fn === "can"), `факты мира: ${C.canonical(v.world)}`);
  const r = lib.replay(engineFor, v, incidents);
  ok(r.ok && r.unused === 0, `повтор: ${JSON.stringify({ misses: r.misses, diffs: r.diffs, unused: r.unused, got: r.got }).slice(0, 600)}`);
  // Неверный момент, порядок или facts в ожидаемом — расхождение
  const bad = (f) => {
    const u = structuredClone(v);
    f(u.expect.ok);
    return lib.replay(engineFor, u, incidents).diffs;
  };
  ok(bad((e) => (e.fired[0].at = TICK_NOW)).includes("fired"), "at не сравнивается");
  ok(bad((e) => e.fired.reverse()).includes("fired"), "порядок fired не сравнивается");
  ok(bad((e) => (e.facts[1].breach = "")).includes("facts.1"), "facts второго не сравниваются");
  ok(bad((e) => (e.external[0] = [{ fn: "notify", target: "x" }])).includes("external.0"), "external не сравнивается");
  // Без ctx.now на ленте — промах
  const noNow = lib.replay(engineFor, Object.assign({}, v, { world: v.world.filter((e) => e.fn !== "ctx.now") }), incidents);
  ok(!noNow.ok && noNow.misses.includes("ctx.now"), `без ctx.now: ${JSON.stringify(noNow.misses)}`);
});

test("запись tick: молчание — на ленте idleSec [me] как его даёт сервер, момент не раньше changedAt; без changedAt повтор расходится", () => {
  const { C, lib, engineFor, rec, engine, events, mk } = tickEngine({ idleSec: () => 500 });
  const x = mk("x", { number: "INC-0001", state: "in_progress", owner: "me", timers: {} });
  x.changedAt = TICK_NOW - 100000;
  events.push(x);
  const fired = engine.tick();
  // idleHoldSec 300: молчание с now − 500 с даёт now − 200 с, но инцидент изменился в now − 100 с (BUG-76)
  ok(fired.length >= 1 && fired[0].transition === "system_hold_idle" && fired[0].at === TICK_NOW - 100000, `fired: ${JSON.stringify(firedOf(fired))}`);
  const { incidents, vectors: vs, skipped } = rec.take();
  ok(vs.length === 1 && C.canonical(skipped) === ZERO_SKIPPED, `векторов ${vs.length}, skipped ${C.canonical(skipped)}`);
  const [v] = vs;
  ok(C.canonical(v.changedAt) === `{"x":${TICK_NOW - 100000}}`, `changedAt: ${C.canonical(v.changedAt)}`);
  // Сырое молчание, а не факт cel.world на момент перехода (тот выводится из него)
  const idle = v.world.filter((e) => e.fn === "idleSec");
  ok(idle.length === 1 && C.canonical(idle[0]) === '{"args":["me"],"fn":"idleSec","out":500}', `idleSec на ленте: ${C.canonical(idle)}`);
  const r = lib.replay(engineFor, v, incidents);
  ok(r.ok, `повтор: ${JSON.stringify({ misses: r.misses, diffs: r.diffs, got: r.got }).slice(0, 600)}`);
  const lost = lib.replay(engineFor, Object.assign({}, v, { changedAt: {} }), incidents);
  ok(!lost.ok && lost.diffs.includes("fired"), `без changedAt: ${JSON.stringify(lost.diffs)}`);
  const quiet = lib.replay(engineFor, Object.assign({}, v, { world: v.world.map((e) => (e.fn === "idleSec" ? Object.assign({}, e, { out: 100 }) : e)) }), incidents);
  ok(!quiet.ok && quiet.misses.length === 0 && quiet.diffs.includes("fired"), `idleSec 100: ${JSON.stringify({ diffs: quiet.diffs, misses: quiet.misses })}`);
});

test("tick с исполнителями коллег: сработал переход коллеги — вектора нет, счёт withPeers; сработали только мои — вектор, повтор без коллег тот же", () => {
  const { C, lib, engineFor, rec, engine, events, mk, ctx } = tickEngine({ agentStateOf: (who) => (who === "colleague" ? "offline" : "available") });
  const peer = rec.create(Object.assign({}, ctx, { me: "colleague", agentState: () => "offline" }));
  events.push(mk("c", { number: "INC-0002", state: "in_progress", owner: "colleague", timers: {} }));
  const a = engine.tick({ peers: [peer] });
  ok(a.length >= 1 && a[0].operator === "colleague" && a[0].transition === "owner_signed_out", `такт с коллегой: ${JSON.stringify(a.map((f) => [f.operator, f.transition]))}`);
  let taken = rec.take();
  ok(taken.vectors.length === 0 && taken.withPeers === 1 && C.canonical(taken.skipped) === ZERO_SKIPPED, `векторов ${taken.vectors.length}, withPeers ${taken.withPeers}, skipped ${C.canonical(taken.skipped)}`);
  events.length = 0;
  events.push(mk("x", { number: "INC-0001", timers: { reaction: { due: TICK_NOW - 60000 } } }));
  const b = engine.tick({ peers: [peer] });
  ok(b.length >= 1 && b.every((f) => f.operator === "me"), `только мои: ${JSON.stringify(b.map((f) => [f.operator, f.transition]))}`);
  taken = rec.take();
  ok(taken.vectors.length === 1 && taken.withPeers === 1, `векторов ${taken.vectors.length}, withPeers ${taken.withPeers}`);
  const r = lib.replay(engineFor, taken.vectors[0], taken.incidents);
  ok(r.ok, `повтор без коллег: ${JSON.stringify({ misses: r.misses, diffs: r.diffs })}`);
});

test("tick: часы сдвинулись за вызов — вектора нет, skipped.nowChanged 1", () => {
  let t = TICK_NOW;
  const { rec, engine, events, mk } = trEngine({ ctx: { now: () => t++ } });
  events.push(mk("x", { timers: { reaction: { due: TICK_NOW - 60000 } } }));
  engine.tick();
  const { vectors: vs, skipped } = rec.take();
  ok(vs.length === 0 && skipped.nowChanged === 1, `векторов ${vs.length}, skipped ${JSON.stringify(skipped)}`);
});

test("tick без сработавших — вектор tick:tick с пустым fired; исход отбора различает сработавшие переходы", () => {
  const { C, lib, engineFor, rec, engine, events, mk } = tickEngine();
  // В окне после дедлайна (graceSec 3 с) переход по таймеру ещё не выполняется
  events.push(mk("x", { number: "INC-0001", timers: { reaction: { due: TICK_NOW - 2000 } } }));
  ok(engine.tick().length === 0, "в окне сработало");
  const { incidents, vectors: vs } = rec.take();
  ok(vs.length === 1 && vs[0].name === "tick" && C.canonical(vs[0].expect.ok.fired) === "[]" && !("incidents" in vs[0].expect.ok), `вектор: ${C.canonical(vs.map((v) => v.expect))}`);
  ok(lib.replay(engineFor, vs[0], incidents).ok, "повтор пустого такта");
  const e = (ids) => ({ ok: { fired: ids.map((t) => ({ at: 1, id: "x", transition: t })), journal: {}, after: [] } });
  ok(lib.outcomeOf(e(["a", "b"])) !== lib.outcomeOf(e(["a"])) && lib.outcomeOf(e(["a"])) !== lib.outcomeOf(e([])), "исход не различает сработавшие");
});

results.forEach(([name, e]) => console.log(e ? `FAIL ${name}\n    ${String(e.message || e)}` : `ok   ${name}`));
const failed = results.filter(([, e]) => e).length;
console.log(`test_cel: ${results.length - failed} из ${results.length}`);
process.exitCode = failed;
