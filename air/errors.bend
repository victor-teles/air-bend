import Base
import ./json.bend as Json
import ./http.bend as Http
import ./router.bend as Router

# Errors
# ======
#
# A handler answers `Http.Response.fail(e)`; `on_error` is the middleware
# that turns it into the response the client sees, through a renderer the
# app picks. Two renderers ship: `plain` and `json`. Both show the error's
# detail, method and path in dev only. An app without `on_error` still
# works: the server settles a failed response in prod style.

# A renderer turns an error into the response the client sees.
def Render() -> Type:
  Http.Request -> Http.Error -> Http.Response

def on_error.fin(render: Render(), req: Http.Request, res: Http.Response, err: Maybe<&2, Http.Error>) -> IO(Http.Response):
  match err:
    case None{}:
      IO.pure(Http.Response, res)
    case Some{e}:
      IO.pure(Http.Response, render(req, e))

def on_error.go(render: Render(), req: Http.Request, res: Http.Response) -> IO(Http.Response):
  +res = res
  on_error.fin(render, req, res, Http.Response.error(res))

# Runs `next`; a failed response is rendered by `render`. What `render`
# answers is final, even another failure, which the server settles.
def on_error(render: Render(), next: Router.Handler(), req: Http.Request) -> IO(Http.Response):
  +req = req
  IO.bind(Http.Response, Http.Response, next(req), on_error.go(render, req))

# Renderers
# ---------

def place(+req: Http.Request) -> String:
  Http.Method.show(Http.Request.method(req)) ++ " " ++ Http.Request.path(req)

def plain.detail(detail: String) -> String:
  match detail:
    case SNil{}:
      SNil{}
    case SCon{h, t}:
      "\n" ++ SCon{h, t}

def plain.body(reason: String, req: Http.Request, +e: Http.Error, dev: Bool) -> String:
  match dev:
    case True{}:
      reason ++ "\n" ++ place(req) ++ plain.detail(Http.Error.detail(e))
    case False{}:
      reason

# Plain text: the reason phrase; in dev, the method and path on a second
# line and the detail on a third when there is one.
def plain(+env: Http.Env, req: Http.Request, +e: Http.Error) -> Http.Response:
  +status = Http.Error.status(e)
  Http.Response.with_status(
    Http.Response.text(plain.body(Http.Status.reason(status), req, e, Http.Env.is_dev(env))),
    status)

def json.fields(+status: U32, req: Http.Request, +e: Http.Error, dev: Bool) -> List<&2, Json.Field()>:
  match dev:
    case True{}:
      [
        Json.field("status", Json.of_u32(status)),
        Json.field("error", Json.of_str(Http.Status.reason(status))),
        Json.field("detail", Json.of_str(Http.Error.detail(e))),
        Json.field("path", Json.of_str(Http.Request.path(req)))
      ]
    case False{}:
      [
        Json.field("status", Json.of_u32(status)),
        Json.field("error", Json.of_str(Http.Status.reason(status)))
      ]

# JSON: `{"status":404,"error":"Not Found"}`, plus `detail` and `path`
# in dev. Strings are escaped by the renderer.
def json(+env: Http.Env, req: Http.Request, +e: Http.Error) -> Http.Response:
  +status = Http.Error.status(e)
  Http.Response.with_status(
    Http.Response.of_json(Json.obj(json.fields(status, req, e, Http.Env.is_dev(env)))),
    status)

# Effects
# -------

def attempt.go(-A: Type, r: Result<&1, &1, U32 & String, A>, k: A -> IO(Http.Response)) -> IO(Http.Response):
  match r:
    case Done{v}:
      k(v)
    case Fail{e}:
      (code, msg) = e
      IO.pure(Http.Response, Http.Response.fail(Http.Internal{msg}))

# Runs a fallible effect: its value goes to `k`, its failure becomes a
# 500 with the message as detail. `IO.try` would end the process instead.
def attempt(-A: Type, act: IO(Result<&1, &1, U32 & String, A>), k: A -> IO(Http.Response)) -> IO(Http.Response):
  IO.bind(Result<&1, &1, U32 & String, A>, Http.Response, act, r => attempt.go(A, r, k))

# Environment
# -----------

def Env.parse(r: Result<&1, &1, U32 & String, String>) -> Http.Env:
  match r:
    case Done{v}:
      Bool.pick(Http.Env, String.eq(v, "dev"), Http.Dev{}, Http.Prod{})
    case Fail{e}:
      Http.Prod{}

# `Dev` when `AIR_ENV` is "dev"; `Prod` otherwise, including when unset.
def Env.from_env() -> IO(Http.Env):
  IO.bind(Result<&1, &1, U32 & String, String>, Http.Env, IO.get_env("AIR_ENV"), r => IO.pure(Http.Env, Env.parse(r)))
