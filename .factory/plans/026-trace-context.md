# Plan 026: W3C trace context, a span per request through an exporter hook, and a wall clock

> **Executor instructions**: Deliver the stated outcome within scope. Adapt routine
> implementation details to current code, preserve the listed contracts, and run
> the relevant acceptance checks. Fix task-caused failures and recheck affected
> behavior. Escalate only the material conditions below. Update the plan's status
> in `.factory/plans/README.md`.
>
> **Drift check**: `git diff --stat cea6656 -- air/lib/log.bend air/lib/random.bend air/lib/http.bend air.bend`
> should be routine (025 adds `Response.route`; this plan reads it).

## Status

- **Priority**: P3
- **Effort**: M
- **Risk**: MED (first custom effect in the repo, a C and a JS file; random draws cost throughput)
- **Depends on**: 025 (span names use `Air.Response.route`). 019 recommended.
- **Category**: ops (roadmap Tier 6: "Metrics + OpenTelemetry tracing hooks": tracing half)
- **Planned at**: commit `cea6656`, 2026-09-22, clean tree

## Why this matters

In a system of several services, a request's path is followed by the
W3C `traceparent` header: each service keeps the trace id, makes its own
span id, and reports a span. Air ignores the header today, so an Air
service breaks every trace that passes through it, and its log lines
cannot be joined with its neighbours'. This plan makes Air a
well-behaved hop. It continues or starts a trace, exposes the ids to
handlers (for outgoing calls and logs), and emits one span per request
through an exporter function the app picks. A JSON-line exporter ships.
Spans need real timestamps, and Bend's `IO.now` is uptime
(`effs/now.c`), so this plan adds Air's first custom effect: a wall
clock.

## Decisions

- **Parsing** (`traceparent: 00-<32 hex>-<16 hex>-<2 hex>`): lowercase hex
  only, trace id and parent id not all zeros, version `ff` invalid. A
  higher version is parsed by its first four fields, per the spec. An
  invalid or absent header starts a new trace. `tracestate` is passed
  through untouched as a local and is not interpreted.
- **Ids**: a new trace id is `Random.token()` (four draws, 32 hex). A span
  id is 16 hex from **two** draws (a new `Random.span_id()`: request ids
  mix in the clock, but span ids should be random). Cost note from plan
  014: each draw is a worker-pool trip, about 5% of throughput per draw on
  the hello bench. Continuing a trace costs 2 draws, starting one costs
  6. Measure and record.
- **What handlers see** (locals): `trace_id`, `span_id`, `parent_id`
  (`""` for a root), `trace_flags` and `traceparent`, the value to send
  downstream (`00-<trace_id>-<span_id>-<flags>`). `Air.log` adds
  `"trace_id"` to its line when the local is present (additive field).
- **Span record** (a `Data` type in `air/lib/trace.bend`):
  `Span{trace_id, span_id, parent_id, name, start_ms: String, duration_ms: U32, status: U32, method, route, path}`.
  `name` is `"GET /users/:id"` from `Air.Response.route` (025), or just
  the method for a miss. `start_ms` is Unix epoch milliseconds as decimal
  text: it does not fit `U32`, and `Nat` arithmetic on it is not needed.
- **Exporter hook**: `Air.trace(export: Span -> IO(Unit))` is middleware.
  Put it in `use` inside `request_id` and outside `log`. Shipped exporters:
  `Air.Trace.print` prints one JSON line per span with OpenTelemetry
  semantic-convention attribute names (`http.request.method`,
  `http.route`, `url.path`, `http.response.status_code`) plus
  `trace_id`/`span_id`/`parent_span_id`/`start_time_unix_ms`/`duration_ms`.
  `Air.Trace.drop` does nothing and propagates ids only. **OTLP export
  over the network is out of scope**: it needs an HTTP client over
  `TCP.connect`, batching and retries. A collector can tail the JSON
  lines (for example the filelog receiver). Record this in the index.
- **Sampling**: honor the incoming sampled flag (`01`) in `trace_flags`.
  Export only sampled spans. A new root is sampled unless the setting
  says otherwise: `Air.trace_sampled(every: U32, export)` keeps 1 in
  `every` roots, decided from the trace id's last hex digits so the
  decision is stable per trace.
- **Wall clock**: `air/lib/effs/wall_ms.c` and `.js`, the def
  `Clock.wall_ms() -> IO(String)` (decimal epoch ms). C:
  `clock_gettime(CLOCK_REALTIME)` into `io_str`. JS: `String(Date.now())`.
  Follow `~/.bend/bend2/effs/now.c` / `now.js` and the effect guide
  (`~/.bend/guide/EFFECTS.md`, "An effect def": the def body is two
  imports; the C function is `<lowercased def path>_run`, registered in a
  constructor with `io_eff(CID_…, …, 0)`). Put the def in a new module
  `air/lib/clock.bend`. Because the C name comes from the def path,
  confirm the `CID_` name by reading the generated C (`-o out.c`) when
  the build complains.
- **`Air.log`'s `ts` becomes epoch ms** from the wall clock (it has been
  uptime, "until Bend gains a wall clock", per plan 014's note). This is a
  visible change to the log line, so note it in the guide and the index.

## Current state

- `air/lib/log.bend`: `request_id` (the local `request_id`,
  `Random.fresh_id`) and `log` (`line(ts, id, method, path, status, ms)`
  with `Json.render`; `ts` from `IO.now()`).
