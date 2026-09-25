# Benchmarks

`bench/bench.mjs` is a dependency-free Node load generator. `bench/reference.mjs`
is a Node server with the same routes as `examples/hello/main.bend`, so the two can
be measured under the same load. `bench/run.sh [conns] [seconds]` builds the
example natively, runs both servers, and benchmarks each; `SKIP_BUILD=1` reuses
the last build.

```
node bench/bench.mjs --url http://localhost:8080/hello/world --conns 32 --seconds 10
node bench/bench.mjs --url http://localhost:8080/echo --method POST --body hello
```

`ECONNREFUSED` errors under load mean the listen backlog overflowed between
accepts, not that a request failed once accepted.
Bend's runtime listens with a backlog of 16 (`effs/tcp_listen.c`), which is
what caps Air at high connection counts.

## CI: head against base

`.github/workflows/ci.yml` benchmarks every pull request against its base
branch on the same runner. A stored baseline would flake: shared runners
differ by more than the regressions worth catching.

```
bench/build.sh <repo-dir> <out-binary> [port]   # hello, natively, on a free port
bench/ab.sh <base-bin> <head-bin>               # alternate them, write bench/out/ab.jsonl
node bench/compare.mjs [bench/out/ab.jsonl]     # median head/base per route; exit 1 under 0.85
```

`build.sh` swaps hello's port 8080 (default 18080; `BENCH_PORT` in
`ab.sh` must match) in a copy of `main.bend` next to the original, so it
works on any checkout, `main` included. `ab.sh` runs base, then head, for
each of `ROUNDS` (5) rounds of `SECS` (5) seconds at `CONNS` (32) on
`GET /hello/world` and a 1 KB `POST /echo`, one server at a time.
`compare.mjs` takes the median of each side, prints a Markdown table
with the spread of each side, and appends it to `$GITHUB_STEP_SUMMARY`
in CI. `THRESHOLD` overrides 0.85. With `BENCH_ACCEPTED=true` (the
`bench-accepted` label on the pull request) it reports without failing:
for a change whose cost is the point, like the shield's headers.

Noise, measured 2026-09-23 on a busy Apple Silicon laptop (load
average 4-5), the same binary on both sides:

| rounds | GET head/base | POST head/base |
| -----: | ------------: | -------------: |
| 3      | 1.009, 1.132, 1.015 | 1.021, 1.030, 0.947 |
| 5      | 0.986, 1.003  | 1.019, 0.996   |

Three rounds strayed by 13% once, too close to a 15% gate, so the
default is five. A hello that adds a 4 KB header to every response
measured 0.141 (GET) and 0.345 (POST) and failed the gate, as it
should. This branch against `main` measured 0.921 and 1.093 at three
rounds, within the noise. The runner's own noise has not been measured
yet; if a same-binary run there strays past 15%, raise `ROUNDS` before
the threshold.

## 2026-09-24 (plan 027, stream backpressure), Apple Silicon, native hello

`/admin/flood` streams 20,000 pieces of 16 KiB (about 320 MB). Each
piece is new text, because one shared string would hide what the
window holds. The pieces go to `curl --limit-rate 1M`. RSS was sampled
every second for 20 s (kB). Idle RSS was about 3.2 MB.

| window | RSS series (kB) | pieces sent in 20 s |
| ------ | --------------- | ------------------: |
| 8 (`Stream.new`) | 7952 7952 7952 7760 7696 7680 7680 7680 7680 7680 7264 7264 7264 7264 7264 7264 7264 7264 7264 7264 | 1414 |
| 64 (`with_room(64)`) | 29456 29456 29456 29456 28784 28784 28784 28784 28784 28784 28784 28784 28784 28784 28784 28784 28784 28688 28720 28720 | 1477 |

Both series are flat. The producer sent about 70 pieces/s, the
client's 64/s plus what the socket buffers took, instead of all 20,000.
The 56 extra pieces of window cost about 21.5 MB, about 390 KB per
16 KiB piece, because a Bend string is a list of characters. With one
string shared by every piece, both windows sat at about 3 MB.

