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

def routes() -> List<Air.Route()>:
  [
    Air.Route.get("/", home),
    Air.Route.get("/hello/:name", greet),
    Air.Route.get("/search", search),
    Air.Route.post("/echo", echo),
    Air.Route.post("/form", form),
    Air.Route.get("/cookie/:name", cookie),
    Air.Route.get("/ticks", ticks)
  ]

def app(req: Air.Request()) -> IO(Air.Response()):
  Air.dispatch(routes(), req)

def main() -> IO(Unit):
  do IO<Unit>:
    Air.Route.check(routes())
    Air.serve(~app, 8080)
