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
# A middleware is a def with `next` first. `timing` runs the rest of the
# chain and logs how long it took. The request is read here and passed
# on, so it is rebound with `+`; so is the response, read for its status
# and returned.

def timing.fin(method: String, path: String, before: Nat, res: Air.Response(), after: Nat) -> IO(Air.Response()):
  +res = res
  do IO<Air.Response()>:
    IO.print(method ++ " " ++ path ++ " -> " ++ U32.show(Air.Response.status(res)) ++ " (" ++ Nat.show(Nat.sub(after, before)) ++ " ms)")
    return res

def timing.go(method: String, path: String, before: Nat, res: Air.Response()) -> IO(Air.Response()):
  IO.bind(Nat, Air.Response(), IO.now(), timing.fin(method, path, before, res))

def timing(next: Air.Handler(), req: Air.Request()) -> IO(Air.Response()):
  +req = req
  do IO<Air.Response()>:
    before : Nat <- IO.now()
    res : Air.Response() <- next(req)
    timing.go(Air.Method.show(Air.Request.method(req)), Air.Request.path(req), before, res)

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
    Air.Route.get("/env", env)
  ]

def admin() -> List<Air.Route()>:
  [Air.Route.get("/whoami", whoami)]

# The admin group is wrapped in `auth` and mounted under "/admin"; the
# middleware is a template argument, so it is a def applied to a constant.
def routes() -> List<Air.Route()>:
  Air.Route.all([public(), Air.Route.mount("/admin", Air.Route.wrap(~auth("secret"), admin()))])

def base(req: Air.Request()) -> IO(Air.Response()):
  Air.dispatch(routes(), req)

# `timing` wraps the whole app, then `on_error` renders failures as
# plain text; the first middleware in the list is the outermost. `serve`
# takes the app as a template, which must be a closed term, so the
# environment is read per request rather than passed in from `main`.
def app.fin(req: Air.Request(), env: Air.Env()) -> IO(Air.Response()):
  Air.use([timing, Air.on_error(Air.Error.plain(env))], base)(req)

def app(req: Air.Request()) -> IO(Air.Response()):
  IO.bind(Air.Env(), Air.Response(), Air.Env.from_env(), app.fin(req))

def main() -> IO(Unit):
  do IO<Unit>:
    Air.Route.check(routes())
    Air.serve(~app, 8080)
