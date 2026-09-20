# Plan 011: Handlers fail with a typed HTTP error that one middleware renders, plainly in prod and with detail in dev

> **Executor instructions**: Deliver the stated outcome within scope. Adapt routine
> implementation details to current code, preserve the listed contracts, and run
> the relevant acceptance checks. Fix task-caused failures and recheck affected
> behavior. Escalate only the material conditions below. Update the plan's status
> in `.factory/plans/README.md`.
>
> **Drift check**: Requires plan 010 (`Middleware()`, `use`, `Request.locals`).
> `git diff --stat c989e4a -- air/http.bend air/server.bend` should show only
> plan 010's `locals` change. Confirm `type Body is Data: Whole{text} | Stream{chan}`
> at `air/http.bend:796`, that `Response.render` at `air/http.bend:1338` renders
> a `Whole` body through `render_head` + `render_body`, and that the server's
> `respond` at `air/server.bend:606` branches on `Http.Response.payload`.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED (touches `Body`, which the server's send path matches on)
- **Depends on**: `.factory/plans/010-middleware.md`
- **Category**: direction (roadmap Tier 4: centralized error handler, typed error hierarchy, async rejection capture, dev vs prod rendering, double-send guard)
- **Planned at**: commit `c989e4a`, 2026-09-20, clean tree

## Why this matters

A handler today answers an error by hand-building a `Response` with a
status and a text body, so every app renders its 404 and 401 pages in
several places and nothing can swap them for JSON or HTML in one move.
Bend has no exceptions: a handler cannot throw, and the only ways to abort
are `IO.try` and `IO.die`, which end the whole process. So the error
channel has to be a value. This plan makes it one and gives it a single
rendering point.

Decisions:

- **An error is a value, `Http.Error`, a sum type over the common statuses**
  plus `Other{status, detail}`. `detail` is free text for the developer,
  never for the client in prod.
- **An error travels as a response whose body is not yet rendered.** `Body`
  gains `Failed{err: Error}`; `Response.fail(e)` is a response with that
  body and the error's status. `Air.fail(e)` wraps it in `IO`. A middleware,
  `on_error(render, next)`, runs `next` and, when the body is `Failed`,
  replaces the response with `render(req, e)`. Whatever reaches the server
  still `Failed` is settled by the server in prod style (reason phrase,
  `text/plain`), so an app without the middleware keeps working and never
  leaks a detail. This is Express's `app.use((err, req, res, next) => …)`
  without the throw.
- **The router's own 404, 405 and 400 become `Failed` bodies**, so a custom
  error renderer also owns the "no route" page. Their rendered bytes stay
  identical to today's.
- **Dev vs prod is an `Env` value**, `Dev{}` or `Prod{}`, read from
  `AIR_ENV` (`dev` → `Dev`, anything else or unset → `Prod`); the examples
  read it per request, see step 4.
  The two shipped renderers, `Error.plain(env)` and `Error.json(env)`,
  include `detail` only in dev. Bend has no stack traces; the detail string
  is the closest thing, and the shipped dev renderer also adds the method
  and path.
- **Async rejection capture** means: a failed effect must become an `Error`,
  not a dead process. `attempt(A, act, k)` runs a fallible effect
  (`IO(Result<&1, &1, U32 & String, A>)`), continues with `k` on `Done` and
  answers `fail(Internal{msg})` on `Fail`. (Verified on 2.0.10: matching
  `Fail{e}` then `(code, msg) = e` inside a helper def checks and runs.) The
  README states the rule: never `IO.try` or `IO.die` inside a handler. What
  the runtime itself does on a crash (stack overflow) cannot be caught and
  is documented as such.
- **The double-send guard is by construction.** A handler is a function to
  one `IO(Response)`; the socket belongs to the server; a stream producer's
  send after close answers `False`. There is no second send to detect.
  This plan documents it and ticks the roadmap line; no code.

## Current state

- `air/http.bend:796-806` — `Body` (`Whole`, `Stream`) and
  `Response{status, headers, cookies, body: Body}`; `Body.text` (`:813`)
  answers `""` for a stream; `Response.payload` (`:827`) hands the body to
  the server.
- `air/http.bend:866-878` — `not_found`, `method_not_allowed(allow)`,
  `bad_request` build `Response.text(reason)` with a status; the 405 adds
  `allow`. `LAWS.bend:154` pins `header(method_not_allowed("GET, OPTIONS"), "allow")`.
- `air/http.bend:1236-1272` — `Status.reasons` map and `Status.reason(code)`;
  410 and 415 are missing.
- `air/http.bend:1296-1345` — `render_body`, `render_head`, `render`:
  `render(r, head_only, keep)` for a `Whole` body writes the start line,
  headers, `content-length`, cookies, body. Laws at `LAWS.bend:157, 361,
  366, 598, 669, 673` pin exact render output; they must keep passing.
- `air/server.bend:436-446` — `refuse` sends the server's own 4xx/5xx
  (parse failures, limits, 503 on app timeout) as `Response.text(reason)`;
  no app code runs for these. Unchanged.
- `air/server.bend:591-609` — `respond` logs, then `respond.pick` matches
  `payload`: `Whole` → `send`, `Stream` → `stream`.
- `air/router.bend` after plan 010 — `Handler()`, `Middleware()`, `use`;
  `miss.pick` (`:412`) answers `not_found` / `options` / `method_not_allowed`.
- `air.bend:471-483` — facade for `not_found`, `method_not_allowed`,
  `options`, `bad_request`.
- `IO.get_env(name) -> IO(Result<&1, &1, U32 & String, String>)` (Base).
- Conventions as in plan 010; in addition, `Http` never touches a socket,
  and every branch on a computed Bool goes through a helper def.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Check and prove | `bend PROOF.bend` | `All terms check.` |
| Run hello in dev | `AIR_ENV=dev bend examples/hello/main.bend` | listens on 8080 |
| Run hello in prod | `bend examples/hello/main.bend` | listens on 8080 |
| Probe | `curl -si localhost:8080/boom` | 500; body has the detail in dev only |
| Probe 404 | `curl -si localhost:8080/nope` | 404 rendered by the app's renderer |
| Run dashboard | `bend examples/dashboard/main.bend` then `curl -si localhost:8080/api/nope` | 404 as JSON |

## Implementation rules relevant to this plan

- `Error` and `Env` live in `air/http.bend` above `Body` (a def must be
  declared above every use). Rendering to a `Response` also lives there
  (`Response.settle`). The middleware, `attempt` and `Env.from_env` live in
  a new module `air/errors.bend` (alias `Errors`), which imports `http` and
  `router`.
- `Error` shape:

  ```
  type Error is Data:
    BadRequest{detail: String}
    Unauthorized{detail: String}
    Forbidden{detail: String}
    NotFound{detail: String}
    Conflict{detail: String}
    Gone{detail: String}
    TooLarge{detail: String}
    Unsupported{detail: String}
    Unprocessable{detail: String}
    TooMany{detail: String}
    Internal{detail: String}
    NotImplemented{detail: String}
    Unavailable{detail: String}
    Other{status: U32, detail: String}
  ```

  `Error.status(e) -> U32` (400, 401, 403, 404, 409, 410, 413, 415, 422,
  429, 500, 501, 503, or the given one), `Error.detail(e) -> String`,
  `Error.reason(e) = Status.reason(Error.status(e))`. Add "410 Gone" and
  "415 Unsupported Media Type" to `Status.reasons`. Constructor names are
  addressed as `Http.NotFound{..}` from other modules; none collides with
  Base.
- `Body` gains `Failed{err: Error}` as its third variant. `Body.text` of a
  `Failed` answers the prod plain text (the reason phrase), so
  `Response.body(Response.not_found()) == "Not Found"` keeps holding.
- `Response.fail(e) = Response{Error.status(e), Map.new(&2, String), Nil{}, Failed{e}}`.
  `Response.error(r) -> Maybe<&2, Error>` reads it back.
- `Response.settle(env, r) -> Response`: a `Failed` body becomes the
  `Whole` plain rendering under `env` (`content-type: text/plain; charset=utf-8`
  set only if the response has no content type yet); `Whole` and `Stream`
  pass through. Plain rendering: prod is the reason phrase; dev is the
  reason phrase, and when `detail` is not empty, a newline and the detail.
  `Response.render` calls `settle(Prod{}, r)` first, so every existing
  render law is unchanged and the server never writes a detail.
- `not_found()`, `bad_request()`, `method_not_allowed(allow)` become
  `Response.fail(NotFound{""})`, `Response.fail(BadRequest{""})`,
  `Response.with_header(Response.fail(Other{405, ""}), "allow", allow)`.
  `options` stays a 204. The server's `refuse` stays as is.
- Server: in `respond.pick`, add a `Http.Failed{err}` case that sends
  `settle(Prod{}, res)` through the `Whole` path. Simplest: have `respond`
  rebind `+res = Http.Response.settle(Http.Prod{}, res)` before `payload`,
  and keep `respond.pick` total with a `Failed` case that calls `send` the
  same way as `Whole` (it is unreachable after settle but the match must
  be total).
- `air/errors.bend`:

  ```
  # A renderer turns an error into the response the client sees.
  def Render() -> Type:
    Http.Request -> Http.Error -> Http.Response

  def on_error.fin(render: Render(), +req: Http.Request, res: Http.Response, err: Maybe<&2, Http.Error>) -> Http.Response:
    match err:
      case None{}:
        res
      case Some{e}:
        render(req, e)

  # Runs `next`; a failed response is rendered by `render`. Anything
  # `render` answers is final, even another failure (the server settles it).
  def on_error(render: Render(), next: Router.Handler(), req: Http.Request) -> IO(Http.Response):
    +req = req
    IO.bind(Http.Response, Http.Response, next(req), res => on_error.fin(render, req, res, Http.Response.error(res)))
  ```

  (`res` is used twice in `fin`: rebind `+res` or read `error` before. The
  executor picks; `Response` is `Data`.)
  `plain(+env, req, e)` and `json(+env, req, e)` are the shipped renderers;
  partially applied to `env` they are `Render()`. JSON shape:
  `{"status":404,"error":"Not Found"}` in prod, plus `"detail":"..."` and
  `"path":"/nope"` in dev, built with `Json.obj` so strings are escaped.
  `plain` in dev appends `method path` on a second line and the detail on
  a third when present.
  `attempt(-A: Type, act: IO(Result<&1, &1, U32 & String, A>), k: A -> IO(Http.Response)) -> IO(Http.Response)`:
  `Done{v}` → `k(v)`; `Fail{e}` → `(code, msg) = e`, answer
  `IO.pure(Http.Response, Http.Response.fail(Http.Internal{msg}))`.
  `Env.from_env() -> IO(Http.Env)`: `IO.get_env("AIR_ENV")`, `Done{"dev"}`
  → `Dev{}`, anything else → `Prod{}`.
- Facade (`air.bend`): `Air.Error()` and `Air.Env()` type aliases;
  `Air.Error.bad_request(detail)` … `Air.Error.unavailable(detail)`,
  `Air.Error.other(status, detail)`; `Air.Error.status/detail/reason`;
  `Air.Error.plain(env)`, `Air.Error.json(env)` (documented as renderers
  for `on_error`); `Air.Response.fail(e)`, `Air.fail(e) -> IO(Response())`,
  `Air.Response.error(r)`; `Air.on_error(render, next)` documented as a
  middleware for `use`; `Air.attempt(A, act, k)`; `Air.Env.dev()`,
  `Air.Env.prod()`, `Air.Env.from_env()`.

## Scope

**In scope**:
- `air/http.bend` — `Error`, `Env`, `Failed`, `Response.fail/error/settle`,
  reasons 410 and 415, the three router error builders.
- `air/errors.bend` (new) — `Render()`, `on_error`, `plain`, `json`,
  `attempt`, `Env.from_env`.
- `air/server.bend` — `respond` settles a `Failed` body in prod style; the
  `respond.pick` match gains the case. Nothing else.
- `air.bend` — the facade names above; the header comment lists
  `air/errors.bend`.
- `examples/hello/main.bend` — `Env.from_env()` in `main`, passed to
  `routes` like the dashboard passes its switch; `use([timing, Air.on_error(Air.Error.plain(env))], base)`;
  `auth` answers `Air.fail(Air.Error.unauthorized("x-token missing or wrong"))`;
  new `GET /boom` answers `Air.fail(Air.Error.internal("the disk is on fire"))`;
  new `GET /env` uses `Air.attempt` on `IO.get_env("HOME")` to show a
  captured effect.
- `examples/dashboard/main.bend` — `use([Air.on_error(Air.Error.json(env))], base)`
  so `/api/nope` and a bad `/api/echo` body answer JSON; `echo.fin` answers
  `Air.Response.fail(Air.Error.bad_request("body is not JSON"))`.
- `LAWS.bend`, `PROOF.bend` — laws below.
- `README.md` — an "Errors" section: `Air.fail`, `on_error`, the two
  renderers, `AIR_ENV=dev`, the `attempt` rule ("never `IO.try` in a
  handler"), the by-construction note on double sends, and that the
  server's own refusals (parse errors, limits, the 503 on timeout) do not
  pass through `on_error`.
- `roadmap.md` — tick the remaining Tier 4 lines (centralized error
  handler, typed error hierarchy, async rejection capture, dev vs prod
  rendering, response-already-sent guard) with one-line notes.
- `.factory/plans/README.md` — status row.

**Out of scope**:
- Routing the server's own refusals through the app: there is no parsed
  request (or the connection is no longer trusted). Rejected in the index.
- Catching a runtime crash. Not possible in Bend 2.0.10.
- HTML error pages: an app writes a `Render()` of its own; the shipped two
  are plain and JSON.
- Content negotiation between the shipped renderers (`Accept`-based
  switching): an app composes `Request.accepts` and the two renderers
  itself. One sentence in the README.

## Git workflow

- Branch: the current worktree branch. Do not commit or push unless asked.
  `bend PROOF.bend` before any commit.

## Steps

### Step 1: `Error`, `Env`, `Failed`, `settle` in `Http`

Add the types and accessors above `Body`, the variant, `fail`, `error`,
`settle`, the reasons, and make `render` settle first. Rewrite
`not_found`, `bad_request`, `method_not_allowed`. Keep every existing law
green.

**Evidence**: `bend PROOF.bend` → `All terms check.`; the laws at
`LAWS.bend:154, 157, 361, 366` unchanged and passing.

### Step 2: the server settles

`respond` rebinds the response through `settle(Prod{}, res)` before
`payload`; `respond.pick` gains the `Failed` case. Confirm a `Failed`
response written by a handler under an app without `on_error` reaches the
client as `text/plain` with the reason and no detail.

### Step 3: `air/errors.bend` and the facade

As specified in the rules. The `-A: Type` parameter of `attempt` is the
one part not verified in planning: if the checker refuses the erased type
parameter in that position, take `A` as a plain `Type` argument as
`IO.bind` does (`IO.bind(A, B, m, f)`), and mirror that in the facade.

### Step 4: examples

Hello and dashboard as in scope. `serve` takes `~app`, a template, so the
app must be a closed term: `Air.serve(~app(env), 8080)` with `env` bound
in `main` is refused, and `serve` threads nothing but the switch to the
app. Read the environment per request instead, inside `app`; a `getenv`
per request is cheap and keeps `main` as it is:

```
def app.fin(req: Air.Request(), env: Air.Env()) -> IO(Air.Response()):
  Air.use([timing, Air.on_error(Air.Error.plain(env))], base)(req)

def app(req: Air.Request()) -> IO(Air.Response()):
  IO.bind(Air.Env(), Air.Response(), Air.Env.from_env(), app.fin(req))
```

(`app.fin(req)` is a partial application over the plain parameter `env`;
`req` is affine and used once inside.) The dashboard does the same with
`Air.Error.json(env)` inside its `app(switch, req)`. State in the README
that an app which wants one read at startup can cache the `Env` in a
`Chan` or thread it through `serve_until`'s switch type in its own way;
this plan does not change `serve`.

### Step 5: laws

Under an "Errors" heading in `LAWS.bend`, `{==}` in `PROOF.bend`:

```
error_status_not_found:   Http.Error.status(Http.NotFound{""}) == 404
error_status_other:       Http.Error.status(Http.Other{418, ""}) == 418
error_reason_gone:        Http.Error.reason(Http.Gone{""}) == "Gone"
fail_carries_status:      Http.Response.status(Http.Response.fail(Http.Forbidden{"x"})) == 403
fail_reads_back:          Http.Response.error(Http.Response.fail(Http.Conflict{"c"})) == Some{Http.Conflict{"c"}}
whole_has_no_error:       Http.Response.error(Http.Response.text("hi")) == None{}
settle_prod_hides_detail: Http.Response.body(Http.Response.settle(Http.Prod{}, Http.Response.fail(Http.Internal{"disk"}))) == "Internal Server Error"
settle_dev_shows_detail:  Http.Response.body(Http.Response.settle(Http.Dev{}, Http.Response.fail(Http.Internal{"disk"}))) == "Internal Server Error\ndisk"
settle_keeps_type:        header(settle(Prod{}, with_type(fail(NotFound{""}), "text/html")), "content-type") == "text/html; charset=utf-8"
not_found_is_failed:      Http.Response.error(Http.Response.not_found()) == Some{Http.NotFound{""}}
not_found_renders_same:   Http.Response.render(Http.Response.not_found(), False{}, True{}) == "HTTP/1.1 404 Not Found\r\ncontent-type: text/plain; charset=utf-8\r\ncontent-length: 9\r\n\r\nNot Found"  (adjust to the exact header order `render` uses today; take it from the 405 law at LAWS.bend:157)
json_prod_shape:          Http.Response.body(Errors.json(Http.Prod{}, request("GET /nope HTTP/1.1\r"), Http.NotFound{"d"})) == "{\"status\":404,\"error\":\"Not Found\"}"
json_dev_shape:           ... == "{\"status\":404,\"error\":\"Not Found\",\"detail\":\"d\",\"path\":\"/nope\"}"
```

`on_error`, `attempt` and `Env.from_env` are IO and are proven live.

### Step 6: live checks

Record in the status row:

1. `AIR_ENV=dev`: `curl -si localhost:8080/boom` → 500, body has
   "Internal Server Error", "GET /boom", "the disk is on fire".
2. prod: same request → 500, body is exactly "Internal Server Error".
3. `curl -si localhost:8080/nope` → 404 through `plain` (dev shows
   `GET /nope` on the second line).
4. `curl -si localhost:8080/admin/whoami` → 401 with the detail in dev only.
5. Dashboard: `curl -si localhost:8080/api/nope` → 404 JSON;
   `curl -si -XPOST -H 'content-type: application/json' -d 'nope' localhost:8080/api/echo`
   → 400 JSON with `"detail":"body is not JSON"` in dev only.
6. `curl -si localhost:8080/env` → 200 with the value, or 500 with the
   effect's message in dev when the variable is unset (`env -u HOME`).
7. Remove `on_error` from hello's `use` temporarily: `/boom` → 500
   `text/plain` "Internal Server Error" from the server's settle, no
   detail even in dev. Restore.
8. `curl -I localhost:8080/nope` → 404 head only (HEAD path unchanged).

## Test plan

Thirteen laws for the pure parts; the eight live checks above.

## Done criteria

- [ ] `bend PROOF.bend` prints `All terms check.` with the new laws and every prior law.
- [ ] Live checks 1–8 pass and are noted in the index.
- [ ] `grep -n "Response.text(\"Not Found\")\|Response.text(\"Bad Request\")\|Response.text(\"Method Not Allowed\")" air/http.bend` returns nothing.
- [ ] `git diff --stat -- air/server.bend` touches only `respond` / `respond.pick`.
- [ ] README "Errors" section exists; `roadmap.md` Tier 4 is fully ticked.
- [ ] `.factory/plans/README.md` row 011 updated.

## STOP conditions

- `Body` cannot gain a `Data` variant holding `Error` (it can: `Error` is
  `Data`, but stop if the checker disagrees about `Body`'s kind).
- Settling inside `render` breaks a render law that cannot be restored by
  matching today's header order exactly. Report the law rather than
  changing its expected bytes.
- `attempt` cannot be typed generically even with a plain `Type` argument;
  ship a `String`-specialized `attempt_str` and report.
- `Env.from_env` per request measurably moves the benchmark (it should
  not: one `getenv`); report before changing `serve`'s signature (out of
  scope).

## Maintenance notes

- Tier 5 batteries should answer `Response.fail(..)` for their refusals
  (CORS, rate limit 429, schema 422) so one renderer owns every error page.
- If Tier 6 adds an `onError` lifecycle hook, it is `on_error` with a
  logging renderer wrapped around the app's; no new mechanism.
- Reviewers: check that no path writes a `detail` under `Prod{}`, that
  `render` output for the three router errors is byte-identical to before
  (the laws), and that `refuse` in the server did not change.
