# Plan 017: Schema values that validate JSON bodies, query strings and params

> **Executor instructions**: Deliver the stated outcome within scope. Adapt routine
> implementation details to current code, preserve the listed contracts, and run
> the relevant acceptance checks. Fix task-caused failures and recheck affected
> behavior. Escalate only the material conditions below. Update the plan's status
> in `.factory/plans/README.md`.
>
> **Drift check**: `git diff --stat 13be69e -- air/json.bend air/http.bend air/router.bend air/errors.bend`
> should be empty or routine (013 touches `errors.bend`; fine). Confirm
> `Json.Value` constructors (`bend` names in `air/json.bend`: null, bool,
> number-as-text, string, array, object with ordered fields) and the
> accessors `Json.get`, `Json.items`, `Json.fields`, `Json.u32`, `Json.str`,
> `Json.boolean`, `Json.is_null` exist as re-exported in `air.bend`.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: LOW (a pure checker over `Json.Value` and one middleware)
- **Depends on**: none (011 for the 422 shape; shipped)
- **Category**: direction (roadmap Tier 5: schema validation hooks for params/query/body/response)
- **Planned at**: commit `13be69e`, 2026-09-20, clean tree

## Why this matters

Every JSON handler today re-implements "is `name` a string, is `age` a
number, is `email` present": `Request.json` gives a value and the handler
walks it. This plan ships a schema as a value, a total checker that lists
every problem at once, and a middleware that answers 422 with those
problems before the handler runs. Bend has no reflection and no type
inference from route definitions (that roadmap line is Tier 6 and TS-only),
so the schema is written by hand, next to the route.

Decisions:

- **Schema is a sum type** over `Json.Value`:
  `Any`, `Str`, `Num`, `Int` (a non-negative integer that fits `U32`),
  `Boolean`, `Null`, `Enum{options: List<String>}`, `Arr{item: Schema}`,
  `Obj{fields: List<Field>, strict: Bool}` with
  `Field{name, required: Bool, schema}`. Strict objects refuse unknown
  keys. No min/max, pattern or length rules in this cut: they double the
  surface, and a handler can check a range in one line after validation.
- **Errors are a list of strings**, one per problem, with a path:
  `"name: expected string"`, `"tags[2]: expected string"`,
  `"missing: email"`, `"unknown: nickname"`, `"age: expected integer"`,
  `"role: expected one of admin, user"`. An empty list means valid.
- **Strings are lenient when validating query and params**: those are
  strings by nature, so `check_strings(schema, map)` turns the map into an
  object of strings and checks it in lenient mode, where `Int` accepts
  `"42"`, `Num` accepts a JSON-number spelling, `Boolean` accepts
  `"true"`/`"false"`, `Null` accepts `""`. Body validation is strict.
- **The middleware answers 422 itself**, as JSON:
  `{"status":422,"error":"Unprocessable Content","errors":["…"]}`,
  bypassing `on_error`, because the client must see the list in prod too
  and plan 011's renderers hide detail in prod by design. A body that is
  not JSON at all (or has the wrong content type) is a 400 through
  `Response.fail(BadRequest{"body is not JSON"})`, as the dashboard's echo
  does today. The response's schema is not validated (rejected below).
- Three middleware, one per source: `validate_json(schema)`,
  `validate_query(schema)`, `validate_params(schema)`; the last two take
  an `Obj` schema whose fields name the keys. No re-parsing cache: the
  handler calls `Request.json` again (a second parse of an already-bounded
  body; the cost is small and a typed local is not available).

## Current state

- `air/json.bend` — `Value` and its constructors (read the file header for
  the constructor names, e.g. `Num{text}`, `Str{s}`, `Arr{items}`, `Obj{fields}`),
  `parse`, `render`, accessors; `escape` for strings.
- `air/http.bend` — `Request.json`, `Request.query` (`Map<&2, String>` inside;
  find the raw map accessor or add `Request.query_map`/`Request.params_map`),
  `Request.param`, `Response.fail`, `BadRequest`.
