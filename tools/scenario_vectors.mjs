// Векторы сценариев для бэкенда (решение 195 плана этапа 6): файл Specification/Workflow_machine/fixtures/scenario-vectors.json —
// «сценарий + прохождение + вызов → ответ» исполнителя сценариев прототипа (prototype/scenario.js). Сервер повторяет каждый
// вектор своим исполнителем (пакет scenariomachine) и сверяет ответ. Сценарии на сервер попадают пулом scripts этого
// файла, отдельно не вендорятся.
//
//   node tools/scenario_vectors.mjs --update   — собрать и записать файл. Сначала проверка покрытия: нет причины отказа
//                                                или типа шага — стоп с перечнем, файл не пишется
//   node tools/scenario_vectors.mjs --check    — собрать заново в памяти и сравнить с файлом побайтно; тихо, код 0,
//                                                если равны; иначе — первое расхождение, код 1
//   --scenario=путь — копия prototype/scenario.js для проб порчи (только с --check): порченый исполнитель не должен
//                     записать эталон, а --check на нём обязан отказать
//
// timeZone: "UTC" — границы Datetime min и max без часового пояса (в 00-primitives) читаются как UTC; сервер читает так же.
// Формат 1: { format, timeZone, scripts: { <sha16>: сценарий }, counts: { answer, share }, vectors: […] }.
// Вектор answer: { id, op: "answer", script, result, call: { stepId, value, skip, attachments, at, by },
//                  expect: { ok: { result, macros, warnings } } | { error }, views }.
// Вектор share:  { id, op: "share", from, to, result (прохождение основного до переноса), call: { fromResult, at },
//                  expect: { ok: { result, moved } }, views }.
// views — что исполнитель говорит о прохождении после вызова (при отказе — о неизменном): path, ahead, cursor,
// progress, stepsFilled { closing, none }.
// Прогоны детерминированы: ГПСЧ с зерном 1, at от 2026-11-02T10:00:00.000Z шагом 1 с, by — op-1.
// Код выхода — 0 или 1.
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

// Границы Datetime в сценариях бывают без часового пояса (Date.parse читает их как местное время): часовой пояс
// фиксируем, чтобы файл не зависел от машины
process.env.TZ = "UTC";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const FILE = path.join(ROOT, "Specification/Workflow_machine/fixtures/scenario-vectors.json");
const SCENARIO_JS = path.join(ROOT, "prototype/scenario.js");
const LOGIC_JS = path.join(ROOT, "prototype/vendor/json-logic-js/logic.js");
const SCRIPT_DIRS = ["Specification/Workflow_machine/fixtures/scenarios", "Specification/Scenario_machine/examples", "Specification/Scenario_machine/examples/showcase"];
const MAX_BYTES = 8 * 1024 * 1024; // файл 5,78 МБ: запас 38%
const RUNS = 20; // прогонов по зерну на сценарий
const RUN_CAP = 6; // вызовов в одном прогоне, не больше
const SHARE_SELF = 4; // перенос между прохождениями одной версии
const SHARE_PAIR = 8; // перенос между разными версиями одного сценария
const T0 = Date.parse("2026-11-02T10:00:00.000Z");
const BY = "op-1";
const REASONS = ["unknown_step", "not_on_path", "not_editable", "required", "option", "count", "type", "length", "format", "range", "readonly", "attachments"];
const TYPES = ["RadioButton", "Checkbox", "Select", "Comment", "Datetime", "Image", "Message"];

const clone = (x) => JSON.parse(JSON.stringify(x));
const sha16 = (script) => crypto.createHash("sha256").update(JSON.stringify(script)).digest("hex").slice(0, 16);

// Исполнитель — из prototype/scenario.js через vm, с JSONLogic, как в браузере
function executor(scenarioPath) {
  const g = { console };
  g.window = g;
  vm.createContext(g);
  vm.runInContext(fs.readFileSync(LOGIC_JS, "utf8"), g, { filename: "logic.js" });
  vm.runInContext(fs.readFileSync(scenarioPath, "utf8"), g, { filename: "scenario.js" });
  return g.IMScenario;
}

