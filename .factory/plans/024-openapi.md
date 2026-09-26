# Plan 024: Routes carry their schemas, and Air serves an OpenAPI 3.1 document built from them

> **Executor instructions**: Deliver the stated outcome within scope. Adapt routine
> implementation details to current code, preserve the listed contracts, and run
> the relevant acceptance checks. Fix task-caused failures and recheck affected
> behavior. Escalate only the material conditions below. Update the plan's status
> in `.factory/plans/README.md`.
>
> **Drift check**: `git diff --stat cea6656 -- air/lib/router.bend air/lib/schema.bend air/lib/json.bend air.bend examples/dashboard`
> should be empty or routine. This plan changes the `Route` constructor. If
> another plan changed it in the meantime (025 adds a router local; that
> does not touch `Route`), reconcile before starting.

## Status

- **Priority**: P2
- **Effort**: L
- **Risk**: MED (changes `Router.Route`, rebuilt on every request, so throughput must be re-measured; reverses one import)
- **Depends on**: 017 (shipped: `Schema`). 019 recommended (tests), 020 recommended (the bench gate catches a routing regression).
- **Category**: dx (roadmap Tier 6: "OpenAPI generation from route schemas")
- **Planned at**: commit `cea6656`, 2026-09-22, clean tree

## Why this matters

Plan 017 made schemas values and validates bodies, queries and params
with them. But a schema lives inside a middleware closure
(`Air.validate_json(new_task())(create)`), so nothing can read it back.
API consumers need a machine-readable contract (client generation, docs
UIs, contract tests), and writing one by hand drifts from the code on
the first change. This plan puts the schema on the route itself, **once**:
a single call both validates and documents. It adds `Air.openapi(…)`,
a handler that serves an OpenAPI 3.1 JSON document derived from a route
list. Path parameters come from the patterns for free.

## Decisions

- **Notes on the route, converted late.** `Router.Route` gains a field
  `notes: List<&2, Note>`, with
  `type Note is Data: Summary{text} | Tag{name} | Body{schema} | Query{schema} | Returns{status: U32, schema}`
  (add `Describe{text}` if useful). Notes are cheap `Data` values. The
  schemas are already built for validation. Conversion to JSON happens
  only in `document`, so a normal request pays for one extra list field
  and no JSON building. `Route.new` starts with `Nil{}`. `mount`, `wrap`,
  `conflicts` and every `Route{…}` match carry or ignore the field.
- **One call validates and documents.** Decorators take a route and give
  a route:
  - `Air.Api.body(schema, route)` wraps the handler in
    `Schema.validate_json(schema)` **and** adds `Body{schema}`;
  - `Air.Api.query(schema, route)` does the same with `validate_query` and
    `Query{schema}`; each property becomes an `in: query` parameter,
    `required` when it is not `SOpt`;
  - `Air.Api.returns(status, schema, route)`, `Air.Api.summary(text, route)`,
    `Air.Api.tag(name, route)` only add notes.

  Usage:
  `Air.Api.body(new_task(), Air.Api.returns(201, task(), Air.Api.summary("Create a task", Air.Route.post("/tasks", create))))`.
  Path params need no call: every `:name` / `*name` segment becomes an
  `in: path`, `required: true`, `{"type":"string"}` parameter.
  `validate_params` stays as is and is not documented (params are always
  strings in the spec).
- **Import direction.** The notes hold `Schema.Schema`, so `router.bend`
  must import `schema.bend`. Today `schema.bend` imports `router.bend`
  only for the type `Router.Handler()` (lines 363-389). Replace those uses
  with the literal type `Http.Request -> IO(Http.Response)` and drop the
  import, so no cycle forms. `Note` lives in `router.bend`, which imports
  `./schema.bend`.
- **Schema → JSON Schema (2020-12, as OpenAPI 3.1 uses)**: `SAny` → `{}`;
  `SStr` → `{"type":"string"}`; `SNum` → `{"type":"number"}`; `SInt` →
  `{"type":"integer","minimum":0,"maximum":4294967295}`; `SBool` →
  `{"type":"boolean"}`; `SNull` → `{"type":"null"}`; `SEnum{os}` →
  `{"type":"string","enum":[…]}`; `SArr{s}` → `{"type":"array","items":…}`;
  `SObj{props, strict}` → `{"type":"object","properties":{…},"required":[…]}`
  plus `"additionalProperties":false` when strict (omit `required` when
  empty). `SOpt{s}` is the inner schema, not required. Bend forbids
  mutual recursion (props ↔ schema), so write the converter as the
  checker is written (`schema.bend` `run`/`step`): a work list with fuel.
  Or, simpler, since the output is a tree: a recursive def over a
  **list of schemas** that returns a list of JSON values
  (`convert_all(xs: List<&2, Schema>) -> List<&2, Json.Value>`). A single
  schema is `convert_all([s])`. Object props then recurse through the
  same def. Pick whichever the checker accepts. The termination rule is
  that the first changed argument must shrink.
