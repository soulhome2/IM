// Векторы CEL для бэкенда (PROC-44): файл Specification/Workflow_machine/fixtures/cel-vectors.json — «вход + мир →
// результат» каждого вида вычислений машины на исполнителе прототипа (prototype/cel-runtime.js). Бэкенд повторяет
// каждый вектор своим исполнителем и сверяет ответ. Формат и как повторять — CEL.md, раздел «Векторы».
//
//   node tools/cel_vectors.mjs --update   — запись: Chrome на tests/api.html?celVectors=1 (около 6 мин), отбор
//                                           (lib.select), синтетика на границах; затем всё, что делает --check,
//                                           и только потом запись файла. Тесты API не pass — стоп без записи.
//                                           Тем же прогоном — fixtures/transition-vectors.json (блок
//                                           transitionvectors-out и синтетика переходов в Node): любой счётчик
//                                           skipped не 0, файл больше 4 МБ или случай синтетики не показал своё —
//                                           стоп, не пишется ни один из двух файлов
//   node tools/cel_vectors.mjs --check    — быстро, без Chrome: файл есть, собран от этой машины (sha256 байтов),
//                                           равен своей канонической записи, каждый вектор повторяется по ленте
//                                           на нынешнем исполнителе, у каждого имени машины есть вектор, размер;
//                                           затем векторы переходов: покрытие (transitionCoverage), каждый
//                                           повторяется по ленте на ядре прототипа (prototype/engine.js, по ядру
//                                           на me), сравнение — решение 41. --update
//                                           делает то же до записи; расхождение или промах — не пишется ни один файл
//   --file=путь — другой файл векторов; --transitions=путь — другой файл векторов переходов; --machine=путь —
//   другая машина (проверка хэша); --tmp=папка — где
//   --update держит профиль Chrome (иначе — системная временная папка); CHROME — другой исполняемый файл Chrome
//
// Библиотека векторов (канон, пул, лента, повтор, отбор, запись) — tests/cel-vectors.js. Код выхода — 0 или 1.
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import vm from "node:vm";
import { spawnSync } from "node:child_process";
import { fileURLToPath, pathToFileURL } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const MACHINE = path.join(ROOT, "Specification/Workflow_machine/workflow_schema.v1.json");
const FILE = path.join(ROOT, "Specification/Workflow_machine/fixtures/cel-vectors.json");
const MAX_BYTES = 8 * 1024 * 1024;
const TRANSITIONS_FILE = path.join(ROOT, "Specification/Workflow_machine/fixtures/transition-vectors.json");
const TRANSITIONS_MAX_BYTES = 4 * 1024 * 1024;
const TRANSITIONS_COMMENT = "Собрано tools/cel_vectors.mjs --update из записи tests/api.html?celVectors=1 и синтетики. Руками не править. Формат — CEL.md, «Векторы переходов»";
const OPS = ["create", "merge", "run", "runAll"];
// Требования покрытия векторов переходов без вектора — с причиной словами (ключ → причина); не больше 3, больше —
// синтетика (syntheticTransitions). Ключ — как у требования в transitionCoverage: имя перехода («reopen», «create») —
// нет вектора ok с этим именем; «op:refusal» («run:refusal», «runAll:refusal», «merge:refusal») — нет отказа у op;
// «run:canceled» — нет вектора run с canceled. Пишется в поле uncovered файла переходов
const UNCOVERED_TRANSITIONS_OK = {};
const UNCOVERED_TRANSITIONS_MAX = 3;
// Запись: виртуальное время страницы (таймеры тестов) и настоящее — запись идёт около 6 минут, почти всё — JS
// кодирования входов, а он виртуального времени не тратит
const VIRTUAL_BUDGET_MS = 180000;
const WALL_TIMEOUT_MS = 15 * 60 * 1000;
const COMMENT = "Собрано tools/cel_vectors.mjs --update из записи tests/api.html?celVectors=1 и синтетики. Руками не править. Формат — CEL.md, «Векторы»";
const KINDS = ["guard", "rule", "definition", "effect"];

// Имена машины, у которых векторов нет и не будет, — с причиной словами («вид:имя» → причина). Больше 10 имён —
// не расширять список, а добавить синтетику
const UNCOVERED_OK = {};

/* ===== Исполнитель прототипа в Node ===== */

function load(machinePath) {
  const bytes = fs.readFileSync(machinePath);
  const W = JSON.parse(bytes.toString("utf8"));
  const g = { console, TextEncoder, TextDecoder };
  g.window = g;
  vm.createContext(g);
  // Ядро прототипа и библиотека векторов переходов — для их повтора, как в tools/check_quint_replay.mjs
  for (const f of ["prototype/vendor/cel-js/cel.js", "prototype/cel-runtime.js", "prototype/engine.js", "tests/cel-vectors.js", "tests/transition-vectors.js"]) {
    vm.runInContext(fs.readFileSync(path.join(ROOT, f), "utf8"), g, { filename: f });
  }
  return { W, bytes, IMCel: g.IMCel, lib: g.IMCelVectors.lib, IMEngine: g.IMEngine, tlib: g.IMTransitionVectors.lib };
}
const sha256 = (b) => crypto.createHash("sha256").update(b).digest("hex");

/* ===== Канонический файл: шапка, по строке на инцидент пула, по строке на вектор ===== */

// Ключи пула, на которые ссылается значение ({$ref})
function refs(v, out) {
  if (Array.isArray(v)) v.forEach((x) => refs(x, out));
  else if (v && typeof v === "object") {
    if (typeof v.$ref === "string") out.add(v.$ref);
    Object.values(v).forEach((x) => refs(x, out));
  }
  return out;
}
// Файл из данных: векторы — по id, в пуле — только то, на что ссылаются векторы, по ключу; counts — по векторам.
// Ключи верхнего уровня — по алфавиту, как в каноне
function serialize(lib, { incidents, vectors, machineSha256, skipped }) {
  const vs = [...vectors].sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
  const used = [...refs(vs, new Set())].sort();
  used.forEach((k) => {
    if (!incidents[k]) throw new Error(`в пуле нет инцидента ${k}`);
  });
  const counts = Object.fromEntries(KINDS.map((k) => [k, vs.filter((v) => v.kind === k).length]));
  return (
    `{"$comment":${JSON.stringify(COMMENT)},"counts":${lib.canonical(counts)},"format":1,\n` +
    `"incidents":{\n${used.map((k) => `${JSON.stringify(k)}:${lib.canonical(incidents[k])}`).join(",\n")}},\n` +
    `"machineSha256":${JSON.stringify(machineSha256)},"skipped":${lib.canonical(skipped)},\n` +
    `"vectors":[\n${vs.map((v) => lib.canonical(v)).join(",\n")}]}\n`
  );
}

