import Base
import ./text.bend as Text
import ./chunk.bend as Chunk
import ./http.bend as Http
import ./router.bend as Router
import ./race.bend as Race
import ./drain.bend as Drain

# Server
# ======
#
# HTTP/1.1 over Bend's TCP effects: keep-alive and pipelining,
# Content-Length and chunked bodies, `Expect: 100-continue`, and the
# no-body rules for HEAD, 1xx, 204 and 304. Each connection runs as its
# own computation, with a clock (race.bend) that bounds every phase of a
# request and a gate (drain.bend) through which the server stops.

def RecvR() -> Type:
  Socket & Result<&1, &1, U32 & String, String>

def SendR() -> Type:
  Socket & Result<&1, &1, U32 & String, Unit>

def AcceptR() -> Type:
  Listener & Result<&1, &1, U32 & String, Socket>

def RecvRaced() -> Type:
  Race.Raced<RecvR()>

def SendRaced() -> Type:
  Race.Raced<SendR()>

def recv_size() -> U32:
  65536

# Requests served on one connection before it is closed.
def max_requests() -> Nat:
  100000n

# Timeouts
# --------
#
# Milliseconds; 0 means no limit. `idle` bounds the wait for a request on
# an open connection, `head` the request line and headers from their
# first byte, `body` the body, `app` the handler, `send` the write of the
# response, and `drain` how long a stopping server waits for the requests
# in flight. A phase that runs out of time closes the connection; the
# app's timeout answers 503 first.
type Timeouts is Data:
  Timeouts{idle: U32, head: U32, body: U32, app: U32, send: U32, drain: U32}

# 15 s idle, 10 s head, 30 s body, 30 s app, 30 s send, 10 s drain.
def Timeouts.default() -> Timeouts:
  Timeouts{15000, 10000, 30000, 30000, 30000, 10000}

def Timeouts.idle(t: Timeouts) -> U32:
  match t:
    case Timeouts{a, b, c, d, e, f}:
      a

def Timeouts.head(t: Timeouts) -> U32:
  match t:
    case Timeouts{a, b, c, d, e, f}:
      b

def Timeouts.body(t: Timeouts) -> U32:
  match t:
    case Timeouts{a, b, c, d, e, f}:
      c

def Timeouts.app(t: Timeouts) -> U32:
  match t:
    case Timeouts{a, b, c, d, e, f}:
      d

def Timeouts.send(t: Timeouts) -> U32:
  match t:
    case Timeouts{a, b, c, d, e, f}:
      e

def Timeouts.drain(t: Timeouts) -> U32:
  match t:
    case Timeouts{a, b, c, d, e, f}:
      f

def least.go(+a: U32, +b: U32, none_a: Bool, none_b: Bool) -> U32:
  match none_a none_b:
    case True{} _:
      b
    case False{} True{}:
      a
    case False{} False{}:
      U32.min(a, b)

# The smaller of two limits, where 0 is no limit.
def least(+a: U32, +b: U32) -> U32:
  least.go(a, b, U32.is_zero(a), U32.is_zero(b))

# The watchdog's step: the shortest limit in force on a connection.
def Timeouts.step(+t: Timeouts) -> U32:
  least(Timeouts.idle(t), least(Timeouts.head(t), least(Timeouts.body(t), least(Timeouts.app(t), Timeouts.send(t)))))

# Context
# -------

# What a connection carries: the settings, the app's stop switch, the
# server's gate, and the connection's own clock.
type Ctx is Data:
  Ctx{limits: Http.Limits, timeouts: Timeouts, switch: Chan(Unit), gate: Chan(Drain.Tally), clock: Race.Clock}

def Ctx.limits(+c: Ctx) -> Http.Limits:
  match c:
    case Ctx{limits, timeouts, switch, gate, clock}:
      limits

def Ctx.timeouts(+c: Ctx) -> Timeouts:
  match c:
    case Ctx{limits, timeouts, switch, gate, clock}:
      timeouts

