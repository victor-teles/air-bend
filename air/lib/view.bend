import Base
import ./text.bend as Text
import ./json.bend as Json
import ./http.bend as Http

# View
# ====
#
# HTML templates in a Mustache subset, rendered from a JSON context:
#
#   {{name}}             the value, HTML-escaped
#   {{{name}}}           the value, raw
#   {{#name}}..{{/name}} once per item of an array, once for any other
#                        truthy value (with it as the context), else not
#   {{^name}}..{{/name}} once when the value is falsy or an empty array
#   {{.}}                the current item
#   {{! note }}          a comment
#
# Names may be dotted (`user.name`); lookup walks the context stack
# from the innermost item out, so a block over a list can still read a
# top-level field. A missing name, `null`, an array or an object prints
# as "". Malformed templates render, never fail: an unclosed `{{` is
# text, an unclosed section runs to the end, a stray `{{/x}}` is
# dropped. Bend forbids mutual recursion, so rendering walks a work
# list with a fuel, like the JSON renderer, and output grows reversed.

type Tok is Data:
  TText{s: String}
  TVar{name: String}
  TRaw{name: String}
  TOpen{name: String}
  TInv{name: String}
  TClose{name: String}
  TComment{}

# Lexing
# ------

def push_text(acc: List<&2, Tok>, s: String) -> List<&2, Tok>:
  match s:
    case SNil{}:
      acc
    case SCon{h, t}:
      Con{TText{SCon{h, t}}, acc}

def classify(+t: String) -> Tok:
  match t:
    case SCon{'#', r}:
      TOpen{String.trim(r)}
    case SCon{'^', r}:
      TInv{String.trim(r)}
    case SCon{'/', r}:
      TClose{String.trim(r)}
    case SCon{'!', r}:
      TComment{}
    case _:
      TVar{t}

def tag.put(acc: List<&2, Tok>, raw: Bool, tr: Text.Two()) -> List<&2, Tok>:
  (tag, rest) = tr
  +tag = String.trim(tag)
  push_text(Con{Bool.pick(Tok, raw, TRaw{tag}, classify(tag)), acc}, rest)

def tag.fin(acc: List<&2, Tok>, raw: Bool, +p: String, found: Maybe<&2, Text.Two()>) -> List<&2, Tok>:
  match found:
    case None{}:
      Con{TText{"{{" ++ p}, acc}
    case Some{tr}:
      tag.put(acc, raw, tr)

def tag.go(acc: List<&2, Tok>, +p: String, raw: Bool) -> List<&2, Tok>:
  match raw:
    case True{}:
      tag.fin(acc, True{}, p, Text.split_str(String.drop(p, 1n), "}}}"))
    case False{}:
      tag.fin(acc, False{}, p, Text.split_str(p, "}}"))

# What follows one `{{`: a tag and the text after it.
def tag(acc: List<&2, Tok>, +p: String) -> List<&2, Tok>:
  tag.go(acc, p, Text.head_is(p, '{'))

def lex.go(pieces: List<&2, String>, acc: List<&2, Tok>) -> List<&2, Tok>:
  match pieces:
    case Nil{}:
      List.reverse(&2, Tok, acc)
    case Con{p, t}:
      lex.go(t, tag(acc, p))

def lex.start(pieces: List<&2, String>) -> List<&2, Tok>:
  match pieces:
    case Nil{}:
      Nil{}
    case Con{first, t}:
      lex.go(t, push_text(Nil{}, first))

def lex(+template: String) -> List<&2, Tok>:
  lex.start(Text.split_seq_all(template, "{{"))

# Lookup
# ------

def find_frame(stack: List<&2, Json.Value>, +key: String, acc: Maybe<&2, Json.Value>) -> Maybe<&2, Json.Value>:
  match stack acc:
    case _ Some{v}:
      Some{v}
    case Nil{} None{}:
      None{}
    case Con{f, t} None{}:
      find_frame(t, key, Json.get(f, key))

