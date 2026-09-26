import Base
import ./text.bend as Text
import ./http.bend as Http
import ./router.bend as Router
import ./store.bend as Store

# Metrics
# =======
#
# Request counts by method, route and status, and a latency histogram
# by route, in the Prometheus text format. `metrics` is the middleware:
# it times the rest of the chain and records one observation per
# request in the store's `metrics` namespace, under one lock. `expose`
# is the handler that renders the namespace for a scraper.
#
# The route label is the pattern the router left on the response
# (`Http.Response.route`), so `/users/7` and `/users/8` are one series.
# A request no route answered (404, 405, OPTIONS, or one a middleware
# outside dispatch answered) is labelled `route=""`. A method outside
# the seven Air knows is `OTHER`: the client picks the method, and it
# must not add series.
#
# The namespace holds, per key, a count as text:
#
#   c␉GET␉/a␉200     requests with that method, route and status
#   b␉/a␉0.05        observations whose bucket is 0.05, not cumulative
#   n␉/a             observations
#   s␉/a, m␉/a       the sum: whole seconds, and the milliseconds past them
#   a␉name           an app counter (`count`)
#
# where ␉ is a tab, which no method or route contains.

def sep() -> Char:
  '\t'

def key2(+a: String, b: String) -> String:
  a ++ SCon{sep(), b}

def counter_key(+method: String, +route: String, +status: U32) -> String:
  key2(key2(key2("c", method), route), U32.show(status))

def bucket_key(+route: String, le: String) -> String:
  key2(key2("b", route), le)

# Numbers
# -------

def pad3(+n: U32) -> String:
  Bool.pick(String, U32.is_lt(n, 10), "00" ++ U32.show(n),
    Bool.pick(String, U32.is_lt(n, 100), "0" ++ U32.show(n), U32.show(n)))

# Milliseconds as seconds with three decimals: 1503 is "1.503".
def seconds(+secs: U32, +ms: U32) -> String:
  U32.show(secs) ++ "." ++ pad3(ms)

def drop_zeros(+s: String) -> String:
  match s:
    case SCon{'0', t}:
      drop_zeros(t)
    case _:
      s

def trimmed(+whole: String, frac: String) -> String:
  match frac:
    case SNil{}:
      whole
    case SCon{h, t}:
      whole ++ "." ++ String.reverse(SCon{h, t})

# A bucket bound in milliseconds as Prometheus writes it: 5 is "0.005",
# 1000 is "1", 2500 is "2.5".
def le(+ms: U32) -> String:
  trimmed(U32.show(U32.div(ms, 1000)), drop_zeros(String.reverse(pad3(U32.mod(ms, 1000)))))

# The bucket bounds in milliseconds, the default set of Prometheus
# clients: 5 ms to 10 s, then `+Inf`.
def bounds() -> List<&2, U32>:
  [5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000, 10000]

def bucket.go(desc: List<&2, U32>, +ms: U32, acc: String) -> String:
  match desc:
    case Nil{}:
      acc
    case Con{+b, t}:
      bucket.go(t, ms, Bool.pick(String, U32.is_le(ms, b), le(b), acc))

# The `le` of the smallest bound an observation fits under.
def bucket(+ms: U32) -> String:
  bucket.go(List.reverse(&2, U32, bounds()), ms, "+Inf")

# Observing
# ---------

def label_of(+m: Http.Method) -> String:
  match m:
    case Http.Other{name}:
      "OTHER"
    case _:
      Http.Method.show(m)

# The method label: the seven known methods by name, anything else "OTHER".
def method_label(+name: String) -> String:
  label_of(Http.Method.parse(name))

def num(+m: Map<&2, String>, key: String) -> U32:
  Text.digits_or(Text.map_get(m, key, SNil{}), 0)

def bump(m: Map<&2, String>, +key: String, +by: U32) -> Map<&2, String>:
  +m = m
  Map.set(&2, String, m, key, U32.show(U32.add(num(m, key), by)))

