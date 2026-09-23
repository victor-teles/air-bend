# Plan 025: Prometheus metrics per route, method and status, with a latency histogram

> **Executor instructions**: Deliver the stated outcome within scope. Adapt routine
> implementation details to current code, preserve the listed contracts, and run
> the relevant acceptance checks. Fix task-caused failures and recheck affected
> behavior. Escalate only the material conditions below. Update the plan's status
> in `.factory/plans/README.md`.
>
> **Drift check**: `git diff --stat cea6656 -- air/lib/router.bend air/lib/http.bend air/lib/store.bend air/lib/log.bend air.bend`
> should be routine. 024 changes `Route` (fine). 019 adds `Response.refusal` (fine).

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED (a store lock per request, plus a router annotation on every hit, both on the hot path; must be benchmarked)
- **Depends on**: 024 (do it first, so the router is changed once at a time), 019 (tests), 020 (bench gate) recommended
- **Category**: ops (roadmap Tier 6: "Metrics + OpenTelemetry tracing hooks": metrics half; tracing is 026)
- **Planned at**: commit `cea6656`, 2026-09-22, clean tree

## Why this matters

An operator's first questions are how many requests per route, how many
failed, and how slow. Air answers today only through one JSON log line
per request (`Air.log`), which needs a log pipeline to aggregate. This
plan adds the standard answer: `Air.metrics`, a middleware that counts
requests by method, route pattern and status and records a latency
histogram, and a `/metrics` handler in the Prometheus text format that
every metrics system scrapes. Route *patterns* (`/users/:id`), not raw
paths, keep the series bounded.

## Decisions

