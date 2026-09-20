import Base
import ./air/http.bend as Http
import ./air/json.bend as Json
import ./air/form.bend as Form
import ./air/disk.bend as Disk
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
#   air/json.bend    a JSON value, parser and renderer
#   air/http.bend    Limits, Method, Status, Request (parsing, framing), Response
#   air/form.bend    multipart/form-data parts
#   air/disk.bend    files as responses
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

def Cookie() -> Data:
  Http.Cookie

# A JSON value. To match on its constructors, import `air/json.bend`
# directly: imports are not transitive.
def Json() -> Data:
  Json.Value

# A key and its value, for `Json.obj`.
def Json.Field() -> Data:
  Json.Field()

# One part of a multipart/form-data body.
def Part() -> Data:
  Form.Part

# Whether to believe forwarding headers; see `Trust.proxy`.
def Trust() -> Data:
  Http.Trust

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

# The content type's media type, lowercased, without parameters.
def Request.media_type(r: Request()) -> String:
  Http.Request.media_type(r)

# The body as JSON when the content type is `application/json` (or
# `+json`) and the body parses; None otherwise.
def Request.json(r: Request()) -> Maybe<&2, Json()>:
  Http.Request.json(r)

# The first cookie named `name`; "" when absent. Values are as sent.
def Request.cookie(r: Request(), name: String) -> String:
  Http.Request.cookie(r, name)

# Every cookie sent, as (name, value) pairs in order.
def Request.cookies(r: Request()) -> List<&2, Sigma<&2, &2, String, _ => String>>:
  Http.Request.cookies(r)

# The offer the client's `Accept` header prefers, by q-value and
# specificity, the earliest offer on ties; None when it accepts none of
# them. An absent header takes the first offer.
def Request.accepts(r: Request(), offers: List<&2, String>) -> Maybe<&2, String>:
  Http.Request.accepts(r, offers)

def Request.accepts_encoding(r: Request(), offers: List<&2, String>) -> Maybe<&2, String>:
  Http.Request.accepts_encoding(r, offers)

# Like `accepts`, with the language prefix rule: `en` accepts `en-us`.
def Request.accepts_language(r: Request(), offers: List<&2, String>) -> Maybe<&2, String>:
  Http.Request.accepts_language(r, offers)

# The client's address as a trusted proxy reports it: the rightmost
# `X-Forwarded-For` entry, else the last `Forwarded` `for=` node. Bend's
# `TCP.accept` gives no peer address, so without a trusted proxy this is
# None.
def Request.client_ip(r: Request(), trust: Trust()) -> Maybe<&2, String>:
  Http.Request.client_ip(r, trust)

# The host asked for: `X-Forwarded-Host` or `Forwarded` `host=` under a
# trusted proxy, else the `Host` header; "" when absent.
def Request.host(r: Request(), trust: Trust()) -> String:
  Http.Request.host(r, trust)

# "https" when a trusted proxy says so, else "http".
def Request.scheme(r: Request(), trust: Trust()) -> String:
  Http.Request.scheme(r, trust)

# Every value of a repeated query key, in order: `?tag=a&tag=b` gives
# ["a", "b"]. `query` keeps the last one. Keys are flat: `a[b]` is a key
# named `a[b]`.
def Request.query_all(r: Request(), key: String) -> List<&2, String>:
  Http.Request.query_all(r, key)

# A field of an `application/x-www-form-urlencoded` body; "" when the
# body is not one or the key is absent.
def Request.form(r: Request(), key: String) -> String:
  Http.Request.form(r, key)

def Request.form_all(r: Request(), key: String) -> List<&2, String>:
  Http.Request.form_all(r, key)

# The parts of a `multipart/form-data` body, in order; None when the
# body is not one or is malformed. Parts are text: the runtime reads a
# socket as UTF-8, so a binary upload is not preserved byte for byte.
def Request.parts(r: Request()) -> Maybe<&2, List<&2, Part()>>:
  Form.parts(r)

# Trust
# -----

# Ignore every forwarding header (the default stance).
def Trust.none() -> Trust():
  Http.NoProxy{}

# Believe `X-Forwarded-For`, `X-Forwarded-Host`, `X-Forwarded-Proto` and
# `Forwarded`, as set by one proxy in front of Air. Only turn this on
# when the proxy is the only way to reach the server.
def Trust.proxy() -> Trust():
  Http.Proxy{}