// Файл переходов: векторы — по id, пул — как записан (в нём только инциденты оставленных векторов), counts — по op
function serializeTransitions(lib, { incidents, vectors, machineSha256, skipped, uncovered }) {
  const vs = [...vectors].sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
  const counts = Object.fromEntries(OPS.map((o) => [o, vs.filter((v) => v.op === o).length]));
  return (
    `{"$comment":${JSON.stringify(TRANSITIONS_COMMENT)},"counts":${lib.canonical(counts)},"format":1,\n` +
    `"incidents":{\n${Object.keys(incidents).sort().map((k) => `${JSON.stringify(k)}:${lib.canonical(incidents[k])}`).join(",\n")}},\n` +
    `"machineSha256":${JSON.stringify(machineSha256)},"skipped":${lib.canonical(skipped)},"uncovered":${lib.canonical(uncovered)},\n` +
    `"vectors":[\n${vs.map((v) => lib.canonical(v)).join(",\n")}]}\n`
  );
}

// Стоп до записи: запись переходов неполна (нет skipped или его счётчика, счётчик не 0, векторов нет —
// lib.recordedProblem) или файл больше 4 МБ. synth — синтетика переходов: вход, совпавший с записанным, остаётся
// синтетикой (с названием случая)
function transitionsText(env, tr, synth, machineSha256) {
  const problem = env.tlib.recordedProblem(tr);
  if (problem) throw new Error(`запись переходов: ${problem}. Файлы не записаны`);
  const ids = new Set(synth.vectors.map((v) => v.id));
  const vectors = tr.vectors.filter((v) => !ids.has(v.id)).concat(synth.vectors);
  const text = serializeTransitions(env.lib, { incidents: Object.assign({}, tr.incidents, synth.incidents), vectors, machineSha256, skipped: tr.skipped, uncovered: UNCOVERED_TRANSITIONS_OK });
  const size = Buffer.byteLength(text, "utf8");
  if (size > TRANSITIONS_MAX_BYTES) throw new Error(`файл переходов ${(size / 1048576).toFixed(2)} МБ — больше 4 МБ. Файлы не записаны`);
  return text;
}

/* ===== Проверка ===== */

// text — содержимое файла, env — исполнитель на машине, с которой сверяем. Печатает итог, возвращает true/false
function check(text, env, where) {
  const { lib, W, IMCel } = env;
  const fail = (msg) => (console.log(msg), false);
  let data;
  try {
    data = JSON.parse(text);
  } catch (e) {
    return fail(`${where}: правлен руками — не JSON (${e.message}): node tools/cel_vectors.mjs --update`);
  }
  if (data.machineSha256 !== sha256(env.bytes)) return fail(`${where}: машина изменилась после сборки векторов: node tools/cel_vectors.mjs --update`);
  if (data.format !== 1) return fail(`${where}: формат ${data.format}, а этот инструмент знает 1`);
  let canon;
  try {
    canon = serialize(lib, data);
  } catch (e) {
    return fail(`${where}: правлен руками — ${e.message}: node tools/cel_vectors.mjs --update`);
  }
  if (canon !== text) {
    const a = text.split("\n");
    const b = canon.split("\n");
    let i = 0;
    while (i < a.length && a[i] === b[i]) i++;
    return fail(`${where}: правлен руками — файл не равен своей канонической записи (первое отличие — строка ${i + 1}): node tools/cel_vectors.mjs --update`);
  }
  const cel = IMCel.create(W);
  const wrongId = [];
  const repeat = [];
  const mismatch = [];
  const missed = [];
  data.vectors.forEach((v) => {
    if (lib.idOf(v) !== v.id) wrongId.push(v.id);
    const calls = (v.world || []).map((e) => `${e.fn}|${lib.canonical(e.args)}`);
    if (new Set(calls).size !== calls.length) repeat.push(v.id);
    const r = lib.replay(cel, v, data.incidents);
    if (r.misses.length) missed.push(`${v.id} (${[...new Set(r.misses)].join(", ")})`);
    else if (!r.ok) mismatch.push(`${v.id}: ждали ${lib.canonical(v.expect).slice(0, 200)}, а ${lib.canonical(r.got).slice(0, 200)}`);
  });
  // Покрытие: у каждого имени машины — вектор, или имя в UNCOVERED_OK с причиной
  const names = {
    guard: cel.guardNames(),
    effect: cel.effectNames(),
    definition: Object.keys(W.cel.definitions || {}).filter((k) => !k.startsWith("$")),
    rule: cel.ruleNames(),
  };
  const covered = new Set(data.vectors.map((v) => `${v.kind}:${v.name}`));
  const all = new Set(KINDS.flatMap((k) => names[k].map((n) => `${k}:${n}`)));
  const uncovered = [...all].filter((n) => !covered.has(n) && !UNCOVERED_OK[n]);
  const staleOk = Object.keys(UNCOVERED_OK).filter((n) => covered.has(n) || !all.has(n) || !String(UNCOVERED_OK[n]).trim());
  const size = Buffer.byteLength(text, "utf8");
  const synthetic = data.vectors.filter((v) => v.case != null);
  const by = (k) => data.vectors.filter((v) => v.kind === k).length;
  // Числа — векторов: у одного вектора бывает и id не по входу, и расхождение
  const idsOf = (...lists) => new Set(lists.flat().map((s) => s.split(/[ :]/).slice(0, 3).join(":"))).size;

  console.log(
    `векторов: ${data.vectors.length} (${KINDS.map((k) => `${k} ${by(k)}`).join(", ")}), расхождений: ${idsOf(mismatch, wrongId)}, промахов ленты: ${idsOf(missed, repeat)}, без векторов: ${uncovered.length}`
  );
  console.log(
    `  синтетика: ${synthetic.length} (с ошибкой в expect: ${synthetic.filter((v) => v.expect && "error" in v.expect).length}); ` +
      `пропущено при записи — разные ответы на один вызов мира: ${(data.skipped || {}).tapeRepeat}, ошибка факта мира: ${(data.skipped || {}).worldError}; ` +
      `имён: условий ${names.guard.length}, эффектов ${names.effect.length}, определений ${names.definition.length}, правил интерфейса ${names.rule.length}; ` +
      `${(size / 1048576).toFixed(2)} МБ`
  );
  const list = (title, xs) => xs.length && console.log(`${title}:\n  ${xs.slice(0, 30).join("\n  ")}${xs.length > 30 ? `\n  … ещё ${xs.length - 30}` : ""}`);
  list("расхождения", mismatch);
  list("id не по входу", wrongId);
  list("промахи ленты", missed);
  list("на ленте два ответа на один вызов", repeat);
  list("без векторов (синтетика в tools/cel_vectors.mjs или UNCOVERED_OK с причиной)", uncovered);
  list("UNCOVERED_OK: имя покрыто, нет в машине или без причины", staleOk);
  // Ошибка вычисления — ошибка сервера (PROC-44 в3): у каждого вида вычислений есть вектор с expect.error
  const noError = KINDS.filter((k) => !data.vectors.some((v) => v.kind === k && v.expect && "error" in v.expect));
  list("нет вектора с ошибкой вычисления (синтетика в tools/cel_vectors.mjs)", noError);
  let good = !mismatch.length && !wrongId.length && !missed.length && !repeat.length && !uncovered.length && !staleOk.length && !noError.length;
  if (size > MAX_BYTES) {
    console.log(`файл ${(size / 1048576).toFixed(2)} МБ — больше 8 МБ: уменьшите PER_NAME в tests/cel-vectors.js`);
    good = false;
  }
  return good;
}

