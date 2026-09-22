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
