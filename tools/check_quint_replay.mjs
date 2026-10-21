// Сверка ядра исполнения (ARCH-07.9): истории модели Quint повторяются на исполнителе прототипа.
// Ядро — порядок условий, срочность автоматических переходов, окно после дедлайна, объединение — записано
// дважды: prototype/engine.js и Specification/Workflow_machine/quint/src/core.qnt. Модель разыгрывает истории
// (quint run --out-itf), скрипт повторяет каждый шаг на исполнителе — те же настройки, права, доступ, состояние
// операторов, часы и действия — и в спокойные моменты (у модели нет готовых автоматических переходов)
// сравнивает все инциденты и ответы сценария. Факты мира — из истории модели, без сервера и эталонного набора.
// Запуск из корня репозитория: node tools/check_quint_replay.mjs [--traces=N] [--steps=M] [--seed=0x…]
// [--dir=папка с готовыми *.itf.json]. Нужен quint в PATH (если нет --dir).
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import vm from "node:vm";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const Q = path.join(ROOT, "Specification/Workflow_machine/quint");
const MACHINE = JSON.parse(fs.readFileSync(path.join(ROOT, "Specification/Workflow_machine/workflow_schema.v1.json"), "utf8"));
const opt = (name, dflt) => (process.argv.find((a) => a.startsWith(`--${name}=`)) || `=${dflt}`).split("=").slice(1).join("=");
const TRACES = Number(opt("traces", 300));
const STEPS = Number(opt("steps", 40));
const OPS = ["a", "b"];
const GROUP = "g";
const IDS = ["i1", "i2", "i3"];

/* ===== Истории модели ===== */

let dir = opt("dir", "");
if (!dir) {
  dir = fs.mkdtempSync(path.join(os.tmpdir(), "quint-replay-"));
  // Пачками по 200: quint держит выгружаемые истории в памяти. Зерно пачки — заданное плюс её номер
  const seed = opt("seed", "");
  for (let b = 0, left = TRACES; left > 0; b++, left -= 200) {
    const n = Math.min(200, left);
    const r = spawnSync(
      "quint",
      ["run", "im.qnt", "--invariant", "inv", `--max-samples=${n}`, `--max-steps=${STEPS}`, `--out-itf=${dir}/b${b}t{seq}.itf.json`, `--n-traces=${n}`, ...(seed ? [`--seed=${"0x" + (BigInt(seed) + BigInt(b)).toString(16)}`] : [])],
      { cwd: Q, encoding: "utf8", maxBuffer: 1 << 28 }
    );
    if (r.status !== 0 && !/\[ok\]/.test(r.stdout)) {
      console.log(r.stdout.split("\n").slice(-5).join("\n"), r.stderr);
      process.exit(1);
    }
  }
}
// Значение ITF → данные: целые — числа, словари — объекты, множества — отсортированные списки
function decode(v) {
  if (Array.isArray(v)) return v.map(decode);
  if (!v || typeof v !== "object") return v;
  if ("#bigint" in v) return Number(v["#bigint"]);
  if ("#map" in v) return Object.fromEntries(v["#map"].map(([k, x]) => [String(decode(k)), decode(x)]));
  if ("#set" in v) return v["#set"].map(decode).sort();
  if ("#tup" in v) return v["#tup"].map(decode);
  return Object.fromEntries(Object.entries(v).filter(([k]) => !k.startsWith("#")).map(([k, x]) => [k, decode(x)]));
}

/* ===== Исполнитель прототипа ===== */

const g = { console, TextEncoder, TextDecoder };
g.window = g;
vm.createContext(g);
for (const f of ["prototype/vendor/cel-js/cel.js", "prototype/cel-runtime.js", "prototype/engine.js"]) vm.runInContext(fs.readFileSync(path.join(ROOT, f), "utf8"), g, { filename: f });

