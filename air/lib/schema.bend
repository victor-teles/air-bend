import Base
import ./text.bend as Text
import ./json.bend as Json
import ./http.bend as Http

# Schema
# ======
#
# A schema is a value describing a JSON value; `errors` checks one and
# lists every problem at once, each with a path: "name: expected
# string", "tags[2]: expected integer", "missing: email", "unknown:
# nickname". An empty list means valid. Three middleware check a body,
# a query string or the path params before the handler runs and answer
# 422 with the list.
#
# Query strings and params are strings by nature, so they are checked
# leniently: an integer may be "42", a boolean "true" or "false", a
# number any JSON number spelling, a null "". Bodies are strict.
#
# Bend forbids mutual recursion, so the checker walks a work list with
# a fuel, like the JSON renderer: a field or an item becomes a job.

type Schema is Data:
  SAny{}
  SStr{}
  SNum{}
  SInt{}
  SBool{}
  SNull{}
  SEnum{options: List<&2, String>}
  SArr{each: Schema}
  SObj{props: List<&2, Sigma<&2, &2, String, _ => Schema>>, strict: Bool}
  SOpt{inner: Schema}

def Prop() -> Data:
  Sigma<&2, &2, String, _ => Schema>

# Builders
# --------

def any() -> Schema:
  SAny{}

def str() -> Schema:
  SStr{}

def num() -> Schema:
  SNum{}

# A non-negative integer that fits in 32 bits.
def int() -> Schema:
  SInt{}

def boolean() -> Schema:
  SBool{}

def null() -> Schema:
  SNull{}

def one_of(options: List<&2, String>) -> Schema:
  SEnum{options}

def arr(each: Schema) -> Schema:
  SArr{each}

# An object that refuses keys it does not list.
def obj(props: List<&2, Prop()>) -> Schema:
  SObj{props, True{}}

# An object that lets other keys through.
def obj_open(props: List<&2, Prop()>) -> Schema:
  SObj{props, False{}}

# A required field.
def field(name: String, s: Schema) -> Prop():
  (name, s)

# A field that may be absent; when present it must match.
def optional(name: String, s: Schema) -> Prop():
  (name, SOpt{s})

# Paths and messages
# ------------------

def join.go(+path: String, +name: String, root: Bool) -> String:
  match root:
    case True{}:
      name
    case False{}:
      path ++ "." ++ name

def join(+path: String, +name: String) -> String:
  join.go(path, name, String.is_empty(path))

def index(+path: String, +i: U32) -> String:
  path ++ "[" ++ U32.show(i) ++ "]"

def msg.go(+path: String, +text: String, root: Bool) -> String:
  match root:
    case True{}:
      text
    case False{}:
      path ++ ": " ++ text

def msg(+path: String, +text: String) -> String:
  msg.go(path, text, String.is_empty(path))

# Leaves
# ------

def num_text(v: Maybe<&2, Json.Value>) -> Bool:
  match v:
    case Some{Json.Num{t}}:
      True{}
    case _:
      False{}

def is_some(d: Maybe<&2, U32>) -> Bool:
  match d:
    case None{}:
      False{}
    case Some{n}:
      True{}

def is_str(+lenient: Bool, v: Json.Value) -> Bool:
  match v:
    case Json.Str{s}:
      True{}
    case _:
      False{}

def is_num(+lenient: Bool, v: Json.Value) -> Bool:
  match v:
    case Json.Num{t}:
      True{}
    case Json.Str{+s}:
      Bool.and(lenient, num_text(Json.parse(s)))
    case _:
      False{}

def is_int(+lenient: Bool, v: Json.Value) -> Bool:
  match v:
    case Json.Num{+t}:
      is_some(Text.digits(t))
    case Json.Str{+s}:
      Bool.and(lenient, is_some(Text.digits(s)))
    case _:
      False{}

def is_bool(+lenient: Bool, v: Json.Value) -> Bool:
  match v:
    case Json.Boolean{b}:
      True{}
    case Json.Str{+s}:
      Bool.and(lenient, Bool.or(String.eq(s, "true"), String.eq(s, "false")))
    case _:
      False{}

def is_null(+lenient: Bool, v: Json.Value) -> Bool:
  match v:
    case Json.Null{}:
      True{}
    case Json.Str{s}:
      Bool.and(lenient, String.is_empty(s))
    case _:
      False{}

def listed(options: List<&2, String>, +s: String) -> Bool:
  match options:
    case Nil{}:
      False{}
    case Con{h, t}:
      Bool.or(String.eq(h, s), listed(t, s))

