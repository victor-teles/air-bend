# Plan 003: 405 carries a correct Allow header, HEAD falls back to GET, OPTIONS is answered automatically

> **Executor instructions**: Deliver the stated outcome within scope. Adapt routine
> implementation details to current code, preserve the listed contracts, and run
> the relevant acceptance checks. Fix task-caused failures and recheck affected
> behavior. Escalate only the material conditions below. Update the plan's status
> in `.factory/plans/README.md`.
>
> **Drift check**: Requires plan 002 (typed `Seg` patterns, `dispatch_with`).
> Confirm `air/router.bend` has `type Seg` and `dispatch_with` before starting;
> if not, execute 002 first.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW (router only; the server already handles HEAD bodies)
- **Depends on**: `.factory/plans/002-route-patterns.md`
- **Category**: direction (roadmap Tier 2: "405 with a correct Allow header", "Automatic HEAD from GET, automatic OPTIONS")
- **Planned at**: no commit yet (initial import staged), 2026-09-19

## Why this matters

A 405 without `Allow` violates RFC 9110 §15.5.6, `HEAD /` on a GET-only app
answers 405 today even though the server already knows to drop the body for
HEAD, and `OPTIONS` reaches the 404/405 fallback. After this plan every
miss on a known path lists the methods that would have worked, HEAD works
wherever GET does, and OPTIONS answers 204 with `Allow` unless the app
registered its own OPTIONS route.

## Current state

- `air/router.bend`: after plan 002, `Pick` is still

  ```
  type Pick is Type:
    Hit{handler: Handler(), params: Map<&2, String>}
    Miss{path_matched: Bool}
  ```

  `consider.fin(seen, handler, same_method, matched)` returns `Hit` on a
  method-and-path match, `Miss{True{}}` on a path-only match, else
  `Miss{seen}`. `fallback(path_matched)` picks 405 or 404. `run(pick, req)`
  executes. `dispatch_with(policy, routes, req)` is the entry point.
- `air/http.bend`: `Method` has `GET POST PUT DELETE PATCH HEAD OPTIONS Other{name}`;
  `Method.show`, `Method.is_eq` compare by shown name.
  `Response.method_not_allowed()` is a 405 with a text body and no `Allow`.
- `air/server.bend` `respond` (line ~448) already passes
  `Http.Method.is_eq(Http.Request.method(req), Http.HEAD{})` as `head_only`
  to `send`, and `Response.render` keeps `content-length` for HEAD. Nothing
  in the server needs to change for HEAD fallback.
- Plan 001 makes the `OPTIONS *` target parse to path `"*"`.
- Laws cannot compare a `Pick` (it holds a closure); they compare Data
  produced from it.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Check and prove | `bend PROOF.bend` | `All terms check.` |
| Run starter | `bend examples/hello/main.bend` | listens on 8080 |

## Implementation rules relevant to this plan

- Single pass over the route list: it is affine (closures), so "try HEAD
  routes, then GET routes" must be one fold with a richer accumulator, not
  two walks.
- No `if`; branch through helper defs matching on parameters.
- `Allow` values are deduplicated and sorted; alphabetical order from
  `Map.keys` is fine and deterministic for laws.

## Scope

**In scope**:
- `air/router.bend` — `Pick` redesign, `Allow` computation, HEAD and
  OPTIONS handling, `head` and `options` route constructors.
- `air/http.bend` — `Response.method_not_allowed(allow: String)` takes the
  header value; `Response.options(allow)` (204 with `Allow`).
- `air.bend` — `Route.head`, `Route.options`, updated
  `Response.method_not_allowed` wrapper.
- `LAWS.bend`, `PROOF.bend`, `README.md`.
- `.factory/plans/README.md` — status row.

**Out of scope**:
- `air/server.bend`.
- CORS preflight (Tier 5) — automatic OPTIONS answers only `Allow`.
- An `any`-method route.

## Git workflow

- Do not commit or push unless asked. `bend PROOF.bend` before any commit.

## Steps

### Step 1: richer `Pick`

```
# The outcome of walking the routes. `Hit` is an exact match. `Fallback`
# is a GET route found while serving HEAD, kept unless an explicit HEAD
# route turns up later. `Miss` carries the methods routes offered for
# this path, deduplicated, so 405 and OPTIONS can list them.
type Pick is Type:
  Hit{handler: Handler(), params: Map<&2, String>}
  Fallback{handler: Handler(), params: Map<&2, String>, allowed: Map<&2, String>}
  Miss{allowed: Map<&2, String>}
```

`consider` rules, in order:

- `Hit` wins and is carried through untouched.
- Route's path does not match (under the policy): keep the accumulator.
- Path matches and methods are equal: `Hit`.
- Path matches, request is `HEAD`, route is `GET`, accumulator is not
  `Hit`: `Fallback{handler, params, allowed + "GET"}` (a later GET does not
  replace an earlier `Fallback`; keep the first).
- Path matches, other method: add `Method.show(route method)` to `allowed`
  and keep `Fallback` or `Miss` as it was.

The `allowed` map is the set of methods routes offered for the path. When
rendering it, add `HEAD` if `GET` is present and always add `OPTIONS`, then
`String.join(Map.keys(&2, String, m), ", ")` (app-sized data, so Base
`String.join` is fine).

### Step 2: resolve the pick

`run(pick, req)`:

- `Hit` → handler.
- `Fallback` → handler (the server drops the body for HEAD).
- `Miss{allowed}` with the request method `OPTIONS` and a non-empty
  `allowed` → `Http.Response.options(render_allow(allowed))`.
- `Miss{allowed}` non-empty → `Http.Response.method_not_allowed(render_allow(allowed))`.
- `Miss` empty → 404.

For the `OPTIONS *` target (path `"*"`), every route counts as
path-matching: handle it in `consider.route` by treating a `"*"` request
path as matching any pattern (a Bool computed once in `dispatch_with` and
passed down). The answer is then 204 with the union of all methods.

### Step 3: responses and constructors

- `air/http.bend`: change `Response.method_not_allowed()` to
  `Response.method_not_allowed(allow: String)` adding the `allow` header;
  add `Response.options(allow: String)` as `Response.with_header(Response.empty(204), "allow", allow)`.
  `Status.reasons` already has 204 and 405.
- `air/router.bend`: add `head(path, handler)` and `options(path, handler)`
  beside `get`..`patch`.
- `air.bend`: `Route.head`, `Route.options`; update the
  `Response.method_not_allowed` wrapper to take `allow`. The server does
  not call `method_not_allowed` (grep to confirm; today only the router
  does).

### Step 4: laws

Add a pure `describe(pick: Pick) -> String` in the router that consumes the
pick and returns `"hit"`, `"fallback"`, or `"miss: " ++ render_allow(allowed)`,
plus a `pick(policy, routes, req) -> Pick` split out of `dispatch_with` so
laws can call `Router.describe(Router.pick(...))`. A request for laws comes
from `Http.Request.parse`; add `Http.Parsed.request(p, fallback)` or build
the `Request` directly in `LAWS.bend` through a helper that matches
`Parsed` (a helper def is allowed in `LAWS.bend`; it has `Laws.noop`
from plan 002 already).

```
law head_falls_back_to_get:
  {Router.describe(Router.pick(Router.Ignore{}, [Router.get("/", Laws.noop)], <HEAD / request>))
    == "hit-or-fallback" ...}
```

Write these concretely once the helpers exist; the behaviors to pin are:

1. `HEAD /` with only `GET /` registered → `"fallback"`.
2. `HEAD /` with `GET /` then `HEAD /` registered → `"hit"`.
3. `DELETE /x` with `GET /x` and `POST /x` registered → `"miss: GET, HEAD, OPTIONS, POST"`.
4. `DELETE /y` with nothing on `/y` → `"miss: "` (then 404 at `run`).
5. `Http.Response.header(Http.Response.method_not_allowed("GET, OPTIONS"), "allow") == "GET, OPTIONS"`.
6. `Http.Response.render(Http.Response.options("GET, OPTIONS"), False{}, True{})`
   equals `"HTTP/1.1 204 No Content\r\nallow: GET, OPTIONS\r\nconnection: keep-alive\r\n\r\n"`
   (header order follows `Map.to_list`, alphabetical; adjust if the
   renderer orders differently, but keep the law).
7. `OPTIONS *` with `GET /a` and `POST /b` registered → `"miss: GET, HEAD, OPTIONS, POST"`.

### Step 5: README and live check

README "API": `Air.dispatch` line gains "A HEAD request runs the GET route
when no HEAD route matches; 405 lists the allowed methods in `Allow`;
OPTIONS answers 204 with `Allow` unless a route claims it." Remove
"automatic HEAD for GET routes" from "Not yet". Add `Route.head`,
`Route.options` to the route constructors line.

Probes on `bend examples/hello/main.bend`:

| Request | Expect |
|---|---|
| `curl -sI localhost:8080/ \| head -1` | `HTTP/1.1 200 OK`, no body, `content-length` present |
| `curl -si -X DELETE localhost:8080/ \| grep -i '^allow\|^HTTP'` | `405`, `allow: GET, HEAD, OPTIONS` |
| `curl -si -X OPTIONS localhost:8080/echo \| grep -i '^allow\|^HTTP'` | `204`, `allow: OPTIONS, POST` |
| `curl -si -X OPTIONS --request-target '*' localhost:8080 \| grep -i '^allow\|^HTTP'` | `204`, all four methods plus HEAD and OPTIONS |
| `curl -si localhost:8080/nope \| head -1` | `404` |

## Test plan

Laws above; live probes recorded in the status row.

## Done criteria

- [ ] `bend PROOF.bend` prints `All terms check.` with the seven behaviors pinned.
- [ ] `grep -n "Fallback{" air/router.bend` shows the constructor and its use in `consider` and `run`.
- [ ] `grep -rn "method_not_allowed()" air air.bend examples` returns nothing (all callers pass `allow`).
- [ ] Live probes match.
- [ ] README updated; "automatic HEAD" gone from "Not yet".
- [ ] `git status --short` shows only in-scope files.

## STOP conditions

- The affine route list cannot be folded into a three-state `Pick` without
  the checker refusing a closure move; report the error rather than
  walking the list twice.
- Serving a HEAD fallback needs a change in `air/server.bend` (it should
  not; `respond` already drops the body).

## Maintenance notes

- Tier 5 CORS preflight will extend the automatic OPTIONS answer with
  `Access-Control-*` headers; keep `Response.options` as the single place
  that builds it.
- If an `any`-method route is added later, `render_allow` must expand it to
  the full method list.
- Reviewer focus: an explicit HEAD route listed after a GET route must win;
  `Allow` never lists a method twice.
