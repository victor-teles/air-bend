import Base

# Drain
# =====
#
# Graceful shutdown. Bend has no signals, so the app flips a `Switch`;
# the server then stops accepting, lets the requests in flight finish,
# and returns. The `Tally` counts those requests: one value in a one-slot
# channel, where taking it is the lock and putting it back the unlock.

# Switch
# ------

def Switch() -> Data:
  Chan(Unit)

def Switch.new() -> IO(Chan(Unit)):
  Chan.new(Unit, 1)

# Flips the switch. Flipping it again does nothing.
def Switch.flip(switch: Chan(Unit)) -> IO(Unit):
  Chan.close(Unit, switch)

# Returns once the switch is flipped.
def Switch.wait(switch: Chan(Unit)) -> IO(Unit):
  IO.bind(Maybe<&1, Unit>, Unit, Chan.recv(Unit, switch), got => IO.pure(Unit, Unit{}))

# Tally
# -----

type Tally is Data:
  Open{n: U32}
  Draining{n: U32}

def Tally.count(t: Tally) -> U32:
  match t:
    case Open{n}:
      n
    case Draining{n}:
      n

# Whether a new request may start.
def Tally.admit(t: Tally) -> Bool:
  match t:
    case Open{n}:
      True{}
    case Draining{n}:
      False{}

# A request starts; none does while draining.
def Tally.enter(t: Tally) -> Tally:
  match t:
    case Open{n}:
      Open{U32.inc(n)}
    case Draining{n}:
      Draining{n}

def Tally.leave(t: Tally) -> Tally:
  match t:
    case Open{n}:
      Open{U32.sub(n, 1)}
    case Draining{n}:
      Draining{U32.sub(n, 1)}

def Tally.drain(t: Tally) -> Tally:
  match t:
    case Open{n}:
      Draining{n}
    case Draining{n}:
      Draining{n}

# Drained: no request in flight, and none admitted since.
def Tally.clear(t: Tally) -> Bool:
  match t:
    case Open{n}:
      False{}
    case Draining{n}:
      U32.is_zero(n)

# Gate
# ----

def Gate() -> Data:
  Chan(Tally)

def Gate.new.go(gate: Chan(Tally)) -> IO(Chan(Tally)):
  +g = gate
  IO.bind(Bool, Chan(Tally), Chan.send(Tally, g, Open{0}), ok => IO.pure(Chan(Tally), g))

def Gate.new() -> IO(Chan(Tally)):
  IO.bind(Chan(Tally), Chan(Tally), Chan.new(Tally, 1), Gate.new.go)

def swap.put(f: Tally -> Tally, +gate: Chan(Tally), t: Tally) -> IO(Maybe<&1, Tally>):
  +v = t
  IO.bind(Bool, Maybe<&1, Tally>, Chan.send(Tally, gate, f(v)), ok => IO.pure(Maybe<&1, Tally>, Some{v}))

def swap.go(f: Tally -> Tally, +gate: Chan(Tally), got: Maybe<&1, Tally>) -> IO(Maybe<&1, Tally>):
  match got:
    case None{}:
      IO.pure(Maybe<&1, Tally>, None{})
    case Some{t}:
      swap.put(f, gate, t)

# Replaces the tally with `f` of it and answers the old one.
def swap(f: Tally -> Tally, +gate: Chan(Tally)) -> IO(Maybe<&1, Tally>):
  IO.bind(Maybe<&1, Tally>, Maybe<&1, Tally>, Chan.recv(Tally, gate), swap.go(f, gate))

def admitted(got: Maybe<&1, Tally>) -> Bool:
  match got:
    case None{}:
      False{}
    case Some{t}:
      Tally.admit(t)

def cleared(got: Maybe<&1, Tally>) -> Bool:
  match got:
    case None{}:
      True{}
    case Some{t}:
      Tally.clear(t)

# A request starts: True when admitted, and then `leave` must follow.
def enter(+gate: Chan(Tally)) -> IO(Bool):
  IO.bind(Maybe<&1, Tally>, Bool, swap(Tally.enter, gate), got => IO.pure(Bool, admitted(got)))

def leave(+gate: Chan(Tally)) -> IO(Unit):
  IO.bind(Maybe<&1, Tally>, Unit, swap(Tally.leave, gate), got => IO.pure(Unit, Unit{}))

def is_open(+gate: Chan(Tally)) -> IO(Bool):
  IO.bind(Maybe<&1, Tally>, Bool, swap(t => t, gate), got => IO.pure(Bool, admitted(got)))

# Stops admitting requests.
def close(+gate: Chan(Tally)) -> IO(Unit):
  IO.bind(Maybe<&1, Tally>, Unit, swap(Tally.drain, gate), got => IO.pure(Unit, Unit{}))

def settled(+gate: Chan(Tally)) -> IO(Bool):
  IO.bind(Maybe<&1, Tally>, Bool, swap(t => t, gate), got => IO.pure(Bool, cleared(got)))

def in_flight(got: Maybe<&1, Tally>) -> U32:
  match got:
    case None{}:
      0
    case Some{t}:
      Tally.count(t)

def count(+gate: Chan(Tally)) -> IO(U32):
  IO.bind(Maybe<&1, Tally>, U32, swap(t => t, gate), got => IO.pure(U32, in_flight(got)))

# Polling period while draining, in ms.
def poll() -> U32:
  50

def await(fuel: Nat, +gate: Chan(Tally), done: Bool) -> IO(Bool):
  match fuel done:
    case _ True{}:
      IO.pure(Bool, True{})
    case 0n False{}:
      IO.pure(Bool, False{})
    case 1n+p False{}:
      do IO<Bool>:
        IO.sleep(poll())
        d : Bool <- settled(gate)
        await(p, gate, d)

# Waits up to `grace` ms for the requests in flight to finish. True when
# they did.
def wait_for(+gate: Chan(Tally), +grace: U32) -> IO(Bool):
  IO.bind(Bool, Bool, settled(gate), await(U32.to_nat(U32.div(grace, poll())), gate))
