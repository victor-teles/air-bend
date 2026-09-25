import Base
import ./text.bend as Text
import ./json.bend as Json
import ./random.bend as Random
import ./clock.bend as Clock
import ./http.bend as Http
import ./router.bend as Router

# Trace
# =====
#
# W3C trace context, so an Air service is a well-behaved hop in a
# distributed trace. `trace` is the middleware: it continues the trace
# a valid `traceparent` header names, or starts one, gives the handlers
# the ids as locals, and hands one `Span` per sampled request to an
# exporter the app picks. `print` writes a span as a JSON line (a
# collector can tail it); `drop` only propagates the ids.
#
# The locals: `trace_id`, `span_id`, `parent_id` ("" for a root),
# `trace_flags`, `traceparent` (the value to send downstream) and
# `tracestate` (the client's, untouched).

# Parsing
# -------

# What a valid `traceparent` carries from the caller.
type Parent is Data:
  Parent{trace_id: String, parent_id: String, flags: String}

def lower_hex(+c: Char) -> Bool:
  Bool.or(Char.is_digit(c), Bool.and(U32.is_ge(Char.to_u32(c), 97), U32.is_le(Char.to_u32(c), 102)))

def hex_run(s: String, +n: U32, ok: Bool) -> Bool:
  match s ok:
    case _ False{}:
      False{}
    case SNil{} True{}:
      U32.is_eq(n, 0)
    case SCon{h, t} True{}:
      hex_run(t, U32.sub(n, 1), Bool.and(U32.is_gt(n, 0), lower_hex(h)))

# Exactly `n` lowercase hex digits.
def is_hex(s: String, +n: U32) -> Bool:
  hex_run(s, n, True{})

