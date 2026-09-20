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

def routes() -> List<Air.Route()>:
  [
    Air.Route.get("/", home),
    Air.Route.get("/hello/:name", greet),
    Air.Route.get("/search", search),
    Air.Route.post("/echo", echo)
  ]

def app(req: Air.Request()) -> IO(Air.Response()):
  Air.dispatch(routes(), req)

def main() -> IO(Unit):
  do IO<Unit>:
    Air.Route.check(routes())
    Air.serve(~app, 8080)
