import Base

# Race
# ====
#
# Bend has no timed receive and no way to cancel an effect, so a timeout
# is a race. The effect runs in a computation of its own and reports on
# a channel; a watchdog reports on the same channel when the deadline
# passes; whoever reads the channel takes the first report. A runner that
# loses still holds its value (a socket, say) and gets it back to clean
# up, because a handle dropped on the floor is a leaked descriptor.
#
# One clock serves a whole connection: a race channel, an armed deadline
# and a watchdog that sleeps until it. Re-arming the clock is cheap, so
# every phase of a request (waiting, head, body, app, reply) gets its own
# deadline without a computation per phase. The watchdog's sleep is
# capped at `step`, so a deadline moved earlier is seen at most `step`
# later.

type Raced<-A: Type> is Type:
  Won{value: A}
  Lost{}

# A report on the race channel: a runner finished, or the watchdog saw
# the deadline of generation `gen` pass.
type Flag is Data:
  Ready{}
  Late{gen: U32}

# The armed deadline. `at` is in IO.now milliseconds, 0 when disarmed;
# `gen` tells a stale Late from a live one. The value lives in a one-slot
# channel, so taking it is the lock and putting it back is the unlock.
type Arm is Data:
  Arm{gen: U32, at: Nat}

type Clock is Data:
  Clock{race: Chan(Flag), dial: Chan(Arm), step: U32}

def Arm.gen(a: Arm) -> U32:
  match a:
    case Arm{gen, at}:
      gen

def Arm.at.go(+now: Nat, +ms: U32, none: Bool) -> Nat:
  match none:
    case True{}:
      0n
    case False{}:
      Nat.add(U32.to_nat(ms), now)

# The deadline `ms` from `now`; 0 ms means no deadline.
def Arm.at(+now: Nat, +ms: U32) -> Nat:
  Arm.at.go(now, ms, U32.is_zero(ms))

# The next arming: a new generation with its own deadline.
def Arm.next(a: Arm, +now: Nat, +ms: U32) -> Arm:
  match a:
    case Arm{gen, at}:
      Arm{U32.inc(gen), Arm.at(now, ms)}

# Whether the arm is due at `now`.
def Arm.due(+a: Arm, +now: Nat) -> Bool:
  match a:
    case Arm{gen, at}:
      Bool.and(Bool.not(Nat.is_eq(at, 0n)), Nat.is_le(at, now))

def Arm.sleep.go(+step: U32, disarmed: Bool, left: Nat) -> U32:
  match disarmed:
    case True{}:
      step
    case False{}:
      U32.max(1, U32.min(step, U32.from_nat(Nat.min(left, U32.to_nat(step)))))

# How long the watchdog sleeps from `now`: until the deadline, at most
# `step`, at least a millisecond.
def Arm.sleep(+a: Arm, +now: Nat, +step: U32) -> U32:
  match a:
    case Arm{gen, at}:
      Arm.sleep.go(U32.max(1, step), Nat.is_eq(at, 0n), Nat.sub(at, now))

# Watchdog
# --------

# Fires the deadline of `a`: disarms it, then reports Late.
def fire(+race: Chan(Flag), +dial: Chan(Arm), +a: Arm) -> IO(Unit):
  match a:
    case Arm{gen, at}:
      do IO<Unit>:
        put : Bool <- Chan.send(Arm, dial, Arm{gen, 0n})
        sent : Bool <- Chan.send(Flag, race, Late{gen})
        return Unit{}

# Puts the dial back untouched.
def keep(+dial: Chan(Arm), a: Arm) -> IO(Unit):
  IO.bind(Bool, Unit, Chan.send(Arm, dial, a), ok => IO.pure(Unit, Unit{}))

def tick.go(+race: Chan(Flag), +dial: Chan(Arm), +step: U32, +now: Nat, +a: Arm, due: Bool) -> IO(U32):
  match due:
    case True{}:
      IO.bind(Unit, U32, fire(race, dial, a), u => IO.pure(U32, step))
    case False{}:
      IO.bind(Unit, U32, keep(dial, a), u => IO.pure(U32, Arm.sleep(a, now, step)))