// Покрытие векторов переходов: требование (ключ, как в UNCOVERED_TRANSITIONS_OK) → есть ли вектор. У каждого ручного
// перехода машины (trigger: manual) и у create — вектор ok с этим именем, любой op (detach — run и runAll, merge —
// merge); у run, runAll и merge — хотя бы один отказ; хотя бы один вектор run с canceled. Синтетика считается.
// Требование без вектора и не в UNCOVERED_TRANSITIONS_OK — провал. Возвращает число без векторов и строки «что не так»
function transitionCoverage(lib, W, data) {
  const has = (test) => data.vectors.some((v) => v.expect && test(v));
  const need = {};
  W.transitions
    .filter((t) => t.trigger === "manual")
    .map((t) => t.id)
    .concat("create")
    .forEach((n) => (need[n] = has((v) => v.name === n && v.expect.ok)));
  ["run", "runAll", "merge"].forEach((o) => (need[`${o}:refusal`] = has((v) => v.op === o && v.expect.refusal)));
  need["run:canceled"] = has((v) => v.op === "run" && v.expect.ok && Object.keys(v.expect.ok.canceled || {}).length > 0);
  const ok = UNCOVERED_TRANSITIONS_OK;
  const missing = Object.keys(need).filter((k) => !need[k] && !ok[k]);
  const stale = Object.keys(ok).filter((k) => !(k in need) || need[k] || !String(ok[k]).trim());
  const problems = [];
  if (missing.length) problems.push(`без векторов: ${missing.join(", ")} — синтетика в tools/cel_vectors.mjs или UNCOVERED_TRANSITIONS_OK с причиной`);
  if (stale.length) problems.push(`UNCOVERED_TRANSITIONS_OK: требование покрыто, его нет или без причины: ${stale.join(", ")}`);
  if (Object.keys(ok).length > UNCOVERED_TRANSITIONS_MAX) problems.push(`UNCOVERED_TRANSITIONS_OK: ${Object.keys(ok).length} записей — больше ${UNCOVERED_TRANSITIONS_MAX}: добавьте синтетику`);
  if (lib.canonical(data.uncovered ?? null) !== lib.canonical(ok)) problems.push("поле uncovered файла не равно UNCOVERED_TRANSITIONS_OK: node tools/cel_vectors.mjs --update");
  return { missing: missing.length, problems };
}

// Векторы переходов: text — содержимое файла, env — ядро прототипа на машине, с которой сверяем. Файл собран от этой
// машины, запись цела (lib.recordedProblem), покрытие (transitionCoverage), файл равен своей канонической записи;
// каждый вектор повторяется по ленте на ядре прототипа — по ядру на me (lib.engines), сравнение — lib.compare
// (решение 41). Неиспользованные записи ленты и closeResultLabel [""] — только счёт. Печатает итог, возвращает
// true/false
function checkTransitions(text, env, where) {
  const { lib, tlib, W } = env;
  const fail = (msg) => (console.log(msg), false);
  let data;
  try {
    data = JSON.parse(text);
  } catch (e) {
    return fail(`${where}: правлен руками — не JSON (${e.message}): node tools/cel_vectors.mjs --update`);
  }
  if (data.machineSha256 !== sha256(env.bytes)) return fail(`${where}: машина изменилась после сборки векторов переходов: node tools/cel_vectors.mjs --update`);
  if (data.format !== 1) return fail(`${where}: формат ${data.format}, а этот инструмент знает 1`);
  const problem = tlib.recordedProblem(data);
  if (problem) return fail(`${where}: правлен руками — ${problem}: node tools/cel_vectors.mjs --update`);
  // Покрытие — до сверки с канонической записью: его видно и у файла, правленого руками
  const cover = transitionCoverage(lib, W, data);
  cover.problems.forEach((p) => console.log(p));
  let canon;
  try {
    canon = serializeTransitions(lib, data);
  } catch (e) {
    return fail(`${where}: правлен руками — ${e.message}: node tools/cel_vectors.mjs --update`);
  }
  if (canon !== text) {
    const a = text.split("\n");
    const b = canon.split("\n");
    let i = 0;
    while (i < a.length && a[i] === b[i]) i++;
    return fail(`${where}: правлен руками — файл не равен своей канонической записи (первое отличие — строка ${i + 1}): node tools/cel_vectors.mjs --update`);
  }
  const engineFor = tlib.engines(env.IMEngine.create, W);
  const mismatch = [];
  const missed = [];
  let unused = 0;
  let closeResultLabel = 0;
  data.vectors.forEach((v) => {
    const r = tlib.replay(engineFor, v, data.incidents);
    unused += r.unused;
    closeResultLabel += r.closeResultLabel;
    if (r.misses.length) missed.push(`${v.id} (${[...new Set(r.misses)].join(", ")})`);
    else if (!r.ok) mismatch.push(`${v.id}: ${r.diffs.join(", ")}${r.got.thrown != null ? ` — ${r.got.thrown}` : ""}`);
  });
  const by = (o) => data.vectors.filter((v) => v.op === o).length;
  console.log(`векторов переходов: ${data.vectors.length} (run ${by("run")}, runAll ${by("runAll")}, merge ${by("merge")}, create ${by("create")}), расхождений: ${mismatch.length}, промахов ленты: ${missed.length}, без векторов: ${cover.missing}`);
  console.log(`  синтетика переходов: ${data.vectors.filter((v) => v.case != null).length}`);
  console.log(`  неиспользованных записей ленты: ${unused}; closeResultLabel [""] как "": ${closeResultLabel}`);
  const list = (title, xs) => xs.length && console.log(`${title}:\n  ${xs.slice(0, 30).join("\n  ")}${xs.length > 30 ? `\n  … ещё ${xs.length - 30}` : ""}`);
  list("расхождения переходов", mismatch);
  list("промахи ленты переходов", missed);
  return !mismatch.length && !missed.length && !cover.problems.length;
}

