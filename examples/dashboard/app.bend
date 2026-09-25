import Base
import ../../air.bend as Air

# dashboard
# =========
#
# A page with real markup: an HTML shell and a script served from
# `public/`, styled with Tailwind, that talks to JSON routes on the same
# server. This file is the app; `main.bend` serves it and
# `tests/dashboard.bend` runs it without a socket.

# Static files
# ------------
#
# `Air.static` maps the `*path` wildcard onto a file under `public/`,
# refusing anything that could leave the directory, and answers 304 or
# 206 when the browser asks. The first directory is right when run from
# this folder, the second from the repo root.

def files.retry(req: Air.Request(), first: Air.Response(), missing: Bool) -> IO(Air.Response()):
  match missing:
    case True{}:
      Air.static("examples/dashboard/public", req)
    case False{}:
      IO.pure(Air.Response(), first)

def files.fin(req: Air.Request(), first: Air.Response()) -> IO(Air.Response()):
  +first = first
  files.retry(req, first, U32.is_eq(Air.Response.status(first), 404))

def files(req: Air.Request()) -> IO(Air.Response()):
  +req = req
  IO.bind(Air.Response(), Air.Response(), Air.static("public", req), files.fin(req))

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

def all_tasks() -> List<&2, Air.Json()>:
  [
    task(1, "Parse the request line", True{}),
    task(2, "Decode chunked bodies", True{}),
    task(3, "Serve a page with Tailwind", True{}),
    task(4, "Percent-decode paths", True{}),
    task(5, "Parse JSON bodies", True{}),
    task(6, "Static file middleware", True{}),
    task(7, "Validate request bodies", False{})
  ]

def tasks.limit(n: Maybe<&2, U32>) -> Nat:
  match n:
    case None{}:
      100n
    case Some{k}:
      U32.to_nat(k)

# `?limit=2` keeps the first two; the query was checked before this ran,
# so `limit` is absent or an integer.
def tasks(req: Air.Request()) -> IO(Air.Response()):
  IO.pure(Air.Response(), Air.Response.of_json(Air.Json.arr(
    List.take(&2, Air.Json(), all_tasks(), tasks.limit(U32.read(Air.Request.query(req, "limit")))))))

def tasks_query() -> Air.Schema():
  Air.Schema.obj_open([Air.Schema.optional("limit", Air.Schema.int())])

# A new task: a title and whether it is done, nothing else.
def new_task() -> Air.Schema():
  Air.Schema.obj([
    Air.Schema.field("title", Air.Schema.str()),
    Air.Schema.field("done", Air.Schema.boolean())
  ])

# What the task routes answer, for the API document.
def task_schema() -> Air.Schema():
  Air.Schema.obj([
    Air.Schema.field("id", Air.Schema.int()),
    Air.Schema.field("title", Air.Schema.str()),
    Air.Schema.field("done", Air.Schema.boolean())
  ])

def created_schema() -> Air.Schema():
  Air.Schema.obj([
    Air.Schema.field("id", Air.Schema.int()),
    Air.Schema.field("task", new_task())
  ])

def create.fin(body: Maybe<&2, Air.Json()>) -> Air.Response():
  match body:
    case None{}:
      Air.Response.fail(Air.Error.bad_request("body is not JSON"))
    case Some{v}:
      Air.Response.with_status(Air.Response.of_json(Air.Json.obj([
        Air.Json.field("id", Air.Json.of_u32(8)),
        Air.Json.field("task", v)
      ])), 201)

# Runs only for a body that matches `new_task()`.
def create(req: Air.Request()) -> IO(Air.Response()):
  IO.pure(Air.Response(), create.fin(Air.Request.json(req)))

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

# One route for the page and everything beside it; it goes after the
# API mount so `/api/...` matches first.
def pages() -> List<Air.Route()>:
  [Air.Route.get("/*path", files)]

# The JSON routes, mounted under "/api" below. The task routes validate
# and document with one schema each: `Api.query` and `Api.body` check
# the request, and the notes feed `/openapi.json`.
def api(switch: Air.Switch()) -> List<Air.Route()>:
  [
    Air.Api.summary("Server stats", Air.Route.get("/stats", stats)),
    Air.Api.tag("tasks",
      Air.Api.summary("List tasks",
        Air.Api.returns(200, Air.Schema.arr(task_schema()),
          Air.Api.query(tasks_query(), Air.Route.get("/tasks", tasks))))),
    Air.Api.tag("tasks",
      Air.Api.summary("Create a task",
        Air.Api.returns(201, created_schema(),
          Air.Api.body(new_task(), Air.Route.post("/tasks", create))))),
    Air.Api.summary("Greet by name", Air.Route.get("/hello/:name", greet)),
    Air.Api.summary("Echo a JSON body", Air.Route.post("/echo", echo)),
    Air.Api.summary("Stop the server", Air.Route.post("/shutdown", shutdown(switch)))
  ]

# The API under "/api", as served and as documented.
def api_mounted(switch: Air.Switch()) -> List<Air.Route()>:
  Air.Route.mount("/api", api(switch))

# `/openapi.json` documents `api_mounted`; it builds the list again
# rather than containing itself.
def routes(+switch: Air.Switch()) -> List<Air.Route()>:
  Air.Route.all([
    Air.health(),
    api_mounted(switch),
    [Air.Route.get("/openapi.json", Air.openapi("Air dashboard", "1.0.0", api_mounted(switch)))],
    pages()
  ])

# The app takes the stop switch along with the request, as `serve_until`
# hands it over, so a route can stop the server. Every request gets an
# id and a log line, every response the default security headers; a front end served elsewhere in development
# (Vite's port, say) may call the API thanks to `cors`. Errors, the
# router's 404 included, are rendered as JSON; `AIR_ENV=dev` adds detail
# and path.
def base(switch: Air.Switch(), req: Air.Request()) -> IO(Air.Response()):
  Air.dispatch(routes(switch), req)

def app.fin(switch: Air.Switch(), req: Air.Request(), env: Air.Env()) -> IO(Air.Response()):
  Air.use([
    Air.request_id,
    Air.log,
    Air.shield(Air.Shield.default()),
    Air.cors(Air.Cors.new(["http://localhost:5173"])),
    Air.on_error(Air.Error.json(env))
  ], base(switch))(req)

def app(switch: Air.Switch(), req: Air.Request()) -> IO(Air.Response()):
  IO.bind(Air.Env(), Air.Response(), Air.Env.from_env(), app.fin(switch, req))
