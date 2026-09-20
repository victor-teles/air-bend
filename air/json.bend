import Base
import ./text.bend as Text

# JSON
# ====
#
# A value, a strict parser and a renderer. Numbers keep their lexeme:
# Bend has `U32` and `F32` only, so `Num{"12345678901"}` loses nothing
# and `u32` converts on demand. Objects are ordered field lists, as
# written. The parser takes no comments, trailing commas or leading
# zeros, refuses lone surrogates and raw control characters, and caps
# nesting at 64 so a bracket bomb cannot overflow the stack.
#
# Bend forbids mutual recursion, so the parser is one def with a mode
# argument, and every recursive call shrinks a `Nat` fuel; the renderer
# walks a work list the same way.

type Value is Data:
  Null{}
  Boolean{b: Bool}
  Num{text: String}
  Str{s: String}
  Arr{items: List<&2, Value>}
  Obj{fields: List<&2, Sigma<&2, &2, String, _ => Value>>}

# A key and its value.
def Field() -> Data:
  Sigma<&2, &2, String, _ => Value>

# Builders
# --------

def null() -> Value:
  Null{}

def of_bool(b: Bool) -> Value:
  Boolean{b}

def of_u32(n: U32) -> Value:
  Num{U32.show(n)}

# A number as written, unchecked: "-1.5e3".
def num(text: String) -> Value:
  Num{text}

def of_str(s: String) -> Value:
  Str{s}

def arr(xs: List<&2, Value>) -> Value:
  Arr{xs}

def obj(fs: List<&2, Field()>) -> Value:
  Obj{fs}

def field(key: String, v: Value) -> Field():
  (key, v)

# Accessors
# ---------
#
# All total: a value of the wrong shape reads as None, "" or [].

def get.try.pick(v: Value, same: Bool) -> Maybe<&2, Value>:
  match same:
    case True{}:
      Some{v}
    case False{}:
      None{}

def get.try(f: Field(), +key: String) -> Maybe<&2, Value>:
  (k, v) = f
  get.try.pick(v, String.eq(k, key))

def get.go(fs: List<&2, Field()>, +key: String, found: Maybe<&2, Value>) -> Maybe<&2, Value>:
  match fs found:
    case _ Some{v}:
      Some{v}
    case Nil{} None{}:
      None{}
    case Con{f, t} None{}:
      get.go(t, key, get.try(f, key))

# The first field named `key` of an object.
def get(v: Value, key: String) -> Maybe<&2, Value>:
  match v:
    case Obj{fs}:
      get.go(fs, key, None{})
    case _:
      None{}

# The `i`th item of an array.
def at(v: Value, i: Nat) -> Maybe<&2, Value>:
  match v:
    case Arr{xs}:
      List.get(&2, Value, xs, i)
    case _:
      None{}

def str(v: Value) -> Maybe<&2, String>:
  match v:
    case Str{s}:
      Some{s}
    case _:
      None{}

# A non-negative integer that fits; "-1" and "1.0" read as None.
def u32(v: Value) -> Maybe<&2, U32>:
  match v:
    case Num{text}:
      Text.digits(text)
    case _:
      None{}

def boolean(v: Value) -> Maybe<&2, Bool>:
  match v:
    case Boolean{b}:
      Some{b}
    case _:
      None{}

def is_null(v: Value) -> Bool:
  match v:
    case Null{}:
      True{}
    case _:
      False{}

def items(v: Value) -> List<&2, Value>:
  match v:
    case Arr{xs}:
      xs
    case _:
      Nil{}

def fields(v: Value) -> List<&2, Field()>:
  match v:
    case Obj{fs}:
      fs
    case _:
      Nil{}

# Rendering
# ---------

# `\u00XX`, reversed onto `rev`.
def escape.control(+code: U32, rev: String) -> String:
  SCon{Text.hex_digit(U32.mod(code, 16)), SCon{Text.hex_digit(U32.div(code, 16)), SCon{'0', SCon{'0', SCon{'u', SCon{'\\', rev}}}}}}