def get_in(v: Maybe<&2, Json.Value>, +key: String) -> Maybe<&2, Json.Value>:
  match v:
    case None{}:
      None{}
    case Some{x}:
      Json.get(x, key)

def walk(segs: List<&2, String>, v: Maybe<&2, Json.Value>) -> Maybe<&2, Json.Value>:
  match segs:
    case Nil{}:
      v
    case Con{s, t}:
      walk(t, get_in(v, s))

def or_null(v: Maybe<&2, Json.Value>) -> Json.Value:
  match v:
    case None{}:
      Json.null()
    case Some{x}:
      x

def top(stack: List<&2, Json.Value>) -> Json.Value:
  match stack:
    case Nil{}:
      Json.null()
    case Con{h, t}:
      h

def find.path(+stack: List<&2, Json.Value>, segs: List<&2, String>) -> Json.Value:
  match segs:
    case Nil{}:
      Json.null()
    case Con{h, t}:
      or_null(walk(t, find_frame(stack, h, None{})))

# A name's value: `.` is the current item; `a.b` finds `a` in the
# innermost frame that has it, then walks down.
def find(+stack: List<&2, Json.Value>, +name: String) -> Json.Value:
  Bool.pick(Json.Value, String.eq(name, "."), top(stack), find.path(stack, Text.split_all(name, '.')))

# Values
# ------

def text_of(v: Json.Value) -> String:
  match v:
    case Json.Str{s}:
      s
    case Json.Num{t}:
      t
    case Json.Boolean{True{}}:
      "true"
    case Json.Boolean{False{}}:
      "false"
    case _:
      SNil{}

def truthy(v: Json.Value) -> Bool:
  match v:
    case Json.Null{}:
      False{}
    case Json.Boolean{b}:
      b
    case Json.Num{t}:
      Bool.not(String.eq(t, "0"))
    case Json.Str{s}:
      Text.non_empty(s)
    case Json.Arr{xs}:
      Bool.not(List.is_empty(&2, Json.Value, xs))
    case Json.Obj{fs}:
      True{}

# `& < > " '` as entities, onto a reversed accumulator.
def escape(s: String, rev: String) -> String:
  match s:
    case SNil{}:
      rev
    case SCon{'&', t}:
      escape(t, Text.rev_onto("&amp;", rev))
    case SCon{'<', t}:
      escape(t, Text.rev_onto("&lt;", rev))
    case SCon{'>', t}:
      escape(t, Text.rev_onto("&gt;", rev))
    case SCon{'"', t}:
      escape(t, Text.rev_onto("&quot;", rev))
    case SCon{'\'', t}:
      escape(t, Text.rev_onto("&#39;", rev))
    case SCon{c, t}:
      escape(t, SCon{c, rev})

# Sections
# --------

type Split is Data:
  Split{body: List<&2, Tok>, rest: List<&2, Tok>}

# The body of a section up to its matching close, and what follows.
def split(toks: List<&2, Tok>, depth: Nat, acc: List<&2, Tok>) -> Split:
  match toks depth:
    case Nil{} _:
      Split{List.reverse(&2, Tok, acc), Nil{}}
    case Con{TClose{n}, t} 0n:
      Split{List.reverse(&2, Tok, acc), t}
    case Con{TClose{n}, t} 1n+d:
      split(t, d, Con{TClose{n}, acc})
    case Con{TOpen{n}, t} d:
      split(t, Succ{d}, Con{TOpen{n}, acc})
    case Con{TInv{n}, t} d:
      split(t, Succ{d}, Con{TInv{n}, acc})
    case Con{tok, t} d:
      split(t, d, Con{tok, acc})

type Job is Data:
  Job{toks: List<&2, Tok>, stack: List<&2, Json.Value>}

type Out is Data:
  Out{work: List<&2, Job>, rev: String}

