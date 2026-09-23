import Base
import ../air.bend as Air
import ../examples/dashboard/app.bend as Dashboard

# Tests for examples/dashboard
# ============================
#
# Runs the dashboard app in-process with `Air.Test`. Run from the repo
# root, `bend tests/dashboard.bend`: static files are looked up under
# `public/` and then `examples/dashboard/public/`, both relative to the
# working directory. Exits 1 if any check failed.

def summary(+res: Air.Response()) -> String:
  U32.show(Air.Response.status(res)) ++ " " ++ Air.Response.body(res)

# The app takes the stop switch; no test flips it.
def run(raw: String) -> IO(Air.Response()):
  IO.bind(Air.Switch(), Air.Response(), Air.Switch.new(), sw => Air.Test.inject(Dashboard.app(sw), raw))

def post_json(target: String, body: String) -> String:
  Air.Test.post(target, "application/json", body)

def creates() -> IO(Bool):
  IO.bind(Air.Response(), Bool, run(post_json("/api/tasks", "{\"title\":\"x\",\"done\":false}")),
    res => Air.Test.expect("a valid task is created", summary(res), "201 {\"id\":8,\"task\":{\"title\":\"x\",\"done\":false}}"))

def rejects() -> IO(Bool):
  IO.bind(Air.Response(), Bool, run(post_json("/api/tasks", "{\"title\":5,\"extra\":1}")),
    res => Air.Test.expect("an invalid task is 422 with every error",
      summary(res),
      "422 {\"status\":422,\"error\":\"Unprocessable Content\",\"errors\":[\"title: expected string\",\"missing: done\",\"unknown: extra\"]}"))

def not_json() -> IO(Bool):
  IO.bind(Air.Response(), Bool, run(post_json("/api/tasks", "nope")),
    res => Air.Test.expect_u32("a body that is not JSON is 400", Air.Response.status(res), 400))

def bad_query() -> IO(Bool):
  IO.bind(Air.Response(), Bool, run(Air.Test.get("/api/tasks?limit=abc")),
    res => Air.Test.expect_u32("?limit=abc is 422", Air.Response.status(res), 422))

def limit.fin(+body: String) -> IO(Bool):
  Air.Test.expect_true("?limit=2 answers two tasks",
    Bool.and(String.contains(body, "\"id\":2"), Bool.not(String.contains(body, "\"id\":3"))), body)

def limit() -> IO(Bool):
  IO.bind(Air.Response(), Bool, run(Air.Test.get("/api/tasks?limit=2")), res => limit.fin(Air.Response.body(res)))

def static.fin(+res: Air.Response()) -> IO(Bool):
  Air.Test.expect_true("a static file is served with an etag",
    Bool.and(U32.is_eq(Air.Response.status(res), 200), Bool.not(String.is_empty(Air.Response.header(res, "etag")))),
    U32.show(Air.Response.status(res)))

def static() -> IO(Bool):
  IO.bind(Air.Response(), Bool, run(Air.Test.get("/app.js")), res => static.fin(res))

def json_404() -> IO(Bool):
  IO.bind(Air.Response(), Bool, run(Air.Test.get("/api/nope")),
    res => Air.Test.expect("an unknown API path is a JSON 404", summary(res), "404 {\"status\":404,\"error\":\"Not Found\"}"))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Bool <- creates()
    b : Bool <- rejects()
    c : Bool <- not_json()
    d : Bool <- bad_query()
    e : Bool <- limit()
    f : Bool <- static()
    g : Bool <- json_404()
    Air.Test.finish([a, b, c, d, e, f, g])
