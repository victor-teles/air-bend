# Air

A web framework for [Bend](https://bend-lang.com). Routing, path params,
query strings, headers and bodies, over Bend's own TCP effects. The server
speaks HTTP/1.1: keep-alive and pipelining, Content-Length and chunked
bodies, `Expect: 100-continue`, and the no-body rules for HEAD, 204 and 304.
Every phase of a request runs under a timeout, and a server can be stopped
gracefully from a route.

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

## Examples

Each folder under `examples/` is a project of its own:

- `examples/hello/`: the four-route starter above.
- `examples/dashboard/`: an HTML page with JavaScript and Tailwind, served
  from disk, with JSON routes behind it. `bend examples/dashboard/main.bend`
  and open http://localhost:8080.

## API

- `Air.serve(~app, port)`: listens forever. Each connection is its own
  computation, so a slow client never blocks the others. Connections stay
  open between requests unless a side says `Connection: close` (or the
  request is HTTP/1.0 and does not ask for keep-alive).
- `Air.serve_with(~app, limits, port)`: the same under your own
  `Air.Limits.new(head, headers, url, body)`, byte caps on the request head, the
  number of header lines, the URL and the body. The defaults are 16 KiB, 100,
  8 KiB and 1 MiB; past them the server answers 431, 431, 414 or 413.
- `Air.serve_until(~app, limits, timeouts, switch, port)`: serves until
  `switch` (from `Air.Switch.new()`) is flipped with `Air.Switch.flip`, then
  stops accepting, waits up to the drain timeout for the requests in flight,
  and returns. Here `app` is `Switch -> Request -> IO(Response)`: the server
  hands the switch to the app, so a route can flip it. Connections idle
  between requests are not waited for; `Air.exit(code)` ends the process and
  closes them with it.
- `Air.Timeouts.new(idle, head, body, app, send, drain)`: milliseconds, 0 for
  no limit. `idle` bounds the wait for a request on an open connection,
  `head` the request line and headers from their first byte, `body` the body,
  `app` the handler, `send` the write of the response, and `drain` the wait
  at shutdown. The defaults are 15 s, 10 s, 30 s, 30 s, 30 s and 10 s. A phase
  that runs out of time closes the connection; the app's timeout answers 503
  first. `serve` and `serve_with` use the defaults.
- `Air.dispatch(routes, req)`: runs the first matching route. A HEAD
  request runs the GET route when no HEAD route matches, and the server
  drops the body. A path that matches only under other methods answers 405
  with an `Allow` header; OPTIONS on such a path answers 204 with `Allow`
  unless a route claims it, and `OPTIONS *` lists every method the app
  serves. Nothing matching answers 404. Routes are tried in order, so put
  the specific one first.
- `Air.dispatch_with(policy, routes, req)`: the same under a trailing-slash
  policy. `Air.Slash.ignore()` (what `dispatch` uses) treats `/a/` and `/a`
  as the same path. `Air.Slash.strict()` matches a route only when it and
  the request agree on the slash. `Air.Slash.redirect()` answers 308 to the
  path without the slash, query kept; `/` is never redirected.
- `Air.Route.get / post / put / delete / patch / head / options(path, handler)`: a route.
  `:name` segments bind params; a last `*name` segment binds the rest of the
  path, joined with `/`, possibly empty. A handler is `Request -> IO(Response)`.
- `Air.Route.mount(prefix, routes)`: prefixes every route, so `/users/:id`
  under `/api` is `/api/users/:id`. `Air.Route.all([group, group])` joins
  groups in order.
- `Air.Route.check(routes)`: run it in `main` before serving. It prints every
  duplicate (same method and shape, `:` and `*` names aside) and every
  wildcard that is not last, then ends the process with code 1. Without it a
  duplicate would shadow the later route silently. Give it its own
  `routes()`: a route list is consumed by whatever walks it.
- `Air.Request.method / version / path / target / body / header(req, name) /
  query(req, key) / param(req, key)`: accessors. `path` is the normal form
  described under Paths; `target` is the request-target as received. Header
  names are case-insensitive; a repeated header reads as its values joined
  with ", ". Query values are percent-decoded, with `+` as a space.
- `Air.Response.text / html / json(body)`: a 200 with a content type.
  `with_status`, `with_header`, `empty(code)`, `redirect(url)`, `not_found()`,
  `method_not_allowed(allow)`, `options(allow)`.

Handlers are affine closures, so `routes()` is called once per request. That
is deliberate: it is what lets a handler run again for the next request.

## Framing

Bodies are read by `Content-Length` or `Transfer-Encoding: chunked`. A
request that carries both, repeats `Content-Length`, gives a non-numeric
length, folds a header over two lines, or asks for any other transfer
encoding is refused (400 or 501) and its connection closed, because those
are the shapes request smuggling takes. Bytes after one request's body are
the start of the next, so pipelined clients work.

Responses to HEAD requests, and responses with a 1xx, 204 or 304 status,
are sent without a body. 204 and 1xx also omit `Content-Length`.

## Paths

A route sees the path in one normal form: an absolute-form target
(`GET http://host/x`) loses its scheme and authority, each segment is
percent-decoded, `.` and `..` are resolved, repeated slashes collapse, and a
trailing slash is kept. So `/hello/Ol%C3%A1` reaches a handler as
`/hello/Olá`, and `/a/./b/../c` as `/a/c`. Decoding happens after the split
on `/`, so `%2F` yields a `/` inside its segment; Air does not treat it as a
segment boundary that survives routing. A malformed or truncated escape, an
escaped NUL, an invalid, overlong or surrogate UTF-8 sequence, or a `..`
that climbs above the root answers 400 and closes the connection. `OPTIONS *`
keeps `*` as its path. `Air.Request.target` has the raw form.

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