def Ctx.switch(+c: Ctx) -> Chan(Unit):
  match c:
    case Ctx{limits, timeouts, switch, gate, clock}:
      switch

def Ctx.gate(+c: Ctx) -> Chan(Drain.Tally):
  match c:
    case Ctx{limits, timeouts, switch, gate, clock}:
      gate

def Ctx.clock(+c: Ctx) -> Race.Clock:
  match c:
    case Ctx{limits, timeouts, switch, gate, clock}:
      clock

def Ctx.head_max(+c: Ctx) -> U32:
  Http.Limits.head(Ctx.limits(c))

def Ctx.body_max(+c: Ctx) -> U32:
  Http.Limits.body(Ctx.limits(c))

# Starts a phase: the connection's clock is set `ms` from now.
def arm(+c: Ctx, +ms: U32) -> IO(U32):
  Race.arm(Ctx.clock(c), ms)

# Racing
# ------
#
# A receive or send that loses its race still holds the socket, and
# closes it when the effect finally returns.

def close_recv(r: RecvR()) -> IO(Unit):
  (sock, res) = r
  Socket.close(sock)

def close_send(r: SendR()) -> IO(Unit):
  (sock, res) = r
  Socket.close(sock)

def drop_reply(res: Http.Response) -> IO(Unit):
  IO.pure(Unit, Unit{})

def recv_within(+ctx: Ctx, +gen: U32, sock: Socket) -> IO(RecvRaced()):
  Race.within(RecvR(), close_recv, Ctx.clock(ctx), gen, TCP.recv(sock, recv_size()))

def send_within(+ctx: Ctx, +gen: U32, sock: Socket, data: String) -> IO(SendRaced()):
  Race.within(SendR(), close_send, Ctx.clock(ctx), gen, TCP.send(sock, data))

# Head
# ----

# Reading the head: receive until the blank line, the size cap, the
# deadline, or the peer hangs up. `rest` is whatever followed the blank
# line.
type HeadState is Type:
  HeadReading{sock: Socket, buf: String, size: U32}
  HeadDone{sock: Socket, head: String, rest: String}
  HeadEof{sock: Socket}
  HeadFail{sock: Socket, status: U32}
  HeadLate{waiting: Bool}

def head_sized.fin(sock: Socket, head: String, rest: String, over: Bool) -> HeadState:
  match over:
    case True{}:
      HeadFail{sock, 431}
    case False{}:
      HeadDone{sock, head, rest}

def head_sized(sock: Socket, +head: String, rest: String, +max: U32) -> HeadState:
  head_sized.fin(sock, head, rest, U32.is_gt(Text.byte_length(head, 0), max))

def head_more(sock: Socket, buf: String, size: U32, eof: Bool, over: Bool) -> HeadState:
  match eof over:
    case True{} _:
      HeadEof{sock}
    case False{} True{}:
      HeadFail{sock, 431}
    case False{} False{}:
      HeadReading{sock, buf, size}

def head_fin(sock: Socket, buf: String, +size: U32, +max: U32, eof: Bool, found: Maybe<&2, Text.Two()>) -> HeadState:
  match found:
    case Some{hr}:
      (head, rest) = hr
      head_sized(sock, head, rest, max)
    case None{}:
      head_more(sock, buf, size, eof, U32.is_gt(size, max))

def head_grow(sock: Socket, +buf: String, size: U32, max: U32, eof: Bool) -> HeadState:
  head_fin(sock, buf, size, max, eof, Text.split_str(buf, "\r\n\r\n"))

def head_advance(+max: U32, buf: String, +size: U32, r: RecvR()) -> HeadState:
  (sock, res) = r
  match res:
    case Fail{e}:
      HeadEof{sock}
    case Done{+chunk}:
      head_grow(sock, Text.drop_crlf(Text.append(buf, chunk)), U32.add(size, Text.byte_length(chunk, 0)), max, String.is_empty(chunk))