def escape.other(c: Char, rev: String, control: Bool) -> String:
  match control:
    case True{}:
      escape.control(Char.to_u32(c), rev)
    case False{}:
      SCon{c, rev}

# The characters of `s` escaped and reversed onto `rev`, then the
# closing quote. The opening quote is the caller's.
def escape(s: String, rev: String) -> String:
  match s:
    case SNil{}:
      SCon{'"', rev}
    case SCon{'"', t}:
      escape(t, SCon{'"', SCon{'\\', rev}})
    case SCon{'\\', t}:
      escape(t, SCon{'\\', SCon{'\\', rev}})
    case SCon{'\n', t}:
      escape(t, SCon{'n', SCon{'\\', rev}})
    case SCon{'\r', t}:
      escape(t, SCon{'r', SCon{'\\', rev}})
    case SCon{'\t', t}:
      escape(t, SCon{'t', SCon{'\\', rev}})
    case SCon{+c, t}:
      escape(t, escape.other(c, rev, U32.is_lt(Char.to_u32(c), 32)))

# What is left to render: a value, or literal text.
type Item is Data:
  Val{v: Value}
  Lit{text: String}

def with_sep(work: List<&2, Item>, sep: Bool) -> List<&2, Item>:
  match sep:
    case True{}:
      Con{Lit{","}, work}
    case False{}:
      work

# Pushes "[", the items with commas, and "]" in front of `work`. The
# items come reversed, so the last is pushed first.
def push_items.go(rev: List<&2, Value>, work: List<&2, Item>, sep: Bool) -> List<&2, Item>:
  match rev:
    case Nil{}:
      Con{Lit{"["}, work}
    case Con{v, t}:
      push_items.go(t, Con{Val{v}, with_sep(work, sep)}, True{})

def push_items(xs: List<&2, Value>, work: List<&2, Item>) -> List<&2, Item>:
  push_items.go(List.reverse(&2, Value, xs), Con{Lit{"]"}, work}, False{})

def push_fields.go(rev: List<&2, Field()>, work: List<&2, Item>, sep: Bool) -> List<&2, Item>:
  match rev:
    case Nil{}:
      Con{Lit{"{"}, work}
    case Con{f, t}:
      (k, v) = f
      push_fields.go(t, Con{Val{Str{k}}, Con{Lit{":"}, Con{Val{v}, with_sep(work, sep)}}}, True{})

def push_fields(fs: List<&2, Field()>, work: List<&2, Item>) -> List<&2, Item>:
  push_fields.go(List.reverse(&2, Field(), fs), Con{Lit{"}"}, work}, False{})

def bool_text(b: Bool) -> String:
  match b:
    case True{}:
      "true"
    case False{}:
      "false"

def render.go(fuel: Nat, work: List<&2, Item>, rev: String) -> String:
  match fuel work:
    case _ Nil{}:
      String.reverse(rev)
    case 0n _:
      String.reverse(rev)
    case 1n+f Con{Lit{text}, t}:
      render.go(f, t, Text.rev_onto(text, rev))
    case 1n+f Con{Val{Null{}}, t}:
      render.go(f, t, Text.rev_onto("null", rev))
    case 1n+f Con{Val{Boolean{b}}, t}:
      render.go(f, t, Text.rev_onto(bool_text(b), rev))
    case 1n+f Con{Val{Num{text}}, t}:
      render.go(f, t, Text.rev_onto(text, rev))
    case 1n+f Con{Val{Str{s}}, t}:
      render.go(f, t, escape(s, SCon{'"', rev}))
    case 1n+f Con{Val{Arr{xs}}, t}:
      render.go(f, push_items(xs, t), rev)
    case 1n+f Con{Val{Obj{fs}}, t}:
      render.go(f, push_fields(fs, t), rev)

