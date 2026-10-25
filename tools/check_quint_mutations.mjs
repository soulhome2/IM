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

// имя, что портится, найти, заменить — текст машины (выражения CEL в JSON); пятое поле — ручная часть модели
// (quint/src/…): порча ядра или мира, машина не меняется (PROC-45)
const MUTATIONS = [
  ["level-current-addressee", "эскалация не пропускает уровень текущего адресата (RULE-93)", "l.target != addressee(x) && canAcceptNow(", "canAcceptNow("],
  ["level-signed-out", "эскалация отдаёт вышедшему, у кого в группе никого (RULE-100)", "&& canAcceptNow(l.target, x, x.owner))", "&& canAccept(l.target, x, x.owner))"],
  ["level-no-duty-group", "эскалация пропускает вышедшего, хотя в его дежурной группе есть кому принять (RULE-100, PROC-50)", "(signedIn(who) || cel.bind(g, dutyGroupOf(who), g != '' && members(g).exists(m, m != except && m != who && signedIn(m) && canAcceptPerson(m, x))))", "signedIn(who)"],
  ["level-group-owner", "эскалация считает в группе и владельца (RULE-93)", "canAcceptNow(l.target, x, x.owner)", "canAcceptNow(l.target, x, '')"],
  ["breach-at-now", "нарушение датируется моментом записи, а не дедлайном (§10.1, правило 5; PROC-51)", "'at': deadline, 'owner': addressee(before)", "'at': now, 'owner': addressee(before)"],
  ["breach-no-owner", "нарушение записывается ни на кого", "'owner': addressee(before)", "'owner': ''"],
  ["group-breach-not-shared", "нарушение основного привязанным не записывается (RULE-97)", "groupMembersAt(incident, deadline)", "[]"],
  ["window-left-not-in-group", "отсоединённый в окне после срока группы — не в группе (BUG-73)", " || (e.leftGroup.primaryId == p.id && e.leftGroup.linkedAt <= at && e.leftGroup.at >= at)", ""],
  ["detach-window-not-spent", "отсоединённый после наступившего срока группы — с неотработанным остатком 0 (BUG-75)", "\"if\": \"leftOf(ps[0], timerId, now) == 0\"", "\"if\": \"spent(ps[0], timerId, now)\""],
  ["detach-at-deadline-out", "отсоединённый в миг срока группы — не в группе (BUG-75)", "e.leftGroup.at >= at", "e.leftGroup.at > at"],
  ["active-limit", "лимит активных пропускает лишний", "countMine(me, 'in_progress', incident.id) < limits.maxActive\"", "countMine(me, 'in_progress', incident.id) <= limits.maxActive\""],
  ["relink-off", "привязанные объединяемого новому основному не переходят", "\"in\": \"linkedOf(incident.id).filter(e, !isDone(e))\"", "\"in\": \"[]\""],
  ["scenario-ignored", "объединяются инциденты разных сценариев", "\"expr\": \"cel.bind(ps, incidentById(form.primaryId), size(ps) > 0 && ps[0].scenario == incident.scenario)\"", "\"expr\": \"true\""],
  ["reopen-keeps-closed-at", "«Переоткрыть» оставляет время закрытия (RULE-103)", "{ \"kind\": \"transactional\", \"fn\": \"setFlag\", \"args\": [\"closedAt\", \"0\"] },", ""],
  ["processed-without-steps", "«Обработан» без пройденного сценария", "\"expr\": \"i.requiredStepSet == 'none' || stepsFilled(x, i.requiredStepSet)\"", "\"expr\": \"true\""],
  ["lost-access-ignored", "потеря доступа адресата не замечается (RULE-71)", "\"expr\": \"addressee(incident) != '' && hasAccess(addressee(incident), incident) == expected\"", "\"expr\": \"addressee(incident) != '' && true == expected\""],
  ["pause-not-paused", "«на паузе» не отмечается — остаток теряется", `{"set": "${T}.paused", "value": "true"}, {"set": "${T}.due", "value": "0"}`, `{"set": "${T}.paused", "value": "false"}, {"set": "${T}.due", "value": "0"}`],
  ["no-link-no-deadline", "у «Нет связи» снова нет срока: связь вернулась — отложенный лежит бесконечно (RULE-118, RULE-129)", "rs[0].deadlineFromIdle ? (", "false ? ("],
  ["hold-idle-threshold", "«нет связи» у «В работе» — по порогу возврата в очередь, а не удержания (П2)", "{ \"fn\": \"agentIdleFor\", \"args\": [\"session.idleHoldSec\"] }", "{ \"fn\": \"agentIdleFor\", \"args\": [\"session.idleReleaseSec\"] }"],
  ["core-timer-late", "ядро: часы не останавливаются в конце окна — переход по таймеру опаздывает (П1)", ".union(ds.map(d => d + GRACE_MS))", "", "core.qnt"],
  ["core-window-no-breach", "ядро: ручное действие в окне отменяет переход по таймеру без нарушения (RULE-63, BUG-62)", "windowBreach(t.id, { ...ctx(DISPATCHER, DISPATCHER, NO_FORM, \"\"), deadline: before.timers.get(t.timer).due, before: before }, i, w)", "w", "core.qnt"],
  ["core-system-waits-window", "ядро: системный переход ждёт конца окна, переход по таймеру не идёт первым (RULE-67)", "t.trigger == \"system\" or sys or moment(t, i) + GRACE_MS <= clock", "t.trigger == \"system\" or moment(t, i) + GRACE_MS <= clock", "core.qnt"],
  ["core-continues-ignored", "ядро: «Передать», «Отклонить» в окне отменяют автоэскалацию, хотя реакция продолжается (RULE-83)", "        not(CONTINUES_ON.get(t.timer).contains(tid)),\n", "        true,\n", "core.qnt"],
  // Порядка по моменту (RULE-41) и момента молчания не раньше последнего перехода (BUG-76) здесь нет: они нужны
  // после простоя сервиса, а модель шагает от события к событию — в её шагах порча ничего не меняет (20 000
  // историй). Порядок проверяет мутация кода tick-array-order и тесты API «прыжок часов»
  ["core-merge-primary-no-window", "ядро: у основного, которого берут при объединении, окно не учитывается (BUG-62)", "val pc = if (taking) canceledBy(TAKE_WITH, p) else []", "val pc = if (false) canceledBy(TAKE_WITH, p) else []", "core.qnt"],
  ["resume-refires", "отработанный норматив при возврате в работу — новый срок (RULE-50)", `${T}.fired != 0 ? ${T}.fired : now + left`, "false ? 0 : now + left"],
  // Выжившие порчи консилиума verification-audit 2026-10-24 (PROC-73): правила права на действие и двух соседних состояний
  ["hold-no-owner", "«Отложить» чужой инцидент — без условия «я владелец» (§6.1, К1)", "{ \"fn\": \"hasPermission\", \"args\": [\"incident:hold\"] },\n        { \"fn\": \"isOwner\" },\n", "{ \"fn\": \"hasPermission\", \"args\": [\"incident:hold\"] },\n"],
  ["transfer-restarts-reaction", "передача из «Новое» и «Ожидает принятия» запускает реакцию заново — передачами её не продлить (§4, §6.1, RULE-83)", "\"args\": [\"reaction\", \"byEscalationLevel\", true] },\n        { \"kind\": \"transactional\", \"fn\": \"appendLog\", \"args\": [\"workflow.journal.transfer\"] }", "\"args\": [\"reaction\", \"byEscalationLevel\"] },\n        { \"kind\": \"transactional\", \"fn\": \"appendLog\", \"args\": [\"workflow.journal.transfer\"] }"],
  ["claim-on-break", "«Взять» на перерыве и после выхода (§10.1, правило 2)", "{ \"fn\": \"hasPermission\", \"args\": [\"incident:claim\"] },\n        { \"fn\": \"agentReady\" },\n        { \"fn\": \"withinActiveLimit\" }", "{ \"fn\": \"hasPermission\", \"args\": [\"incident:claim\"] },\n        { \"fn\": \"withinActiveLimit\" }"],
  ["close-on-break", "«Закрыть» на перерыве и после выхода (§10.1, правило 2)", "{ \"fn\": \"agentReady\" },\n        { \"fn\": \"closeResultAllowed\" }", "{ \"fn\": \"closeResultAllowed\" }"],
  ["mass-foreign-on-hold", "«Массовый сбой» из чужого «Отложен» (§2.2, §6.1)", "\"ownerOnlyInStates\": [\"in_progress\", \"on_hold\"],", "\"ownerOnlyInStates\": [\"in_progress\"],"],
  ["break-skipped-by-escalation", "эскалация пропускает адресата на перерыве — он инцидент получает (§8.3, §12.1)", "\"expr\": \"agentState(who) != 'offline'\", \"$comment\": \"§12.1. Человек вошёл", "\"expr\": \"agentState(who) == 'ready'\", \"$comment\": \"§12.1. Человек вошёл"],
  ["reopen-no-window", "«Переоткрыть» после срока переоткрытия (§6.1, §10.1, BUG-31)", "\"expr\": \"now - incident.closedAt <= limits.reopenWindowMin * 60000\"", "\"expr\": \"true\""],
  // Потолок эскалации (PROC-74, А1-03): видна только при maxLevel меньше числа уровней — состав уровней перебирает init
  ["level-ceiling-ignored", "автоэскалация не смотрит на потолок maxLevel (§8.3)", "l.level > x.escalationLevel && l.level <= escalation.maxLevel && ", "l.level > x.escalationLevel && "],
];

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
    const r = await run("quint", ["run", "im.qnt", "--invariants", ...INVARIANTS, `--max-samples=${p.samples}`, `--max-steps=${STEPS}`, `--init=${p.init}`, `--step=${p.step}`], dir);
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
  execFileSync("node", [path.join(ROOT, "tools/gen_quint.mjs"), `--machine=${path.join(dir, "machine.json")}`, `--src=${path.join(dir, "src")}`, `--out=${path.join(dir, "im.qnt")}`], { stdio: "ignore" });
  return dir;
}

