import Base
import ./text.bend as Text
import ./http.bend as Http

# Store
# =====
#
# The one value every request can read and write: a shelf of namespaces,
# each a map of strings, behind a one-slot channel. Taking the shelf out
# is the lock and putting it back the unlock, so the function applied in
# between must be pure and quick: every other request waits on it. The
# server makes one store per process and puts it on each request; a
# request built elsewhere has none, and reads as empty.
#
# Bend has no globals, and a template argument such as `serve`'s app
# must be closed, so state cannot be threaded from `main` into the app:
# it rides on the request instead. Strings, like params and locals: a
# count or a time renders and parses in one call.

def Shelf() -> Data:
  Map<&2, Map<&2, String>>

def Store() -> Data:
  Chan(Shelf())

def new.go(chan: Chan(Shelf())) -> IO(Chan(Shelf())):
  +c = chan
  IO.bind(Bool, Chan(Shelf()), Chan.send(Shelf(), c, Map.new(&2, Map<&2, String>)), ok => IO.pure(Chan(Shelf()), c))

def new() -> IO(Store()):
  IO.bind(Chan(Shelf()), Chan(Shelf()), Chan.new(Shelf(), 1), new.go)

# Locking
# -------

def swap.put(f: Shelf() -> Shelf(), +store: Store(), v: Shelf()) -> IO(Shelf()):
  +next = f(v)
  IO.bind(Bool, Shelf(), Chan.send(Shelf(), store, next), ok => IO.pure(Shelf(), next))

def swap.go(f: Shelf() -> Shelf(), +store: Store(), got: Maybe<&1, Shelf()>) -> IO(Shelf()):
  match got:
    case None{}:
      IO.pure(Shelf(), Map.new(&2, Map<&2, String>))
    case Some{v}:
      swap.put(f, store, v)

# Replaces the shelf with `f` of it and answers the new shelf. A closed
# store answers empty.
def swap(f: Shelf() -> Shelf(), +store: Store()) -> IO(Shelf()):
  IO.bind(Maybe<&1, Shelf()>, Shelf(), Chan.recv(Shelf(), store), swap.go(f, store))

# Namespaces
# ----------

def ns_of.fin(r: Map<&2, Map<&2, String>> & Map<&2, String>) -> Map<&2, String>:
  (m, v) = r
  v

# One namespace of a shelf, empty when absent.
def ns_of(shelf: Shelf(), ns: String) -> Map<&2, String>:
  ns_of.fin(Map.get(Map<&2, String>, Map.new(&2, String), shelf, ns))

def update.shelf(+ns: String, f: Map<&2, String> -> Map<&2, String>, shelf: Shelf()) -> Shelf():
  +shelf = shelf
  Map.set(&2, Map<&2, String>, shelf, ns, f(ns_of(shelf, ns)))

def update.fin(+ns: String, shelf: Shelf()) -> IO(Map<&2, String>):
  IO.pure(Map<&2, String>, ns_of(shelf, ns))

# Replaces the namespace with `f` of it and answers the new namespace.
def update(+store: Store(), +ns: String, f: Map<&2, String> -> Map<&2, String>) -> IO(Map<&2, String>):
  IO.bind(Shelf(), Map<&2, String>, swap(update.shelf(ns, f), store), update.fin(ns))

def read(+store: Store(), +ns: String) -> IO(Map<&2, String>):
  update(store, ns, m => m)

def get.fin(+key: String, m: Map<&2, String>) -> IO(String):
  IO.pure(String, Text.map_get(m, key, SNil{}))

def get(+store: Store(), +ns: String, +key: String) -> IO(String):
  IO.bind(Map<&2, String>, String, read(store, ns), get.fin(key))

def unit(m: Map<&2, String>) -> IO(Unit):
  IO.pure(Unit, Unit{})

def set(+store: Store(), +ns: String, +key: String, +value: String) -> IO(Unit):
  IO.bind(Map<&2, String>, Unit, update(store, ns, m => Map.set(&2, String, m, key, value)), unit)

