// Compares an A/B run (bench/ab.sh) and fails on a regression. No dependencies.
//
//   node bench/compare.mjs [bench/out/ab.jsonl]
//
// For each target, the median req/s of head over the median of base. Exits 1
// when any ratio is under THRESHOLD (0.85 unless the env sets it), unless
// BENCH_ACCEPTED=true, which reports without failing. Prints a Markdown
// table, and appends it to $GITHUB_STEP_SUMMARY when that is set.

import { readFileSync, appendFileSync } from "node:fs";

const file = process.argv[2] ?? "bench/out/ab.jsonl";
const threshold = Number(process.env.THRESHOLD ?? 0.85);
const accepted = process.env.BENCH_ACCEPTED === "true";

const rows = readFileSync(file, "utf8").split("\n").filter(Boolean).map((l) => JSON.parse(l));
const median = (xs) => {
  const s = [...xs].sort((a, b) => a - b);
  const m = Math.floor(s.length / 2);
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
};
const spread = (xs) => (xs.length ? (Math.max(...xs) - Math.min(...xs)) / median(xs) : 0);

const targets = [...new Set(rows.map((r) => r.target))];
let failed = false;
const lines = [
  `| target | base req/s | head req/s | head/base | base spread | head spread | errors |`,
  `| --- | ---: | ---: | ---: | ---: | ---: | ---: |`,
];
for (const t of targets) {
  const side = (s) => rows.filter((r) => r.target === t && r.side === s);
  const base = side("base").map((r) => r.rps);
  const head = side("head").map((r) => r.rps);
  if (!base.length || !head.length) throw new Error(`${t}: missing base or head runs`);
  const ratio = median(head) / median(base);
  const errors = [...side("base"), ...side("head")].reduce((n, r) => n + r.errors, 0);
  const bad = ratio < threshold;
  failed ||= bad;
  lines.push(`| ${t} | ${median(base).toFixed(0)} | ${median(head).toFixed(0)} | ${ratio.toFixed(3)}${bad ? " ❌" : ""} | ${(spread(base) * 100).toFixed(1)}% | ${(spread(head) * 100).toFixed(1)}% | ${errors} |`);
}
const verdict = failed
  ? accepted
    ? `Regression below ${threshold} accepted by the \`bench-accepted\` label.`
    : `Regression: head is below ${threshold} of base. Add the \`bench-accepted\` label if the cost is intended.`
  : `No regression (threshold ${threshold}).`;
const report = ["### Benchmark: head vs base", "", ...lines, "", verdict, ""].join("\n");
console.log(report);
if (process.env.GITHUB_STEP_SUMMARY) appendFileSync(process.env.GITHUB_STEP_SUMMARY, report + "\n");
process.exit(failed && !accepted ? 1 : 0);