# Compact JSON text. Strings escape `"`, `\`, newline, return, tab and
# other control characters; everything else goes out as is, in UTF-8.
# Bounded at ten million nodes, which is what the fuel counts.
def render(v: Value) -> String:
  render.go(10000000n, [Val{v}], SNil{})

# Parsing
# -------

def skip_ws(+s: String) -> String:
  match s:
    case SCon{' ', t}:
      skip_ws(t)
    case SCon{'\n', t}:
      skip_ws(t)
    case SCon{'\r', t}:
      skip_ws(t)
    case SCon{'\t', t}:
      skip_ws(t)
    case _:
      s

# One step of parsing: a value and what follows it (whitespace already
# skipped), a closing bracket met where a value was expected, an error,
# or nothing yet.
type Out is Data:
  Ok{v: Value, rest: String}
  Err{}
  CloseArr{rest: String}
  CloseObj{rest: String}
  Begin{}

# Strings, phase one: the raw text up to the closing quote.
type Scan is Data:
  Scanned{raw: String, rest: String}
  Unterminated{}

def scan.go(s: String, acc: String, escaped: Bool) -> Scan:
  match s escaped:
    case SNil{} _:
      Unterminated{}
    case SCon{'"', t} False{}:
      Scanned{String.reverse(acc), t}
    case SCon{'\\', t} False{}:
      scan.go(t, SCon{'\\', acc}, True{})
    case SCon{c, t} _:
      scan.go(t, SCon{c, acc}, False{})

# Strings, phase two: escapes. `hi` is a high surrogate waiting for its
# low half.
type Unesc is Data:
  Fail{}
  Go{acc: String, hi: Maybe<&2, U32>}

def hex4(+a: U32, +b: U32, +c: U32, +d: U32) -> U32:
  Bool.pick(U32,
    Bool.and(Bool.and(U32.is_lt(a, 16), U32.is_lt(b, 16)), Bool.and(U32.is_lt(c, 16), U32.is_lt(d, 16))),
    U32.add(U32.mul(U32.add(U32.mul(U32.add(U32.mul(a, 16), b), 16), c), 16), d),
    65536)

def unicode.none(acc: String, +code: U32, bad: Bool, high: Bool, low: Bool) -> Unesc:
  match bad high low:
    case True{} _ _:
      Fail{}
    case False{} True{} _:
      Go{acc, Some{code}}
    case False{} False{} True{}:
      Fail{}
    case False{} False{} False{}:
      Go{SCon{Char.from_u32(code), acc}, None{}}

def unicode.some(acc: String, +h: U32, +code: U32, low: Bool) -> Unesc:
  match low:
    case True{}:
      Go{SCon{Char.from_u32(U32.add(65536, U32.add(U32.shln(U32.sub(h, 55296), 10n), U32.sub(code, 56320)))), acc}, None{}}
    case False{}:
      Fail{}

# A `\uXXXX` escape: `code` is 65536 when a digit was not hex.
def unicode(acc: String, hi: Maybe<&2, U32>, +code: U32) -> Unesc:
  match hi:
    case None{}:
      unicode.none(acc, code, U32.is_ge(code, 65536),
        Bool.and(U32.is_ge(code, 55296), U32.is_le(code, 56319)),
        Bool.and(U32.is_ge(code, 56320), U32.is_le(code, 57343)))
    case Some{h}:
      unicode.some(acc, h, code, Bool.and(U32.is_ge(code, 56320), U32.is_le(code, 57343)))

def simple(acc: String, hi: Maybe<&2, U32>, e: Char) -> Unesc:
  match hi e:
    case Some{h} _:
      Fail{}
    case None{} '"':
      Go{SCon{'"', acc}, None{}}
    case None{} '\\':
      Go{SCon{'\\', acc}, None{}}
    case None{} '/':
      Go{SCon{'/', acc}, None{}}
    case None{} 'b':
      Go{SCon{Char.from_u32(8), acc}, None{}}
    case None{} 'f':
      Go{SCon{Char.from_u32(12), acc}, None{}}
    case None{} 'n':
      Go{SCon{'\n', acc}, None{}}
    case None{} 'r':
      Go{SCon{'\r', acc}, None{}}
    case None{} 't':
      Go{SCon{'\t', acc}, None{}}
    case None{} _:
      Fail{}

