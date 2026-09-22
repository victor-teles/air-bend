import Base

# Text
# ====
#
# String helpers the rest of Air is built on. Everything here is
# tail-recursive so it is safe on a request buffer; `String.append`,
# `String.length` and `String.split` from Base are not.

# A reusable pair of strings; `String & String` is the affine pair.
def Two() -> Data:
  Sigma<&2, &2, String, _ => String>

def fst(kv: Two()) -> String:
  (k, v) = kv
  k

def snd(kv: Two()) -> String:
  (k, v) = kv
  v

# Prepends `xs` reversed onto `acc`. Tail-recursive, unlike `String.append`.
def rev_onto(xs: String, acc: String) -> String:
  match xs:
    case SNil{}:
      acc
    case SCon{h, t}:
      rev_onto(t, SCon{h, acc})

# `a ++ b` without a stack frame per character of `a`: use it when `a` may
# be large, such as a request buffer.
def append(a: String, b: String) -> String:
  rev_onto(String.reverse(a), b)

def non_empty(s: String) -> Bool:
  Bool.not(String.is_empty(s))

def head_is(s: String, +c: Char) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{h, t}:
      Char.is_eq(h, c)

# Splits at the first `sep`. `hit` says whether `s` starts with `sep`.
# Without a `sep`, the whole string is the first half.
def split_once(s: String, +sep: Char, acc: String, hit: Bool) -> Two():
  match s hit:
    case _ True{}:
      (String.reverse(acc), String.drop(s, 1n))
    case SNil{} False{}:
      (String.reverse(acc), SNil{})
    case SCon{h, +t} False{}:
      split_once(t, sep, SCon{h, acc}, head_is(t, sep))

def split_at(+s: String, +sep: Char) -> Two():
  split_once(s, sep, SNil{}, head_is(s, sep))

# Splits at the first occurrence of the substring `sep`, if any.
def split_seq(s: String, +sep: String, acc: String, hit: Bool) -> Maybe<&2, Two()>:
  match s hit:
    case _ True{}:
      Some{(String.reverse(acc), String.drop(s, String.length(sep)))}
    case SNil{} False{}:
      None{}
    case SCon{h, +t} False{}:
      split_seq(t, sep, SCon{h, acc}, String.starts_with(t, sep))

def split_str(+s: String, +sep: String) -> Maybe<&2, Two()>:
  split_seq(s, sep, SNil{}, String.starts_with(s, sep))

# Splits on every occurrence of the substring `sep`, tail-recursively.
# `hit` says whether `s` starts with `sep`; `skip` counts the characters
# of a matched `sep` still to pass over, during which `hit` is ignored.
def split_seq_all.go(s: String, +sep: String, line: String, acc: List<&2, String>, +tail_len: Nat, skip: Nat, hit: Bool) -> List<&2, String>:
  match s skip hit:
    case SNil{} _ _:
      List.reverse(&2, String, Con{String.reverse(line), acc})
    case SCon{h, +t} 1n+k _:
      split_seq_all.go(t, sep, line, acc, tail_len, k, String.starts_with(t, sep))
    case SCon{h, +t} 0n True{}:
      split_seq_all.go(t, sep, SNil{}, Con{String.reverse(line), acc}, tail_len, tail_len, String.starts_with(t, sep))
    case SCon{h, +t} 0n False{}:
      split_seq_all.go(t, sep, SCon{h, line}, acc, tail_len, 0n, String.starts_with(t, sep))

def pred(n: Nat) -> Nat:
  match n:
    case 0n:
      0n
    case 1n+p:
      p

def split_seq_all(+s: String, +sep: String) -> List<&2, String>:
  split_seq_all.go(s, sep, SNil{}, Nil{}, pred(String.length(sep)), 0n, Bool.and(non_empty(sep), String.starts_with(s, sep)))

# Splits on every `sep`. Tail-recursive, unlike `String.split`, so it is
# safe on a request head. `hit` says whether `s` starts with `sep`.
def split_all.go(s: String, +sep: Char, line: String, acc: List<&2, String>, hit: Bool) -> List<&2, String>:
  match s hit:
    case SNil{} _:
      List.reverse(&2, String, Con{String.reverse(line), acc})
    case SCon{h, +t} True{}:
      split_all.go(t, sep, SNil{}, Con{String.reverse(line), acc}, head_is(t, sep))
    case SCon{h, +t} False{}:
      split_all.go(t, sep, SCon{h, line}, acc, head_is(t, sep))