def in_enum(options: List<&2, String>, v: Json.Value) -> Bool:
  match v:
    case Json.Str{+s}:
      listed(options, s)
    case _:
      False{}

# Jobs
# ----

type Job is Data:
  Check{schema: Schema, path: String, v: Json.Value}
  Report{text: String}

type Next is Data:
  Next{work: List<&2, Job>, acc: List<&2, String>}

def leaf(+path: String, +text: String, rest: List<&2, Job>, acc: List<&2, String>, ok: Bool) -> Next:
  match ok:
    case True{}:
      Next{rest, acc}
    case False{}:
      Next{rest, Con{msg(path, text), acc}}

def item_jobs(+each: Schema, +path: String, xs: List<&2, Json.Value>, +i: U32) -> List<&2, Job>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{x, t}:
      Con{Check{each, index(path, i), x}, item_jobs(each, path, t, U32.inc(i))}

def is_opt(s: Schema) -> Bool:
  match s:
    case SOpt{i}:
      True{}
    case _:
      False{}

def prop_job.pick(+s: Schema, +name: String, +path: String, found: Maybe<&2, Json.Value>) -> List<&2, Job>:
  match found:
    case Some{v}:
      [Check{s, join(path, name), v}]
    case None{}:
      Bool.pick(List<&2, Job>, is_opt(s), Nil{}, [Report{"missing: " ++ join(path, name)}])

def prop_job(p: Prop(), +path: String, +fs: List<&2, Json.Field()>) -> List<&2, Job>:
  (name, s) = p
  +name = name
  prop_job.pick(s, name, path, Json.get(Json.Obj{fs}, name))

def prop_jobs(props: List<&2, Prop()>, +path: String, +fs: List<&2, Json.Field()>) -> List<&2, Job>:
  match props:
    case Nil{}:
      Nil{}
    case Con{p, t}:
      List.append(&2, Job, prop_job(p, path, fs), prop_jobs(t, path, fs))

def prop_name(p: Prop()) -> String:
  (k, v) = p
  k

def declared(props: List<&2, Prop()>, +name: String) -> Bool:
  match props:
    case Nil{}:
      False{}
    case Con{p, t}:
      Bool.or(String.eq(prop_name(p), name), declared(t, name))

def unknown_job(+props: List<&2, Prop()>, +path: String, f: Json.Field()) -> List<&2, Job>:
  (name, v) = f
  +name = name
  Bool.pick(List<&2, Job>, declared(props, name), Nil{}, [Report{"unknown: " ++ join(path, name)}])

def unknown_jobs(+props: List<&2, Prop()>, +path: String, fs: List<&2, Json.Field()>) -> List<&2, Job>:
  match fs:
    case Nil{}:
      Nil{}
    case Con{f, t}:
      List.append(&2, Job, unknown_job(props, path, f), unknown_jobs(props, path, t))

def obj_jobs(+props: List<&2, Prop()>, +path: String, +fs: List<&2, Json.Field()>, strict: Bool) -> List<&2, Job>:
  match strict:
    case True{}:
      List.append(&2, Job, prop_jobs(props, path, fs), unknown_jobs(props, path, fs))
    case False{}:
      prop_jobs(props, path, fs)

def check.arr(+each: Schema, +path: String, v: Json.Value, rest: List<&2, Job>, acc: List<&2, String>) -> Next:
  match v:
    case Json.Arr{xs}:
      Next{List.append(&2, Job, item_jobs(each, path, xs, 0), rest), acc}
    case _:
      Next{rest, Con{msg(path, "expected array"), acc}}

def check.obj(+props: List<&2, Prop()>, +strict: Bool, +path: String, v: Json.Value, rest: List<&2, Job>, acc: List<&2, String>) -> Next:
  match v:
    case Json.Obj{fs}:
      Next{List.append(&2, Job, obj_jobs(props, path, fs, strict), rest), acc}
    case _:
      Next{rest, Con{msg(path, "expected object"), acc}}