Releasing the producer:

- The client killed mid-stream: `flood: client gone after 1414` 0.03 s
  later (1477 with room 64).
- A client that connects and never reads (`curl -N … | sleep 90`): the
  buffers took 58 pieces, then the send timeout (30 s) fired
  (`air: timeout: stream`), and `flood: client gone after 58` came
  36.5 s after the request. RSS fell over that time, from 7.9 MB to
  1-2.5 MB.

## 2026-09-24 (plan 026, tracing), Apple Silicon, 32 connections, 5s, `ab.sh` with 7 rounds

This compares hello's full stack, with `Air.log`'s wall-clock `ts`,
before and after adding `Air.trace` inside `request_id`. The machine was
noisy that day: the spreads were 20-70%, and some rounds dropped by
half on both sides. The medians below are from the steady rounds (2-7
for start and continue, 1-4 for drop). The full JSONL is in
`bench/out/ab-026-*.jsonl`.

| case                                        | draws | GET no trace | GET trace | ratio      |
| ------------------------------------------- | ----: | -----------: | --------: | ---------: |
| start a trace, `Trace.print`                | 6     | ~12.4k       | ~8.2k     | ~0.66      |
| start a trace, `Trace.drop`                 | 6     | ~12.6k       | ~8.6k     | ~0.70      |
| continue a `traceparent`, `Trace.print`     | 2     | ~10.5k       | ~9.0k     | ~0.85      |

Almost all of the cost is the random draws. Each draw is a trip
through the runtime's worker pool, so four more draws for a new trace
id cost about 15-20% more than continuing a trace. Printing the span
line costs a few percent. Starting a trace crosses plan 026's 30% STOP
line. Cheaper trace ids would mean fewer draws mixed with the clock,
which weakens the randomness the spec asks for, so that choice is left
to the operator. The CI gate (0.85) fails on hello with tracing on.
POST ratios were 0.75 for start and 0.83 for continue, with a few
connection errors on both sides.

## 2026-09-24 (plan 025, metrics), Apple Silicon, 32 connections, 5s, `ab.sh` with 7 rounds

Two A/Bs of native hello builds, each measured with nothing else running.
The first compares the tree before 025 with the router's `air-route`
annotation and the `settle` strip added, with no metrics middleware.
The second compares that build with `Air.metrics` added outermost in
hello's `use` list: one store lock and five map writes per request.
Medians:

| change                          | target            | before | after | after/before | spreads     |
| ------------------------------- | ----------------- | -----: | ----: | -----------: | ----------- |
| router annotation + strip       | GET /hello/world  | 16096  | 15894 | 0.987        | 6.8%, 8.7%  |
| router annotation + strip       | POST /echo 1KB    | 9073   | 9025  | 0.995        | 19.9%, 15.6% |
| `Air.metrics` in the stack      | GET /hello/world  | 14572  | 12548 | 0.861        | 13.2%, 11.4% |
| `Air.metrics` in the stack      | POST /echo 1KB    | 8277   | 7908  | 0.956        | 22.2%, 13.2% |

The annotation is within noise. The middleware costs about 14% on the
cheapest route, about as much as the rate-limited route pays for its
own lock. Together they come to about 0.85 of the tree before 025, which
is at the CI gate's threshold, so a pull request that adds metrics to
hello may need `bench-accepted`. An app that does not use `Air.metrics`
pays only for the annotation.

## 2026-09-21 (after Tier 5 store, rate limiting and sessions), Apple Silicon, 32 connections, 5s

The store field on every request costs nothing measurable. `session`
wraps only `/count` and `/logout`, so the bench route is untouched;
the day's runs of it sit between 15k and 17.6k, run-to-run noise.
Minting a session per request (`/count` without a cookie) sustains
7-9k req/s across sweeps; the store-only `/visits` holds 13k with 40k
sessions in the store.

| target                | req/s | p50 ms | errors |
| --------------------- | ----: | -----: | -----: |
| Air GET /hello/:name  | 16167 | 1.9    | 0      |

