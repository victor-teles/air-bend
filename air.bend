import Base
import ./air/lib/http.bend as Http
import ./air/lib/json.bend as Json
import ./air/lib/form.bend as Form
import ./air/lib/disk.bend as Disk
import ./air/lib/static.bend as Static
import ./air/lib/errors.bend as Errors
import ./air/lib/log.bend as Log
import ./air/lib/store.bend as Store
import ./air/lib/rate.bend as Rate
import ./air/lib/session.bend as Session
import ./air/lib/schema.bend as Schema
import ./air/lib/view.bend as View
import ./air/lib/cors.bend as Cors
import ./air/lib/shield.bend as Shield
import ./air/lib/router.bend as Router
import ./air/lib/drain.bend as Drain
import ./air/lib/server.bend as Server
import ./air/lib/test.bend as Test
import ./air/lib/config.bend as Config
import ./air/lib/hooks.bend as Hooks
import ./air/lib/health.bend as Health
import ./air/lib/openapi.bend as OpenApi
import ./air/lib/metrics.bend as Metric
import ./air/lib/clock.bend as Clock
import ./air/lib/trace.bend as Trace

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
# A middleware takes the next handler and gives one back; it runs code
# before and after `next`, or answers without calling it:
#
#   def timing(next: Air.Handler(), req: Air.Request()) -> IO(Air.Response()):
#     ...runs next(req), logs the elapsed time, returns its response...
#
#   def base(req: Air.Request()) -> IO(Air.Response()):
#     Air.dispatch(routes(), req)
#
#   def app(req: Air.Request()) -> IO(Air.Response()):
#     Air.use([timing], base)(req)
#
# This file is the public surface. The work lives in `air/lib/`:
#
#   text.bend     string helpers that are safe on request buffers
#   chunk.bend    the `Transfer-Encoding: chunked` decoder
#   json.bend     a JSON value, parser and renderer
#   http.bend     Limits, Method, Status, Request (parsing, framing), Response
#   form.bend     multipart/form-data parts
#   disk.bend     files as responses
#   static.bend   a directory as a handler
#   errors.bend   typed errors, their renderers, and effect capture
#   log.bend      request ids and one log line per request
#   random.bend   ids and tokens from the host's entropy
#   store.bend    the shared store every request carries
#   rate.bend     a fixed-window rate limit over the store
#   session.bend  cookie-keyed sessions in the store
#   schema.bend   schemas and the middleware that validates with them
#   view.bend     HTML templates over a JSON context
#   cors.bend     cross-origin resource sharing, preflight included
#   shield.bend   defensive response headers
#   router.bend   Route, Handler, dispatch
#   race.bend     deadlines: an effect raced against a watchdog
#   drain.bend    the stop switch and the tally of requests in flight
#   server.bend   the HTTP/1.1 connection loop over TCP
#   test.bend     running an app on a request without a socket
#   config.bend   settings from the environment and a `.env` file
#   hooks.bend    lifecycle hooks as middleware with a name
#   health.bend   /healthz and /readyz, and readiness checks
#   openapi.bend  an OpenAPI 3.1 document from the routes
#
# One level down so that a module's C name (`air/lib/json.parse`) can
# never be the facade's (`air.Json.parse`): the backend would refuse the
# pair as "two names mangle to" the same symbol.
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

# The shared store: namespaces of string maps behind a lock; see `Store`.
def Store() -> Data:
  Store.Store()

# How sessions are kept; see `session`.
def Session() -> Data:
  Session.Config

# A description of a JSON value; see `validate_json`.
def Schema() -> Data:
  Schema.Schema

# A field of an object schema.
def Schema.Prop() -> Data:
  Schema.Prop()

def Cookie() -> Data:
  Http.Cookie

# An HTTP error as a value; see `fail` and `on_error`.
def Error() -> Data:
  Http.Error

# `Env.dev()` or `Env.prod()`: whether error renderers show details.
def Env() -> Data:
  Http.Env

# What `on_error` takes: a request and an error to the response the
# client sees. `Error.plain(env)` and `Error.json(env)` are two.
def Render() -> Type:
  Errors.Render()

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

# A CORS policy; see `cors`.
def Cors() -> Data:
  Cors.Cors

# A list of defensive headers; see `shield`.
def Shield() -> Data:
  Shield.Shield()

def Handler() -> Type:
  Router.Handler()

# `Handler() -> Handler()`: see `use` and `Route.wrap`.
def Middleware() -> Type:
  Router.Middleware()

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

# A value a middleware left for the handlers after it; "" when absent.
def Request.local(r: Request(), key: String) -> String:
  Http.Request.local(r, key)

# The id `request_id` gave this request; "" without that middleware.
def Request.id(r: Request()) -> String:
  Http.Request.local(r, "request_id")

# The token of this request's session; "" without `session` above.
def Request.session_id(r: Request()) -> String:
  Http.Request.local(r, "session_id")

def Request.with_local(r: Request(), key: String, value: String) -> Request():
  Http.Request.with_local(r, key, value)

