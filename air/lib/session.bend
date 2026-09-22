import Base
import ./text.bend as Text
import ./random.bend as Random
import ./json.bend as Json
import ./http.bend as Http
import ./router.bend as Router
import ./store.bend as Store

# Session
# =======
#
# State tied to one browser across requests. A random token in a cookie
# names an entry in the store's `sessions` namespace; the `start`
# middleware makes sure every request has a live one, and handlers read
# and write fields by name. Server-side only: Bend has no HMAC, so a
# cookie cannot carry data safely, and the cookie carries the token
# alone. Sessions live in the process and end with it.
#
# A session's fields are one JSON object, kept as one string under its
# token, so the store's shelf stays small however many sessions there
# are: a `Map` costs more per operation as it grows, and only the
# session operations should pay for the sessions. `_seen` is the
# millisecond it was last touched (the process clock, in U32:
# `Nat.read` cannot be law-checked, its overflow guard being 2^48 in
# unary); one older than the TTL is treated as absent. A tally of
# sessions minted since the last sweep lives beside; when a mint takes
# it past `max`, that request sweeps the expired sessions in one pass
# and the tally restarts at zero, so the store holds at most the live
# sessions plus `max`. A token that names no live session is replaced,
# so a guessed or stale cookie never attaches to data.

type Config is Data:
  Config{name: String, ttl_ms: U32, max: U32, secure: Bool}

# Cookie `air_session`, a day, ten thousand sessions before a sweep,
# not `Secure` (turn it on behind the TLS proxy).
def default() -> Config:
  Config{"air_session", 86400000, 10000, False{}}

def with_name(c: Config, name: String) -> Config:
  match c:
    case Config{n, t, m, s}:
      Config{name, t, m, s}

# Milliseconds, up to 49 days.
def with_ttl(c: Config, ms: U32) -> Config:
  match c:
    case Config{n, t, m, s}:
      Config{n, ms, m, s}

def with_max(c: Config, max: U32) -> Config:
  match c:
    case Config{n, t, m, s}:
      Config{n, t, max, s}

def secure(c: Config, on: Bool) -> Config:
  match c:
    case Config{n, t, m, s}:
      Config{n, t, m, on}

def Config.name(c: Config) -> String:
  match c:
    case Config{n, t, m, s}:
      n

def Config.ttl(c: Config) -> U32:
  match c:
    case Config{n, t, m, s}:
      t

def Config.max(c: Config) -> U32:
  match c:
    case Config{n, t, m, s}:
      m

def Config.secure(c: Config) -> Bool:
  match c:
    case Config{n, t, m, s}:
      s

# Encoding
# --------

def ns() -> String:
  "sessions"

def tally_ns() -> String:
  "session_tally"

def field_of(kv: Text.Two()) -> Json.Field():
  (k, v) = kv
  Json.field(k, Json.of_str(v))

def fields_of(kvs: List<&2, Text.Two()>) -> List<&2, Json.Field()>:
  match kvs:
    case Nil{}:
      Nil{}
    case Con{kv, t}:
      Con{field_of(kv), fields_of(t)}

# A session's fields as one JSON object: `{"_seen":"5161","n":"2"}`.
def encode(m: Map<&2, String>) -> String:
  Json.render(Json.obj(fields_of(Map.to_list(&2, String, m))))

def str_or_empty(v: Maybe<&2, String>) -> String:
  match v:
    case None{}:
      SNil{}
    case Some{s}:
      s

def entry_of(f: Json.Field()) -> Text.Two():
  (k, v) = f
  (k, str_or_empty(Json.str(v)))

def entries_of(fs: List<&2, Json.Field()>) -> List<&2, Text.Two()>:
  match fs:
    case Nil{}:
      Nil{}
    case Con{f, t}:
      Con{entry_of(f), entries_of(t)}

def decode.fin(v: Maybe<&2, Json.Value>) -> Map<&2, String>:
  match v:
    case None{}:
      Map.new(&2, String)
    case Some{j}:
      Map.from_list(&2, String, entries_of(Json.fields(j)))