## 2026-09-20 (after Tier 5 request ids and logging), Apple Silicon, 32 connections, 5s

The hello example now runs `Air.request_id` and `Air.log` in place of
its `timing` middleware, and the server no longer prints a line for app
responses. `log` alone costs nothing measurable (a JSON line replaces
the server's plain one). `request_id` costs 15% for its two map sets and
36 bytes on the wire, and at first another 20% for four random draws:
each `IO.random_u32` goes through the runtime's worker pool, like a
system call. An id is now one draw plus the millisecond clock.

| target                | req/s | p50 ms | errors |
| --------------------- | ----: | -----: | -----: |
| Air GET /hello/:name  | 17275 | 1.83   | 0      |

## 2026-09-20 (after Tier 5 CORS and shield), Apple Silicon, 32 connections, 5s

The hello example now runs `Air.shield(Air.Shield.default())` and
`Air.cors(Air.Cors.any())`, so every response carries six more headers,
about 230 bytes. Measured back to back on the same machine: the Tier 4
binary served 28.2k GET req/s; with both middleware, 17.5k. `cors` alone
costs nothing measurable; the whole drop is `shield`, and it is bytes,
not lookups: six one-letter headers with the same total bytes cost the
same. Two fixes in this round brought it to 21.4k: the head renderer
appended each header line to the growing accumulator (quadratic in
header bytes; now each line goes in front, linear), and the shield's
fixed names skip the lowercase pass. What remains is the runtime's cost
per byte of response: 230 bytes more in the body alone cost 16% here, so
a shield on a tiny response is a visible share. The Node reference sets
no such headers, so the two columns are no longer the same work.

| target                | req/s | p50 ms | errors |
| --------------------- | ----: | -----: | -----: |
| Air GET /hello/:name  | 21358 | 1.59   | 0      |
| Air POST /echo 1KB    | 10935 | 3.33   | 0      |

## 2026-09-20 (after Tier 3, Bend 2.0.19), Apple Silicon, 32 connections, 5s

Same load as below, after the request/response work and the toolchain
update. The streaming path is separate from this one and does not touch it.

| target                | req/s | p50 ms | errors |
| --------------------- | ----: | -----: | -----: |
| Air GET /hello/:name  | 30458 | 1.05   | 0      |
| Air POST /echo 1KB    | 12644 | 2.55   | 0      |

## 2026-09-19 (after Tier 2 routing), Apple Silicon, Bend 2.0.10, Node 24, 32 connections, 5s

Keep-alive is on for both servers now. The Tier 1 binary (before path
decoding, typed patterns and `Allow`) served 29.7k GET req/s and 12.8k POST
req/s under the same load; Tier 2 costs about 8% on GET, which is the
percent-decoding and normalization pass over the path.

| target                | req/s | p50 ms | p99 ms | errors |
| --------------------- | ----: | -----: | -----: | -----: |
| Air GET /hello/:name  | 27483 | 1.15   | 1.30   | 0      |
| Air POST /echo 1KB    | 13162 | 2.82   | 3.05   | 0      |
| Node GET /hello/:name | 63023 | 0.47   | 1.00   | 0      |
| Node POST /echo 1KB   | 56126 | 0.52   | 1.22   | 0      |

## 2026-09-19 (Tier 1, before keep-alive), Apple Silicon, Bend 2.0.10, Node 24, 32 connections, 5s

| target                | req/s | p50 ms | p99 ms | errors |
| --------------------- | ----: | -----: | -----: | -----: |
| Air GET /hello/:name  | 7730  | 3.64   | 10.9   | 2      |
| Air POST /echo 1KB    | 4387  | 5.56   | 32.1   | 233    |
| Node GET /hello/:name | 7521  | 3.48   | 17.7   | 0      |
| Node POST /echo 1KB   | 8373  | 3.43   | 10.3   | 0      |

At 8 connections Air serves 6400 req/s with p50 under 1 ms. At 64 it drops
to about 4300 req/s and refuses more connections. The POST gap is the body
path: the request buffer is a linked list of chars that is re-scanned on every
chunk.