/* ===== Синтетика на границах ===== */

// На исходной машине: значения настроек — в названиях случаев и ожидаемых ответах
function synthetic(env) {
  const { W, IMCel, lib } = env;
  const NOW = lib.NOW;
  const want = { maxActive: null, maxOnHold: 5, reopenWindowMin: 1440, idleHoldSec: 300 };
  const have = { maxActive: W.limits.maxActive, maxOnHold: W.limits.maxOnHold, reopenWindowMin: W.limits.reopenWindowMin, idleHoldSec: W.session.idleHoldSec };
  if (lib.canonical(want) !== lib.canonical(have)) throw new Error(`синтетика написана под настройки ${lib.canonical(want)}, а в машине ${lib.canonical(have)}: поправьте случаи в tools/cel_vectors.mjs`);
  const timerIds = W.timers.map((t) => t.id);
  const ERROR = Symbol("error");
  const ANY = Symbol("any");
  const out = { vectors: [], incidents: {} };
  // Инцидент в ответе — #id, чтобы ждать по-человечески: [#a]
  const shown = (v, pool) => JSON.parse(JSON.stringify(v), (k, x) => (x && typeof x === "object" && typeof x.$ref === "string" && pool[x.$ref] ? `#${pool[x.$ref].id}` : x));

  // Один случай: свой recorder, вычисление, вектор вида kind и имени name (последний — вложенные определения
  // пишутся раньше), сверка с ожидаемым. post — правка вектора после записи (null на входе)
  function add(kind, name, label, run, expected, post) {
    const rec = lib.recorder(IMCel.create, W);
    const cel = rec.create(W);
    try {
      run(cel);
    } catch (e) {
      // Ошибка вычисления — в expect вектора; ждали ли её — ниже
    }
    const { incidents, vectors } = rec.take();
    let v = vectors.filter((x) => x.kind === kind && x.name === name).pop();
    if (!v) throw new Error(`синтетика «${label}»: вектор ${kind}:${name} не записан`);
    // post меняет вход до сверки: свой ответ (expect) он ставит сам — повтором на исполнителе без записи
    if (post) post(v, incidents);
    const got = v.expect && "error" in v.expect ? ERROR : shown(v.expect.value, incidents);
    const ok = expected === ANY ? got !== ERROR : expected === ERROR ? got === ERROR : got !== ERROR && lib.canonical(got) === lib.canonical(expected);
    if (!ok) throw new Error(`синтетика «${label}»: ждали ${expected === ERROR ? "ошибку" : expected === ANY ? "значение" : lib.canonical(expected)}, а ${lib.canonical(v.expect)}`);
    v.case = label;
    v.id = lib.idOf(v);
    if (out.vectors.some((x) => x.id === v.id)) throw new Error(`синтетика «${label}»: тот же вход, что у другого случая (${v.id})`);
    out.vectors.push(v);
    Object.assign(out.incidents, incidents);
  }

  const timers = (over = {}) => Object.fromEntries(timerIds.map((id) => [id, over[id] || {}]));
  // Инцидент-основа: s1, INC-9001, в работе у op1, приоритет 50, все таймеры машины
  const incident = (cel, over = {}) =>
    cel.value("Incident", Object.assign({ id: "s1", number: "INC-9001", state: "in_progress", owner: "op1", priority: 50, occurredAt: NOW - 600000 }, over, { timers: timers(over.timers) }));
  const scopeOf = (x, more) => Object.assign({ me: "op1", actor: "op1", incident: x, incidents: () => [x], form: {}, surface: "card", now: NOW, world: {} }, more);
  const guard = (fn, args, label, raw, expected, more, post) =>
    add("guard", fn, label, (cel) => {
      const x = incident(cel, raw);
      cel.guard(fn, args, scopeOf(x, typeof more === "function" ? more(cel, x) : more), {});
    }, expected, post);
  const definition = (name, label, args, expected, world, post) => add("definition", name, label, (cel) => cel.call(name, args(cel), world || {}), expected, post);
  const fail = (key, vars) => (vars ? { key, vars } : { key });

  // timerExpired: дедлайн наступил (<= now) и ещё не сработал
  const te = "workflow.guard.timer_not_expired";
  [
    ["due = now − 1", { due: NOW - 1 }, null],
    ["due = now", { due: NOW }, null],
    ["due = now + 1", { due: NOW + 1 }, fail(te)],
    ["due = 0 — таймер не идёт", { due: 0 }, fail(te)],
    ["fired = due — дедлайн уже сработал", { due: NOW - 1, fired: NOW - 1 }, fail(te)],
  ].forEach(([what, reaction, expected]) => guard("timerExpired", ["reaction"], `timerExpired ['reaction']: ${what}`, { timers: { reaction } }, expected));
  guard("timerExpired", ["nope"], "timerExpired ['nope']: таймера нет в словаре — ошибка, не «не выполнено» (PROC-44 в3)", {}, ERROR);

  // agentIdleFor: молчание не меньше session.idleHoldSec (300 с)
  [
    [299, fail("workflow.guard.agent_online")],
    [300, null],
  ].forEach(([sec, expected]) => guard("agentIdleFor", ["session.idleHoldSec"], `agentIdleFor ['session.idleHoldSec']: idleSec ${sec} при пороге 300`, {}, expected, { world: { idleSec: () => sec } }));

  // withinHoldLimit: своих отложенных, кроме этого, меньше limits.maxOnHold (5). Сам он тоже отложен — не считается
  [
    [4, null],
    [5, fail("workflow.guard.hold_limit", { n: 5 })],
  ].forEach(([n, expected]) =>
    guard("withinHoldLimit", [], `withinHoldLimit: своих отложенных, кроме этого, ${n} при лимите 5`, { state: "on_hold" }, expected, (cel, x) => {
      const others = Array.from({ length: n }, (_, i) => incident(cel, { id: `h${i + 1}`, number: `INC-91${i + 1}0`, state: "on_hold" }));
      return { incidents: () => [x, ...others] };
    })
  );

  // withinReopenWindow: с закрытия прошло не больше limits.reopenWindowMin (1440 мин = 86 400 000 мс)
  [
    [86400000, null],
    [86400001, fail("workflow.guard.reopen_window", { n: 1440 })],
  ].forEach(([ago, expected]) => guard("withinReopenWindow", [], `withinReopenWindow: now − closedAt = ${ago}`, { state: "closed", closedAt: NOW - ago }, expected));

  // mergePrimary: равные приоритет и время появления — первый по порядку выборки
  // Список — значением CEL (Array из окружения исполнителя: cel-js узнаёт список своего Array)
  const twoNew = (cel, order) => cel.value("list<Incident>", order.map((id) => incident(cel, { id, number: `INC-${id === "a" ? 9101 : 9102}`, state: "new", owner: "", occurredAt: NOW - 1000 })));
  definition("mergePrimary", "определение mergePrimary: два new, равные priority и occurredAt, выборка [a, b] — первый по порядку", (cel) => [twoNew(cel, ["a", "b"]), "op1"], ["#a"]);
  definition("mergePrimary", "определение mergePrimary: два new, равные priority и occurredAt, выборка [b, a] — первый по порядку", (cel) => [twoNew(cel, ["b", "a"]), "op1"], ["#b"]);

  // recipients: порядок — как у members мира
  definition("recipients", "определение recipients: дежурная группа, members → [b, a], оба на месте и с доступом — порядок мира", (cel) => ["g1", incident(cel)], ["b", "a"], {
    isGroup: (id) => id === "g1",
    members: (g) => (g === "g1" ? ["b", "a"] : []),
    agentState: () => "ready",
    access: () => true,
  });

  // leftOf и spent: остаток 0 на паузе и у дедлайна
  [
    ["на паузе с остатком 0", { due: 0, paused: true, left: 0, fired: NOW - 1000 }, 0, true],
    ["due = now", { due: NOW, fired: NOW }, 0, true],
    ["due = now + 1", { due: NOW + 1, fired: NOW + 1 }, 1, false],
  ].forEach(([what, reaction, left, spent]) => {
    // Аргументы определения — значения CEL: int — BigInt
    definition("leftOf", `определение leftOf: ${what}`, (cel) => [incident(cel, { timers: { reaction } }), "reaction", cel.value("int", NOW)], left);
    definition("spent", `определение spent: ${what}, fired = ${reaction.fired === NOW - 1000 ? "прежний дедлайн" : "due"}`, (cel) => [incident(cel, { timers: { reaction } }), "reaction", cel.value("int", NOW)], spent);
  });

  // Пусто на входе: null у полей инцидента и формы — как value(): '' и 0
  const nulls = { owner: null, closedAt: null, holdReasonId: null };
  const formNulls = Object.fromEntries(Object.keys(W.cel.types.Form).filter((k) => !k.startsWith("$")).map((k) => [k, null]));
  // Запись null в вектор: свой инцидент пула с null в полях, форма — null во всех полях
  const nullify = (v, pool) => {
    const swap = new Map();
    const walk = (o) => {
      if (Array.isArray(o)) return o.forEach(walk);
      if (!o || typeof o !== "object") return;
      if (typeof o.$ref === "string") {
        if (!swap.has(o.$ref)) {
          const rec = Object.assign({}, pool[o.$ref], nulls);
          const k = lib.keyOf(rec);
          pool[k] = rec;
          swap.set(o.$ref, k);
        }
        o.$ref = swap.get(o.$ref);
        return;
      }
      Object.values(o).forEach(walk);
    };
    walk(v.args);
    walk(v.scope);
    if (v.scope.form) v.scope.form = formNulls;
  };
  const empty = { owner: "", assignmentGroup: "", closedAt: 0, holdReasonId: "" };
  guard("isOwnerOrUnowned", [], "пусто на входе: isOwnerOrUnowned — null в owner, closedAt, holdReasonId и в полях формы → '' и 0, ничей", empty, null, {}, nullify);
  guard("withinReopenWindow", [], "пусто на входе: withinReopenWindow — null в closedAt → 0, окно прошло", Object.assign({ state: "closed" }, empty), fail("workflow.guard.reopen_window", { n: 1440 }), {}, nullify);
  definition("addressee", "пусто на входе: определение addressee — null в owner → ''", (cel) => [incident(cel, empty)], "", {}, nullify);

  // Имена без векторов в записи тестов API
  [
    [true, null],
    [false, fail("workflow.guard.required_steps")],
  ].forEach(([filled, expected]) =>
    guard("requiredStepsFilled", ["closing"], `requiredStepsFilled ['closing']: stepsFilled ${filled}`, {}, expected, { world: { stepsFilled: (x, set) => set === "closing" && filled } })
  );
  [
    ["due = now + 1", { due: NOW + 1 }, true],
    ["due = now, fired = due", { due: NOW, fired: NOW }, false],
    ["due = 0", { due: 0 }, false],
  ].forEach(([what, reaction, runs]) => definition("timerRuns", `определение timerRuns: ${what}`, (cel) => [incident(cel, { timers: { reaction } }), "reaction"], runs));
  const cel0 = IMCel.create(W);
  cel0
    .ruleNames()
    .filter((n) => n.startsWith("queueSort.keys."))
    .forEach((where) =>
      [
        ["реакция идёт", { reaction: { due: NOW + 60000 } }],
        ["реакция не идёт", {}],
      ].forEach(([what, t]) => add("rule", where, `${where}: ${what}`, (cel) => cel.rule(where, scopeOf(incident(cel, { timers: t })), undefined), ANY))
    );

  // Ошибки вычисления — ошибка сервера, не «не выполнено» и не значение (PROC-44 в3): в каждом виде вычислений.
  // Таймер без ключа у условия — выше (timerExpired ['nope'])
  const effect = (fn, args, label, raw, expected) =>
    add("effect", fn, label, (cel) => {
      const x = incident(cel, raw);
      const list = [x];
      const store = { incidents: () => list, instance: (id) => list.find((i) => i.id === id), touch() {}, world() {} };
      cel.effect(fn, args, { me: "op1", actor: "op1", incident: x, before: incident(cel, raw), form: {}, surface: "card", now: NOW, world: {} }, store);
    }, expected);
  // Переполнение int64: now * now — больше 2^63. cel-js проверяет + - * так же, как cel-go
  effect("restartTimer", ["reaction", "now * now"], "ошибка: restartTimer ['reaction', 'now * now'] — переполнение int64 в выражении аргумента", { timers: { reaction: { due: NOW + 1000 } } }, ERROR);
  effect("pauseTimer", ["nope"], "ошибка: pauseTimer ['nope'] — таймера нет в машине: timerDef('nope') — элемент [0] пустого списка", {}, ERROR);
  // Правило интерфейса и определение: у инцидента нет таймера машины — данные сервера неполные
  const noReaction = () => Object.fromEntries(timerIds.filter((id) => id !== "reaction").map((id) => [id, {}]));
  add("rule", "queueSort.keys.reaction_deadline.0", "ошибка: queueSort.keys.reaction_deadline.0 — в incident.timers нет reaction", (cel) => cel.rule("queueSort.keys.reaction_deadline.0", scopeOf(cel.value("Incident", { id: "s1", number: "INC-9001", state: "in_progress", owner: "op1", priority: 50, timers: noReaction() })), undefined), ERROR);
  definition("timerRuns", "ошибка: определение timerRuns(x, 'nope') — таймера нет в incident.timers", (cel) => [incident(cel), "nope"], ERROR);
  // Тип на входе: строка там, где int. Записать её нельзя (запись кодирует по типу), поэтому вход правится после
  // записи, а ответ — повтор на исполнителе без записи. Дробное число в вектор не попадает вовсе (только целые)
  definition("leftOf", "ошибка: определение leftOf — строка 'abc' в параметре now: int", (cel) => [incident(cel, { timers: { reaction: { due: NOW + 1 } } }), "reaction", cel.value("int", NOW)], ERROR, {}, (v, pool) => {
    v.args[2] = "abc";
    v.expect = lib.replay(IMCel.create(W), v, pool).got;
  });
  // Факт с ref без списка инцидентов: countMine у withinHoldLimit, а scope.incidents нет
  guard("withinHoldLimit", [], "ошибка: withinHoldLimit — факт countMine (ref), а списка инцидентов нет", {}, ERROR, { incidents: undefined });
  return out;
}