# Part
# ----

def Part.name(p: Part()) -> String:
  Form.Part.name(p)

# The uploaded file's name; None for a plain field.
def Part.filename(p: Part()) -> Maybe<&2, String>:
  Form.Part.filename(p)

# The part's content type, "text/plain" when it had none.
def Part.mime(p: Part()) -> String:
  Form.Part.mime(p)

def Part.body(p: Part()) -> String:
  Form.Part.body(p)

# The first plain field named `name` among the parts; "" when absent.
def Part.field(parts: List<&2, Part()>, name: String) -> String:
  Form.field(parts, name)

# The first file part named `name`.
def Part.file(parts: List<&2, Part()>, name: String) -> Maybe<&2, Part()>:
  Form.file(parts, name)

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

# A 200 with a JSON value rendered as its body.
def Response.of_json(v: Json()) -> Response():
  Http.Response.of_json(v)

# A 200 whose body is whatever a producer sends on `chan`, written to
# the client as it arrives (chunked encoding), until the producer
# closes the channel:
#
#   def ticks.start(chan: Chan(String)) -> IO(Air.Response()):
#     +chan = chan
#     do IO<Air.Response()>:
#       IO.spawn(Unit, tick(5n, chan, True{}))
#       return Air.Response.sse(chan)
#
#   def ticks(req: Air.Request()) -> IO(Air.Response()):
#     IO.bind(Chan(String), Air.Response(), Air.Stream.new(), ticks.start)
#
# Each piece has the send timeout to arrive and be written; a producer
# silent for longer ends the connection. When the client goes away the
# server closes the channel, so the producer's next `Chan.send` answers
# False: stop then. A HEAD request gets the head only and the channel
# is closed at once. An HTTP/1.0 client gets the pieces unframed and
# the connection closes after.
def Response.stream(chan: Chan(String)) -> Response():
  Http.Response.stream(chan)

# A stream typed `text/event-stream`; send `Air.Sse.event` or
# `Air.Sse.data` on it.
def Response.sse(chan: Chan(String)) -> Response():
  Http.Response.sse(chan)

# Stream
# ------

# A channel for `Response.stream`: room for eight pieces, so a producer
# ahead of a slow client waits rather than piling up memory.
def Stream.new() -> IO(Chan(String)):
  Chan.new(String, 8)

# Sse
# ---

# An SSE event: "event: name", one "data:" line per line of `data`,
# and the blank line that ends it.
def Sse.event(name: String, data: String) -> String:
  Http.Sse.event(name, data)

# An unnamed SSE message: the data lines and the blank line.
def Sse.data(data: String) -> String:
  Http.Sse.data(data)

# The file at `path` with `mime`: a 200 tagged with an ETag, a 304 when
# the request's `If-None-Match` has that tag, a 206 for a `Range`, or a
# 404 when the file cannot be read. Files are read as UTF-8 text, so
# this is for HTML, CSS, JavaScript, SVG and the like, not images. The
# path is yours to choose: nothing here guards against `..`.
def Response.file(req: Request(), path: String, mime: String) -> IO(Response()):
  Disk.respond(req, path, mime)

# The same three steps on any response: tag the body with its ETag and
# offer byte ranges, answer 304 to a matching `If-None-Match`, and
# answer a `Range` with a 206 or 416. Only GET and HEAD 200s qualify.
def Response.with_etag(r: Response()) -> Response():
  Http.Response.with_etag(r)

def Response.conditional(req: Request(), r: Response()) -> Response():
  Http.Response.conditional(req, r)

def Response.ranged(req: Request(), r: Response()) -> Response():
  Http.Response.ranged(req, r)

# The whole file as text, or None when it cannot be opened or read.
def Disk.read(path: String) -> IO(Maybe<&2, String>):
  Disk.read(path)

# A 200 whose content type is inferred from the body's first character:
# `<` is HTML, `{` or `[` is JSON, anything else plain text. `with_type`
# after it overrides the guess.
def Response.send(body: String) -> Response():
  Http.Response.send(body)

# Sets the content type; text types, JSON, JavaScript and SVG get
# `; charset=utf-8` unless the mime already has a parameter.
def Response.with_type(r: Response(), mime: String) -> Response():
  Http.Response.with_type(r, mime)

