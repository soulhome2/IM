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
for (const f of ["prototype/vendor/cel-js/cel.js", "prototype/cel-runtime.js", "tests/cel-vectors.js"]) {
  // Библиотеки векторов может не быть — тогда падают только её тесты
  if (f.startsWith("tests/") && !fs.existsSync(path.join(ROOT, f))) continue;
  vm.runInContext(fs.readFileSync(path.join(ROOT, f), "utf8"), g, { filename: f });
}
const { IMCel } = g;
const vectors = () => {
  if (!g.IMCelVectors) throw new Error("IMCelVectors не объявлен: нет tests/cel-vectors.js");
  return g.IMCelVectors.lib;
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
  cel.guard("hasPermission", ["incident:claim"], Object.assign({}, scope, { world: { can: () => true } }), {});
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

results.forEach(([name, e]) => console.log(e ? `FAIL ${name}\n    ${String(e.message || e)}` : `ok   ${name}`));
const failed = results.filter(([, e]) => e).length;
console.log(`test_cel: ${results.length - failed} из ${results.length}`);
process.exitCode = failed;
