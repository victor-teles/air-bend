import Base
import ./text.bend as Text

# Random
# ======
#
# Ids from the host's entropy. Each `IO.random_u32` goes through the
# runtime's worker pool and costs like a system call, so draw as few
# words as the use needs: one for a request id, four for a token.

def draw.fin(r: Result<&1, &1, U32 & String, U32>) -> IO(U32):
  match r:
    case Done{n}:
      IO.pure(U32, n)
    case Fail{e}:
      IO.bind(Nat, U32, IO.now(), now => IO.pure(U32, U32.from_nat(now)))

# A random word; when the source fails, the clock's low bits.
def draw() -> IO(U32):
  IO.bind(Result<&1, &1, U32 & String, U32>, U32, IO.random_u32(), draw.fin)

# Sixteen lowercase hex characters from two words.
def hex_id(a: U32, b: U32) -> String:
  Text.hex_show(a) ++ Text.hex_show(b)

# A random word and the millisecond it was made: unique enough to tell
# requests apart in a log, which is all a request id is for.
def fresh_id() -> IO(String):
  do IO<String>:
    a : U32 <- draw()
    now : Nat <- IO.now()
    return hex_id(a, U32.from_nat(now))

# Thirty-two hex characters of entropy: a session token, not guessable.
def token() -> IO(String):
  do IO<String>:
    a : U32 <- draw()
    b : U32 <- draw()
    c : U32 <- draw()
    d : U32 <- draw()
    return hex_id(a, b) ++ hex_id(c, d)

def safe_char(+c: Char) -> Bool:
  Bool.or(Char.is_alpha(c), Bool.or(Char.is_digit(c),
    Bool.or(Char.is_eq(c, '-'), Bool.or(Char.is_eq(c, '_'), Char.is_eq(c, '.')))))

def safe_id.go(s: String, +n: U32, ok: Bool) -> Bool:
  match s ok:
    case _ False{}:
      False{}
    case SNil{} True{}:
      Bool.and(U32.is_ge(n, 1), U32.is_le(n, 128))
    case SCon{h, t} True{}:
      safe_id.go(t, U32.inc(n), safe_char(h))

# One to 128 characters, each a letter, a digit, `-`, `_` or `.`: an id
# a proxy set, a log line can carry, and a store key can hold.
def safe_id(s: String) -> Bool:
  safe_id.go(s, 0, True{})