// Контроль: без порчи — ни нарушений, ни упавших сценариев
async function control() {
  const dir = prepare(src);
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
async function check([name, what, find, replace, part]) {
  const text = part ? fs.readFileSync(path.join(Q, "src", part), "utf8") : src;
  if (text.split(find).length !== 2) return { line: `STALE ${name}: в ${part ? `src/${part}` : "машине"} не найдено место порчи (или оно не одно)`, bad: true };
  const dir = prepare(part ? src : src.replace(find, replace), part, part ? text.replace(find, replace) : null);
  try {
    const r = await judge(dir);
    if (r.error) return { line: `ERROR ${name} — ${r.error}`, bad: true };
    if (r.by === "inv") return { line: `OK  ${name} — ${what}: инвариант ${r.names.join(", ")} (профиль «${r.profile}»)`, bad: false, inv: r.names };
    if (r.by === "test") return { line: `OK  ${name} — ${what}: сценарии ${r.names.join(", ")}`, bad: false, inv: [] };
    return { line: `BAD ${name} — ${what}: ни инвариант, ни сценарий не поймали`, bad: true };
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

const todo = MUTATIONS.filter(([name]) => !only.length || only.includes(name)).filter((m, i) => i % shardM === shardK - 1);
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
const failed = results.filter((r) => r.bad).length;
console.log(`Порч машины, которых модель не поймала: ${results.filter((r) => r.line.startsWith("BAD") || r.line.startsWith("STALE")).length}`);
if (ctl.bad || results.some((r) => r.line.startsWith("ERROR"))) console.log("Прогон недействителен — контроль без порчи не прошёл или quint не разобрал модель");
process.exit(failed || ctl.bad ? 1 : 0);
