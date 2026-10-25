// Порчи машины для модели Quint (ARCH-07.6): в копии машины (или ручной части модели) портится одно место, модель генерируется
// заново (tools/gen_quint.mjs), и её инварианты (quint run) или сценарии (quint test) должны порчу поймать.
// Не поймали — инварианты и сценарии этого правила не проверяют. Нужен quint в PATH.
// Истории — по профилям порога покрытия (tools/quint_profiles.mjs) до первого нарушения; поймавшие инварианты —
// по имени (--invariants), в конце — какие инварианты какие порчи ловят (PROC-75). Контроль без порчи — первым:
// не прошёл или quint не разобрал модель — прогон недействителен, а не «поймано» (ERROR).
// Порчи независимы — каждая в своём каталоге — и идут одновременно (PROC-41): --jobs=N, по умолчанию три
// четверти ядер, как у мутаций кода (tools/parallel.py); итог печатается в порядке списка.
// Запуск из корня репозитория: node tools/check_quint_mutations.mjs [имя …] [--samples=N] [--jobs=N] [--shard=K/M]
// --samples=N — всего историй на порчу, по профилям пропорционально (по умолчанию — как у порога покрытия)
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync, spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import { PROFILES, STEPS } from "./quint_profiles.mjs";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const MACHINE = path.join(ROOT, "Specification/Workflow_machine/workflow_schema.v1.json");
const Q = path.join(ROOT, "Specification/Workflow_machine/quint");
const T = "incident.timers[timerId]";

// Порчи ручных частей модели (quint/src/…, пятое поле): ядро или мир, машина не меняется (PROC-45). Порчи машины —
// в общем списке tools/mutations/machine.json, ниже (ALL)
const MUTATIONS = [
  ["core-timer-late", "ядро: часы не останавливаются в конце окна — переход по таймеру опаздывает (П1)", ".union(ds.map(d => d + GRACE_MS))", "", "core.qnt"],
  ["core-window-no-breach", "ядро: ручное действие в окне отменяет переход по таймеру без нарушения (RULE-63, BUG-62)", "windowBreach(t.id, { ...ctx(DISPATCHER, DISPATCHER, NO_FORM, \"\"), deadline: before.timers.get(t.timer).due, before: before }, i, w)", "w", "core.qnt"],
  ["core-system-waits-window", "ядро: системный переход ждёт конца окна, переход по таймеру не идёт первым (RULE-67)", "t.trigger == \"system\" or sys or moment(t, i) + GRACE_MS <= clock", "t.trigger == \"system\" or moment(t, i) + GRACE_MS <= clock", "core.qnt"],
  ["core-continues-ignored", "ядро: «Передать», «Отклонить» в окне отменяют автоэскалацию, хотя реакция продолжается (RULE-83)", "        not(CONTINUES_ON.get(t.timer).contains(tid)),\n", "        true,\n", "core.qnt"],
  // Порядка по моменту (RULE-41) и момента молчания не раньше последнего перехода (BUG-76) здесь нет: они нужны
  // после простоя сервиса, а модель шагает от события к событию — в её шагах порча ничего не меняет (20 000
  // историй). Порядок проверяет мутация кода tick-array-order и тесты API «прыжок часов»
  ["core-merge-primary-no-window", "ядро: у основного, которого берут при объединении, окно не учитывается (BUG-62)", "val pc = if (taking) canceledBy(TAKE_WITH, p) else []", "val pc = if (false) canceledBy(TAKE_WITH, p) else []", "core.qnt"],
];
// Порчи выражений машины — общий список с тестами API (tools/mutations/machine.json, PROC-75), затем порчи ручных частей
// Порча с пометкой model — модель её не проверяет (вне модели, мир модели, эквивалентна, кандидат в инвариант): пропускается
const ALL = [...JSON.parse(fs.readFileSync(path.join(ROOT, "tools/mutations/machine.json"), "utf8")).map((m) => [m.name, m.what, m.find, m.replace, null, m.model]), ...MUTATIONS];

const args = process.argv.slice(2);
const total = PROFILES.reduce((s, p) => s + p.samples, 0);
const want = Number((args.find((a) => a.startsWith("--samples=")) || `--samples=${total}`).split("=")[1]);
const profiles = PROFILES.map((p) => ({ ...p, samples: Math.max(1, Math.round((p.samples * want) / total)) }));
// Одновременно — четверть ядер: quint без зерна сам считает во все ядра, больше порч разом — только теснота и память
// (23 мин и обрыв quint при трёх четвертях ядер, PROC-75)
const jobs = Math.max(1, Number((args.find((a) => a.startsWith("--jobs=")) || "").split("=")[1]) || Math.floor(os.cpus().length / 4));
// K-я из M частей, как у мутаций кода (tools/parallel.py): номера k-1, k-1+m, … — для матрицы CI
const [shardK, shardM] = ((args.find((a) => a.startsWith("--shard=")) || "--shard=1/1").split("=")[1]).split("/").map(Number);
const only = args.filter((a) => !a.startsWith("--"));
const src = fs.readFileSync(MACHINE, "utf8");
// Инварианты — конъюнкты inv модели: их quint проверяет по отдельности и называет нарушенные
const qsrc = fs.readFileSync(path.join(Q, "im.qnt"), "utf8");
const INVARIANTS = qsrc.slice(qsrc.indexOf("  val inv = all {")).split("\n  }")[0].split("\n").slice(1).map((l) => l.trim().replace(/,$/, "")).filter(Boolean);