- `air/errors.bend:66-84` — `json.fields` shows the 422-style object shape to mirror.
- `examples/dashboard/main.bend:84-93` — `echo` handler to put under `validate_json`.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Check and prove | `bend PROOF.bend` | `All terms check.` |
| Run the example | `bend examples/dashboard/main.bend` | listens on 8080 |
| Valid body | `curl -si localhost:8080/api/tasks -H 'content-type: application/json' -d '{"title":"x","done":false}'` | 201 or 200 |
| Invalid body | `… -d '{"title":5}'` | 422 with `errors: ["title: expected string","missing: done"]` |
| Not JSON | `… -d 'nope'` | 400 rendered by `on_error` |
| Query | `curl -si 'localhost:8080/api/tasks?limit=abc'` | 422 `limit: expected integer` |

## Implementation rules relevant to this plan

- New module `air/schema.bend` (alias `Schema`), importing `Base`,
  `./text.bend`, `./json.bend`, `./http.bend`, `./router.bend`.
- Types: `type Schema is Data:` with the ten constructors above and
  `type Field is Data: Field{name: String, required: Bool, schema: Schema}`.
  Builders: `str()`, `num()`, `int()`, `boolean()`, `null()`, `any()`,
  `one_of(options)`, `arr(item)`, `obj(fields)` (strict), `obj_open(fields)`,
  `field(name, schema)` (required), `optional(name, schema)`.
- Checker: `check(+lenient: Bool, schema: Schema, +path: String, v: Json.Value, acc: List<&2, String>) -> List<&2, String>`
  accumulating errors in reverse then `List.reverse` at the top-level
  `errors(schema, v) -> List<&2, String>` and `errors_lenient`. Arrays walk
  with an index in `U32`; objects walk the schema's fields (lookup by
  `Json.get`) and, when strict, the value's fields for unknown names.
  Path rendering: `""` at the root, `name`, `name.sub`, `name[2]`. Keep the
  recursion structural on the schema and value (both finite); a body is
  bounded by the body limit, so the stack is fine.
- `check_strings(schema, m: Map<&2, String>) -> List<&2, String>`:
  `Map.to_list` to `Json.obj` of `Json.of_str` values, then lenient errors.
- 422: `unprocessable(errs: List<&2, String>) -> Http.Response`:
  `Response.with_status(Response.of_json(Json.obj([status, error, errors])), 422)`.
- Middleware:
  - `validate_json(schema: Schema, next, req)`: `+req = req`; branch on
    `Request.json(req)`: `None` → `fail(BadRequest{"body is not JSON"})`;
    `Some{v}` → errors; empty → `next(req)`, else `unprocessable`.
    `schema` is affine and used once per request; not `+`.
  - `validate_query(schema, next, req)` and `validate_params(schema, next, req)`
    over `check_strings`.
- Facade: `Air.Schema()`, `Air.Schema.str/num/int/boolean/null/any/one_of/arr/obj/obj_open/field/optional`,
  `Air.Schema.errors(schema, value)`, `Air.validate_json(schema)`,
  `Air.validate_query(schema)`, `Air.validate_params(schema)` in "Batteries".
  Per-route use: `Air.Route.post("/tasks", Air.validate_json(task_schema())(create))`;
  the schema is built by a def so the route list stays a template-free value.

## Scope

**In scope**:
- `air/schema.bend` (new); `air.bend`; `LAWS.bend`; `PROOF.bend`.
- `examples/dashboard/main.bend`: `POST /api/tasks` under
  `validate_json(task_schema())` that echoes the task back with an id;
  `GET /api/tasks?limit=` under `validate_query(obj_open([optional("limit", int())]))`
  that slices the list. `public/app.js`: no change required; optional: a
  form that posts a task.
