import Base
import ./text.bend as Text
import ./json.bend as Json
import ./http.bend as Http
import ./schema.bend as Schema
import ./router.bend as Router

# OpenAPI
# =======
#
# An OpenAPI 3.1 document built from a route list. A route carries
# notes (router.bend); the decorators here add them, and `body` and
# `query` also wrap the handler in the validating middleware, so one
# schema both checks the request and documents it. Path parameters come
# from the pattern: every `:name` and `*name` is a string in the path.
#
# Schemas become JSON Schema 2020-12, the dialect OpenAPI 3.1 uses,
# inline (no `$ref`). Bend forbids mutual recursion, so one def converts
# a list of schemas, on a fuel, and an object converts its properties
# as a list.

# Schemas as JSON Schema
# ----------------------

def typed(name: String) -> Json.Value:
  Json.obj([Json.field("type", Json.of_str(name))])

def strs(xs: List<&2, String>) -> List<&2, Json.Value>:
  match xs:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      Con{Json.of_str(h), strs(t)}

def leaf(s: Schema.Schema) -> Json.Value:
  match s:
    case Schema.SAny{}:
      Json.obj([])
    case Schema.SStr{}:
      typed("string")
    case Schema.SNum{}:
      typed("number")
    case Schema.SInt{}:
      Json.obj([
        Json.field("type", Json.of_str("integer")),
        Json.field("minimum", Json.of_u32(0)),
        Json.field("maximum", Json.num("4294967295"))
      ])
    case Schema.SBool{}:
      typed("boolean")
    case Schema.SNull{}:
      typed("null")
    case Schema.SEnum{options}:
      Json.obj([Json.field("type", Json.of_str("string")), Json.field("enum", Json.arr(strs(options)))])
    case Schema.SArr{each}:
      Json.obj([])
    case Schema.SObj{props, strict}:
      Json.obj([])
    case Schema.SOpt{inner}:
      Json.obj([])

def is_opt(s: Schema.Schema) -> Bool:
  match s:
    case Schema.SOpt{inner}:
      True{}
    case _:
      False{}

def prop_name(kv: Schema.Prop()) -> String:
  (k, v) = kv
  k

def prop_schema(kv: Schema.Prop()) -> Schema.Schema:
  (k, v) = kv
  v

def prop_required(kv: Schema.Prop()) -> Bool:
  (k, v) = kv
  Bool.not(is_opt(v))

def prop_names(props: List<&2, Schema.Prop()>) -> List<&2, String>:
  match props:
    case Nil{}:
      Nil{}
    case Con{kv, t}:
      Con{prop_name(kv), prop_names(t)}

def prop_schemas(props: List<&2, Schema.Prop()>) -> List<&2, Schema.Schema>:
  match props:
    case Nil{}:
      Nil{}
    case Con{kv, t}:
      Con{prop_schema(kv), prop_schemas(t)}

def required.keep(+kv: Schema.Prop(), rest: List<&2, String>, req: Bool) -> List<&2, String>:
  match req:
    case True{}:
      Con{prop_name(kv), rest}
    case False{}:
      rest

# The names of the props that are not optional.
def required(props: List<&2, Schema.Prop()>) -> List<&2, String>:
  match props:
    case Nil{}:
      Nil{}
    case Con{+kv, t}:
      required.keep(kv, required(t), prop_required(kv))

def zip_fields(names: List<&2, String>, vs: List<&2, Json.Value>) -> List<&2, Json.Field()>:
  match names vs:
    case Con{n, nt} Con{v, vt}:
      Con{Json.field(n, v), zip_fields(nt, vt)}
    case _ _:
      Nil{}

def required_field(names: List<&2, String>) -> List<&2, Json.Field()>:
  match names:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      [Json.field("required", Json.arr(strs(Con{h, t})))]

def strict_field(strict: Bool) -> List<&2, Json.Field()>:
  match strict:
    case True{}:
      [Json.field("additionalProperties", Json.of_bool(False{}))]
    case False{}:
      Nil{}

def object(+props: List<&2, Schema.Prop()>, values: List<&2, Json.Value>, strict: Bool) -> Json.Value:
  Json.obj(List.concat(&2, Json.Field(), [
    [Json.field("type", Json.of_str("object")), Json.field("properties", Json.obj(zip_fields(prop_names(props), values)))],
    required_field(required(props)),
    strict_field(strict)
  ]))

def first(xs: List<&2, Json.Value>) -> Json.Value:
  match xs:
    case Nil{}:
      Json.obj([])
    case Con{h, t}:
      h

