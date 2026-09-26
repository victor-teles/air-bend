import Base
import ../air.bend as Air
import ../examples/dashboard/app.bend as Dashboard
import ../air/lib/text.bend as Text
import ../air/lib/trace.bend as Trace

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

def documented.fin(+res: Air.Response()) -> IO(Bool):
  +doc = Air.Response.body(res)
  Air.Test.expect_true("/openapi.json documents both task routes",
    Bool.and(U32.is_eq(Air.Response.status(res), 200),
      Bool.and(String.contains(doc, "\"/api/tasks\":{\"get\""),
        Bool.and(String.contains(doc, "\"post\":{\"operationId\":\"post_api_tasks\""),
          String.contains(doc, "\"/api/hello/{name}\"")))),
    doc)

def documented() -> IO(Bool):
  IO.bind(Air.Response(), Bool, run(Air.Test.get("/openapi.json")), res => documented.fin(res))

# Metrics
# -------

def with_header(+res: Air.Response(), name: String) -> String:
  U32.show(Air.Response.status(res)) ++ " " ++ Air.Response.header(res, name)

def metrics_lines(+body: String) -> String:
  String.join([
    Bool.show(String.contains(body, "air_http_requests_total{method=\"GET\",route=\"/api/hello/:name\",status=\"200\"} 3\n")),
    Bool.show(String.contains(body, "air_http_requests_total{method=\"DELETE\",route=\"\",status=\"405\"} 1\n")),
    Bool.show(String.contains(body, "air_http_request_duration_seconds_bucket{route=\"/api/hello/:name\",le=\"+Inf\"} 3\n")),
    Bool.show(String.contains(body, "air_http_request_duration_seconds_count{route=\"/api/hello/:name\"} 3\n"))
  ], " ")

def metrics_counted.fin(+res: Air.Response()) -> IO(Bool):
  Air.Test.expect("/metrics counts by route pattern",
    with_header(res, "content-type") ++ " " ++ metrics_lines(Air.Response.body(res)),
    "200 text/plain; version=0.0.4; charset=utf-8 True True True True")

# Three hits on one route and a miss, then a scrape: the route's
# counter, `+Inf` bucket and `_count` agree, and the miss (a DELETE no
# route takes: GET has the page catch-all) is `route=""`.
def metrics_counted.go(sw: Air.Switch(), store: Air.Store()) -> IO(Bool):
  +sw = sw
  +store = store
  do IO<Bool>:
    a : Air.Response() <- Air.Test.inject_shared(Dashboard.app(sw), store, Air.Test.get("/api/hello/a"))
    b : Air.Response() <- Air.Test.inject_shared(Dashboard.app(sw), store, Air.Test.get("/api/hello/b"))
    c : Air.Response() <- Air.Test.inject_shared(Dashboard.app(sw), store, Air.Test.get("/api/hello/c"))
    d : Air.Response() <- Air.Test.inject_shared(Dashboard.app(sw), store, "DELETE /nope HTTP/1.1\r\nhost: test\r\n\r\n")
    res : Air.Response() <- Air.Test.inject_shared(Dashboard.app(sw), store, Air.Test.get("/metrics"))
    metrics_counted.fin(res)

def metrics_counted() -> IO(Bool):
  do IO<Bool>:
    sw : Air.Switch() <- Air.Switch.new()
    store : Air.Store() <- Air.Store.new()
    metrics_counted.go(sw, store)

# Tracing
# -------
#
# `/trace` answers its trace locals, one per line: `traceparent`,
# `trace_id`, `parent_id`, `span_id`.

def valid(+tp: String) -> String:
  Bool.show(Bool.not(Maybe.is_none(&2, Trace.Parent, Trace.parse(tp))))

def trace_view(lines: List<&2, String>) -> String:
  match lines:
    case Con{+tp, Con{+trace_id, Con{parent_id, Con{+span_id, Nil{}}}}}:
      String.join([
        valid(tp),
        Bool.show(String.eq(tp, "00-" ++ trace_id ++ "-" ++ span_id ++ "-01")),
        trace_id,
        "parent=" ++ parent_id
      ], " ")
    case _:
      "malformed"

def view(+res: Air.Response()) -> String:
  trace_view(Text.split_all(Air.Response.body(res), '\n'))

def traceparent(value: String, raw: String) -> String:
  Air.Test.with_header("traceparent", value, raw)

# A valid header: same trace, the caller's span as parent, a new span.
def trace_continued() -> IO(Bool):
  IO.bind(Air.Response(), Bool, run(traceparent("00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01", Air.Test.get("/trace"))),
    res => Air.Test.expect("a valid traceparent is continued", view(res),
      "True True 4bf92f3577b34da6a3ce929d0e0e4736 parent=00f067aa0ba902b7"))

def fresh(+view: String) -> Bool:
  Bool.and(String.contains(view, "True True "), String.contains(view, " parent="))

def trace_fresh.fin(+view: String) -> IO(Bool):
  Air.Test.expect_true("no traceparent starts a sampled root", Bool.and(fresh(view), String.ends_with(view, "parent=")), view)

def trace_fresh() -> IO(Bool):
  IO.bind(Air.Response(), Bool, run(Air.Test.get("/trace")), res => trace_fresh.fin(view(res)))

# An all-zero trace id is invalid: a new trace, not the zero one.
def trace_invalid.fin(+view: String) -> IO(Bool):
  Air.Test.expect_true("an invalid traceparent starts a new trace",
    Bool.and(Bool.and(fresh(view), String.ends_with(view, "parent=")), Bool.not(String.contains(view, "00000000000000000000000000000000"))), view)

def trace_invalid() -> IO(Bool):
  IO.bind(Air.Response(), Bool, run(traceparent("00-00000000000000000000000000000000-00f067aa0ba902b7-01", Air.Test.get("/trace"))),
    res => trace_invalid.fin(view(res)))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Bool <- creates()
    b : Bool <- rejects()
    c : Bool <- not_json()
    d : Bool <- bad_query()
    e : Bool <- limit()
    f : Bool <- static()
    g : Bool <- json_404()
    h : Bool <- documented()
    i : Bool <- metrics_counted()
    j : Bool <- trace_continued()
    k : Bool <- trace_fresh()
    l : Bool <- trace_invalid()
    Air.Test.finish([a, b, c, d, e, f, g, h, i, j, k, l])