def plain.pick(acc: String, c: Char, ok: Bool) -> Unesc:
  match ok:
    case True{}:
      Go{SCon{c, acc}, None{}}
    case False{}:
      Fail{}

# A raw character: refused below 0x20, or while a surrogate is pending.
def plain(acc: String, hi: Maybe<&2, U32>, +c: Char) -> Unesc:
  match hi:
    case None{}:
      plain.pick(acc, c, U32.is_ge(Char.to_u32(c), 32))
    case Some{h}:
      Fail{}

def unescape.go(s: String, d: Unesc) -> Maybe<&2, String>:
  match s d:
    case _ Fail{}:
      None{}
    case SNil{} Go{acc, None{}}:
      Some{String.reverse(acc)}
    case SNil{} Go{acc, Some{h}}:
      None{}
    case SCon{'\\', SCon{'u', SCon{a, SCon{b, SCon{c, SCon{e, t}}}}}} Go{acc, hi}:
      unescape.go(t, unicode(acc, hi, hex4(Text.hex_val(Char.to_u32(a)), Text.hex_val(Char.to_u32(b)), Text.hex_val(Char.to_u32(c)), Text.hex_val(Char.to_u32(e)))))
    case SCon{'\\', SCon{e, t}} Go{acc, hi}:
      unescape.go(t, simple(acc, hi, e))
    case SCon{'\\', SNil{}} Go{acc, hi}:
      None{}
    case SCon{c, t} Go{acc, hi}:
      unescape.go(t, plain(acc, hi, c))

def unescape(raw: String) -> Maybe<&2, String>:
  unescape.go(raw, Go{SNil{}, None{}})

def parse.string.fin(rest: String, decoded: Maybe<&2, String>) -> Out:
  match decoded:
    case None{}:
      Err{}
    case Some{s}:
      Ok{Str{s}, skip_ws(rest)}

def parse.string.go(sc: Scan) -> Out:
  match sc:
    case Unterminated{}:
      Err{}
    case Scanned{raw, rest}:
      parse.string.fin(rest, unescape(raw))

# `t` is what follows the opening quote.
def parse.string(t: String) -> Out:
  parse.string.go(scan.go(t, SNil{}, False{}))

# Numbers: the JSON grammar as a state machine over character classes.
type Class is Data:
  Digit{}
  Zero{}
  Minus{}
  Plus{}
  Dot{}
  Exp{}
  Other{}
  End{}

def class_of(c: Char, digit: Bool) -> Class:
  match c digit:
    case '0' _:
      Zero{}
    case '-' _:
      Minus{}
    case '+' _:
      Plus{}
    case '.' _:
      Dot{}
    case 'e' _:
      Exp{}
    case 'E' _:
      Exp{}
    case _ True{}:
      Digit{}
    case _ False{}:
      Other{}

def head_class(s: String) -> Class:
  match s:
    case SNil{}:
      End{}
    case SCon{+c, t}:
      class_of(c, Char.is_digit(c))

type NumState is Data:
  NStart{}
  NNeg{}
  NIntZero{}
  NIntDigits{}
  NFrac0{}
  NFracDigits{}
  NExp0{}
  NExpSign{}
  NExpDigits{}
  NStop{}
  NBad{}