def incr.step(+key: String, m: Map<&2, String>) -> Map<&2, String>:
  +m = m
  Map.set(&2, String, m, key, U32.show(U32.inc(Text.digits_or(Text.map_get(m, key, SNil{}), 0))))

def incr.fin(+key: String, m: Map<&2, String>) -> IO(U32):
  IO.pure(U32, Text.digits_or(Text.map_get(m, key, SNil{}), 0))

# Adds one to a key holding a number (a missing or malformed value
# counts as 0) and answers the new count.
def incr(+store: Store(), +ns: String, +key: String) -> IO(U32):
  IO.bind(Map<&2, String>, U32, update(store, ns, incr.step(key)), incr.fin(key))

def drop.fin(shelf: Shelf()) -> IO(Unit):
  IO.pure(Unit, Unit{})

# Removes a namespace whole.
def drop(+store: Store(), +ns: String) -> IO(Unit):
  IO.bind(Shelf(), Unit, swap(shelf => Map.del(&2, Map<&2, String>, shelf, ns), store), drop.fin)

def namespaces.fin(shelf: Shelf()) -> IO(List<&2, String>):
  IO.pure(List<&2, String>, Map.keys(&2, Map<&2, String>, shelf))

def namespaces(+store: Store()) -> IO(List<&2, String>):
  IO.bind(Shelf(), List<&2, String>, swap(shelf => shelf, store), namespaces.fin)

# On a request
# ------------
#
# The same, through the request. A request without a store reads as
# empty and writes go nowhere.

def update_in.go(+ns: String, f: Map<&2, String> -> Map<&2, String>, store: Maybe<&2, Store()>) -> IO(Map<&2, String>):
  match store:
    case None{}:
      IO.pure(Map<&2, String>, Map.new(&2, String))
    case Some{s}:
      update(s, ns, f)

def update_in(+req: Http.Request, +ns: String, f: Map<&2, String> -> Map<&2, String>) -> IO(Map<&2, String>):
  update_in.go(ns, f, Http.Request.store(req))

def read_in(+req: Http.Request, +ns: String) -> IO(Map<&2, String>):
  update_in(req, ns, m => m)

def get_in(+req: Http.Request, +ns: String, +key: String) -> IO(String):
  IO.bind(Map<&2, String>, String, read_in(req, ns), get.fin(key))

def set_in(+req: Http.Request, +ns: String, +key: String, +value: String) -> IO(Unit):
  IO.bind(Map<&2, String>, Unit, update_in(req, ns, m => Map.set(&2, String, m, key, value)), unit)

def incr_in(+req: Http.Request, +ns: String, +key: String) -> IO(U32):
  IO.bind(Map<&2, String>, U32, update_in(req, ns, incr.step(key)), incr.fin(key))

def swap_in.go(f: Shelf() -> Shelf(), store: Maybe<&2, Store()>) -> IO(Shelf()):
  match store:
    case None{}:
      IO.pure(Shelf(), Map.new(&2, Map<&2, String>))
    case Some{s}:
      swap(f, s)

# The whole shelf replaced with `f` of it; for sweeps.
def swap_in(+req: Http.Request, f: Shelf() -> Shelf()) -> IO(Shelf()):
  swap_in.go(f, Http.Request.store(req))

def namespaces_in(+req: Http.Request) -> IO(List<&2, String>):
  IO.bind(Shelf(), List<&2, String>, swap_in(req, shelf => shelf), namespaces.fin)

def drop_in.go(+ns: String, store: Maybe<&2, Store()>) -> IO(Unit):
  match store:
    case None{}:
      IO.pure(Unit, Unit{})
    case Some{s}:
      drop(s, ns)

def drop_in(+req: Http.Request, +ns: String) -> IO(Unit):
  drop_in.go(ns, Http.Request.store(req))