# A deadline hit while waiting is the idle one; after that, the head's.
def head_raced(+max: U32, buf: String, +size: U32, waiting: Bool, r: RecvRaced()) -> HeadState:
  match r:
    case Race.Won{v}:
      head_advance(max, buf, size, v)
    case Race.Lost{}:
      HeadLate{waiting}

# The first look at a connection's buffer: bytes left over from the
# previous request may already hold the next head.
def head_start.go(+max: U32, sock: Socket, +buf: String) -> HeadState:
  head_grow(sock, buf, Text.byte_length(buf, 0), max, False{})

def head_start(+max: U32, sock: Socket, buf: String) -> HeadState:
  head_start.go(max, sock, Text.drop_crlf(buf))

# Once the first bytes are in, the wait is over and the head limit starts.
def head_phase(+ctx: Ctx, +gen: U32, waiting: Bool) -> IO(U32):
  match waiting:
    case True{}:
      arm(ctx, Timeouts.head(Ctx.timeouts(ctx)))
    case False{}:
      IO.pure(U32, gen)

def read_head(fuel: Nat, +ctx: Ctx, +gen: U32, +waiting: Bool, state: HeadState) -> IO(HeadState):
  match fuel state:
    case _ HeadDone{sock, head, rest}:
      IO.pure(HeadState, HeadDone{sock, head, rest})
    case _ HeadEof{sock}:
      IO.pure(HeadState, HeadEof{sock})
    case _ HeadFail{sock, status}:
      IO.pure(HeadState, HeadFail{sock, status})
    case _ HeadLate{w}:
      IO.pure(HeadState, HeadLate{w})
    case 0n HeadReading{sock, buf, size}:
      IO.pure(HeadState, HeadEof{sock})
    case 1n+p HeadReading{sock, buf, size}:
      do IO<HeadState>:
        r : RecvRaced() <- recv_within(ctx, gen, sock)
        next : U32 <- head_phase(ctx, gen, waiting)
        read_head(p, ctx, next, False{}, head_raced(Ctx.head_max(ctx), buf, size, waiting, r))

# Body
# ----

# Reading the body: a fixed number of bytes, or chunks until the last one.
# `rest` in `BodyDone` is the start of the next pipelined request. A
# status of 0 in `BodyFail` means the peer went away: close, do not reply.
type BodyState is Type:
  BodyFixed{sock: Socket, buf: String, need: U32}
  BodyChunked{sock: Socket, chunk: Chunk.Decoder}
  BodyDone{sock: Socket, body: String, rest: String}
  BodyFail{sock: Socket, status: U32}
  BodyLate{}

def fixed_fin(sock: Socket, buf: String, need: U32, take: Text.Take) -> BodyState:
  match take:
    case Text.Took{body, rest}:
      BodyDone{sock, body, rest}
    case Text.TakeNeed{}:
      BodyFixed{sock, buf, need}
    case Text.TakeBad{}:
      BodyFail{sock, 400}

def fixed(sock: Socket, +buf: String, +need: U32) -> BodyState:
  fixed_fin(sock, buf, need, Text.take_bytes(buf, need))

def chunked_fin(sock: Socket, c: Chunk.Decoder) -> BodyState:
  match c:
    case Chunk.ChunkWait{s}:
      BodyChunked{sock, s}
    case Chunk.ChunkDone{body, rest}:
      BodyDone{sock, body, rest}
    case Chunk.ChunkBad{status}:
      BodyFail{sock, status}
    case Chunk.ChunkSize{buf, acc, used}:
      BodyChunked{sock, Chunk.ChunkSize{buf, acc, used}}
    case Chunk.ChunkData{buf, acc, used, n}:
      BodyChunked{sock, Chunk.ChunkData{buf, acc, used, n}}
    case Chunk.ChunkTrail{buf, acc}:
      BodyChunked{sock, Chunk.ChunkTrail{buf, acc}}

def chunked(sock: Socket, +max: U32, c: Chunk.Decoder) -> BodyState:
  chunked_fin(sock, Chunk.drain(1000000n, max, c))

