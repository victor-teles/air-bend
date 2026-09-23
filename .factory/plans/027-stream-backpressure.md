# Plan 027: Streaming backpressure proven under a slow client, with a configurable window

> **Executor instructions**: Deliver the stated outcome within scope. Adapt routine
> implementation details to current code, preserve the listed contracts, and run
> the relevant acceptance checks. Fix task-caused failures and recheck affected
> behavior. Escalate only the material conditions below. Update the plan's status
> in `.factory/plans/README.md`.
>
> **Drift check**: `git diff --stat cea6656 -- air/lib/server.bend air.bend examples/hello`
> should be routine (earlier Tier 6 plans touch these; the streaming section of `server.bend`, lines ~396-537 at planning time, should be unchanged).

## Status

- **Priority**: P3
- **Effort**: S
- **Risk**: LOW (mostly verification. Code change: one constructor and docs)
- **Depends on**: none
- **Category**: perf/ops (roadmap Tier 6: "Backpressure handling on streaming responses")
- **Planned at**: commit `cea6656`, 2026-09-22, clean tree

## Why this matters

A streaming producer that is faster than its client must slow down, or
the server buffers without bound and one slow reader can exhaust memory.
Planning found that **Air already has end-to-end backpressure**, by
construction, but nothing proves or documents it as a guarantee. The chain
(verified in the runtime sources during planning):

1. `Air.Stream.new()` is `Chan.new(String, 8)` (`air.bend:465-468`). A
   channel with room parks the sender when full: in
   `~/.bend/bend2/effs/chan_send.c`, `chan_send_run` stores into the
   ring while `size < room`, else `return chan_park(row, w, f[1]);`.
2. The server writes each piece with `TCP.send`. `effs/tcp_send.c` sends
   on a non-blocking socket and, on `EAGAIN`, parks until the socket is
   writable (`io_wait_on(w, fd, POLLOUT, …)`). So the server takes the
   next piece only after the previous one is in the kernel buffer.