/* ===== Синтетика векторов переходов ===== */

// На исходной машине, ожидаемое — запись на ядре прототипа (решение 31): каждый случай — своя запись переходов, кадр —
// запись CEL этого исполнителя (её векторы CEL не берутся). env — свой load(): IMCel.create подменяется. Инциденты —
// с UUID, своим событием и номером INC-%04d (их можно положить в PostgreSQL). Что случай должен показать, проверяет
// shows: не показал — стоп
function syntheticTransitions(env) {
  const { W, lib, tlib } = env;
  const NOW = lib.NOW;
  const SCENARIO = "60000000-0000-4000-8000-000000000002";
  const want = { graceSec: 3, reactionDefaultSec: 300, levels: ["petrova", "noc"], reactionNorm60: "defaultSec" };
  const reaction = W.timers.find((t) => t.id === "reaction");
  // Норматив реакции у инцидента случая «приоритет 60» — определением norm машины (строки overrides по overridesBy,
  // затем byPriority, затем defaultSec): он идёт за defaultSec, только если своего норматива у приоритета 60 нет
  const cel = env.IMCel.create(W);
  const x60 = cel.value("Incident", { eventType: "fire", scenario: SCENARIO, priority: 60 });
  const norm60 = (sec) => Number(cel.call("norm", [x60, cel.value("TimerDef", Object.assign({}, reaction, { defaultSec: sec }))], { inSourceGroup: () => false }));
  const have = {
    graceSec: ((W.invariants || {}).manualWinsOverTimer || {}).graceSec,
    reactionDefaultSec: reaction.defaultSec,
    levels: W.escalation.levels.map((l) => l.target),
    reactionNorm60: norm60(reaction.defaultSec) === reaction.defaultSec && norm60(reaction.defaultSec + 1) === reaction.defaultSec + 1 ? "defaultSec" : `свой, ${norm60(reaction.defaultSec)} с`,
  };
  if (lib.canonical(want) !== lib.canonical(have)) throw new Error(`синтетика переходов написана под настройки ${lib.canonical(want)}, а в машине ${lib.canonical(have)}: поправьте случаи в tools/cel_vectors.mjs`);
  // Запись CEL — до первого IMEngine.create: через неё ядро получает исполнитель, и её кадр видит факты мира
  const celRec = lib.recorder(env.IMCel.create, W);
  env.IMCel.create = celRec.create;
  const out = { vectors: [], incidents: {} };
  const ID = (n) => `10000000-0000-4000-8000-00000000${n}`;
  // Мир: op1 и op2 могут всё; petrova и noc (уровни эскалации) — ничего: эскалировать некому
  const world = {
    can: (who) => who !== "petrova" && who !== "noc",
    access: () => true,
    isOperator: (id) => ["op1", "op2", "petrova", "noc"].includes(id),
    isGroup: () => false,
    members: () => [],
    dutyGroups: () => [],
    inSourceGroup: () => false,
    deviceInGroup: () => false,
    groupDepth: () => 0,
    agentState: () => "ready",
    idleSec: () => 0,
    stepsFilled: () => true,
    lastTransferTarget: () => "",
    transferTargets: () => ["op2"],
  };
  // Инцидент n (9001…): своё событие, сценарий «Пожар», приоритет 50, все таймеры машины
  const plain = (n, over = {}) =>
    Object.assign({ id: ID(n), number: `INC-${n}`, eventGuid: `70000000-0000-4000-8000-00000000${n}`, eventType: "fire", scenario: SCENARIO, priority: 50, occurredAt: NOW - 600000, state: "new", owner: "" }, over, {
      timers: Object.fromEntries(W.timers.map((t) => [t.id, Object.assign({}, (over.timers || {})[t.id])])),
    });

  // Один случай: своя запись, вызов call(engine, events, mk), один вектор; shows(v, pool) — что не так ([] — всё так)
  function add(label, call, shows) {
    const rec = tlib.recorder(env.IMEngine.create, W, celRec.frame);
    const events = [];
    const engine = rec.create({
      workflow: W,
      me: "op1",
      now: () => NOW,
      events: () => events,
      scenarioKey: (ev) => ev.scenarioGuid,
      world,
      log: (ev, who, k, v, at) => ev.log.push({ at, whoId: who, k, v: v || null }),
      actorName: (id) => (id ? `name:${id}` : ["workflow.label.unassigned"]),
      progress: () => ({ filled: 0, total: 2 }),
      stepNumber: () => 1,
      transferTargets: () => world.transferTargets().map((id) => ({ id })),
      setCursor() {},
      shareAnswers: () => 0,
      deliver() {},
      onEvict() {},
      onBreachShared() {},
    });
    const mk = (n, over) => engine.fromView(plain(n, over), { log: [] });
    call(engine, events, mk);
    const taken = rec.take();
    const skipped = Object.entries(taken.skipped).filter(([, x]) => x);
    if (skipped.length || taken.vectors.length !== 1) throw new Error(`синтетика переходов «${label}»: векторов ${taken.vectors.length}, skipped ${lib.canonical(taken.skipped)}`);
    const [v] = taken.vectors;
    const problems = shows(v, taken.incidents);
    if (problems.length) throw new Error(`синтетика переходов «${label}»: ${problems.join("; ")}; а записано ${lib.canonical(v.expect).slice(0, 600)}`);
    if (out.vectors.some((x) => x.id === v.id || x.case === label)) throw new Error(`синтетика переходов «${label}»: тот же вход или то же название, что у другого случая (${v.id})`);
    v.case = label;
    out.vectors.push(v);
    Object.assign(out.incidents, taken.incidents);
  }

  // Проверки ожидаемого: каждая — текст, если не так
  const ok = (v) => (v.expect.ok ? [] : ["ждали ok"]);
  const canceled = (v, id, tr) => {
    const c = (v.expect.ok || {}).canceled;
    const got = c ? c[id] : undefined;
    return got === tr ? [] : [`ждали canceled ${tr || "нет"}, а ${got || "нет"}`];
  };
  const keys = (v, id) => (((v.expect.ok || {}).journal || {})[id] || []).map((e) => e.templateKey);
  const after = (v, pool, id) => {
    const d = ((v.expect.ok || {}).incidents || {})[id];
    return d ? pool[d.$ref] : null;
  };
  const refusal = (v, fields) => {
    const r = v.expect.refusal;
    if (!r) return ["ждали отказ"];
    return Object.entries(fields)
      .filter(([k, x]) => lib.canonical(k === "key" ? r.why[0] : k === "name" ? (r.why[1] || {}).name : r[k]) !== lib.canonical(x))
      .map(([k, x]) => `ждали ${k} ${lib.canonical(x)}`);
  };
  const OVERRIDDEN = "workflow.journal.timer_overridden";
  const id1 = ID(9001);

  // Окно после дедлайна (graceSec 3 с): дедлайн реакции в new, переход по таймеру — escalation_ceiling (эскалировать некому)
  add("«Взять» в окне после дедлайна: reaction.due = now − 2999 — срабатывание escalation_ceiling отменено, нарушение reaction на момент дедлайна, журнал [timer_overridden, claim]", (engine, events, mk) => {
    events.push(mk(9001, { timers: { reaction: { due: NOW - 2999 } } }), mk(9002));
    engine.run("claim", events[0], {}, { surface: "card" });
  }, (v, pool) => {
    const x = after(v, pool, id1);
    const breach = x && x.breaches.find((b) => b.kind === "reaction");
    return ok(v).concat(
      canceled(v, id1, "escalation_ceiling"),
      breach && breach.at === NOW - 2999 ? [] : [`ждали нарушение reaction на ${NOW - 2999}`],
      ((v.expect.ok || {}).facts || {})[id1] && v.expect.ok.facts[id1].breach === "reaction" ? [] : ["ждали facts.breach reaction"],
      lib.canonical(keys(v, id1)) === lib.canonical([OVERRIDDEN, "workflow.journal.claim"]) ? [] : [`ждали журнал [timer_overridden, claim], а ${lib.canonical(keys(v, id1))}`]
    );
  });
  add("«Взять» на конце окна: reaction.due = now − 3000 — окно кончилось, отмены и нарушения нет", (engine, events, mk) => {
    events.push(mk(9001, { timers: { reaction: { due: NOW - 3000 } } }), mk(9002));
    engine.run("claim", events[0], {}, { surface: "card" });
  }, (v, pool) => {
    const x = after(v, pool, id1);
    return ok(v).concat(
      canceled(v, id1, undefined),
      x && !x.breaches.length ? [] : ["ждали без нарушений"],
      keys(v, id1).includes(OVERRIDDEN) ? ["timer_overridden в журнале"] : []
    );
  });
  add("«Передать» op2 в окне: reaction.due = now − 1000 — реакция продолжается (continuesOn), срабатывание не отменено", (engine, events, mk) => {
    events.push(mk(9001, { timers: { reaction: { due: NOW - 1000 } } }), mk(9002));
    engine.run("transfer", events[0], { targetId: "op2", comment: "передаю" }, { surface: "card" });
  }, (v) => ok(v).concat(canceled(v, id1, undefined), keys(v, id1).includes(OVERRIDDEN) ? ["timer_overridden в журнале"] : []));

  // Форма
  add("«Отложить» с чужой причиной: reasonId «nope» — значение недопустимо", (engine, events, mk) => {
    events.push(mk(9001, { state: "in_progress", owner: "op1" }), mk(9002));
    engine.run("hold", events[0], { reasonId: "nope" }, { surface: "card" });
  }, (v) => refusal(v, { key: "workflow.error.field_invalid", code: "FORM_FIELD_INVALID", name: ["workflow.form.hold.field.reasonId"] }));
  add("«Закрыть» без результата: форма {} — поле результата обязательно", (engine, events, mk) => {
    events.push(mk(9001, { state: "in_progress", owner: "op1" }), mk(9002));
    engine.run("close", events[0], {}, { surface: "card" });
  }, (v) => refusal(v, { key: "workflow.error.field_required", name: ["workflow.form.close.field.resultId"] }));
  add("«Закрыть» «Массовый сбой» без причины: resultId mass — поле причины обязательно", (engine, events, mk) => {
    events.push(mk(9001, { state: "in_progress", owner: "op1" }), mk(9002));
    engine.run("close", events[0], { resultId: "mass" }, { surface: "card" });
  }, (v) => refusal(v, { key: "workflow.error.field_required", name: ["workflow.form.close.field.causeId"] }));

  // «Отсоединить все»: первый привязан к основному 9003 (в работе у op1 — primaryEditable), второй не привязан
  add("«Отсоединить все»: [9001 привязан к 9003, 9002 new] — второй не в linked, отказ называет его", (engine, events, mk) => {
    events.push(mk(9001, { state: "linked", linkedTo: ID(9003), linkedAt: NOW - 60000 }), mk(9002), mk(9003, { state: "in_progress", owner: "op1" }));
    engine.runAll("detach", [events[0], events[1]], {}, { surface: "card" });
  }, (v) => refusal(v, { notFrom: true, id: ID(9002) }));

  // Норматив при появлении: у приоритета 60 своего норматива нет (reactionNorm60 выше) — defaultSec реакции (300 с)
  add("Появление с приоритетом 60 без своего норматива — реакция defaultSec: due = now + 300000", (engine, events, mk) => {
    events.push(mk(9002));
    engine.create(mk(9001, { state: "", priority: 60 }));
  }, (v, pool) => {
    const x = after(v, pool, id1);
    return ok(v).concat(x && x.timers.reaction.due === NOW + 300000 ? [] : [`ждали reaction.due ${NOW + 300000}, а ${x && x.timers.reaction.due}`]);
  });
  return out;
}

