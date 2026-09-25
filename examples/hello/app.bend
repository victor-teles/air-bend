import Base
import ../../air.bend as Air

# hello
# =====
#
# The app: handlers, routes and middleware. `main.bend` serves it and
# `tests/hello.bend` runs it without a socket.

def home(req: Air.Request()) -> IO(Air.Response()):
  IO.pure(Air.Response(), Air.Response.html("<h1>Hello from Bend</h1>"))

def greet(req: Air.Request()) -> IO(Air.Response()):
  IO.pure(Air.Response(), Air.Response.text("Olá, " ++ Air.Request.param(req, "name") ++ "!"))

def search(req: Air.Request()) -> IO(Air.Response()):
  IO.pure(Air.Response(), Air.Response.json("{\"q\": \"" ++ Air.Request.query(req, "q") ++ "\"}"))

def echo(req: Air.Request()) -> IO(Air.Response()):
  IO.pure(Air.Response(), Air.Response.text(Air.Request.body(req)))

# A urlencoded form: `curl -d 'name=x+y' localhost:8080/form`.
def form(req: Air.Request()) -> IO(Air.Response()):
  IO.pure(Air.Response(), Air.Response.text("Olá, " ++ Air.Request.form(req, "name") ++ "!"))

# `curl -b 'theme=dark' localhost:8080/cookie/theme`. A handler's
# request is affine; rebinding it with `+` lets it be read twice.
def cookie(req: Air.Request()) -> IO(Air.Response()):
  +req = req
  IO.pure(Air.Response(), Air.Response.text(Air.Request.cookie(req, Air.Request.param(req, "name"))))

# Server-Sent Events: five ticks a second apart. The producer runs in
# its own computation and closes the channel when done. `ok` is the
# last send's answer: False means the client is gone, so stop.
def tick(+n: Nat, +chan: Chan(String), ok: Bool) -> IO(Unit):
  match n ok:
    case _ False{}:
      IO.print("ticks: client gone")
    case 0n True{}:
      Chan.close(String, chan)
    case 1n+p True{}:
      do IO<Unit>:
        sent : Bool <- Chan.send(String, chan, Air.Sse.event("tick", Nat.show(n)))
        IO.sleep(1000)
        tick(p, chan, sent)

# The channel is shared: the producer writes it, the response carries
# it to the server. A do-block binding is affine, so a def with a `+`
# parameter does the sharing.
def ticks.start(chan: Chan(String)) -> IO(Air.Response()):
  +chan = chan
  do IO<Air.Response()>:
    IO.spawn(Unit, tick(5n, chan, True{}))
    return Air.Response.sse(chan)

def ticks(req: Air.Request()) -> IO(Air.Response()):
  IO.bind(Chan(String), Air.Response(), Air.Stream.new(), ticks.start)

# Middleware
# ----------
#
# A middleware is a def with `next` first. `Air.request_id` and `Air.log`
# come with Air: every request gets an id and one JSON log line. A
# middleware of one's own follows the same shape, as `auth` below.

# `auth` takes its setting before `next`, so `auth("secret")` is a
# middleware. A request with the right token goes on with a local the
# handlers can read; any other is answered here, and `next` is dropped.
def auth.go(next: Air.Handler(), req: Air.Request(), ok: Bool) -> IO(Air.Response()):
  match ok:
    case True{}:
      next(Air.Request.with_local(req, "user", "victor"))
    case False{}:
      Air.fail(Air.Error.unauthorized("x-token missing or wrong"))

def auth(+token: String, next: Air.Handler(), req: Air.Request()) -> IO(Air.Response()):
  +req = req
  auth.go(next, req, String.eq(Air.Request.header(req, "x-token"), token))

# `curl -H 'x-token: secret' localhost:8080/admin/whoami`.
def whoami(req: Air.Request()) -> IO(Air.Response()):
  IO.pure(Air.Response(), Air.Response.text("you are " ++ Air.Request.local(req, "user")))

# Errors
# ------
#
# A handler fails with a value. `on_error` below renders it: the reason
# phrase in prod, and with `AIR_ENV=dev` the route and the detail too.

