# Plan 010: Handlers compose through onion middleware, globally and per group, with per-request locals

> **Executor instructions**: Deliver the stated outcome within scope. Adapt routine
> implementation details to current code, preserve the listed contracts, and run
> the relevant acceptance checks. Fix task-caused failures and recheck affected
> behavior. Escalate only the material conditions below. Update the plan's status
> in `.factory/plans/README.md`.
>
> **Drift check**: `git diff --stat c989e4a -- air.bend air/http.bend air/router.bend examples LAWS.bend PROOF.bend README.md roadmap.md`
> should be empty or routine. Confirm `Handler()` is still
> `Http.Request -> IO(Http.Response)` at `air/router.bend:14`, that `Route` is
> the four-field `Route{method, pattern, slash, handler}` at `air/router.bend:49`,
> and that `Http.Request` has the eight fields listed below at `air/http.bend:102`.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: LOW (pure composition; the server does not change)
- **Depends on**: none
- **Category**: direction (roadmap Tier 4: pipeline model, global/per-group/per-route middleware, short-circuiting, per-request context)
- **Planned at**: commit `c989e4a`, 2026-09-20, clean tree

## Why this matters

Today an app is one function, `req => dispatch(routes(), req)`, and any
cross-cutting concern (logging, auth, timing, request IDs) has to be pasted
into every handler. The roadmap asks for one pipeline model, committed to
before anything in Tier 5 is built on it. This plan commits to the **onion
model**: a middleware is a function from the next handler to a handler, it
may run code before and after `next`, and it short-circuits by not calling
`next` at all. Bend's affine functions make this the only model that fits:
a hook-phase model needs a registry of callbacks that would be copied per
request, and functions cannot be copied. The onion needs no registry, and
the type checker enforces that `next` runs at most once.

Decisions, verified with scratch programs on Bend 2.0.10 during planning:

- **`Middleware() = Handler() -> Handler()`.** A middleware is written as a
  def with `next` first: `def logger(next: Handler, req: Request) -> IO(Response)`.
  Partially applied to `next` it is a handler; as a bare name it is a
  middleware. A configured middleware takes its config before `next`:
  `def auth(+token: String, next: Handler, req: Request)` and is used as
  `auth("secret")`. (Verified: a `+` config parameter followed by partial
  application checks and runs.)
- **Global**: `use(mws, handler)` folds a list of middleware around a handler,
  first in the list outermost. (Verified: `use([add(1), add(2)], double)(10)`
  answered 23, so `add(1)` ran last on the way out.)
- **Per group**: `Route.wrap(~mw, routes)` wraps every route's handler. The
  middleware is a template parameter (`~`) because a function value cannot be
  applied to N routes; a template is inlined per call site and may be called
  any number of times. A `~` argument must be closed: a top-level def, or a
  def partially applied to constants (`~auth("secret")`), never a local
  variable of the caller. (Verified: `wrap_each(~add(5), [double, double])`
  checks and runs.)
- **Per route**: no new API. `Route.get("/x", auth("s")(handler))` is a
  handler already, since `auth("s")` is `Handler -> Handler`.
- **Short-circuit**: a middleware that answers without calling `next` drops
  `next`; dropping an affine value is free. Nothing to build.
- **Per-request context**: `Request` gains a `locals: Map<&2, String>` field,
  set by middleware with `Request.with_local` and read downstream with
  `Request.local`. Values are strings, like params and query: a `Map` needs
  `Data` values, and strings are what every consumer (a log line, a header,
  a template) wants. Typed locals are rejected below.

## Current state

- `air/router.bend:14` — `def Handler() -> Type: Http.Request -> IO(Http.Response)`.
- `air/router.bend:49-53` — `type Route is Type: Route{method: Http.Method, pattern: List<&2, Seg>, slash: Bool, handler: Handler()}` and `new`.
- `air/router.bend:86-92` — `mount.go` rebuilds each `Route` with a new
  pattern; `wrap.go` will follow the same shape with a new handler.
