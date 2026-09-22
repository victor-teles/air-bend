# Plan 015: A shared store on every request, and a fixed-window rate limiter over it

> **Executor instructions**: Deliver the stated outcome within scope. Adapt routine
> implementation details to current code, preserve the listed contracts, and run
> the relevant acceptance checks. Fix task-caused failures and recheck affected
> behavior. Escalate only the material conditions below. Update the plan's status
> in `.factory/plans/README.md`.
>
> **Drift check**: `git diff --stat 13be69e -- air.bend air/http.bend air/server.bend air/drain.bend air/errors.bend examples LAWS.bend PROOF.bend README.md roadmap.md`
> should show only plan 013's changes (`Response.inherit`, `on_error`) and
> plan 014's (`Server.log` call site, `air/log.bend`). Confirm `Http.Request`
> has nine fields (`locals` last) at `air/http.bend:102`, that `Server.Ctx`
> is the five-field record at `air/server.bend:108`, and that `run` calls
> `app(Ctx.switch(ctx), Http.Request.with_body(req, body))` at `:636`.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MEDIUM (touches `Request` and the server's `Ctx`; the store is a lock every limited request takes)
- **Depends on**: 013 (a 429's `retry-after` must survive `on_error`)
- **Category**: direction (roadmap Tier 5: rate limiting; README "handlers that share state")
- **Planned at**: commit `13be69e`, 2026-09-20, clean tree

## Why this matters

Nothing in Air can remember anything between two requests. A rate limiter, a
session store, a visit counter: each needs one value shared by every
connection. Bend has no globals, and a value created in `main` cannot be
closed into the app, because the app is a template argument and **templates
take only closed arguments**. Verified at planning time with a scratch
program: `serve_until(~ignore_switch(~app(st)), …)` where `st` is a `+`
parameter is refused with "st is a variable here, not comptime: pass it at
run time". A server generic over an app-chosen state type is refused too
("only leading binders take ~", and a type binder cannot precede the
template). So the state must be **one concrete framework type, carried at
run time**, the way the stop switch already is.

Decision: **the store rides on the request.** `Request` gains a last field,
`store: Maybe<&2, Chan(Shelf)>`, where `Shelf` is `Map<&2, Map<&2, String>>`:
namespaces of string maps. The server puts the store there before calling the
app, so no entry point changes shape, `use` and `Route.wrap` are untouched,
and a middleware or handler reaches it through `Request.store(req)`. The
parser seeds `None`; only a request built by the server carries a store.
A `Chan` is `Data`, so `Maybe<&2, Chan(..)>` is allowed (the affine-pair
restriction is for `String & String`, not for channels).

Why strings in string maps: every consumer here wants strings (counts and
timestamps render and parse in one call; session fields are strings like
params and locals; plan 010's index deferred typed locals to "a session
store (Tier 5)", and this is the answer). Namespaces let a session be dropped
in one `Map.del`. A one-slot channel is the lock: `Chan.recv` takes the
shelf, `Chan.send` puts it back, exactly `Drain.Gate`'s pattern. The
function applied between the two must be pure, or every other request waits
on it.

Verified at planning time: a generic one-slot cell `Cell(A) = Chan(A)` with
`swap(-A: Data, f: A -> A, +cell, d)` checks and runs (`-A: Data`, not
`Type`: the value is rebound with `+`). The store here is concrete, so no
generic is needed, but the shape is proven.

Rate limiting, over the store:

- **Fixed window** per key: a namespace `rate` holds `_epoch` (the window
  number, `now_ms / window_ms`, fits `U32` until year 2106 for windows of a
  second or more) and one count per key. When the epoch changes, the whole
  namespace is replaced: memory is bounded by the distinct keys in one
  window, no sweep. Simpler than a sliding window or token bucket, and the
  headers are the same.
- **Key**: a function `Request -> String` the app supplies. `Rate.by_ip(trust)`
  uses `Request.client_ip` and falls back to `""` (one global bucket) when
  there is no trusted proxy, since `TCP.accept` gives no peer address
  (documented in `Request.client_ip`). `Rate.by_header(name)` keys on a
  header, for API keys. An app writes its own for anything else.
- **Answer**: over the limit, `Response.fail(TooMany{"rate limit: k of n per w ms"})`
  with `retry-after` (seconds to the next window, at least 1); every
  response carries `x-ratelimit-limit`, `x-ratelimit-remaining`,
  `x-ratelimit-reset` (seconds). The 429 is a failed body, so `on_error`
  renders it in the app's style and, after plan 013, keeps the headers.

## Current state

- `air/http.bend:102-112` — `Request` with nine fields; ~20 `case Request{...}` patterns;
  `parse` at `:657` builds one; `with_params`/`with_body`/`with_local` rebuild it.
- `air/server.bend:108-135` — `Ctx` and its five accessors; `conn` at `:791`
  builds it; `run` at `:633-637` calls the app.
- `air/server.bend:870-896` — `serve_until`, `serve_with`, `serve`; `serve_with`
  wraps `~app` as `~(sw => app)`.
- `air/drain.bend:88-125` — `Gate`: the one-slot channel as a lock, `swap`.
- `air/http.bend:1050-1060` — `Response.fail`, `TooMany{detail}` at `Error`.
- `air/text.bend:179` — `digits(s) -> Maybe<U32>`; Base `U32.from_nat`,
  `Nat.div`, `U32.show`.
- `README.md:63` — "handlers that share state" under "Not yet".
- `LAWS.bend:116` — a `Http.Request{...}` literal with nine fields; gains a tenth.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Check and prove | `bend PROOF.bend` | `All terms check.` |
| Run the example | `bend examples/hello/main.bend` | listens on 8080 |
| Under the limit | `curl -si localhost:8080/` | 200 with `x-ratelimit-remaining` |
| Over the limit | `for i in $(seq 1 6); do curl -s -o /dev/null -w '%{http_code}\n' localhost:8080/limited; done` | five `200` then `429` |
| Retry-After survives | `curl -si localhost:8080/limited` after that | `429`, `retry-after: N`, body from `on_error` |
| Counter | `curl -s localhost:8080/visits` twice | `1` then `2` |
| Bench | `bench/run.sh` | GET path unchanged (the bench route is not limited) |

## Implementation rules relevant to this plan

- **`Store`** in a new `air/store.bend` (alias `Store`), importing `Base`,
  `./text.bend`, `./http.bend`:
  - `def Shelf() -> Data: Map<&2, Map<&2, String>>` and `def Store() -> Data: Chan(Shelf())`.
    (`Shelf` and `Store` do not collide with Base names; check `bend base Store`.)
  - `new() -> IO(Store())`: `Chan.new(Shelf(), 1)` then send an empty map, as `Drain.Gate.new`.
  - `swap(f: Shelf() -> Shelf(), +store: Store()) -> IO(Shelf())`: recv, send
    `f(v)`, answer the **new** shelf (rebind with `+`); a closed channel
    answers the empty map. Same shape as `Drain.swap`.
  - `update(+store, +ns: String, f: Map<&2, String> -> Map<&2, String>) -> IO(Map<&2, String>)`:
    `swap` with a function that gets the namespace (empty map default via
    `Map.get`), applies `f`, sets it back; answers the new namespace map.
  - `read(+store, +ns) -> IO(Map<&2, String>)`, `get(+store, +ns, +key) -> IO(String)`
    (`""` default, `Text.map_get`), `set(+store, +ns, +key, +value) -> IO(Unit)`,
    `drop(+store, +ns) -> IO(Unit)` (`Map.del`), `namespaces(+store) -> IO(List<&2, String>)` (`Map.keys`).
  - Request-level versions taking `req: Http.Request` and branching on
    `Request.store(req)`: `None` answers the defaults (`""`, empty map, unit).
    Name them `Store.get_in(req, ns, key)` etc. or make these the facade's
    `Air.Store.get(req, ns, key)`; the facade takes the request, so that
    handlers never see the channel.
- **`Request`**: append `store: Maybe<&2, Chan(Map<&2, Map<&2, String>>)>`;
  `parse` seeds `None{}`; `Request.store(r)`, `Request.with_store(r, s)`.
  Because `Chan(..)` is not `+`-able in a pattern? It is Data, so it is; but
  keep every accessor's pattern shape as today, appending one name.
- **Server**: `Ctx` gains `store: Chan(Shelf)` (import `./store.bend`);
  `run` calls `app(Ctx.switch(ctx), Http.Request.with_store(Http.Request.with_body(req, body), Some{Ctx.store(ctx)}))`.
  `serve_until` creates the store with `Store.new()` next to the gate and
  passes it through `serve_until.go` → `loop` → `conn` like `gate`. Add
  `serve_shared(~app, +limits, +timeouts, +store, +switch, +port)` that takes
  the store instead of creating it, and make `serve_until` call it; this is
  for an app that also wants the store from a background task.
- **Rate** in a new `air/rate.bend` (alias `Rate`), importing `Base`,
  `./text.bend`, `./http.bend`, `./router.bend`, `./store.bend`:
  - `epoch(now: Nat, +window_ms: U32) -> U32`: `U32.from_nat(Nat.div(now, U32.to_nat(window_ms)))`.
  - `tick(+epoch: U32, +key: String, m: Map<&2, String>) -> Map<&2, String>`:
    when `m`'s `_epoch` differs from `epoch`, start from an empty map with
    `_epoch` set; then increment `key` (`Text.digits` with `0` default,
    `U32.show`). Pure; this is the `f` given to `Store.update`.
  - `count(+key, m) -> U32`, `reset_in(now: Nat, +window_ms) -> U32` (seconds
    to the next window, minimum 1).
  - `decorate(+limit, +used, +reset, r: Response) -> Response`: the three
    `x-ratelimit-*` headers (`remaining` saturating at 0).
  - `refuse(+limit, +window_ms, +used, +reset) -> Response`: `fail(TooMany{..})`
    with `retry-after`, decorated.
  - `limit(+n: U32, +window_ms: U32, key: Http.Request -> String, next: Router.Handler(), req: Http.Request) -> IO(Http.Response)`:
    `+req = req`; `k = key(req)`; `now <- IO.now()`; `m <- Store.update(req, "rate", tick(epoch(now, window_ms), k))`;
    branch on `U32.is_le(count(k, m), n)` through a helper: `next(req)` then
    `decorate`, or `refuse`. `key` is affine and used once; it is not `+`.
    A request with no store (`None`) is never limited.
  - `by_ip(+trust: Http.Trust, req: Http.Request) -> String` and
    `by_header(+name: String, req: Http.Request) -> String`.
- Facade: `Air.Store()`, `Air.Shelf()` (types), `Air.Store.new`,
  `Air.Store.get(req, ns, key)`, `set`, `read`, `update`, `drop`,
  `Air.Request.store`, `Air.serve_shared`, `Air.rate(n, window_ms, key)`,
  `Air.Rate.by_ip(trust)`, `Air.Rate.by_header(name)`. Reserve the namespace
  prefix `air:` for the framework's own use? No: use plain `rate` and,
  in 016, `session:<id>`; document that apps pick namespaces that do not
  start with `rate` or `session:`.

## Scope

**In scope**:
- `air/store.bend`, `air/rate.bend` (new); `air/http.bend` (`store` field);
  `air/server.bend` (`Ctx.store`, `run`, `serve_shared`); `air.bend`;
  `LAWS.bend` (literal fix, laws); `PROOF.bend`.
- `examples/hello/main.bend`: a `/visits` route that answers
  `Air.Store.update(req, "app", bump)` rendered as text; a `/limited` route
  under `Air.rate(5, 10000, Air.Rate.by_ip(Air.Trust.none()))` applied to
  that one route (`Air.rate(..)(handler)`); the bench route `/hello/:name`
  stays unlimited.
- `README.md`: "Not yet" loses "handlers that share state"; a "Shared state"
  paragraph (`Air.Store.*`, namespaces, the lock rule: keep `update`'s
  function pure) and a "Rate limiting" paragraph (fixed window, keys, the
  no-peer-address caveat).
- `roadmap.md`: tick "Rate limiting".
- `.factory/plans/README.md`: row 015; "Findings": the template/closed-argument
  limit that forces a request-carried store.

**Out of scope**: sliding windows, token buckets, per-route limits with
different keys sharing one namespace (use a different `ns` per limiter: add a
`+ns` parameter only if two limiters in one app are needed by 016 or an
example), distributed stores, persistence.

## Git workflow

- Current worktree branch. Do not commit or push unless asked. `bend PROOF.bend` first.

## Steps

### Step 1: `store` on `Request`, `air/store.bend`

Field, accessors, the `LAWS.bend` literal, the module. `bend PROOF.bend`
must pass before the server changes.

### Step 2: the server carries a store

`Ctx.store`, `run`, `serve_shared`, `serve_until`. Run the hello example and
confirm the existing routes behave as before.

### Step 3: `air/rate.bend`, facade, example

### Step 4: laws

```
store_ns_default_empty:  Store.ns_of(Map.new(&2, Map<&2, String>), "x") == Map.new(&2, String)
rate_epoch:              Rate.epoch(125000n, 60000) == 2
rate_tick_new_window:    Rate.count("k", Rate.tick(3, "k", Map.set(&2, String, Map.set(&2, String, Map.new(&2, String), "_epoch", "2"), "k", "9"))) == 1
rate_tick_same_window:   Rate.count("k", Rate.tick(2, "k", Map.set(&2, String, Map.set(&2, String, Map.new(&2, String), "_epoch", "2"), "k", "9"))) == 10
rate_reset_in_min_one:   Rate.reset_in(119999n, 60000) == 1
rate_refuse_status:      Http.Response.status(Rate.refuse(5, 60000, 6, 30)) == 429
rate_refuse_retry_after: Http.Response.header(Rate.refuse(5, 60000, 6, 30), "retry-after") == "30"
rate_remaining_floor:    Http.Response.header(Rate.decorate(5, 9, 1, Http.Response.text("")), "x-ratelimit-remaining") == "0"
request_store_seeded_none: Http.Request.store(request("GET / HTTP/1.1\r")) == None{}
```

(`Store.ns_of(shelf, ns)` is the pure namespace lookup `update` uses; expose
it so a law can pin the default.)

### Step 5: live checks

Record in the index:

1. `/visits` twice → `1`, `2`; from two parallel `curl`s → still distinct numbers (the lock works).
2. `/limited` six times within 10 s → five 200s with `x-ratelimit-remaining` 4..0, then 429.
3. The 429 has `retry-after`, `x-ratelimit-*` and the `on_error` plain body `Too Many Requests` (headers survived rendering, plan 013).
4. Wait for the window → 200 again.
5. `/hello/world` never carries `x-ratelimit-*` (per-route limiter).
6. `bench/run.sh`: `/hello/:name` within a few percent of 30.4k (one extra `Map.set` per request for the store field).

## Test plan

Nine laws; six live checks including the bench.

## Done criteria

- [ ] `bend PROOF.bend` prints `All terms check.` with the new laws.
- [ ] Live checks 1–6 pass and are noted in the index with the bench number.
- [ ] `Air.Store.*`, `Air.rate`, `Air.Rate.*`, `Air.serve_shared`, `Air.Request.store` exist with comments.
- [ ] README, roadmap, index updated.

## STOP conditions

- `Maybe<&2, Chan(..)>` is refused as a `Request` field: fall back to a
  sum type `type Slot is Data: NoStore{} Stored{store: Chan(..)}` in
  `air/store.bend` and import it from `air/http.bend` (check the import
  graph: `store.bend` must then not import `http.bend`; move the
  request-level helpers to `air/http.bend` or the facade).
- The bench drops by more than 5 %: report the number; do not remove the
  field, the owner decides.
- `Store.update` deadlocks when a handler calls it while another `update` is
  pending on the same connection (should be impossible since `f` is pure):
  report with the reproduction.

## Maintenance notes

- Plan 016 builds sessions on `Store` namespaces `session:<id>` and needs
  `swap` over the whole shelf for its sweep; keep `swap` public.
- `Drain.Gate` could be rewritten over the same cell shape; not worth the
  churn now.
