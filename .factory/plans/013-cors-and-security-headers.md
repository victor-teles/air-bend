# Plan 013: CORS with preflight, a security-headers middleware, and failed responses that keep their headers

> **Executor instructions**: Deliver the stated outcome within scope. Adapt routine
> implementation details to current code, preserve the listed contracts, and run
> the relevant acceptance checks. Fix task-caused failures and recheck affected
> behavior. Escalate only the material conditions below. Update the plan's status
> in `.factory/plans/README.md`.
>
> **Drift check**: `git diff --stat 13be69e -- air.bend air/errors.bend air/http.bend air/router.bend examples LAWS.bend PROOF.bend README.md roadmap.md`
> should be empty or routine. Confirm `on_error.fin` at `air/errors.bend:20-26`
> still answers `render(req, e)` and nothing else, that `Response` is the
> four-field `Response{status, headers, cookies, body}` at `air/http.bend:964`,
> and that `Response.method_not_allowed` sets `allow` on a failed body at `:1054`.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: LOW (three middleware-shaped pure transforms; one small fix in `on_error`)
- **Depends on**: none (010 and 011 are shipped)
- **Category**: direction (roadmap Tier 5: CORS including preflight; security headers) plus one bug fix
- **Planned at**: commit `13be69e`, 2026-09-20, clean tree

## Why this matters

A browser app on another origin cannot call an Air API today: nothing answers
a preflight, and nothing adds `Access-Control-Allow-Origin`. And every
response should carry a few defensive headers that no handler wants to
remember. Both are one middleware each in the onion shape from plan 010.

**A bug found while planning, fixed here because both batteries depend on it**:
`on_error` replaces a failed response with what the renderer builds and drops
the failed response's headers. Verified live at planning time on
`examples/hello/main.bend`: `curl -si -X POST localhost:8080/` answers
`405 Method Not Allowed` with **no `allow` header**, while the router set one
(`Response.method_not_allowed`). The rate limiter of plan 015 needs
`Retry-After` on a 429 to survive rendering the same way, and CORS headers
added by a middleware inside `on_error` must survive too. Fix: the rendered
response inherits the failed response's headers and cookies, the renderer's
own headers winning on a clash.

Decisions:

- **CORS config is a value**, `Cors`, built with `Cors.any()` (every origin)
  or `Cors.new(origins)` (an exact list; scheme, host and port must match
  byte for byte, lowercase as browsers send them), and refined with
  `with_methods`, `with_headers`, `with_expose`, `with_credentials`,
  `with_max_age`. Defaults: methods `GET, HEAD, POST, PUT, PATCH, DELETE, OPTIONS`,
  allowed headers empty (a preflight echoes `Access-Control-Request-Headers`),
  no exposed headers, no credentials, max age 600.
- **Preflight is answered by the middleware** (204, no body) and never reaches
  the router, so the router's own `OPTIONS` answer (204 with `Allow`) is for
  same-origin clients only. A preflight is `OPTIONS` with a non-empty
  `Access-Control-Request-Method`.
- **A request without `Origin`** or from an origin not in the list goes
  through untouched: no CORS headers, no error. The browser enforces.
- **`Allow-Origin` is `*` under `Cors.any()` without credentials**, otherwise
  the request's origin echoed back, plus `Vary: Origin` (appended to an
  existing `Vary`). `Access-Control-Allow-Credentials: true` only with
  credentials, and then `*` is never sent.
- **Security headers are a list of (name, value)** the app can extend or
  override. `Shield.default()`: `x-content-type-options: nosniff`,
  `x-frame-options: DENY`, `referrer-policy: strict-origin-when-cross-origin`,
  `cross-origin-opener-policy: same-origin`, `cross-origin-resource-policy: same-origin`,
  `x-permitted-cross-domain-policies: none`. Opt-in: `with_hsts(seconds)`
  (`strict-transport-security: max-age=N; includeSubDomains`; off by default
  because Air runs behind a TLS proxy and HSTS from a plain-HTTP dev server
  is a footgun), `with_csp(policy)`, `with_frame(value)`, `with_header(name, value)`.
  The middleware sets each header **only when the response lacks it**, so a
  handler's own value wins.