- `air/router.bend:431-441` — `run(pick, req)` calls the picked handler with
  `Http.Request.with_params(req, params)`; unchanged by this plan.
- `air/http.bend:102-112` — `type Request is Data: Request{method, version, target, path, query, headers, params, body}`.
  Every accessor matches `case Request{m, v, tg, p, q, h, ps, b}` (about
  twenty sites in the file); the constructor is built at `air/http.bend:183`
  (`with_params`), `:188` (`with_body`) and `:657` (`Parsed{Request{...}}` in
  `parse`).
- `LAWS.bend:116` builds a `Http.Request{...}` literal with eight fields; it
  gains a ninth.
- `air.bend:90-96` — `Handler()` and `Stoppable()` aliases; `air.bend:550-620`
  is the "Routing" section of the facade (`Route.get` … `dispatch`).
- `examples/hello/main.bend` — seven routes, `app` is `Air.dispatch(routes(), req)`.
- `README.md:37` — "Middleware, static files, and handlers that share state."
  under "Not yet".
- Conventions: every def in `air/` is named relative to its module
  (`use`, not `Router.use`); the facade re-exports with a one-line comment;
  no `if`, branch through a helper def that matches a parameter; `+` on any
  parameter read twice; a `+` parameter cannot be the one abstracted by a
  partial application. A do-block binding is affine.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Check and prove | `bend PROOF.bend` | `All terms check.` |
| Run the example | `bend examples/hello/main.bend` | listens on 8080, logs one line per request |
| Probe timing | `curl -si localhost:8080/` | 200, and a log line `GET / -> 200 (N ms)` or similar |
| Probe short-circuit | `curl -si localhost:8080/admin/whoami` | `401`; with `-H 'x-token: secret'` → `200` and the body names the user from the local |
| Bench (optional) | `bench/run.sh` (see `bench/README.md`) | GET req/s within a few percent of 30.4k |

## Implementation rules relevant to this plan

- `Middleware()` and `use` live in `air/router.bend` next to `Handler()`;
  `wrap` lives after `mount`. Do not create a new module for three defs.
- `use` is a plain recursive fold; the list of middleware is `List<Middleware()>`
  (an affine list of closures, each used once). Order: the head of the list
  is outermost. Write it exactly as:

  ```
  def use(mws: List<Middleware()>, h: Handler()) -> Handler():
    match mws:
      case Nil{}:
        h
      case Con{m, rest}:
        m(use(rest, h))
  ```

- `wrap` is a template over the middleware:

  ```
  def wrap(~mw: Middleware(), routes: List<Route>) -> List<Route>:
    match routes:
      case Nil{}:
        Nil{}
      case Con{Route{m, pat, slash, h}, rest}:
        Con{Route{m, pat, slash, mw(h)}, wrap(~mw, rest)}
  ```

  Templates come first in the parameter list and may call only templates
  declared above them (this one calls only itself). The facade wrapper
  `Air.Route.wrap(~mw, routes)` must also be a template and pass `~mw` on.
- `locals` goes last in `Request` (after `body`) so the field order in the
  ~20 `case Request{...}` patterns changes by one appended name. `parse`
  seeds it with `Map.new(&2, String)`. `with_local(r, key, value)` sets one
  key; `local(r, key)` reads with `""` as default via `Text.map_get`, like
  `param`.
- A middleware that reads the request and also passes it on must rebind
  `+req = req` at the top of its body (`Request` is `Data`).
- Keep `dispatch`, `pick`, `run` byte-for-byte: this plan adds, it does not
  reroute.

## Scope

**In scope**:
- `air/router.bend` — `Middleware()`, `use`, `wrap`.
- `air/http.bend` — `locals` field, `Request.local`, `Request.with_local`,
  `Request.locals` (the whole map, for laws and logging).
- `air.bend` — `Air.Middleware()`, `Air.use`, `Air.Route.wrap`,
  `Air.Request.local`, `Air.Request.with_local`; the header comment gains a
  middleware example.