# The server's store, on every request it builds; None elsewhere. The
# `Store` helpers below take the request, so a handler never needs this.
def Request.store(r: Request()) -> Maybe<&2, Store()>:
  Http.Request.store(r)

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

# The pattern of the route that answered, as written ("/users/:id"),
# for a middleware outside `dispatch`; "" when no route did.
def Response.route(r: Response()) -> String:
  Http.Response.route(r)

def Response.with_status(r: Response(), status: U32) -> Response():
  Http.Response.with_status(r, status)

def Response.with_header(r: Response(), name: String, value: String) -> Response():
  Http.Response.with_header(r, name, value)

# Sets a header only when the response lacks it.
def Response.with_default_header(r: Response(), name: String, value: String) -> Response():
  Http.Response.with_default_header(r, name, value)

# The `Set-Cookie` lines, in order.
def Response.cookies(r: Response()) -> List<&2, String>:
  Http.Response.cookies(r)

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
# path is yours to choose: nothing here guards against `..`; `static`
# does, for a whole directory.
def Response.file(req: Request(), path: String, mime: String) -> IO(Response()):
  Disk.respond(req, path, mime)

# A directory as a handler, on a wildcard route whose param is `path`:
#
#   Air.Route.get("/assets/*path", Air.static("public"))
#
# serves `public/css/app.css` for `/assets/css/app.css`, with the mime
# from the extension and everything `Response.file` does. A request
# cannot leave `dir`: a segment holding `/` or `\` (from `%2F`, `%5C`),
# `.`, `..` or a dotfile is a 404, as is a missing file. A path ending
# in `/` serves its `index.html`. There is no listing, and a symlink
# inside `dir` is followed wherever it points.
def static(+dir: String, req: Request()) -> IO(Response()):
  Static.respond(dir, req)

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

# A 200 with `template` rendered against `ctx` as HTML; see `View.render`.
def Response.view(+template: String, ctx: Json()) -> Response():
  View.respond(template, ctx)

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

# An error as a response: the status is the error's, and the body is
# rendered later by `on_error` or, without it, by the server in prod
# style. `fail` is the same wrapped in IO, for a handler to return.
def Response.fail(e: Error()) -> Response():
  Http.Response.fail(e)

def fail(e: Error()) -> IO(Response()):
  IO.pure(Response(), Http.Response.fail(e))

# The error a failed response carries; None once rendered.
def Response.error(r: Response()) -> Maybe<&2, Error()>:
  Http.Response.error(r)

# A 404 as a failed response, what `dispatch` answers for no route.
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

# Error
# -----
#
# Each takes a detail for the developer: shown by the renderers in dev,
# never in prod. Bend has no exceptions, so an error is a value a handler
# returns with `fail`.

def Error.bad_request(detail: String) -> Error():
  Http.BadRequest{detail}

def Error.unauthorized(detail: String) -> Error():
  Http.Unauthorized{detail}

def Error.forbidden(detail: String) -> Error():
  Http.Forbidden{detail}

def Error.not_found(detail: String) -> Error():
  Http.NotFound{detail}

def Error.conflict(detail: String) -> Error():
  Http.Conflict{detail}

def Error.gone(detail: String) -> Error():
  Http.Gone{detail}

def Error.too_large(detail: String) -> Error():
  Http.TooLarge{detail}

def Error.unsupported(detail: String) -> Error():
  Http.Unsupported{detail}

def Error.unprocessable(detail: String) -> Error():
  Http.Unprocessable{detail}

def Error.too_many(detail: String) -> Error():
  Http.TooMany{detail}

def Error.internal(detail: String) -> Error():
  Http.Internal{detail}

def Error.not_implemented(detail: String) -> Error():
  Http.NotImplemented{detail}

def Error.unavailable(detail: String) -> Error():
  Http.Unavailable{detail}

# Any other status.
def Error.other(status: U32, detail: String) -> Error():
  Http.Status{status, detail}

def Error.status(e: Error()) -> U32:
  Http.Error.status(e)

def Error.detail(e: Error()) -> String:
  Http.Error.detail(e)

# The reason phrase: "Not Found".
def Error.reason(+e: Error()) -> String:
  Http.Status.reason(Http.Error.status(e))

# Renderers for `on_error`. `plain` answers the reason phrase as text;
# in dev, the method and path on a second line and the detail on a
# third. `json` answers `{"status":404,"error":"Not Found"}`, plus
# `detail` and `path` in dev.
def Error.plain(+env: Env(), req: Request(), e: Error()) -> Response():
  Errors.plain(env, req, e)

def Error.json(+env: Env(), req: Request(), e: Error()) -> Response():
  Errors.json(env, req, e)

# Env
# ---

def Env.dev() -> Env():
  Http.Dev{}

def Env.prod() -> Env():
  Http.Prod{}

# `dev` when the `AIR_ENV` variable is "dev"; `prod` otherwise.
def Env.from_env() -> IO(Env()):
  Errors.Env.from_env()

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

