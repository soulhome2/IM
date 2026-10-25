// Инварианты модели Quint и порог покрытия (PROC-72): случайные истории по профилям (tools/quint_profiles.mjs) с
// инвариантом inv и свидетелями — reached_<переход> у каждого перехода машины и premise_… у посылок инвариантов
// (quint/src/invariants.qnt). Свидетель считается в историях всех профилей вместе; встретился меньше чем в
// --min историях (по умолчанию 20) — задача падает: переход или посылка в прогоне почти не проверяются.
// Без --seed: с зерном quint считает в один поток, в 10 раз медленнее. Нарушение — история и зерно в выводе.
// Запуск из корня репозитория: node tools/check_quint_coverage.mjs [--min=N]. Нужен quint в PATH.
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { PROFILES, STEPS } from "./quint_profiles.mjs";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const Q = path.join(ROOT, "Specification/Workflow_machine/quint");
const opt = (name, dflt) => (process.argv.find((a) => a.startsWith(`--${name}=`)) || `=${dflt}`).split("=").slice(1).join("=");
const MIN = Number(opt("min", 20));

const WITNESSES = [...fs.readFileSync(path.join(Q, "im.qnt"), "utf8").matchAll(/^ {2}val ((?:reached|premise)_\w+) =/gm)].map((m) => m[1]);
if (!WITNESSES.some((w) => w.startsWith("premise_"))) {
  console.log("В im.qnt нет свидетелей посылок premise_… — quint/src/invariants.qnt");
  process.exit(1);
}

const seen = Object.fromEntries(WITNESSES.map((w) => [w, PROFILES.map(() => 0)]));
let failed = false;
PROFILES.forEach((p, k) => {
  const t0 = Date.now();
  const r = spawnSync(
    "quint",
    // --verbosity=1: без примера истории — длинный вывод в трубу quint обрывал раньше строки итога (PROC-75)
    ["run", "im.qnt", "--invariant", "inv", `--max-samples=${p.samples}`, `--max-steps=${STEPS}`, `--init=${p.init}`, `--step=${p.step}`, "--witnesses", ...WITNESSES, "--verbosity=1"],
    { cwd: Q, encoding: "utf8", maxBuffer: 1 << 28 }
  );
  const ok = (r.stdout.match(/^\[ok\].*$/m) || [])[0];
  if (r.status !== 0 || !ok) {
    console.log(`Профиль «${p.name}» (--init=${p.init} --step=${p.step}): нарушение или ошибка quint`);
    console.log(r.stdout, r.stderr);
    const seed = (r.stdout.match(/--seed=(0x[0-9a-f]+)/) || [])[1];
    if (seed) console.log(`История целиком: cd Specification/Workflow_machine/quint && quint run im.qnt --invariant inv --max-samples=${p.samples} --max-steps=${STEPS} --init=${p.init} --step=${p.step} --seed=${seed}`);
    failed = true;
    return;
  }
  for (const m of r.stdout.matchAll(/^(\w+) was witnessed in (\d+) trace/gm)) if (seen[m[1]]) seen[m[1]][k] = Number(m[2]);
  console.log(`Профиль «${p.name}», ${p.samples} историй по ${STEPS} шагов: ${ok.replace(/^\[ok\] /, "").replace(/\.$/, "")}, ${Math.round((Date.now() - t0) / 1000)} с`);
});
if (failed) process.exit(1);

const total = (w) => seen[w].reduce((a, b) => a + b, 0);
const rows = WITNESSES.slice().sort((a, b) => total(a) - total(b));
const low = rows.filter((w) => total(w) < MIN);
const width = Math.max(...rows.map((w) => w.length));
console.log(`\nВ скольких историях встретилось (${PROFILES.map((p) => p.name).join(" / ")} = всего), порог ${MIN}:`);
for (const w of rows) console.log(`  ${w.padEnd(width)}  ${seen[w].map((n) => String(n).padStart(5)).join(" ")}  = ${String(total(w)).padStart(5)}${total(w) < MIN ? "  НИЖЕ ПОРОГА" : ""}`);
console.log(`\nСвидетелей: ${rows.length}, ниже порога: ${low.length}${low.length ? ` — ${low.join(", ")}` : ""}`);
process.exit(low.length ? 1 : 0);
