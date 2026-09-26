# Plan 019: Apps can be tested in-process by injecting requests without a socket

> **Executor instructions**: Deliver the stated outcome within scope. Adapt routine
> implementation details to current code, preserve the listed contracts, and run
> the relevant acceptance checks. Fix task-caused failures and recheck affected
> behavior. Escalate only the material conditions below. Update the plan's status
> in `.factory/plans/README.md`.
>
> **Drift check**: `git diff --stat cea6656 -- air.bend air/lib/http.bend air/lib/server.bend air/lib/store.bend examples/hello`
> and `git status --short` should be empty or routine.

## Status

- **Priority**: P1 (plan 020's CI runs these tests; later plans use them for evidence)
- **Effort**: M
- **Risk**: LOW (new module; the server is only refactored so both paths share one function)
- **Depends on**: none
- **Category**: dx (roadmap Tier 6: "Testing helper: inject a request without opening a socket")
- **Planned at**: commit `cea6656`, 2026-09-22, clean tree

## Why this matters

Today the only ways to check an app are laws over pure pieces
(`LAWS.bend`) and `curl` against a running server. Laws cannot run `IO`, so
a handler that touches the store, the clock or a middleware chain can only
be checked by hand. That is why every previous plan's "live checks" live
as prose in the index. This plan adds `Air.Test`: build a request from raw
HTTP text, run the app on it with a fresh store, and get back the
`Response` the server would have written. A test program then asserts on
it and exits 1 on failure. `bend tests/hello.bend` becomes a real check
that CI (plan 020) can run.

## Decisions

- **Input is raw HTTP text**, parsed by the same `Http.Request.parse` the
  server uses: `Air.Test.raw("GET /hello/ada HTTP/1.1\r\nhost: x\r\n\r\n")`.
  Whatever comes after the blank line is the body, taken whole. This tests
  the parser too, and needs no request builder API. Convenience wrappers
  cover the common cases:
  `Air.Test.get(target)`, `Air.Test.post(target, content_type, body)`,
  `Air.Test.with_header(name, value, raw)` (inserts a header line before
  the blank line).
  A `Content-Length` is added by `post` automatically. `raw` does not add
  one.
- **Refusals come back as responses.** A head the parser refuses
  (`Http.Refused{status}`) gives the refusal response the server would send
  (`Http.Response.with_status(Http.Response.text(Http.Status.reason(status)), status)`).
  A fixed-length body longer than `Limits.body` gives 413. Chunked request
  bodies are out of scope: pass the decoded body.
- **The app runs exactly as under `serve`**: with the body set, a store on
  the request (a fresh one per call, or a shared one via `inject_shared`),
  and the response settled with `Http.Response.settle(Http.Prod{}, res)`, as
  `Server.respond` does. No timeouts, because there is no watchdog without
  a connection. Document that.
- **Streamed bodies are drained** by `Air.Test.body(res) -> IO(String)`,
  which concatenates the channel's pieces until it closes. It uses fuel
  `max_chunks()`. For a whole body it answers the text. For a failed one
  it answers "".
- **Assertions are tiny and print TAP-like lines**:
  `Air.Test.expect(name, got: String, want: String) -> IO(Bool)` prints
  `ok - name` or `not ok - name: want "…" got "…"`.
  `Air.Test.expect_u32(name, got, want)` does the same for a status.
  `Air.Test.finish(results: List<Bool>) -> IO(Unit)` prints
  `N passed, M failed` and calls `IO.die(Unit, 1, …)` when any failed.
  There is no framework beyond this: a test program is a `main` in a `do`
  block.
- **Where tests live**: `tests/` at the repo root, one file per example
  (`tests/hello.bend`, `tests/dashboard.bend`). Each imports the example's
  `main.bend`? No: an import brings in `main` too. A second `main` would
  collide. Instead, move each example's app into `examples/<name>/app.bend`
  (routes, handlers and `app`) and keep `main.bend` as a few lines that
  import it and serve. Tests import `app.bend`. If moving is refused by the
  checker for some reason, write the tests against a small app defined in
  the test file and record why (see STOP).

## Current state

- `air/lib/server.bend:581-585`, where the server runs the app:

  ```
  def run(~app: Chan(Unit) -> Router.Handler(), +ctx: Ctx, sock: Socket, +req: Http.Request, rest: String, body: String) -> IO(Next):
    do IO<Next>:
      gen : U32 <- arm(ctx, Timeouts.app(Ctx.timeouts(ctx)))
      r : Race.Raced<Http.Response> <- Race.within(Http.Response, drop_reply, Ctx.clock(ctx), gen, app(Ctx.switch(ctx), Http.Request.with_store(Http.Request.with_body(req, body), Some{Ctx.store(ctx)})))
  ```

  and `respond` (`:562`), which settles: `+res = Http.Response.settle(Http.Prod{}, res)`.
  Refusals are built in `refuse.go` (`:391`).
- `air/lib/http.bend`: `Request.parse(+limits, head) -> Parsed` (`:749`),
  with `Parsed{req}` / `Refused{status}` (`:680`). `Request.with_body`
  (`:229`), `Request.with_store` (`:196`), `Request.framing` returns
  `Framing` = `NoBody | Fixed{n} | Chunked | Unframed{status}` (`:753`).
  `Response` is `Response{status, headers, cookies, body: Body}` with
  `Body = Whole{text} | Stream{chan} | Failed{err}` (`:983-991`).
  `Response.status/header/body` accessors exist. `Response.render(r, head_only, keep)`
  gives wire text.
- The head string the server hands to `parse` is everything before
  `\r\n\r\n` (`server.bend:157`, `Text.split_str(buf, "\r\n\r\n")`). Laws
  build requests the same way: `LAWS.bend:122-130` (`request(head)`), for
  example `request("GET /a HTTP/1.1\r")`. Mirror the server exactly: split
  the raw text with `Text.split_str(raw, "\r\n\r\n")`.
- `air/lib/store.bend`: `new() -> IO(Store())`.
- `examples/hello/main.bend` (220 lines) and
  `examples/dashboard/main.bend` hold handlers, routes, `app` and `main` in
  one file. The dashboard reads files relative to its folder. Check how
  (`Air.static`, `Response.file`) before writing tests that fetch assets.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Check and prove | `bend PROOF.bend` | `All terms check.` |
| Run tests | `bend tests/hello.bend` | `N passed, 0 failed`, exit 0 |
| Failing test exit code | edit one `want`, run, `echo $?` | `1` |
| Examples still serve | `bend examples/hello/main.bend` then `curl -s localhost:8080/hello/ada` | `Olá, ada!` |
| Native build (C names) | `bend examples/hello/main.bend -o /tmp/hello && bend examples/dashboard/main.bend -o /tmp/dash` | both exit 0 |

## Implementation rules relevant to this plan

Bend rules (from `AGENTS.md`; the checker enforces them):
- Declare a def above every use. No mutual recursion, and no `if`: branch
  through a helper def that matches on a parameter.
- `match` and tuple destructuring only on parameters or pattern-bound
  names, never on a `let` or a computed value. Scrutinees follow parameter
  order.
- Self-calls must decrease, with the fuel or list first. Use `Text.append`
  for big buffers. `String.append` recurses on its left side.
- A `+` parameter cannot be the one a partial application abstracts: take
  it plain and rebind `+x = x` at the top of the body.
- Inside `air/lib/`, name defs relative to the module. The facade
  re-exports with a wrapper def (types by `def X() -> Data:`). Native-build
  both examples after adding facade names (C symbol collisions).

Design:
- New module `air/lib/test.bend` (alias `Test` in the facade and laws),
  importing `Base`, `./text.bend`, `./http.bend`, `./router.bend`,
  `./store.bend`.
- Extract the server's refusal response into `Http.Response.refusal(status: U32) -> Response`
  (in `http.bend`), and have `server.bend`'s `refuse.go` call it. The test
  module then uses the same function. This is the only server change.
- `inject(app: Router.Handler(), raw: String) -> IO(Http.Response)`:
  split, parse, check framing, then `IO.bind(Store.new(), s => inject_shared(app, s, raw))`.
  `inject_shared(app, +store, raw)` is for tests that need the store to
  persist across requests (counters, sessions, rate limits).
- Framing: `Fixed{n}` with `n > Limits.body` → 413. `Fixed{n}` otherwise
  takes the first `n` bytes of the rest (`Text.take_bytes`; if short,
  400). `NoBody` → "". `Chunked` → the rest as is (documented
  simplification). `Unframed{status}` → that refusal.
- Facade section "Testing" in `air.bend`: `Air.Test.raw/get/post/with_header/inject/inject_shared/body/expect/expect_u32/finish`,
  with a short comment block showing a three-line test `main`.

## Scope

**In scope**:
- `air/lib/test.bend` (new), `air/lib/http.bend` (`Response.refusal`),
  `air/lib/server.bend` (`refuse.go` uses it; no behavior change), `air.bend`.
- `examples/hello/app.bend` and `examples/dashboard/app.bend` (new; moved
  code), each `main.bend` reduced to imports + `main`. The README commands
  (`bend examples/hello/main.bend`) keep working unchanged.
- `tests/hello.bend`, `tests/dashboard.bend` (new).
- `LAWS.bend`, `PROOF.bend`: laws for the pure parts (split, framing
  decision, `with_header`, `Response.refusal` render).
- `docs/content/docs/guides/testing.mdx` (new) + `guides/meta.json` entry;
  `docs/content/docs/project/checks.mdx`: add `bend tests/*.bend`.
- `AGENTS.md`: layout line for `tests/` and "run the tests before committing".
- `roadmap.md`: tick the testing helper line with a one-line note.
- `.factory/plans/README.md`: row 019.

**Out of scope**: timeouts in injected requests, chunked request decoding
in tests, a test runner that discovers files, mocking effects (`Disk.read`,
`IO.random_u32` run for real), snapshot testing.

## Steps

### Step 1: `Response.refusal` and the pure helpers, with laws

Laws to add (adapt the exact strings to what the code produces, but keep
each claim):

```
test_get_raw:        Test.get("/a?b=1") == "GET /a?b=1 HTTP/1.1\r\nhost: test\r\n\r\n"
test_post_length:    Test.post("/e", "text/plain", "héllo") contains "content-length: 6"   (bytes, not chars)
test_with_header:    Test.with_header("x-a", "1", Test.get("/")) == "GET / HTTP/1.1\r\nhost: test\r\nx-a: 1\r\n\r\n"
refusal_render:      Http.Response.render(Http.Response.refusal(431), False{}, False{}) == <the exact bytes refuse sends today>
```

Capture the "exact bytes" expectation by rendering the current
`refuse.go` response in a scratch law before refactoring, so the refactor
is proven byte-identical.

### Step 2: `inject`, `inject_shared`, `body`, assertions

`inject` returns the settled response. `body` drains a stream: write
`drain(fuel: Nat, +chan, acc) -> IO(String)` with fuel first.

### Step 3: split the examples, write the tests

`tests/hello.bend` covers at least:
1. `GET /hello/ada` → 200, body `Olá, ada!`.
2. `GET /nope` → 404 with the `on_error` plain body.
3. `POST /nope-method` on a GET-only path → 405 and an `allow` header.
4. `GET /admin/whoami` without the token → 401. With `x-token: secret` →
   200 `you are victor`.
5. `GET /visits` twice through `inject_shared` → `1` then `2`.
6. `GET /limited` six times shared → the sixth is 429 with `retry-after`.
7. `GET /ticks` → `content-type: text/event-stream` and a body with five
   `event: tick` blocks. Before relying on the test, check whether the
   producer's `IO.sleep(1000)` makes it take 5 s. If so, keep it: it
   proves `body` drains a stream.
8. A raw head over `Limits.default()`'s 16384-byte head cap → 431 (the refusal path).
9. `x-request-id` present on every response (the middleware chain ran).

`tests/dashboard.bend`: valid and invalid `POST /api/tasks` (201 / 422
with the errors list), `?limit=abc` → 422, one static file with an
`etag`. Run it from the repo root. If static paths are relative to the
working directory, say so in the test file header.

### Step 4: docs and bookkeeping

Guide page: why (laws cannot run IO), the shape of a test file, shared vs
fresh store, streams, what is not simulated (timeouts, sockets, the
server's 100-continue and keep-alive).

## Test plan

- Laws from step 1 in `LAWS.bend`/`PROOF.bend`.
- `bend tests/hello.bend` and `bend tests/dashboard.bend` pass. Flip one
  expectation and confirm exit code 1 and a `not ok` line, then revert.
- Both examples still serve (`curl` one route each) and native-build.

## Done criteria

- [ ] `bend PROOF.bend` prints `All terms check.`
- [ ] `bend tests/hello.bend` and `bend tests/dashboard.bend` exit 0 with ≥ 9 and ≥ 4 checks.
- [ ] A deliberately wrong expectation exits 1 (checked, then reverted).
- [ ] `refuse` sends byte-identical responses (law).
- [ ] Both examples native-build and serve as before.
- [ ] Guide page, checks page, AGENTS.md, roadmap and index row updated.

## STOP conditions

- Moving an example's code into `app.bend` breaks something the checker
  or a backend needs (for example a relative `Disk` path resolved against
  the importing file). Keep the examples whole, write each test against a
  copy of the few routes it needs, and record why in the index.
- `IO.die` inside `finish` does not set the process exit status on the JS
  runner (`bend file.bend`). Check `echo $?`. If it is 0, find the Base
  effect that sets it (`bend base IO`). If none exists, report: CI
  (plan 020) depends on the exit code.
- `inject` needs a `~template` app, so `inject(app, raw)` with a plain
  handler value is refused. Take `~app` then, matching `serve`.

## Maintenance notes

- Plan 020 runs `bend tests/*.bend` in CI. Keep each test file fast (the
  SSE test is the slow one).
- Later plans (health, metrics, OpenAPI, hooks) should add their evidence
  as tests here instead of prose-only live checks.
- If Bend gains effect mocking, `Random`/`Disk` could be stubbed. Until
  then tests assert on shapes (16 hex chars) rather than values.
