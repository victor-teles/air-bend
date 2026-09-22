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

## Request ids and logging

`Air.request_id` gives every request an id, the client's `X-Request-Id`
when it is safe to print (letters, digits, `-`, `_`, `.`; up to 128) or
16 hex characters from a random word and the millisecond it started,
and returns it as `x-request-id`. Handlers
read it with `Air.Request.id`. `Air.log`, placed inside it, prints one
JSON line per request:

```
{"ts":5161,"id":"a9bf17ed00001429","method":"GET","path":"/","status":200,"ms":1}
```

`ts` counts milliseconds since the process started: Bend has no wall
clock, so a log shipper adds the date. The server prints its own line
only for what the app never sees: a bad request line, a limit, the 503
on a timeout.

## Shared state

Bend has no globals, and the app is a template argument that must be a
closed term, so state cannot be threaded in from `main`. Instead every
request carries the server's store: namespaces of string maps behind a
lock, reached through the request.

```python
def visits(req: Air.Request()) -> IO(Air.Response()):
  IO.bind(U32, Air.Response(), Air.Store.incr(req, "app", "visits"), n => ...)
```

`Air.Store.get`, `set`, `incr`, `read`, `drop`, and `update`, which
replaces a namespace with a pure function of it and answers the result.
Taking the value out is the lock, so keep that function quick: every
other request waits on it. `Air.serve_shared` takes a store made with
`Air.Store.new`, for a task outside the server that shares it. The
framework uses the namespaces `rate`, `sessions` and `session_tally`.

## Sessions

`Air.session(cfg)` gives the routes it wraps a session: a random token
in an `HttpOnly`, `SameSite=Lax` cookie names an entry in the store, and
handlers read and write fields by name. Wrap the group that needs it,
`Air.Route.wrap(~Air.session(Air.Session.default()), pages())`, rather
than the whole app: a client that never sends cookies would mint a
session per request.

```python
def count(req: Air.Request()) -> IO(Air.Response()):
  IO.bind(U32, Air.Response(), Air.Session.incr(req, "n"), n => ...)
```

`Air.Session.get`, `set`, `incr`, `fields`, `clear` (drops the data,
keeps the token) and `end` (drops the data and expires the cookie on a
response). Sessions are server-side only: Bend has no HMAC, so a cookie
cannot carry data safely, and the cookie carries the token alone. They
live in the process and end with it. A session untouched for the TTL (a
day by default) is gone, and once the store holds more than `max` of
them (ten thousand) a request sweeps the expired ones. A token that
names no live session is replaced, so a guessed or stale cookie never
attaches to data. Turn on `Air.Session.secure(cfg, True{})` behind the
TLS proxy. Keys starting with `_` are the framework's. Each session is
one JSON string in the store's `sessions` namespace, so the rest of the
store does not slow down as sessions pile up.

## Rate limiting

`Air.rate(n, window_ms, key)` is a middleware: at most `n` requests per
key per window. Over the limit the request fails with 429, `retry-after`
and the reason; every response carries `x-ratelimit-limit`,
`x-ratelimit-remaining` and `x-ratelimit-reset`. The window is fixed and
the counts start over each window, so memory is bounded by the keys seen
in one. `Air.Rate.by_ip(trust)` keys on the address a trusted proxy
reports; without one there is no client address (`TCP.accept` gives
none), so every request shares one bucket. `Air.Rate.by_header("x-api-key")`
keys on a header; a def of the app's can key on anything.

```python
Air.Route.get("/search", Air.rate(60, 60000, Air.Rate.by_ip(Air.Trust.proxy()))(search))
```

## Static files

`Air.static(dir)` is a handler for a wildcard route whose param is
`path`:

```python
Air.Route.get("/assets/*path", Air.static("public"))
```

It serves the file under `dir` with a mime from the extension, an ETag,
304 and byte ranges. A request cannot leave `dir`: a segment holding a
slash of either kind (from `%2F` or `%5C`), a `.` or `..`, or a dotfile
is a 404, the same as a missing file. A path ending in `/` serves its
`index.html`. There is no directory listing, and a symlink inside `dir`
is followed wherever it points. Files are read as UTF-8 text, so this is
for HTML, CSS, JavaScript and SVG, not images.

## CORS and security headers

Two middleware ship with Air. `Air.cors(cfg)` answers preflights and
adds `Access-Control-Allow-Origin` to responses for the origins the
policy lists; `Air.Cors.any()` allows every origin and
`Air.Cors.new(["https://app.example.com"])` an exact list. A request from
any other origin passes through untouched and the browser refuses it.
`Air.shield(hs)` adds defensive headers a handler has not set itself:
`Air.Shield.default()` covers `nosniff`, framing, referrer and
cross-origin isolation; HSTS and CSP are opt-in with `with_hsts` and
`with_csp`, since Air runs behind a TLS proxy.

```python
Air.use([Air.request_id, Air.log, Air.shield(Air.Shield.default()), Air.cors(Air.Cors.any()), Air.on_error(render)], base)
```

All go outside `on_error`, so an error response carries them too.

## Errors

Bend has no exceptions, so an error is a value a handler returns:

```python
def show(req: Air.Request()) -> IO(Air.Response()):
  Air.fail(Air.Error.not_found("no such user"))
```

`Air.on_error(render)` is the middleware that turns it into the response
the client sees. Two renderers ship: `Air.Error.plain(env)` for text and
`Air.Error.json(env)` for `{"status":404,"error":"Not Found"}`. The
router's own 404 and 405 pass through it too, and a rendered error keeps
the headers of the failure it came from, such as the `Allow` of a 405 or
a cookie a middleware set. With `AIR_ENV=dev` (read
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
- Bodies are decoded as UTF-8 text by the runtime's `TCP.recv`. A
  multi-byte character split across two receives comes through as
  replacement characters, so binary uploads are not yet safe.

## Benchmarks

`bench/run.sh` compares a native build of the example against a Node server
with the same routes. See `bench/README.md` for the tool and current numbers.

## Checks

`bend PROOF.bend` proves the laws in `LAWS.bend`. It must print
"All terms check." before a commit.