- `examples/hello/main.bend` — a global `timing` middleware and an `auth`
  middleware on a mounted `/admin` group that sets a local.
- `LAWS.bend`, `PROOF.bend` — laws below.
- `README.md` — drop "Middleware" from "Not yet"; add a short "Middleware"
  section with the two shapes (global `use`, group `wrap`).
- `roadmap.md` — tick the five Tier 4 lines this plan covers (pipeline
  model, global/per-route/per-group, short-circuiting, per-request context)
  with one-line notes in the style of Tiers 2 and 3. The remaining Tier 4
  lines belong to plan 011.
- `.factory/plans/README.md` — status row.

**Out of scope**:
- Error handling, `Env`, `fail`: plan 011.
- Anything in `air/server.bend`: the server calls the app once and needs no
  change.
- Typed or JSON-valued locals; a `Map<&2, Json.Value>` is possible but
  doubles the API for no consumer yet. Rejected in the index.
- `any`-method routes; still no need shown.
- Request logging with IDs (Tier 5) — the `timing` middleware in the example
  is a demo, not a framework feature.

## Git workflow

- Branch: the current worktree branch. Do not commit or push unless asked.
  `bend PROOF.bend` before any commit.

## Steps

### Step 1: `locals` on `Request`

Add the field, update every `case Request{...}` pattern in `air/http.bend`
(append one name), seed it in `parse`, add the three accessors next to
`Request.param` (`air/http.bend:157`). Fix the literal at `LAWS.bend:116`.

**Evidence**: `bend PROOF.bend` → `All terms check.` before any other change.

### Step 2: `Middleware`, `use`, `wrap` in the router

Add `Middleware()` right under `Handler()` with the comment: "A middleware
takes the next handler and gives a handler. Written as a def with `next`
first, `def logger(next: Handler(), req: Request)`, the bare name is a
middleware and `logger(h)` a handler. To answer without running `next`,
drop it." Add `use` after `Handler`/`Middleware`; add `wrap` after `mount`
with the template rule in its comment (closed argument: a def, or a def
applied to constants).

### Step 3: facade

`Air.Middleware()`, `Air.use(mws, handler)`, `Air.Route.wrap(~mw, routes)`,
`Air.Request.local`, `Air.Request.with_local`. Extend the header example in
`air.bend` with:

```
#   def timing(next: Air.Handler(), req: Air.Request()) -> IO(Air.Response()):
#     ...runs next, logs the elapsed time, returns its response...
#
#   def app(req: Air.Request()) -> IO(Air.Response()):
#     Air.use([timing], base)(req)
```

where `base` is `req => Air.dispatch(routes(), req)` written as a def
(`dispatch` takes `+req`, so it cannot be partially applied to a
`req`-less closure; a two-line def is the idiom).

### Step 4: example

In `examples/hello/main.bend`:

- `timing`: reads `IO.now()`, calls `next(req)`, reads `IO.now()` again,
  prints `method path -> status (N ms)` (the server already logs
  `method path -> status`; the example line adds the time), returns the
  response. Needs `+req` and the response rebound with `+`.
- `auth(+token, next, req)`: when `Air.Request.header(req, "x-token")`
  equals `token`, calls `next(Air.Request.with_local(req, "user", "victor"))`;
  otherwise answers `Air.Response.with_status(Air.Response.text("Unauthorized"), 401)`
  without calling `next`. (Plan 011 will turn that into `Air.fail`.)
- `whoami`: `Air.Response.text("you are " ++ Air.Request.local(req, "user"))`.
- routes: `Air.Route.all([public(), Air.Route.mount("/admin", Air.Route.wrap(~auth("secret"), admin()))])`;
  `app` is `Air.use([timing], base)(req)`.

### Step 5: laws

In `LAWS.bend` under a new "Middleware" heading, with `{==}` proofs in
`PROOF.bend`:

