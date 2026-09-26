import Base
import ./http.bend as Http
import ./router.bend as Router

# Hooks
# =====
#
# Lifecycle hooks are middleware with a name. Each takes a plain function
# rather than `next`, so it cannot forget to call the rest of the chain
# or call it twice. Where one sits in `use` or `Route.wrap` decides its
# phase:
#
#   on_request   before the handler; in `use` it sees the request before
#                routing (onRequest), inside `Route.wrap` after it, with
#                params bound (preHandler)
#   on_send      after the handler; its response is the one sent (onSend)
#   on_response  after the handler, with the milliseconds it took
#                (onResponse); before the server writes, which app code
#                never sees
#   on_fail      when the response is a failure, before a renderer
#                outside it turns it into a page (onError, observe only)
#
# A hook that must answer early (auth) is an ordinary middleware that
# does not call `next`. There is no registry of callbacks: functions
# cannot be copied in Bend, and the onion needs none.

# Runs `f` on the request and the rest of the chain on what it answers.
def on_request(f: Http.Request -> IO(Http.Request), next: Router.Handler(), req: Http.Request) -> IO(Http.Response):
  IO.bind(Http.Request, Http.Response, f(req), next)

# Runs the rest of the chain, then `f` on the request and the response;
# `f`'s response is the one sent.
def on_send(f: Http.Request -> Http.Response -> IO(Http.Response), next: Router.Handler(), req: Http.Request) -> IO(Http.Response):
  +req = req
  IO.bind(Http.Response, Http.Response, next(req), f(req))

def on_response.fin(f: Http.Request -> Http.Response -> Nat -> IO(Unit), +req: Http.Request, +res: Http.Response, ms: Nat) -> IO(Http.Response):
  do IO<Http.Response>:
    f(req, res, ms)
    return res

def on_response.go(f: Http.Request -> Http.Response -> Nat -> IO(Unit), +req: Http.Request, +before: Nat, res: Http.Response) -> IO(Http.Response):
  +res = res
  IO.bind(Nat, Http.Response, IO.now(), after => on_response.fin(f, req, res, Nat.sub(after, before)))

# Runs the rest of the chain, then `f` on the request, the response and
# the milliseconds the chain took. The response is unchanged. It runs
# before the server writes the response: a write that fails is not seen.
def on_response(f: Http.Request -> Http.Response -> Nat -> IO(Unit), next: Router.Handler(), req: Http.Request) -> IO(Http.Response):
  +req = req
  do IO<Http.Response>:
    before : Nat <- IO.now()
    res : Http.Response <- next(req)
    on_response.go(f, req, before, res)

def on_fail.fin(f: Http.Request -> Http.Error -> IO(Unit), +req: Http.Request, res: Http.Response, err: Maybe<&2, Http.Error>) -> IO(Http.Response):
  match err:
    case None{}:
      IO.pure(Http.Response, res)
    case Some{e}:
      do IO<Http.Response>:
        f(req, e)
        return res

def on_fail.go(f: Http.Request -> Http.Error -> IO(Unit), +req: Http.Request, res: Http.Response) -> IO(Http.Response):
  +res = res
  on_fail.fin(f, req, res, Http.Response.error(res))

# Runs the rest of the chain and, when its response is a failure, `f` on
# the request and the error: to count or report it. The response is
# unchanged; put this inside `on_error`, which renders it.
def on_fail(f: Http.Request -> Http.Error -> IO(Unit), next: Router.Handler(), req: Http.Request) -> IO(Http.Response):
  +req = req
  IO.bind(Http.Response, Http.Response, next(req), res => on_fail.go(f, req, res))
