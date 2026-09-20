# Plan 002: Routes support wildcards, mounting, a trailing-slash policy, and a startup conflict check

> **Executor instructions**: Deliver the stated outcome within scope. Adapt routine
> implementation details to current code, preserve the listed contracts, and run
> the relevant acceptance checks. Fix task-caused failures and recheck affected
> behavior. Escalate only the material conditions below. Update the plan's status
> in `.factory/plans/README.md`.
>
> **Drift check**: The repo had no commits when this was planned. Plan 001 is
> expected to have landed first (`Request.target` exists, `Request.path` is
> normalized and keeps a trailing slash). If it has not, either execute 001
> first or, for the Redirect policy only, read the raw query from
> `Request.path`'s sibling data and note the gap in the status row.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED (changes `Route`'s shape; every route in both examples goes through it)
- **Depends on**: `.factory/plans/001-path-decoding.md` (for the Redirect policy's raw query and the preserved trailing slash)
- **Category**: direction (roadmap Tier 2: wildcards, sub-routers/prefix groups, trailing-slash policy, conflict detection)
- **Planned at**: no commit yet (initial import staged), 2026-09-19

## Why this matters

The router matches literal and `:param` segments, first route wins, and
nothing else. Apps cannot capture a tail (`/files/*path`), cannot group routes
under a prefix without repeating it, get no say on `/users/` versus `/users`,
and a duplicated route silently shadows the later one. This plan gives
patterns a real grammar, a `mount` for prefixes, an explicit slash policy
whose default keeps today's behavior, and a check an app runs once at
startup that reports duplicate or malformed routes before the server listens.

Decisions taken here (override in the status row if the operator disagrees):

- **No radix tree.** Handlers are affine closures, so `routes()` is rebuilt
  per request by design (see the comment at the top of `air.bend`). A tree
  built per request costs more than the linear scan it replaces, and a tree
  shared across requests cannot hold the handlers. Linear scan over
  pre-classified segments stays; revisit only if a benchmark shows routing
  above a few percent of a request.
- **No optional segments.** `:name?` interacts badly with conflict detection
  and with 405 computation. Register two routes, or use a wildcard.
- **First match wins** stays the rule; there is no specificity ordering.
  The conflict check exists so that a shadowed duplicate is a startup error
  rather than a surprise.

## Current state

- `air/router.bend` (119 lines) — `Route{method, pattern: List<&2, String>, handler}`,
  `new(method, path, handler)` splits `path` with `Text.segments`.
  `bind_segment` (line 39) decides `:name` versus literal at match time:

  ```
  def bind_segment(m: Map<&2, String>, +pat: String, +seg: String) -> Maybe<&2, Map<&2, String>>:
    match pat:
      case SCon{':', name}:
        Some{Map.set(&2, String, m, name, seg)}
      case _:
        bind_segment.lit(m, String.eq(pat, seg))
  ```

  `match_path(pat, segs, params)` (line 47) walks both lists in step and
  fails on a length mismatch. `Pick` is `Hit{handler, params} | Miss{path_matched}`;
  `select` folds `consider` over the list; `dispatch(routes, req)` runs the pick.
- `air.bend` re-exports `Route.get/post/put/delete/patch` and `dispatch`.
  `Route()` is `def Route() -> Type: Router.Route` (a Type, not Data, because
  it holds a closure), so route lists are `List<Route()>` with the default
  quant.
- `LAWS.bend` has four routing laws (`segments_drop_empty`, `route_binds_param`,
  `route_rejects_literal`, `route_rejects_length`) that call
  `Router.match_path(["users", ":id"], ["users", "42"], Some{Map.new(&2, String)})`.
  Those laws must be updated to the new pattern type, not deleted.
- `examples/hello/main.bend` and `examples/dashboard/main.bend` build route
  lists with `Air.Route.get(...)`; `main` calls `Air.serve` / `Air.serve_until`.
- Bend constraints (from `AGENTS.md`): defs above use, no mutual recursion,
  `match` only on parameters, no `if`, a `+` parameter cannot be the one
  abstracted by a partial application. A value holding a closure cannot be
  `+`, so a `List<Route>` is consumed by whatever walks it: `check` must be
  called on its own fresh `routes()` value, and `dispatch` on another.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Check and prove | `bend PROOF.bend` | `All terms check.` |
| Run starter | `bend examples/hello/main.bend` | listens on 8080 |
| Run dashboard | `bend examples/dashboard/main.bend` | listens on 8080 |

## Implementation rules relevant to this plan

- Inside `air/router.bend`, name defs relative to the module and avoid Base
  names. `Seg`, `Slash`, `mount`, `conflicts`, `check` are free.
- Keep `dispatch(routes, req)` with its current signature and its current
  behavior (Ignore policy) so the examples keep working with no change.
- Laws test pure defs that return Data. `Pick` and `Route` hold closures, so
  a law can consume a route list built with a dummy handler and compare a
  `List<&2, String>` or `Maybe` result, but never compare a `Pick`.
- A pattern is parsed once, in `new`, never at match time.

## Scope

**In scope**:
- `air/router.bend` — `Seg`, pattern parsing, wildcard matching, `Slash`
  policy, `dispatch_with`, `mount`, `conflicts`, `check`.
- `air.bend` — `Air.Slash.*`, `Air.dispatch_with`, `Air.Route.mount`,
  `Air.Route.all`, `Air.Route.check`.
- `LAWS.bend`, `PROOF.bend` — update the four routing laws, add new ones.
- `README.md` — routing section.
- `examples/hello/main.bend`, `examples/dashboard/main.bend` — call
  `Air.Route.check` in `main`; the dashboard mounts its `/api` routes.
- `.factory/plans/README.md` — status row.

**Out of scope**:
- `air/http.bend`, `air/server.bend`, `air/text.bend` — no edits; if a
  helper is missing, add it to `air/router.bend`.
- 405 `Allow`, automatic HEAD/OPTIONS — plan 003. Keep `Miss{path_matched}`
  as is; plan 003 replaces it.
- A radix tree, optional segments, regex segments, an `any` method route.

## Git workflow

- Do not commit or push unless asked. `bend PROOF.bend` before any commit.

## Steps

### Step 1: a typed pattern

Replace `pattern: List<&2, String>` with `pattern: List<&2, Seg>`:

```
# One segment of a route pattern. `Rest` is `*name`: it must be last and
# binds the remaining path, joined with "/", possibly "".
type Seg is Data:
  Lit{text: String}
  Param{name: String}
  Rest{name: String}
```

`classify(+s: String) -> Seg` matches `SCon{':', name}` → `Param{name}`,
`SCon{'*', name}` → `Rest{name}`, else `Lit{s}`. `parse_pattern(path)` maps
`classify` over `Text.segments(path)` (use `List.map` with the explicit
type args, or a tail-recursive `.go` with an accumulator to stay in the
module's style). `Route` also records `slash: Bool`: the pattern ended with
`/` and is longer than `/` (compute with `String.ends_with` on the pattern
string given by the app; it is app data, not request data, so Base helpers
are fine).

Rewrite `bind_segment` to match on `Seg` instead of inspecting the first
char. In `match_path`, when the pattern head is `Rest{name}`, bind `name`
to the remaining request segments joined by `/` (a `.go` that folds with
`Text.append` and returns `Some{..}`), ignoring anything after `Rest` in
the pattern. `Rest` matches zero or more segments, so `/files/*p` matches
`/files` with `p == ""`.

### Step 2: trailing-slash policy

```
# What a trailing slash means. `Ignore` (the default) treats "/a/" and
# "/a" as the same path. `Strict` matches a route only when the request
# and the pattern agree on the slash. `Redirect` answers 308 to the path
# without the slash, query kept, and never redirects "/".
type Slash is Data:
  Ignore{}
  Strict{}
  Redirect{}
```

`dispatch_with(policy: Slash, routes, +req)`:

- Compute `path_slash: Bool` from `Http.Request.path(req)` (ends with `/`,
  length > 1). Under plan 001 this is reliable; `Text.segments` never sees
  it, so matching is unaffected.
- `Ignore`: behave exactly as `dispatch` does today.
- `Strict`: a route is considered only when `route.slash == path_slash`.
  Pass the Bool into `consider.route` and add it to the `same_method` gate.
- `Redirect`: when `path_slash`, do not consult routes; answer
  `Http.Response.with_header(Http.Response.empty(308), "location", stripped)`
  where `stripped` is the path minus its last char, plus `"?" ++ qs` when
  the raw target (`Http.Request.target(req)`, split at `?`) has a non-empty
  query. Add `308` → `"Permanent Redirect"` to `Status.reasons` only if it
  is missing; it is missing today, and that edit in `air/http.bend` is the
  one exception to the out-of-scope list (one line).
- `dispatch(routes, req)` becomes `dispatch_with(Ignore{}, routes, req)`.

### Step 3: mounting

```
# Prefixes every route with `prefix`; "/api" + "/users/:id" is
# "/api/users/:id". The prefix may itself contain params or a wildcard,
# but a wildcard in the prefix makes every route under it unreachable.
def mount(prefix: String, routes: List<Route>) -> List<Route>:
```

Parse the prefix once, then rebuild each `Route` with
`List.append(&2, Seg, prefix_segs, pattern)`. The route list is consumed and
rebuilt (it holds closures), so walk it with an accumulator and reverse.
Add `all(groups: List<List<Route>>) -> List<Route>` as `List.concat` so an
app can write `Air.Route.all([Air.Route.mount("/api", api()), pages()])`.

### Step 4: conflict check

Two routes conflict when their methods are equal and their patterns have
the same shape: `Lit` equal by text, `Param` equal to any `Param`, `Rest`
equal to any `Rest`. A pattern is malformed when a `Rest` is not last.

```
# Renders the shape of a pattern, params and wildcards anonymized:
# "/users/:/*". Two routes with the same method and shape conflict.
def shape(pattern: List<&2, Seg>) -> String:

# Every problem in a route list, one line each, in list order:
#   "duplicate route: GET /users/:" and "wildcard not last: GET /a/*/b".
# Empty when the list is clean. The list is consumed.
def conflicts(routes: List<Route>) -> List<&2, String>:
```

Implement `conflicts` with a `Map<&2, String>` keyed by
`Method.show(m) ++ " " ++ shape(pattern)` (`Map.has` is the test) and an
accumulator of messages, returning `List.reverse`. Then:

```
# Prints each conflict and ends the process with code 1; returns
# quietly when the routes are clean. Call it in `main` before `serve`.
def check(routes: List<Route>) -> IO(Unit):
```

`IO.die(Unit, 1, msg)` is how `Air.exit` ends the process (`air.bend`,
last def); use it with the joined messages. Print each line with
`IO.print` first so the user sees all of them.

### Step 5: facade, examples, README

- `air.bend`: `def Slash() -> Data: Router.Slash`; `Slash.ignore()`,
  `Slash.strict()`, `Slash.redirect()` constructors (constructors cannot be
  re-exported); `dispatch_with(policy, routes, req)`; `Route.mount`,
  `Route.all`, `Route.check`. Document each in the same voice as the
  neighbors.
- `examples/hello/main.bend`: `main` becomes
  ```
  def main() -> IO(Unit):
    do IO<Unit>:
      Air.Route.check(routes())
      Air.serve(~app, 8080)
  ```
- `examples/dashboard/main.bend`: split `routes(switch)` into `pages()`
  and `api(switch)` (paths without `/api`), combine with
  `Air.Route.all([pages(), Air.Route.mount("/api", api(switch))])`, and add
  the check to `main` before `serve_until`.
- `README.md`: in "API", document `*name` on the `Route.get / ...` line,
  add lines for `Air.Route.mount`, `Air.Route.all`, `Air.Route.check`, and
  `Air.dispatch_with(policy, routes, req)` with the three policies. Note that
  route order decides between overlapping routes and that `check` is the
  duplicate guard.

### Step 6: laws

Update the existing four to the new type, for example:

```
law route_binds_param:
  {Router.match_path([Router.Lit{"users"}, Router.Param{"id"}], ["users", "42"], Some{Map.new(&2, String)})
    == Some{Map.set(&2, String, Map.new(&2, String), "id", "42")}
    : Maybe<&2, Map<&2, String>>}
```

Add, with proofs in the same positions:

```
law classify_segments:
  {[Router.classify("users"), Router.classify(":id"), Router.classify("*rest")]
    == [Router.Lit{"users"}, Router.Param{"id"}, Router.Rest{"rest"}] : List<&2, Router.Seg>}

law wildcard_binds_tail:
  {Router.match_path([Router.Lit{"files"}, Router.Rest{"p"}], ["files", "a", "b"], Some{Map.new(&2, String)})
    == Some{Map.set(&2, String, Map.new(&2, String), "p", "a/b")} : Maybe<&2, Map<&2, String>>}

law wildcard_binds_empty:
  {Router.match_path([Router.Lit{"files"}, Router.Rest{"p"}], ["files"], Some{Map.new(&2, String)})
    == Some{Map.set(&2, String, Map.new(&2, String), "p", "")} : Maybe<&2, Map<&2, String>>}

law shape_anonymizes:
  {Router.shape([Router.Lit{"users"}, Router.Param{"id"}, Router.Rest{"r"}]) == "/users/:/*" : String}

law mount_prefixes:
  {Router.pattern_of(Router.mount("/api", [Router.get("/users/:id", <dummy handler>)]))
    == [[Router.Lit{"api"}, Router.Lit{"users"}, Router.Param{"id"}]] : List<&2, List<&2, Router.Seg>>}

law conflicts_finds_duplicate:
  {Router.conflicts([Router.get("/users/:id", <dummy>), Router.get("/users/:name", <dummy>)])
    == ["duplicate route: GET /users/:"] : List<&2, String>}

law conflicts_allows_methods:
  {Router.conflicts([Router.get("/users", <dummy>), Router.post("/users", <dummy>)])
    == [] : List<&2, String>}

law conflicts_flags_wildcard_position:
  {Router.conflicts([Router.get("/a/*x/b", <dummy>)])
    == ["wildcard not last: GET /a/*/b"] : List<&2, String>}

law redirect_target_keeps_query:
  {Router.redirect_target("/users/", "/users/?page=2") == "/users?page=2" : String}
```

`<dummy>` is a handler def declared in `LAWS.bend`
(`def Laws.noop(req: Http.Request) -> IO(Http.Response): IO.pure(Http.Response, Http.Response.empty(204))`),
and `pattern_of(routes) -> List<&2, List<&2, Seg>>` is a small helper in
the router that drops handlers so laws can compare patterns. Adjust names
to whatever you implement, but keep one law per behavior above.

### Step 7: live check

Start the dashboard and probe:

| Request | Expect |
|---|---|
| `curl -s localhost:8080/api/hello/bend` | `{"greeting":"Hello, bend!"}` (mounted) |
| `curl -s localhost:8080/api/tasks/` | 200 (Ignore policy) |
| duplicate a route in `routes()` and start | process prints `duplicate route: ...` and exits 1 |

Then temporarily switch the hello app to `Air.dispatch_with(Air.Slash.redirect(), ...)`
and confirm `curl -si 'localhost:8080/search/?q=1' | head -3` shows
`308` and `location: /search?q=1`; revert the example afterwards.

## Test plan

Laws above. No other harness exists.

## Done criteria

- [ ] `bend PROOF.bend` prints `All terms check.`; the four original routing laws still exist, rewritten to `Seg`.
- [ ] `grep -n "Rest{" air/router.bend` shows the constructor, `classify`, `match_path`, and `shape`.
- [ ] Both examples call `Air.Route.check` in `main` and start cleanly.
- [ ] `examples/dashboard/main.bend` uses `Air.Route.mount("/api", ...)`.
- [ ] README documents wildcards, mount, all, check, and the slash policies.
- [ ] Live probes match; the duplicate-route probe exits 1 with the message.
- [ ] `git status --short` shows only in-scope files (plus the one-line 308 reason in `air/http.bend`).

## STOP conditions

- Plan 001 has not landed and the Redirect policy cannot rebuild the query:
  finish everything else, implement Redirect without the query, and report.
- The checker rejects `List<&2, Seg>` inside `Route` (a Data list inside a
  Type record) in a way that needs a different representation; report the
  error before redesigning `Route`.
- A change here forces edits to `air/server.bend`.

## Maintenance notes

- Plan 003 replaces `Miss{path_matched}` with a list of allowed methods;
  it should build on `consider.route`'s new `Seg` matching without touching
  `classify`, `mount`, or `conflicts`.
- If a static-file route arrives (Tier 5), it will use `Rest` for the file
  path and must re-check `..` even though plan 001 resolves dots, because a
  decoded `%2F` inside one segment can reintroduce a `/`.
- Reviewer focus: `Rest` bound to `""` on an exact prefix match, the
  Redirect policy never redirecting `/`, and `check` consuming its own
  `routes()` value rather than the one `dispatch` uses.