# The next state, `NStop` when the class ends the number, `NBad` when
# it cannot follow.
def step(st: NumState, cls: Class) -> NumState:
  match st cls:
    case NStart{} Minus{}:
      NNeg{}
    case NStart{} Zero{}:
      NIntZero{}
    case NStart{} Digit{}:
      NIntDigits{}
    case NStart{} _:
      NBad{}
    case NNeg{} Zero{}:
      NIntZero{}
    case NNeg{} Digit{}:
      NIntDigits{}
    case NNeg{} _:
      NBad{}
    case NIntZero{} Dot{}:
      NFrac0{}
    case NIntZero{} Exp{}:
      NExp0{}
    case NIntZero{} Digit{}:
      NBad{}
    case NIntZero{} Zero{}:
      NBad{}
    case NIntZero{} _:
      NStop{}
    case NIntDigits{} Digit{}:
      NIntDigits{}
    case NIntDigits{} Zero{}:
      NIntDigits{}
    case NIntDigits{} Dot{}:
      NFrac0{}
    case NIntDigits{} Exp{}:
      NExp0{}
    case NIntDigits{} _:
      NStop{}
    case NFrac0{} Digit{}:
      NFracDigits{}
    case NFrac0{} Zero{}:
      NFracDigits{}
    case NFrac0{} _:
      NBad{}
    case NFracDigits{} Digit{}:
      NFracDigits{}
    case NFracDigits{} Zero{}:
      NFracDigits{}
    case NFracDigits{} Exp{}:
      NExp0{}
    case NFracDigits{} _:
      NStop{}
    case NExp0{} Plus{}:
      NExpSign{}
    case NExp0{} Minus{}:
      NExpSign{}
    case NExp0{} Digit{}:
      NExpDigits{}
    case NExp0{} Zero{}:
      NExpDigits{}
    case NExp0{} _:
      NBad{}
    case NExpSign{} Digit{}:
      NExpDigits{}
    case NExpSign{} Zero{}:
      NExpDigits{}
    case NExpSign{} _:
      NBad{}
    case NExpDigits{} Digit{}:
      NExpDigits{}
    case NExpDigits{} Zero{}:
      NExpDigits{}
    case NExpDigits{} _:
      NStop{}
    case NStop{} _:
      NBad{}
    case NBad{} _:
      NBad{}

def accepting(st: NumState) -> Bool:
  match st:
    case NIntZero{}:
      True{}
    case NIntDigits{}:
      True{}
    case NFracDigits{}:
      True{}
    case NExpDigits{}:
      True{}
    case _:
      False{}

def parse.number.fin(acc: String, rest: String, ok: Bool) -> Out:
  match ok:
    case True{}:
      Ok{Num{String.reverse(acc)}, skip_ws(rest)}
    case False{}:
      Err{}

# `st` is the state after `acc`; `next` the state after the head of `s`.
def parse.number.go(s: String, acc: String, st: NumState, +next: NumState) -> Out:
  match s next:
    case _ NBad{}:
      Err{}
    case _ NStop{}:
      parse.number.fin(acc, s, accepting(st))
    case SNil{} _:
      Err{}
    case SCon{c, +t} _:
      parse.number.go(t, SCon{c, acc}, next, step(next, head_class(t)))

def parse.number(+s: String) -> Out:
  parse.number.go(s, SNil{}, NStart{}, step(NStart{}, head_class(s)))

def literal.pick(ok: Bool, v: Value, rest: String) -> Out:
  match ok:
    case True{}:
      Ok{v, skip_ws(rest)}
    case False{}:
      Err{}

# `t` follows the literal's first letter; `expect` is the rest of it.
def literal(+t: String, +expect: String, v: Value) -> Out:
  literal.pick(String.starts_with(t, expect), v, String.drop(t, String.length(expect)))

# Where the parser is: at a value, or back in a container with the
# result of parsing its next piece.
type Mode is Data:
  Top{}
  Items{acc: List<&2, Value>}
  Fields{acc: List<&2, Field()>}
  Pending{acc: List<&2, Field()>, key: String}