# Wraps every route's handler in one middleware, for a group:
# `Route.mount("/admin", Route.wrap(~auth("secret"), admin()))`. The
# middleware is a template argument, so it must be closed: a def, or a
# def applied to constants, not a local variable. A single route needs
# no helper: `Route.get("/x", auth("secret")(handler))`.
def Route.wrap(~mw: Middleware(), routes: List<Route()>) -> List<Route()>:
  Router.wrap(~mw, routes)

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

# Middleware
# ----------

# Wraps a handler in each middleware, the first in the list outermost:
# with `use([a, b], h)`, `a` runs first on the way in and last on the
# way out. A middleware is a def with `next` first,
#
#   def auth(+token: String, next: Air.Handler(), req: Air.Request()) -> IO(Air.Response()):
#
# so `auth("secret")` is a middleware. One that answers without calling
# `next` ends the chain: `next` is affine, dropping it is free.
def use(mws: List<Middleware()>, handler: Handler()) -> Handler():
  Router.use(mws, handler)

# The error middleware: runs `next`, and renders a failed response with
# `render`. Put it in `use`, outermost or just inside the logging:
#
#   Air.use([Air.on_error(Air.Error.plain(env))], base)
#
# The server's own refusals (a bad request line, a limit, the 503 on
# timeout) happen before the app runs and do not pass through it.
def on_error(render: Render(), next: Handler(), req: Request()) -> IO(Response()):
  Errors.on_error(render, next, req)

# Hooks
# -----
#
# Lifecycle hooks are middleware that take a plain function instead of
# `next`. Their place in `use` or `Route.wrap` is their phase:
#
#   Air.use([
#     Air.request_id,
#     Air.on_response(record),        # onResponse: after, with the ms
#     Air.on_send(stamp),             # onSend: may change the response
#     Air.on_error(Air.Error.plain(env)),
#     Air.on_fail(report)             # onError: sees the failure first
#   ], base)
#
#   Air.Route.wrap(~Air.on_request(load_user), routes())   # preHandler
#
# `on_response` runs before the server writes: nothing after the write
# reaches app code.

# onRequest / preHandler: `f` may change the request the chain gets.
def on_request(f: Request() -> IO(Request()), next: Handler(), req: Request()) -> IO(Response()):
  Hooks.on_request(f, next, req)

# onSend: `f` gets the request and the response and answers the one sent.
def on_send(f: Request() -> Response() -> IO(Response()), next: Handler(), req: Request()) -> IO(Response()):
  Hooks.on_send(f, next, req)

# onResponse: `f` gets the request, the response and the milliseconds the
# chain inside took; the response is unchanged.
def on_response(f: Request() -> Response() -> Nat -> IO(Unit), next: Handler(), req: Request()) -> IO(Response()):
  Hooks.on_response(f, next, req)

# onError, to observe: `f` gets the request and the error of a failed
# response, which goes on unchanged. Put it inside `on_error`.
def on_fail(f: Request() -> Error() -> IO(Unit), next: Handler(), req: Request()) -> IO(Response()):
  Hooks.on_fail(f, next, req)

# Runs a fallible effect in a handler: its value goes to `k`, its failure
# becomes a 500 whose detail is the message. Use it instead of `IO.try`,
# which would end the process.
def attempt(-A: Type, act: IO(Result<&1, &1, U32 & String, A>), k: A -> IO(Response())) -> IO(Response()):
  Errors.attempt(A, act, k)

# Batteries
# ---------
#
# Middleware that ships with Air. Put them in `use`, outermost first:
#
#   Air.use([Air.request_id, Air.log, Air.shield(Air.Shield.default()), Air.cors(Air.Cors.any()), Air.on_error(render)], base)
#
# All sit outside `on_error` so an error response gets the headers and
# the log line too; a rendered error keeps the headers of the failure it
# came from.

# Gives the request an id: the client's `X-Request-Id` when it is one to
# 128 characters of letters, digits, `-`, `_` and `.` (what a proxy in
# front sets), else 16 hex characters from a random word and the
# millisecond it started. Handlers read it with
# `Request.id`; the client gets it back as `x-request-id`.
def request_id(next: Handler(), req: Request()) -> IO(Response()):
  Log.request_id(next, req)

# Prints one JSON line per request to stdout,
# `{"ts":5161,"id":"…","method":"GET","path":"/x","status":200,"ms":3}`,
# with `ts` the start in milliseconds since the process started (Bend
# has no wall clock; a log shipper adds the date). Put it inside `request_id`
# so the line has the id. The server itself logs only what the app
# never sees: bad heads, limits, and the 503 on timeout.
def log(next: Handler(), req: Request()) -> IO(Response()):
  Log.log(next, req)

# Cross-origin requests under `cfg`. A request without `Origin`, or from
# an origin the policy does not list, passes through untouched. A
# preflight (`OPTIONS` with `Access-Control-Request-Method`) is answered
# here with 204 and never reaches the router. Any other allowed request
# runs, and its response carries `Access-Control-Allow-Origin` and
# `Vary: origin`.
def cors(cfg: Cors(), next: Handler(), req: Request()) -> IO(Response()):
  Cors.cors(cfg, next, req)

