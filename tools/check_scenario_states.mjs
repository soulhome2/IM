// Полный перебор состояний исполнителя сценариев (PROC-79; консилиум 2026-10-24, В13, А4-14): модель Quint и сверка
// ядра подставляют вместо сценария заглушку, а путь по веткам, выпавшие шаги, перенос ответов при объединении и
// «пройден» — в prototype/scenario.js. Здесь он перебирается целиком на сценариях эталонного набора и примерах машины
// сценариев: из начала — любой ответ на любой шаг пути (текущий и пройденный, если его можно переответить), пропуск
// необязательного; состояния различаются ответами, путём, текущим шагом и завершённостью. Ответ на шаг с выбором —
// каждым вариантом, на остальные — одним допустимым значением. Перенос (share) — между всеми найденными
// прохождениями всех версий одного сценария, в том числе пары версий, где у шага тот же id, но другой тип; пар
// больше PAIRS (большие примеры) — выборка PAIRS пар с постоянным зерном, повторяемая.
// Свойства прохождения — как consistent в tests/scenario-tests.js, и свойства переноса.
// Запуск из корня репозитория: node tools/check_scenario_states.mjs [--mutations]
// --mutations — самопроверка: каждую порчу исполнителя из MUTATIONS перебор должен поймать
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const AT = "2026-10-27T10:00:00Z";
const DATETIME = "2026-10-27T09:30:00Z";

// Сценарии: эталонный набор и примеры машины сценариев (без отрицательных — их отвергает проверка сценариев)
function scripts() {
  const dirs = [path.join(ROOT, "Specification/Workflow_machine/fixtures/scenarios"), path.join(ROOT, "Specification/Scenario_machine/examples")];
  const out = [];
  for (const d of dirs) for (const f of fs.readdirSync(d).filter((x) => x.endsWith(".json")).sort()) out.push({ name: f, script: JSON.parse(fs.readFileSync(path.join(d, f), "utf8")) });
  // Пара версий, где у шага тот же id, но другой тип (Р10): заметка оператора — выбор с вариантом, который совпадает
  // с ответом-комментарием, — перенос без сверки типа его бы перенёс
  const base = out.find((x) => x.name === "01-perimeter-alarm.json");
  const v2 = JSON.parse(JSON.stringify(base.script));
  v2.scenario.version = 2;
  const note = v2.steps.find((s) => s.id === "operator_note");
  const comment = answersFor(note)[0].value;
  note.type = "RadioButton";
  note.view = { label: "Заметка", required: false, options: [{ id: comment, label: "Заметка", default: false }, { id: "none", label: "Нет", default: false }] };
  out.push({ name: "01-perimeter-alarm.json, версия 2: operator_note — RadioButton", script: v2 });
  return out;
}
const COMMENT = "note";

// Исполнитель — из prototype/scenario.js через vm, с JSONLogic, как в браузере; source — для порч
function executor(source) {
  const g = { console };
  g.window = g;
  vm.createContext(g);
  vm.runInContext(fs.readFileSync(path.join(ROOT, "prototype/vendor/json-logic-js/logic.js"), "utf8"), g);
  vm.runInContext(source, g, { filename: "scenario.js" });
  return g.IMScenario;
}

// Ответы на шаг: { value, attachments } для каждого варианта; пропуск — отдельно
function answersFor(step) {
  const v = step.view;
  switch (step.type) {
    case "RadioButton":
      return v.options.map((o) => ({ value: o.id }));
    case "Checkbox": {
      const ids = v.options.map((o) => o.id);
      const max = v.maxSelected != null ? v.maxSelected : ids.length;
      const sets = ids.map((x) => [x]).concat([ids.slice(0, max)]);
      if (v.minSelected === 0) sets.push([]);
      return sets.filter((s) => s.length >= v.minSelected && s.length <= max).map((value) => ({ value }));
    }
    case "Select":
      return v.lists[0].options.map((o) => ({ value: Object.fromEntries(v.lists.map((l, i) => [l.id, [i === 0 ? o.id : l.options[0].id]])) }));
    case "Comment":
      return [{ value: v.readonly ? "" : COMMENT.padEnd(v.minLength || 0, ".") }];
    case "Datetime":
      return [{ value: v.min || v.max || DATETIME }];
    case "Image": {
      const att = { id: `img-${step.id}`, stepId: step.id, name: "photo.jpg", mime: "image/jpeg", size: 1 };
      return [{ value: att.id, attachments: [att] }];
    }
    default:
      return [{ value: null }];
  }
}

