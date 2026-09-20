# Air

A web framework for [Bend](https://bend-lang.com). 

```python
import Base
import ./air.bend as Air

def greet(req: Air.Request()) -> IO(Air.Response()):
  IO.pure(Air.Response(), Air.Response.text("hi " ++ Air.Request.param(req, "name")))

def routes() -> List<Air.Route()>:
  [Air.Route.get("/hello/:name", greet)]

def app(req: Air.Request()) -> IO(Air.Response()):
  Air.dispatch(routes(), req)

def main() -> IO(Unit):
  Air.serve(~app, 8080)
```

```
bend examples/hello/main.bend
curl localhost:8080/hello/world
```

## Middleware

A middleware is a def with the next handler first. It runs code before
and after `next`, or answers without calling it, which ends the chain.

```python
def timing(next: Air.Handler(), req: Air.Request()) -> IO(Air.Response()):
  +req = req
  do IO<Air.Response()>:
    before : Nat <- IO.now()
    res : Air.Response() <- next(req)
    ...log the elapsed time, return res...

def auth(+token: String, next: Air.Handler(), req: Air.Request()) -> IO(Air.Response()):
  ...call next(Air.Request.with_local(req, "user", name)) or answer 401...
```

`Air.use([timing], base)` wraps the whole app, the first in the list
outermost. `Air.Route.wrap(~auth("secret"), admin())` wraps a group; the
middleware there is a template argument, so it must be a def or a def
applied to constants. A single route takes `auth("secret")(handler)`.
Middleware leaves values for handlers with `Air.Request.with_local`, read
with `Air.Request.local`. See `examples/hello/main.bend`.

## Errors

Bend has no exceptions, so an error is a value a handler returns:

```python
def show(req: Air.Request()) -> IO(Air.Response()):
  Air.fail(Air.Error.not_found("no such user"))
```

`Air.on_error(render)` is the middleware that turns it into the response
the client sees. Two renderers ship: `Air.Error.plain(env)` for text and
`Air.Error.json(env)` for `{"status":404,"error":"Not Found"}`. The
router's own 404 and 405 pass through it too. With `AIR_ENV=dev` (read
by `Air.Env.from_env()`) they add the route and the detail; in prod the
detail never leaves the process, and an app without `on_error` gets the
same prod rendering from the server.

A fallible effect in a handler goes through `Air.attempt`, which turns
its failure into a 500 with the message as detail. Never `IO.try` or
`IO.die` in a handler: both end the process, and nothing can catch them.
A runtime crash cannot be caught either.

The server's own refusals (a bad request line, a limit, the 503 on
timeout) happen before the app runs and do not pass through `on_error`.
A response cannot be sent twice: a handler returns one value and the
server owns the socket, so there is no guard to add.

## Not yet

- Signals: Bend 2.0.10 has none, so a server stops from inside the process
  (a route, a timer), not from `kill`. Bend also cannot cancel an effect, so
  a timeout ends the request but not the receive under it: the socket of a
  client that goes silent is closed when the client next sends or hangs up,
  and until then it holds a descriptor. Bound it at a proxy if that matters.
  A connection is closed after 100000 requests.
- TLS: not planned in Air. Terminate it at a proxy (nginx, Caddy) and run
  Air on localhost behind it.
- Static files, and handlers that share state.
- Bodies are decoded as UTF-8 text by the runtime's `TCP.recv`. A
  multi-byte character split across two receives comes through as
  replacement characters, so binary uploads are not yet safe.

## Benchmarks

`bench/run.sh` compares a native build of the example against a Node server
with the same routes. See `bench/README.md` for the tool and current numbers.

## Checks

`bend PROOF.bend` proves the laws in `LAWS.bend`. It must print
"All terms check." before a commit.
