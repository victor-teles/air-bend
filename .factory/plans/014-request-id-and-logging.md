# Plan 014: Request IDs and one structured log line per request

> **Executor instructions**: Deliver the stated outcome within scope. Adapt routine
> implementation details to current code, preserve the listed contracts, and run
> the relevant acceptance checks. Fix task-caused failures and recheck affected
> behavior. Escalate only the material conditions below. Update the plan's status
> in `.factory/plans/README.md`.
>
> **Drift check**: `git diff --stat 13be69e -- air.bend air/server.bend air/json.bend air/http.bend examples LAWS.bend PROOF.bend README.md roadmap.md bench`
> should be empty or routine. Confirm `Server.log` at `air/server.bend:399`
> is the only per-request print, and list its call sites with
> `grep -n "log(" air/server.bend` before changing any.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW (two middleware; one print moves out of the server)
- **Depends on**: none (013 makes `x-request-id` survive `on_error`, but the ID is also readable from the local without it)
- **Category**: direction (roadmap Tier 5: request ID + structured request logging)
- **Planned at**: commit `13be69e`, 2026-09-20, clean tree

## Why this matters

The server prints `GET / -> 200` for every response, unstructured, with no
way to correlate a line with a client's report or with a proxy's own log.
This plan ships two middleware: `request_id`, which takes the client's
`X-Request-Id` when it is safe or mints one, leaves it in a local and on the
response; and `log`, which prints one JSON line per request with the time,
the id, the method, the path, the status and the elapsed milliseconds.

**A decision to surface**: once an app logs its own line, the server's
`method path -> status` line is a duplicate. This plan keeps the server's
line **only for what the app never sees** (400 on a bad head, 413/414/431 on
limits, 503 on the app timeout, and the `air: timeout:` lines) and drops it
for responses the app produced. An app that wants a per-request line adds
`Air.log`. Both examples do. If the owner would rather keep the server line
unconditionally, skip step 3 and note it; nothing else depends on it.

Decisions:

- **ID format**: 32 lowercase hex characters from four `IO.random_u32`
  draws (`Text.hex_show` gives eight each). Random, not sequential: no
  shared counter needed and nothing leaks request volume. If a draw fails
  (`Result.Fail`), fall back to the hex of `IO.now()` low bits plus the
  draws that worked; never crash.
- **Trusting the client's id**: accepted when 1 to 128 characters, all in
  `[A-Za-z0-9._-]`. Anything else is replaced. Proxies that set the header
  keep their id; a client cannot inject a newline or a script into the log.
- **Local name** `request_id`; **header** `x-request-id` on every response,
  set by `request_id` before calling `next` on the request and after on the
  response.
- **Log line**: `{"ts":1726790000000,"id":"…","method":"GET","path":"/x","status":200,"ms":3}`
  built with `Json.obj` so strings are escaped, printed with `IO.print`.
  `ts` is `IO.now()` at the start; `ms` the difference. `id` is the local,
  `""` when `request_id` is not in the chain. No `ip`: it needs a `Trust`
  and is one `with_local` away for an app that wants it (`Request.client_ip`).
- **`log` inside `request_id`** in the chain (`use([Air.request_id, Air.log, …])`)
  so the line has the id; document that order.

## Current state

- `air/server.bend:399` — `def log(method, path, +status)`; call sites to
  find: after the app's response in `on_app` (around `:609-627`) and in the
  refusal paths (`refuse`, limits, timeouts).
- `air/text.bend:194` — `hex_show(n: U32)`: eight lowercase hex digits.
- `air/json.bend` — `obj`, `field`, `of_str`, `of_u32`, `num`, `render`.
- `air/http.bend:157-170` — `Request.local`, `with_local`.
- `examples/hello/main.bend:60-79` — the `timing` middleware, which this plan
  replaces with `Air.log` (it prints the same line, unstructured).
- Base: `IO.random_u32() -> IO(Result<&1, &1, U32 & String, U32>)`, `IO.now() -> IO(Nat)`.
- `bench/reference.mjs` logs nothing; `bench/run.sh` runs the hello example
  natively. `Air.log` will add one `IO.print` per request to the benchmarked
  path where the server's print used to be: net zero prints.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Check and prove | `bend PROOF.bend` | `All terms check.` |
| Run the example | `bend examples/hello/main.bend` | one JSON line per request on stdout |
| Minted id | `curl -si localhost:8080/` | `x-request-id: <32 hex>` and the same id in the log line |
| Kept id | `curl -si localhost:8080/ -H 'X-Request-Id: abc-123'` | `x-request-id: abc-123` |
| Rejected id | `curl -si localhost:8080/ -H 'X-Request-Id: <script>'` | a minted id instead |
| Refusal still logged | `printf 'GARBAGE\r\n\r\n' \| nc localhost 8080` | server prints its own 400 line |
| Bench (optional) | `bench/run.sh` | within a few percent of 30.4k req/s |

## Implementation rules relevant to this plan

- New module `air/log.bend` (alias `Log`), importing `Base`, `./text.bend`,
  `./json.bend`, `./http.bend`, `./router.bend`. Do not name any def `await`
  or another JavaScript reserved word.