# Moves `rev` onto the front of `rest`, reversing it back.
def onto(rev: List<&2, Job>, rest: List<&2, Job>) -> List<&2, Job>:
  match rev:
    case Nil{}:
      rest
    case Con{j, t}:
      onto(t, Con{j, rest})

def item_jobs(xs: List<&2, Json.Value>, +body: List<&2, Tok>, +stack: List<&2, Json.Value>, acc: List<&2, Job>) -> List<&2, Job>:
  match xs:
    case Nil{}:
      acc
    case Con{x, t}:
      item_jobs(t, body, stack, Con{Job{body, Con{x, stack}}, acc})

def once(+body: List<&2, Tok>, +stack: List<&2, Json.Value>, v: Json.Value, on: Bool) -> List<&2, Job>:
  match on:
    case True{}:
      [Job{body, Con{v, stack}}]
    case False{}:
      Nil{}

# The jobs of a section, reversed: one per item, or one, or none.
def section_jobs(+body: List<&2, Tok>, +stack: List<&2, Json.Value>, +v: Json.Value) -> List<&2, Job>:
  match v:
    case Json.Arr{xs}:
      item_jobs(xs, body, stack, Nil{})
    case _:
      once(body, stack, v, truthy(v))

def inverted_jobs(+body: List<&2, Tok>, +stack: List<&2, Json.Value>, on: Bool) -> List<&2, Job>:
  match on:
    case True{}:
      Nil{}
    case False{}:
      [Job{body, stack}]

def section(+inv: Bool, +name: String, +stack: List<&2, Json.Value>, sp: Split, rest: List<&2, Job>, rev: String) -> Out:
  match sp:
    case Split{+body, after}:
      Out{onto(Bool.pick(List<&2, Job>, inv,
        inverted_jobs(body, stack, truthy(find(stack, name))),
        section_jobs(body, stack, find(stack, name))), Con{Job{after, stack}, rest}), rev}

# Rendering
# ---------

def step.tok(toks: List<&2, Tok>, +stack: List<&2, Json.Value>, rest: List<&2, Job>, rev: String) -> Out:
  match toks:
    case Nil{}:
      Out{rest, rev}
    case Con{TText{s}, t}:
      Out{Con{Job{t, stack}, rest}, Text.rev_onto(s, rev)}
    case Con{TVar{+n}, t}:
      Out{Con{Job{t, stack}, rest}, escape(text_of(find(stack, n)), rev)}
    case Con{TRaw{+n}, t}:
      Out{Con{Job{t, stack}, rest}, Text.rev_onto(text_of(find(stack, n)), rev)}
    case Con{TOpen{n}, t}:
      section(False{}, n, stack, split(t, 0n, Nil{}), rest, rev)
    case Con{TInv{n}, t}:
      section(True{}, n, stack, split(t, 0n, Nil{}), rest, rev)
    case Con{TClose{n}, t}:
      Out{Con{Job{t, stack}, rest}, rev}
    case Con{TComment{}, t}:
      Out{Con{Job{t, stack}, rest}, rev}

def step(j: Job, rest: List<&2, Job>, rev: String) -> Out:
  match j:
    case Job{toks, stack}:
      step.tok(toks, stack, rest, rev)

def go(fuel: Nat, o: Out) -> String:
  match fuel o:
    case _ Out{Nil{}, rev}:
      String.reverse(rev)
    case 0n Out{w, rev}:
      String.reverse(rev)
    case 1n+f Out{Con{j, t}, rev}:
      go(f, step(j, t, rev))

# The template with `ctx`. Bounded at ten million steps.
def render(+template: String, ctx: Json.Value) -> String:
  go(10000000n, Out{[Job{lex(template), [ctx]}], SNil{}})

# A 200 with the rendered template as HTML.
def respond(+template: String, ctx: Json.Value) -> Http.Response:
  Http.Response.html(render(template, ctx))
