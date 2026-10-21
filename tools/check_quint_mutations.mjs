// Порчи машины для модели Quint (ARCH-07.6): в копии машины портится одно выражение, модель генерируется
// заново (tools/gen_quint.mjs), и её инварианты (quint run) или сценарии (quint test) должны порчу поймать.
// Не поймали — инварианты и сценарии этого правила не проверяют. Нужен quint в PATH.
// Порчи независимы — каждая в своём каталоге — и идут одновременно (PROC-41): --jobs=N, по умолчанию три
// четверти ядер, как у мутаций кода (tools/parallel.py); итог печатается в порядке списка.
// Запуск из корня репозитория: node tools/check_quint_mutations.mjs [имя …] [--samples=N] [--jobs=N]
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync, spawn } from "node:child_process";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const MACHINE = path.join(ROOT, "Specification/Workflow_machine/workflow_schema.v1.json");
const Q = path.join(ROOT, "Specification/Workflow_machine/quint");
const T = "incident.timers[timerId]";

// имя, что портится, найти, заменить — текст машины (выражения CEL в JSON)
const MUTATIONS = [
  ["level-current-addressee", "эскалация не пропускает уровень текущего адресата (RULE-93)", "l.target != addressee(x) && canAccept(", "canAccept("],
  ["level-group-owner", "эскалация считает в группе и владельца (RULE-93)", "canAccept(l.target, x, x.owner)", "canAccept(l.target, x, '')"],
  ["breach-no-owner", "нарушение записывается ни на кого", "'owner': addressee(before)", "'owner': ''"],
  ["group-breach-not-shared", "нарушение основного привязанным не записывается (RULE-97)", "incidents.filter(e, e.id != incident.id && inGroupAt(e, incident, deadline))", "[]"],
  ["window-left-not-in-group", "отсоединённый в окне после срока группы — не в группе (BUG-73)", " || (e.leftGroup.primaryId == p.id && e.leftGroup.linkedAt <= at && e.leftGroup.at >= at)", ""],
  ["detach-window-not-spent", "отсоединённый после наступившего срока группы — с неотработанным остатком 0 (BUG-75)", "\"if\": \"leftOf(ps[0], timerId, now) == 0\"", "\"if\": \"spent(ps[0], timerId, now)\""],
  ["detach-at-deadline-out", "отсоединённый в миг срока группы — не в группе (BUG-75)", "e.leftGroup.at >= at", "e.leftGroup.at > at"],
  ["active-limit", "лимит активных пропускает лишний", "size(mineIn(incidents, me, 'in_progress', incident.id)) < limits.maxActive\"", "size(mineIn(incidents, me, 'in_progress', incident.id)) <= limits.maxActive\""],
  ["relink-off", "привязанные объединяемого новому основному не переходят", "\"in\": \"incidents.filter(e, e.linkedTo == incident.id && !isDone(e))\"", "\"in\": \"[]\""],
  ["scenario-ignored", "объединяются инциденты разных сценариев", "\"expr\": \"cel.bind(ps, byId(incidents, form.primaryId), size(ps) > 0 && ps[0].scenario == incident.scenario)\"", "\"expr\": \"true\""],
  ["processed-without-steps", "«Обработан» без пройденного сценария", "\"expr\": \"i.requiredStepSet == 'none' || stepsFilled(x, i.requiredStepSet)\"", "\"expr\": \"true\""],
  ["lost-access-ignored", "потеря доступа адресата не замечается (RULE-71)", "\"expr\": \"addressee(incident) != '' && hasAccess(addressee(incident), incident) == expected\"", "\"expr\": \"addressee(incident) != '' && true == expected\""],
  ["pause-not-paused", "«на паузе» не отмечается — остаток теряется", `{"set": "${T}.paused", "value": "true"}, {"set": "${T}.due", "value": "0"}`, `{"set": "${T}.paused", "value": "false"}, {"set": "${T}.due", "value": "0"}`],
  ["resume-refires", "отработанный норматив при возврате в работу — новый срок (RULE-50)", `${T}.fired != 0 ? ${T}.fired : now + left`, "false ? 0 : now + left"],
];

const args = process.argv.slice(2);
const samples = Number((args.find((a) => a.startsWith("--samples=")) || "--samples=3000").split("=")[1]);
const jobs = Math.max(1, Number((args.find((a) => a.startsWith("--jobs=")) || "").split("=")[1]) || Math.floor((os.cpus().length * 3) / 4));
const only = args.filter((a) => !a.startsWith("--"));
const src = fs.readFileSync(MACHINE, "utf8");

// Процесс целиком: код выхода и весь вывод
function run(cmd, argv, cwd) {
  return new Promise((resolve) => {
    const p = spawn(cmd, argv, { cwd });
    let out = "";
    p.stdout.on("data", (d) => (out += d));
    p.stderr.on("data", (d) => (out += d));
    p.on("close", (status) => resolve({ status, out }));
  });
}

// Одна порча: строка итога и поймана ли
async function check([name, what, find, replace]) {
  if (src.split(find).length !== 2) return { line: `STALE ${name}: в машине не найдено место порчи (или оно не одно)`, bad: true };
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "quint-mut-"));
  try {
    fs.writeFileSync(path.join(dir, "machine.json"), src.replace(find, replace));
    fs.copyFileSync(path.join(Q, "im_test.qnt"), path.join(dir, "im_test.qnt"));
    execFileSync("node", [path.join(ROOT, "tools/gen_quint.mjs"), `--machine=${path.join(dir, "machine.json")}`, `--out=${path.join(dir, "im.qnt")}`], { stdio: "ignore" });
    const inv = await run("quint", ["run", "im.qnt", "--invariant", "inv", `--max-samples=${samples}`, "--max-steps=40"], dir);
    const byInv = /\[violation\]/.test(inv.out);
    const test = byInv ? null : await run("quint", ["test", "im_test.qnt"], dir);
    const byTest = test && test.status !== 0;
    const failedTests = test ? [...test.out.matchAll(/^\s+\d+\) (\w+) failed/gm)].map((m) => m[1]) : [];
    if (byInv || byTest) return { line: `OK  ${name} — ${what}: ${byInv ? "инвариант" : `сценарии ${failedTests.join(", ")}`}`, bad: false };
    return { line: `BAD ${name} — ${what}: ни инвариант, ни сценарий не поймали`, bad: true };
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

const todo = MUTATIONS.filter(([name]) => !only.length || only.includes(name));
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
const failed = results.filter((r) => r.bad).length;
console.log(`Порч машины, которых модель не поймала: ${failed}`);
process.exit(failed ? 1 : 0);
