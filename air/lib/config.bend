import Base
import ./text.bend as Text
import ./http.bend as Http
import ./router.bend as Router
import ./disk.bend as Disk
import ./store.bend as Store
import ./drain.bend as Drain
import ./server.bend as Server
import ./health.bend as Health

# Config
# ======
#
# Settings from the environment, a `.env` file, and defaults in code, in
# that order. Bend can read one variable at a time (`IO.get_env`) but
# cannot list or set them, so a `.env` file is loaded into a map and
# every lookup asks the environment first.
#
# Numbers fail fast: a variable that is set but is not digits ends the
# process at startup with its name, rather than serving with a surprise.
# A value is never printed when its name looks like a secret.
#
# Handlers read settings through the store (namespace `config`): the app
# is a closed template, so a value made in `main` cannot reach it any
# other way.

def Config() -> Data:
  Map<&2, String>

# Secrets
# -------

def secret.any(+name: String, words: List<&2, String>) -> Bool:
  match words:
    case Nil{}:
      False{}
    case Con{w, rest}:
      Bool.or(String.contains(name, w), secret.any(name, rest))

# Whether a name looks like it holds a secret: its value is never printed.
def secret(name: String) -> Bool:
  secret.any(String.to_upper(name), ["SECRET", "TOKEN", "KEY", "PASSWORD"])

# `value` quoted for a message, or `<hidden>` for a secret's.
def show_value(name: String, value: String) -> String:
  Bool.pick(String, secret(name), "<hidden>", "\"" ++ value ++ "\"")

# The `.env` file
# ---------------
#
# `KEY=VALUE` per line. Blank lines and `#` comments are skipped, a
# leading `export ` is dropped, key and value are trimmed, and one pair
# of surrounding `"` or `'` comes off the value. No escapes and no
# `${VAR}` expansion. A later line wins over an earlier one.

type Line is Data:
  Blank{}
  Entry{key: String, value: String}
  Malformed{}

def unquote.close(+v: String, +rest: String, +q: Char) -> String:
  Bool.pick(String, Text.last_is(rest, q), String.reverse(String.drop(String.reverse(rest), 1n)), v)

# `"x"` or `'x'` is `x`; anything else is as written.
def unquote(+v: String) -> String:
  match v:
    case SCon{'"', rest}:
      unquote.close(v, rest, '"')
    case SCon{'\'', rest}:
      unquote.close(v, rest, '\'')
    case _:
      v

def classify.entry(key: String, value: String, empty: Bool) -> Line:
  match empty:
    case True{}:
      Malformed{}
    case False{}:
      Entry{key, unquote(String.trim(value))}

def classify.key(+key: String, value: String) -> Line:
  classify.entry(key, value, String.is_empty(key))

def classify.split(found: Maybe<&2, Text.Two()>) -> Line:
  match found:
    case None{}:
      Malformed{}
    case Some{kv}:
      (k, v) = kv
      classify.key(String.trim(k), v)

def drop_export(+t: String) -> String:
  Bool.pick(String, String.starts_with(t, "export "), String.trim(String.drop(t, 7n)), t)

# One trimmed line of a `.env` file.
def classify(+t: String) -> Line:
  match t:
    case SNil{}:
      Blank{}
    case SCon{'#', rest}:
      Blank{}
    case _:
      classify.split(Text.split_str(drop_export(t), "="))

def line(s: String) -> Line:
  classify(String.trim(s))

def parse.add(acc: Map<&2, String>, l: Line) -> Map<&2, String>:
  match l:
    case Entry{k, v}:
      Map.set(&2, String, acc, k, v)
    case Blank{}:
      acc
    case Malformed{}:
      acc

def parse.go(lines: List<&2, String>, acc: Map<&2, String>) -> Map<&2, String>:
  match lines:
    case Nil{}:
      acc
    case Con{h, t}:
      parse.go(t, parse.add(acc, line(h)))