def all_zero(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{h, t}:
      Bool.and(Char.is_eq(h, '0'), all_zero(t))

# A trace or span id: the length in lowercase hex, not all zeros.
def id_ok(+s: String, +n: U32) -> Bool:
  Bool.and(is_hex(s, n), Bool.not(all_zero(s)))

# `ff` is never valid. `00` has exactly four fields; a later version may
# add fields after them, which are ignored.
def version_ok(+v: String, last: Bool) -> Bool:
  Bool.and(is_hex(v, 2), Bool.and(Bool.not(String.eq(v, "ff")), Bool.or(last, Bool.not(String.eq(v, "00")))))

def parse.fin(trace: String, parent: String, flags: String, ok: Bool) -> Maybe<&2, Parent>:
  match ok:
    case True{}:
      Some{Parent{trace, parent, flags}}
    case False{}:
      None{}

def parse.fields(fields: List<&2, String>) -> Maybe<&2, Parent>:
  match fields:
    case Con{+v, Con{+trace, Con{+parent, Con{+flags, rest}}}}:
      parse.fin(trace, parent, flags,
        Bool.and(version_ok(v, List.is_empty(&2, String, rest)),
          Bool.and(id_ok(trace, 32), Bool.and(id_ok(parent, 16), is_hex(flags, 2)))))
    case _:
      None{}

# A `traceparent` value: `00-<32 hex>-<16 hex>-<2 hex>`, lowercase, ids
# not all zeros. Anything else is None, and the request starts a trace.
def parse(+s: String) -> Maybe<&2, Parent>:
  parse.fields(Text.split_all(s, '-'))

# The value to send downstream.
def render(+trace_id: String, +span_id: String, +flags: String) -> String:
  "00-" ++ trace_id ++ "-" ++ span_id ++ "-" ++ flags

# Sampling
# --------

def flags_of(sampled: Bool) -> String:
  match sampled:
    case True{}:
      "01"
    case False{}:
      "00"

def hex_or_zero(r: Maybe<&2, U32>) -> U32:
  match r:
    case Some{n}:
      n
    case None{}:
      0

# Whether the flags' sampled bit (the low bit) is set.
def is_sampled(+flags: String) -> Bool:
  U32.is_eq(U32.and(hex_or_zero(Text.hex(flags)), 1), 1)

# Whether a new root is kept when one in `every` is: decided by the
# trace id's last eight hex digits, so every service that samples this
# way agrees on a trace. `every` 0 keeps none, 1 keeps all.
def keeps(+every: U32, +trace_id: String) -> Bool:
  Bool.and(U32.is_gt(every, 0),
    U32.is_eq(U32.mod(hex_or_zero(Text.hex(String.drop(trace_id, 24n))), U32.max(every, 1)), 0))

# Spans
# -----

# One request as a span. `start_ms` is Unix epoch milliseconds as
# decimal text (it does not fit a U32); `parent_id` is "" for a root;
# `route` is the pattern that answered, "" for none.
type Span is Data:
  Span{trace_id: String, span_id: String, parent_id: String, name: String, start_ms: String, duration_ms: U32, status: U32, method: String, route: String, path: String}

def name_of(+method: String, route: String) -> String:
  match route:
    case SNil{}:
      method
    case SCon{h, t}:
      method ++ " " ++ SCon{h, t}

# The span's name: "GET /users/:id", or the method alone when no route
# answered, which keeps names few as OpenTelemetry asks.
def span_name(+method: String, +route: String) -> String:
  name_of(method, route)

# One JSON line, attribute names from OpenTelemetry's HTTP conventions.
def json(s: Span) -> String:
  match s:
    case Span{trace_id, span_id, parent_id, name, start_ms, duration_ms, status, method, route, path}:
      Json.render(Json.obj([
        Json.field("trace_id", Json.of_str(trace_id)),
        Json.field("span_id", Json.of_str(span_id)),
        Json.field("parent_span_id", Json.of_str(parent_id)),
        Json.field("name", Json.of_str(name)),
        Json.field("start_time_unix_ms", Json.num(start_ms)),
        Json.field("duration_ms", Json.of_u32(duration_ms)),
        Json.field("http.request.method", Json.of_str(method)),
        Json.field("http.route", Json.of_str(route)),
        Json.field("url.path", Json.of_str(path)),
        Json.field("http.response.status_code", Json.of_u32(status))
      ]))

# The shipped exporters: a JSON line on stdout, or nothing.
def print(s: Span) -> IO(Unit):
  IO.print(json(s))

def drop(s: Span) -> IO(Unit):
  IO.pure(Unit, Unit{})

# The middleware
# --------------

# The ids of this request's span, decided before the handler runs.
type Ids is Data:
  Ids{trace_id: String, span_id: String, parent_id: String, flags: String}

def continued(p: Parent, span_id: String) -> IO(Ids):
  match p:
    case Parent{trace_id, parent_id, flags}:
      IO.pure(Ids, Ids{trace_id, span_id, parent_id, flags})

def root.fin(+every: U32, trace_id: String, span_id: String) -> IO(Ids):
  +trace_id = trace_id
  IO.pure(Ids, Ids{trace_id, span_id, SNil{}, flags_of(keeps(every, trace_id))})

# A new trace: four draws for the trace id, two for the span id.
def root(+every: U32) -> IO(Ids):
  do IO<Ids>:
    trace_id : String <- Random.token()
    span_id : String <- Random.span_id()
    root.fin(every, trace_id, span_id)

# A continued trace keeps the caller's id and flags: two draws.
def ids(+every: U32, parent: Maybe<&2, Parent>) -> IO(Ids):
  match parent:
    case Some{p}:
      IO.bind(String, Ids, Random.span_id(), sid => continued(p, sid))
    case None{}:
      root(every)

def with_ids(req: Http.Request, i: Ids) -> Http.Request:
  match i:
    case Ids{+trace_id, +span_id, parent_id, +flags}:
      Http.Request.with_local(Http.Request.with_local(Http.Request.with_local(Http.Request.with_local(Http.Request.with_local(
        req,
        "trace_id", trace_id),
        "span_id", span_id),
        "parent_id", parent_id),
        "trace_flags", flags),
        "traceparent", render(trace_id, span_id, flags))

def with_state(+req: Http.Request) -> Http.Request:
  Http.Request.with_local(req, "tracestate", Http.Request.header(req, "tracestate"))

def export_span(exporter: Span -> IO(Unit), s: Span, sampled: Bool) -> IO(Unit):
  match sampled:
    case True{}:
      exporter(s)
    case False{}:
      IO.pure(Unit, Unit{})

def span_of(+req: Http.Request, +start: String, +ms: U32, +res: Http.Response) -> Span:
  +method = Http.Method.show(Http.Request.method(req))
  +route = Http.Response.route(res)
  Span{
    Http.Request.local(req, "trace_id"),
    Http.Request.local(req, "span_id"),
    Http.Request.local(req, "parent_id"),
    span_name(method, route),
    start, ms, Http.Response.status(res), method, route, Http.Request.path(req)}

def finish(exporter: Span -> IO(Unit), +req: Http.Request, +start: String, +before: Nat, res: Http.Response, after: Nat) -> IO(Http.Response):
  +res = res
  do IO<Http.Response>:
    export_span(exporter, span_of(req, start, U32.from_nat(Nat.sub(after, before)), res), is_sampled(Http.Request.local(req, "trace_flags")))
    return res

def run(exporter: Span -> IO(Unit), next: Router.Handler(), req: Http.Request) -> IO(Http.Response):
  +req = req
  do IO<Http.Response>:
    start : String <- Clock.wall_ms()
    before : Nat <- IO.now()
    res : Http.Response <- next(req)
    after : Nat <- IO.now()
    finish(exporter, req, start, before, res, after)

def begin(exporter: Span -> IO(Unit), next: Router.Handler(), +req: Http.Request, i: Ids) -> IO(Http.Response):
  run(exporter, next, with_state(with_ids(req, i)))

# Keeps one new root in `every` (see `keeps`); a continued trace follows
# its caller's sampled flag. Only sampled spans reach the exporter, but
# every request gets ids.
def trace_sampled(+every: U32, exporter: Span -> IO(Unit), next: Router.Handler(), req: Http.Request) -> IO(Http.Response):
  +req = req
  IO.bind(Ids, Http.Response, ids(every, parse(Http.Request.header(req, "traceparent"))), i => begin(exporter, next, req, i))

# Every new root sampled.
def trace(exporter: Span -> IO(Unit), next: Router.Handler(), req: Http.Request) -> IO(Http.Response):
  trace_sampled(1, exporter, next, req)
