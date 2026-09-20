# Plan 008: Handlers stream response bodies over chunked encoding, including Server-Sent Events

> **Executor instructions**: Deliver the stated outcome within scope. Adapt routine
> implementation details to current code, preserve the listed contracts, and run
> the relevant acceptance checks. Fix task-caused failures and recheck affected
> behavior. Escalate only the material conditions below. Update the plan's status
> in `.factory/plans/README.md`.
>
> **Drift check**: Requires plan 007 (the four-field `Response`). Confirm
> `air/server.bend` `send` still calls `Http.Response.render` once with the
> whole body, and that `Race.within` / `arm` are the timeout primitives.

## Status

- **Priority**: P2
- **Effort**: L
- **Risk**: HIGH (touches the server's send path and the timeout model)
- **Depends on**: `.factory/plans/007-response-builders.md`
- **Category**: direction (roadmap Tier 3: streaming bodies + SSE)
- **Planned at**: no commit yet, 2026-09-19

## Why this matters

A response today is one `String` written in one `TCP.send`. A handler that
wants to push progress, tail a log, or serve Server-Sent Events has to
produce everything first. Bend gives the pieces: `IO.fork`/`IO.spawn` run a
producer concurrently and `Chan.recv` answers `None{}` when the producer
closes the channel (`bend guide`, "IO and Concurrency"). The server can
write a chunked body by receiving from that channel until it closes.

Decisions:

- **A stream is a `Chan(String)` on the response.** The handler creates it,
  forks a producer that `Chan.send`s pieces and finally `Chan.close`s, and
  returns `Response.stream(chan)`. The server owns the socket and writes
  each piece as one chunk. This keeps the "handler returns a value" contract.
- **Timeouts**: the app timeout still bounds the handler returning the
  `Response`. Each chunk write is raced under the `send` timeout, re-armed
  per chunk. A producer that goes silent is bounded by a new `stream` idle
  timeout: the wait on the channel is raced under the `send` timeout too
  (one clock, re-armed), so no new `Timeouts` field is needed; document
  that `send` is the per-chunk budget.
- **HTTP/1.0 or HEAD**: a 1.0 client gets the stream with
  `connection: close` and no framing (body ends when the socket closes);
  HEAD gets the head only and the channel is drained to let the producer
  finish (or closed, if `Chan.close` from the reader side is allowed; verify
  with a scratch program, since the guide does not say).
- **Backpressure**: `Chan.new(String, room)` has a room parameter. Use a
  small room (8) so a producer blocks when the client is slow; Tier 6 owns
  a fuller policy.

## Current state

- `air/server.bend`:
  - `send(+ctx, sock, rest, head_only, +keep, res)` arms the send timeout,
    renders the whole response, `send_within`, then `after_send` decides
    `Again{sock, rest}` or `stop(sock)`.
  - `respond(+ctx, sock, +req, rest, +res)` logs and calls `send` with
    `head_only` = method is HEAD and `keep` from the request and the
    response's `connection` header.
  - `arm(ctx, ms) -> IO(U32)` re-arms the per-connection watchdog and returns
    a generation; `Race.within(T, on_lose, clock, gen, effect)` returns
    `Race.Won{v}` or `Race.Lost{}`. `close_send` is the loser callback that
    closes the socket when a late send returns.
  - Pipelining: `rest` is bytes after this request; a stream must not
    interleave with them, which is already true since the loop is sequential.
- `air/http.bend`: after 007, `Response{status, headers, cookies, body: String}`.
  `Response.render(r, head_only, keep)` produces head and body together;
  `Response.no_body(status)`, `render_length`.
- `air/race.bend`: `within`, `Arm`, one watchdog per connection (AGENTS.md:
  never leave a sleeper per request behind).
- `Chan.send(A, chan, v) -> IO(Bool)` (false when closed), `Chan.recv -> IO(Maybe<&1, A>)`,
  `Chan.close`, `IO.spawn(Unit, act)`, `IO.fork`.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Check and prove | `bend PROOF.bend` | `All terms check.` |
| Probe | `curl -sN localhost:8080/ticks` | lines arriving one per second |
| Wire check | `printf 'GET /ticks HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n' \| nc localhost 8080` | `transfer-encoding: chunked`, hex sizes, final `0\r\n\r\n` |

## Implementation rules relevant to this plan

- The body variant lives in `Http`; the loop that drains a channel to the
  socket lives in `Server`, next to `send`. `Http` never touches a socket.
- Every loop is a `Nat`-fuel recursion advanced by a pure step, like
  `session`/`step` in the server. Cap chunks per stream generously (a
  million) and close the connection when the cap is hit.
- One watchdog per connection: use `arm` before each chunk, never `IO.sleep`.
- Keep `Response.render` byte-identical for whole bodies (laws pin it).

## Scope

**In scope**:
- `air/http.bend` — `type Body is Type: Whole{text: String} | Stream{chan: Chan(String)}`
  (a `Chan` is `Data`, so `Body` can be `Data`; verify), `Response.body`
  field becomes `Body`; `Response.stream(chan)`, `Response.sse(chan)`
  (`content-type: text/event-stream`, `cache-control: no-cache`),
  `Response.render_head(r, keep, chunked)` split out of `render`; `Sse.event(name, data)`
  and `Sse.data(data)` formatters (each line of `data` prefixed `data: `,
  ending with a blank line).
- `air/server.bend` — `send` branches on the body: `Whole` unchanged; `Stream`
  writes the head with `transfer-encoding: chunked` (HTTP/1.1) then
  `stream_loop`; on HEAD, head only.
- `air.bend` — `Air.Response.stream / sse`, `Air.Sse.event / data`, `Air.Stream.new() -> IO(Chan(String))`
  as a thin alias so apps do not import `Chan` details.
- `examples/hello/main.bend` — `GET /ticks`: SSE, five events one second apart.
- `LAWS.bend`, `PROOF.bend`, `README.md`, `.factory/plans/README.md`.

**Out of scope**: request body streaming (rejected in 005); compression;
WebSocket (Tier 5); a separate stream timeout field.

## Git workflow

- Do not commit or push unless asked. `bend PROOF.bend` before any commit.

## Steps

### Step 1: verify channel semantics with a scratch program

Before touching the server, write `scratch_chan.bend` at the repo root
(relative import; delete after): fork a producer that sends three strings
and closes; the main computation `Chan.recv`s until `None{}`. Also test
what a reader-side `Chan.close` does to a blocked `Chan.send` (the
`Chan.send` result `Bool`). Record both facts in the plan status row; they
decide the HEAD handling.

### Step 2: `Body` in `Http`

Change the last field to `Body`; every accessor match updates. `Response.body(r)`
returns `""` for a stream (document). `render(r, head_only, keep)` handles
`Whole` exactly as today; for `Stream` it renders the head with
`transfer-encoding: chunked` and no `content-length` (or, when `keep` is
false and the request was 1.0, neither: a parameter `chunked: Bool`).
Add `chunk(piece) -> String`: hex length, `\r\n`, piece, `\r\n`; and
`last_chunk() = "0\r\n\r\n"`. Sizes are bytes: use `Text.byte_length`.

### Step 3: the server loop

In `send`, match the body (through an `Http.Response.kind` helper that
returns Data, since `Body` holds a channel and cannot be `+`):

- `Whole` → today's path.
- `Stream{chan}` → send the head under the send timeout; then
  `stream_loop(fuel, ctx, sock, chan, chunked)`: `arm` the send timeout,
  `Race.within` the `Chan.recv`; `Won{Some{piece}}` → send `chunk(piece)`
  (raced again), loop; `Won{None}` → send `last_chunk()` when `chunked`,
  then `after_send` as today; `Lost` → `late("stream")` (the socket is
  with the loser callback, as for reads). A failed send (client gone)
  stops the loop; the producer's next `Chan.send` returns false when the
  server closes the channel: close it on every exit path so producers can
  notice.
- HEAD: send the head, close the channel (if step 1 showed that unblocks
  the producer) or spawn a drain, then continue as a whole response would.

### Step 4: facade, example, README

`Air.Stream.new()`, `Air.Response.stream(chan)`, `Air.Response.sse(chan)`,
`Air.Sse.event(name, data)`, `Air.Sse.data(data)`. The hello example:

```
def ticks(req: Air.Request()) -> IO(Air.Response()):
  do IO<Air.Response()>:
    chan : Chan(String) <- Air.Stream.new()
    IO.spawn(Unit, tick(5n, chan))
    return Air.Response.sse(chan)
```

with `tick` sending `Air.Sse.event("tick", U32.show(n))` and sleeping
1000 ms, then `Chan.close`. README: a "Streaming" section with this
example, the per-chunk `send` timeout rule, and the HTTP/1.0 behavior.

### Step 5: laws

```
chunk_frames:        Http.chunk("Wiki") == "4\r\nWiki\r\n"; chunk("Olá") == "4\r\nOlá\r\n" (bytes)
last_chunk:          "0\r\n\r\n"
sse_event_format:    Sse.event("tick", "a\nb") == "event: tick\ndata: a\ndata: b\n\n"
sse_data_format:     Sse.data("x") == "data: x\n\n"
render_stream_head:  render_head for a stream response == exact text with transfer-encoding: chunked and no content-length
render_whole_unchanged: the three existing render laws still pass
```

Server behavior is proven live (step 6), since it is IO.

### Step 6: live checks

`curl -sN localhost:8080/ticks` shows five events a second apart; the `nc`
wire check shows chunk framing and the final `0`; a client that
disconnects after two events leaves no stuck computation (the process
stays responsive: a second curl works) and the log shows the stream end;
an HTTP/1.0 request gets the body unframed and the connection closed;
`curl -I localhost:8080/ticks` returns promptly with head only.

## Test plan

Laws for the pure parts; the six live checks above recorded in the status row.

## Done criteria

- [ ] `bend PROOF.bend` prints `All terms check.`
- [ ] Six live checks pass, including the disconnect and HEAD cases.
- [ ] Whole-body throughput unchanged within noise: `SKIP_BUILD= bash bench/run.sh 32 5` GET within 5% of the 27.5k req/s in `bench/README.md`.
- [ ] README has the Streaming section; roadmap row ticked.
- [ ] `git status --short` shows only in-scope files (plus `bench/out/*` from the bench).

## STOP conditions

- Step 1 shows a reader cannot unblock a producer (no reader-side close
  and `Chan.send` blocks forever on a full channel): then a producer to a
  disconnected client leaks a computation. Report with the scratch output
  before implementing; the plan may need a producer-side `Air.Stream.send`
  that checks a stop flag.
- The bench regresses more than 5% on whole bodies.

## Maintenance notes

- WebSocket (Tier 5) will want the same "server owns the socket, handler
  owns a channel" shape; keep `stream_loop` free of SSE specifics.
- Reviewer focus: every exit path closes the channel; `arm` per chunk, no sleeps.