- **How the route label reaches a global middleware.** `Air.metrics`
  sits in `Air.use([...], base)`, outside dispatch, so it only sees the
  response. The router therefore **annotates the response**: on a hit or
  GET fallback, `run` adds the internal header `air-route` with the
  matched pattern rendered with names (`/api/tasks/:id`, including any
  mount prefix). `Http.Response.settle`, which both the server
  (`respond`) and `Air.Test.inject` (019) call before writing, **removes
  `air-route`**, so it never reaches the wire. That is one `Map.set` and
  one `Map.del` per request. A miss (404/405/OPTIONS) has no annotation
  and is labelled `route=""`. Rejected alternatives: a router local
  (invisible outside dispatch); running the metrics middleware inside
  `Route.wrap` (misses 404s, one copy per route); a second routing walk
  (doubles the router's cost). `Air.Response.route(res)` exposes the
  annotation for other middleware (`Air.log` may add it to its line
  later; not in this plan).
- **Metric names and units (Prometheus conventions)**:
  ```
  # HELP air_http_requests_total Requests answered, by method, route and status.
  # TYPE air_http_requests_total counter
  air_http_requests_total{method="GET",route="/hello/:name",status="200"} 12
  # HELP air_http_request_duration_seconds Time in the app, from the middleware's view.
  # TYPE air_http_request_duration_seconds histogram
  air_http_request_duration_seconds_bucket{route="/hello/:name",le="0.005"} 10
  … le="0.01","0.025","0.05","0.1","0.25","0.5","1","2.5","5","10","+Inf"
  air_http_request_duration_seconds_sum{route="/hello/:name"} 0.042
  air_http_request_duration_seconds_count{route="/hello/:name"} 12
  ```
  Durations come from `IO.now()` (ms) and render as seconds with three
  decimals. Methods outside the seven known ones are labelled `OTHER`,
  since a client controls the method and it must not add series. Label
  values are escaped (`\` → `\\`, `"` → `\"`, newline → `\n`). Series are
  sorted by key, which is deterministic and enough for Prometheus.
- **Storage**: the store namespace `metrics`, one `Store.update` per
  request (one lock). Inside the pure update, set four keys: the counter
  `c␟GET␟/route␟200`, the bucket the observation falls in (**not**
  cumulative; cumulate at render time), the sum in ms, and the count. Use
  a separator that cannot appear in a route or a method (`\u001f` or
  `\t`) and write it in one def.
- **Exposition**: `Air.Metrics.expose` is a handler (`GET` it anywhere;
  `text/plain; version=0.0.4; charset=utf-8`). It reads the namespace
  once and renders. The guide recommends mounting it on an internal path
  or behind an auth middleware, since it reveals route names.
- **App counters**: `Air.Metrics.count(req, name)` increments
  `app_<name>_total` (name restricted to `[a-z0-9_]`, otherwise ignored).
  No labels in this cut.
- **In-flight gauge rejected** for now: the drain tally lives in the
  server's context, not on the request. Revisit if 023's store-based
  server state grows.

## Current state

- Router hit path (`air/lib/router.bend`, `run`):

  ```
  def run(pick: Pick, +req: Http.Request) -> IO(Http.Response):
    match pick:
      case Hit{handler, params}:
        handler(Http.Request.with_params(req, params))
      case Fallback{handler, params, allowed}:
        handler(Http.Request.with_params(req, params))
  ```

  `Pick`'s `Hit`/`Fallback` do not carry the pattern today. Add it (a
  `String` rendered once in `consider.fin` when a route becomes the hit,
  or the `List<&2, Seg>` rendered at `run`). Render with names: a new
  `render_pattern(pat)` (the existing `shape` anonymizes params, so it is
  not the one). After 024, `openapi.template` renders `{id}`, which is
  also not the one: metrics use `:id`, as the route was written.
- `air/lib/http.bend:1517-1530`: `Response.settle.go` / `settle` rebuild
  the response per body kind. Strip `air-route` from `h` in all three
  arms. `Response.with_header(r, name, value)` exists.
  `Map.del(&2, String, m, key)` is Base.
- `air/lib/log.bend:62-78`: the `IO.now()` before/after pattern and
  `Nat.sub(after, before)`.
- `air/lib/store.bend`: `update_in(+req, +ns, f) -> IO(Map<&2, String>)`
  (a pure `f`, applied under the lock); `read_in(+req, +ns)`.
  `Text.digits_or` parses counters (`incr.step` is the model).
- Bench history (`bench/README.md`): 16-17k GET req/s with the hello
  middleware stack; the rate-limited route serves 13.5k/s through the
  store lock.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Proof | `bend PROOF.bend` | `All terms check.` |
| Tests (019) | `bend tests/hello.bend` | exit 0 |
| Live | `bend examples/hello/main.bend`, a few `curl`s, then `curl -s localhost:8080/metrics` | the series above with real counts |
| Prometheus format check | `curl -s localhost:8080/metrics \| promtool check metrics` if `promtool` is installed; otherwise compare against the format spec by eye and say so | no errors |
| Bench | `bench/run.sh 32 5`, or 020's `ab.sh` against the pre-plan binary | record both numbers |
| Native | `bend examples/hello/main.bend -o /tmp/h && bend examples/dashboard/main.bend -o /tmp/d` | exit 0 |

## Implementation rules relevant to this plan

- Bend: declare before use; no `if`; match only on parameters; the first
  changed argument of a self-call shrinks; `+x = x` to reuse a value; big
  string building with `Text.append` (the exposition can be long).
  `String.append` recurses on its left operand. See `AGENTS.md`.
- New module `air/lib/metrics.bend` (`Base`, `./text.bend`, `./http.bend`,
  `./router.bend`, `./store.bend`). Pure core: `observe(method, route, status, ms, m) -> Map`
  and `expose_text(m) -> String`. Both get laws. The middleware and
  handler are thin IO wrappers.
- Facade: `Air.metrics`, `Air.Metrics.expose`, `Air.Metrics.count`,
  `Air.Response.route`. Native-build both examples.

## Scope

**In scope**: `air/lib/router.bend` (pattern on the pick, the annotation
in `run`, `render_pattern`), `air/lib/http.bend` (strip in `settle`,
`Response.route`), `air/lib/metrics.bend` (new), `air.bend`, `LAWS.bend`,
`PROOF.bend`, hello (metrics in `use`, `/metrics` under the `admin`
group so it sits behind `auth`), `tests/hello.bend` (if 019),
`docs/content/docs/guides/metrics.mdx` + `meta.json`, `bench/README.md`
(a dated entry with the cost), roadmap: mark the line half done
("metrics: 025; tracing: 026"), index row.

**Out of scope**: OpenTelemetry metrics export (OTLP), push gateways,
per-label custom metrics, summaries/quantiles, an in-flight gauge,
process metrics (no `/proc` or rusage effect in Bend).

## Steps

### Step 1: router annotation and settle strip, measured alone

Laws: a hit's response carries `air-route` = `/users/:id` for a
`/users/:id` route matched by `/users/7`; a mounted route carries the
prefix; a 404 carries none; `settle` removes it. Existing router laws must
pass unchanged. Bench this step alone and record GET req/s before and
after.

### Step 2: `observe`, `expose_text`, laws

```
m_counter:   expose_text(observe("GET", "/a", 200, 3, {})) contains "air_http_requests_total{method=\"GET\",route=\"/a\",status=\"200\"} 1"
m_bucket:    an observation of 30 ms counts in le="0.05" and above, not in le="0.025"
m_sum:       sum after 3 ms and 1500 ms renders "1.503"
m_other:     method "BREW" is labelled "OTHER"
m_escape:    route "/a\"b" renders as route="/a\\\"b"
m_unmatched: route "" renders route=""
```

### Step 3: middleware, handler, example, docs, bench

## Test plan

Laws above, plus, with 019, a test that injects three requests into a
shared store and reads `/admin/metrics` (with the token): counts 3 for the
route, and `_count` equals the counter sum. Bench: record the full
middleware stack with and without `Air.metrics`.

## Done criteria

- [ ] `bend PROOF.bend` passes (≥ 10 new laws across router and metrics).
- [ ] `air-route` never appears on the wire (`curl -si` any route).
- [ ] `/admin/metrics` output parses (promtool, or a stated manual check).
- [ ] Bench entry in `bench/README.md` with the router-annotation cost and the metrics-middleware cost, measured separately.
- [ ] Guide, roadmap (partial), index updated. Both examples native-build.

## STOP conditions

- The router annotation alone costs more than 3% of GET throughput.
  Report the numbers before continuing. The fallback is route labels
  only via `Route.wrap`, which changes the public design.
- `Air.metrics` costs more than 20% on the hello bench (the store lock).
  Report it. A per-connection batch would need server changes, a separate
  decision.

## Maintenance notes

- Plan 026 (tracing) reads `Air.Response.route` for its span name.
- If an app mounts thousands of routes, the series count grows with
  them. That is inherent and documented.
