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

## Not yet

- Signals: Bend 2.0.10 has none, so a server stops from inside the process
  (a route, a timer), not from `kill`. Bend also cannot cancel an effect, so
  a timeout ends the request but not the receive under it: the socket of a
  client that goes silent is closed when the client next sends or hangs up,
  and until then it holds a descriptor. Bound it at a proxy if that matters.
  A connection is closed after 100000 requests.
- TLS: not planned in Air. Terminate it at a proxy (nginx, Caddy) and run
  Air on localhost behind it.
- Middleware, static files, and handlers that share state.
- Bodies are decoded as UTF-8 text by the runtime's `TCP.recv`. A
  multi-byte character split across two receives comes through as
  replacement characters, so binary uploads are not yet safe.

## Benchmarks

`bench/run.sh` compares a native build of the example against a Node server
with the same routes. See `bench/README.md` for the tool and current numbers.

## Checks

`bend PROOF.bend` proves the laws in `LAWS.bend`. It must print
"All terms check." before a commit.