# The pairs of a `.env` text; malformed lines are left out.
def parse(text: String) -> Map<&2, String>:
  parse.go(Text.split_all(text, '\n'), Map.new(&2, String))

def malformed.note(acc: List<&2, U32>, +n: U32, l: Line) -> List<&2, U32>:
  match l:
    case Malformed{}:
      Con{n, acc}
    case Entry{k, v}:
      acc
    case Blank{}:
      acc

def malformed.go(lines: List<&2, String>, +n: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match lines:
    case Nil{}:
      List.reverse(&2, U32, acc)
    case Con{h, t}:
      malformed.go(t, U32.inc(n), malformed.note(acc, n, line(h)))

# The numbers, from 1, of the lines `parse` leaves out.
def malformed(text: String) -> List<&2, U32>:
  malformed.go(Text.split_all(text, '\n'), 1, Nil{})

# Numbers
# -------

# The number in `raw`, or `fallback` when it is empty (unset). Anything
# else that is not digits is a problem, see `problem`.
def number(+raw: String, +fallback: U32) -> U32:
  Bool.pick(U32, String.is_empty(raw), fallback, Text.digits_or(raw, fallback))

def problem.fin(+name: String, raw: String, bad: Bool) -> List<&2, String>:
  match bad:
    case True{}:
      [name ++ " is not a number: " ++ show_value(name, raw)]
    case False{}:
      Nil{}

def is_none(d: Maybe<&2, U32>) -> Bool:
  match d:
    case None{}:
      True{}
    case Some{n}:
      False{}

# What is wrong with `raw` as the number `name`: nothing when it is
# empty or digits.
def problem(+name: String, +raw: String) -> List<&2, String>:
  problem.fin(name, raw, Bool.and(Text.non_empty(raw), is_none(Text.digits(raw))))

# The server's limits from the four raw values, each defaulting to
# `Limits.default()`'s.
def limits_of(+head: String, +headers: String, +url: String, +body: String) -> Http.Limits:
  +d = Http.Limits.default()
  Http.Limits{
    number(head, Http.Limits.head(d)),
    number(headers, Http.Limits.headers(d)),
    number(url, Http.Limits.url(d)),
    number(body, Http.Limits.body(d))
  }

def limits_problems(+head: String, +headers: String, +url: String, +body: String) -> List<&2, String>:
  List.concat(&2, String, [
    problem("AIR_MAX_HEAD", head),
    problem("AIR_MAX_HEADERS", headers),
    problem("AIR_MAX_URL", url),
    problem("AIR_MAX_BODY", body)
  ])

def timeouts_of(+idle: String, +head: String, +body: String, +app: String, +send: String, +drain: String) -> Server.Timeouts:
  +d = Server.Timeouts.default()
  Server.Timeouts{
    number(idle, Server.Timeouts.idle(d)),
    number(head, Server.Timeouts.head(d)),
    number(body, Server.Timeouts.body(d)),
    number(app, Server.Timeouts.app(d)),
    number(send, Server.Timeouts.send(d)),
    number(drain, Server.Timeouts.drain(d))
  }

def timeouts_problems(+idle: String, +head: String, +body: String, +app: String, +send: String, +drain: String) -> List<&2, String>:
  List.concat(&2, String, [
    problem("AIR_TIMEOUT_IDLE", idle),
    problem("AIR_TIMEOUT_HEAD", head),
    problem("AIR_TIMEOUT_BODY", body),
    problem("AIR_TIMEOUT_APP", app),
    problem("AIR_TIMEOUT_SEND", send),
    problem("AIR_TIMEOUT_DRAIN", drain)
  ])

def port_problems(+raw: String) -> List<&2, String>:
  List.concat(&2, String, [
    problem("PORT", raw),
    Bool.pick(List<&2, String>, U32.is_gt(number(raw, 1), 65535), ["PORT is out of range: " ++ show_value("PORT", raw)], Nil{})
  ])

# Reading
# -------

def raw.fin(r: Result<&1, &1, U32 & String, String>) -> IO(String):
  match r:
    case Done{v}:
      IO.pure(String, v)
    case Fail{e}:
      IO.pure(String, SNil{})

# A variable's value; "" when it is unset.
def raw(name: String) -> IO(String):
  IO.bind(Result<&1, &1, U32 & String, String>, String, IO.get_env(name), raw.fin)

def report(problems: List<&2, String>) -> IO(Unit):
  match problems:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{h, t}:
      do IO<Unit>:
        IO.print("air: config: " ++ h)
        report(t)

def checked.halt(-A: Type, problems: List<&2, String>) -> IO(A):
  do IO<A>:
    report(problems)
    IO.die(A, 1, "air: config is invalid")

# `value` when there are no problems; otherwise prints them and ends the
# process with code 1.
def checked(-A: Type, problems: List<&2, String>, value: A) -> IO(A):
  match problems:
    case Nil{}:
      IO.pure(A, value)
    case Con{h, t}:
      checked.halt(A, Con{h, t})

def env.fin(+fallback: String, v: String) -> IO(String):
  +v = v
  IO.pure(String, Bool.pick(String, String.is_empty(v), fallback, v))

# A variable, or `fallback` when it is unset or empty.
def env(name: String, fallback: String) -> IO(String):
  +fallback = fallback
  IO.bind(String, String, raw(name), v => env.fin(fallback, v))

def u32.fin(+name: String, +fallback: U32, v: String) -> IO(U32):
  +v = v
  checked(U32, problem(name, v), number(v, fallback))

# A variable as a number, or `fallback` when it is unset or empty. A
# value that is not digits ends the process with a message naming it.
def u32(name: String, fallback: U32) -> IO(U32):
  +name = name
  +fallback = fallback
  IO.bind(String, U32, raw(name), v => u32.fin(name, fallback, v))

def port.fin(+fallback: U32, v: String) -> IO(U32):
  +v = v
  checked(U32, port_problems(v), number(v, fallback))

# `PORT`, or `fallback`; ends the process when it is not a port number.
def port(fallback: U32) -> IO(U32):
  +fallback = fallback
  IO.bind(String, U32, raw("PORT"), v => port.fin(fallback, v))

def limits.fin(+head: String, +headers: String, +url: String, +body: String) -> IO(Http.Limits):
  checked(Http.Limits, limits_problems(head, headers, url, body), limits_of(head, headers, url, body))

# The server's limits from `AIR_MAX_HEAD`, `AIR_MAX_HEADERS`,
# `AIR_MAX_URL` and `AIR_MAX_BODY` (bytes), each defaulting to
# `Limits.default()`'s.
def limits() -> IO(Http.Limits):
  do IO<Http.Limits>:
    head : String <- raw("AIR_MAX_HEAD")
    headers : String <- raw("AIR_MAX_HEADERS")
    url : String <- raw("AIR_MAX_URL")
    body : String <- raw("AIR_MAX_BODY")
    limits.fin(head, headers, url, body)

def timeouts.fin(+idle: String, +head: String, +body: String, +app: String, +send: String, +drain: String) -> IO(Server.Timeouts):
  checked(Server.Timeouts, timeouts_problems(idle, head, body, app, send, drain), timeouts_of(idle, head, body, app, send, drain))

# The server's timeouts from `AIR_TIMEOUT_IDLE`, `_HEAD`, `_BODY`,
# `_APP`, `_SEND` and `_DRAIN` (milliseconds; 0 is no limit), each
# defaulting to `Timeouts.default()`'s.
def timeouts() -> IO(Server.Timeouts):
  do IO<Server.Timeouts>:
    idle : String <- raw("AIR_TIMEOUT_IDLE")
    head : String <- raw("AIR_TIMEOUT_HEAD")
    body : String <- raw("AIR_TIMEOUT_BODY")
    app : String <- raw("AIR_TIMEOUT_APP")
    send : String <- raw("AIR_TIMEOUT_SEND")
    drain : String <- raw("AIR_TIMEOUT_DRAIN")
    timeouts.fin(idle, head, body, app, send, drain)

# Loading and reading back
# ------------------------

def warn(+path: String, lines: List<&2, U32>) -> IO(Unit):
  match lines:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{n, t}:
      do IO<Unit>:
        IO.print("air: " ++ path ++ ":" ++ U32.show(n) ++ ": ignored")
        warn(path, t)

def load.fin(+path: String, found: Maybe<&2, String>) -> IO(Map<&2, String>):
  match found:
    case None{}:
      IO.pure(Map<&2, String>, Map.new(&2, String))
    case Some{+text}:
      do IO<Map<&2, String>>:
        warn(path, malformed(text))
        return parse(text)

# The pairs of the `.env` file at `path`; empty when there is none.
# Lines it cannot read are named and skipped.
def load(path: String) -> IO(Map<&2, String>):
  +path = path
  IO.bind(Maybe<&2, String>, Map<&2, String>, Disk.read(path), found => load.fin(path, found))

def install.fin(m: Map<&2, String>) -> IO(Unit):
  IO.pure(Unit, Unit{})

# Puts a loaded config where handlers can read it (`get`).
def install(store: Store.Store(), cfg: Map<&2, String>) -> IO(Unit):
  +store = store
  IO.bind(Map<&2, String>, Unit, Store.update(store, "config", m => cfg), install.fin)

def get.stored(+fallback: String, v: String) -> IO(String):
  +v = v
  IO.pure(String, Bool.pick(String, String.is_empty(v), fallback, v))

def get.env(+req: Http.Request, +name: String, +fallback: String, +v: String, empty: Bool) -> IO(String):
  match empty:
    case True{}:
      IO.bind(String, String, Store.get_in(req, "config", name), s => get.stored(fallback, s))
    case False{}:
      IO.pure(String, v)

def get.fin(+req: Http.Request, +name: String, +fallback: String, v: String) -> IO(String):
  +v = v
  get.env(req, name, fallback, v, String.is_empty(v))

# A setting in a handler: the environment's value, else the loaded
# config's (`install`), else `fallback`.
def get(req: Http.Request, name: String, fallback: String) -> IO(String):
  +req = req
  +name = name
  +fallback = fallback
  IO.bind(String, String, raw(name), v => get.fin(req, name, fallback, v))

# Serving
# -------

def serve.go(~app: Chan(Unit) -> Router.Handler(), +switch: Chan(Unit), +fallback_port: U32, cfg: Map<&2, String>, store: Store.Store()) -> IO(Unit):
  +store = store
  do IO<Unit>:
    install(store, cfg)
    delay : U32 <- u32("AIR_DRAIN_DELAY", 0)
    Health.delay(store, delay)
    l : Http.Limits <- limits()
    t : Server.Timeouts <- timeouts()
    p : U32 <- port(fallback_port)
    Server.serve_shared(~app, l, t, store, switch, p)

# `Server.serve_shared` with everything from the environment: `.env`
# loaded from the working directory and installed in a fresh store, the
# limits and timeouts from their `AIR_*` variables, the drain delay from
# `AIR_DRAIN_DELAY` (ms, see `Health.delay`), and `PORT` or
# `fallback_port`.
def serve_until(~app: Chan(Unit) -> Router.Handler(), switch: Chan(Unit), +fallback_port: U32) -> IO(Unit):
  +switch = switch
  do IO<Unit>:
    cfg : Map<&2, String> <- load(".env")
    store : Store.Store() <- Store.new()
    serve.go(~app, switch, fallback_port, cfg, store)

def serve(~app: Router.Handler(), +fallback_port: U32) -> IO(Unit):
  IO.bind(Chan(Unit), Unit, Drain.Switch.new(), switch => serve_until(~(sw => app), switch, fallback_port))
