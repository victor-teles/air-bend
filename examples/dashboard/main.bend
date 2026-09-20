import Base
import ../../air.bend as Air

# dashboard
# =========
#
# A page with real markup: an HTML shell and a script served from
# `public/`, styled with Tailwind, that talks to JSON routes on the same
# server. Run it from this folder or from the repo root:
#
#   cd examples/dashboard && bend main.bend
#   bend examples/dashboard/main.bend
#
# and open http://localhost:8080.

# Static routes
# -------------
#
# `Air.Response.file` reads the file, tags it with an ETag, and answers
# 304 or 206 when the browser asks. The first path is right when run
# from this folder, the second from the repo root.

def serve_file.retry(+req: Air.Request(), name: String, mime: String, first: Air.Response(), missing: Bool) -> IO(Air.Response()):
  match missing:
    case True{}:
      Air.Response.file(req, "examples/dashboard/public/" ++ name, mime)
    case False{}:
      IO.pure(Air.Response(), first)

def serve_file.fin(+req: Air.Request(), name: String, mime: String, first: Air.Response()) -> IO(Air.Response()):
  +first = first
  serve_file.retry(req, name, mime, first, U32.is_eq(Air.Response.status(first), 404))

def serve_file(req: Air.Request(), +name: String, +mime: String) -> IO(Air.Response()):
  +req = req
  IO.bind(Air.Response(), Air.Response(), Air.Response.file(req, "public/" ++ name, mime), serve_file.fin(req, name, mime))

def index(req: Air.Request()) -> IO(Air.Response()):
  serve_file(req, "index.html", "text/html")

def script(req: Air.Request()) -> IO(Air.Response()):
  serve_file(req, "app.js", "text/javascript")

# JSON routes
# -----------
#
# Responses are built as values and rendered by Air, so a quote in a
# title comes out escaped.

def task(id: U32, title: String, done: Bool) -> Air.Json():
  Air.Json.obj([
    Air.Json.field("id", Air.Json.of_u32(id)),
    Air.Json.field("title", Air.Json.of_str(title)),
    Air.Json.field("done", Air.Json.of_bool(done))
  ])

def stats.fin(now: Nat) -> IO(Air.Response()):
  IO.pure(Air.Response(), Air.Response.of_json(Air.Json.obj([
    Air.Json.field("server", Air.Json.of_str("air")),
    Air.Json.field("bend", Air.Json.of_str("2.0.10")),
    Air.Json.field("uptime_ms", Air.Json.num(Nat.show(now))),
    Air.Json.field("requests_per_conn", Air.Json.of_u32(100000)),
    Air.Json.field("max_body", Air.Json.of_u32(1048576))
  ])))

def stats(req: Air.Request()) -> IO(Air.Response()):
  IO.bind(Nat, Air.Response(), IO.now(), stats.fin)

def tasks(req: Air.Request()) -> IO(Air.Response()):
  IO.pure(Air.Response(), Air.Response.of_json(Air.Json.arr([
    task(1, "Parse the request line", True{}),
    task(2, "Decode chunked bodies", True{}),
    task(3, "Serve a page with Tailwind", True{}),
    task(4, "Percent-decode paths", True{}),
    task(5, "Parse JSON bodies", True{}),
    task(6, "Static file middleware", False{})
  ])))

def greet(req: Air.Request()) -> IO(Air.Response()):
  IO.pure(Air.Response(), Air.Response.of_json(Air.Json.obj([
    Air.Json.field("greeting", Air.Json.of_str("Hello, " ++ Air.Request.param(req, "name") ++ "!"))
  ])))

# Echoes the JSON body back, wrapped; a body that is not JSON is a 400,
# rendered as JSON by `on_error` below.
def echo.fin(parsed: Maybe<&2, Air.Json()>) -> Air.Response():
  match parsed:
    case None{}:
      Air.Response.fail(Air.Error.bad_request("body is not JSON"))
    case Some{v}:
      Air.Response.of_json(Air.Json.obj([Air.Json.field("received", v)]))

def echo(req: Air.Request()) -> IO(Air.Response()):
  IO.pure(Air.Response(), echo.fin(Air.Request.json(req)))

# Flips the server's stop switch: no new connections are accepted, the
# requests in flight finish, and `main` goes on to exit.
def shutdown(switch: Air.Switch(), req: Air.Request()) -> IO(Air.Response()):
  do IO<Air.Response()>:
    Air.Switch.flip(switch)
    return Air.Response.of_json(Air.Json.obj([Air.Json.field("stopping", Air.Json.of_bool(True{}))]))

def pages() -> List<Air.Route()>:
  [
    Air.Route.get("/", index),
    Air.Route.get("/app.js", script)
  ]

# The JSON routes, mounted under "/api" below.
def api(switch: Air.Switch()) -> List<Air.Route()>:
  [
    Air.Route.get("/stats", stats),
    Air.Route.get("/tasks", tasks),
    Air.Route.get("/hello/:name", greet),
    Air.Route.post("/echo", echo),
    Air.Route.post("/shutdown", shutdown(switch))
  ]

def routes(switch: Air.Switch()) -> List<Air.Route()>:
  Air.Route.all([pages(), Air.Route.mount("/api", api(switch))])

# The app takes the stop switch along with the request, as `serve_until`
# hands it over, so a route can stop the server. Errors, the router's 404
# included, are rendered as JSON; `AIR_ENV=dev` adds detail and path.
def base(switch: Air.Switch(), req: Air.Request()) -> IO(Air.Response()):
  Air.dispatch(routes(switch), req)

def app.fin(switch: Air.Switch(), req: Air.Request(), env: Air.Env()) -> IO(Air.Response()):
  Air.use([Air.on_error(Air.Error.json(env))], base(switch))(req)

def app(switch: Air.Switch(), req: Air.Request()) -> IO(Air.Response()):
  IO.bind(Air.Env(), Air.Response(), Air.Env.from_env(), app.fin(switch, req))

# The switch is a channel, so it can be shared: once with the route
# check, once with the server.
def serve(+switch: Air.Switch()) -> IO(Unit):
  do IO<Unit>:
    Air.Route.check(routes(switch))
    Air.serve_until(~app, Air.Limits.default(), Air.Timeouts.default(), switch, 8080)
    Air.exit(0)

def main() -> IO(Unit):
  do IO<Unit>:
    switch : Air.Switch() <- Air.Switch.new()
    serve(switch)