- `README.md`: a "Validation" section with a schema example and the 422 shape.
- `roadmap.md`: tick "Schema validation hooks (params/query/body/response)"
  with the note "body, query, params; response validation rejected".
- `.factory/plans/README.md`: row 017; "Findings": response validation rejected.

**Out of scope**: response validation (every response would be re-parsed
on the hot path for a guarantee that laws give more cheaply), min/max/
pattern/length rules, coercion into typed locals, OpenAPI output (Tier 6
can walk the same `Schema` value).

## Git workflow

- Current worktree branch. Do not commit or push unless asked. `bend PROOF.bend` first.

## Steps

### Step 1: `air/schema.bend` types and checker, with laws

```
schema_str_ok:          Schema.errors(Schema.str(), Json.of_str("a")) == []
schema_str_wrong:       Schema.errors(Schema.str(), Json.of_u32(1)) == [": expected string"]   # pin the root path rendering you choose
schema_obj_missing:     Schema.errors(Schema.obj([Schema.field("a", Schema.str())]), Json.obj([])) == ["missing: a"]
schema_obj_unknown:     Schema.errors(Schema.obj([]), Json.obj([Json.field("x", Json.null())])) == ["unknown: x"]
schema_obj_open:        Schema.errors(Schema.obj_open([]), Json.obj([Json.field("x", Json.null())])) == []
schema_arr_index:       Schema.errors(Schema.arr(Schema.int()), Json.arr([Json.of_u32(1), Json.of_str("b")])) == ["[1]: expected integer"]
schema_enum:            Schema.errors(Schema.one_of(["a", "b"]), Json.of_str("c")) == [": expected one of a, b"]
schema_nested_path:     Schema.errors(Schema.obj([Schema.field("u", Schema.obj([Schema.field("n", Schema.str())]))]), Json.obj([Json.field("u", Json.obj([Json.field("n", Json.null())]))])) == ["u.n: expected string"]
schema_lenient_int:     Schema.check_strings(Schema.obj_open([Schema.field("limit", Schema.int())]), Map.set(&2, String, Map.new(&2, String), "limit", "42")) == []
schema_lenient_bad_int: Schema.check_strings(Schema.obj_open([Schema.field("limit", Schema.int())]), Map.set(&2, String, Map.new(&2, String), "limit", "x")) == ["limit: expected integer"]
schema_422_body:        Http.Response.body(Schema.unprocessable(["a: expected string"])) == "{\"status\":422,\"error\":\"Unprocessable Content\",\"errors\":[\"a: expected string\"]}"
```

### Step 2: middleware, facade, example, docs

### Step 3: live checks

Record in the index:

1. Valid POST → 200/201 with the echoed task.
2. `{"title":5}` → 422 with both errors in order.
3. `nope` → 400 via `on_error` (JSON on the dashboard).
4. Wrong content type with a JSON body → 400 (`Request.json` is `None`).
5. `?limit=abc` → 422; `?limit=2` → two tasks; no `limit` → all.
6. `AIR_ENV` unset (prod) still shows the `errors` list on 422.

## Test plan

Eleven laws; six live checks.

## Done criteria

- [ ] `bend PROOF.bend` prints `All terms check.` with the new laws.
- [ ] Live checks 1–6 pass and are noted in the index.
- [ ] `Air.Schema.*`, `Air.validate_json/query/params` exist with comments.
- [ ] README, roadmap, index updated; `air/server.bend` unchanged.

## STOP conditions

- A recursive `type Schema` with a `List<Field>` of a type that holds
  `Schema` is refused (mutual recursion between two types): flatten to one
  type with `FieldOf{name, required, schema}` as a constructor of `Schema`
  itself and have `Obj{fields: List<&2, Schema>}`. Not a stop.
- `Request.json` cannot be called twice (the request body is consumed):
  it is a pure accessor on a `+req`, so this should not happen; report if it does.

## Maintenance notes

- Tier 6 OpenAPI generation can render a `Schema` value to JSON Schema
  with one more def here.