const stepOf = (script, id) => script.steps.find((s) => s.id === id) || null;
// Обязательный шаг — по спецификации, раздел 9, а не по исполнителю: его и проверяем
const required = (step) => (step.type === "Checkbox" ? step.view.minSelected > 0 : step.type !== "Image" && step.type !== "Message" && step.view.required === true);
const key = (S, script, r) => JSON.stringify([Object.entries(r.state).sort(([a], [b]) => (a < b ? -1 : 1)).map(([id, e]) => [id, e.value, Boolean(e.skipped)]), S.path(script, r), r.currentStepId, Boolean(r.completedAt)]);

// Нарушения свойств прохождения
function violations(S, script, r) {
  const out = [];
  const p = S.path(script, r);
  if (r.completedAt) {
    if (r.currentStepId !== null) out.push("у завершённого есть текущий шаг");
    const last = stepOf(script, p[p.length - 1]);
    if (!last || !r.state[last.id] || S.evaluate(last, r.state[last.id].value)) out.push(`завершён, а последний шаг пути ${p[p.length - 1]} не финальный или без ответа`);
  } else if (r.currentStepId !== p[p.length - 1]) out.push(`текущий шаг ${r.currentStepId} — не конец пути ${p.join(" → ")}`);
  for (const id of Object.keys(r.state)) if (!p.includes(id)) out.push(`ответ у шага ${id} вне пути ${p.join(" → ")}`);
  p.slice(0, r.completedAt ? p.length : -1).forEach((id) => !r.state[id] && out.push(`шаг пути ${id} без ответа`));
  for (const [id, e] of Object.entries(r.state)) {
    const step = stepOf(script, id);
    if (e.skipped && step && (step.type === "Message" || required(step))) out.push(`обязательный шаг ${id} пропущен`);
  }
  // Следующий шаг пути — исход ответа предыдущего
  for (let i = 0; i + 1 < p.length; i++) {
    const e = r.state[p[i]];
    const ev = e && S.evaluate(stepOf(script, p[i]), e.value);
    if (e && (!ev || ev.outcome.goto !== p[i + 1])) out.push(`после ${p[i]} путь ведёт в ${p[i + 1]}, а ответ — в ${ev ? ev.outcome.goto : "конец"}`);
  }
  if (S.stepsFilled(script, r, "closing") !== Boolean(r.completedAt)) out.push("набор closing не совпадает с завершённостью");
  const prog = S.progress(script, r);
  if (prog.total !== null && prog.filled > prog.total) out.push(`прогресс ${prog.filled} из ${prog.total}`);
  return out;
}

// Все состояния сценария из начала: ответ на шаг пути каждым вариантом и пропуск
function explore(S, script) {
  const seen = new Map();
  const queue = [[S.start(script), []]];
  const problems = [];
  seen.set(key(S, script, queue[0][0]), queue[0]);
  while (queue.length && problems.length < 3) {
    const [r, trail] = queue.shift();
    violations(S, script, r).forEach((v) => problems.push(`${v}; шаги: ${trail.join(", ") || "начало"}`));
    for (const id of S.path(script, r)) {
      const step = stepOf(script, id);
      // Пропуск — на каждом шаге: можно ли, решает исполнитель, а свойства проверяют, что он решил верно
      const tries = answersFor(step).map((a) => [a, { at: AT, by: "op", attachments: a.attachments }]);
      tries.push([{ value: null }, { at: AT, by: "op", skip: true }]);
      for (const [a, opts] of tries) {
        const res = S.answer(script, r, id, a.value, opts);
        if (!res.ok) continue;
        const k = key(S, script, res.result);
        if (!seen.has(k)) {
          const item = [res.result, trail.concat(`${id}=${opts.skip ? "пропуск" : JSON.stringify(a.value)}`)];
          seen.set(k, item);
          queue.push(item);
        }
      }
    }
  }
  return { states: [...seen.values()], problems };
}