- Not in scope: per-route CORS (wrap a group with `Route.wrap(~Air.cors(cfg), routes)`
  already works for that), origin patterns or wildcards in subdomains,
  `Access-Control-Allow-Private-Network`.

## Current state

- `air/errors.bend:20-33` — `on_error.fin` / `on_error.go` / `on_error`.
- `air/http.bend:964-1010` — `Response`, `Response.header`, `Response.with_header`
  (lowercases the name, `Map.set`), `Response.with_cookie` appends to `cookies`.
- `air/http.bend:1054` — `Response.method_not_allowed(allow)` = `with_header(fail(Status{405, ""}), "allow", allow)`.
- `air/router.bend` — `Middleware()`, `use`, `wrap`; `dispatch` answers OPTIONS
  itself with 204 and `Allow` (plan 003).
- `air/text.bend:162` — `has_token(v, tok)` splits a comma list; reuse for
  origin lists rendered as text if handy, but origins are a `List<&2, String>`.
- Base: `Map.union(m, n)` sets `n`'s entries over `m` (n wins), verified in
  `bend base Map.union`.
- `examples/hello/main.bend` — `app.fin` uses `[timing, Air.on_error(...)]`.
- Conventions as in plan 010: `+` config before `next`; helper defs instead
  of `if`; module-relative names; constructors through the alias.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Check and prove | `bend PROOF.bend` | `All terms check.` |
| Run the example | `bend examples/hello/main.bend` | listens on 8080 |
| 405 keeps Allow | `curl -si -X POST localhost:8080/` | `405` **with** `allow: GET, HEAD, OPTIONS` |
| Preflight | `curl -si -X OPTIONS localhost:8080/echo -H 'Origin: http://a.test' -H 'Access-Control-Request-Method: POST' -H 'Access-Control-Request-Headers: content-type'` | `204`, `access-control-allow-origin`, `-allow-methods`, `-allow-headers: content-type`, `-max-age`, `vary: origin` |
| Simple request | `curl -si localhost:8080/ -H 'Origin: http://a.test'` | `200` with `access-control-allow-origin` |
| Shield | `curl -si localhost:8080/` | the six default headers present |

## Implementation rules relevant to this plan

- **Step 1 fix** in `air/http.bend`: `Response.inherit(from: Response, r: Response) -> Response`
  answers `r` with `Map.union(from.headers, r.headers)` and cookies
  `from.cookies ++ r.cookies`; status and body are `r`'s. Then `on_error.fin`'s
  `Some{e}` branch becomes `Response.inherit(res, render(req, e))`; the
  `res` is already `+` in `on_error.go`, so pass it down. The renderer's
  `content-type` wins because `Map.union` prefers its second argument;
  prove it with a law rather than trusting the reading.
- **CORS** in a new `air/cors.bend` (alias `Cors`), importing `Base`,
  `./text.bend`, `./http.bend`, `./router.bend`:
  - `type Cors is Data: Cors{origins: List<&2, String>, methods: String, headers: String, expose: String, credentials: Bool, max_age: U32}`;
    `any()`, `new(origins)`, the five `with_*`.
  - `allowed(+cfg: Cors, +origin: String) -> Bool`: `origins` empty means any;
    else exact membership.
  - `origin_value(+cfg: Cors, +origin: String) -> String`: `"*"` when
    `origins` is empty and `credentials` is false; else `origin`.
  - `add_vary(r: Response) -> Response`: sets `vary: origin`, or appends
    `, origin` to an existing `vary` that lacks the token (`Text.has_token`).
  - `decorate(+cfg, +origin, r) -> Response`: `access-control-allow-origin`,
    `access-control-allow-credentials: true` when set, `access-control-expose-headers`
    when non-empty, then `add_vary`.
  - `preflight(+cfg, +origin, +req) -> Response`: `Response.empty(204)` plus
    `decorate`, `access-control-allow-methods`, `access-control-allow-headers`
    (config value, else the request's `access-control-request-headers` when
    non-empty, else absent), `access-control-max-age`.
  - `is_preflight(+req) -> Bool`: method is OPTIONS and
    `Request.header(req, "access-control-request-method")` is non-empty.
  - `cors(+cfg: Cors, next: Router.Handler(), req: Http.Request) -> IO(Http.Response)`:
    `+req = req`; origin = `Request.header(req, "origin")`; when origin is
    empty or not allowed → `next(req)`; when preflight → pure `preflight`
    (drop `next`); else `IO.bind(next(req), r => pure(decorate(cfg, origin, r)))`.
    Three-way branch through a small sum type or two helper defs.