def boom(req: Air.Request()) -> IO(Air.Response()):
  Air.fail(Air.Error.internal("the disk is on fire"))

# A fallible effect under `attempt`: its failure is a 500 with the
# message as detail, where `IO.try` would end the process. Try it with
# `env -u HOME bend examples/hello/main.bend`.
def env.fin(home: String) -> IO(Air.Response()):
  IO.pure(Air.Response(), Air.Response.text("home is " ++ home))

def env(req: Air.Request()) -> IO(Air.Response()):
  Air.attempt(String, IO.get_env("HOME"), env.fin)

# Shared state
# ------------
#
# The store is one value every request can read and write, in
# namespaces of strings, behind a lock. `incr` counts; `get`, `set` and
# `update` (a pure function over a namespace) do the rest.

def visits.fin(n: U32) -> IO(Air.Response()):
  IO.pure(Air.Response(), Air.Response.text(U32.show(n)))

# `curl localhost:8080/visits` twice answers 1 then 2.
def visits(req: Air.Request()) -> IO(Air.Response()):
  IO.bind(U32, Air.Response(), Air.Store.incr(req, "app", "visits"), visits.fin)

# Five requests per ten seconds, then 429 with `retry-after`. Without a
# trusted proxy there is no client address, so every client shares the
# bucket; `Air.Rate.by_header("x-api-key")` would key on a header.
def limited(req: Air.Request()) -> IO(Air.Response()):
  IO.pure(Air.Response(), Air.Response.text("still fine"))

# Sessions
# --------
#
# `Air.session` gives the routes it wraps a session, keyed by a cookie;
# handlers read and write fields by name. It wraps a group rather than
# the whole app: a client that never sends cookies (a load generator,
# a bot) would mint a session per request.

def count.fin(n: U32) -> IO(Air.Response()):
  IO.pure(Air.Response(), Air.Response.text(U32.show(n)))

# `curl -c jar -b jar localhost:8080/count` counts up per browser.
def count(req: Air.Request()) -> IO(Air.Response()):
  IO.bind(U32, Air.Response(), Air.Session.incr(req, "n"), count.fin)

# Drops the session and its cookie.
def logout(req: Air.Request()) -> IO(Air.Response()):
  Air.Session.end(req, Air.Response.text("bye"))

# Config
# ------
#
# `GREETING` from the environment, else from a `.env` file in the
# working directory, else "Olá": `GREETING=Hi bend examples/hello/main.bend`
# then `curl localhost:8080/config/greeting`.

def greeting.fin(g: String) -> IO(Air.Response()):
  IO.pure(Air.Response(), Air.Response.text(g))

def greeting(req: Air.Request()) -> IO(Air.Response()):
  IO.bind(String, Air.Response(), Air.Config.get(req, "GREETING", "Olá"), greeting.fin)

# Templates
# ---------
#
# A template held in a def and rendered from a JSON context: `{{name}}`
# is escaped, the list renders once per item, and the empty state shows
# when there are none. `curl localhost:8080/page/Ada%20%3Cx%3E`.

def page_template() -> String:
  "<h1>Hello, {{name}}</h1>\n<ul>{{#items}}<li>{{.}}</li>{{/items}}</ul>{{^items}}<p>Nothing yet.</p>{{/items}}\n"

def page(req: Air.Request()) -> IO(Air.Response()):
  IO.pure(Air.Response(), Air.Response.view(page_template(), Air.Json.obj([
    Air.Json.field("name", Air.Json.of_str(Air.Request.param(req, "name"))),
    Air.Json.field("items", Air.Json.arr([Air.Json.of_str("routing"), Air.Json.of_str("sessions"), Air.Json.of_str("templates")]))
  ])))

# The empty state: `curl localhost:8080/empty`.
def empty(req: Air.Request()) -> IO(Air.Response()):
  IO.pure(Air.Response(), Air.Response.view(page_template(), Air.Json.obj([
    Air.Json.field("name", Air.Json.of_str("nobody")),
    Air.Json.field("items", Air.Json.arr([]))
  ])))

