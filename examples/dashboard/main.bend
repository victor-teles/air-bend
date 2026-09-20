import Base
import ../../air.bend as Air
import ../../air/text.bend as Text

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

# Reading a file
# --------------
#
# `File.read` hands back the handle beside each chunk; read until a chunk
# is empty, then close. `Text.append` keeps big files off the stack.

def OpenR() -> Type:
  Result<&1, &1, U32 & String, File>

def ReadR() -> Type:
  File & Result<&1, &1, U32 & String, String>

type FileState is Type:
  Reading{file: File, acc: String}
  Finished{file: File, acc: String}

def read_more(file: File, acc: String, eof: Bool) -> FileState:
  match eof:
    case True{}:
      Finished{file, acc}
    case False{}:
      Reading{file, acc}

def read_step(acc: String, r: ReadR()) -> FileState:
  (file, res) = r
  match res:
    case Fail{e}:
      Finished{file, acc}
    case Done{+chunk}:
      read_more(file, Text.append(acc, chunk), String.is_empty(chunk))

def read_loop(fuel: Nat, state: FileState) -> IO(String):
  match fuel state:
    case _ Finished{file, acc}:
      do IO<String>:
        File.close(file)
        return acc
    case 0n Reading{file, acc}:
      do IO<String>:
        File.close(file)
        return acc
    case 1n+p Reading{file, acc}:
      do IO<String>:
        r : ReadR() <- File.read(file, 65536)
        read_loop(p, read_step(acc, r))

def read_opened(r: OpenR()) -> IO(String):
  match r:
    case Fail{e}:
      IO.pure(String, "")
    case Done{file}:
      read_loop(1000n, Reading{file, ""})

# The first path is right when run from this folder, the second from the
# repo root. A file found at neither reads as "".
def read_fallback(fallback: String, r: OpenR()) -> IO(String):
  match r:
    case Fail{e}:
      IO.bind(OpenR(), String, File.open(fallback, "r"), read_opened)
    case Done{file}:
      read_loop(1000n, Reading{file, ""})

def read_public(+name: String) -> IO(String):
  IO.bind(OpenR(), String, File.open("public/" ++ name, "r"), read_fallback("examples/dashboard/public/" ++ name))

# Static routes
# -------------

# An empty file, or a missing one, answers 404. Matching on the string
# avoids copying a body that may be large.
def with_type(body: String, mime: String) -> Air.Response():
  match body:
    case SNil{}:
      Air.Response.not_found()
    case SCon{h, t}:
      Air.Response.with_header(Air.Response.new(200, SCon{h, t}), "content-type", mime)

def serve_file.fin(mime: String, body: String) -> IO(Air.Response()):
  IO.pure(Air.Response(), with_type(body, mime))

def serve_file(name: String, mime: String) -> IO(Air.Response()):
  IO.bind(String, Air.Response(), read_public(name), serve_file.fin(mime))

def index(req: Air.Request()) -> IO(Air.Response()):
  serve_file("index.html", "text/html; charset=utf-8")

def script(req: Air.Request()) -> IO(Air.Response()):
  serve_file("app.js", "text/javascript; charset=utf-8")

# JSON routes
# -----------

def json_str(s: String) -> String:
  "\"" ++ s ++ "\""

def field(key: String, value: String) -> String:
  json_str(key) ++ ":" ++ value

def json_bool(b: Bool) -> String:
  match b:
    case True{}:
      "true"
    case False{}:
      "false"

def task(id: U32, title: String, done: Bool) -> String:
  "{" ++ field("id", U32.show(id)) ++ "," ++ field("title", json_str(title)) ++ "," ++ field("done", json_bool(done)) ++ "}"

def stats.fin(now: Nat) -> IO(Air.Response()):
  IO.pure(Air.Response(), Air.Response.json(
    "{" ++ field("server", json_str("air")) ++ ","
        ++ field("bend", json_str("2.0.10")) ++ ","
        ++ field("uptime_ms", Nat.show(now)) ++ ","
        ++ field("requests_per_conn", "100000") ++ ","
        ++ field("max_body", "1048576") ++ "}"))

def stats(req: Air.Request()) -> IO(Air.Response()):
  IO.bind(Nat, Air.Response(), IO.now(), stats.fin)

def tasks(req: Air.Request()) -> IO(Air.Response()):
  IO.pure(Air.Response(), Air.Response.json(
    "[" ++ task(1, "Parse the request line", True{}) ++ ","
        ++ task(2, "Decode chunked bodies", True{}) ++ ","
        ++ task(3, "Serve a page with Tailwind", True{}) ++ ","
        ++ task(4, "Percent-decode paths", True{}) ++ ","
        ++ task(5, "Static file middleware", False{}) ++ "]"))

def greet(req: Air.Request()) -> IO(Air.Response()):
  IO.pure(Air.Response(), Air.Response.json(
    "{" ++ field("greeting", json_str("Hello, " ++ Air.Request.param(req, "name") ++ "!")) ++ "}"))

# Echoes the JSON body back, wrapped. No JSON parser yet, so the body is
# returned as it came.
def echo(req: Air.Request()) -> IO(Air.Response()):
  IO.pure(Air.Response(), Air.Response.json(
    "{" ++ field("received", Air.Request.body(req)) ++ "}"))

# Flips the server's stop switch: no new connections are accepted, the
# requests in flight finish, and `main` goes on to exit.
def shutdown(switch: Air.Switch(), req: Air.Request()) -> IO(Air.Response()):
  do IO<Air.Response()>:
    Air.Switch.flip(switch)
    return Air.Response.json("{" ++ field("stopping", "true") ++ "}")

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
# hands it over, so a route can stop the server.
def app(switch: Air.Switch(), req: Air.Request()) -> IO(Air.Response()):
  Air.dispatch(routes(switch), req)

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
