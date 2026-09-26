import Base
import ./text.bend as Text
import ./random.bend as Random
import ./clock.bend as Clock
import ./json.bend as Json
import ./http.bend as Http
import ./router.bend as Router

# Log
# ===
#
# Two middleware. `request_id` gives every request an id: the client's
# `X-Request-Id` when it is safe to print, else a fresh one, left in the
# `request_id` local and on the response. `log` prints one JSON line per
# request with the time, the id, the method, the path, the status and
# the milliseconds it took. Put `log` inside `request_id` so the line
# has the id.

# Ids
# ---

def pick_id.go(+given: String, safe: Bool) -> IO(String):
  match safe:
    case True{}:
      IO.pure(String, given)
    case False{}:
      Random.fresh_id()

# The client's id when safe, else a fresh one.
def pick_id(+given: String) -> IO(String):
  pick_id.go(given, Random.safe_id(given))

def stamp(+id: String, res: Http.Response) -> IO(Http.Response):
  IO.pure(Http.Response, Http.Response.with_header(res, "x-request-id", id))

def request_id.go(next: Router.Handler(), req: Http.Request, id: String) -> IO(Http.Response):
  +id = id
  IO.bind(Http.Response, Http.Response, next(Http.Request.with_local(req, "request_id", id)), stamp(id))

# The middleware: the id goes to the handlers as the `request_id` local
# and to the client as `x-request-id`.
def request_id(next: Router.Handler(), req: Http.Request) -> IO(Http.Response):
  +req = req
  IO.bind(String, Http.Response, pick_id(Http.Request.header(req, "x-request-id")), request_id.go(next, req))

# Lines
# -----

# The `trace_id` field, only when tracing gave the request one.
def trace_field(trace_id: String, rest: List<&2, Json.Field()>) -> List<&2, Json.Field()>:
  match trace_id:
    case SNil{}:
      rest
    case SCon{h, t}:
      Con{Json.field("trace_id", Json.of_str(SCon{h, t})), rest}

# One JSON object: `{"ts":…,"id":"…","method":"GET","path":"/x","status":200,"ms":3}`,
# with `"trace_id"` after the id when `Air.trace` runs outside `log`.
# `ts` is the start in Unix epoch milliseconds, from the wall clock
# (`Clock.wall_ms`), as decimal text. Strings are escaped by the
# renderer, so a path cannot break the line.
def line(ts: String, id: String, trace_id: String, method: String, path: String, status: U32, ms: Nat) -> String:
  Json.render(Json.obj(Con{
    Json.field("ts", Json.num(ts)),
    Con{Json.field("id", Json.of_str(id)),
    trace_field(trace_id, [
      Json.field("method", Json.of_str(method)),
      Json.field("path", Json.of_str(path)),
      Json.field("status", Json.of_u32(status)),
      Json.field("ms", Json.num(Nat.show(ms)))
    ])}}))

def log.fin(ts: String, +req: Http.Request, +before: Nat, res: Http.Response, after: Nat) -> IO(Http.Response):
  +res = res
  do IO<Http.Response>:
    IO.print(line(ts, Http.Request.local(req, "request_id"), Http.Request.local(req, "trace_id"),
      Http.Method.show(Http.Request.method(req)), Http.Request.path(req), Http.Response.status(res), Nat.sub(after, before)))
    return res

# The middleware: runs `next` and prints the line. The id is the
# `request_id` local, "" without `request_id` outside this; the trace id
# is the `trace_id` local.
def log(next: Router.Handler(), req: Http.Request) -> IO(Http.Response):
  +req = req
  do IO<Http.Response>:
    ts : String <- Clock.wall_ms()
    before : Nat <- IO.now()
    res : Http.Response <- next(req)
    after : Nat <- IO.now()
    log.fin(ts, req, before, res, after)
