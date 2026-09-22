import Base
import ./text.bend as Text
import ./http.bend as Http
import ./router.bend as Router

# Cors
# ====
#
# Cross-origin resource sharing as one middleware. A request with no
# `Origin`, or one the config does not allow, passes through untouched
# and the browser enforces. A preflight (`OPTIONS` with
# `Access-Control-Request-Method`) is answered here, 204, and never
# reaches the router; any other allowed request runs and its response
# gets the CORS headers.

# `origins` empty means any origin. `methods`, `headers` and `expose` are
# comma lists as they go on the wire; `headers` empty means "echo what
# the preflight asks for".
type Cors is Data:
  Cors{origins: List<&2, String>, methods: String, headers: String, expose: String, credentials: Bool, max_age: U32}

# Every origin; the usual methods; no credentials; ten minutes of cache.
def any() -> Cors:
  Cors{Nil{}, "GET, HEAD, POST, PUT, PATCH, DELETE, OPTIONS", SNil{}, SNil{}, False{}, 600}

# Exactly these origins, matched byte for byte: "https://app.example.com".
def new(origins: List<&2, String>) -> Cors:
  Cors{origins, "GET, HEAD, POST, PUT, PATCH, DELETE, OPTIONS", SNil{}, SNil{}, False{}, 600}

def with_methods(c: Cors, methods: String) -> Cors:
  match c:
    case Cors{o, m, h, e, cr, a}:
      Cors{o, methods, h, e, cr, a}

def with_headers(c: Cors, headers: String) -> Cors:
  match c:
    case Cors{o, m, h, e, cr, a}:
      Cors{o, m, headers, e, cr, a}

def with_expose(c: Cors, expose: String) -> Cors:
  match c:
    case Cors{o, m, h, e, cr, a}:
      Cors{o, m, h, expose, cr, a}

def with_credentials(c: Cors, on: Bool) -> Cors:
  match c:
    case Cors{o, m, h, e, cr, a}:
      Cors{o, m, h, e, on, a}

def with_max_age(c: Cors, seconds: U32) -> Cors:
  match c:
    case Cors{o, m, h, e, cr, a}:
      Cors{o, m, h, e, cr, seconds}

# Deciding
# --------

def listed(origins: List<&2, String>, +origin: String, found: Bool) -> Bool:
  match origins found:
    case _ True{}:
      True{}
    case Nil{} False{}:
      False{}
    case Con{h, t} False{}:
      listed(t, origin, String.eq(h, origin))

def allowed.go(origins: List<&2, String>, +origin: String) -> Bool:
  match origins:
    case Nil{}:
      True{}
    case Con{h, t}:
      listed(Con{h, t}, origin, False{})

# Whether `origin` may call: any when the list is empty, else listed.
def allowed(c: Cors, +origin: String) -> Bool:
  match c:
    case Cors{o, m, h, e, cr, a}:
      allowed.go(o, origin)

def origin_value.go(+origin: String, star: Bool) -> String:
  match star:
    case True{}:
      "*"
    case False{}:
      origin

# What `Access-Control-Allow-Origin` says: `*` for any origin without
# credentials, since browsers refuse `*` with credentials; else the
# request's origin echoed back.
def origin_value(c: Cors, +origin: String) -> String:
  match c:
    case Cors{o, m, h, e, cr, a}:
      origin_value.go(origin, Bool.and(List.is_empty(&2, String, o), Bool.not(cr)))

# A preflight is OPTIONS with a requested method.
def is_preflight(+req: Http.Request) -> Bool:
  Bool.and(
    Http.Method.is_eq(Http.Request.method(req), Http.OPTIONS{}),
    Text.non_empty(Http.Request.header(req, "access-control-request-method")))

# Decorating
# ----------

def add_vary.go(r: Http.Response, +vary: String, has: Bool) -> Http.Response:
  match has:
    case True{}:
      r
    case False{}:
      Http.Response.with_header(r, "vary", Bool.pick(String, String.is_empty(vary), "origin", vary ++ ", origin"))

# `Vary: origin`, appended to an existing `Vary` that lacks it, so a
# cache never serves one origin's answer to another.
def add_vary(r: Http.Response) -> Http.Response:
  +r = r
  +vary = Http.Response.header(r, "vary")
  add_vary.go(r, vary, Text.has_token(vary, "origin"))

def when_set(r: Http.Response, +name: String, +value: String) -> Http.Response:
  match value:
    case SNil{}:
      r
    case SCon{h, t}:
      Http.Response.with_header(r, name, SCon{h, t})

def when_on(r: Http.Response, +name: String, +value: String, on: Bool) -> Http.Response:
  match on:
    case True{}:
      Http.Response.with_header(r, name, value)
    case False{}:
      r

# The headers every allowed response carries, from the config's fields.
def decorate.go(origins: List<&2, String>, +expose: String, +credentials: Bool, +origin: String, r: Http.Response) -> Http.Response:
  add_vary(
    when_set(
      when_on(
        Http.Response.with_header(r, "access-control-allow-origin",
          origin_value.go(origin, Bool.and(List.is_empty(&2, String, origins), Bool.not(credentials)))),
        "access-control-allow-credentials", "true", credentials),
      "access-control-expose-headers", expose))

def decorate(c: Cors, +origin: String, r: Http.Response) -> Http.Response:
  match c:
    case Cors{o, m, h, e, cr, a}:
      decorate.go(o, e, cr, origin, r)

def allow_headers(+configured: String, +asked: String) -> String:
  match configured:
    case SNil{}:
      asked
    case SCon{h, t}:
      SCon{h, t}

# The 204 that answers a preflight: the allowed methods, the allowed
# headers (the config's, else the ones the browser asks for), the cache
# time, and the headers of `decorate`.
def preflight(c: Cors, +origin: String, +req: Http.Request) -> Http.Response:
  match c:
    case Cors{o, m, h, e, cr, a}:
      decorate.go(o, e, cr, origin,
        Http.Response.with_header(
          when_set(
            Http.Response.with_header(Http.Response.empty(204), "access-control-allow-methods", m),
            "access-control-allow-headers", allow_headers(h, Http.Request.header(req, "access-control-request-headers"))),
          "access-control-max-age", U32.show(a)))

# The middleware
# --------------

type Mode is Data:
  Skip{}
  Preflight{}
  Simple{}

def mode.go(+req: Http.Request, allowed: Bool) -> Mode:
  match allowed:
    case False{}:
      Skip{}
    case True{}:
      Bool.pick(Mode, is_preflight(req), Preflight{}, Simple{})

def mode(c: Cors, +origin: String, +req: Http.Request) -> Mode:
  match origin:
    case SNil{}:
      Skip{}
    case SCon{h, t}:
      mode.go(req, allowed(c, SCon{h, t}))

def decorated(c: Cors, +origin: String, r: Http.Response) -> IO(Http.Response):
  IO.pure(Http.Response, decorate(c, origin, r))

def run(c: Cors, +origin: String, next: Router.Handler(), +req: Http.Request, m: Mode) -> IO(Http.Response):
  match m:
    case Skip{}:
      next(req)
    case Preflight{}:
      IO.pure(Http.Response, preflight(c, origin, req))
    case Simple{}:
      IO.bind(Http.Response, Http.Response, next(req), decorated(c, origin))

# `cors(cfg)` is a middleware: put it in `use` outside `on_error`, so an
# error response gets the headers too.
def cors(c: Cors, next: Router.Handler(), req: Http.Request) -> IO(Http.Response):
  +c = c
  +req = req
  +origin = Http.Request.header(req, "origin")
  run(c, origin, next, req, mode(c, origin, req))