// Сценарии: эталонный набор и примеры машины сценариев (без отрицательных — их отвергает проверка сценариев) и пара
// версий, где у шага тот же id, но другой тип (перенос без сверки типа его бы перенёс)
function loadScripts() {
  const out = [];
  for (const d of SCRIPT_DIRS) {
    const dir = path.join(ROOT, d);
    for (const f of fs.readdirSync(dir).filter((x) => x.endsWith(".json")).sort()) out.push({ name: f.replace(/\.json$/, ""), script: JSON.parse(fs.readFileSync(path.join(dir, f), "utf8")) });
  }
  const base = out.find((x) => x.name === "01-perimeter-alarm");
  const v2 = clone(base.script);
  v2.scenario.version = 2;
  const note = v2.steps.find((s) => s.id === "operator_note");
  note.type = "RadioButton";
  note.view = { label: "Заметка", required: false, options: [{ id: "note", label: "Заметка", default: false }, { id: "none", label: "Нет", default: false }] };
  out.push({ name: "01-perimeter-alarm.type-changed", script: v2 });
  // Переход «остаёмся на шаге» (goto на себя) и на несуществующий шаг: в сценариях набора их нет, а ответ тогда
  // оставляет курсор на отвеченном шаге — предупреждение, «N из M» с учётом этого ответа
  const step = (id, type, view, transitions, finish) => ({ id, type, title: id, description: "", revisitable: true, multitasking: false, report: false, finish, view, transitions });
  const go = (goto) => ({ goto, macro: null });
  out.push({
    name: "synthetic.stay",
    script: {
      scenario: { id: "60000000-0000-4000-8000-0000000000f1", name: "Остаться на шаге", description: "", version: 1, createdAt: "2026-09-01T09:00:00Z", updatedAt: "2026-09-01T09:00:00Z", initialStep: "pick" },
      steps: [
        step("pick", "RadioButton", { label: "Выбор", required: true, default: null, options: [{ id: "stay", label: "Остаться" }, { id: "ghost", label: "Несуществующий" }, { id: "on", label: "Дальше" }] }, {
          rules: [{ condition: { "==": [{ var: "value" }, "stay"] }, goto: "pick", macro: null }, { condition: { "==": [{ var: "value" }, "ghost"] }, goto: "nowhere", macro: null }],
          default: go("end"),
        }, false),
        step("end", "Message", { label: "Готово" }, { default: go(null) }, true),
      ],
    },
  });
  // Пара версий для переноса ответов (guid f2): у шага s2 меняется тип, а значение "x" верно в обоих типах
  // (Comment — строка, RadioButton — вариант "x"); у шага s1 во второй версии нет варианта "c". Без них перенос
  // без сверки типа и без проверки значения в сценарии основного остался бы незамеченным
  const shareScenario = (version, s1, s2) => ({
    scenario: { id: "60000000-0000-4000-8000-0000000000f2", name: "Перенос", description: "", version, createdAt: "2026-09-01T09:00:00Z", updatedAt: "2026-09-01T09:00:00Z", initialStep: "s1" },
    steps: [step("s1", "RadioButton", s1, { default: go("s2") }, false), step("s2", s2.type, s2.view, { default: go("s3") }, false), step("s3", "Message", { label: "Готово" }, { default: go(null) }, true)],
  });
  const opts = (...ids) => ids.map((id) => ({ id, label: id }));
  const radio = (...ids) => ({ label: "Выбор", required: true, default: null, options: opts(...ids) });
  out.push({ name: "synthetic.share-a", script: shareScenario(1, radio("a", "b", "c"), { type: "Comment", view: { label: "Текст", default: "", required: false, readonly: false, minLength: 0, maxLength: 100 } }) });
  out.push({ name: "synthetic.share-b", script: shareScenario(2, radio("a", "b"), { type: "RadioButton", view: radio("x", "y") }) });
  return out;
}

/* ===== ГПСЧ ===== */