// Процесс целиком: код выхода и весь вывод
function run(cmd, argv, cwd) {
  return new Promise((resolve) => {
    const p = spawn(cmd, argv, { cwd });
    let out = "";
    p.stdout.on("data", (d) => (out += d));
    p.stderr.on("data", (d) => (out += d));
    p.on("close", (status, signal) => resolve({ status, signal, out }));
  });
}

// Модель в каталоге: истории по профилям до первого нарушения, затем сценарии. Итог — что поймало, или ошибка quint
async function judge(dir) {
  for (const p of profiles) {
    // --verbosity=1: без примера истории — итог, нарушенные инварианты и зерно; длинный вывод в трубу quint обрывал
    // раньше строки итога (ERROR relink-forgets-group, PROC-75)
    const r = await run("quint", ["run", "im.qnt", "--invariants", ...INVARIANTS, `--max-samples=${p.samples}`, `--max-steps=${STEPS}`, `--init=${p.init}`, `--step=${p.step}`, "--verbosity=1"], dir);
    if (/\[violation\]/.test(r.out)) return { by: "inv", names: [...r.out.matchAll(/^\s*❌ (\w+)/gm)].map((m) => m[1]), profile: p.name };
    if (!/\[ok\]/.test(r.out)) return { error: `quint run, профиль «${p.name}», ${r.signal ? `сигнал ${r.signal}` : `код ${r.status}`}: ${r.out.trim().split("\n").slice(-3).join(" ").slice(-300)}` };
  }
  const test = await run("quint", ["test", "im_test.qnt"], dir);
  const failed = [...test.out.matchAll(/^\s+\d+\) (\w+) failed/gm)].map((m) => m[1]);
  if (failed.length) return { by: "test", names: failed };
  if (test.status !== 0) return { error: `quint test, ${test.signal ? `сигнал ${test.signal}` : `код ${test.status}`}: ${test.out.trim().split("\n").slice(-3).join(" ").slice(-300)}` };
  return { by: null };
}

// Каталог с моделью из машины и ручных частей (испорченных или нет)
function prepare(machineText, part, partText) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "quint-mut-"));
  fs.writeFileSync(path.join(dir, "machine.json"), machineText);
  fs.cpSync(path.join(Q, "src"), path.join(dir, "src"), { recursive: true });
  if (part) fs.writeFileSync(path.join(dir, "src", part), partText);
  fs.copyFileSync(path.join(Q, "im_test.qnt"), path.join(dir, "im_test.qnt"));
  try {
    execFileSync("node", [path.join(ROOT, "tools/gen_quint.mjs"), `--machine=${path.join(dir, "machine.json")}`, `--src=${path.join(dir, "src")}`, `--out=${path.join(dir, "im.qnt")}`], { stdio: "pipe" });
  } catch (e) {
    // Сборка модели отказала (например, неизвестное имя в выражении): порчу поймал генератор, как поймал бы check_cel.mjs
    fs.rmSync(dir, { recursive: true, force: true });
    return { refused: (String(e.stderr).match(/^Error: (.*)$/m) || [, String(e.stderr).trim().split("\n").pop()])[1] };
  }
  return dir;
}