# Adds `ms` to the route's sum, carrying whole seconds.
def add_sum(m: Map<&2, String>, +route: String, +ms: U32) -> Map<&2, String>:
  +m = m
  +total = U32.add(num(m, key2("m", route)), ms)
  bump(Map.set(&2, String, m, key2("m", route), U32.show(U32.mod(total, 1000))), key2("s", route), U32.div(total, 1000))

# One request, its method already labelled.
def record(+method: String, +route: String, +status: U32, +ms: U32, m: Map<&2, String>) -> Map<&2, String>:
  add_sum(
    bump(bump(bump(m, counter_key(method, route, status), 1), bucket_key(route, bucket(ms)), 1), key2("n", route), 1),
    route, ms)

# One request answered: its method's name, the route pattern ("" for
# none), the status and the milliseconds it took, added to `m`.
def observe(+method: String, +route: String, +status: U32, +ms: U32, m: Map<&2, String>) -> Map<&2, String>:
  record(method_label(method), route, status, ms, m)

# Rendering
# ---------

def escape.go(s: String, rev: String) -> String:
  match s:
    case SNil{}:
      String.reverse(rev)
    case SCon{'\\', t}:
      escape.go(t, SCon{'\\', SCon{'\\', rev}})
    case SCon{'"', t}:
      escape.go(t, SCon{'"', SCon{'\\', rev}})
    case SCon{'\n', t}:
      escape.go(t, SCon{'n', SCon{'\\', rev}})
    case SCon{c, t}:
      escape.go(t, SCon{c, rev})

# A label value: backslash, double quote and newline escaped.
def escape(s: String) -> String:
  escape.go(s, SNil{})

def label(+name: String, value: String) -> String:
  name ++ "=\"" ++ escape(value) ++ "\""

def counter_line(fields: List<&2, String>, +n: String) -> String:
  match fields:
    case Con{method, Con{route, Con{status, Nil{}}}}:
      "air_http_requests_total{" ++ label("method", method) ++ "," ++ label("route", route) ++ "," ++ label("status", status) ++ "} " ++ n ++ "\n"
    case _:
      SNil{}

def app_line(+name: String, +n: String) -> String:
  "# TYPE app_" ++ name ++ "_total counter\napp_" ++ name ++ "_total " ++ n ++ "\n"

def bucket_line(+route: String, +le: String, +n: U32) -> String:
  "air_http_request_duration_seconds_bucket{" ++ label("route", route) ++ "," ++ label("le", le) ++ "} " ++ U32.show(n) ++ "\n"

# The route's buckets, cumulated in bound order.
def buckets(asc: List<&2, U32>, +m: Map<&2, String>, +route: String, +cum: U32, rev: String) -> String:
  match asc:
    case Nil{}:
      rev
    case Con{+b, t}:
      +next = U32.add(cum, num(m, bucket_key(route, le(b))))
      buckets(t, m, route, next, Text.rev_onto(bucket_line(route, le(b), next), rev))

def histogram(+m: Map<&2, String>, +route: String, +n: String, rev: String) -> String:
  Text.rev_onto(
    bucket_line(route, "+Inf", Text.digits_or(n, 0))
      ++ "air_http_request_duration_seconds_sum{" ++ label("route", route) ++ "} " ++ seconds(num(m, key2("s", route)), num(m, key2("m", route))) ++ "\n"
      ++ "air_http_request_duration_seconds_count{" ++ label("route", route) ++ "} " ++ n ++ "\n",
    buckets(bounds(), m, route, 0, rev))

# The kind of a key is its first character; what follows the tab is
# the rest. A section renders only its own kind.
type Section is Data:
  Counters{}
  Histograms{}
  Apps{}

def entry(section: Section, key: String, +n: String, +m: Map<&2, String>, rev: String) -> String:
  match section key:
    case Counters{} SCon{'c', SCon{'\t', rest}}:
      Text.rev_onto(counter_line(Text.split_all(rest, sep()), n), rev)
    case Histograms{} SCon{'n', SCon{'\t', route}}:
      histogram(m, route, n, rev)
    case Apps{} SCon{'a', SCon{'\t', name}}:
      Text.rev_onto(app_line(name, n), rev)
    case _ _:
      rev