def check(+lenient: Bool, s: Schema, +path: String, v: Json.Value, rest: List<&2, Job>, acc: List<&2, String>) -> Next:
  match s:
    case SAny{}:
      Next{rest, acc}
    case SStr{}:
      leaf(path, "expected string", rest, acc, is_str(lenient, v))
    case SNum{}:
      leaf(path, "expected number", rest, acc, is_num(lenient, v))
    case SInt{}:
      leaf(path, "expected integer", rest, acc, is_int(lenient, v))
    case SBool{}:
      leaf(path, "expected boolean", rest, acc, is_bool(lenient, v))
    case SNull{}:
      leaf(path, "expected null", rest, acc, is_null(lenient, v))
    case SEnum{+options}:
      leaf(path, "expected one of " ++ String.join(options, ", "), rest, acc, in_enum(options, v))
    case SArr{each}:
      check.arr(each, path, v, rest, acc)
    case SObj{props, strict}:
      check.obj(props, strict, path, v, rest, acc)
    case SOpt{inner}:
      Next{Con{Check{inner, path, v}, rest}, acc}

def step(+lenient: Bool, j: Job, rest: List<&2, Job>, acc: List<&2, String>) -> Next:
  match j:
    case Check{s, path, v}:
      check(lenient, s, path, v, rest, acc)
    case Report{text}:
      Next{rest, Con{text, acc}}

def run(fuel: Nat, +lenient: Bool, n: Next) -> List<&2, String>:
  match fuel n:
    case _ Next{Nil{}, acc}:
      List.reverse(&2, String, acc)
    case 0n Next{w, acc}:
      List.reverse(&2, String, Con{"too deep to check", acc})
    case 1n+f Next{Con{j, t}, acc}:
      run(f, lenient, step(lenient, j, t, acc))

# Every problem with `v` under `s`, in document order; [] when valid.
def errors(s: Schema, v: Json.Value) -> List<&2, String>:
  run(1000000n, False{}, Next{[Check{s, "", v}], Nil{}})

# The same, reading strings as numbers, booleans and nulls.
def errors_lenient(s: Schema, v: Json.Value) -> List<&2, String>:
  run(1000000n, True{}, Next{[Check{s, "", v}], Nil{}})

def string_field(kv: Text.Two()) -> Json.Field():
  (k, v) = kv
  Json.field(k, Json.of_str(v))

def string_fields(kvs: List<&2, Text.Two()>) -> List<&2, Json.Field()>:
  match kvs:
    case Nil{}:
      Nil{}
    case Con{kv, t}:
      Con{string_field(kv), string_fields(t)}

# A map of strings (a query, the params) checked leniently as an object.
def check_strings(s: Schema, m: Map<&2, String>) -> List<&2, String>:
  errors_lenient(s, Json.obj(string_fields(Map.to_list(&2, String, m))))

# Answers
# -------

def of_strs(xs: List<&2, String>) -> List<&2, Json.Value>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      Con{Json.of_str(h), of_strs(t)}

# The 422, as JSON, with the list. It bypasses `on_error` on purpose:
# the client needs the list in prod too, where renderers hide details.
def unprocessable(errs: List<&2, String>) -> Http.Response:
  Http.Response.with_status(
    Http.Response.of_json(Json.obj([
      Json.field("status", Json.of_u32(422)),
      Json.field("error", Json.of_str("Unprocessable Content")),
      Json.field("errors", Json.arr(of_strs(errs)))
    ])),
    422)

# Middleware
# ----------

def verdict(next: (Http.Request -> IO(Http.Response)), req: Http.Request, errs: List<&2, String>) -> IO(Http.Response):
  match errs:
    case Nil{}:
      next(req)
    case Con{h, t}:
      IO.pure(Http.Response, unprocessable(Con{h, t}))

def validate_json.go(s: Schema, next: (Http.Request -> IO(Http.Response)), req: Http.Request, body: Maybe<&2, Json.Value>) -> IO(Http.Response):
  match body:
    case None{}:
      IO.pure(Http.Response, Http.Response.fail(Http.BadRequest{"body is not JSON"}))
    case Some{v}:
      verdict(next, req, errors(s, v))

# The body must be JSON (by content type, and parse) matching `s`: else
# 400 through `on_error`, or 422 with the list.
def validate_json(s: Schema, next: (Http.Request -> IO(Http.Response)), req: Http.Request) -> IO(Http.Response):
  +req = req
  validate_json.go(s, next, req, Http.Request.json(req))

# The query string, leniently, against an object schema.
def validate_query(s: Schema, next: (Http.Request -> IO(Http.Response)), req: Http.Request) -> IO(Http.Response):
  +req = req
  verdict(next, req, check_strings(s, Http.Request.query_map(req)))

# The path params, leniently, against an object schema.
def validate_params(s: Schema, next: (Http.Request -> IO(Http.Response)), req: Http.Request) -> IO(Http.Response):
  +req = req
  verdict(next, req, check_strings(s, Http.Request.params(req)))