// Контроль: без порчи — ни нарушений, ни упавших сценариев
async function control() {
  const dir = prepare(src);
  if (dir.refused) return { line: `ERROR контроль без порчи — сборка модели отказала: ${dir.refused}`, bad: true };
  try {
    const r = await judge(dir);
    if (r.error) return { line: `ERROR контроль без порчи — ${r.error}`, bad: true };
    if (r.by) return { line: `ERROR контроль без порчи — поймано то, чего нет: ${r.by === "inv" ? "инварианты" : "сценарии"} ${r.names.join(", ")}`, bad: true };
    return { line: "OK  контроль без порчи — нарушений нет, сценарии проходят", bad: false };
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

// Одна порча: строка итога, поймана ли и чем
async function check([name, what, find, replace, part, skip]) {
  if (skip) return { line: `SKIP ${name}: ${skip}`, bad: false, skip: true };
  const text = part ? fs.readFileSync(path.join(Q, "src", part), "utf8") : src;
  if (text.split(find).length !== 2) return { line: `STALE ${name}: в ${part ? `src/${part}` : "машине"} не найдено место порчи (или оно не одно)`, bad: true };
  const dir = prepare(part ? src : src.replace(find, replace), part, part ? text.replace(find, replace) : null);
  if (dir.refused) return { line: `OK  ${name}${what ? ` — ${what}` : ""}: сборка модели отказала — ${dir.refused}`, bad: false, inv: [] };
  try {
    const r = await judge(dir);
    if (r.error) return { line: `ERROR ${name} — ${r.error}`, bad: true };
    if (r.by === "inv") return { line: `OK  ${name}${what ? ` — ${what}` : ""}: инвариант ${r.names.join(", ")} (профиль «${r.profile}»)`, bad: false, inv: r.names };
    if (r.by === "test") return { line: `OK  ${name}${what ? ` — ${what}` : ""}: сценарии ${r.names.join(", ")}`, bad: false, inv: [] };
    return { line: `BAD ${name}${what ? ` — ${what}` : ""}: ни инвариант, ни сценарий не поймали`, bad: true };
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

const todo = ALL.filter(([name]) => !only.length || only.includes(name)).filter((m, i) => i % shardM === shardK - 1);
// Сначала — один короткий прогон: при первом запуске quint скачивает вычислитель (~/.quint/rust-evaluator-…) без
// блокировки, и одновременные первые прогоны на чистом раннере падают на недокачанном архиве — в CI так выглядели
// «пойманными сценариями» 21 порча из 33, хотя quint просто не запустился
{
  const warm = await run("quint", ["run", "im.qnt", "--invariant", "inv", "--max-samples=1", "--max-steps=1"], Q);
  if (!/\[ok\]/.test(warm.out)) {
    console.log(`ERROR quint не запускается: ${warm.out.trim().split("\n").slice(-3).join(" ")}`);
    process.exit(1);
  }
}
const base = control();
const results = new Array(todo.length);
let next = 0;
let printed = 0;
async function worker() {
  while (next < todo.length) {
    const i = next++;
    results[i] = await check(todo[i]);
    // В порядке списка: печатается всё готовое подряд
    while (printed < todo.length && results[printed]) console.log(results[printed++].line);
  }
}
await Promise.all(Array.from({ length: Math.min(jobs, todo.length) }, worker));
const ctl = await base;
console.log(ctl.line);
// Какие инварианты какие порчи ловят; не поймавший ни одной — может быть пустым (А2-25)
const caught = Object.fromEntries(INVARIANTS.map((n) => [n, []]));
todo.forEach(([name], i) => (results[i].inv || []).forEach((n) => caught[n] && caught[n].push(name)));
if (!only.length && shardM === 1) {
  console.log("\nИнвариант → порчи, которые он поймал:");
  for (const [n, ms] of Object.entries(caught)) console.log(`  ${n}: ${ms.length ? ms.join(", ") : "—"}`);
  const none = Object.keys(caught).filter((n) => !caught[n].length);
  if (none.length) console.log(`Инварианты без пойманных порч (своей порчи нет или её ловит другой первым): ${none.join(", ")}`);
}
// Кто поймал — для таблицы «порча → модель / тесты API» (tools/mutation_table.py): только из действительного прогона;
// части (--shard) и выборки дописывают свои порчи к прежним
if (!ctl.bad && !results.some((r) => r.line.startsWith("ERROR"))) {
  const file = path.join(ROOT, "tools/mutations/quint-catchers.json");
  const known = new Set(ALL.map(([name]) => name));
  const prev = fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, "utf8")) : {};
  const next = Object.fromEntries(Object.entries(prev).filter(([n]) => known.has(n)));
  todo.forEach(([name], i) => {
    const r = results[i];
    if (r.skip) return;
    next[name] = r.line.startsWith("OK") ? r.line.slice(r.line.lastIndexOf(": ") + 2) : null;
  });
  const sorted = Object.fromEntries(Object.keys(next).sort().map((n) => [n, next[n]]));
  fs.writeFileSync(file, JSON.stringify(sorted, null, 1) + "\n");
}
const failed = results.filter((r) => r.bad).length;
console.log(`Порч машины, которых модель не поймала: ${results.filter((r) => r.line.startsWith("BAD") || r.line.startsWith("STALE")).length}; пропущено по пометке model: ${results.filter((r) => r.skip).length}`);
if (ctl.bad || results.some((r) => r.line.startsWith("ERROR"))) console.log("Прогон недействителен — контроль без порчи не прошёл или quint не разобрал модель");
process.exit(failed || ctl.bad ? 1 : 0);