def body_start.fixed(sock: Socket, rest: String, +n: U32, over: Bool) -> BodyState:
  match over:
    case True{}:
      BodyFail{sock, 413}
    case False{}:
      fixed(sock, rest, n)

def body_start(sock: Socket, +max: U32, rest: String, framing: Http.Framing) -> BodyState:
  match framing:
    case Http.NoBody{}:
      BodyDone{sock, SNil{}, rest}
    case Http.Fixed{+n}:
      body_start.fixed(sock, rest, n, U32.is_gt(n, max))
    case Http.Chunked{}:
      chunked(sock, max, Chunk.ChunkSize{rest, SNil{}, 0})
    case Http.Unframed{status}:
      BodyFail{sock, status}

def fixed_more(sock: Socket, buf: String, need: U32, eof: Bool) -> BodyState:
  match eof:
    case True{}:
      BodyFail{sock, 0}
    case False{}:
      fixed(sock, buf, need)

def fixed_advance(buf: String, need: U32, r: RecvR()) -> BodyState:
  (sock, res) = r
  match res:
    case Fail{e}:
      BodyFail{sock, 0}
    case Done{+chunk}:
      fixed_more(sock, Text.append(buf, chunk), need, String.is_empty(chunk))

def fixed_raced(buf: String, need: U32, r: RecvRaced()) -> BodyState:
  match r:
    case Race.Won{v}:
      fixed_advance(buf, need, v)
    case Race.Lost{}:
      BodyLate{}

def chunked_more(sock: Socket, +max: U32, c: Chunk.Decoder, eof: Bool) -> BodyState:
  match eof:
    case True{}:
      BodyFail{sock, 0}
    case False{}:
      chunked(sock, max, c)

def chunked_advance(+max: U32, c: Chunk.Decoder, r: RecvR()) -> BodyState:
  (sock, res) = r
  match res:
    case Fail{e}:
      BodyFail{sock, 0}
    case Done{+chunk}:
      chunked_more(sock, max, Chunk.feed(c, chunk), String.is_empty(chunk))

def chunked_raced(+max: U32, c: Chunk.Decoder, r: RecvRaced()) -> BodyState:
  match r:
    case Race.Won{v}:
      chunked_advance(max, c, v)
    case Race.Lost{}:
      BodyLate{}

def read_body(fuel: Nat, +ctx: Ctx, +gen: U32, state: BodyState) -> IO(BodyState):
  match fuel state:
    case _ BodyDone{sock, body, rest}:
      IO.pure(BodyState, BodyDone{sock, body, rest})
    case _ BodyFail{sock, status}:
      IO.pure(BodyState, BodyFail{sock, status})
    case _ BodyLate{}:
      IO.pure(BodyState, BodyLate{})
    case 0n BodyFixed{sock, buf, need}:
      IO.pure(BodyState, BodyFail{sock, 0})
    case 0n BodyChunked{sock, c}:
      IO.pure(BodyState, BodyFail{sock, 0})
    case 1n+p BodyFixed{sock, buf, need}:
      do IO<BodyState>:
        r : RecvRaced() <- recv_within(ctx, gen, sock)
        read_body(p, ctx, gen, fixed_raced(buf, need, r))
    case 1n+p BodyChunked{sock, c}:
      do IO<BodyState>:
        r : RecvRaced() <- recv_within(ctx, gen, sock)
        read_body(p, ctx, gen, chunked_raced(Ctx.body_max(ctx), c, r))

# Reply
# -----

# What a connection does after a response: serve another request from
# the bytes already buffered, or stop (the socket is closed by then, or
# on its way to be).
type Next is Type:
  Again{sock: Socket, rest: String}
  Stop{}

def log(method: String, path: String, +status: U32) -> IO(Unit):
  IO.print(method ++ " " ++ path ++ " -> " ++ U32.show(status))

def stop(sock: Socket) -> IO(Next):
  do IO<Next>:
    Socket.close(sock)
    return Stop{}

# A phase ran out of time. The socket is with the runner still waiting
# on it, which closes it when that wait ends.
def late(what: String) -> IO(Next):
  do IO<Next>:
    IO.print("air: timeout: " ++ what)
    return Stop{}

