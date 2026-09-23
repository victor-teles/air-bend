# Plan 021: Configuration from the environment and a `.env` file, with `serve_env`

> **Executor instructions**: Deliver the stated outcome within scope. Adapt routine
> implementation details to current code, preserve the listed contracts, and run
> the relevant acceptance checks. Fix task-caused failures and recheck affected
> behavior. Escalate only the material conditions below. Update the plan's status
> in `.factory/plans/README.md`.
>
> **Drift check**: `git diff --stat cea6656 -- air.bend air/lib/errors.bend air/lib/server.bend air/lib/store.bend`
> should be empty or routine (019 touches `server.bend`'s `refuse.go`; fine).

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none (019 recommended first, so the parser gets tests as well as laws)
- **Category**: dx (roadmap Tier 6: "Config + env handling")
- **Planned at**: commit `cea6656`, 2026-09-22, clean tree

## Why this matters

Ports, limits and timeouts are hard-coded in every `main`
(`Air.serve(~app, 8080)`), and the only setting read from the environment
is `AIR_ENV` (`Air.Env.from_env`). Deploying behind a platform that assigns
`PORT`, raising the body limit for an upload route, or keeping a database
URL out of the source means writing `IO.get_env` plumbing by hand, with
`Result` matching and digit parsing each time. This plan adds a small
`Config` module: typed reads with defaults that fail fast on malformed
numbers, a `.env` loader, settings visible to handlers through the store,
and `Air.serve_env(~app)`, which takes port, limits and timeouts from the
environment.

## Decisions

- **Process environment wins over `.env`**, which wins over the default
  in code. Bend cannot set or enumerate environment variables. Only
  `IO.get_env(name)` exists (`bend base IO`; C side `getenv`, run inline
  and cheap). So a `.env` file is loaded into a `Map` and every lookup tries
  `get_env` first.
- **Numbers fail fast.** `Config.u32(name, default)` answers the default
  when the variable is unset or empty. It ends the process with
  `air: config: NAME is not a number: "<value>"` (exit 1) when set but not
  digits. Use `IO.die`, called from `main`-time code only. Never print the
  value of a name containing `SECRET`, `TOKEN`, `KEY` or `PASSWORD`: print
  `<hidden>` instead.
- **`.env` format**: lines `KEY=VALUE`; blank lines and `#` comments
  skipped; optional leading `export `; the value trimmed; one pair of
  surrounding `"` or `'` removed; no escapes and no `${VAR}` expansion.
  A line without `=` or with an empty key is malformed. `load` prints
  `air: .env:<line>: ignored` for each such line and keeps going. A
  missing file is an empty config, not an error.
- **Handlers read config through the store** (namespace `config`), since
  the app is a closed template and cannot capture a value from `main`
  (see plan 015's finding). `Config.install(store, cfg)` writes the loaded
  map. `Air.Config.get(req, name, default) -> IO(String)` tries
  `get_env`, then the store, then the default.
- **Server settings from the environment**:
  `Air.Limits.from_env() -> IO(Limits)` reads `AIR_MAX_HEAD`,
  `AIR_MAX_HEADERS`, `AIR_MAX_URL` and `AIR_MAX_BODY`.
  `Air.Timeouts.from_env() -> IO(Timeouts)` reads `AIR_TIMEOUT_IDLE`,
  `…_HEAD`, `…_BODY`, `…_APP`, `…_SEND` and `…_DRAIN`, in ms.
  `Air.Config.port(default) -> IO(U32)` reads `PORT`. Each falls back to
  today's defaults field by field.
- **`Air.serve_env(~app, +default_port)`** = load `.env` from the working
  directory, install it into a fresh store, then `serve_shared` with
  `from_env` limits and timeouts, a new switch and `PORT`. Both examples
  switch to it with `8080` as the default, so `PORT=9090 bend examples/hello/main.bend`
  works (plan 020's A/B can then run two servers side by side).

## Current state

- `air/lib/errors.bend:108-117`: the one env reader today:

  ```
  def Env.parse(r: Result<&1, &1, U32 & String, String>) -> Http.Env:
    ...
  def Env.from_env() -> IO(Http.Env):
    IO.bind(Result<&1, &1, U32 & String, String>, Http.Env, IO.get_env("AIR_ENV"), r => IO.pure(Http.Env, Env.parse(r)))
  ```

  This is the pattern for matching `get_env`'s `Result` (`Done{v}` / `Fail{e}`).
- `air/lib/text.bend:179-190`: `digits(+s) -> Maybe<&2, U32>` and
  `digits_or(+s, +fallback) -> U32`. Use `digits`, never `Nat.read`
  (AGENTS.md: a law that reaches `Nat.read` never finishes checking).
  `split_at(+s, +sep: Char) -> Two()` at `:56`.
- `air/lib/disk.bend:68`: `read(path) -> IO(Maybe<&2, String>)`.
- `air/lib/store.bend`: `new()`, `update(+store, +ns, f)`, `get_in(+req, +ns, +key)`.
- `air/lib/http.bend:18-22`: `Limits{head, headers, url, body}`, default
  `Limits{16384, 100, 8192, 1048576}`. `server.bend`:
  `Timeouts{idle, head, body, app, send, drain}`, default
  `{15000, 10000, 30000, 30000, 30000, 10000}`.
- `air.bend:1211`: `serve(~app, +port)`. `serve_shared(~app, +limits, +timeouts, +store, +switch, +port)`
  is re-exported. `examples/*/main.bend` end with `Air.serve(~app, 8080)`.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Proof | `bend PROOF.bend` | `All terms check.` |
| Tests (if 019 landed) | `bend tests/hello.bend` | exit 0 |
| PORT | `PORT=9090 bend examples/hello/main.bend` then `curl -s localhost:9090/hello/x` | `Olá, x!` |
| Bad number | `AIR_MAX_BODY=abc bend examples/hello/main.bend; echo $?` | message naming `AIR_MAX_BODY`, exit 1 |
| Body limit | `AIR_MAX_BODY=10 bend examples/hello/main.bend` + `curl -s -o /dev/null -w '%{http_code}' -d 'more than ten bytes' localhost:8080/echo` | `413` |
| .env | a `.env` with `GREETING=Hi` in the cwd + a route reading it | `Hi` |
| Native | `bend examples/hello/main.bend -o /tmp/h && bend examples/dashboard/main.bend -o /tmp/d` | exit 0 |

## Implementation rules relevant to this plan

- Bend rules: declare before use; no `if` (a helper def per branch); match
  only on parameters; recursion decreases on its first changing argument;
  rebind `+x = x` for a `+` value a lambda would capture. See `AGENTS.md`.
- New module `air/lib/config.bend` importing `Base`, `./text.bend`,
  `./http.bend`, `./disk.bend`, `./store.bend` and `./server.bend` (for
  `Timeouts`). Check that `server.bend` does not import anything that
  imports `config.bend`. Imports must stay acyclic.
- Pure parts (`parse`, `malformed`, `unquote`, the secret-name test,
  `Limits` from a lookup function) must be laws. IO wrappers stay thin.
  Structure `from_env` as: read the raw strings (IO), then a pure
  `limits_of(head, headers, url, body: String) -> Result`-like function
  that is law-checked.
- Facade: `Air.Config()` (the map type), `Air.Config.env/u32/port/load/install/get`,
  `Air.Limits.from_env`, `Air.Timeouts.from_env`, `Air.serve_env`.
  Native-build both examples after (C symbol collisions).

## Scope

**In scope**: `air/lib/config.bend` (new), `air.bend`, `LAWS.bend`,
`PROOF.bend`, both examples' `main` (to `serve_env`), one hello route
`/config/greeting` reading `GREETING` via `Air.Config.get` (default
`"Olá"`), `tests/hello.bend` case for it (if 019 landed),
`docs/content/docs/guides/configuration.mdx` (new) + `meta.json`,
`.gitignore` (add `.env`), roadmap tick, index row.

**Out of scope**: typed config schemas (use `Schema` on a JSON file if
needed later), hot reload, secrets managers, `${VAR}` expansion, writing
the environment.

## Steps

### Step 1: pure parser and lookups, with laws

```
config_parse_basic:   Config.parse("A=1\n# c\n\nexport B = \"two words\"\n") has A→"1", B→"two words"
config_parse_single:  Config.parse("C='x=y'") has C→"x=y"          (first '=' splits)
config_malformed:     Config.malformed("A=1\nnope\n=x\n") == [2, 3]
config_hidden:        Config.show_value("DB_PASSWORD", "hunter2") == "<hidden>"
config_limits_ok:     Config.limits_of("", "", "", "10") == Ok(Limits{16384, 100, 8192, 10})
config_limits_bad:    Config.limits_of("", "", "", "1e3") == Bad("AIR_MAX_BODY", "1e3")
```

Pick the result type yourself (a small `type Read is Data: Ok{..} | Bad{name, value}`).
Keep the claims.

### Step 2: IO layer and `serve_env`; move the examples to it

### Step 3: docs page

Precedence order, the `.env` format, the `AIR_*` names with defaults in
one table, reading config in a handler, and the fact that secrets are
never printed.

## Test plan

Six laws, plus the live checks in the commands table. If 019 landed, the
`/config/greeting` case goes into `tests/hello.bend` with a `.env`-free
default (`Olá`).

## Done criteria

- [ ] `bend PROOF.bend` passes with the new laws.
- [ ] `PORT`, `AIR_MAX_BODY=10` (413) and a malformed number (exit 1 naming the variable) behave as specified.
- [ ] `.env` values reach a handler. The process env overrides `.env` (check with `GREETING=Env` set on the command line).
- [ ] Both examples use `serve_env` and still native-build.
- [ ] Docs page, `.gitignore`, roadmap and index updated.

## STOP conditions

- `IO.die` from `main` does not produce a nonzero exit on the JS runner.
  Report it (plan 019 has the same dependency). Do not swallow bad config
  silently.
- `serve_env` cannot take `~app` and pass it on to `serve_shared` because
  of a template restriction. Offer `Air.Config.server()` returning the
  settings instead, and keep `main` explicit.

## Maintenance notes

- Plan 023 (readiness) and 025 (metrics) may add `AIR_*` settings. Add
  them to the docs table.
- Keep the secret-name heuristic in one def so it can grow.