# Adds each header of `hs` the response lacks; a handler's own wins.
def shield(hs: Shield(), next: Handler(), req: Request()) -> IO(Response()):
  Shield.shield(hs, next, req)

# At most `n` requests per `key` per window of `window_ms`. `key` names
# the bucket from the request: `Rate.by_ip(trust)`, `Rate.by_header(name)`,
# or a def of the app's. Counts live in the store's `rate` namespace and
# start over each window, so memory is bounded by the keys seen in one.
# Over the limit the request fails with 429, `retry-after` and the
# detail "rate limit: 6 of 5 per 60000 ms"; every response carries
# `x-ratelimit-limit`, `x-ratelimit-remaining` and `x-ratelimit-reset`
# (seconds). One route: `Air.rate(5, 60000, key)(handler)`; a group:
# `Route.wrap(~Air.rate(5, 60000, key), routes)`.
def rate(+n: U32, +window_ms: U32, key: Request() -> String, next: Handler(), req: Request()) -> IO(Response()):
  Rate.limit(n, window_ms, key, next, req)

# Gives every request below it a session: the `air_session` cookie's
# token when it names a live session, else a fresh one, whose cookie the
# response sets. Data lives in the store under `session:<token>`; the
# cookie carries the token alone (Bend has no HMAC to sign a cookie
# with), so sessions end with the process. See `Session.get` and friends.
def session(+cfg: Session(), next: Handler(), req: Request()) -> IO(Response()):
  Session.start(cfg, next, req)

# The body must be JSON (by content type, and parse) matching `schema`,
# or the request is answered here: 400 through `on_error` when the body
# is not JSON, 422 with every problem when it does not match:
#
#   {"status":422,"error":"Unprocessable Content","errors":["title: expected string","missing: done"]}
#
# The 422 bypasses `on_error` on purpose, so the client sees the list in
# prod too. One route: `Air.Route.post("/tasks", Air.validate_json(task())(create))`,
# with `task()` a def building the schema. The handler reads the body
# again with `Request.json`.
def validate_json(schema: Schema(), next: Handler(), req: Request()) -> IO(Response()):
  Schema.validate_json(schema, next, req)

# The query string against an object schema, leniently: `?limit=42`
# passes `Schema.int()`, `?on=true` passes `Schema.boolean()`. List the
# keys with `Schema.obj_open` unless unknown keys should fail too.
def validate_query(schema: Schema(), next: Handler(), req: Request()) -> IO(Response()):
  Schema.validate_query(schema, next, req)

# The path params against an object schema, leniently.
def validate_params(schema: Schema(), next: Handler(), req: Request()) -> IO(Response()):
  Schema.validate_params(schema, next, req)

# Schema
# ------
#
# No min, max, pattern or length rules: check a range in the handler
# after validation.

def Schema.any() -> Schema():
  Schema.any()

def Schema.str() -> Schema():
  Schema.str()

def Schema.num() -> Schema():
  Schema.num()

# A non-negative integer that fits in 32 bits.
def Schema.int() -> Schema():
  Schema.int()

def Schema.boolean() -> Schema():
  Schema.boolean()

def Schema.null() -> Schema():
  Schema.null()

# A string among `options`.
def Schema.one_of(options: List<&2, String>) -> Schema():
  Schema.one_of(options)

def Schema.arr(each: Schema()) -> Schema():
  Schema.arr(each)

# An object that refuses keys it does not list.
def Schema.obj(props: List<&2, Schema.Prop()>) -> Schema():
  Schema.obj(props)

# An object that lets other keys through.
def Schema.obj_open(props: List<&2, Schema.Prop()>) -> Schema():
  Schema.obj_open(props)

def Schema.field(name: String, s: Schema()) -> Schema.Prop():
  Schema.field(name, s)

# A field that may be absent; when present it must match.
def Schema.optional(name: String, s: Schema()) -> Schema.Prop():
  Schema.optional(name, s)

# Every problem, in document order; [] when `value` matches.
def Schema.errors(s: Schema(), value: Json()) -> List<&2, String>:
  Schema.errors(s, value)

# View
# ----

# `template` rendered against `ctx`, in a Mustache subset:
#
#   {{name}}             the value, HTML-escaped (`& < > " '`)
#   {{{name}}}           the value, raw
#   {{#name}}..{{/name}} once per item of an array, once for any other
#                        truthy value (with it as the context), else not
#   {{^name}}..{{/name}} once when the value is falsy or an empty array
#   {{.}}                the current item
#   {{! note }}          a comment
#
# Names may be dotted (`user.name`), and a block over a list still sees
# the outer fields. Missing names print as "". Malformed templates
# render, never fail. No partials. A template from disk:
#
#   IO.bind(Maybe<&2, String>, Air.Response(), Air.Disk.read("views/page.html"), t => ...)
#
# with `None` answered by `Air.fail(Air.Error.internal("template missing"))`.
def View.render(+template: String, ctx: Json()) -> String:
  View.render(template, ctx)