def split_all(+s: String, +sep: Char) -> List<&2, String>:
  split_all.go(s, sep, SNil{}, Nil{}, head_is(s, sep))

def push_non_empty(acc: List<&2, String>, +seg: String) -> List<&2, String>:
  match seg:
    case SNil{}:
      acc
    case SCon{h, t}:
      Con{seg, acc}

# The non-empty segments of a path: "/users//42/" gives ["users", "42"].
def segments.go(s: String, line: String, acc: List<&2, String>, hit: Bool) -> List<&2, String>:
  match s hit:
    case SNil{} _:
      List.reverse(&2, String, push_non_empty(acc, String.reverse(line)))
    case SCon{h, +t} True{}:
      segments.go(t, SNil{}, push_non_empty(acc, String.reverse(line)), head_is(t, '/'))
    case SCon{h, +t} False{}:
      segments.go(t, SCon{h, line}, acc, head_is(t, '/'))

def segments(+path: String) -> List<&2, String>:
  segments.go(path, SNil{}, Nil{}, head_is(path, '/'))

def map_get.fin(r: Map<&2, String> & String) -> String:
  (m, v) = r
  v

def map_get(m: Map<&2, String>, key: String, d: String) -> String:
  map_get.fin(Map.get(String, d, m, key))

def count(xs: List<&2, String>, +acc: U32) -> U32:
  match xs:
    case Nil{}:
      acc
    case Con{h, t}:
      count(t, U32.add(acc, 1))

# Drops the empty lines a client may send between requests.
def drop_crlf(+s: String) -> String:
  match s:
    case SCon{'\r', SCon{'\n', t}}:
      drop_crlf(t)
    case _:
      s

# Whether `v`, a comma-separated header value, lists the token `tok`.
def has_token.go(parts: List<&2, String>, +tok: String, found: Bool) -> Bool:
  match parts found:
    case _ True{}:
      True{}
    case Nil{} False{}:
      False{}
    case Con{h, t} False{}:
      has_token.go(t, tok, String.eq(String.to_lower(String.trim(h)), tok))

def has_token(v: String, +tok: String) -> Bool:
  has_token.go(split_all(v, ','), tok, False{})

# A strict decimal: digits only, no sign, no overflow. `U32.read` is
# looser than that, and a Content-Length must not be.
def digits.go(s: String, +acc: U32, ok: Bool) -> Maybe<&2, U32>:
  match s ok:
    case _ False{}:
      None{}
    case SNil{} True{}:
      Some{acc}
    case SCon{+h, t} True{}:
      digits.go(
        t,
        U32.add(U32.mul(acc, 10), U32.sub(Char.to_u32(h), 48)),
        Bool.and(Char.is_digit(h), U32.is_le(acc, 429496728)))

def digits(+s: String) -> Maybe<&2, U32>:
  digits.go(s, 0, non_empty(s))

def digits_or.fin(d: Maybe<&2, U32>, +fallback: U32) -> U32:
  match d:
    case None{}:
      fallback
    case Some{n}:
      n

# `digits`, with `fallback` for anything that is not one.
def digits_or(+s: String, +fallback: U32) -> U32:
  digits_or.fin(digits(s), fallback)

# The lowercase hex digit for 0..15.
def hex_digit(+n: U32) -> Char:
  Char.from_u32(Bool.pick(U32, U32.is_lt(n, 10), U32.add(48, n), U32.add(87, n)))

def hex_show.go(digits: Nat, +n: U32, acc: String) -> String:
  match digits:
    case 0n:
      acc
    case 1n+k:
      hex_show.go(k, U32.div(n, 16), SCon{hex_digit(U32.mod(n, 16)), acc})

# Eight lowercase hex digits, zero-padded.
def hex_show(n: U32) -> String:
  hex_show.go(8n, n, SNil{})

# FNV-1a over the code points; start `acc` at `fnv_seed()`.
def fnv1a(s: String, +acc: U32) -> U32:
  match s:
    case SNil{}:
      acc
    case SCon{h, t}:
      fnv1a(t, U32.mul(U32.xor(acc, Char.to_u32(h)), 16777619))

def fnv_seed() -> U32:
  2166136261

# The value of a hex digit, or 16 when it is not one.
def hex_val(+x: U32) -> U32:
  Bool.pick(U32, Bool.and(U32.is_ge(x, 48), U32.is_le(x, 57)), U32.sub(x, 48),
    Bool.pick(U32, Bool.and(U32.is_ge(x, 97), U32.is_le(x, 102)), U32.sub(x, 87),
      Bool.pick(U32, Bool.and(U32.is_ge(x, 65), U32.is_le(x, 70)), U32.sub(x, 55), 16)))