```
local_round_trip:      Http.Request.local(Http.Request.with_local(request("GET / HTTP/1.1\r"), "user", "v"), "user") == "v"
local_absent:          Http.Request.local(request("GET / HTTP/1.1\r"), "user") == ""
local_keeps_params:    Http.Request.param(Http.Request.with_local(Http.Request.with_params(r, {"id":"1"}), "k", "v"), "id") == "1"
wrap_keeps_patterns:   Router.pattern_of(Router.wrap(~ident, [Router.get("/a/:id", noop), Router.post("/b", noop)])) == Router.pattern_of([Router.get("/a/:id", noop), Router.post("/b", noop)])
wrap_keeps_conflicts:  Router.conflicts(Router.wrap(~ident, [Router.get("/a", noop), Router.get("/a", noop)])) == ["duplicate route: GET /a"]
```

where `ident` is a def `def ident(next: Router.Handler(), req: Http.Request) -> IO(Http.Response): next(req)`
declared in `LAWS.bend` above the laws (top-level defs are allowed as
template arguments). `use` and short-circuiting are IO and are proven live
(step 6); if `Router.pattern_of` cannot see through the template, write a
`Router.methods_of` helper instead and note it.

### Step 6: live checks

Run the example and record in the status row:

1. `curl -si localhost:8080/` → 200 and the timing log line.
2. `curl -si localhost:8080/admin/whoami` → 401, body `Unauthorized`, and
   **no** `whoami` side effect (the handler never ran: the timing line shows
   401).
3. `curl -si -H 'x-token: secret' localhost:8080/admin/whoami` → 200 `you are victor`.
4. `curl -si -H 'x-token: secret' localhost:8080/hello/x` → 200 (public
   route untouched by `auth`).
5. Order: temporarily put a second middleware in `use` that prints
   "inner"/"outer" and confirm the first in the list prints first on the
   way in and last on the way out; remove it after.

## Test plan

Laws for the pure parts (locals, `wrap`), the five live checks above. Run
`bench/run.sh` once if convenient; `use([timing], base)` adds two `IO.now`
calls per request, which should not move the number.

## Done criteria

- [ ] `bend PROOF.bend` prints `All terms check.` with the five new laws.
- [ ] `examples/hello/main.bend` runs; live checks 1–5 pass and are noted in the index.
- [ ] `Air.use`, `Air.Route.wrap`, `Air.Middleware()`, `Air.Request.local`, `Air.Request.with_local` exist in `air.bend` with comments.
- [ ] `air/server.bend` is unchanged (`git diff --stat -- air/server.bend` empty).
- [ ] README "Not yet" no longer lists middleware; a "Middleware" section exists.
- [ ] `roadmap.md` Tier 4 lines for this plan are ticked with notes.
- [ ] `.factory/plans/README.md` row 010 updated.

## STOP conditions

- The checker refuses `wrap` as a template (for instance because
  `List<Route>` recursion in a template is not allowed). Fallback to try
  first: make `wrap.go` the template and `wrap` a non-template that calls
  it. If neither checks, report; per-group middleware would then have to
  be a route-list-level fold that takes a `List<Middleware()>` one per
  route, which is a worse API and needs a decision.
- Adding `locals` breaks a law that pins `Request` equality in a way that
  cannot be fixed by adding the ninth field (none is known).
- The JS backend rejects a name introduced here (`use` is not a JavaScript
  reserved word; `wrap` and `local` are not either. Do not name anything
  `await`, `new`, `delete`, `default`).

## Maintenance notes

- Plan 011 adds `on_error` as a middleware in this shape and turns the
  example's 401 into `Air.fail`.
- Tier 5 batteries (CORS, security headers, rate limiting, request ID,
  sessions) are each one middleware def; static files are a handler.
- Reviewers: check that `use` order matches the documented "first is
  outermost" and that no `Request{...}` pattern was left with eight fields
  (the checker catches it, but the error message names the wrong site).
