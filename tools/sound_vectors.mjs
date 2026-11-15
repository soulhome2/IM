// Векторы функции решения звука (правила §21, план 87б, задача 3): файл Specification/Workflow_machine/fixtures/sound-vectors.json —
// источник, правится руками, ожидания записаны по правилам, а не сняты с кода. Каждый вектор гоняется через
// prototype/sound.js (window.IMSound) в vm; конфигуратор (src/operator/sound/decide.ts) проходит те же векторы.
//
//   node tools/sound_vectors.mjs --check   — прогнать все векторы; при расхождении — перечень, код 1; иначе «sound vectors: N/N»
//   --sound=путь — копия prototype/sound.js для проб порчи: порченая функция обязана дать код 1
//
// Формат 1: { $comment, format, settings, vectors: [...] }. settings — раздел sound машины без $comment (сверяется с
// workflow_schema.v1.json); у вектора settings — JSON Merge Patch поверх него (RFC 7396, как патч поста).
// Вектор: { name, rules, settings?, ctx: { agentState, meGuid, onlyImportantUntil, now }, steps: [...] }; состояние
// в начале — { sounding: [], attention: [] }. Шаг — одно из:
//   { now?, event }       — decideSound(state, event, ctx)
//   { now?, silence }     — silence(state), «Тихо»
//   { now?, tick: {...} } — сменить поля ctx (agentState, onlyImportantUntil) и applyCtx(state, ctx)
//   { now?, restore: [] } — restoreSound(очередь IncidentSummary, ctx): перечитанная очередь, без залпа
//   { plan: { start, horizonSec? } } — planRepeats(topSounding(state), start, horizonSec)
//   { cue: уровень | { level, byPriority } } — cueForPriority(byPriority ?? ctx.settings.byPriority, level)
// now — сменить ctx.now до шага. expect — только перечисленные ключи, сравнение точное:
//   play (Sounding | null, только у event), sounding, attention, top (guid верхнего или null), repeats, cue.
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const FILE = path.join(ROOT, "Specification/Workflow_machine/fixtures/sound-vectors.json");
const MACHINE = path.join(ROOT, "Specification/Workflow_machine/workflow_schema.v1.json");
const MIN_VECTORS = 30;

const args = process.argv.slice(2);
const soundArg = args.find((a) => a.startsWith("--sound="));
const SOUND_JS = soundArg ? path.resolve(soundArg.slice("--sound=".length)) : path.join(ROOT, "prototype/sound.js");
if (!args.includes("--check")) {
  console.error("запуск: node tools/sound_vectors.mjs --check [--sound=путь]");
  process.exit(1);
}

const clone = (x) => JSON.parse(JSON.stringify(x));
const canon = (x) => JSON.stringify(x, (k, v) => (v && typeof v === "object" && !Array.isArray(v) ? Object.fromEntries(Object.keys(v).sort().map((key) => [key, v[key]])) : v));
const stripComments = (o) => Object.fromEntries(Object.entries(o).filter(([k]) => !k.startsWith("$comment")));

// JSON Merge Patch (RFC 7396)
function mergePatch(target, patch) {
  if (patch === null || typeof patch !== "object" || Array.isArray(patch)) return clone(patch);
  const out = target && typeof target === "object" && !Array.isArray(target) ? clone(target) : {};
  for (const [k, v] of Object.entries(patch)) {
    if (v === null) delete out[k];
    else out[k] = mergePatch(out[k], v);
  }
  return out;
}

function loadSound() {
  if (!fs.existsSync(SOUND_JS)) throw new Error(`нет ${path.relative(ROOT, SOUND_JS)}`);
  const g = { console };
  g.window = g;
  vm.createContext(g);
  vm.runInContext(fs.readFileSync(SOUND_JS, "utf8"), g, { filename: "sound.js" });
  const S = g.IMSound;
  for (const fn of ["cueForPriority", "decideSound", "silence", "topSounding", "planRepeats", "restoreSound", "applyCtx"]) {
    if (!S || typeof S[fn] !== "function") throw new Error(`в sound.js нет IMSound.${fn}`);
  }
  return S;
}

function run() {
  const errors = [];
  const data = JSON.parse(fs.readFileSync(FILE, "utf8"));
  if (data.format !== 1) errors.push(`format ${data.format}, ждали 1`);
  const machine = JSON.parse(fs.readFileSync(MACHINE, "utf8"));
  if (canon(stripComments(machine.sound || {})) !== canon(data.settings)) errors.push("settings файла не равны разделу sound машины (без $comment)");
  if (data.vectors.length < MIN_VECTORS) errors.push(`векторов ${data.vectors.length}, нужно не меньше ${MIN_VECTORS}`);
  const names = new Set();
  for (const v of data.vectors) {
    if (names.has(v.name)) errors.push(`имя вектора повторяется: ${v.name}`);
    names.add(v.name);
  }

  let S;
  try {
    S = loadSound();
  } catch (e) {
    errors.push(String(e.message || e));
    return { errors, passed: 0, total: data.vectors.length };
  }

  let passed = 0;
  for (const v of data.vectors) {
    const fails = [];
    try {
      const ctx = clone(v.ctx);
      ctx.settings = v.settings ? mergePatch(data.settings, v.settings) : clone(data.settings);
      let state = { sounding: [], attention: [] };
      v.steps.forEach((step, i) => {
        if (step.now !== undefined) ctx.now = step.now;
        const got = {};
        if (step.event !== undefined) {
          const r = S.decideSound(clone(state), clone(step.event), clone(ctx));
          state = r.state;
          got.play = r.play;
        } else if (step.silence) {
          state = S.silence(clone(state));
        } else if (step.tick) {
          Object.assign(ctx, step.tick);
          state = S.applyCtx(clone(state), clone(ctx));
        } else if (step.restore) {
          state = S.restoreSound(clone(step.restore), clone(ctx));
        } else if (step.plan) {
          const top = S.topSounding(clone(state));
          got.repeats = step.plan.horizonSec === undefined ? S.planRepeats(top, step.plan.start) : S.planRepeats(top, step.plan.start, step.plan.horizonSec);
        } else if (step.cue !== undefined) {
          const level = typeof step.cue === "number" ? step.cue : step.cue.level;
          const byPriority = typeof step.cue === "number" ? ctx.settings.byPriority : step.cue.byPriority;
          got.cue = S.cueForPriority(clone(byPriority), level);
        } else {
          fails.push(`шаг ${i + 1}: неизвестный вид шага`);
          return;
        }
        got.sounding = state.sounding;
        got.attention = state.attention;
        const top = S.topSounding(clone(state));
        got.top = top ? top.guid : null;
        for (const [k, want] of Object.entries(step.expect || {})) {
          if (!(k in got)) {
            fails.push(`шаг ${i + 1}: ожидание ${k} не к этому виду шага`);
            continue;
          }
          if (canon(got[k] ?? null) !== canon(want)) fails.push(`шаг ${i + 1}, ${k}: ждали ${canon(want)}, получили ${canon(got[k] ?? null)}`);
        }
      });
    } catch (e) {
      fails.push(`исключение: ${e.stack || e}`);
    }
    if (fails.length) errors.push(`«${v.name}»:\n    ${fails.join("\n    ")}`);
    else passed++;
  }
  return { errors, passed, total: data.vectors.length };
}

const { errors, passed, total } = run();
console.log(`sound vectors: ${passed}/${total}`);
if (errors.length) {
  for (const e of errors) console.error("  " + e);
  process.exit(1);
}