# One look at the dial: fires it when due, and says how long to sleep.
def tick(+race: Chan(Flag), +dial: Chan(Arm), +step: U32, +now: Nat, +a: Arm) -> IO(U32):
  tick.go(race, dial, step, now, a, Arm.due(a, now))

# The watchdog lives until the dial channel is closed.
def watch(fuel: Nat, +race: Chan(Flag), +dial: Chan(Arm), +step: U32, got: Maybe<&1, Arm>) -> IO(Unit):
  match fuel got:
    case _ None{}:
      IO.pure(Unit, Unit{})
    case 0n Some{a}:
      IO.pure(Unit, Unit{})
    case 1n+p Some{a}:
      do IO<Unit>:
        now : Nat <- IO.now()
        wait : U32 <- tick(race, dial, step, now, a)
        IO.sleep(wait)
        next : Maybe<&1, Arm> <- Chan.recv(Arm, dial)
        watch(p, race, dial, step, next)

def watch.start(+race: Chan(Flag), +dial: Chan(Arm), +step: U32) -> IO(Unit):
  IO.bind(Maybe<&1, Arm>, Unit, Chan.recv(Arm, dial), watch(4294967295n, race, dial, step))

# Clock
# -----

def Clock.spawn(+race: Chan(Flag), +dial: Chan(Arm), +step: U32, watched: Bool) -> IO(Clock):
  match watched:
    case True{}:
      IO.bind(Unit, Clock, IO.spawn(Unit, watch.start(race, dial, step)), u => IO.pure(Clock, Clock{race, dial, step}))
    case False{}:
      IO.pure(Clock, Clock{race, dial, step})

def Clock.dial(+race: Chan(Flag), +step: U32, dial: Chan(Arm)) -> IO(Clock):
  +a = dial
  IO.bind(Bool, Clock, Chan.send(Arm, a, Arm{0, 0n}), ok => Clock.spawn(race, a, step, Bool.not(U32.is_zero(step))))

def Clock.race(+step: U32, race: Chan(Flag)) -> IO(Clock):
  +r = race
  IO.bind(Chan(Arm), Clock, Chan.new(Arm, 1), Clock.dial(r, step))

# A clock whose watchdog wakes at least every `step` ms. With `step` 0
# nothing is watched and no deadline ever fires.
def Clock.new(+step: U32) -> IO(Clock):
  IO.bind(Chan(Flag), Clock, Chan.new(Flag, 1), Clock.race(step))

# Ends the clock: the watchdog stops at its next look, and a runner still
# out there gets its value back.
def Clock.stop(+clock: Clock) -> IO(Unit):
  match clock:
    case Clock{race, dial, step}:
      IO.bind(Unit, Unit, Chan.close(Flag, race), u => Chan.close(Arm, dial))

def rearm.put(+dial: Chan(Arm), +a: Arm) -> IO(U32):
  IO.bind(Bool, U32, Chan.send(Arm, dial, a), ok => IO.pure(U32, Arm.gen(a)))

def rearm.go(+dial: Chan(Arm), +ms: U32, +now: Nat, got: Maybe<&1, Arm>) -> IO(U32):
  match got:
    case None{}:
      IO.pure(U32, 0)
    case Some{a}:
      rearm.put(dial, Arm.next(a, now, ms))

def rearm(+dial: Chan(Arm), +ms: U32, got: Maybe<&1, Arm>) -> IO(U32):
  IO.bind(Nat, U32, IO.now(), now => rearm.go(dial, ms, now, got))

# Sets the deadline `ms` from now (0 for none) and answers its
# generation, which `within` needs to tell a stale Late apart.
def arm(+clock: Clock, +ms: U32) -> IO(U32):
  match clock:
    case Clock{race, dial, step}:
      IO.bind(Maybe<&1, Arm>, U32, Chan.recv(Arm, dial), rearm(dial, ms))

# Runner
# ------
#
# The runner reports Ready on the race channel, then waits on `slot` for
# the verdict: True means it won and its value is wanted on `box`; False
# or a closed slot means it lost and cleans up with `lose`. The verdict
# is explicit because a Ready can land just after a Late was read, and a
# value dropped on the way is a leak.