def after_send.go(r: SendR(), keep: Bool, rest: String) -> IO(Next):
  (sock, res) = r
  match res keep:
    case Done{u} True{}:
      IO.pure(Next, Again{sock, rest})
    case _ _:
      stop(sock)

def after_send(r: SendRaced(), keep: Bool, rest: String) -> IO(Next):
  match r:
    case Race.Won{v}:
      after_send.go(v, keep, rest)
    case Race.Lost{}:
      late("reply")

def send(+ctx: Ctx, sock: Socket, rest: String, head_only: Bool, +keep: Bool, res: Http.Response) -> IO(Next):
  do IO<Next>:
    gen : U32 <- arm(ctx, Timeouts.send(Ctx.timeouts(ctx)))
    r : SendRaced() <- send_within(ctx, gen, sock, Http.Response.render(res, head_only, keep))
    after_send(r, keep, rest)

# An error reply. It always closes, since the request stream can no
# longer be trusted. Http.Status 0 closes without a reply.
def refuse.go(+ctx: Ctx, sock: Socket, method: String, path: String, +status: U32, silent: Bool) -> IO(Next):
  match silent:
    case True{}:
      stop(sock)
    case False{}:
      do IO<Next>:
        log(method, path, status)
        send(ctx, sock, SNil{}, False{}, False{}, Http.Response.with_status(Http.Response.text(Http.Status.reason(status)), status))

def refuse(+ctx: Ctx, sock: Socket, method: String, path: String, +status: U32) -> IO(Next):
  refuse.go(ctx, sock, method, path, status, U32.is_eq(status, 0))

# Writes the app's response. The connection stays open when both the
# request and the response allow it.
def respond(+ctx: Ctx, sock: Socket, +req: Http.Request, rest: String, +res: Http.Response) -> IO(Next):
  do IO<Next>:
    log(Http.Method.show(Http.Request.method(req)), Http.Request.path(req), Http.Response.status(res))
    send(
      ctx,
      sock,
      rest,
      Http.Method.is_eq(Http.Request.method(req), Http.HEAD{}),
      Bool.and(Http.Request.keep_alive(req), Bool.not(Text.has_token(Http.Response.header(res, "connection"), "close"))),
      res)

# App
# ---

def on_app(+ctx: Ctx, sock: Socket, +req: Http.Request, rest: String, r: Race.Raced<Http.Response>) -> IO(Next):
  match r:
    case Race.Won{res}:
      respond(ctx, sock, req, rest, res)
    case Race.Lost{}:
      do IO<Next>:
        IO.print("air: timeout: app")
        refuse(ctx, sock, Http.Method.show(Http.Request.method(req)), Http.Request.path(req), 503)

# Runs the app under its deadline. A handler that overruns keeps running
# in its own computation, but its response is dropped and the client
# gets a 503.
def run(~app: Chan(Unit) -> Router.Handler(), +ctx: Ctx, sock: Socket, +req: Http.Request, rest: String, body: String) -> IO(Next):
  do IO<Next>:
    gen : U32 <- arm(ctx, Timeouts.app(Ctx.timeouts(ctx)))
    r : Race.Raced<Http.Response> <- Race.within(Http.Response, drop_reply, Ctx.clock(ctx), gen, app(Ctx.switch(ctx), Http.Request.with_body(req, body)))
    on_app(ctx, sock, req, rest, r)

def on_body(~app: Chan(Unit) -> Router.Handler(), +ctx: Ctx, +req: Http.Request, state: BodyState) -> IO(Next):
  match state:
    case BodyDone{sock, body, rest}:
      run(~app, ctx, sock, req, rest, body)
    case BodyFail{sock, status}:
      refuse(ctx, sock, Http.Method.show(Http.Request.method(req)), Http.Request.path(req), status)
    case BodyFixed{sock, buf, need}:
      stop(sock)
    case BodyChunked{sock, c}:
      stop(sock)
    case BodyLate{}:
      late("body")

