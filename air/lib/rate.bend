import Base
import ./text.bend as Text
import ./http.bend as Http
import ./router.bend as Router
import ./store.bend as Store

# Rate
# ====
#
# A fixed-window rate limit as a middleware, over the store. The `rate`
# namespace holds `_epoch`, the number of the current window, and one
# count per key; when a request lands in a later window the namespace
# starts over, so memory is bounded by the keys seen in one window and
# nothing sweeps. Over the limit, the request fails with 429 and
# `retry-after`; every response carries `x-ratelimit-limit`,
# `x-ratelimit-remaining` and `x-ratelimit-reset`.

# Windows
# -------

# The window `now` (milliseconds) falls in.
def epoch(now: Nat, +window_ms: U32) -> U32:
  U32.from_nat(Nat.div(now, U32.to_nat(window_ms)))

# Seconds until the next window opens, at least one.
def reset_in.fin(+window_ms: U32, qr: Nat & Nat) -> U32:
  (q, r) = qr
  U32.max(1, U32.div(U32.add(U32.sub(window_ms, U32.from_nat(r)), 999), 1000))

def reset_in(now: Nat, +window_ms: U32) -> U32:
  reset_in.fin(window_ms, Nat.divmod(now, U32.to_nat(window_ms)))

def count.fin(d: Maybe<&2, U32>) -> U32:
  match d:
    case None{}:
      0
    case Some{n}:
      n

# The count for `key` in a window's map.
def count(+key: String, m: Map<&2, String>) -> U32:
  count.fin(Text.digits(Text.map_get(m, key, SNil{})))

def fresh(+epoch: U32) -> Map<&2, String>:
  Map.set(&2, String, Map.new(&2, String), "_epoch", U32.show(epoch))

def tick.go(+epoch: U32, +key: String, +m: Map<&2, String>, same: Bool) -> Map<&2, String>:
  match same:
    case True{}:
      Map.set(&2, String, m, key, U32.show(U32.inc(count(key, m))))
    case False{}:
      Map.set(&2, String, fresh(epoch), key, "1")

# One more request for `key` in window `epoch`: counts on when the map
# is of this window, else starts the window with this one request.
def tick(+epoch: U32, +key: String, m: Map<&2, String>) -> Map<&2, String>:
  +m = m
  tick.go(epoch, key, m, String.eq(Text.map_get(m, "_epoch", SNil{}), U32.show(epoch)))

# Answers
# -------

def decorate(+limit: U32, +used: U32, +reset: U32, r: Http.Response) -> Http.Response:
  Http.Response.with_header(
    Http.Response.with_header(
      Http.Response.with_header(r, "x-ratelimit-limit", U32.show(limit)),
      "x-ratelimit-remaining", U32.show(U32.sub(limit, U32.min(limit, used)))),
    "x-ratelimit-reset", U32.show(reset))

# The 429: a failed response, so `on_error` renders it and the headers
# survive.
def refuse(+limit: U32, +window_ms: U32, +used: U32, +reset: U32) -> Http.Response:
  decorate(limit, used, reset,
    Http.Response.with_header(
      Http.Response.fail(Http.TooMany{"rate limit: " ++ U32.show(used) ++ " of " ++ U32.show(limit) ++ " per " ++ U32.show(window_ms) ++ " ms"}),
      "retry-after", U32.show(reset)))

def decorated(+limit: U32, +used: U32, +reset: U32, r: Http.Response) -> IO(Http.Response):
  IO.pure(Http.Response, decorate(limit, used, reset, r))

def limit.go(+limit: U32, +window_ms: U32, +used: U32, +reset: U32, next: Router.Handler(), req: Http.Request, over: Bool) -> IO(Http.Response):
  match over:
    case True{}:
      IO.pure(Http.Response, refuse(limit, window_ms, used, reset))
    case False{}:
      IO.bind(Http.Response, Http.Response, next(req), decorated(limit, used, reset))

def limit.fin(+limit: U32, +window_ms: U32, +key: String, now: Nat, next: Router.Handler(), req: Http.Request, m: Map<&2, String>) -> IO(Http.Response):
  +used = count(key, m)
  limit.go(limit, window_ms, used, reset_in(now, window_ms), next, req, U32.is_gt(used, limit))

def limit.now(+limit: U32, +window_ms: U32, +key: String, next: Router.Handler(), req: Http.Request, now: Nat) -> IO(Http.Response):
  +req = req
  +now = now
  IO.bind(Map<&2, String>, Http.Response, Store.update_in(req, "rate", tick(epoch(now, window_ms), key)), limit.fin(limit, window_ms, key, now, next, req))

# `limit(n, window_ms, key)` is a middleware: at most `n` requests per
# key per window. `key` names the bucket, `by_ip` or `by_header` below
# or one of the app's own. A request with no store is never limited.
def limit(+n: U32, +window_ms: U32, key: Http.Request -> String, next: Router.Handler(), req: Http.Request) -> IO(Http.Response):
  +req = req
  IO.bind(Nat, Http.Response, IO.now(), limit.now(n, window_ms, key(req), next, req))

# Keys
# ----

def by_ip.fin(ip: Maybe<&2, String>) -> String:
  match ip:
    case None{}:
      SNil{}
    case Some{s}:
      s

# The client's address as a trusted proxy reports it. Without one
# there is no address (`TCP.accept` gives none), so every request
# shares one bucket.
def by_ip(+trust: Http.Trust, req: Http.Request) -> String:
  by_ip.fin(Http.Request.client_ip(req, trust))

# A header's value, for API keys; "" when absent, which is one bucket.
def by_header(+name: String, req: Http.Request) -> String:
  Http.Request.header(req, name)
