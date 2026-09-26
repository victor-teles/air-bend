import Base
import ./text.bend as Text
import ./json.bend as Json
import ./http.bend as Http
import ./router.bend as Router
import ./store.bend as Store

# Health
# ======
#
# Two routes for a load balancer or an orchestrator. `/healthz` answers
# whether the process serves at all; `/readyz` whether it should get
# traffic now. Readiness is read from the store, which every request
# carries:
#
#   air/draining = "1"   set by the server when the stop switch flips
#   ready/<name> = "0"   a check the app marked down (`down`, `up`)
#
# A stopping server marks itself draining, waits `air/drain_delay`
# milliseconds (0 unless set, see `delay`) so balancers see the 503,
# then stops accepting. Checks never run inside `/readyz`: a probe that
# does I/O under load makes an outage worse. A background task marks
# them instead.

def no_store(res: Http.Response) -> Http.Response:
  Http.Response.with_header(res, "cache-control", "no-store")

def answer(+status: U32, fields: List<&2, Json.Field()>) -> Http.Response:
  no_store(Http.Response.with_status(Http.Response.of_json(Json.obj(fields)), status))

def down.add(k: String, acc: List<&2, String>, is_down: Bool) -> List<&2, String>:
  match is_down:
    case True{}:
      Con{k, acc}
    case False{}:
      acc

def down.keep(kv: Text.Two(), acc: List<&2, String>) -> List<&2, String>:
  (k, v) = kv
  down.add(k, acc, String.eq(v, "0"))

def down.go(kvs: List<&2, Text.Two()>, acc: List<&2, String>) -> List<&2, String>:
  match kvs:
    case Nil{}:
      List.reverse(&2, String, acc)
    case Con{kv, t}:
      down.go(t, down.keep(kv, acc))

# The checks marked down, in name order.
def down_checks(ready: Map<&2, String>) -> List<&2, String>:
  down.go(Map.to_list(&2, String, ready), Nil{})

def of_strs(xs: List<&2, String>) -> List<&2, Json.Value>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      Con{Json.of_str(h), of_strs(t)}

def readiness.pick(draining: Bool, failing: List<&2, String>) -> Http.Response:
  match draining failing:
    case True{} _:
      answer(503, [Json.field("status", Json.of_str("draining"))])
    case False{} Nil{}:
      answer(200, [Json.field("status", Json.of_str("ready"))])
    case False{} Con{h, t}:
      answer(503, [Json.field("status", Json.of_str("not ready")), Json.field("down", Json.arr(of_strs(Con{h, t})))])

# The `/readyz` answer from the `air/draining` flag and the `ready`
# namespace: 503 while draining or while any check is down.
def readiness(+draining: String, ready: Map<&2, String>) -> Http.Response:
  readiness.pick(String.eq(draining, "1"), down_checks(ready))

def liveness() -> Http.Response:
  answer(200, [Json.field("status", Json.of_str("ok"))])

def healthz(req: Http.Request) -> IO(Http.Response):
  IO.pure(Http.Response, liveness())

def readyz.fin(+draining: String, ready: Map<&2, String>) -> IO(Http.Response):
  IO.pure(Http.Response, readiness(draining, ready))

def readyz.go(req: Http.Request, draining: String) -> IO(Http.Response):
  +draining = draining
  IO.bind(Map<&2, String>, Http.Response, Store.read_in(req, "ready"), ready => readyz.fin(draining, ready))

def readyz(req: Http.Request) -> IO(Http.Response):
  +req = req
  IO.bind(String, Http.Response, Store.get_in(req, "air", "draining"), draining => readyz.go(req, draining))

# `GET /healthz` and `GET /readyz`; HEAD works through the GET fallback.
def routes() -> List<Router.Route>:
  [Router.get("/healthz", healthz), Router.get("/readyz", readyz)]

# Checks
# ------

def up(+store: Store.Store(), +name: String) -> IO(Unit):
  Store.set(store, "ready", name, "1")

def down(+store: Store.Store(), +name: String) -> IO(Unit):
  Store.set(store, "ready", name, "0")

def up_in(+req: Http.Request, +name: String) -> IO(Unit):
  Store.set_in(req, "ready", name, "1")

def down_in(+req: Http.Request, +name: String) -> IO(Unit):
  Store.set_in(req, "ready", name, "0")

# How long a stopping server stays up, answering `/readyz` with 503,
# before it stops accepting. 0 (the default) stops at once.
def delay(+store: Store.Store(), +ms: U32) -> IO(Unit):
  Store.set(store, "air", "drain_delay", U32.show(ms))