# A 302.
def Response.redirect(url: String) -> Response():
  Http.Response.redirect(url)

def Response.redirect_with(status: U32, url: String) -> Response():
  Http.Response.redirect_with(status, url)

# 301, 303, 307 and 308.
def Response.moved(url: String) -> Response():
  Http.Response.moved(url)

def Response.see_other(url: String) -> Response():
  Http.Response.see_other(url)

def Response.temporary_redirect(url: String) -> Response():
  Http.Response.temporary_redirect(url)

def Response.permanent_redirect(url: String) -> Response():
  Http.Response.permanent_redirect(url)

# Adds a `Set-Cookie` line; several cookies are several lines, in order.
def Response.with_cookie(r: Response(), c: Cookie()) -> Response():
  Http.Response.with_cookie(r, c)

# Tells the browser to drop a cookie set with the default path.
def Response.expire_cookie(r: Response(), name: String) -> Response():
  Http.Response.expire_cookie(r, name)

# Cookie
# ------

# A cookie to set, with safe defaults: Path=/, HttpOnly, SameSite=Lax,
# session-long, not Secure. Names and values are emitted as given.
def Cookie.new(name: String, value: String) -> Cookie():
  Http.Cookie.new(name, value)

def Cookie.with_path(c: Cookie(), path: String) -> Cookie():
  Http.Cookie.with_path(c, path)

def Cookie.with_domain(c: Cookie(), domain: String) -> Cookie():
  Http.Cookie.with_domain(c, domain)

# Seconds; 0 for a session cookie.
def Cookie.with_max_age(c: Cookie(), seconds: U32) -> Cookie():
  Http.Cookie.with_max_age(c, seconds)

def Cookie.secure(c: Cookie(), on: Bool) -> Cookie():
  Http.Cookie.secure(c, on)

def Cookie.http_only(c: Cookie(), on: Bool) -> Cookie():
  Http.Cookie.http_only(c, on)

# "Lax", "Strict", "None" or "". `None` is rendered with `Secure`, as
# browsers require.
def Cookie.same_site(c: Cookie(), mode: String) -> Cookie():
  Http.Cookie.same_site(c, mode)

def Cookie.render(c: Cookie()) -> String:
  Http.Cookie.render(c)

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

# JSON
# ----
#
# Numbers keep their text as written; `u32` reads a non-negative
# integer out of one. Objects keep field order. Every accessor is total.

def Json.parse(text: String) -> Maybe<&2, Json()>:
  Json.parse(text)

def Json.render(v: Json()) -> String:
  Json.render(v)

def Json.null() -> Json():
  Json.null()

def Json.of_bool(b: Bool) -> Json():
  Json.of_bool(b)

def Json.of_u32(n: U32) -> Json():
  Json.of_u32(n)

# A number as written, unchecked: "-1.5e3".
def Json.num(text: String) -> Json():
  Json.num(text)

def Json.of_str(s: String) -> Json():
  Json.of_str(s)

def Json.arr(items: List<&2, Json()>) -> Json():
  Json.arr(items)

def Json.obj(fields: List<&2, Json.Field()>) -> Json():
  Json.obj(fields)

def Json.field(key: String, v: Json()) -> Json.Field():
  Json.field(key, v)

# The first field named `key` of an object.
def Json.get(v: Json(), key: String) -> Maybe<&2, Json()>:
  Json.get(v, key)

# The `i`th item of an array.
def Json.at(v: Json(), i: Nat) -> Maybe<&2, Json()>:
  Json.at(v, i)

def Json.str(v: Json()) -> Maybe<&2, String>:
  Json.str(v)

def Json.u32(v: Json()) -> Maybe<&2, U32>:
  Json.u32(v)

def Json.boolean(v: Json()) -> Maybe<&2, Bool>:
  Json.boolean(v)

def Json.is_null(v: Json()) -> Bool:
  Json.is_null(v)

# The items of an array, or [] for anything else.
def Json.items(v: Json()) -> List<&2, Json()>:
  Json.items(v)

# The fields of an object, or [] for anything else.
def Json.fields(v: Json()) -> List<&2, Json.Field()>:
  Json.fields(v)

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