def array(item: Json.Value) -> Json.Value:
  Json.obj([Json.field("type", Json.of_str("array")), Json.field("items", item)])

# Each schema of `xs` as JSON Schema, in order. A schema deeper than the
# fuel comes out as `{}`, which accepts anything.
def convert(fuel: Nat, xs: List<&2, Schema.Schema>) -> List<&2, Json.Value>:
  match fuel xs:
    case _ Nil{}:
      Nil{}
    case 0n Con{s, rest}:
      Con{Json.obj([]), convert(0n, rest)}
    case 1n+p Con{Schema.SArr{each}, rest}:
      +q = p
      Con{array(first(convert(q, [each]))), convert(q, rest)}
    case 1n+p Con{Schema.SObj{+props, strict}, rest}:
      +q = p
      Con{object(props, convert(q, prop_schemas(props)), strict), convert(q, rest)}
    case 1n+p Con{Schema.SOpt{inner}, rest}:
      +q = p
      Con{first(convert(q, [inner])), convert(q, rest)}
    case 1n+p Con{s, rest}:
      Con{leaf(s), convert(p, rest)}

# A schema as JSON Schema.
def to_json_schema(s: Schema.Schema) -> Json.Value:
  first(convert(100000n, [s]))

# Paths and parameters
# --------------------

def seg_template(seg: Router.Seg) -> String:
  match seg:
    case Router.Lit{text}:
      "/" ++ text
    case Router.Param{name}:
      "/{" ++ name ++ "}"
    case Router.Rest{name}:
      "/{" ++ name ++ "}"

def template.go(pat: List<&2, Router.Seg>) -> String:
  match pat:
    case Nil{}:
      SNil{}
    case Con{h, t}:
      seg_template(h) ++ template.go(t)

# A pattern as an OpenAPI path: "/users/:id/files/*rest" is
# "/users/{id}/files/{rest}".
def template(pat: List<&2, Router.Seg>) -> String:
  match pat:
    case Nil{}:
      "/"
    case Con{h, t}:
      template.go(Con{h, t})

def path_param(+name: String, rest: Bool) -> Json.Value:
  Json.obj(List.concat(&2, Json.Field(), [
    [
      Json.field("name", Json.of_str(name)),
      Json.field("in", Json.of_str("path")),
      Json.field("required", Json.of_bool(True{})),
      Json.field("schema", typed("string"))
    ],
    Bool.pick(List<&2, Json.Field()>, rest, [Json.field("description", Json.of_str("rest of the path, may contain /"))], Nil{})
  ]))

def path_params(pat: List<&2, Router.Seg>) -> List<&2, Json.Value>:
  match pat:
    case Nil{}:
      Nil{}
    case Con{Router.Lit{text}, t}:
      path_params(t)
    case Con{Router.Param{name}, t}:
      Con{path_param(name, False{}), path_params(t)}
    case Con{Router.Rest{name}, t}:
      Con{path_param(name, True{}), path_params(t)}

def query_param(kv: Schema.Prop()) -> Json.Value:
  (k, v) = kv
  +v = v
  Json.obj([
    Json.field("name", Json.of_str(k)),
    Json.field("in", Json.of_str("query")),
    Json.field("required", Json.of_bool(Bool.not(is_opt(v)))),
    Json.field("schema", to_json_schema(v))
  ])

def query_props(props: List<&2, Schema.Prop()>) -> List<&2, Json.Value>:
  match props:
    case Nil{}:
      Nil{}
    case Con{kv, t}:
      Con{query_param(kv), query_props(t)}

# The properties of an object schema as query parameters.
def query_params(q: Maybe<&2, Schema.Schema>) -> List<&2, Json.Value>:
  match q:
    case Some{Schema.SObj{props, strict}}:
      query_props(props)
    case _:
      Nil{}

# Operations
# ----------

type Reply is Data:
  Reply{status: U32, schema: Schema.Schema}

# The notes of one route, gathered.
type Op is Data:
  Op{summary: String, tags: List<&2, String>, body: Maybe<&2, Schema.Schema>, query: Maybe<&2, Schema.Schema>, replies: List<&2, Reply>}

def Op.add(op: Op, n: Router.Note) -> Op:
  match op n:
    case Op{s, t, b, q, r} Router.Summary{text}:
      Op{text, t, b, q, r}
    case Op{s, t, b, q, r} Router.Tag{name}:
      Op{s, List.append(&2, String, t, [name]), b, q, r}
    case Op{s, t, b, q, r} Router.Body{schema}:
      Op{s, t, Some{schema}, q, r}
    case Op{s, t, b, q, r} Router.Query{schema}:
      Op{s, t, b, Some{schema}, r}
    case Op{s, t, b, q, r} Router.Returns{status, schema}:
      Op{s, t, b, q, List.append(&2, Reply, r, [Reply{status, schema}])}