// Перенос ответов из каждого прохождения в каждое — в пределах одного сценария (все версии); пар больше PAIRS —
// выборка PAIRS пар, зерно постоянное
const PAIRS = 100000;
function shares(S, group) {
  const all = [];
  for (const from of group) for (const to of group) all.push([from, to, from.states.length * to.states.length]);
  const total = all.reduce((s, [, , n]) => s + n, 0);
  let seed = 1;
  const rnd = (n) => ((seed = (seed * 48271) % 2147483647), seed % n);
  const pairs = function* () {
    if (total <= PAIRS) {
      for (const [from, to] of all) for (const [fr] of from.states) for (const t of to.states) yield [from, to, fr, t];
      return;
    }
    for (let k = 0; k < PAIRS; k++) {
      let x = rnd(total);
      const [from, to] = all.find(([, , n]) => (x < n ? true : ((x -= n), false)));
      yield [from, to, from.states[Math.floor(x / to.states.length)][0], to.states[x % to.states.length]];
    }
  };
  let n = 0;
  const problems = [];
  for (const [from, to, fr, [tr, trail]] of pairs()) {
    if (problems.length >= 3) return { n, problems, sampled: total > PAIRS };
    n++;
    const { result, moved } = S.share(from.script, fr, to.script, tr, { at: AT });
    const where = `перенос ${from.name} → ${to.name} (основной: ${trail.join(", ") || "начало"})`;
    for (const [id, e] of Object.entries(tr.state)) if (JSON.stringify(result.state[id]) !== JSON.stringify(e)) problems.push(`${where}: перезаписан ответ основного ${id}`);
    if (tr.completedAt && moved.length) problems.push(`${where}: перенос в завершённое`);
    for (const id of moved) {
      const a = stepOf(from.script, id);
      const b = stepOf(to.script, id);
      if (!a || !b || a.type !== b.type) problems.push(`${where}: перенесён шаг ${id} другого типа`);
      if (fr.state[id] && fr.state[id].skipped) problems.push(`${where}: перенесён пропуск ${id}`);
    }
    violations(S, to.script, result).forEach((v) => problems.push(`${where}: ${v}`));
    if (S.share(from.script, fr, to.script, result, { at: AT }).moved.length) problems.push(`${where}: повторный перенос что-то добавил`);
  }
  return { n, problems, sampled: total > PAIRS };
}

function check(source) {
  const S = executor(source);
  const all = scripts().map((x) => ({ ...x, ...explore(S, x.script) }));
  const problems = all.flatMap((x) => x.problems.map((p) => `${x.name}: ${p}`));
  const groups = new Map();
  all.forEach((x) => groups.set(x.script.scenario.id, (groups.get(x.script.scenario.id) || []).concat(x)));
  let n = 0;
  const sampled = [];
  for (const group of groups.values()) {
    const r = shares(S, group);
    n += r.n;
    if (r.sampled) sampled.push(group[0].name);
    problems.push(...r.problems);
    if (problems.length >= 5) break;
  }
  return { scripts: all.length, states: all.reduce((s, x) => s + x.states.length, 0), shares: n, sampled, problems };
}

// Порчи исполнителя для самопроверки: что найти в prototype/scenario.js (ровно одно место) и на что заменить
const MUTATIONS = [
  ["share-overwrites", "перенос перезаписывает ответ основного (А4, M1)", "if (!entry || entry.skipped || r.state[id] || !src", "if (!entry || entry.skipped || !src"],
  ["dropped-kept", "ответы выпавших шагов не удаляются (А4, M2)", "dropped.forEach((id) => delete r.state[id]);", ""],
  ["branch-keeps-completed", "смена ветки не снимает завершённость (А4, M3)", "      r.currentStepId = after[after.length - 1];\n      r.completedAt = null;", "      r.currentStepId = after[after.length - 1];"],
  ["share-any-type", "перенос без сверки типа шага (А4, M4)", " || src.type !== step.type) break;", ") break;"],
  ["share-skipped", "переносится пропуск", "if (!entry || entry.skipped || r.state[id]", "if (!entry || r.state[id]"],
  ["closing-by-count", "«пройден» — по числу ответов, а не по завершённости (аудит 2)", "(setId === \"closing\" && Boolean(result.completedAt))", "(setId === \"closing\" && Object.keys(result.state).length > 0)"],
  ["skip-required", "пропуск обязательного шага разрешён", "if (o.skip && !canSkip(step)) return { ok: false, error: \"required\" };", ""],
];

const source = fs.readFileSync(path.join(ROOT, "prototype/scenario.js"), "utf8");
if (process.argv.includes("--mutations")) {
  let bad = 0;
  for (const [name, what, find, replace] of MUTATIONS) {
    if (source.split(find).length !== 2) {
      console.log(`STALE ${name}: в prototype/scenario.js место порчи не найдено или не одно`);
      bad++;
      continue;
    }
    const r = check(source.replace(find, replace));
    console.log(r.problems.length ? `OK  ${name} — ${what}: ${r.problems[0]}` : `BAD ${name} — ${what}: перебор не поймал`);
    bad += !r.problems.length;
  }
  console.log(`Порч исполнителя сценариев: ${MUTATIONS.length}, не пойманных: ${bad}`);
  process.exit(bad ? 1 : 0);
}
const r = check(source);
r.problems.slice(0, 5).forEach((p) => console.log(p));
console.log(`Сценариев: ${r.scripts}, состояний прохождения: ${r.states}, переносов: ${r.shares}${r.sampled.length ? ` (выборкой по ${PAIRS} пар: ${r.sampled.join(", ")})` : ""}. Нарушений: ${r.problems.length}`);
process.exit(r.problems.length ? 1 : 0);
