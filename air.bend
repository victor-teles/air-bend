import Base
import ./air/http.bend as Http
import ./air/router.bend as Router
import ./air/drain.bend as Drain
import ./air/server.bend as Server

# Air
# ===
#
# A small web framework for Bend. Import it as `Air`:
#
#   import ./air.bend as Air
#
#   def home(req: Air.Request()) -> IO(Air.Response()):
#     IO.pure(Air.Response(), Air.Response.text("hello"))
#
#   def routes() -> List<Air.Route()>:
#     [Air.Route.get("/", home)]
#
#   def app(req: Air.Request()) -> IO(Air.Response()):
#     Air.dispatch(routes(), req)
#
#   def main() -> IO(Unit):
#     Air.serve(~app, 8080)
#
# Handlers are affine closures, so `routes()` is rebuilt for every request:
# that is what lets each handler be called once per request.
#
# This file is the public surface. The work lives in `air/`:
#
#   air/text.bend    string helpers that are safe on request buffers
#   air/chunk.bend   the `Transfer-Encoding: chunked` decoder
#   air/http.bend    Limits, Method, Status, Request (parsing, framing), Response
#   air/router.bend  Route, Handler, dispatch
#   air/race.bend    deadlines: an effect raced against a watchdog
#   air/drain.bend   the stop switch and the tally of requests in flight
#   air/server.bend  the HTTP/1.1 connection loop over TCP
#
# Bend imports are not transitive, so each public name is re-exported
# here. An app that needs more than this surface (matching on a
# `Method`, say) imports the module it wants directly.

# Types
# -----

def Request() -> Data:
  Http.Request

def Response() -> Data:
  Http.Response

def Method() -> Data:
  Http.Method

def Limits() -> Data:
  Http.Limits

def Timeouts() -> Data:
  Server.Timeouts

def Switch() -> Data:
  Drain.Switch()

def Handler() -> Type:
  Router.Handler()

# A handler that also gets the server's stop switch. `serve_until` takes
# one of these, so a route can stop the server.
def Stoppable() -> Type:
  Switch() -> Handler()

def Route() -> Type:
  Router.Route

def Slash() -> Data:
  Router.Slash

# Limits
# ------

# Byte caps on a request: the head (request line plus headers), the
# number of header lines, the URL, and the body. Past them the server
# answers 431, 431, 414 or 413 and closes the connection.
def Limits.new(head: U32, headers: U32, url: U32, body: U32) -> Limits():
  Http.Limits{head, headers, url, body}

# 16 KiB head, 100 headers, 8 KiB URL, 1 MiB body.
def Limits.default() -> Limits():
  Http.Limits.default()

# Timeouts
# --------

# Milliseconds, 0 for no limit: `idle` bounds the wait for a request on
# an open connection, `head` the request line and headers from their
# first byte, `body` the body, `app` the handler, `send` the write of the
# response, and `drain` how long a stopping server waits for the requests
# in flight. A phase that runs out of time closes the connection; the
# app's timeout answers 503 first.
def Timeouts.new(idle: U32, head: U32, body: U32, app: U32, send: U32, drain: U32) -> Timeouts():
  Server.Timeouts{idle, head, body, app, send, drain}

# 15 s idle, 10 s head, 30 s body, 30 s app, 30 s send, 10 s drain.
def Timeouts.default() -> Timeouts():
  Server.Timeouts.default()

# Switch
# ------

# The stop switch: flip it and a `serve_until` server stops accepting,
# drains, and returns. Flipping it twice is harmless.
def Switch.new() -> IO(Switch()):
  Drain.Switch.new()

def Switch.flip(switch: Switch()) -> IO(Unit):
  Drain.Switch.flip(switch)

# Method
# ------

def Method.show(m: Method()) -> String:
  Http.Method.show(m)

def Method.is_eq(a: Method(), b: Method()) -> Bool:
  Http.Method.is_eq(a, b)

# Request
# -------

def Request.method(r: Request()) -> Method():
  Http.Request.method(r)

# "HTTP/1.1" or "HTTP/1.0", as the request line said.
def Request.version(r: Request()) -> String:
  Http.Request.version(r)

# The path in its normal form: percent-decoded, `.` and `..` resolved,
# repeated slashes collapsed, a trailing slash kept. `*` for `OPTIONS *`.
def Request.path(r: Request()) -> String:
  Http.Request.path(r)

# The request-target as received: raw path and query, undecoded.
def Request.target(r: Request()) -> String:
  Http.Request.target(r)

def Request.body(r: Request()) -> String:
  Http.Request.body(r)

# A header by name, case-insensitive; "" when absent. A repeated header
# reads as its values joined with ", ".
def Request.header(r: Request(), name: String) -> String:
  Http.Request.header(r, name)

# A query-string value, percent-decoded with '+' as space; "" when absent.
def Request.query(r: Request(), key: String) -> String:
  Http.Request.query(r, key)

# A path parameter bound by the route, like `:id`; "" when absent.
def Request.param(r: Request(), key: String) -> String:
  Http.Request.param(r, key)

# Response
# --------

def Response.new(status: U32, body: String) -> Response():
  Http.Response.new(status, body)