def gather.go(notes: List<&2, Router.Note>, op: Op) -> Op:
  match notes:
    case Nil{}:
      op
    case Con{h, t}:
      gather.go(t, Op.add(op, h))

# Notes are kept newest first; gathered oldest first, so the note put on
# last (the outermost call) wins a clash.
def gather(notes: List<&2, Router.Note>) -> Op:
  gather.go(List.reverse(&2, Router.Note, notes), Op{SNil{}, Nil{}, None{}, None{}, Nil{}})

def json_content(schema: Json.Value) -> Json.Value:
  Json.obj([Json.field("application/json", Json.obj([Json.field("schema", schema)]))])

def described(+status: U32) -> Json.Value:
  Json.obj([Json.field("description", Json.of_str(Http.Status.reason(status)))])

def reply_field(r: Reply) -> Json.Field():
  match r:
    case Reply{+status, schema}:
      Json.field(U32.show(status), Json.obj([
        Json.field("description", Json.of_str(Http.Status.reason(status))),
        Json.field("content", json_content(to_json_schema(schema)))
      ]))

def reply_fields(rs: List<&2, Reply>) -> List<&2, Json.Field()>:
  match rs:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      Con{reply_field(h), reply_fields(t)}

# The 422 that `validate_json` answers.
def errors_schema() -> Json.Value:
  Json.obj([
    Json.field("type", Json.of_str("object")),
    Json.field("properties", Json.obj([
      Json.field("status", typed("integer")),
      Json.field("error", typed("string")),
      Json.field("errors", array(typed("string")))
    ]))
  ])

def body_replies(has_body: Bool) -> List<&2, Json.Field()>:
  match has_body:
    case True{}:
      [
        Json.field("400", described(400)),
        Json.field("422", Json.obj([
          Json.field("description", Json.of_str(Http.Status.reason(422))),
          Json.field("content", json_content(errors_schema()))
        ]))
      ]
    case False{}:
      Nil{}

def responses.or_default(fields: List<&2, Json.Field()>) -> List<&2, Json.Field()>:
  match fields:
    case Nil{}:
      [Json.field("default", Json.obj([Json.field("description", Json.of_str("response"))]))]
    case Con{h, t}:
      Con{h, t}

def is_some(m: Maybe<&2, Schema.Schema>) -> Bool:
  match m:
    case None{}:
      False{}
    case Some{s}:
      True{}

def summary_field(s: String) -> List<&2, Json.Field()>:
  match s:
    case SNil{}:
      Nil{}
    case SCon{h, t}:
      [Json.field("summary", Json.of_str(SCon{h, t}))]

def tags_field(tags: List<&2, String>) -> List<&2, Json.Field()>:
  match tags:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      [Json.field("tags", Json.arr(strs(Con{h, t})))]

def params_field(ps: List<&2, Json.Value>) -> List<&2, Json.Field()>:
  match ps:
    case Nil{}:
      Nil{}
    case Con{h, t}:
      [Json.field("parameters", Json.arr(Con{h, t}))]

def body_field(b: Maybe<&2, Schema.Schema>) -> List<&2, Json.Field()>:
  match b:
    case None{}:
      Nil{}
    case Some{s}:
      [Json.field("requestBody", Json.obj([
        Json.field("required", Json.of_bool(True{})),
        Json.field("content", json_content(to_json_schema(s)))
      ]))]

def id_char(+c: Char) -> Char:
  Bool.pick(Char, Bool.or(Char.is_alpha(c), Char.is_digit(c)), c, '_')

def id_chars.put(+c: Char, rest: String, gap: Bool) -> String:
  match gap:
    case True{}:
      rest
    case False{}:
      SCon{c, rest}

# Letters and digits kept, every run of anything else one "_".
def id_chars(s: String, after_gap: Bool) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{+h, t}:
      +c = id_char(h)
      +gap = Char.is_eq(c, '_')
      id_chars.put(c, id_chars(t, gap), Bool.and(gap, after_gap))

def drop_underscores(+s: String) -> String:
  match s:
    case SCon{'_', t}:
      drop_underscores(t)
    case _:
      s

# "get" and "/api/tasks/{id}" make "get_api_tasks_id": what client
# generators name their functions after. Unique while no two routes
# share a method and a path, which `Route.check` enforces.
def operation_id(+method: String, +path: String) -> String:
  method ++ "_" ++ String.reverse(drop_underscores(String.reverse(drop_underscores(id_chars(path, False{})))))