- **Document shape**:
  `{"openapi":"3.1.0","info":{"title":…,"version":…},"paths":{…}}`.
  Paths are grouped in first-seen order. Two routes with the same template
  and different methods share one path item. The template turns `:id` into
  `{id}` and `*rest` into `{rest}` (OpenAPI cannot express multi-segment
  params; give that parameter the description `"rest of the path, may contain /"`).
  Each operation gets `parameters`, `requestBody`
  (`{"required":true,"content":{"application/json":{"schema":…}}}`),
  `responses` (each `Returns` as
  `"201":{"description":"Created","content":{"application/json":{"schema":…}}}`,
  the description from `Http.Status.reason`). A body adds a `"422"`
  response with the error-list shape and `"400"`. With no `Returns`,
  add `"default":{"description":"response"}`: `responses` must not be
  empty. `summary` and `tags` go on the operation when present. Explicit
  HEAD/OPTIONS routes are listed. The router's automatic HEAD/OPTIONS are
  not.
- **Serving**: `Air.openapi(title, version, routes: List<Route>) -> Handler`
  renders the document per request (it is small, and cached nowhere, as
  there are no globals). A route list cannot contain a route that
  documents that same list (self-reference). So the app mounts it next to
  the API: `Air.Route.all([api(), [Air.Route.get("/openapi.json", Air.openapi("Dashboard", "1.0.0", api()))]])`.
  Document that `api()` is then built twice per request that reaches this
  route list, and check the cost in the bench.

## Current state

- `air/lib/router.bend`:
  - `type Route is Type: Route{method: Http.Method, pattern: List<&2, Seg>, slash: Bool, handler: Handler()}`;
    `new(method, +path, handler)`; `get/post/put/delete/patch/head/options`.
  - `mount.go` and `wrap` rebuild `Route{m, pat, slash, h}`.
  - `conflicts.go` matches `Route{m, +pat, slash, h}`. `pattern_of` and
    `consider.route` match it too. Every one of these gains the field.
  - `Seg = Lit{text} | Param{name} | Rest{name}`.
- `air/lib/schema.bend`: `type Schema is Data: SAny | SStr | SNum | SInt | SBool | SNull | SEnum{options} | SArr{each} | SObj{props: List<&2, Sigma<&2,&2,String,_ => Schema>>, strict} | SOpt{inner}`.
  Middleware `validate_json(s, next, req)`, `validate_query`,
  `validate_params`. `unprocessable(errs)` gives the 422 shape
  `{"status":422,"error":"Unprocessable Content","errors":[…]}`.
- `air/lib/json.bend`: `Value = Null | Boolean{b} | Num{text} | Str{s} | Arr{items} | Obj{fields}`;
  builders `null/of_bool/of_u32/num/of_str/arr/obj/field`; `render`.
- `examples/dashboard/main.bend:89-146`: schemas `tasks_query()` and
  `new_task()`; routes
  `Air.Route.get("/tasks", Air.validate_query(tasks_query())(tasks))` and
  `Air.Route.post("/tasks", Air.validate_json(new_task())(create))` inside
  `api(switch)`, mounted under `/api`. Mounting must keep notes.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Proof | `bend PROOF.bend` | `All terms check.` (existing router laws unchanged) |