# Back to fields; anything that is not an object of strings reads empty.
def decode(s: String) -> Map<&2, String>:
  decode.fin(Json.parse(s))

# Liveness
# --------

def touch(now: U32, m: Map<&2, String>) -> Map<&2, String>:
  Map.set(&2, String, m, "_seen", U32.show(now))

def alive.fin(+now: U32, +ttl: U32, seen: Maybe<&2, U32>) -> Bool:
  match seen:
    case None{}:
      False{}
    case Some{+s}:
      Bool.and(U32.is_le(s, now), U32.is_lt(U32.sub(now, s), ttl))

# Whether a session touched at `_seen` is still within the TTL at `now`.
# No `_seen`, or one in the future, is dead.
def alive(+now: U32, +ttl: U32, m: Map<&2, String>) -> Bool:
  alive.fin(now, ttl, Text.digits(Text.map_get(m, "_seen", SNil{})))

def sweep.keep(acc: Map<&2, String>, +token: String, +s: String, kept: Bool) -> Map<&2, String>:
  match kept:
    case True{}:
      Map.set(&2, String, acc, token, s)
    case False{}:
      acc

def sweep.put(+now: U32, +ttl: U32, kv: Text.Two(), acc: Map<&2, String>) -> Map<&2, String>:
  (token, s) = kv
  +token = token
  +s = s
  sweep.keep(acc, token, s, alive(now, ttl, decode(s)))

def sweep.go(+now: U32, +ttl: U32, kvs: List<&2, Text.Two()>, acc: Map<&2, String>) -> Map<&2, String>:
  match kvs:
    case Nil{}:
      acc
    case Con{kv, t}:
      sweep.go(now, ttl, t, sweep.put(now, ttl, kv, acc))

# The live sessions of the `sessions` namespace.
def sweep(+now: U32, +ttl: U32, sessions: Map<&2, String>) -> Map<&2, String>:
  sweep.go(now, ttl, Map.to_list(&2, String, sessions), Map.new(&2, String))

# Reading and writing one session, through the request.
def load.fin(+token: String, sessions: Map<&2, String>) -> IO(Map<&2, String>):
  IO.pure(Map<&2, String>, decode(Text.map_get(sessions, token, SNil{})))

def load(+req: Http.Request, +token: String) -> IO(Map<&2, String>):
  IO.bind(Map<&2, String>, Map<&2, String>, Store.read_in(req, ns()), load.fin(token))

def save.go(+token: String, m: Map<&2, String>, sessions: Map<&2, String>) -> Map<&2, String>:
  Map.set(&2, String, sessions, token, encode(m))

def unit_of(m: Map<&2, String>) -> IO(Unit):
  IO.pure(Unit, Unit{})

def save(+req: Http.Request, +token: String, m: Map<&2, String>) -> IO(Unit):
  IO.bind(Map<&2, String>, Unit, Store.update_in(req, ns(), save.go(token, m)), unit_of)

def forget(+req: Http.Request, +token: String) -> IO(Unit):
  IO.bind(Map<&2, String>, Unit, Store.update_in(req, ns(), sessions => Map.del(&2, String, sessions, token)), unit_of)

# Cookies
# -------

def cookie(+c: Config, +id: String) -> Http.Cookie:
  Http.Cookie.secure(Http.Cookie.new(Config.name(c), id), Config.secure(c))

# Sweeping
# --------

def restart(+req: Http.Request, m: Map<&2, String>) -> IO(Unit):
  Store.set_in(req, tally_ns(), "count", "0")

# Sweeps, then the tally restarts: the next sweep is `max` mints away,
# so the cost is one pass per `max` mints whatever survives.
def sweep_now(+c: Config, +req: Http.Request, now: Nat) -> IO(Unit):
  IO.bind(Map<&2, String>, Unit, Store.update_in(req, ns(), sweep(U32.from_nat(now), Config.ttl(c))), restart(req))