# Session
# -------

# Cookie `air_session`, `Path=/; HttpOnly; SameSite=Lax`, a day of TTL,
# a sweep of expired sessions once there are more than ten thousand,
# and not `Secure`: turn that on behind the TLS proxy.
def Session.default() -> Session():
  Session.default()

def Session.with_name(cfg: Session(), name: String) -> Session():
  Session.with_name(cfg, name)

# Milliseconds since the session was last touched before it counts as
# gone; up to 49 days.
def Session.with_ttl(cfg: Session(), ms: U32) -> Session():
  Session.with_ttl(cfg, ms)

# How many sessions the store holds before a request sweeps the expired
# ones.
def Session.with_max(cfg: Session(), max: U32) -> Session():
  Session.with_max(cfg, max)

def Session.secure(cfg: Session(), on: Bool) -> Session():
  Session.secure(cfg, on)

# A field of the session; "" when absent.
def Session.get(req: Request(), +key: String) -> IO(String):
  Session.get(req, key)

# Keys starting with `_` are the framework's; a write to one is dropped.
def Session.set(req: Request(), +key: String, +value: String) -> IO(Unit):
  Session.set(req, key, value)

# Adds one to a field holding a number (absent is 0) and answers the
# new count.
def Session.incr(req: Request(), +key: String) -> IO(U32):
  Session.incr(req, key)

# Every field, `_seen` (the last touch, in process milliseconds) included.
def Session.fields(req: Request()) -> IO(Map<&2, String>):
  Session.fields(req)

# Drops the data; the token and its cookie stay.
def Session.clear(req: Request()) -> IO(Unit):
  Session.clear(req)

# Drops the data and expires the cookie on `res`; the next request gets
# a new session.
def Session.end(req: Request(), res: Response()) -> IO(Response()):
  Session.end(req, res)

# Rate
# ----

# The client's address as a trusted proxy reports it; without one every
# request shares one bucket, since `TCP.accept` gives no peer address.
def Rate.by_ip(+trust: Trust(), req: Request()) -> String:
  Rate.by_ip(trust, req)

# A header's value, for API keys; absent is one bucket.
def Rate.by_header(+name: String, req: Request()) -> String:
  Rate.by_header(name, req)

# Store
# -----
#
# One value shared by every request of a server: namespaces (`ns`) of
# string maps, behind a lock. A handler reads and writes it through the
# request. `update` replaces a namespace with a pure function of it and
# answers the result; keep that function quick, every other request
# waits on it. A request built outside a server reads empty and writes
# nowhere. The framework uses the namespaces `rate` and, later,
# `session:*`; pick others.

# A key of a namespace; "" when absent.
def Store.get(req: Request(), +ns: String, +key: String) -> IO(String):
  Store.get_in(req, ns, key)

def Store.set(req: Request(), +ns: String, +key: String, +value: String) -> IO(Unit):
  Store.set_in(req, ns, key, value)

# Adds one to a key holding a number (absent counts as 0) and answers
# the new count, atomically.
def Store.incr(req: Request(), +ns: String, +key: String) -> IO(U32):
  Store.incr_in(req, ns, key)

# The whole namespace.
def Store.read(req: Request(), +ns: String) -> IO(Map<&2, String>):
  Store.read_in(req, ns)

# Replaces the namespace with `f` of it, atomically, and answers the new one.
def Store.update(req: Request(), +ns: String, f: Map<&2, String> -> Map<&2, String>) -> IO(Map<&2, String>):
  Store.update_in(req, ns, f)

# Removes a namespace whole.
def Store.drop(req: Request(), +ns: String) -> IO(Unit):
  Store.drop_in(req, ns)

# A store of one's own, for `serve_shared`.
def Store.new() -> IO(Store()):
  Store.new()

# Cors
# ----

# Any origin, without credentials: `Access-Control-Allow-Origin: *`.
def Cors.any() -> Cors():
  Cors.any()

# Exactly these origins, byte for byte: "https://app.example.com". The
# request's origin is echoed back.
def Cors.new(origins: List<&2, String>) -> Cors():
  Cors.new(origins)

# The comma list for `Access-Control-Allow-Methods`; the default is
# "GET, HEAD, POST, PUT, PATCH, DELETE, OPTIONS".
def Cors.with_methods(cfg: Cors(), methods: String) -> Cors():
  Cors.with_methods(cfg, methods)

# The comma list for `Access-Control-Allow-Headers`; empty (the default)
# echoes what the preflight asks for.
def Cors.with_headers(cfg: Cors(), headers: String) -> Cors():
  Cors.with_headers(cfg, headers)

# The comma list for `Access-Control-Expose-Headers`.
def Cors.with_expose(cfg: Cors(), expose: String) -> Cors():
  Cors.with_expose(cfg, expose)

# Allows cookies and authorization across origins. Browsers refuse `*`
# with credentials, so the origin is echoed back even under `any`.
def Cors.with_credentials(cfg: Cors(), on: Bool) -> Cors():
  Cors.with_credentials(cfg, on)

