# Plan 023: Health and readiness endpoints that turn 503 while draining

> **Executor instructions**: Deliver the stated outcome within scope. Adapt routine
> implementation details to current code, preserve the listed contracts, and run
> the relevant acceptance checks. Fix task-caused failures and recheck affected
> behavior. Escalate only the material conditions below. Update the plan's status
> in `.factory/plans/README.md`.
>
> **Drift check**: `git diff --stat cea6656 -- air/lib/server.bend air/lib/store.bend air/lib/drain.bend air.bend`
> should be routine (019 and 021 touch `server.bend`/`air.bend`; fine).

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW (the stopper marks the store and optionally sleeps before closing the gate; delay 0 keeps today's shutdown)
- **Depends on**: none (022 for the plugin framing in docs; 019 for tests)
- **Category**: dx/ops (roadmap Tier 6: "Health/readiness endpoints")
- **Planned at**: commit `cea6656`, 2026-09-22, clean tree

## Why this matters

A load balancer or orchestrator needs two answers. Liveness asks whether
the process can serve at all. Readiness asks whether it should get
traffic now. Air has graceful shutdown (plan: Tier 1 drain) but nothing
tells a balancer that a server is draining. During the drain window,
keep-alive connections keep sending requests to a server that is going
away. An app warming a cache has no way to say "not yet" either. This
plan ships both endpoints as a route group, with readiness that
(a) turns 503 as soon as the stop switch is flipped and (b) turns 503
while any named check the app marked is down.

## Decisions

- **`Air.health()` is a `List<Route>`** (a plugin in plan 022's sense):
  `GET /healthz` → 200 `{"status":"ok"}`, and `GET /readyz` → 200
  `{"status":"ready"}` or 503 `{"status":"draining"}` /
  `{"status":"not ready","down":["cache","db"]}`. Both send
  `cache-control: no-store`. HEAD works through the router's GET
  fallback. Mount it anywhere: `Air.Route.all([Air.health(), routes()])`,
  or under a prefix with `mount`.
- **Draining comes from the server.** In `serve_shared.go` the stopper
  gets the store. After the switch fires and **before** `Drain.close`, it
  sets `air`/`draining` = `"1"`. `readyz` reads it. The stopper already
  runs once per server, so the cost is nothing per request.
- **A pre-stop delay makes the signal useful.** Once `Drain.close` runs,
  every new request, `/readyz` included, gets the server's own plain 503
  from `admitted` (`Drain.enter` answers False). Without a gap between
  the flag and the gate, no balancer would ever see `draining`. So the
  stopper sleeps `drain_delay` ms (`IO.sleep`) between setting the flag
  and closing the gate. It keeps serving normally meanwhile, which is the
  usual pre-stop pattern. The delay is read from the store (`air`/`drain_delay`,
  digits, default `0`, which keeps today's behavior exactly), not from
  `Timeouts`: adding a seventh `Timeouts` field would break
  `Air.Timeouts.new`'s six-argument signature. Set it with
  `Air.Ready.delay(store, ms)` before serving. If plan 021 has landed,
  `serve_env` also reads `AIR_DRAIN_DELAY`.
- **App checks are store flags**, namespace `ready`: `Air.Ready.down(store, name)`
  and `Air.Ready.up(store, name)` for use from `main` or a background task
  with the store it made (`serve_shared`), plus `Air.Ready.down_in(req, name)`
  / `up_in(req, name)` from a handler. A name set to `"0"` makes
  `readyz` 503 and appear in `down`, sorted (`Map.keys` order). An app
  that never calls these is ready when not draining.
- **No per-request checks** (such as pinging a database inside `readyz`):
  a readiness probe that does I/O under load is the classic cascading
  failure. A background task updates the flag instead. Document the
  pattern with an `IO.sleep` loop.

## Current state

- `air/lib/server.bend:801-807`, the stopper:

  ```
  def stopper(switch: Chan(Unit), +gate: Chan(Drain.Tally), +port: U32) -> IO(Unit):
    do IO<Unit>:
      Drain.Switch.wait(switch)
      IO.print("air: stopping")
      Drain.close(gate)
      knock(port)
  ```

  spawned from `serve_shared.go` (`:818-825`), which has `+store` in scope:
  `IO.spawn(Unit, stopper(switch, g, port))`.
- `air/lib/store.bend`: `set(+store, +ns, +key, +value) -> IO(Unit)`,
  `read_in(+req, +ns) -> IO(Map<&2, String>)`, `get_in`, `set_in`.
  `Store()` = `Chan(Map<&2, Map<&2, String>>)`.
- `air/lib/drain.bend`: `Switch.flip`. `examples/hello` serves with
  `Air.serve` and has no switch. `examples/dashboard/main.bend:131-181`
  already has one: a `shutdown(switch, req)` route that calls
  `Air.Switch.flip(switch)`, and `Air.serve_until(~app, …, switch, 8080)`.
  So mount `Air.health()` in **both** examples, and do the draining check
  on the dashboard.
- Response helpers: `Http.Response.of_json`, `with_status`,
  `with_header`; `Json.obj/field/of_str/arr`.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Proof | `bend PROOF.bend` | `All terms check.` |
| Live | `bend examples/hello/main.bend` then `curl -si localhost:8080/healthz` and `/readyz` | 200 / 200 |
| Draining | dashboard with a 3000 ms delay set in its `main`; hit its shutdown route (find the path in `api(switch)`), then at once `curl -si localhost:8080/readyz` | 503 `{"status":"draining"}`; after 3 s new connections are refused and the process exits after in-flight requests |
| No delay | the same with delay 0 (default) | shutdown behaves exactly as before this plan |
| Check down | a hello route that marks `cache` down, then `/readyz` | 503 with `"down":["cache"]` |
| Native | `bend examples/hello/main.bend -o /tmp/h` | exit 0 |

With 019, also test it in-process: inject `/readyz` with a store whose
`air`/`draining` is `"1"`.

## Implementation rules relevant to this plan

- New module `air/lib/health.bend` (`Base`, `./json.bend`, `./http.bend`,
  `./router.bend`, `./store.bend`). The pure core,
  `readiness(draining: String, ready: Map<&2, String>) -> Http.Response`,
  holds all the logic and gets the laws. Handlers only read the store and
  call it.
- Server change: add `+store` to `stopper`. After the switch fires, it
  sets the flag with `Store.set`, reads `air`/`drain_delay` with
  `Store.get` + `Text.digits_or(…, 0)`, calls `IO.sleep(ms)` when it is
  nonzero (a helper def matching on `U32.is_zero`), then closes the gate
  and knocks as today. `server.bend` already imports `./store.bend`. No
  other server change.
- Facade: `Air.health()`, `Air.Ready.up/down/up_in/down_in/delay`.
  Native-build after.

## Scope

**In scope**: `air/lib/health.bend` (new), `air/lib/server.bend`
(stopper), `air.bend`, `LAWS.bend`, `PROOF.bend`, both examples (mount
`Air.health()`; hello gets a route that toggles a `demo` check),
`tests/hello.bend` (if 019), `docs/content/docs/guides/health.mdx` +
`meta.json`, roadmap tick, index row.

**Out of scope**: excluding probes from logs/metrics (an app mounts
`health()` outside its logging `use` if it wants, and the guide shows
how), gRPC health, startup probes as a third endpoint (readiness with a
`warmup` flag covers it).

## Steps

### Step 1: `readiness` and its laws

```
ready_ok:        status(readiness("", {}))                       == 200
ready_draining:  body(readiness("1", {}))                        == "{\"status\":\"draining\"}"
ready_down:      body(readiness("", {cache:"0", db:"1"}))        == "{\"status\":\"not ready\",\"down\":[\"cache\"]}"
ready_down_503:  status(readiness("", {cache:"0"}))              == 503
ready_no_store:  cache-control header of readiness("", {})       == "no-store"
```

### Step 2: stopper marks draining; routes; facade

### Step 3: example, tests, guide

The guide has the probe config for a typical orchestrator (liveness
`/healthz`, readiness `/readyz`), the background-check pattern, the drain
sequence (switch → `readyz` 503 → gate closes → in-flight requests
finish), and a note that the drain delay must exceed the balancer's
probe interval times its failure threshold for the 503 to be seen.

## Test plan

Five laws. With 019: inject `/healthz`, `/readyz` with a fresh store
(200), with `air/draining`=`1` (503), and with `ready/demo`=`0` (503,
`down` lists it). Live: the delayed draining check, recorded in the
index.

## Done criteria

- [ ] `bend PROOF.bend` passes with five new laws.
- [ ] With a drain delay, `/readyz` answers 503 `draining` after the switch is flipped and before the gate closes (recorded). With delay 0, shutdown is unchanged.
- [ ] A down check shows in `down` and clears when marked up.
- [ ] Guide, roadmap and index updated. Hello native-builds.

## STOP conditions

- Setting the store in the stopper deadlocks with a request holding the
  store lock during shutdown. It should not: `swap` is short and pure.
  If it happens, report it with the sequence. Do not move the flag
  elsewhere without saying so.

## Maintenance notes

- If Bend gains signals, the signal handler flips the same switch, and
  readiness follows for free.