// Машина с настройками истории: переключатели, лимиты, люди модели в уровнях эскалации и алертах
const machines = new Map();
function machineFor(s) {
  const key = JSON.stringify([s.escalation.enabled, s.escalation.onResolutionOverdue, s.escalation.levels.map((l) => l.target), s.limits.maxActive, s.limits.maxOnHold]);
  if (!machines.has(key)) {
    const w = JSON.parse(JSON.stringify(MACHINE));
    Object.assign(w.escalation, { enabled: s.escalation.enabled, onResolutionOverdue: s.escalation.onResolutionOverdue });
    w.escalation.levels = w.escalation.levels.map((l, i) => Object.assign({}, l, { targetKind: s.escalation.levels[i].targetKind, target: s.escalation.levels[i].target }));
    Object.assign(w.alerts, { targetKind: s.alerts.targetKind, target: s.alerts.target });
    w.limits.maxActive = s.limits.maxActive || null;
    w.limits.maxOnHold = s.limits.maxOnHold || null;
    machines.set(key, vm.runInContext("JSON.parse", g)(JSON.stringify(w)));
  }
  return machines.get(key);
}

function replay(states, name) {
  const facts = {};
  const setFacts = (st) => Object.assign(facts, { cfg: st.cfg, agents: st.agents, lastBeat: st.lastBeat, clock: st.clock });
  setFacts(states[0]);
  const W = machineFor(states[0].settings);
  const events = [];
  const answers = Object.fromEntries(IDS.map((i) => [i, []]));
  const evOf = (id) => events.find((e) => e.id === id);
  const engines = {};
  for (const me of OPS) {
    engines[me] = g.IMEngine.create({
      workflow: W,
      me,
      now: () => facts.clock,
      events: () => events,
      scenarioKey: (ev) => ev.scenarioGuid,
      can: (key) => facts.cfg.perms[me].includes(key),
      permsOf: (who) => (facts.cfg.perms[who] || []).slice(),
      isGroup: (id) => id === GROUP,
      isOperator: (id) => OPS.includes(id),
      membersOf: (grp) => (grp === GROUP ? OPS.filter((m) => facts.cfg.members[GROUP].includes(m)) : []),
      dutyGroups: () => [GROUP],
      inGroup: () => false,
      agentState: () => facts.agents[me],
      agentStateOf: (who) => facts.agents[who] || "offline",
      idleSec: () => (facts.clock - facts.lastBeat[me]) / 1000,
      hasAccess: (who, ev) => OPS.includes(who) && facts.cfg.access[who].includes(ev.id),
      stepsFilled: (ev, setId) => setId === "none" || (setId === "closing" && ["s1", "s2"].every((x) => answers[ev.id].includes(x))),
      progress: (ev) => ({ filled: answers[ev.id].length, total: 2 }),
      stepNumber: () => 1,
      setCursor: () => {},
      shareAnswers: (from, to) => {
        const add = answers[from.id].filter((x) => !answers[to.id].includes(x));
        answers[to.id] = answers[to.id].concat(add).sort();
        return add.length;
      },
      actorName: (id) => id || "",
      log: (ev, whoId, k, v, at) => ev.log.push({ at, whoId, k, v }),
      transferTargets: () => [],
      defaultTransferTarget: () => null,
      notifyAlert: () => 1,
      alertRecipients: () => 1,
      onEvict: () => {},
      onBreachShared: () => {},
    });
  }
  // Планировщик — как у сервера прототипа: полный такт от первого оператора, у остальных — их системные (agentOnly)
  const settle = () => {
    for (let n = 0; n < 50; n++) {
      const fired = engines.a.tick().length + engines.b.tick({ agentOnly: true }).length;
      if (!fired) return;
    }
  };
  // since («когда запущен») прототип хранит только у таймера удержания (FIELDS в engine.js); выражения машины его
  // не читают — у остальных таймеров не сравнивается
  const norm = (x) => {
    if (!x) return x;
    const y = JSON.parse(JSON.stringify(x));
    Object.keys(y.timers || {}).forEach((t) => t !== "hold" && (y.timers[t].since = 0));
    return sorted(y);
  };
  const problems = [];
  const compare = (k, st) => {
    for (const id of IDS) {
      const want = st.world.inc[id];
      if (want.state === "") continue;
      const ev = evOf(id);
      const got = ev ? norm(engines.a.celView(ev)) : null;
      if (JSON.stringify(norm(want)) !== JSON.stringify(got)) problems.push(`${name}, шаг ${k} (${describe(st.lastAction)}): ${id} — ${diff(norm(want), got)}`);
    }
    for (const id of IDS) {
      const want = (st.world.answers[id] || []).slice().sort();
      if (JSON.stringify(want) !== JSON.stringify(answers[id].slice().sort())) problems.push(`${name}, шаг ${k}: ответы ${id} — модель ${want}, исполнитель ${answers[id]}`);
    }
  };
  for (let k = 1; k < states.length && !problems.length; k++) {
    const st = states[k];
    const a = st.lastAction;
    setFacts(states[k - 1]);
    if (a.kind === "create") {
      const ev = { id: a.incident, number: a.incident, typeId: "fire", priority: a.prio, scenarioGuid: a.scenario, log: [], breaches: [] };
      events.push(ev);
      events.sort((x, y) => IDS.indexOf(x.id) - IDS.indexOf(y.id));
      const r = engines.a.create(ev);
      if (!r.ok) problems.push(`${name}, шаг ${k}: появление ${a.incident} — исполнитель отказал: ${JSON.stringify(r.why)}`);
    } else if (a.kind === "manual") {
      const r = engines[a.actor].run(a.name, evOf(a.incident), Object.assign({}, a.form), { surface: a.surface });
      if (!r.ok) problems.push(`${name}, шаг ${k} (${describe(a)}): модель выполнила, исполнитель отказал: ${JSON.stringify(r.why)}`);
    } else if (a.kind === "merge") {
      const r = engines[a.actor].merge(evOf(a.incident), a.others.map(evOf));
      if (!r.ok) problems.push(`${name}, шаг ${k} (${describe(a)}): модель объединила, исполнитель отказал: ${JSON.stringify(r.why)}`);
    } else if (a.name === "answer") answers[a.incident] = st.world.answers[a.incident].slice();
    setFacts(st);
    // Спокойный момент: следующее действие модели — не автоматический переход. Последний шаг истории — без
    // планировщика: история могла оборваться посреди автоматических переходов; оборвалась на нём — не сравнивается
    const next = states[k + 1];
    if (!next) {
      if (a.kind !== "auto") compare(k, st);
    }
    else if (next.lastAction.kind !== "auto") {
      settle();
      compare(k, st);
    }
  }
  return problems;
}
const describe = (a) => [a.kind, a.name, a.actor, a.incident, a.kind === "merge" ? a.others.join("+") : ""].filter(Boolean).join(" ");
const sorted = (v) => (Array.isArray(v) ? v.map(sorted) : v && typeof v === "object" ? Object.fromEntries(Object.keys(v).sort().map((k) => [k, sorted(v[k])])) : v);
function diff(a, b, p = "", out = []) {
  if (JSON.stringify(a) === JSON.stringify(b)) return out.join("; ");
  if (a && b && typeof a === "object" && typeof b === "object") new Set([...Object.keys(a), ...Object.keys(b)]).forEach((k) => diff(a[k], b[k], `${p}.${k}`, out));
  else out.push(`${p || "."}: модель ${JSON.stringify(a)}, исполнитель ${JSON.stringify(b)}`);
  return out.slice(0, 6).join("; ");
}

const num = (f) => f.match(/\d+/g).map(Number);
const files = fs.readdirSync(dir).filter((f) => f.endsWith(".itf.json")).sort((x, y) => num(x)[0] - num(y)[0] || num(x)[1] - num(y)[1]);
let checked = 0;
let steps = 0;
const all = [];
for (const f of files) {
  const states = JSON.parse(fs.readFileSync(path.join(dir, f), "utf8")).states.map(decode);
  const p = replay(states, f);
  checked++;
  steps += states.length - 1;
  all.push(...p);
  if (all.length >= 5) break;
}
all.slice(0, 5).forEach((x) => console.log(x));
console.log(`Историй модели: ${checked}, шагов: ${steps}. Расхождений модели и исполнителя: ${all.length}`);
process.exit(all.length ? 1 : 0);