- **Shield** in a new `air/shield.bend` (alias `Shield`): `Shield() -> Type`
  is `List<&2, Sigma<&2, &2, String, _ => String>>` (the `Text.Pair` shape;
  `Text.Two` exists as a constructor for it, check `air/text.bend:11`).
  `default()`, `with_hsts(hs, seconds)`, `with_csp(hs, policy)`, `with_frame(hs, value)`,
  `with_header(hs, name, value)` (replace by name, else append; names
  lowercased). `Http.Response.with_default_header(r, name, value)` sets only
  when `Response.header(r, name)` is `""`. `apply(hs, r)` folds it.
  `shield(+hs: Shield(), next, req) -> IO(Response)`: `next(req)` then `apply`.
  Note `hs` is a list of strings: Data, so `+` is fine.
- Facade (`air.bend`): types `Air.Cors()`, `Air.Shield()`; builders
  `Air.Cors.any`, `Air.Cors.new`, `Air.Cors.with_methods/with_headers/with_expose/with_credentials/with_max_age`,
  `Air.Shield.default/with_hsts/with_csp/with_frame/with_header`; middleware
  `Air.cors(cfg)`, `Air.shield(hs)`; `Air.Response.with_default_header`.
  A new "Batteries" section after "Middleware" holds the two middleware; the
  config builders go under their own headings like `Cookie`.
- Order guidance in the facade comment: `use([Air.shield(hs), Air.cors(cfg), Air.on_error(..)], base)`.
  `cors` outside `on_error` so an error response also gets CORS headers;
  with step 1 the reverse order works too.

## Scope

**In scope**:
- `air/http.bend`: `Response.inherit`, `Response.with_default_header`.
- `air/errors.bend`: `on_error.fin` uses `inherit`.
- `air/cors.bend`, `air/shield.bend` (new); `air.bend`; `LAWS.bend`; `PROOF.bend`.
- `examples/hello/main.bend`: `app.fin` becomes
  `Air.use([timing, Air.shield(Air.Shield.default()), Air.cors(Air.Cors.any()), Air.on_error(...)], base)`.
  `examples/dashboard/main.bend`: `Air.shield(Air.Shield.default())` and
  `Air.cors(Air.Cors.new(["http://localhost:5173"]))` (a Vite-style dev
  origin, as the comment says) around `on_error`.
- `README.md`: a "CORS and security headers" paragraph under Middleware.
- `roadmap.md`: tick "CORS, including preflight" and "Security headers".
- `.factory/plans/README.md`: row 013 and a line in "Findings" about the
  405/Allow bug.

**Out of scope**: rate limiting (015), request IDs (014), anything in `air/server.bend`.

## Git workflow

- Current worktree branch. Do not commit or push unless asked. `bend PROOF.bend` first.

## Steps

### Step 1: failed responses keep their headers

`Response.inherit`, the `on_error.fin` change, and these laws before anything else:

```
inherit_keeps_allow:    Http.Response.header(Http.Response.inherit(Http.Response.method_not_allowed("GET"), Http.Response.text("x")), "allow") == "GET"
inherit_renderer_wins:  Http.Response.header(Http.Response.inherit(Http.Response.with_header(Http.Response.fail(Http.NotFound{""}), "content-type", "a"), Http.Response.text("x")), "content-type") == "text/plain; charset=utf-8"
inherit_keeps_cookies:  Http.Response.cookies(Http.Response.inherit(Http.Response.with_cookie(Http.Response.fail(Http.NotFound{""}), Http.Cookie.new("a", "1")), Http.Response.text("x"))) == [Http.Cookie.render(Http.Cookie.new("a", "1"))]
```

(add a `Response.cookies` accessor if there is none). Live: `curl -si -X POST localhost:8080/` shows `allow`.

### Step 2: `air/cors.bend`

Pure defs first, then the middleware. Laws:

```
cors_any_allows:         Cors.allowed(Cors.any(), "http://a.test") == True{}
cors_list_exact:         Cors.allowed(Cors.new(["http://a.test"]), "http://a.test:81") == False{}
cors_star_without_creds: Cors.origin_value(Cors.any(), "http://a.test") == "*"
cors_echo_with_creds:    Cors.origin_value(Cors.with_credentials(Cors.any(), True{}), "http://a.test") == "http://a.test"
cors_vary_appends:       Http.Response.header(Cors.add_vary(Http.Response.with_header(Http.Response.text(""), "vary", "Accept")), "vary") == "Accept, origin"
cors_preflight_methods:  Http.Response.header(Cors.preflight(Cors.any(), "http://a.test", request("OPTIONS /x HTTP/1.1\r\nOrigin: http://a.test\r\nAccess-Control-Request-Method: POST\r\nAccess-Control-Request-Headers: x-a\r")), "access-control-allow-headers") == "x-a"
cors_is_preflight:       Cors.is_preflight(request("OPTIONS /x HTTP/1.1\r\nAccess-Control-Request-Method: POST\r")) == True{}
```

using the `request(...)` law helper already in `LAWS.bend` (check its exact
name and how it takes a head).

### Step 3: `air/shield.bend`

```
shield_default_nosniff:  Http.Response.header(Shield.apply(Shield.default(), Http.Response.text("")), "x-content-type-options") == "nosniff"
shield_handler_wins:     Http.Response.header(Shield.apply(Shield.default(), Http.Response.with_header(Http.Response.text(""), "x-frame-options", "SAMEORIGIN")), "x-frame-options") == "SAMEORIGIN"
shield_hsts_opt_in:      Http.Response.header(Shield.apply(Shield.default(), Http.Response.text("")), "strict-transport-security") == ""
shield_with_hsts:        Http.Response.header(Shield.apply(Shield.with_hsts(Shield.default(), 3600), Http.Response.text("")), "strict-transport-security") == "max-age=3600; includeSubDomains"
```

### Step 4: facade, examples, docs

### Step 5: live checks

On the hello example, record in the index:

1. `curl -si -X POST localhost:8080/` → 405 with `allow: GET, HEAD, OPTIONS`.
2. The preflight command above → 204 with the five CORS headers and `vary: origin`; no `allow` header (the router never ran).
3. `curl -si localhost:8080/ -H 'Origin: http://a.test'` → 200, `access-control-allow-origin: *`.
4. `curl -si localhost:8080/` → no `access-control-*`; the six shield headers present.
5. `curl -si localhost:8080/boom -H 'Origin: http://a.test'` → 500 rendered by `on_error` **and** `access-control-allow-origin` present.
6. On the dashboard: `curl -si localhost:8080/api/tasks -H 'Origin: http://evil.test'` → 200 without CORS headers; with `Origin: http://localhost:5173` → with them.

## Test plan

Fourteen laws; six live checks. Optional: `bench/run.sh` once; two extra
`Map.set` per response should not move 30.4k req/s by more than noise.

## Done criteria

- [ ] `bend PROOF.bend` prints `All terms check.` with the new laws.
- [ ] 405 under `on_error` carries `allow` (live check 1).
- [ ] Live checks 2–6 pass and are noted in the index.
- [ ] `Air.cors`, `Air.shield`, `Air.Cors.*`, `Air.Shield.*`, `Air.Response.with_default_header` exist with comments.
- [ ] README, roadmap, index updated; `air/server.bend` unchanged.

## STOP conditions

- `Map.union` precedence is the other way round (law `inherit_renderer_wins`
  fails): swap the arguments; if neither order works, fold `r`'s headers over
  `from`'s with `Map.set` via `Map.to_list`. Not a stop, a fallback.
- A `Sigma` list as a `+` parameter is refused: hold the shield as
  `Map<&2, String>` instead (order of headers on the wire does not matter).
- The three-way branch in `cors` cannot be expressed without matching a
  computed value: introduce `type Mode is Data: Skip{} Preflight{} Simple{}`
  computed by a pure def and matched by a helper.

## Maintenance notes

- Plan 015 relies on step 1 so that `retry-after` survives `on_error`.
- Plan 014's `request_id` sets `x-request-id` before `on_error` and relies on
  step 1 as well when the response is a failure rendered inside it.