def body_fuel() -> Nat:
  1048576n

def continue_line() -> String:
  "HTTP/1.1 100 Continue\r\n\r\n"

def framed(f: Http.Framing) -> Bool:
  match f:
    case Http.NoBody{}:
      False{}
    case Http.Fixed{n}:
      True{}
    case Http.Chunked{}:
      True{}
    case Http.Unframed{status}:
      True{}

# The body phase starts only when there is a body to read.
def body_phase(+ctx: Ctx, has_body: Bool) -> IO(U32):
  match has_body:
    case True{}:
      arm(ctx, Timeouts.body(Ctx.timeouts(ctx)))
    case False{}:
      IO.pure(U32, 0)

def after_continue.go(~app: Chan(Unit) -> Router.Handler(), +ctx: Ctx, +gen: U32, +req: Http.Request, framing: Http.Framing, r: SendR()) -> IO(Next):
  (sock, res) = r
  match res:
    case Fail{e}:
      stop(sock)
    case Done{u}:
      do IO<Next>:
        state : BodyState <- read_body(body_fuel(), ctx, gen, body_start(sock, Ctx.body_max(ctx), SNil{}, framing))
        on_body(~app, ctx, req, state)

def after_continue(~app: Chan(Unit) -> Router.Handler(), +ctx: Ctx, +gen: U32, +req: Http.Request, framing: Http.Framing, r: SendRaced()) -> IO(Next):
  match r:
    case Race.Won{v}:
      after_continue.go(~app, ctx, gen, req, framing, v)
    case Race.Lost{}:
      late("100-continue")

def send_continue(~app: Chan(Unit) -> Router.Handler(), +ctx: Ctx, +gen: U32, +req: Http.Request, framing: Http.Framing, sock: Socket) -> IO(Next):
  do IO<Next>:
    r : SendRaced() <- send_within(ctx, gen, sock, continue_line())
    after_continue(~app, ctx, gen, req, framing, r)

# With `Expect: 100-continue` and no body bytes in yet, the client is
# waiting for a go-ahead before it sends the body.
def on_framing(~app: Chan(Unit) -> Router.Handler(), +ctx: Ctx, +req: Http.Request, sock: Socket, rest: String, +framing: Http.Framing, expect: Bool) -> IO(Next):
  match expect:
    case True{}:
      do IO<Next>:
        gen : U32 <- arm(ctx, Timeouts.body(Ctx.timeouts(ctx)))
        send_continue(~app, ctx, gen, req, framing, sock)
    case False{}:
      do IO<Next>:
        gen : U32 <- body_phase(ctx, framed(framing))
        state : BodyState <- read_body(body_fuel(), ctx, gen, body_start(sock, Ctx.body_max(ctx), rest, framing))
        on_body(~app, ctx, req, state)

def on_request(~app: Chan(Unit) -> Router.Handler(), +ctx: Ctx, sock: Socket, +rest: String, +req: Http.Request, +framing: Http.Framing) -> IO(Next):
  on_framing(~app, ctx, req, sock, rest, framing,
    Bool.and(Http.Request.expects_continue(req), Bool.and(String.is_empty(rest), Http.Framing.readable(framing, Ctx.body_max(ctx)))))

def on_parsed(~app: Chan(Unit) -> Router.Handler(), +ctx: Ctx, sock: Socket, rest: String, parsed: Http.Parsed) -> IO(Next):
  match parsed:
    case Http.Refused{status}:
      refuse(ctx, sock, "?", "?", status)
    case Http.Parsed{+req}:
      on_request(~app, ctx, sock, rest, req, Http.Request.framing(req))

# A request that made it through the gate is served and then signed
# out; one that did not meets a stopping server and gets a 503.
def admitted(~app: Chan(Unit) -> Router.Handler(), +ctx: Ctx, sock: Socket, head: String, rest: String, ok: Bool) -> IO(Next):
  match ok:
    case True{}:
      do IO<Next>:
        next : Next <- on_parsed(~app, ctx, sock, rest, Http.Request.parse(Ctx.limits(ctx), head))
        Drain.leave(Ctx.gate(ctx))
        return next
    case False{}:
      refuse(ctx, sock, "?", "?", 503)