# Seconds a browser may cache a preflight; 600 by default.
def Cors.with_max_age(cfg: Cors(), seconds: U32) -> Cors():
  Cors.with_max_age(cfg, seconds)

# Shield
# ------

# `x-content-type-options: nosniff`, `x-frame-options: DENY`,
# `referrer-policy: strict-origin-when-cross-origin`,
# `cross-origin-opener-policy: same-origin`,
# `cross-origin-resource-policy: same-origin` and
# `x-permitted-cross-domain-policies: none`.
def Shield.default() -> Shield():
  Shield.default()

# `Strict-Transport-Security` for `seconds`, subdomains included. Off by
# default: only for a server reached over HTTPS.
def Shield.with_hsts(hs: Shield(), seconds: U32) -> Shield():
  Shield.with_hsts(hs, seconds)

def Shield.with_csp(hs: Shield(), policy: String) -> Shield():
  Shield.with_csp(hs, policy)

# "DENY" or "SAMEORIGIN".
def Shield.with_frame(hs: Shield(), value: String) -> Shield():
  Shield.with_frame(hs, value)

# Any header: replaces one of the same name, else appends.
def Shield.with_header(hs: Shield(), name: String, value: String) -> Shield():
  Shield.with_header(hs, name, value)

# OpenAPI
# -------
#
# A route can say what it takes and answers; `Air.openapi` turns a route
# list into an OpenAPI 3.1 document. `Api.body` and `Api.query` also
# validate, so one schema checks the request and documents it:
#
#   Air.Api.summary("Create a task",
#     Air.Api.returns(201, task(),
#       Air.Api.body(new_task(), Air.Route.post("/tasks", create))))
#
# Path parameters come from the pattern. Serve the document from a route
# outside the list it describes:
#
#   Air.Route.all([api(), [Air.Route.get("/openapi.json", Air.openapi("Tasks", "1.0.0", api()))]])

# Validates the JSON body against `schema` and documents it.
def Api.body(schema: Schema(), route: Route()) -> Route():
  OpenApi.body(schema, route)

# Validates the query against an object schema and documents each
# property as a query parameter.
def Api.query(schema: Schema(), route: Route()) -> Route():
  OpenApi.query(schema, route)

# Documents a JSON response with `status`.
def Api.returns(status: U32, schema: Schema(), route: Route()) -> Route():
  OpenApi.returns(status, schema, route)

def Api.summary(text: String, route: Route()) -> Route():
  OpenApi.summary(text, route)

def Api.tag(name: String, route: Route()) -> Route():
  OpenApi.tag(name, route)

# The document for `routes`, as JSON.
def Api.document(title: String, version: String, routes: List<Route()>) -> Json():
  OpenApi.document(title, version, routes)

# A handler answering the document for `routes`.
def openapi(title: String, version: String, routes: List<Route()>, req: Request()) -> IO(Response()):
  OpenApi.handler(title, version, routes, req)

# Health
# ------
#
# `Air.health()` is two routes, `GET /healthz` (200 while the process
# serves) and `GET /readyz` (503 while the server drains or while a check
# is down). Mount them with the app's routes:
#
#   Air.Route.all([Air.health(), routes()])
#
# When the stop switch flips, `/readyz` turns 503 at once. With a drain
# delay (`Ready.delay`, or `AIR_DRAIN_DELAY` under `serve_env`) the
# server keeps serving that long before it stops accepting, so a
# balancer sees the 503 and moves traffic away first.

def health() -> List<Route()>:
  Health.routes()

# Marks the check `name` down: `/readyz` answers 503 and lists it.
def Ready.down(store: Store(), name: String) -> IO(Unit):
  Health.down(store, name)

def Ready.up(store: Store(), name: String) -> IO(Unit):
  Health.up(store, name)

# The same from a handler, through the request's store.
def Ready.down_in(req: Request(), name: String) -> IO(Unit):
  Health.down_in(req, name)

def Ready.up_in(req: Request(), name: String) -> IO(Unit):
  Health.up_in(req, name)

# Milliseconds a stopping server keeps serving, `/readyz` answering 503,
# before it stops accepting. 0, the default, stops at once.
def Ready.delay(store: Store(), ms: U32) -> IO(Unit):
  Health.delay(store, ms)

# Metrics
# -------
#
# `Air.metrics` counts requests by method, route pattern and status and
# records how long each took, in the store. `Metrics.expose` answers
# them in the Prometheus text format. Put the middleware in `use` and
# the handler behind auth or on an internal path, since it names every
# route:
#
#   Air.use([Air.metrics, Air.log, ...], base)
#   Air.Route.mount("/admin", Air.Route.wrap(~auth("secret"), [Air.Route.get("/metrics", Air.Metrics.expose)]))

def metrics(next: Handler(), req: Request()) -> IO(Response()):
  Metric.metrics(next, req)

def Metrics.expose(req: Request()) -> IO(Response()):
  Metric.expose(req)

