import Base
import ../air.bend as Air
import ../examples/hello/app.bend as Hello

# Tests for examples/hello
# ========================
#
# Runs the hello app in-process with `Air.Test`: no socket, no port.
# `bend tests/hello.bend` prints one `ok` or `not ok` line per check
# and exits 1 if any failed. The ticks check takes about five seconds:
# the producer sleeps a second between events.

# A response in one line, "200 body", so status and body are one check.
def summary(+res: Air.Response()) -> String:
  U32.show(Air.Response.status(res)) ++ " " ++ Air.Response.body(res)

# The status and one header, "405 GET, HEAD, OPTIONS".
def with_header(+res: Air.Response(), name: String) -> String:
  U32.show(Air.Response.status(res)) ++ " " ++ Air.Response.header(res, name)

def run(raw: String) -> IO(Air.Response()):
  Air.Test.inject(Hello.app, raw)

# Routing and handlers
# --------------------

def greets() -> IO(Bool):
  IO.bind(Air.Response(), Bool, run(Air.Test.get("/hello/ada")),
    res => Air.Test.expect("GET /hello/:name greets", summary(res), "200 Olá, ada!"))

def not_found() -> IO(Bool):
  IO.bind(Air.Response(), Bool, run(Air.Test.get("/nope")),
    res => Air.Test.expect("unknown path is a plain 404", summary(res), "404 Not Found"))

def not_allowed() -> IO(Bool):
  IO.bind(Air.Response(), Bool, run(Air.Test.post("/hello/ada", "text/plain", "x")),
    res => Air.Test.expect("POST on a GET route is 405 with allow", with_header(res, "allow"), "405 GET, HEAD, OPTIONS"))

def echoes() -> IO(Bool):
  IO.bind(Air.Response(), Bool, run(Air.Test.post("/echo", "text/plain", "héllo")),
    res => Air.Test.expect("POST /echo returns the body", summary(res), "200 héllo"))

def form() -> IO(Bool):
  IO.bind(Air.Response(), Bool, run(Air.Test.post("/form", "application/x-www-form-urlencoded", "name=a+b")),
    res => Air.Test.expect("urlencoded form is decoded", summary(res), "200 Olá, a b!"))

def escapes.fin(+body: String) -> IO(Bool):
  Air.Test.expect_true("template escapes the name", String.contains(body, "Hello, &lt;x&gt;"), body)

def escapes() -> IO(Bool):
  IO.bind(Air.Response(), Bool, run(Air.Test.get("/page/%3Cx%3E")), res => escapes.fin(Air.Response.body(res)))

# Middleware
# ----------

def unauthorized() -> IO(Bool):
  IO.bind(Air.Response(), Bool, run(Air.Test.get("/admin/whoami")),
    res => Air.Test.expect("admin without a token is 401", summary(res), "401 Unauthorized"))

def authorized() -> IO(Bool):
  IO.bind(Air.Response(), Bool, run(Air.Test.with_header("x-token", "secret", Air.Test.get("/admin/whoami"))),
    res => Air.Test.expect("admin with the token sees the local", summary(res), "200 you are victor"))

def id_shape(+id: String) -> Bool:
  Bool.and(U32.is_eq(U32.from_nat(String.length(id)), 16), Bool.not(String.contains(id, " ")))

def request_id() -> IO(Bool):
  IO.bind(Air.Response(), Bool, run(Air.Test.get("/")),
    res => Air.Test.expect_true("x-request-id is 16 characters", id_shape(Air.Response.header(res, "x-request-id")), "no id"))

def kept_id() -> IO(Bool):
  IO.bind(Air.Response(), Bool, run(Air.Test.with_header("x-request-id", "abc-123", Air.Test.get("/"))),
    res => Air.Test.expect("a safe client id is kept", Air.Response.header(res, "x-request-id"), "abc-123"))

# Shared state
# ------------

def visits(store: Air.Store()) -> IO(Bool):
  +store = store
  do IO<Bool>:
    a : Air.Response() <- Air.Test.inject_shared(Hello.app, store, Air.Test.get("/visits"))
    b : Air.Response() <- Air.Test.inject_shared(Hello.app, store, Air.Test.get("/visits"))
    Air.Test.expect("the store counts across requests", Air.Response.body(a) ++ "," ++ Air.Response.body(b), "1,2")

# Sends `n` requests to /limited and answers the last response.
def hit(n: Nat, +store: Air.Store(), last: Air.Response()) -> IO(Air.Response()):
  match n:
    case 0n:
      IO.pure(Air.Response(), last)
    case 1n+p:
      IO.bind(Air.Response(), Air.Response(), Air.Test.inject_shared(Hello.app, store, Air.Test.get("/limited")), r => hit(p, store, r))

def limited.fin(+res: Air.Response()) -> IO(Bool):
  Air.Test.expect_true("the sixth request in the window is 429 with retry-after",
    Bool.and(U32.is_eq(Air.Response.status(res), 429), Bool.not(String.is_empty(Air.Response.header(res, "retry-after")))),
    summary(res))

def limited(store: Air.Store()) -> IO(Bool):
  IO.bind(Air.Response(), Bool, hit(6n, store, Air.Response.text("")), r => limited.fin(r))

# Refusals
# --------

def too_big() -> IO(Bool):
  IO.bind(Air.Response(), Bool, run(Air.Test.with_header("x-big", String.repeat("a", 17000n), Air.Test.get("/"))),
    res => Air.Test.expect("a head over 16 KiB is refused with 431", summary(res), "431 Request Header Fields Too Large"))

def bad_head() -> IO(Bool):
  IO.bind(Air.Response(), Bool, run("GET /\r\n\r\n"),
    res => Air.Test.expect_u32("a request line without a version is 400", Air.Response.status(res), 400))

# Streams
# -------

def ticks_want() -> String:
  Air.Sse.event("tick", "5") ++ Air.Sse.event("tick", "4") ++ Air.Sse.event("tick", "3")
    ++ Air.Sse.event("tick", "2") ++ Air.Sse.event("tick", "1")

def ticks.fin(+res: Air.Response()) -> IO(Bool):
  IO.bind(String, Bool, Air.Test.body(res),
    body => Air.Test.expect("SSE sends five ticks", Air.Response.header(res, "content-type") ++ "\n" ++ body,
      "text/event-stream\n" ++ ticks_want()))

def ticks() -> IO(Bool):
  IO.bind(Air.Response(), Bool, run(Air.Test.get("/ticks")), r => ticks.fin(r))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Bool <- greets()
    b : Bool <- not_found()
    c : Bool <- not_allowed()
    d : Bool <- echoes()
    e : Bool <- form()
    f : Bool <- escapes()
    g : Bool <- unauthorized()
    h : Bool <- authorized()
    i : Bool <- request_id()
    j : Bool <- kept_id()
    counter : Air.Store() <- Air.Store.new()
    k : Bool <- visits(counter)
    bucket : Air.Store() <- Air.Store.new()
    l : Bool <- limited(bucket)
    m : Bool <- too_big()
    n : Bool <- bad_head()
    o : Bool <- ticks()
    Air.Test.finish([a, b, c, d, e, f, g, h, i, j, k, l, m, n, o])