# One def for values, arrays and objects. `fuel` shrinks on every
# call; `depth` on every container. `s` matters in `Top` only; `r` is
# the result of the nested parse in the other modes.
def parse.go(+fuel: Nat, +depth: Nat, mode: Mode, s: String, r: Out) -> Out:
  match fuel depth mode s r:
    case 0n _ _ _ _:
      Err{}
    case 1n+f _ Top{} SNil{} _:
      Err{}
    case 1n+f 1n+d Top{} SCon{'[', t} _:
      parse.go(f, depth, Items{Nil{}}, SNil{}, parse.go(f, d, Top{}, skip_ws(t), Begin{}))
    case 1n+f 1n+d Top{} SCon{'{', t} _:
      parse.go(f, depth, Fields{Nil{}}, SNil{}, parse.go(f, d, Top{}, skip_ws(t), Begin{}))
    case 1n+f 0n Top{} SCon{'[', t} _:
      Err{}
    case 1n+f 0n Top{} SCon{'{', t} _:
      Err{}
    case 1n+f _ Top{} SCon{']', t} _:
      CloseArr{skip_ws(t)}
    case 1n+f _ Top{} SCon{'}', t} _:
      CloseObj{skip_ws(t)}
    case 1n+f _ Top{} SCon{'"', t} _:
      parse.string(t)
    case 1n+f _ Top{} SCon{'t', t} _:
      literal(t, "rue", Boolean{True{}})
    case 1n+f _ Top{} SCon{'f', t} _:
      literal(t, "alse", Boolean{False{}})
    case 1n+f _ Top{} SCon{'n', t} _:
      literal(t, "ull", Null{})
    case 1n+f _ Top{} SCon{c, t} _:
      parse.number(SCon{c, t})
    case 1n+f 1n+d Items{acc} _ Ok{v, SCon{',', t}}:
      parse.go(f, depth, Items{Con{v, acc}}, SNil{}, parse.go(f, d, Top{}, skip_ws(t), Begin{}))
    case 1n+f _ Items{acc} _ Ok{v, SCon{']', t}}:
      Ok{Arr{List.reverse(&2, Value, Con{v, acc})}, skip_ws(t)}
    case 1n+f _ Items{Nil{}} _ CloseArr{t}:
      Ok{Arr{Nil{}}, t}
    case 1n+f _ Items{acc} _ _:
      Err{}
    case 1n+f 1n+d Fields{acc} _ Ok{Str{k}, SCon{':', t}}:
      parse.go(f, depth, Pending{acc, k}, SNil{}, parse.go(f, d, Top{}, skip_ws(t), Begin{}))
    case 1n+f _ Fields{Nil{}} _ CloseObj{t}:
      Ok{Obj{Nil{}}, t}
    case 1n+f _ Fields{acc} _ _:
      Err{}
    case 1n+f 1n+d Pending{acc, k} _ Ok{v, SCon{',', t}}:
      parse.go(f, depth, Fields{Con{(k, v), acc}}, SNil{}, parse.go(f, d, Top{}, skip_ws(t), Begin{}))
    case 1n+f _ Pending{acc, k} _ Ok{v, SCon{'}', t}}:
      Ok{Obj{List.reverse(&2, Field(), Con{(k, v), acc})}, skip_ws(t)}
    case 1n+f _ Pending{acc, k} _ _:
      Err{}

def parse.fin(r: Out) -> Maybe<&2, Value>:
  match r:
    case Ok{v, SNil{}}:
      Some{v}
    case _:
      None{}

# Nesting deeper than this is refused.
def max_depth() -> Nat:
  64n

# Every step consumes a character, so twice the length is fuel enough.
def fuel_for(+s: String) -> Nat:
  U32.to_nat(U32.add(U32.mul(2, Text.byte_length(s, 0)), 8))

# A value from JSON text, or None when the text is not exactly one
# strict JSON value (surrounding whitespace allowed).
def parse(+s: String) -> Maybe<&2, Value>:
  parse.fin(parse.go(fuel_for(s), max_depth(), Top{}, skip_ws(s), Begin{}))