def entry.kv(+section: Section, kv: Text.Two(), +m: Map<&2, String>, rev: String) -> String:
  (k, v) = kv
  entry(section, k, v, m, rev)

def section.go(kvs: List<&2, Text.Two()>, +section: Section, +m: Map<&2, String>, rev: String) -> String:
  match kvs:
    case Nil{}:
      rev
    case Con{kv, t}:
      section.go(t, section, m, entry.kv(section, kv, m, rev))

def counters_head() -> String:
  "# HELP air_http_requests_total Requests answered, by method, route and status.\n# TYPE air_http_requests_total counter\n"

def histogram_head() -> String:
  "# HELP air_http_request_duration_seconds Time in the app, from the middleware's view.\n# TYPE air_http_request_duration_seconds histogram\n"

# The namespace in the Prometheus text format: the request counter, the
# duration histogram, then the app counters, each series sorted by key.
def expose_text(m: Map<&2, String>) -> String:
  +m = m
  +kvs = Map.to_list(&2, String, m)
  String.reverse(
    section.go(kvs, Apps{}, m,
      section.go(kvs, Histograms{}, m,
        Text.rev_onto(histogram_head(),
          section.go(kvs, Counters{}, m,
            Text.rev_onto(counters_head(), SNil{}))))))

# App counters
# ------------

def name_ok(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{c, t}:
      +c = c
      Bool.and(Bool.or(Bool.or(Char.is_lower(c), Char.is_digit(c)), Char.is_eq(c, '_')), name_ok(t))

# A counter name is `[a-z0-9_]+`: it becomes part of a metric name.
def valid_name(+name: String) -> Bool:
  Bool.and(Text.non_empty(name), name_ok(name))

def tally.go(+name: String, m: Map<&2, String>, ok: Bool) -> Map<&2, String>:
  match ok:
    case True{}:
      bump(m, key2("a", name), 1)
    case False{}:
      m

# Adds one to the app counter `name`; an invalid name changes nothing.
def tally(+name: String, m: Map<&2, String>) -> Map<&2, String>:
  tally.go(name, m, valid_name(name))

# Handlers
# --------

def done(m: Map<&2, String>) -> IO(Unit):
  IO.pure(Unit, Unit{})

# Adds one to `app_<name>_total`. The name must be `[a-z0-9_]+`, or the
# call does nothing.
def count(+req: Http.Request, +name: String) -> IO(Unit):
  IO.bind(Map<&2, String>, Unit, Store.update_in(req, "metrics", m => tally(name, m)), done)

def metrics.fin(+req: Http.Request, +before: Nat, res: Http.Response, after: Nat) -> IO(Http.Response):
  +res = res
  IO.bind(Map<&2, String>, Http.Response,
    Store.update_in(req, "metrics",
      record(label_of(Http.Request.method(req)), Http.Response.route(res), Http.Response.status(res), U32.from_nat(Nat.sub(after, before)))),
    m => IO.pure(Http.Response, res))

def metrics.go(+req: Http.Request, +before: Nat, res: Http.Response) -> IO(Http.Response):
  IO.bind(Nat, Http.Response, IO.now(), metrics.fin(req, before, res))

# The middleware: times the rest of the chain and records the request.
# Put it outside `on_error`, or inside: a failed response carries its
# status either way.
def metrics(next: Router.Handler(), req: Http.Request) -> IO(Http.Response):
  +req = req
  do IO<Http.Response>:
    before : Nat <- IO.now()
    res : Http.Response <- next(req)
    metrics.go(req, before, res)

def content_type() -> String:
  "text/plain; version=0.0.4; charset=utf-8"

def exposition(m: Map<&2, String>) -> Http.Response:
  Http.Response.with_header(Http.Response.with_header(Http.Response.new(200, expose_text(m)), "content-type", content_type()), "cache-control", "no-store")

# The handler a scraper reads: `GET` it on an internal path, or behind
# an auth middleware, since it names every route.
def expose(req: Http.Request) -> IO(Http.Response):
  IO.bind(Map<&2, String>, Http.Response, Store.read_in(req, "metrics"), m => IO.pure(Http.Response, exposition(m)))