# Adds one to the counter `app_<name>_total`. `name` must be
# `[a-z0-9_]+`; any other name is ignored.
def Metrics.count(req: Request(), name: String) -> IO(Unit):
  Metric.count(req, name)

# Tracing
# -------
#
# `Air.trace(exporter)` continues the W3C trace a valid `traceparent`
# names, or starts one, and hands one `Span` per sampled request to
# `exporter`. Put it inside `request_id` and outside `log`, so the log
# line carries the trace id:
#
#   Air.use([Air.request_id, Air.trace(Air.Trace.print), Air.log], base)
#
# Handlers read the ids as locals: `trace_id`, `span_id`, `parent_id`,
# `trace_flags`, and `traceparent`, the value to send downstream.

# A span: one request, or one an app builds for its own work. `start_ms`
# is Unix epoch milliseconds as text, `parent_id` "" for a root.
def Span() -> Data:
  Trace.Span

def Span.new(trace_id: String, span_id: String, parent_id: String, name: String, start_ms: String, duration_ms: U32, status: U32, method: String, route: String, path: String) -> Span():
  Trace.Span{trace_id, span_id, parent_id, name, start_ms, duration_ms, status, method, route, path}

def Span.trace_id(s: Span()) -> String:
  match s:
    case Trace.Span{trace_id, span_id, parent_id, name, start_ms, duration_ms, status, method, route, path}:
      trace_id

def Span.span_id(s: Span()) -> String:
  match s:
    case Trace.Span{trace_id, span_id, parent_id, name, start_ms, duration_ms, status, method, route, path}:
      span_id

def Span.parent_id(s: Span()) -> String:
  match s:
    case Trace.Span{trace_id, span_id, parent_id, name, start_ms, duration_ms, status, method, route, path}:
      parent_id

def Span.name(s: Span()) -> String:
  match s:
    case Trace.Span{trace_id, span_id, parent_id, name, start_ms, duration_ms, status, method, route, path}:
      name

def Span.start_ms(s: Span()) -> String:
  match s:
    case Trace.Span{trace_id, span_id, parent_id, name, start_ms, duration_ms, status, method, route, path}:
      start_ms

def Span.duration_ms(s: Span()) -> U32:
  match s:
    case Trace.Span{trace_id, span_id, parent_id, name, start_ms, duration_ms, status, method, route, path}:
      duration_ms

def Span.status(s: Span()) -> U32:
  match s:
    case Trace.Span{trace_id, span_id, parent_id, name, start_ms, duration_ms, status, method, route, path}:
      status

def Span.method(s: Span()) -> String:
  match s:
    case Trace.Span{trace_id, span_id, parent_id, name, start_ms, duration_ms, status, method, route, path}:
      method

def Span.route(s: Span()) -> String:
  match s:
    case Trace.Span{trace_id, span_id, parent_id, name, start_ms, duration_ms, status, method, route, path}:
      route

def Span.path(s: Span()) -> String:
  match s:
    case Trace.Span{trace_id, span_id, parent_id, name, start_ms, duration_ms, status, method, route, path}:
      path

def trace(exporter: Span() -> IO(Unit), next: Handler(), req: Request()) -> IO(Response()):
  Trace.trace(exporter, next, req)

# Keeps one new trace in `every`, decided by the trace id so services
# that sample alike agree; a continued trace follows the caller's flag.
def trace_sampled(every: U32, exporter: Span() -> IO(Unit), next: Handler(), req: Request()) -> IO(Response()):
  Trace.trace_sampled(every, exporter, next, req)

# The exporters that ship: one JSON line per span on stdout, with
# OpenTelemetry attribute names, or nothing (ids are still propagated).
def Trace.print(s: Span()) -> IO(Unit):
  Trace.print(s)

def Trace.drop(s: Span()) -> IO(Unit):
  Trace.drop(s)

def Trace.json(s: Span()) -> String:
  Trace.json(s)

# Milliseconds since the Unix epoch, as decimal text: a wall clock, where
# `IO.now` counts from the process start.
def Clock.wall_ms() -> IO(String):
  Clock.wall_ms()

# Config
# ------
#
# Settings come from the environment first, then a `.env` file, then the
# default in code. `serve_env` does it all for the server: `PORT`, the
# `AIR_MAX_*` limits and the `AIR_TIMEOUT_*` timeouts, and the `.env` in
# the working directory, installed so handlers can read it:
#
#   def main() -> IO(Unit):
#     Air.serve_env(~app, 8080)
#
#   def greeting(req: Air.Request()) -> IO(Air.Response()):
#     IO.bind(String, Air.Response(), Air.Config.get(req, "GREETING", "hi"),
#       g => IO.pure(Air.Response(), Air.Response.text(g)))
#
# A number that is set but is not digits ends the process at startup with
# the variable's name. Values of names containing SECRET, TOKEN, KEY or
# PASSWORD are never printed.

# The pairs of a `.env` file.
def Config() -> Data:
  Config.Config()