def Response.status(r: Response()) -> U32:
  Http.Response.status(r)

def Response.body(r: Response()) -> String:
  Http.Response.body(r)

def Response.header(r: Response(), name: String) -> String:
  Http.Response.header(r, name)

def Response.with_status(r: Response(), status: U32) -> Response():
  Http.Response.with_status(r, status)

def Response.with_header(r: Response(), name: String, value: String) -> Response():
  Http.Response.with_header(r, name, value)

def Response.empty(status: U32) -> Response():
  Http.Response.empty(status)

def Response.text(body: String) -> Response():
  Http.Response.text(body)

def Response.html(body: String) -> Response():
  Http.Response.html(body)

def Response.json(body: String) -> Response():
  Http.Response.json(body)

def Response.redirect(url: String) -> Response():
  Http.Response.redirect(url)

def Response.not_found() -> Response():
  Http.Response.not_found()

# A 405 with its `Allow` header, like "GET, HEAD, OPTIONS".
def Response.method_not_allowed(allow: String) -> Response():
  Http.Response.method_not_allowed(allow)

# A 204 with an `Allow` header, what OPTIONS gets by default.
def Response.options(allow: String) -> Response():
  Http.Response.options(allow)

def Response.bad_request() -> Response():
  Http.Response.bad_request()

# Routing
# -------

# A route: `:name` segments bind params, a last `*name` segment binds
# the rest of the path (possibly ""). Handlers are `Request -> IO(Response)`.
def Route.get(path: String, handler: Handler()) -> Route():
  Router.get(path, handler)

def Route.post(path: String, handler: Handler()) -> Route():
  Router.post(path, handler)

def Route.put(path: String, handler: Handler()) -> Route():
  Router.put(path, handler)

def Route.delete(path: String, handler: Handler()) -> Route():
  Router.delete(path, handler)

def Route.patch(path: String, handler: Handler()) -> Route():
  Router.patch(path, handler)

# Optional: without a HEAD route, HEAD runs the GET route and the server
# drops the body.
def Route.head(path: String, handler: Handler()) -> Route():
  Router.head(path, handler)

# Optional: without an OPTIONS route, OPTIONS answers 204 with `Allow`.
def Route.options(path: String, handler: Handler()) -> Route():
  Router.options(path, handler)

# Prefixes every route: `Route.mount("/api", api())` turns "/users/:id"
# into "/api/users/:id".
def Route.mount(prefix: String, routes: List<Route()>) -> List<Route()>:
  Router.mount(prefix, routes)

# Joins route groups in order: `Route.all([pages(), Route.mount("/api", api())])`.
def Route.all(groups: List<List<Route()>>) -> List<Route()>:
  Router.all(groups)

# Checks a route list once, at startup: a duplicate (same method, same
# shape once params are anonymized) or a wildcard that is not last is
# printed and ends the process with code 1. Routes are matched in order,
# so a duplicate would shadow the later route silently without this.
# Call it in `main` on its own `routes()` before `serve`.
def Route.check(routes: List<Route()>) -> IO(Unit):
  Router.check(routes)

# What a trailing slash means to `dispatch_with`. `ignore`, the default,
# treats "/a/" and "/a" as the same path. `strict` matches a route only
# when it and the request agree on the slash. `redirect` answers 308 to
# the path without the slash, query kept; "/" is never redirected.
def Slash.ignore() -> Slash():
  Router.Ignore{}

def Slash.strict() -> Slash():
  Router.Strict{}

def Slash.redirect() -> Slash():
  Router.Redirect{}

# Runs the first route whose method and path match the request under the
# slash policy. HEAD runs the GET route when no HEAD route matches. A path
# that matches only under other methods answers 405 with `Allow`, or 204
# with `Allow` to OPTIONS; no match answers 404. `OPTIONS *` lists every
# method the app serves.
def dispatch_with(+policy: Slash(), routes: List<Route()>, +req: Request()) -> IO(Response()):
  Router.dispatch_with(policy, routes, req)

# `dispatch_with` under `Slash.ignore()`.
def dispatch(routes: List<Route()>, +req: Request()) -> IO(Response()):
  Router.dispatch(routes, req)

# Server
# ------

# Serves `app` on `port` under `limits` and the default timeouts until
# the process is killed. Each connection runs as its own computation, so
# a slow client never blocks the others.
def serve_with(~app: Handler(), +limits: Limits(), +port: U32) -> IO(Unit):
  Server.serve_with(~app, limits, port)

def serve(~app: Handler(), +port: U32) -> IO(Unit):
  Server.serve(~app, port)

# Serves until `switch` is flipped: then no new connection is accepted,
# the requests in flight get up to the drain timeout to finish, and this
# returns. The app gets the switch, so a route can flip it. Connections
# idle between requests are not waited for; end the process with `exit`
# and they close with it.
def serve_until(~app: Stoppable(), +limits: Limits(), +timeouts: Timeouts(), +switch: Switch(), +port: U32) -> IO(Unit):
  Server.serve_until(~app, limits, timeouts, switch, port)

# Ends the process with `code`, whatever computations are still parked.
def exit(code: U32) -> IO(Unit):
  IO.die(Unit, code, "")