- Pure, law-checked:
  - `safe_char(+c: Char) -> Bool`, `safe_id(+s: String) -> Bool` (length
    1..128 via a counting walk in `U32`, every char safe).
  - `hex_id(a: U32, b: U32, c: U32, d: U32) -> String`: the four `hex_show`
    concatenated (small operands, `++` is fine).
  - `line(ts: Nat, id: String, method: String, path: String, status: U32, ms: Nat) -> String`:
    `Json.render(Json.obj([...]))` with `ts` and `ms` as `Json.num(Nat.show(n))`.
- IO:
  - `draw() -> IO(U32)`: `IO.random_u32` with `Fail` mapped to the low 32
    bits of `IO.now()` (`U32.from_nat`).
  - `fresh_id() -> IO(String)`: four draws, `hex_id`.
  - `pick_id(+given: String) -> IO(String)`: `given` when `safe_id`, else `fresh_id()`.
  - `request_id(next: Router.Handler(), req: Http.Request) -> IO(Http.Response)`:
    `+req = req`; id from `pick_id(Request.header(req, "x-request-id"))`;
    `next(Request.with_local(req, "request_id", id))`, then
    `Response.with_header(res, "x-request-id", id)`. `id` is read twice:
    bind it in a helper def with `+id`.
  - `log(next, req)`: `+req = req`; `before <- IO.now()`; `res <- next(req)`;
    `after <- IO.now()`; `+res = res`; print `line(before, Request.local(req, "request_id"), Method.show(...), Request.path(req), Response.status(res), Nat.sub(after, before))`; return `res`.
    Follow the `timing.fin`/`timing.go` split in the hello example for the
    affine bindings.
- Server (step 3): keep `Server.log` for refusals; remove the call after the
  app's response only. Keep the def's name and shape so the diff is small.
- Facade: `Air.request_id`, `Air.log` in a "Batteries" section (create it if
  013 has not), plus `Air.Request.id(req)` as sugar for
  `Request.local(req, "request_id")`.

## Scope

**In scope**:
- `air/log.bend` (new); `air.bend`; `air/server.bend` (one call site);
  `LAWS.bend`; `PROOF.bend`.
- `examples/hello/main.bend`: delete `timing*`; `app.fin` uses
  `[Air.request_id, Air.log, …]` first. `examples/dashboard/main.bend`: same
  two at the front of its `use` list.
- `README.md`: Middleware section mentions the two; "Checks"/"Benchmarks"
  unchanged.
- `roadmap.md`: tick "Request ID + structured request logging".
- `bench/README.md`: note if a rerun shows movement.
- `.factory/plans/README.md`: row 014, and the server-line decision under
  "Findings".

**Out of scope**: log levels, log sinks other than stdout, sampling, client
IP in the line, `Server-Timing`.

## Git workflow

- Current worktree branch. Do not commit or push unless asked. `bend PROOF.bend` first.

## Steps

### Step 1: `air/log.bend` pure defs and laws

```
log_safe_id_plain:     Log.safe_id("abc-123.X_y") == True{}
log_safe_id_empty:     Log.safe_id("") == False{}
log_safe_id_space:     Log.safe_id("a b") == False{}
log_safe_id_long:      Log.safe_id(String.repeat("a", 129n)) == False{}
log_hex_id_len:        Text.byte_length(Log.hex_id(0, 1, 2, 3), 0) == 32
log_line_escapes:      Log.line(5n, "i", "GET", "/a\"b", 200, 2n) == "{\"ts\":5,\"id\":\"i\",\"method\":\"GET\",\"path\":\"/a\\\"b\",\"status\":200,\"ms\":2}"
```

(Check `String.repeat`'s argument order in Base; adapt.)

### Step 2: the two middleware, facade, examples

### Step 3: the server line

Find the call in the app-response path and remove it; leave the refusal
calls. Run the hello example and confirm one line per request, not two.

### Step 4: live checks

Record in the index:

1. Minted id: header and log line agree, 32 hex chars.
2. Kept id `abc-123`.
3. Rejected id `<script>` (also `a b` and 200 chars) → minted.
4. `curl -si localhost:8080/boom` → 500 line with `"status":500` and the id.
5. Garbage head over `nc` → the server's own 400 line still prints; no JSON line (the app never ran).
6. Dashboard: `curl -si localhost:8080/api/tasks` → a JSON log line and `x-request-id`.
7. `bench/run.sh` (optional): note the number.

## Test plan

Six laws; seven live checks.

## Done criteria

- [ ] `bend PROOF.bend` prints `All terms check.` with the six new laws.
- [ ] Live checks 1–6 pass and are noted in the index.
- [ ] Exactly one log line per app response on both examples; refusals still logged by the server.
- [ ] `Air.request_id`, `Air.log`, `Air.Request.id` exist with comments.
- [ ] README, roadmap, index updated.

## STOP conditions

- The server's app-response log call cannot be separated from the refusal
  ones without restructuring `on_app`: keep the server line and record the
  decision in the index ("both lines print"); do not restructure the server.
- `IO.random_u32` fails on every call on this platform: fall back to
  `IO.now()` bits plus a per-process counter is impossible (no globals), so
  use `IO.now()` alone and note that ids are then time-based.

## Maintenance notes

- Plan 016 (sessions) reuses `Log.draw`/`hex_id` for session ids; move them
  to `air/text.bend` or a tiny `air/random.bend` at that time if `Session`
  would otherwise import `Log`.