def head_late(waiting: Bool) -> IO(Next):
  match waiting:
    case True{}:
      late("idle")
    case False{}:
      late("head")

def on_head(~app: Chan(Unit) -> Router.Handler(), +ctx: Ctx, state: HeadState) -> IO(Next):
  match state:
    case HeadEof{sock}:
      stop(sock)
    case HeadFail{sock, status}:
      refuse(ctx, sock, "?", "?", status)
    case HeadReading{sock, buf, size}:
      stop(sock)
    case HeadLate{waiting}:
      head_late(waiting)
    case HeadDone{sock, head, rest}:
      do IO<Next>:
        ok : Bool <- Drain.enter(Ctx.gate(ctx))
        admitted(~app, ctx, sock, head, rest, ok)

# An empty buffer means waiting on the client; bytes already in mean a
# head is under way.
def first_wait(+ctx: Ctx, fresh: Bool) -> U32:
  match fresh:
    case True{}:
      Timeouts.idle(Ctx.timeouts(ctx))
    case False{}:
      Timeouts.head(Ctx.timeouts(ctx))

# One request: read the head, frame and read the body, run the app,
# write the response.
def step(~app: Chan(Unit) -> Router.Handler(), +ctx: Ctx, sock: Socket, +buf: String) -> IO(Next):
  do IO<Next>:
    gen : U32 <- arm(ctx, first_wait(ctx, String.is_empty(buf)))
    state : HeadState <- read_head(1024n, ctx, gen, String.is_empty(buf), head_start(Ctx.head_max(ctx), sock, buf))
    on_head(~app, ctx, state)

def session(~app: Chan(Unit) -> Router.Handler(), +ctx: Ctx, fuel: Nat, next: Next) -> IO(Unit):
  match fuel next:
    case _ Stop{}:
      IO.pure(Unit, Unit{})
    case 0n Again{sock, rest}:
      Socket.close(sock)
    case 1n+p Again{sock, rest}:
      do IO<Unit>:
        n : Next <- step(~app, ctx, sock, rest)
        session(~app, ctx, p, n)

def conn.go(~app: Chan(Unit) -> Router.Handler(), +ctx: Ctx, sock: Socket) -> IO(Unit):
  do IO<Unit>:
    session(~app, ctx, max_requests(), Again{sock, SNil{}})
    Race.Clock.stop(Ctx.clock(ctx))

# One connection: requests in turn until one side closes or a phase
# runs out of time. The clock stops with the connection.
def conn(~app: Chan(Unit) -> Router.Handler(), +limits: Http.Limits, +timeouts: Timeouts, +switch: Chan(Unit), +gate: Chan(Drain.Tally), sock: Socket) -> IO(Unit):
  IO.bind(Race.Clock, Unit, Race.Clock.new(Timeouts.step(timeouts)), clock => conn.go(~app, Ctx{limits, timeouts, switch, gate, clock}, sock))

# Accepting
# ---------

type Serving is Type:
  Serving{listener: Listener}
  Closed{}

def admit(~app: Chan(Unit) -> Router.Handler(), +limits: Http.Limits, +timeouts: Timeouts, +switch: Chan(Unit), +gate: Chan(Drain.Tally), listener: Listener, sock: Socket, open: Bool) -> IO(Serving):
  match open:
    case True{}:
      do IO<Serving>:
        IO.spawn(Unit, conn(~app, limits, timeouts, switch, gate, sock))
        return Serving{listener}
    case False{}:
      do IO<Serving>:
        Socket.close(sock)
        Listener.close(listener)
        return Closed{}