/* ===== Запись в Chrome ===== */

const unescape = (s) => s.replace(/&(amp|lt|gt|quot|#39|nbsp);/g, (_, e) => ({ amp: "&", lt: "<", gt: ">", quot: '"', "#39": "'", nbsp: " " })[e]);

// Профиль Chrome — во временной папке (--tmp=папка или системная). TMPDIR самому Chrome не подменять: в длинном
// пути его сокет SingletonSocket не помещается, и Chrome падает
function record(tmpRoot) {
  const tmp = fs.mkdtempSync(path.join(tmpRoot || os.tmpdir(), "cel-vectors-"));
  try {
    const url = `${pathToFileURL(path.join(ROOT, "tests/api.html")).href}?celVectors=1`;
    const chrome = process.env.CHROME || "google-chrome";
    const args = ["--headless=new", "--disable-gpu", "--no-first-run", `--user-data-dir=${path.join(tmp, "profile")}`, `--virtual-time-budget=${VIRTUAL_BUDGET_MS}`, "--dump-dom", url];
    const r = spawnSync(chrome, args, { encoding: "utf8", maxBuffer: 1 << 30, timeout: WALL_TIMEOUT_MS, killSignal: "SIGKILL" });
    if (r.error) throw new Error(r.error.code === "ETIMEDOUT" ? `Chrome не уложился в ${WALL_TIMEOUT_MS / 60000} мин` : `Chrome: ${r.error.message}`);
    if (r.status !== 0) throw new Error(`Chrome — код ${r.status}: ${String(r.stderr).slice(-500)}`);
    const dom = r.stdout;
    const result = (/<html[^>]*\sdata-apitest="(\w+)"/.exec(dom) || [])[1];
    const summary = (/id="apitest-summary"[^>]*>([^<]*)</.exec(dom) || [])[1];
    if (result !== "pass") {
      const first = (/data-apitest-first-failed="([^"]*)"/.exec(dom) || [])[1];
      throw new Error(`тесты API — ${result || "не закончились"}${summary ? `: ${unescape(summary)}` : ""}${first ? `; первый упавший — ${unescape(first)}` : ""}. Файл не записан`);
    }
    const pre = /<pre id="celvectors-out"([^>]*)>([\s\S]*?)<\/pre>/.exec(dom);
    if (!pre || !pre[2]) throw new Error("в странице нет записи векторов (celvectors-out пустой)");
    const stats = JSON.parse(unescape((/data-stats="([^"]*)"/.exec(pre[1]) || [, "null"])[1]));
    if (!stats || stats.tapeRepeat == null) throw new Error("в записи нет счётчиков (data-stats)");
    const tpre = /<pre id="transitionvectors-out"[^>]*>([\s\S]*?)<\/pre>/.exec(dom);
    if (!tpre || !tpre[1]) throw new Error("в странице нет записи переходов (transitionvectors-out пустой)");
    return { summary: unescape(summary || ""), stats, data: JSON.parse(unescape(pre[2])), transitions: JSON.parse(unescape(tpre[1])) };
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
  }
}

/* ===== Запуск ===== */

const argv = process.argv.slice(2);
const opt = (name) => (argv.find((a) => a.startsWith(`--${name}=`)) || "").slice(name.length + 3) || null;
const file = path.resolve(opt("file") || FILE);
const machinePath = path.resolve(opt("machine") || MACHINE);
const transitionsFile = path.resolve(opt("transitions") || TRANSITIONS_FILE);
const rel = (p) => (path.relative(ROOT, p).startsWith("..") ? p : path.relative(ROOT, p));

if (argv.includes("--update")) {
  const t0 = Date.now();
  let ok = false;
  try {
    const env = load(machinePath);
    // Синтетика — первой: она быстрая, и её ошибка видна до шести минут записи
    const synth = synthetic(env);
    console.log(`синтетика: ${synth.vectors.length} векторов`);
    // Синтетика переходов — на своём исполнителе (подменяет IMCel.create)
    const trSynth = syntheticTransitions(load(machinePath));
    console.log(`синтетика переходов: ${trSynth.vectors.length} векторов`);
    console.log(`запись: Chrome на tests/api.html?celVectors=1 (около 6 мин, предел ${WALL_TIMEOUT_MS / 60000} мин)…`);
    const rec = record(opt("tmp") && path.resolve(opt("tmp")));
    console.log(`  тесты API — ${rec.summary}; записано векторов ${rec.data.vectors.length}, ${((Date.now() - t0) / 1000).toFixed(0)} с`);
    const ids = new Set(synth.vectors.map((v) => v.id));
    // Отбор — только записанного; вход синтетики, совпавший с записанным, остаётся синтетикой (с названием случая)
    const chosen = env.lib.select(rec.data.vectors).filter((v) => !ids.has(v.id));
    const text = serialize(env.lib, {
      incidents: Object.assign({}, rec.data.incidents, synth.incidents),
      vectors: chosen.concat(synth.vectors),
      machineSha256: sha256(env.bytes),
      skipped: { tapeRepeat: rec.stats.tapeRepeat, worldError: rec.stats.skipped },
    });
    // Переходы — тоже до записи: стоп любого из двух файлов не оставляет записанным ни один
    const trText = transitionsText(env, rec.transitions, trSynth, sha256(env.bytes));
    // Всё, что делает --check, — на свежем исполнителе и ядре, до записи: расхождение или промах в любом — стоп
    const okCel = check(text, load(machinePath), rel(file));
    const okTransitions = checkTransitions(trText, load(machinePath), rel(transitionsFile));
    ok = okCel && okTransitions;
    if (ok) {
      fs.mkdirSync(path.dirname(file), { recursive: true });
      fs.mkdirSync(path.dirname(transitionsFile), { recursive: true });
      fs.writeFileSync(file, text);
      fs.writeFileSync(transitionsFile, trText);
      console.log(`записано ${rel(transitionsFile)}: из записи ${rec.transitions.vectors.length}, синтетика ${trSynth.vectors.length}, ${(Buffer.byteLength(trText, "utf8") / 1048576).toFixed(2)} МБ`);
      console.log(`записано ${rel(file)}: отобрано из записи ${chosen.length}, синтетика ${synth.vectors.length}; всего ${((Date.now() - t0) / 1000).toFixed(0)} с`);
    } else console.log("файлы не записаны");
  } catch (e) {
    console.log(`cel_vectors --update: ${e.message}`);
  }
  process.exitCode = ok ? 0 : 1;
} else if (argv.includes("--check")) {
  let okCel = false;
  let okTransitions = false;
  if (!fs.existsSync(file)) console.log("нет файла, соберите: node tools/cel_vectors.mjs --update");
  else okCel = check(fs.readFileSync(file, "utf8"), load(machinePath), rel(file));
  if (!fs.existsSync(transitionsFile)) console.log("нет файла векторов переходов, соберите: node tools/cel_vectors.mjs --update");
  else okTransitions = checkTransitions(fs.readFileSync(transitionsFile, "utf8"), load(machinePath), rel(transitionsFile));
  process.exitCode = okCel && okTransitions ? 0 : 1;
} else {
  console.log("node tools/cel_vectors.mjs --update | --check [--file=путь] [--transitions=путь] [--machine=путь] [--tmp=папка]");
  process.exitCode = 1;
}