3. When the client goes away or a piece's send timeout fires, the server
   closes the channel (`server.bend` `stream_sent`, `stream_got`). The
   runtime's `chan_shut` wakes every parked sender with `False`
   (`chan_bool(false)`, read from the `bend` binary's embedded runtime).
   So a producer parked on a full channel is released with the answer
   "stop".

This plan turns that into a tested claim with numbers, makes the window
configurable, and documents the one gap: the size of a single piece is
not bounded.

## Decisions

- **Prove it with a measurement, not a law** (IO cannot be law-checked):
  a hello route `/flood` streams 20,000 pieces of 16 KiB (about 320 MB
  total) as fast as it can. A client reads it at 1 MB/s
  (`curl --limit-rate 1M -s -o /dev/null localhost:8080/flood`). Sample
  the server's RSS every second (`ps -o rss= -p <pid>`) for 20 s. Pass:
  RSS stays within a small constant (record it; expect under 50 MB above
  idle) and does not grow with time. The producer prints its piece count
  every 1000 pieces. Its rate must track the client's (about 60 pieces/s),
  not run ahead.
- **Disconnect releases the producer**: kill the curl mid-stream. The
  producer's next (parked) `Chan.send` answers False within the send
  timeout, and the route prints `flood: client gone after N`. Also try a
  client that connects and never reads
  (`curl … | sleep 60`): the server's send timeout (30 s default) ends it,
  and the producer is released.
- **Configurable window**: add `Air.Stream.with_room(n: U32) -> IO(Chan(String))`
  (clamped to at least 1). `Stream.new()` stays room 8. The guide
  explains the trade-off: a bigger window absorbs bursts, costs up to
  `room × piece size` of memory per connection, and delays the producer
  learning that the client left.
- **Piece size is the app's responsibility**: document "split large
  payloads into pieces of at most ~64 KiB". No enforcement: the server
  cannot split a string cheaply, and a limit would reject valid SSE
  events.
- The `/flood` route is test-only. Put it in hello behind the `admin`
  auth group, or in a scratch program. Do not ship an unauthenticated
  300 MB endpoint in an example.

## Current state

- `air.bend:440-468`: the streaming comment block and `Stream.new()`.
- `examples/hello/main.bend:23-52`: `tick` / `ticks.start` / `ticks`. The
  producer pattern: `Chan.send` answers a `Bool`; on `False` stop; close
  the channel when done. `IO.spawn` runs the producer.
- `air/lib/server.bend:396-537`: stream loop. Every wait and write is
  under the send timeout, re-armed per piece (`stream_step`: `arm(ctx, Timeouts.send(…))`).
- `docs/content/docs/guides/`: no streaming guide exists yet. Check
  whether SSE is documented anywhere (`grep -ri sse docs/content`). If
  not, create `streaming.mdx` covering SSE and backpressure.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Native build (measure natively) | `bend examples/hello/main.bend -o /tmp/hello && /tmp/hello` | listens |
| Slow client | `curl -s --limit-rate 1M -H 'x-token: secret' -o /dev/null localhost:8080/admin/flood` | runs ~20 s+ |
| RSS sampling | `for i in $(seq 20); do ps -o rss= -p $(pgrep -f /tmp/hello); sleep 1; done` | flat |
| Disconnect | Ctrl-C the curl | `flood: client gone after N` promptly |
| Non-reading client | `curl -s -N -H 'x-token: secret' localhost:8080/admin/flood \| sleep 60` | producer released within ~30 s |
| Proof | `bend PROOF.bend` | `All terms check.` |

## Implementation rules relevant to this plan

- Bend: a producer loop recurses on a `Nat` fuel first (`tick(+n, …)` is
  the model). Build the 16 KiB piece once, as a def returning a constant
  string (`String.repeat` if Base has it, or a small doubling helper with
  `Text.append`), not per iteration.
- `with_room` is a one-line facade def. Keep it next to `Stream.new`.

## Scope

**In scope**: `air.bend` (`Stream.with_room`, comment updates),
`examples/hello/main.bend` (`/admin/flood`, clearly marked as a
backpressure demo), `docs/content/docs/guides/streaming.mdx` (new, or a
section in an existing page) + `meta.json`, `bench/README.md` (a dated
"backpressure" entry with the RSS series and producer rates), roadmap
tick, index row.

**Out of scope**: backpressure on request bodies (bodies are read whole
under `Limits.body`, a separate design), per-connection memory caps,
changing the server's stream loop (only if the measurement shows
unbounded growth; see STOP).

## Steps

### Step 1: measure before changing anything

Run the slow-client, disconnect and non-reading experiments on a native
build, and record the numbers.

### Step 2: `with_room`, docs, roadmap

Rerun the slow client with `with_room(64)` and compare the RSS ceilings.
Record both.

## Test plan

The experiments are the test. If plan 019 has landed, add an injected
test that `Air.Test.body` on a `with_room(1)` stream of 100 pieces
returns all 100 (the window does not lose data).

## Done criteria

- [ ] RSS series for room 8 and room 64 under a 1 MB/s client in `bench/README.md`, both flat.
- [ ] Disconnect and non-reading client both release the producer (times recorded).
- [ ] `Air.Stream.with_room` exported and documented. The streaming guide explains the window, piece size and disconnect handling.
- [ ] Roadmap line ticked: "bounded channel (room 8, `with_room`) + non-blocking send; measured".

## STOP conditions

- RSS grows with time under the slow client. Then there is a buffer the
  planning analysis missed (for example in the runtime's send path).
  Report the series and where the memory goes, and do not patch the
  server blindly.
- A producer parked on a full channel is **not** released when the
  client disconnects (it hangs past the send timeout). Report it. That
  contradicts the runtime reading above and would need a server change
  (for example closing the channel on every exit path that currently
  misses it).

## Maintenance notes

- If Bend gains a bytes-level send, re-measure. Piece framing and memory
  per piece will change.