function mulberry32(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/* ===== Значения ответов ===== */

function makeGen(rng) {
  const int = (lo, hi) => lo + Math.floor(rng() * (hi - lo + 1));
  const pick = (xs) => xs[Math.floor(rng() * xs.length)];
  const shuffle = (xs) => {
    const a = xs.slice();
    for (let i = a.length - 1; i > 0; i--) {
      const j = int(0, i);
      [a[i], a[j]] = [a[j], a[i]];
    }
    return a;
  };
  const text = (n) => Array.from({ length: n }, (_, i) => (i % 7 === 6 ? " " : "abcdefghij"[int(0, 9)])).join("").replace(/^ | $/g, "x");
  const iso = (ms, style) => {
    const s = new Date(ms).toISOString(); // 2026-..T..:..:..sssZ
    if (style === 0) return s.replace(/\.\d+Z$/, "Z");
    if (style === 1) return s;
    if (style === 2) return s.replace(/:\d\d\.\d+Z$/, "Z");
    const shifted = new Date(ms + 3 * 3600 * 1000).toISOString().replace(/\.\d+Z$/, "+03:00");
    return shifted;
  };
  let n = 0;

  // Верный ответ на шаг: { value, attachments }
  function valid(step) {
    const v = step.view;
    switch (step.type) {
      case "RadioButton":
        return { value: pick(v.options).id, attachments: [] };
      case "Checkbox": {
        const max = v.maxSelected != null ? Math.min(v.maxSelected, v.options.length) : v.options.length;
        return { value: shuffle(v.options.map((o) => o.id)).slice(0, int(v.minSelected, max)), attachments: [] };
      }
      case "Select": {
        const value = {};
        for (const l of v.lists) {
          const ids = shuffle(l.options.map((o) => o.id));
          const k = ids.length === 0 ? 0 : v.required ? int(1, Math.min(2, ids.length)) : int(0, Math.min(2, ids.length));
          if (k > 0 || rng() < 0.7) value[l.id] = ids.slice(0, k);
        }
        return { value, attachments: [] };
      }
      case "Comment": {
        if (v.readonly) return { value: pick([null, ""]), attachments: [] };
        const lo = Math.max(v.minLength || 0, v.required ? 1 : 0);
        const hi = Math.min(v.maxLength != null ? v.maxLength : lo + 20, lo + 20);
        return { value: text(int(lo, Math.max(lo, hi))), attachments: [] };
      }
      case "Datetime": {
        const lo = v.min ? Date.parse(v.min) : Date.parse("2026-01-01T00:00:00Z");
        const hi = v.max ? Date.parse(v.max) : Date.parse("2026-12-31T23:59:59Z");
        return { value: iso(lo + Math.floor(rng() * (hi - lo + 1)), int(0, 3)), attachments: [] };
      }
      case "Image": {
        const att = { id: `img-${step.id}-${++n}`, stepId: step.id, name: "photo.jpg", mime: "image/jpeg", size: int(1, 99999) };
        return { value: att.id, attachments: [att] };
      }
      default:
        return { value: null, attachments: [] };
    }
  }

  // Неверные ответы на шаг: [{ value, attachments }] — исполнитель отвечает на них отказом (причину ставит он, не мы)
  function invalid(step) {
    const v = step.view;
    const out = [];
    const bad = (value, attachments) => out.push({ value, attachments: attachments || [] });
    switch (step.type) {
      case "RadioButton":
        bad("no-such-option");
        bad(7);
        bad(null);
        break;
      case "Checkbox": {
        const ids = v.options.map((o) => o.id);
        bad(["no-such-option"]);
        bad("not-a-list");
        if (ids.length) bad([ids[0], ids[0]]);
        if (v.minSelected > 0) bad([]);
        if (v.maxSelected != null && v.maxSelected < ids.length) bad(ids.slice(0, v.maxSelected + 1));
        break;
      }
      case "Select": {
        bad("not-an-object");
        bad([]);
        bad({ "no-such-list": [] });
        bad(Object.fromEntries(v.lists.map((l) => [l.id, ["no-such-option"]])));
        if (v.lists[0].options.length) bad({ [v.lists[0].id]: [v.lists[0].options[0].id, v.lists[0].options[0].id] });
        if (v.required) bad({});
        break;
      }
      case "Comment":
        if (v.readonly) {
          bad("text for a read-only step");
          break;
        }
        bad(42);
        bad(null);
        if (v.required) bad("   ");
        if (v.minLength > 0) bad("a".repeat(v.minLength - 1));
        if (v.maxLength != null) bad("a".repeat(v.maxLength + 1));
        break;
      case "Datetime":
        bad("tomorrow");
        bad("2026-11-02T10:00:00"); // без часового пояса
        bad(12345);
        bad("2026-13-45T10:00:00Z");
        if (v.min) bad(new Date(Date.parse(v.min) - 1000).toISOString());
        if (v.max) bad(new Date(Date.parse(v.max) + 1000).toISOString());
        if (v.min) bad(new Date(Date.parse(v.min) - 1).toISOString());
        if (v.max) bad(new Date(Date.parse(v.max) + 1).toISOString());
        break;
      case "Image":
        bad(7);
        bad("img-missing", []); // вложения нет
        bad("img-other", [{ id: "img-other", stepId: "some-other-step", name: "a.jpg", mime: "image/jpeg", size: 1 }]); // чужое вложение
        break;
      default:
        break;
    }
    return out;
  }
  return { int, pick, shuffle, valid, invalid, rng };
}

/* ===== Сборка ===== */

function build(S, loaded) {
  const rng = mulberry32(1);
  const gen = makeGen(rng);
  const pool = {};
  const keyOf = new Map(); // name → sha16
  for (const { name, script } of loaded) {
    const key = sha16(script);
    pool[key] = script;
    keyOf.set(name, key);
  }
  let tick = 0;
  const nextAt = () => new Date(T0 + 1000 * tick++).toISOString();
  const vectors = [];
  const counts = { answer: 0, share: 0 };
  const stepOf = (script, id) => script.steps.find((s) => s.id === id);

  const viewsOf = (script, result) => ({
    path: S.path(script, result),
    ahead: S.ahead(script, result),
    cursor: S.cursor(script, result),
    progress: S.progress(script, result),
    stepsFilled: { closing: S.stepsFilled(script, result, "closing"), none: S.stepsFilled(script, result, "none") },
  });

  // Один вызов answer: записать вектор, вернуть новое прохождение (или то же при отказе)
  function answer(name, run, no, script, result, stepId, value, skip, attachments) {
    const call = { stepId, value: skip ? null : value, skip, attachments, at: nextAt(), by: BY };
    const before = clone(result);
    const r = S.answer(script, result, stepId, call.value, { at: call.at, by: BY, skip, attachments });
    const expect = r.ok ? { ok: { result: r.result, macros: r.effects, warnings: r.warnings } } : { error: r.error };
    vectors.push({
      id: `answer/${name}/${run}.${no}`,
      op: "answer",
      script: keyOf.get(name),
      result: before,
      call,
      expect,
      views: viewsOf(script, r.ok ? r.result : before),
    });
    counts.answer++;
    return r.ok ? r.result : result;
  }

  // Прогон по сценарию: на каждом шаге случайно — верный ответ, неверный, пропуск, переответ пройденного, ответ
  // шага вне пути, неизвестный шаг. Прогон кончается после завершения (ещё до трёх вызовов) или по пределу
  function oneRun(name, script, run) {
    let result = S.start(script);
    let extra = 3;
    for (let no = 0; no < RUN_CAP; no++) {
      if (result.completedAt && extra-- <= 0) break;
      const p = S.path(script, result);
      const cur = stepOf(script, S.cursor(script, result));
      const roll = rng();
      const stepIds = script.steps.map((s) => s.id);
      const offPath = stepIds.filter((id) => !p.includes(id));
      const visited = p.filter((id) => id !== result.currentStepId || result.completedAt);
      if (roll < 0.4 && !result.completedAt) {
        const a = gen.valid(cur);
        result = answer(name, run, no, script, result, cur.id, a.value, false, a.attachments);
      } else if (roll < 0.55) {
        const target = !result.completedAt && rng() < 0.8 ? cur : stepOf(script, gen.pick(p));
        const bads = gen.invalid(target);
        if (bads.length) {
          const a = gen.pick(bads);
          result = answer(name, run, no, script, result, target.id, a.value, false, a.attachments);
        } else result = answer(name, run, no, script, result, target.id, null, true, []);
      } else if (roll < 0.65 && !result.completedAt) {
        result = answer(name, run, no, script, result, cur.id, null, true, []);
      } else if (roll < 0.8 && visited.length) {
        const target = stepOf(script, gen.pick(visited));
        const skip = rng() < 0.15;
        const a = gen.valid(target);
        result = answer(name, run, no, script, result, target.id, a.value, skip, a.attachments);
      } else if (roll < 0.88 && offPath.length) {
        const target = stepOf(script, gen.pick(offPath));
        const a = gen.valid(target);
        result = answer(name, run, no, script, result, target.id, a.value, false, a.attachments);
      } else if (roll < 0.92) {
        result = answer(name, run, no, script, result, "no-such-step", "x", false, []);
      } else if (!result.completedAt) {
        const a = gen.valid(cur);
        result = answer(name, run, no, script, result, cur.id, a.value, false, a.attachments);
      }
    }
  }

  // Прохождение, продвинутое верными ответами (часть — пропуски) на случайную глубину
  function advanced(script, depth) {
    let result = S.start(script);
    for (let i = 0; i < depth && !result.completedAt; i++) {
      const cur = stepOf(script, S.cursor(script, result));
      const skip = S.canSkip(cur) && gen.rng() < 0.2;
      const a = gen.valid(cur);
      const r = S.answer(script, result, cur.id, skip ? null : a.value, { at: nextAt(), by: BY, skip, attachments: a.attachments });
      if (!r.ok) break;
      result = r.result;
    }
    return result;
  }

  function oneShare(fromName, toName, no) {
    const from = pool[keyOf.get(fromName)];
    const to = pool[keyOf.get(toName)];
    pushShare(`${fromName}>${toName}/${no}`, fromName, toName, advanced(from, gen.int(0, from.steps.length + 1)), advanced(to, gen.int(0, 2)));
  }

  // Заданные ответы: прохождение сценария from верными ответами [шаг, значение] подряд (отказ — ошибка генератора)
  function answered(script, pairs) {
    let result = S.start(script);
    for (const [id, value] of pairs) {
      const r = S.answer(script, result, id, value, { at: nextAt(), by: BY });
      if (!r.ok) throw new Error(`${script.scenario.id}: ответ ${id} отклонён (${r.error})`);
      result = r.result;
    }
    return result;
  }

  function pushShare(id, fromName, toName, fromResult, result) {
    const from = pool[keyOf.get(fromName)];
    const to = pool[keyOf.get(toName)];
    const call = { fromResult, at: nextAt() };
    const r = S.share(from, clone(fromResult), to, clone(result), { at: call.at });
    vectors.push({
      id: `share/${id}`,
      op: "share",
      from: keyOf.get(fromName),
      to: keyOf.get(toName),
      result: clone(result),
      call,
      expect: { ok: { result: r.result, moved: r.moved } },
      views: viewsOf(to, r.result),
    });
    counts.share++;
  }

  // Обход: один прогон верными ответами, на каждом шаге пути — все неверные ответы подряд (результат при отказе не
  // меняется): каждая причина отказа берётся и там, куда случайный прогон за RUN_CAP вызовов не доходит
  function probe(name, script) {
    let result = S.start(script);
    for (let no = 0; no < script.steps.length * 2 && !result.completedAt; no++) {
      const cur = stepOf(script, S.cursor(script, result));
      const bads = gen.invalid(cur);
      bads.forEach((b, k) => answer(name, "probe", `${no}.${k}`, script, result, cur.id, b.value, false, b.attachments));
      if (cur.type === "Message" || !S.canSkip(cur)) answer(name, "probe", `${no}.skip`, script, result, cur.id, null, true, []);
      // Границы диапазона Datetime: значение ровно на min и на max верно (результат не берём — идём дальше верным)
      if (cur.type === "Datetime") {
        if (cur.view.min) answer(name, "probe", `${no}.min`, script, result, cur.id, new Date(Date.parse(cur.view.min)).toISOString(), false, []);
        if (cur.view.max) answer(name, "probe", `${no}.max`, script, result, cur.id, new Date(Date.parse(cur.view.max)).toISOString(), false, []);
      }
      const a = gen.valid(cur);
      const next = answer(name, "probe", `${no}.ok`, script, result, cur.id, a.value, false, a.attachments);
      if (next === result) break;
      result = next;
    }
  }

  for (const { name, script } of loaded) {
    for (let run = 0; run < RUNS; run++) oneRun(name, script, run);
    probe(name, script);
  }

  // Перенос — между прохождениями сценариев одного guid (scenario.id): одной версии и разных версий
  const byGuid = new Map();
  for (const l of loaded) {
    if (!byGuid.has(l.script.scenario.id)) byGuid.set(l.script.scenario.id, []);
    byGuid.get(l.script.scenario.id).push(l);
  }
  for (const group of byGuid.values()) {
    for (const a of group) for (const b of group) for (let no = 0; no < (a === b ? SHARE_SELF : SHARE_PAIR); no++) oneShare(a.name, b.name, no);
  }
  // Заданные случаи переноса на паре synthetic.share-*: значение верно в обоих типах шага, но тип другой — не
  // переносится; значение верно в сценарии источника, но нет такого варианта у основного — не переносится
  const sa = pool[keyOf.get("synthetic.share-a")];
  const sb = pool[keyOf.get("synthetic.share-b")];
  pushShare("synthetic/type-changed-a>b", "synthetic.share-a", "synthetic.share-b", answered(sa, [["s1", "a"], ["s2", "x"]]), S.start(sb));
  pushShare("synthetic/type-changed-b>a", "synthetic.share-b", "synthetic.share-a", answered(sb, [["s1", "a"], ["s2", "x"]]), S.start(sa));
  pushShare("synthetic/option-removed", "synthetic.share-a", "synthetic.share-b", answered(sa, [["s1", "c"], ["s2", "x"]]), S.start(sb));
  return { pool, counts, vectors };
}

/* ===== Покрытие ===== */

// Причина отказа и тип шага должны встречаться хоть раз; нет — генератор падает с перечнем
function uncovered(data) {
  const reasons = new Set(data.vectors.filter((v) => v.op === "answer" && v.expect.error).map((v) => v.expect.error));
  const types = new Set();
  for (const v of data.vectors) {
    if (v.op !== "answer" || !v.expect.ok) continue;
    const step = data.pool[v.script].steps.find((s) => s.id === v.call.stepId);
    if (step) types.add(step.type);
  }
  return [...REASONS.filter((r) => !reasons.has(r)).map((r) => `причина ${r}`), ...TYPES.filter((t) => !types.has(t)).map((t) => `тип шага ${t}`)];
}

/* ===== Запись ===== */

function serialize(data) {
  const scripts = Object.keys(data.pool).sort().map((k) => `${JSON.stringify(k)}: ${JSON.stringify(data.pool[k])}`);
  return [
    "{",
    `"format": 1,`,
    `"timeZone": "UTC",`,
    `"scripts": {\n${scripts.join(",\n")}\n},`,
    `"counts": ${JSON.stringify(data.counts)},`,
    `"vectors": [\n${data.vectors.map((v) => JSON.stringify(v)).join(",\n")}\n]`,
    "}",
    "",
  ].join("\n");
}

function firstDiff(a, b) {
  const x = a.split("\n");
  const y = b.split("\n");
  for (let i = 0; i < Math.max(x.length, y.length); i++) if (x[i] !== y[i]) return i + 1;
  return 0;
}

/* ===== Запуск ===== */

const argv = process.argv.slice(2);
const opt = (name) => (argv.find((a) => a.startsWith(`--${name}=`)) || "").slice(name.length + 3) || null;
const rel = (p) => (path.relative(ROOT, p).startsWith("..") ? p : path.relative(ROOT, p));

function make(scenarioPath) {
  const data = build(executor(scenarioPath), loadScripts());
  const text = serialize(data);
  const missing = uncovered(data);
  return { data, text, missing };
}

if (opt("scenario") && !argv.includes("--check")) {
  // Порченый исполнитель не должен записать эталон
  console.log("--scenario — только для проб порчи с --check");
  process.exitCode = 1;
} else if (opt("scenario") && !fs.existsSync(opt("scenario"))) {
  console.log(`--scenario: нет файла ${opt("scenario")}`);
  process.exitCode = 1;
} else if (argv.includes("--update") || argv.includes("--check")) {
  const update = argv.includes("--update");
  let ok = false;
  try {
    const { data, text, missing } = make(opt("scenario") ? path.resolve(opt("scenario")) : SCENARIO_JS);
    const bytes = Buffer.byteLength(text, "utf8");
    if (missing.length) console.log(`не покрыто: ${missing.join(", ")}`);
    else if (bytes > MAX_BYTES) console.log(`файл больше ${MAX_BYTES / 1048576} МБ: ${(bytes / 1048576).toFixed(2)} МБ (answer ${data.counts.answer}, share ${data.counts.share})`);
    else if (update) {
      fs.mkdirSync(path.dirname(FILE), { recursive: true });
      fs.writeFileSync(FILE, text);
      console.log(`записано ${rel(FILE)}: сценариев ${Object.keys(data.pool).length}, answer ${data.counts.answer}, share ${data.counts.share}, ${(bytes / 1048576).toFixed(2)} МБ`);
      ok = true;
    } else if (!fs.existsSync(FILE)) console.log("нет файла, соберите: node tools/scenario_vectors.mjs --update");
    else {
      const have = fs.readFileSync(FILE, "utf8");
      if (have === text) ok = true;
      else console.log(`${rel(FILE)} не равен сборке (первое отличие — строка ${firstDiff(have, text)}): исполнитель или сценарии изменились, node tools/scenario_vectors.mjs --update`);
    }
  } catch (e) {
    console.log(`scenario_vectors: ${e.message}`);
  }
  process.exitCode = ok ? 0 : 1;
} else {
  console.log("node tools/scenario_vectors.mjs --update | --check [--scenario=путь]");
  process.exitCode = 1;
}