def accepted(~app: Chan(Unit) -> Router.Handler(), +limits: Http.Limits, +timeouts: Timeouts, +switch: Chan(Unit), +gate: Chan(Drain.Tally), r: AcceptR()) -> IO(Serving):
  (listener, res) = r
  match res:
    case Fail{e}:
      do IO<Serving>:
        IO.print_err("accept failed")
        return Serving{listener}
    case Done{sock}:
      do IO<Serving>:
        open : Bool <- Drain.is_open(gate)
        admit(~app, limits, timeouts, switch, gate, listener, sock, open)

def loop(~app: Chan(Unit) -> Router.Handler(), +limits: Http.Limits, +timeouts: Timeouts, +switch: Chan(Unit), +gate: Chan(Drain.Tally), fuel: Nat, state: Serving) -> IO(Unit):
  match fuel state:
    case _ Closed{}:
      IO.pure(Unit, Unit{})
    case 0n Serving{listener}:
      Listener.close(listener)
    case 1n+p Serving{listener}:
      do IO<Unit>:
        r : AcceptR() <- TCP.accept(listener)
        next : Serving <- accepted(~app, limits, timeouts, switch, gate, r)
        loop(~app, limits, timeouts, switch, gate, p, next)

# Stopping
# --------

def knocked(r: Result<&1, &1, U32 & String, Socket>) -> IO(Unit):
  match r:
    case Done{sock}:
      Socket.close(sock)
    case Fail{e}:
      IO.print_err("air: could not connect to the listener to stop it")

# The accept loop looks at the gate only after an accept, so knock.
def knock(+port: U32) -> IO(Unit):
  IO.bind(Result<&1, &1, U32 & String, Socket>, Unit, TCP.connect("127.0.0.1", port), knocked)

# Waits for the switch, then closes the gate and wakes the accept loop.
def stopper(switch: Chan(Unit), +gate: Chan(Drain.Tally), +port: U32) -> IO(Unit):
  do IO<Unit>:
    Drain.Switch.wait(switch)
    IO.print("air: stopping")
    Drain.close(gate)
    knock(port)

def stopped(+gate: Chan(Drain.Tally), drained: Bool) -> IO(Unit):
  match drained:
    case True{}:
      IO.print("air: stopped")
    case False{}:
      do IO<Unit>:
        n : U32 <- Drain.count(gate)
        IO.print("air: stopped with " ++ U32.show(n) ++ " in flight")

def serve_until.go(~app: Chan(Unit) -> Router.Handler(), +limits: Http.Limits, +timeouts: Timeouts, +switch: Chan(Unit), +port: U32, listener: Listener, gate: Chan(Drain.Tally)) -> IO(Unit):
  +g = gate
  do IO<Unit>:
    IO.spawn(Unit, stopper(switch, g, port))
    IO.print("air: listening on http://localhost:" ++ U32.show(port))
    loop(~app, limits, timeouts, switch, g, 4294967295n, Serving{listener})
    drained : Bool <- Drain.wait_for(g, Timeouts.drain(timeouts))
    stopped(g, drained)

# Serves `app` on `port` until `switch` is flipped, then stops accepting,
# waits up to the drain timeout for the requests in flight, and returns.
# `app` gets the switch, so a route can flip it. Connections idle between
# requests are not waited for; their computations end when the peer
# closes or the process exits.
def serve_until(~app: Chan(Unit) -> Router.Handler(), +limits: Http.Limits, +timeouts: Timeouts, +switch: Chan(Unit), +port: U32) -> IO(Unit):
  do IO<Unit>:
    listener : Listener <- IO.try(Listener, TCP.listen(port))
    gate : Chan(Drain.Tally) <- Drain.Gate.new()
    serve_until.go(~app, limits, timeouts, switch, port, listener, gate)

# Serves `app` on `port` under `limits` and the default timeouts until
# the process is killed.
def serve_with(~app: Router.Handler(), +limits: Http.Limits, +port: U32) -> IO(Unit):
  IO.bind(Chan(Unit), Unit, Drain.Switch.new(), switch => serve_until(~(sw => app), limits, Timeouts.default(), switch, port))

def serve(~app: Router.Handler(), +port: U32) -> IO(Unit):
  serve_with(~app, Http.Limits.default(), port)