- `air/lib/random.bend`: `draw()`, `hex_id(a, b)`, `fresh_id()` (1 draw +
  clock), `token()` (4 draws), `safe_id`.
- `~/.bend/bend2/effs/now.c` and `now.js`: the reference effect for a clock.
  `EFFECTS.md` notes that a user **handle** type is WONTFIX. This effect
  returns a `String`, which is allowed.
- `Http.Request.header(req, "traceparent")`: headers are lowercased at
  parse.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Proof | `bend PROOF.bend` | `All terms check.` |
| Wall clock JS | a scratch `main` printing `Clock.wall_ms()` via `bend scratch.bend` (inside the repo, relative import) | a 13-digit number close to `date +%s000` |
| Wall clock C | the same scratch with `-o /tmp/w && /tmp/w` | the same |
| Continue a trace | `curl -si -H 'traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01' localhost:8080/hello/x` | printed span with that trace id and `parent_span_id` `00f067aa0ba902b7` |
| Start a trace | `curl -s localhost:8080/hello/x` | a span with a fresh 32-hex trace id and no parent |
| Bad header | `-H 'traceparent: 00-000…0-…-01'` (all-zero trace) | new trace, not the zero one |
| Bench | `bench/run.sh 32 5` or 020's `ab.sh` | record |
| Native | both examples `-o` | exit 0 |

## Implementation rules relevant to this plan

- Bend: declare before use; no `if`; match only on parameters; first
  changed argument of a self-call shrinks; `+x = x` for reuse; a def named
  after a JS reserved word breaks the JS backend (so no `export`: use
  `export_span` or pass the function). See `AGENTS.md`.
- Keep parsing pure (`parse_traceparent(s) -> Maybe<&2, Ctx>`) with laws.
  Parsing hex by hand per character is fine. Headers are short.
- New modules: `air/lib/clock.bend`, `air/lib/effs/wall_ms.{c,js}`,
  `air/lib/trace.bend`. Facade: `Air.trace`, `Air.trace_sampled`,
  `Air.Trace.print`, `Air.Trace.drop`, `Air.Span()` + accessors,
  `Air.Clock.wall_ms`. Native-build both examples.

## Scope

**In scope**: the three new modules and the effect files, `air/lib/random.bend`
(`span_id`), `air/lib/log.bend` (`trace_id` field, wall-clock `ts`),
`air.bend`, `LAWS.bend`, `PROOF.bend`, hello (`Air.trace(Air.Trace.print)`
in its `use`), `tests/hello.bend` (if 019: the three header cases, by
reading locals through a handler that echoes `traceparent`),
`docs/content/docs/guides/tracing.mdx` + `meta.json`, the logging guide
(`ts` now epoch), `docs/content/docs/project/not-yet.mdx` (OTLP export),
`bench/README.md` entry, roadmap tick (with 025: "Prometheus metrics;
W3C trace context with a span exporter hook; OTLP export deferred"),
index row.

**Out of scope**: OTLP/HTTP or gRPC export, baggage, `tracestate`
mutation, child spans inside handlers (an app can build `Span` values
itself and call its exporter), client-side propagation helpers beyond the
`traceparent` local.

## Steps

### Step 1: the wall clock effect, alone

Prove it on both backends with the scratch program before anything
depends on it. This is the risky step. See STOP.

### Step 2: parsing and ids, with laws

```
tp_valid:      parse("00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01") is Some with those fields, sampled
tp_zero_trace: parse("00-00000000000000000000000000000000-00f067aa0ba902b7-01") is None
tp_upper:      parse with uppercase hex is None
tp_ff:         version "ff" is None
tp_future:     parse("01-<valid>-<valid>-01-extra") is Some (first four fields)
tp_render:     render(trace, span, "01") == "00-<trace>-<span>-01"
span_json:     Trace.json(a fixed Span) == <exact line>
sample_stable: sampled(every=4, trace) is a pure function of the trace id's last hex digit
```

### Step 3: middleware, exporters, log changes, example, docs, bench

## Test plan

Laws above. Live checks from the commands table, recorded. With 019, the
three header cases as injected tests (ids asserted by shape and by the
continued trace id). Bench with and without `Air.trace` in the hello
stack.

## Done criteria

- [ ] `Clock.wall_ms` works under `bend file.bend` and in a native build.
- [ ] `bend PROOF.bend` passes with ≥ 8 new laws.
- [ ] Continued, new and invalid `traceparent` behave as specified (live or injected).
- [ ] `Air.log` lines carry `trace_id` when tracing is on, and `ts` is epoch ms.
- [ ] Bench entry with the cost of continuing vs starting a trace.
- [ ] Guides, not-yet page, roadmap, index updated. Both examples native-build.

## STOP conditions

- A custom effect cannot be declared outside Base, or works on one
  backend only. Then keep `start_ms` as uptime ms, name the field
  `start_uptime_ms`, leave `Air.log`'s `ts` unchanged, and report it. The
  rest of the plan still ships.
- Starting a trace (6 draws) costs more than 30% of GET throughput.
  Report it. A cheaper id (fewer draws mixed with the wall clock) weakens
  randomness, and the spec asks for random trace ids, so that is the
  operator's call.

## Maintenance notes

- An OTLP exporter can be written later as another `Span -> IO(Unit)`
  over `TCP.connect`. It must batch (a connection per span would be far
  too slow) and must never block the request, so run it in a spawned task
  fed by a channel.
- If Bend adds a wall clock to Base, replace `air/lib/clock.bend`'s
  effect with it and delete the `effs/` files.
