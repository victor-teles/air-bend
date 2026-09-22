import Base
import ../../air.bend as Air

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
    Air.Route.get("/limited", Air.rate(5, 10000, Air.Rate.by_ip(Air.Trust.none()))(limited))
  ]

def with_session() -> List<Air.Route()>:
  [
    Air.Route.get("/count", count),
    Air.Route.get("/logout", logout)
  ]

def admin() -> List<Air.Route()>:
  [Air.Route.get("/whoami", whoami)]

# The admin group is wrapped in `auth` and mounted under "/admin"; the
# middleware is a template argument, so it is a def applied to a constant.
def routes() -> List<Air.Route()>:
  Air.Route.all([
    public(),
    Air.Route.wrap(~Air.session(Air.Session.default()), with_session()),
    Air.Route.mount("/admin", Air.Route.wrap(~auth("secret"), admin()))
  ])

def base(req: Air.Request()) -> IO(Air.Response()):
  Air.dispatch(routes(), req)

# `request_id` and `log` wrap the whole app; `shield` adds defensive
# headers and `cors` lets any origin call; then `on_error` renders
# failures as plain text. The first middleware in the list is the
# outermost, so an error response gets the headers and the log line too.
# `serve` takes the app as a template, which must be a closed term, so
# the environment is read per request rather than passed in from `main`.
def app.fin(req: Air.Request(), env: Air.Env()) -> IO(Air.Response()):
  Air.use([
    Air.request_id,
    Air.log,
    Air.shield(Air.Shield.default()),
    Air.cors(Air.Cors.any()),
    Air.on_error(Air.Error.plain(env))
  ], base)(req)

def app(req: Air.Request()) -> IO(Air.Response()):
  IO.bind(Air.Env(), Air.Response(), Air.Env.from_env(), app.fin(req))

def main() -> IO(Unit):
  do IO<Unit>:
    Air.Route.check(routes())
    Air.serve(~app, 8080)