# Hooks
# -----
#
# Lifecycle hooks are middleware that take a function. They wrap the
# `/hooks` group only, so the rest of the app pays nothing: `record`
# counts every response of the group by status class, `stamp` adds a
# header, `report` counts failures before `on_error` renders them.
# `curl localhost:8080/hooks/ok`, `/hooks/boom`, then `/hooks/stats`.

def status_class(+s: U32) -> String:
  U32.show(U32.div(s, 100)) ++ "xx"

def counted(n: U32) -> IO(Unit):
  IO.pure(Unit, Unit{})

# onResponse: after the handler, with its milliseconds.
def record(req: Air.Request(), res: Air.Response(), ms: Nat) -> IO(Unit):
  IO.bind(U32, Unit, Air.Store.incr(req, "hook_statuses", status_class(Air.Response.status(res))), counted)

# onSend: the response the client gets.
def stamp(req: Air.Request(), res: Air.Response()) -> IO(Air.Response()):
  IO.pure(Air.Response(), Air.Response.with_header(res, "x-hooked", "yes"))

# onError, observing: the failure before it is rendered.
def report(req: Air.Request(), e: Air.Error()) -> IO(Unit):
  IO.bind(U32, Unit, Air.Store.incr(req, "hook_failures", U32.show(Air.Error.status(e))), counted)

def hook_ok(req: Air.Request()) -> IO(Air.Response()):
  IO.pure(Air.Response(), Air.Response.text("ok"))

def hook_boom(req: Air.Request()) -> IO(Air.Response()):
  Air.fail(Air.Error.internal("hooked failure"))

def hook_stats.fin(ok: String, failed: String) -> IO(Air.Response()):
  IO.pure(Air.Response(), Air.Response.text("2xx=" ++ ok ++ " 5xx=" ++ failed))

def hook_stats.go(req: Air.Request(), ok: String) -> IO(Air.Response()):
  IO.bind(String, Air.Response(), Air.Store.get(req, "hook_failures", "500"), failed => hook_stats.fin(ok, failed))

# Counts so far; this request is not in them yet, since `record` runs
# after it.
def hook_stats(req: Air.Request()) -> IO(Air.Response()):
  +req = req
  IO.bind(String, Air.Response(), Air.Store.get(req, "hook_statuses", "2xx"), ok => hook_stats.go(req, ok))

def hooked() -> List<Air.Route()>:
  [
    Air.Route.get("/ok", hook_ok),
    Air.Route.get("/boom", hook_boom),
    Air.Route.get("/stats", hook_stats)
  ]

# preHandler: runs after routing, inside the admin group, so a handler
# there can read what it set.
def mark_admin(req: Air.Request()) -> IO(Air.Request()):
  IO.pure(Air.Request(), Air.Request.with_local(req, "area", "admin"))

# Health
# ------
#
# `Air.health()` adds `/healthz` and `/readyz`. `/admin/demo/down` marks
# a `demo` check down, so `/readyz` answers 503 until `/admin/demo/up`.

def demo.fin(+state: String, u: Unit) -> IO(Air.Response()):
  IO.pure(Air.Response(), Air.Response.text("demo " ++ state))

def demo.go(req: Air.Request(), +state: String, up: Bool) -> IO(Air.Response()):
  match up:
    case True{}:
      IO.bind(Unit, Air.Response(), Air.Ready.up_in(req, "demo"), u => demo.fin(state, u))
    case False{}:
      IO.bind(Unit, Air.Response(), Air.Ready.down_in(req, "demo"), u => demo.fin(state, u))

def demo(req: Air.Request()) -> IO(Air.Response()):
  +req = req
  +state = Air.Request.param(req, "state")
  demo.go(req, state, String.eq(state, "up"))

def area(req: Air.Request()) -> IO(Air.Response()):
  IO.pure(Air.Response(), Air.Response.text("area " ++ Air.Request.local(req, "area")))