# One operation: summary, tags, parameters (path, then query), request
# body, and responses (the declared ones, then 400 and 422 for a body;
# `default` when there are none).
def operation(+id: String, pat: List<&2, Router.Seg>, op: Op) -> Json.Value:
  match op:
    case Op{s, t, +b, q, r}:
      Json.obj(List.concat(&2, Json.Field(), [
        [Json.field("operationId", Json.of_str(id))],
        summary_field(s),
        tags_field(t),
        params_field(List.append(&2, Json.Value, path_params(pat), query_params(q))),
        body_field(b),
        [Json.field("responses", Json.obj(responses.or_default(List.append(&2, Json.Field(), reply_fields(r), body_replies(is_some(b))))))]
      ]))

# Document
# --------

# One path of the document and its operations, in first-seen order.
type Entry is Data:
  Entry{path: String, ops: List<&2, Json.Field()>}

def hit(groups: List<&2, Entry>, +path: String) -> Bool:
  match groups:
    case Nil{}:
      False{}
    case Con{Entry{p, ops}, t}:
      String.eq(p, path)

# Adds an operation under its path; `here` says whether the first entry
# is that path.
def insert(groups: List<&2, Entry>, +path: String, op: Json.Field(), here: Bool) -> List<&2, Entry>:
  match groups here:
    case Nil{} _:
      [Entry{path, [op]}]
    case Con{Entry{p, ops}, rest} True{}:
      Con{Entry{p, List.append(&2, Json.Field(), ops, [op])}, rest}
    case Con{e, +rest} False{}:
      Con{e, insert(rest, path, op, hit(rest, path))}

def place(+groups: List<&2, Entry>, +path: String, op: Json.Field()) -> List<&2, Entry>:
  insert(groups, path, op, hit(groups, path))

def paths.add(+groups: List<&2, Entry>, +method: String, +path: String, pat: List<&2, Router.Seg>, notes: List<&2, Router.Note>) -> List<&2, Entry>:
  place(groups, path, Json.field(method, operation(operation_id(method, path), pat, gather(notes))))

def paths.go(docs: List<&2, Router.Doc>, groups: List<&2, Entry>) -> List<&2, Entry>:
  match docs:
    case Nil{}:
      groups
    case Con{Router.Doc{method, +pat, notes}, rest}:
      paths.go(rest, paths.add(groups, String.to_lower(method), template(pat), pat, notes))

def entry_fields(es: List<&2, Entry>) -> List<&2, Json.Field()>:
  match es:
    case Nil{}:
      Nil{}
    case Con{Entry{p, ops}, t}:
      Con{Json.field(p, Json.obj(ops)), entry_fields(t)}

# The OpenAPI 3.1 document for a route list. `servers` is "/": the
# API is described relative to wherever the document is served.
def document(title: String, version: String, routes: List<Router.Route>) -> Json.Value:
  Json.obj([
    Json.field("openapi", Json.of_str("3.1.0")),
    Json.field("info", Json.obj([Json.field("title", Json.of_str(title)), Json.field("version", Json.of_str(version))])),
    Json.field("servers", Json.arr([Json.obj([Json.field("url", Json.of_str("/"))])])),
    Json.field("paths", Json.obj(entry_fields(paths.go(Router.docs(routes), Nil{}))))
  ])

# A handler that answers the document as JSON. Give it a route list
# other than the one it is mounted in: a list cannot contain itself.
def handler(title: String, version: String, routes: List<Router.Route>, req: Http.Request) -> IO(Http.Response):
  IO.pure(Http.Response, Http.Response.of_json(document(title, version, routes)))

# Decorators
# ----------

# Validates the JSON body against `schema` (`Schema.validate_json`) and
# documents it as the request body.
def body(+schema: Schema.Schema, route: Router.Route) -> Router.Route:
  Router.with_note(Router.Body{schema}, Router.around(Schema.validate_json(schema), route))

# Validates the query against an object schema (`Schema.validate_query`)
# and documents each property as a query parameter.
def query(+schema: Schema.Schema, route: Router.Route) -> Router.Route:
  Router.with_note(Router.Query{schema}, Router.around(Schema.validate_query(schema), route))

# Documents a JSON response.
def returns(status: U32, schema: Schema.Schema, route: Router.Route) -> Router.Route:
  Router.with_note(Router.Returns{status, schema}, route)

def summary(text: String, route: Router.Route) -> Router.Route:
  Router.with_note(Router.Summary{text}, route)

def tag(name: String, route: Router.Route) -> Router.Route:
  Router.with_note(Router.Tag{name}, route)
