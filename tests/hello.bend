import Base
import ../air.bend as Air
import ../examples/hello/app.bend as Hello
import ../air/lib/store.bend as Store

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

# Config
# ------
#
# These assume `GREETING` is not set in the environment, which would win
# over both.

def greeting_default() -> IO(Bool):
  IO.bind(Air.Response(), Bool, run(Air.Test.get("/config/greeting")),
    res => Air.Test.expect("GREETING defaults to Olá", summary(res), "200 Olá"))

def greeting_installed(store: Air.Store()) -> IO(Bool):
  +store = store
  do IO<Bool>:
    Air.Config.install(store, Air.Config.parse("# from a .env\nGREETING=\"Hi there\"\n"))
    res : Air.Response() <- Air.Test.inject_shared(Hello.app, store, Air.Test.get("/config/greeting"))
    Air.Test.expect("an installed .env value reaches the handler", summary(res), "200 Hi there")

# Hooks
# -----

def stamped() -> IO(Bool):
  IO.bind(Air.Response(), Bool, run(Air.Test.get("/hooks/ok")),
    res => Air.Test.expect("on_send stamps a 200", with_header(res, "x-hooked"), "200 yes"))

def stamped_failure() -> IO(Bool):
  IO.bind(Air.Response(), Bool, run(Air.Test.get("/hooks/boom")),
    res => Air.Test.expect("on_send's header survives on_error's render", with_header(res, "x-hooked"), "500 yes"))

def unhooked() -> IO(Bool):
  IO.bind(Air.Response(), Bool, run(Air.Test.get("/hello/ada")),
    res => Air.Test.expect("routes outside the group are not stamped", with_header(res, "x-hooked"), "200 "))

# `record` counts the 200 and the 500, `report` the failure; the stats
# request itself is counted after it answers.
def hook_counts(store: Air.Store()) -> IO(Bool):
  +store = store
  do IO<Bool>:
    a : Air.Response() <- Air.Test.inject_shared(Hello.app, store, Air.Test.get("/hooks/ok"))
    b : Air.Response() <- Air.Test.inject_shared(Hello.app, store, Air.Test.get("/hooks/boom"))
    c : Air.Response() <- Air.Test.inject_shared(Hello.app, store, Air.Test.get("/hooks/stats"))
    Air.Test.expect("on_response and on_fail saw both requests", Air.Response.body(c), "2xx=1 5xx=1")

def pre_handler() -> IO(Bool):
  IO.bind(Air.Response(), Bool, run(Air.Test.with_header("x-token", "secret", Air.Test.get("/admin/area"))),
    res => Air.Test.expect("on_request inside wrap sets a local the handler reads", summary(res), "200 area admin"))

# Health
# ------

def live() -> IO(Bool):
  IO.bind(Air.Response(), Bool, run(Air.Test.get("/healthz")),
    res => Air.Test.expect("/healthz is 200 ok", summary(res), "200 {\"status\":\"ok\"}"))

def ready() -> IO(Bool):
  IO.bind(Air.Response(), Bool, run(Air.Test.get("/readyz")),
    res => Air.Test.expect("/readyz is 200 on a fresh store", summary(res), "200 {\"status\":\"ready\"}"))

def as_admin(raw: String) -> String:
  Air.Test.with_header("x-token", "secret", raw)

# The demo check goes down and back up through its admin route.
def check_cycle(store: Air.Store()) -> IO(Bool):
  +store = store
  do IO<Bool>:
    a : Air.Response() <- Air.Test.inject_shared(Hello.app, store, as_admin(Air.Test.post("/admin/demo/down", "text/plain", "")))
    b : Air.Response() <- Air.Test.inject_shared(Hello.app, store, Air.Test.get("/readyz"))
    c : Air.Response() <- Air.Test.inject_shared(Hello.app, store, as_admin(Air.Test.post("/admin/demo/up", "text/plain", "")))
    d : Air.Response() <- Air.Test.inject_shared(Hello.app, store, Air.Test.get("/readyz"))
    Air.Test.expect("a down check makes /readyz 503 until it is up",
      summary(b) ++ " | " ++ summary(d),
      "503 {\"status\":\"not ready\",\"down\":[\"demo\"]} | 200 {\"status\":\"ready\"}")

# What the server's stopper writes when the switch flips.
def draining(store: Air.Store()) -> IO(Bool):
  +store = store
  do IO<Bool>:
    Store.set(store, "air", "draining", "1")
    res : Air.Response() <- Air.Test.inject_shared(Hello.app, store, Air.Test.get("/readyz"))
    Air.Test.expect("/readyz is 503 while draining", summary(res), "503 {\"status\":\"draining\"}")

# Metrics
# -------

# The router's route note is internal: `inject` settles like the server.
def unlabelled() -> IO(Bool):
  IO.bind(Air.Response(), Bool, run(Air.Test.get("/hello/ada")),
    res => Air.Test.expect("air-route never reaches the client", with_header(res, "air-route"), "200 "))

# Streaming
# ---------

# A producer of `n` one-character pieces; it stops if the reader goes.
def pieces(+n: Nat, +chan: Chan(String), ok: Bool) -> IO(Unit):
  match n ok:
    case _ False{}:
      IO.pure(Unit, Unit{})
    case 0n True{}:
      Chan.close(String, chan)
    case 1n+p True{}:
      IO.bind(Bool, Unit, Chan.send(String, chan, "x"), sent => pieces(p, chan, sent))

def narrow.start(chan: Chan(String)) -> IO(Air.Response()):
  +chan = chan
  do IO<Air.Response()>:
    IO.spawn(Unit, pieces(100n, chan, True{}))
    return Air.Response.stream(chan)

# A window of one piece: the producer waits on every send.
def narrow(req: Air.Request()) -> IO(Air.Response()):
  IO.bind(Chan(String), Air.Response(), Air.Stream.with_room(1), narrow.start)

def narrow_whole() -> IO(Bool):
  IO.bind(Air.Response(), Bool, Air.Test.inject(narrow, Air.Test.get("/")),
    res => IO.bind(String, Bool, Air.Test.body(res),
      body => Air.Test.expect("a one-piece window loses nothing", body, String.repeat("x", 100n))))

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
    p : Bool <- greeting_default()
    configured : Air.Store() <- Air.Store.new()
    q : Bool <- greeting_installed(configured)
    r : Bool <- stamped()
    t : Bool <- stamped_failure()
    u : Bool <- unhooked()
    hooks : Air.Store() <- Air.Store.new()
    v : Bool <- hook_counts(hooks)
    w : Bool <- pre_handler()
    x : Bool <- live()
    y : Bool <- ready()
    checks : Air.Store() <- Air.Store.new()
    z : Bool <- check_cycle(checks)
    stopping : Air.Store() <- Air.Store.new()
    aa : Bool <- draining(stopping)
    ab : Bool <- unlabelled()
    ah : Bool <- narrow_whole()
    Air.Test.finish([a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q, r, t, u, v, w, x, y, z, aa, ab, ah])