def hex.go(s: String, +acc: U32, ok: Bool) -> Maybe<&2, U32>:
  match s ok:
    case _ False{}:
      None{}
    case SNil{} True{}:
      Some{acc}
    case SCon{h, t} True{}:
      +v = hex_val(Char.to_u32(h))
      hex.go(t, U32.add(U32.mul(acc, 16), v), Bool.and(U32.is_lt(v, 16), U32.is_le(acc, 268435455)))

def hex(+s: String) -> Maybe<&2, U32>:
  hex.go(s, 0, non_empty(s))

# UTF-8 byte count, which is what Content-Length counts.
def char_bytes(+x: U32) -> U32:
  Bool.pick(U32, U32.is_lt(x, 128), 1,
    Bool.pick(U32, U32.is_lt(x, 2048), 2,
      Bool.pick(U32, U32.is_lt(x, 65536), 3, 4)))

def byte_length(s: String, acc: U32) -> U32:
  match s:
    case SNil{}:
      acc
    case SCon{h, t}:
      byte_length(t, U32.add(acc, char_bytes(Char.to_u32(h))))

# The first `n` bytes of a string and what follows them. `TakeNeed` asks
# for more input; `TakeBad` means byte `n` falls inside a character.
type Take is Data:
  Took{head: String, rest: String}
  TakeNeed{}
  TakeBad{}

def take_bytes.go(t: String, done: Bool, fits: Bool, h: Char, +n: U32, +b: U32, acc: String) -> Take:
  match t done fits:
    case _ True{} _:
      Took{String.reverse(acc), SCon{h, t}}
    case _ False{} False{}:
      TakeBad{}
    case SNil{} False{} True{}:
      Bool.pick(Take, U32.is_eq(n, b), Took{String.reverse(SCon{h, acc}), SNil{}}, TakeNeed{})
    case SCon{+h2, t2} False{} True{}:
      +left = U32.sub(n, b)
      +b2 = char_bytes(Char.to_u32(h2))
      take_bytes.go(t2, U32.is_eq(left, 0), U32.is_le(b2, left), h2, left, b2, SCon{h, acc})

def take_bytes(s: String, +n: U32) -> Take:
  match s:
    case SNil{}:
      Bool.pick(Take, U32.is_eq(n, 0), Took{SNil{}, SNil{}}, TakeNeed{})
    case SCon{+h, t}:
      +b = char_bytes(Char.to_u32(h))
      take_bytes.go(t, U32.is_eq(n, 0), U32.is_le(b, n), h, n, b, SNil{})

# Percent-decoding
# ----------------
#
# `%XX` escapes are bytes, and a non-ASCII character arrives as two to
# four of them, so the decoder assembles UTF-8 as it goes. A multi-byte
# sequence in progress is `Open`; anything but its next continuation
# byte is an error.
type Utf8 is Data:
  Closed{}
  Open{need: U32, cp: U32, floor: U32}

# The decoder's state between characters: the output so far, reversed,
# and the UTF-8 sequence in progress. `Bad` is sticky.
type Decoding is Data:
  Bad{}
  Next{acc: String, utf8: Utf8}

def on_char(acc: String, st: Utf8, c: Char) -> Decoding:
  match st:
    case Closed{}:
      Next{SCon{c, acc}, Closed{}}
    case Open{need, cp, floor}:
      Bad{}

# A lead byte opens a sequence sized by its high bits; an ASCII byte is
# pushed as is. NUL, a stray continuation byte and the leads UTF-8 never
# uses (C0, C1, F5 and up) are refused.
def lead.pick(acc: String, +b: U32, ok: Bool, ascii: Bool, two: Bool, three: Bool, four: Bool) -> Decoding:
  match ok ascii two three four:
    case False{} _ _ _ _:
      Bad{}
    case True{} True{} _ _ _:
      Next{SCon{Char.from_u32(b), acc}, Closed{}}
    case True{} False{} True{} _ _:
      Next{acc, Open{1, U32.and(b, 31), 128}}
    case True{} False{} False{} True{} _:
      Next{acc, Open{2, U32.and(b, 15), 2048}}
    case True{} False{} False{} False{} True{}:
      Next{acc, Open{3, U32.and(b, 7), 65536}}
    case True{} False{} False{} False{} False{}:
      Bad{}