# Metrics
# -------
#
# `Air.metrics` wraps the whole app (see `app.fin`) and counts every
# request by method, route pattern and status, with a latency
# histogram. `/admin/metrics` answers them for Prometheus, behind
# `auth` since it names every route:
# `curl -H 'x-token: secret' localhost:8080/admin/metrics`.

# Tracing
# -------
#
# `Air.trace` (see `app.fin`) continues a W3C `traceparent` or starts a
# trace, and prints one span per request as a JSON line. `/trace` shows
# what a handler sees; `traceparent` is what it would send downstream:
# `curl -H 'traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01' localhost:8080/trace`.

def trace_ids(req: Air.Request()) -> IO(Air.Response()):
  +req = req
  IO.pure(Air.Response(), Air.Response.text(String.join([
    Air.Request.local(req, "traceparent"),
    Air.Request.local(req, "trace_id"),
    Air.Request.local(req, "parent_id"),
    Air.Request.local(req, "span_id")
  ], "\n")))

# Routes
# ------

def public() -> List<Air.Route()>:
  [
    Air.Route.get("/", home),
    Air.Route.get("/hello/:name", greet),
    Air.Route.get("/search", search),
    Air.Route.post("/echo", echo),
    Air.Route.post("/form", form),
    Air.Route.get("/cookie/:name", cookie),
    Air.Route.get("/ticks", ticks),
    Air.Route.get("/boom", boom),
    Air.Route.get("/env", env),
    Air.Route.get("/visits", visits),
    Air.Route.get("/limited", Air.rate(5, 10000, Air.Rate.by_ip(Air.Trust.none()))(limited)),
    Air.Route.get("/page/:name", page),
    Air.Route.get("/empty", empty),
    Air.Route.get("/config/greeting", greeting),
    Air.Route.get("/trace", trace_ids)
  ]

def with_session() -> List<Air.Route()>:
  [
    Air.Route.get("/count", count),
    Air.Route.get("/logout", logout)
  ]

def admin() -> List<Air.Route()>:
  [
    Air.Route.get("/whoami", whoami),
    Air.Route.get("/area", area),
    Air.Route.post("/demo/:state", demo),
    Air.Route.get("/metrics", Air.Metrics.expose)
  ]

# The admin group is wrapped in `auth` and mounted under "/admin"; the
# middleware is a template argument, so it is a def applied to a constant.
def routes() -> List<Air.Route()>:
  Air.Route.all([
    Air.health(),
    public(),
    Air.Route.wrap(~Air.session(Air.Session.default()), with_session()),
    Air.Route.mount("/admin", Air.Route.wrap(~auth("secret"), Air.Route.wrap(~Air.on_request(mark_admin), admin()))),
    Air.Route.mount("/hooks",
      Air.Route.wrap(~Air.on_response(record),
        Air.Route.wrap(~Air.on_send(stamp),
          Air.Route.wrap(~Air.on_fail(report), hooked()))))
  ])

def base(req: Air.Request()) -> IO(Air.Response()):
  Air.dispatch(routes(), req)

# `metrics` is outermost, so its timing covers the whole chain. `trace`
# sits inside `request_id` and outside `log`, so the log line carries
# the trace id.
# `request_id` and `log` wrap the whole app; `shield` adds defensive
# headers and `cors` lets any origin call; then `on_error` renders
# failures as plain text. The first middleware in the list is the
# outermost, so an error response gets the headers and the log line too.
# `serve` takes the app as a template, which must be a closed term, so
# the environment is read per request rather than passed in from `main`.
def app.fin(req: Air.Request(), env: Air.Env()) -> IO(Air.Response()):
  Air.use([
    Air.metrics,
    Air.request_id,
    Air.trace(Air.Trace.print),
    Air.log,
    Air.shield(Air.Shield.default()),
    Air.cors(Air.Cors.any()),
    Air.on_error(Air.Error.plain(env))
  ], base)(req)

def app(req: Air.Request()) -> IO(Air.Response()):
  IO.bind(Air.Env(), Air.Response(), Air.Env.from_env(), app.fin(req))
