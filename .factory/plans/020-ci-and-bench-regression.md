# Plan 020: CI runs the proof, the tests, native builds, the docs build and a benchmark that fails on regression

> **Executor instructions**: Deliver the stated outcome within scope. Adapt routine
> implementation details to current code, preserve the listed contracts, and run
> the relevant acceptance checks. Fix task-caused failures and recheck affected
> behavior. Escalate only the material conditions below. Update the plan's status
> in `.factory/plans/README.md`.
>
> **Drift check**: `git diff --stat cea6656 -- bench/ .github/ docs/package.json`
> should be empty (019 adds `tests/`; fine).

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED (depends on installing Bend on a hosted Linux runner, which has never been tried here)
- **Depends on**: `.factory/plans/019-test-injection.md` (CI runs `bend tests/*.bend`)
- **Category**: dx (roadmap Tier 6: "Benchmark suite in CI so you catch regressions")
- **Planned at**: commit `cea6656`, 2026-09-22, clean tree

## Why this matters

There is no CI (`.github/` does not exist). The gate `bend PROOF.bend` and
the native builds that catch C-name collisions (plan 016's finding) run
only when someone remembers. Throughput has already regressed silently
twice: 30.4k → 17.5k GET req/s from the shield's bytes (plan 013), and a
four-draw request id that cost 20% (plan 014). Both were found only
because a human benchmarked by hand (`bench/README.md`). This plan adds
one workflow: the proof, the tests, native builds of both examples, the
docs build, and a benchmark that compares the PR against `main` on the
same runner and fails past a threshold.

## Decisions

- **GitHub Actions** (the repo is `github.com/victor-teles/air-bend`), one
  workflow `.github/workflows/ci.yml`, triggered on `pull_request` and
  `push` to `main`. Jobs: `proof` (`bend PROOF.bend`), `tests`
  (`bend tests/*.bend`, one step per file), `native` (build both examples
  with `-o`), `docs` (`pnpm install --frozen-lockfile && pnpm build` in
  `docs/`), `bench` (below). All on `ubuntu-latest`.
- **Installing Bend**: the guide's installer,
  `curl -fsSL https://bend-lang.com/install.sh | sh`, puts `bend` in
  `~/.bend/bin` (add it to `$GITHUB_PATH`). Pin the version if the
  installer supports it. Look at the script before using it. The local
  toolchain is 2.0.19 and 2.0.25 is out. If it cannot be pinned, print
  `bend version` in every job so a toolchain change shows in the log.
  Cache `~/.bend` with the version as the key when pinning works.
- **Benchmark as an A/B on one runner, not an absolute number.** Shared
  runners vary by ±20% between machines, so a stored baseline would flake.
  The `bench` job (PRs only) checks out `main` into a second worktree,
  builds both hello binaries natively, and runs them alternately:
  `main`, PR, `main`, PR, 3 rounds of 5 s each at 32 connections on
  `GET /hello/world` and `POST /echo` 1 KB. It then compares medians. The
  job **fails when the PR's median GET or POST req/s is below 85% of
  `main`'s**, and always prints a Markdown table to the step summary
  (`$GITHUB_STEP_SUMMARY`). Keep the threshold in one variable in the
  script.
- **`bench/bench.mjs` gains `--json`**: print one JSON object
  (`{"rps":…,"p50":…,"p99":…,"errors":…}`) instead of the human text, so
  the comparer does not scrape. The human output is unchanged without the
  flag.
- **`bench/ab.sh <base-bin> <head-bin>`** (new) runs the alternation and
  writes `bench/out/ab.json`. **`bench/compare.mjs`** (new, dependency-free
  Node) reads it, prints the table and exits 1 on regression. `run.sh`
  stays as the local human tool.
- The Node reference server is not benchmarked in CI. It is a local
  comparison, not a gate.

## Current state

- `bench/run.sh`: builds `examples/hello/main.bend` natively to
  `bench/out/hello`, runs it on 8080 and `bench/reference.mjs` on 8081,
  then runs `bench/bench.mjs` against each. Hello listens on a fixed
  port 8080 (`examples/hello/main.bend`: `Air.serve(~app, 8080)`), so an
  A/B must run the two binaries **one at a time**, not side by side.
  Alternatively, make the port come from `PORT`: plan 021 does that for
  the examples. If 021 has landed, run them side by side. If not,
  sequential is fine.
- `bench/bench.mjs`: args `--url --conns --seconds --method --body --close`.
  It prints throughput, latency percentiles, statuses and errors.
- Runtime note from `bench/README.md`: the listen backlog is 16
  (`effs/tcp_listen.c`), so keep `--conns 32` as the README runs do.
- The server prints `air: listening on http://localhost:8080` when ready.
  Wait for that line (poll the log or `curl` in a loop) instead of a fixed
  `sleep 2`.
- `docs/`: pnpm project (`pnpm-lock.yaml` present), `pnpm build` =
  `next build`. Check `docs/package.json` for the `packageManager` field
  and pin pnpm via `pnpm/action-setup` accordingly.
- Native builds need a C compiler (`bend x.bend -o out` emits C and
  compiles it). `ubuntu-latest` ships gcc. Confirm `bend` finds it.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Proof | `bend PROOF.bend` | `All terms check.` |
| Tests | `bend tests/hello.bend` | exit 0 |
| Native | `bend examples/hello/main.bend -o bench/out/hello` | exit 0 |
| JSON bench | `node bench/bench.mjs --url http://localhost:8080/hello/world --conns 32 --seconds 5 --json` | one JSON line |
| A/B locally | `bench/ab.sh bench/out/hello bench/out/hello && node bench/compare.mjs bench/out/ab.json` | table, exit 0 (same binary twice) |
| Regression demo | build a binary with an artificial slowdown (e.g. a middleware that renders a 4 KB string per request) and A/B it | exit 1 |
| Workflow lint | `actionlint .github/workflows/ci.yml` if installed; otherwise review by eye | no errors |

## Implementation rules relevant to this plan

- Shell scripts follow `bench/run.sh`: `set -euo pipefail`, `cd "$(dirname "$0")/.."`,
  a `trap cleanup EXIT` that kills servers.
- Node scripts: no dependencies, ES modules, like `bench/bench.mjs`.
- Do not commit binaries. `bench/out/` should already be ignored; check
  `.gitignore`.
- The workflow must not need secrets. It publishes nothing and does not
  deploy.

## Scope

**In scope**: `.github/workflows/ci.yml` (new), `bench/bench.mjs`
(`--json`), `bench/ab.sh` (new), `bench/compare.mjs` (new),
`bench/README.md` (a "CI" section), `docs/content/docs/project/checks.mdx`
and `benchmarks.mdx` (what CI runs), `roadmap.md` tick, index row.

**Out of scope**: benchmarking the dashboard, streaming, or many routes
(add later as more `ab.sh` targets), storing history, posting PR comments
(needs a token with write access; the step summary is enough), macOS
runners.

## Steps

### Step 1: `--json`, `ab.sh`, `compare.mjs`, run locally

Run the A/B with the same binary on both sides three times. Record the
spread you see. If the same binary ever differs by more than 10%, raise
the rounds or seconds before settling the 85% threshold, and write down
why.

### Step 2: the workflow

Jobs `proof`, `tests`, `native`, `docs` run in parallel. `bench` needs
`native` to pass first. It checks out `main` with `git worktree add`
(fetch depth 0), builds both, and runs `ab.sh` and `compare.mjs`.

### Step 3: prove it on GitHub

Pushing and opening a PR are outward-facing. Do it only if the operator
authorized pushing for this task. Otherwise stop after local checks and
report that the workflow is unverified on GitHub. With authorization: open
a draft PR and confirm all jobs go green and the summary table appears.
Then push a throwaway commit with the artificial slowdown, confirm `bench`
fails, and drop the commit.

## Test plan

- Local: the same-binary A/B passes, the slowdown A/B fails, `--json`
  output parses.
- GitHub (if authorized): green run, red run on the slowdown.

## Done criteria

- [ ] `node bench/compare.mjs` exits 0 on same-binary A/B and 1 on the slowdown A/B, locally.
- [ ] `.github/workflows/ci.yml` has the five jobs, and the bench job is PR-only.
- [ ] `bench/README.md` documents the CI A/B, threshold and noise observed.
- [ ] Either a green CI run on a draft PR is linked in the index row, or the row says "workflow unverified on GitHub: not authorized to push".
- [ ] Roadmap line ticked with a one-line note.

## STOP conditions

- The Bend installer does not work on `ubuntu-latest`: no Linux build, or
  interactive prompts. Report with the log. Do not vendor a binary into
  the repo.
- `bend PROOF.bend` takes more than 15 minutes on the runner. Report the
  time. Splitting the proof is a separate decision.
- Same-binary A/B noise on the runner exceeds 15% even with more rounds.
  Then a gate would flake: ship the bench job as report-only
  (`continue-on-error: true`) and say so in the index.

## Maintenance notes

- A toolchain bump changes both sides of the A/B equally, so it does not
  trip the gate. That is the point of A/B.
- When a PR is meant to trade speed for a feature (like the shield did),
  the bench job fails by design. Document the escape hatch in
  `bench/README.md`: a `bench-accepted` label that the workflow checks
  with `contains(github.event.pull_request.labels.*.name, 'bench-accepted')`.