def runner.fin(-A: Type, lose: A -> IO(Unit), +box: Chan(A), value: A, verdict: Maybe<&1, Bool>) -> IO(Unit):
  match verdict:
    case Some{True{}}:
      IO.bind(Bool, Unit, Chan.send(A, box, value), ok => IO.pure(Unit, Unit{}))
    case Some{False{}}:
      lose(value)
    case None{}:
      lose(value)

def runner.go(-A: Type, lose: A -> IO(Unit), +slot: Chan(Bool), +box: Chan(A), value: A, sent: Bool) -> IO(Unit):
  IO.bind(Maybe<&1, Bool>, Unit, Chan.recv(Bool, slot), runner.fin(A, lose, box, value))

def runner(-A: Type, lose: A -> IO(Unit), +race: Chan(Flag), +slot: Chan(Bool), +box: Chan(A), act: IO(A)) -> IO(Unit):
  IO.bind(A, Unit, act, v => IO.bind(Bool, Unit, Chan.send(Flag, race, Ready{}), runner.go(A, lose, slot, box, v)))

# Winner
# ------

def taken(-A: Type, got: Maybe<&1, A>) -> Raced<A>:
  match got:
    case None{}:
      Lost{}
    case Some{v}:
      Won{v}

# The runner won: ask for its value.
def take(-A: Type, +slot: Chan(Bool), +box: Chan(A)) -> IO(Raced<A>):
  do IO<Raced<A>>:
    told : Bool <- Chan.send(Bool, slot, True{})
    got : Maybe<&1, A> <- Chan.recv(A, box)
    Chan.close(Bool, slot)
    Chan.close(A, box)
    return taken(A, got)

# The deadline won: the runner, whenever it finishes, cleans up.
def give_up(-A: Type, +slot: Chan(Bool), +box: Chan(A)) -> IO(Raced<A>):
  do IO<Raced<A>>:
    Chan.close(Bool, slot)
    Chan.close(A, box)
    return Lost{}

# A Late for the live generation ends the race; a stale one is skipped.
def resolve(+race: Chan(Flag), live: Bool) -> IO(Maybe<&1, Flag>):
  match live:
    case True{}:
      IO.pure(Maybe<&1, Flag>, None{})
    case False{}:
      Chan.recv(Flag, race)

def settle(-A: Type, fuel: Nat, +race: Chan(Flag), +slot: Chan(Bool), +box: Chan(A), +gen: U32, got: Maybe<&1, Flag>) -> IO(Raced<A>):
  match fuel got:
    case _ None{}:
      give_up(A, slot, box)
    case _ Some{Ready{}}:
      take(A, slot, box)
    case 0n Some{Late{g}}:
      give_up(A, slot, box)
    case 1n+p Some{Late{g}}:
      do IO<Raced<A>>:
        next : Maybe<&1, Flag> <- resolve(race, U32.is_eq(g, gen))
        settle(A, p, race, slot, box, gen, next)

def within.box(-A: Type, lose: A -> IO(Unit), +race: Chan(Flag), +gen: U32, act: IO(A), +slot: Chan(Bool), box: Chan(A)) -> IO(Raced<A>):
  +b = box
  do IO<Raced<A>>:
    IO.spawn(Unit, runner(A, lose, race, slot, b, act))
    got : Maybe<&1, Flag> <- Chan.recv(Flag, race)
    settle(A, 8n, race, slot, b, gen, got)

def within.slot(-A: Type, lose: A -> IO(Unit), +race: Chan(Flag), +gen: U32, act: IO(A), slot: Chan(Bool)) -> IO(Raced<A>):
  +s = slot
  IO.bind(Chan(A), Raced<A>, Chan.new(A, 1), within.box(A, lose, race, gen, act, s))

# Runs `act` against the deadline of generation `gen`. `Won` carries its
# value; on `Lost` the value, when it arrives, goes to `lose` instead.
def within(-A: Type, lose: A -> IO(Unit), +clock: Clock, +gen: U32, act: IO(A)) -> IO(Raced<A>):
  match clock:
    case Clock{race, dial, step}:
      IO.bind(Chan(Bool), Raced<A>, Chan.new(Bool, 1), within.slot(A, lose, race, gen, act))