# A variable, or `fallback` when it is unset or empty.
def Config.env(name: String, fallback: String) -> IO(String):
  Config.env(name, fallback)

# A variable as a number, or `fallback`; ends the process on a bad value.
def Config.u32(name: String, fallback: U32) -> IO(U32):
  Config.u32(name, fallback)

# `PORT`, or `fallback`; ends the process on a bad value.
def Config.port(fallback: U32) -> IO(U32):
  Config.port(fallback)

# The pairs of the `.env` file at `path`, empty when there is none; a
# line it cannot read is named and skipped.
def Config.load(path: String) -> IO(Config()):
  Config.load(path)

# The pairs of a `.env` text.
def Config.parse(text: String) -> Config():
  Config.parse(text)

# Puts a loaded config in the store, for `Config.get`.
def Config.install(store: Store(), cfg: Config()) -> IO(Unit):
  Config.install(store, cfg)

# A setting in a handler: the environment's, else the installed
# config's, else `fallback`.
def Config.get(req: Request(), name: String, fallback: String) -> IO(String):
  Config.get(req, name, fallback)

# Limits from `AIR_MAX_HEAD`, `AIR_MAX_HEADERS`, `AIR_MAX_URL` and
# `AIR_MAX_BODY`, each defaulting to `Limits.default()`'s.
def Limits.from_env() -> IO(Limits()):
  Config.limits()

# Timeouts from `AIR_TIMEOUT_IDLE`, `_HEAD`, `_BODY`, `_APP`, `_SEND` and
# `_DRAIN`, each defaulting to `Timeouts.default()`'s.
def Timeouts.from_env() -> IO(Timeouts()):
  Config.timeouts()

# Serves `app` on `PORT` (or `port`) with limits, timeouts and `.env`
# from the environment, until the process is killed.
def serve_env(~app: Handler(), +port: U32) -> IO(Unit):
  Config.serve(~app, port)

# `serve_env` until `switch` is flipped, like `serve_until`.
def serve_env_until(~app: Stoppable(), switch: Switch(), +port: U32) -> IO(Unit):
  Config.serve_until(~app, switch, port)

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

# `serve_until` with a store the caller made (`Store.new`), so a task
# outside the server can read and write what the handlers do; the
# handlers reach it through the request as always.
def serve_shared(~app: Stoppable(), +limits: Limits(), +timeouts: Timeouts(), +store: Store(), +switch: Switch(), +port: U32) -> IO(Unit):
  Server.serve_shared(~app, limits, timeouts, store, switch, port)

# Ends the process with `code`, whatever computations are still parked.
def exit(code: U32) -> IO(Unit):
  IO.die(Unit, code, "")

# Testing
# -------
#
# Runs an app in-process, without a socket. `inject` takes raw HTTP text,
# reads it as the server would (a refused head gives the refusal the
# server would send), runs the app with a fresh store and settles the
# response as the server does before writing. Timeouts, keep-alive and
# 100-continue are not simulated. A test is a program:
#
#   import ../examples/hello/app.bend as Hello
#
#   def main() -> IO(Unit):
#     do IO<Unit>:
#       res : Air.Response() <- Air.Test.inject(Hello.app, Air.Test.get("/hello/ada"))
#       a : Bool <- Air.Test.expect("greets", Air.Response.body(res), "Olá, ada!")
#       b : Bool <- Air.Test.expect_u32("200", Air.Response.status(res), 200)
#       Air.Test.finish([a, b])
#
# `finish` ends the process with code 1 when a check failed.

# A GET for `target` ("/path?query") with a `host` header.
def Test.get(target: String) -> String:
  Test.get(target)

# A POST of `body` with its content type and length.
def Test.post(target: String, content_type: String, body: String) -> String:
  Test.post(target, content_type, body)

# `raw` with one more header line.
def Test.with_header(name: String, value: String, raw: String) -> String:
  Test.with_header(name, value, raw)

# Runs `app` on `raw` with a fresh store.
def Test.inject(app: Handler(), raw: String) -> IO(Response()):
  Test.inject(app, raw)

# Runs `app` on `raw` with `store`, which carries state across requests.
def Test.inject_shared(app: Handler(), store: Store(), raw: String) -> IO(Response()):
  Test.inject_shared(app, store, raw)

# The body as a client reads it; a stream is read until it closes.
def Test.body(res: Response()) -> IO(String):
  Test.body(res)

# Prints `ok - name` or `not ok - name: want … got …`; answers whether
# it passed.
def Test.expect(name: String, got: String, want: String) -> IO(Bool):
  Test.expect(name, got, want)

def Test.expect_u32(name: String, got: U32, want: U32) -> IO(Bool):
  Test.expect_u32(name, got, want)

# A condition, with a note printed when it fails.
def Test.expect_true(name: String, ok: Bool, note: String) -> IO(Bool):
  Test.expect_true(name, ok, note)

# Prints the tally; exits 1 when any check failed.
def Test.finish(results: List<&2, Bool>) -> IO(Unit):
  Test.finish(results)