def maybe_sweep.pick(+c: Config, +req: Http.Request, over: Bool) -> IO(Unit):
  match over:
    case True{}:
      IO.bind(Nat, Unit, IO.now(), sweep_now(c, req))
    case False{}:
      IO.pure(Unit, Unit{})

def maybe_sweep.go(+c: Config, +req: Http.Request, minted: U32) -> IO(Unit):
  maybe_sweep.pick(c, req, U32.is_gt(minted, Config.max(c)))

# One more session minted: past `max` since the last sweep, drop the
# expired ones. A bounded cost paid rarely, and only by a mint.
def maybe_sweep(+c: Config, +req: Http.Request) -> IO(Unit):
  IO.bind(U32, Unit, Store.incr_in(req, tally_ns(), "count"), maybe_sweep.go(c, req))

# Attaching
# ---------

type Attached is Data:
  Attached{req: Http.Request, id: String, minted: Bool}

# The token and the cookie's name go on the request as locals, so the
# helpers below and `end` need no config.
def attach.done(+c: Config, req: Http.Request, +id: String, minted: Bool) -> IO(Attached):
  IO.pure(Attached, Attached{
    Http.Request.with_local(Http.Request.with_local(req, "session_id", id), "session_cookie", Config.name(c)),
    id, minted})

def attach.minted(+c: Config, req: Http.Request, +now: U32, id: String) -> IO(Attached):
  +req = req
  +id = id
  do IO<Attached>:
    save(req, id, touch(now, Map.new(&2, String)))
    maybe_sweep(c, req)
    attach.done(c, req, id, True{})

# A fresh token, and its namespace begun.
def attach.fresh(+c: Config, req: Http.Request, +now: U32) -> IO(Attached):
  IO.bind(String, Attached, Random.token(), attach.minted(c, req, now))

def attach.pick(+c: Config, req: Http.Request, +now: U32, +id: String, m: Map<&2, String>, live: Bool) -> IO(Attached):
  match live:
    case True{}:
      +req = req
      do IO<Attached>:
        save(req, id, touch(now, m))
        attach.done(c, req, id, False{})
    case False{}:
      attach.fresh(c, req, now)

def attach.checked(+c: Config, req: Http.Request, +now: U32, +id: String, m: Map<&2, String>) -> IO(Attached):
  +m = m
  attach.pick(c, req, now, id, m, alive(now, Config.ttl(c), m))

def attach.given(+c: Config, req: Http.Request, +now: U32, +given: String, safe: Bool) -> IO(Attached):
  match safe:
    case True{}:
      +req = req
      IO.bind(Map<&2, String>, Attached, load(req, given), attach.checked(c, req, now, given))
    case False{}:
      attach.fresh(c, req, now)

def attach.at(+c: Config, req: Http.Request, now: Nat) -> IO(Attached):
  +req = req
  +given = Http.Request.cookie(req, Config.name(c))
  attach.given(c, req, U32.from_nat(now), given, Random.safe_id(given))

# The request with its session: the cookie's token when it names a live
# session (touched), else a fresh one.
def attach(+c: Config, req: Http.Request) -> IO(Attached):
  IO.bind(Nat, Attached, IO.now(), attach.at(c, req))

# The middleware
# --------------

def start.fin(+c: Config, +id: String, minted: Bool, res: Http.Response) -> IO(Http.Response):
  match minted:
    case True{}:
      IO.pure(Http.Response, Http.Response.with_cookie(res, cookie(c, id)))
    case False{}:
      IO.pure(Http.Response, res)

def start.go(+c: Config, next: Router.Handler(), a: Attached) -> IO(Http.Response):
  match a:
    case Attached{req, id, minted}:
      IO.bind(Http.Response, Http.Response, next(req), start.fin(c, id, minted))

# `start(cfg)` is a middleware: every request below it has a session,
# and a response to a request that minted one sets the cookie, whatever
# the response is.
def start(+c: Config, next: Router.Handler(), req: Http.Request) -> IO(Http.Response):
  IO.bind(Attached, Http.Response, attach(c, req), start.go(c, next))