| Tests (019) | `bend tests/dashboard.bend` | exit 0 |
| Live | `bend examples/dashboard/main.bend` then `curl -s localhost:8080/openapi.json` | the document |
| Validate the document | `curl -s localhost:8080/openapi.json > /tmp/oa.json && npx -y @redocly/cli@latest lint /tmp/oa.json` | no errors (warnings about missing `servers`/`license` are acceptable; list them) |
| Bench | `bench/run.sh 32 5` (or 020's `ab.sh` against the pre-change binary) | GET /hello/:name within 5% of before |
| Native | `bend examples/hello/main.bend -o /tmp/h && bend examples/dashboard/main.bend -o /tmp/d` | exit 0 |

The `npx` step downloads a linter. It is verification only; add nothing
to the repo's dependencies.

## Implementation rules relevant to this plan

- Bend: declare before use; no mutual recursion; no `if`; match only on
  parameters, in parameter order; the first changed argument of a
  self-call must shrink; `String & String` cannot live in a `Maybe`
  (use `Sigma`, as `Json.Field()` does). See `AGENTS.md`.
- New module `air/lib/openapi.bend` (imports `Base`, `./text.bend`,
  `./json.bend`, `./http.bend`, `./schema.bend`, `./router.bend`) for the
  converter, `document` and the `openapi` handler. The decorators that
  need `Route`'s constructor live in `router.bend` (`with_note(note, route)`)
  or in `openapi.bend` via a `router.bend` accessor. Your choice, as long
  as `Route{…}` is only built in `router.bend`.
- Facade: `Air.Api.body/query/returns/summary/tag`, `Air.openapi`.
  `Air.Api` is a namespace prefix, not a type. Native-build both examples
  (C names: `air.Api.body` vs `air/lib/openapi.body` differ, but check).

## Scope

**In scope**: `air/lib/router.bend` (notes field, `Note`, `with_note`,
carried through `mount`/`wrap`), `air/lib/schema.bend` (drop the router
import), `air/lib/openapi.bend` (new), `air.bend`, `LAWS.bend`,
`PROOF.bend`, `examples/dashboard/main.bend` (both task routes via
`Air.Api.*`, a `task()` response schema, `/openapi.json` mounted),
`tests/dashboard.bend` (if 019), `docs/content/docs/guides/openapi.mdx`
+ `meta.json` (and a pointer from `validation.mdx`), roadmap tick, index row.

**Out of scope**: serving a docs UI (Swagger UI/Redoc need JS assets; an
app can serve one with `Air.static`), headers/cookies as parameters,
security schemes, examples, `$ref` deduplication (inline schemas only),
response validation (rejected in 017), YAML output.

## Steps

### Step 1: reverse the import, add notes to `Route`

Make the field change and the schema import change with no behavior
change, and run `bend PROOF.bend`: every existing router law must pass
untouched. Then benchmark GET before and after this step alone. It is
the only hot-path change.

### Step 2: converter and document, with laws

```
oa_str:         render(to_json_schema(Schema.str())) == "{\"type\":\"string\"}"
oa_obj_strict:  render(to_json_schema(Schema.obj([Schema.field("a", Schema.int()), Schema.optional("b", Schema.str())])))
                == "{\"type\":\"object\",\"properties\":{\"a\":{\"type\":\"integer\",\"minimum\":0,\"maximum\":4294967295},\"b\":{\"type\":\"string\"}},\"required\":[\"a\"],\"additionalProperties\":false}"
oa_arr_enum:    render(to_json_schema(Schema.arr(Schema.one_of(["x"])))) == "{\"type\":\"array\",\"items\":{\"type\":\"string\",\"enum\":[\"x\"]}}"
oa_template:    template(parse_pattern("/users/:id/files/*rest")) == "/users/{id}/files/{rest}"
oa_merge:       two routes GET and POST on "/t" → one path item with "get" and "post", in that order
oa_mount_keeps: notes survive Route.mount("/api", [Api.summary("s", get("/t", noop))])
oa_default:     a bare route's operation has "responses":{"default":{"description":"response"}}
```

Pin one whole-document law for a two-route list, so the exact output is
guarded.

### Step 3: decorators, handler, facade, dashboard, docs, lint

## Test plan

Laws above. With 019: `GET /openapi.json` is 200 JSON whose `paths` has
`/api/tasks` with `get` and `post`, and the POST route still answers 422
for `{"title":5}` (validation is still wired). Lint with redocly: zero
errors. Bench: record before/after GET req/s in the index row.

## Done criteria

- [ ] `bend PROOF.bend` passes: all old router laws plus ≥ 7 new.
- [ ] `/openapi.json` on the dashboard lints with zero errors (redocly).
- [ ] Dashboard task routes each use one `Air.Api.*` chain for validation and docs. No schema is written twice.
- [ ] GET /hello/:name throughput within 5% of the pre-plan build (numbers in the index).
- [ ] Guide, roadmap, index updated. Both examples native-build.

## STOP conditions

- Adding the field costs more than 5% on the hello bench even with notes
  empty. Report the numbers. Do not switch to a side table without
  approval: that changes the public shape.
- The checker refuses `router.bend` importing `schema.bend` for a reason
  other than the cycle this plan removes. Report the error. An
  alternative (notes holding pre-rendered `Json.Value`) is acceptable
  only if it keeps the single-call decorators.
- redocly reports errors that need a spec feature out of scope (for
  example it insists on `$ref`). Report the list.

## Maintenance notes

- New middleware that constrains input should consider a matching `Note`,
  so the document stays complete.
- Plan 025 adds a router local with the matched pattern. It can reuse
  the `template` function from here, or the router's own shape, for its
  `route` label.
- Roadmap's "Type inference from route definitions" was rejected
  (see the index). This document is the closest a Bend app gets to
  exporting its types, and clients can generate typed SDKs from it.