def lead(acc: String, +b: U32, ok: Bool) -> Decoding:
  lead.pick(acc, b, ok,
    Bool.and(U32.is_ge(b, 1), U32.is_lt(b, 128)),
    Bool.and(U32.is_ge(b, 194), U32.is_le(b, 223)),
    Bool.and(U32.is_ge(b, 224), U32.is_le(b, 239)),
    Bool.and(U32.is_ge(b, 240), U32.is_le(b, 244)))

# A continuation byte adds six bits. The last one closes the sequence,
# unless the code point is overlong, a surrogate, or past U+10FFFF.
def cont.pick(acc: String, +need: U32, +cp: U32, +floor: U32, valid: Bool, last: Bool, good: Bool) -> Decoding:
  match valid last good:
    case False{} _ _:
      Bad{}
    case True{} False{} _:
      Next{acc, Open{need, cp, floor}}
    case True{} True{} True{}:
      Next{SCon{Char.from_u32(cp), acc}, Closed{}}
    case True{} True{} False{}:
      Bad{}

def cont(acc: String, +need: U32, +cp: U32, +floor: U32, +b: U32, ok: Bool) -> Decoding:
  +cp2 = U32.or(U32.shln(cp, 6n), U32.and(b, 63))
  cont.pick(acc, U32.sub(need, 1), cp2, floor,
    Bool.and(ok, Bool.and(U32.is_ge(b, 128), U32.is_le(b, 191))),
    U32.is_eq(need, 1),
    Bool.and(U32.is_ge(cp2, floor),
      Bool.and(U32.is_le(cp2, 1114111),
        Bool.not(Bool.and(U32.is_ge(cp2, 55296), U32.is_le(cp2, 57343))))))

def on_byte(acc: String, st: Utf8, +b: U32, ok: Bool) -> Decoding:
  match st:
    case Closed{}:
      lead(acc, b, ok)
    case Open{need, cp, floor}:
      cont(acc, need, cp, floor, b, ok)

# One escaped byte, given as its two hex digits (16 when not a digit).
def escape(acc: String, st: Utf8, +h1: U32, +h2: U32) -> Decoding:
  on_byte(acc, st, U32.add(U32.mul(h1, 16), h2), Bool.and(U32.is_lt(h1, 16), U32.is_lt(h2, 16)))

def percent_decode.go(s: String, +plus: Bool, d: Decoding) -> Maybe<&2, String>:
  match s d:
    case _ Bad{}:
      None{}
    case SNil{} Next{acc, Closed{}}:
      Some{String.reverse(acc)}
    case SNil{} Next{acc, Open{need, cp, floor}}:
      None{}
    case SCon{'%', SCon{h1, SCon{h2, t}}} Next{acc, st}:
      percent_decode.go(t, plus, escape(acc, st, hex_val(Char.to_u32(h1)), hex_val(Char.to_u32(h2))))
    case SCon{'%', t} Next{acc, st}:
      None{}
    case SCon{'+', t} Next{acc, st}:
      percent_decode.go(t, plus, on_char(acc, st, Bool.pick(Char, plus, ' ', '+')))
    case SCon{c, t} Next{acc, st}:
      percent_decode.go(t, plus, on_char(acc, st, c))

# Whether `s` has a character that decoding would change: '%', or '+'
# when `plus`. A scan without allocation, so a plain segment is cheap.
def needs_decode(s: String, +plus: Bool) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{'%', t}:
      True{}
    case SCon{'+', t}:
      Bool.or(plus, needs_decode(t, plus))
    case SCon{c, t}:
      needs_decode(t, plus)

def percent_decode.pick(+s: String, +plus: Bool, needed: Bool) -> Maybe<&2, String>:
  match needed:
    case True{}:
      percent_decode.go(s, plus, Next{SNil{}, Closed{}})
    case False{}:
      Some{s}

# Decodes `%XX` escapes into UTF-8 code points; `plus` turns '+' into a
# space, as query strings want. None on a bad or truncated escape, an
# escaped NUL, or an invalid, overlong or surrogate UTF-8 sequence.
def percent_decode(+s: String, +plus: Bool) -> Maybe<&2, String>:
  percent_decode.pick(s, plus, needs_decode(s, plus))

# Whether the last character is `c`. Tail-recursive and allocation-free,
# unlike `String.ends_with`, which reverses the string.
def last_is.go(s: String, +c: Char, prev: Bool) -> Bool:
  match s:
    case SNil{}:
      prev
    case SCon{h, t}:
      last_is.go(t, c, Char.is_eq(h, c))

def last_is(s: String, +c: Char) -> Bool:
  last_is.go(s, c, False{})