# For handlers
# ------------
#
# Through the request's locals. Without `start` above, the id is "",
# reads answer "" and writes go nowhere.

def sid(+req: Http.Request) -> String:
  Http.Request.local(req, "session_id")

def get.fin(+key: String, m: Map<&2, String>) -> IO(String):
  IO.pure(String, Text.map_get(m, key, SNil{}))

def get(req: Http.Request, +key: String) -> IO(String):
  +req = req
  IO.bind(Map<&2, String>, String, load(req, sid(req)), get.fin(key))

def modify.fin(+req: Http.Request, +token: String, f: Map<&2, String> -> Map<&2, String>, m: Map<&2, String>) -> IO(Map<&2, String>):
  +m2 = f(m)
  IO.bind(Unit, Map<&2, String>, save(req, token, m2), u => IO.pure(Map<&2, String>, m2))

# Loads, applies `f`, saves; answers the new fields. Two store trips,
# not one: a race between two requests of the same session loses one
# write, which a session can bear.
def modify(+req: Http.Request, +token: String, f: Map<&2, String> -> Map<&2, String>) -> IO(Map<&2, String>):
  IO.bind(Map<&2, String>, Map<&2, String>, load(req, token), modify.fin(req, token, f))

def allowed(+req: Http.Request, +key: String) -> Bool:
  Bool.and(Text.non_empty(sid(req)), Bool.not(Text.head_is(key, '_')))

def set.go(+req: Http.Request, +key: String, +value: String, ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.bind(Map<&2, String>, Unit, modify(req, sid(req), m => Map.set(&2, String, m, key, value)), unit_of)
    case False{}:
      IO.pure(Unit, Unit{})

# Keys starting with `_` are the framework's; a write to one is dropped.
def set(req: Http.Request, +key: String, +value: String) -> IO(Unit):
  +req = req
  set.go(req, key, value, allowed(req, key))

def incr.step(+key: String, m: Map<&2, String>) -> Map<&2, String>:
  +m = m
  Map.set(&2, String, m, key, U32.show(U32.inc(Text.digits_or(Text.map_get(m, key, SNil{}), 0))))

def incr.fin(+key: String, m: Map<&2, String>) -> IO(U32):
  IO.pure(U32, Text.digits_or(Text.map_get(m, key, SNil{}), 0))

def incr.go(+req: Http.Request, +key: String, ok: Bool) -> IO(U32):
  match ok:
    case True{}:
      IO.bind(Map<&2, String>, U32, modify(req, sid(req), incr.step(key)), incr.fin(key))
    case False{}:
      IO.pure(U32, 0)

# Adds one to a field holding a number and answers the new count; 0
# without a session or on a reserved key.
def incr(req: Http.Request, +key: String) -> IO(U32):
  +req = req
  incr.go(req, key, allowed(req, key))

# Every field, `_seen` included.
def fields(req: Http.Request) -> IO(Map<&2, String>):
  +req = req
  load(req, sid(req))

def clear.at(+req: Http.Request, now: Nat) -> IO(Unit):
  save(req, sid(req), touch(U32.from_nat(now), Map.new(&2, String)))

# Drops the data; the token and its cookie stay, so the next `set`
# starts a clean session under the same id.
def clear(req: Http.Request) -> IO(Unit):
  +req = req
  IO.bind(Nat, Unit, IO.now(), clear.at(req))

def end.fin(+req: Http.Request, res: Http.Response) -> IO(Http.Response):
  IO.pure(Http.Response, Http.Response.expire_cookie(res, Http.Request.local(req, "session_cookie")))

# Drops the data and tells the browser to forget the cookie; the next
# request mints a new session.
def end(req: Http.Request, res: Http.Response) -> IO(Http.Response):
  +req = req
  do IO<Http.Response>:
    forget(req, sid(req))
    end.fin(req, res)
