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
