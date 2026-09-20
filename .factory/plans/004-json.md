# Plan 004: A JSON module, so handlers parse request bodies and build responses from values

> **Executor instructions**: Deliver the stated outcome within scope. Adapt routine
> implementation details to current code, preserve the listed contracts, and run
> the relevant acceptance checks. Fix task-caused failures and recheck affected
> behavior. Escalate only the material conditions below. Update the plan's status
> in `.factory/plans/README.md`.
>
> **Drift check**: The repo still has no commits; the tree holds the uncommitted
> Tier 2 work (plans 001–003, all DONE). Confirm `bend PROOF.bend` prints
> `All terms check.` before starting. This plan adds a new module and does not
> depend on any Tier 3 plan.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: LOW (new module; existing behavior untouched until an app opts in)
- **Depends on**: none
- **Category**: direction (roadmap Tier 3: body parsers, JSON; Response `json()` from values)
- **Planned at**: no commit yet, 2026-09-19

## Why this matters

Every JSON route in `examples/dashboard/main.bend` hand-concatenates strings
(`field("id", U32.show(id))`) and the echo route admits "No JSON parser yet".
Base has no JSON type (`bend base Json` says so). Without one, apps cannot
read a request body as data, and a handler that builds output by string
concatenation will produce invalid JSON on the first quote in a title. This
plan adds `air/json.bend`: a value type, a strict parser with a depth limit,
a renderer that escapes correctly, and the two request/response hooks.

Decisions:

- **Numbers keep their lexeme.** Bend has `U32` and `F32` only, so `Num{text}`
  stores the digits as written and `Json.u32(v)` converts on demand (Base has
  no `F32.read`, verified 2026-09-20). Nothing is lost on round-trip and big integers are not silently
  truncated.
- **Objects are ordered pair lists**, not a `Map`: JSON order is meaningful to
  humans and a `Map` would sort keys. `Json.get(obj, key)` scans; objects are
  small.
- **Strict parsing**: no comments, no trailing commas, no leading `+`, no bare
  NaN. Depth is capped (default 64) so a nested-array bomb cannot overflow
  the machine stack: rendering and parsing recurse on structure, which is
  bounded by that depth, while strings and arrays are walked tail-recursively.

## Current state

- `air/text.bend` has `hex_val`, `percent_decode` (UTF-8 assembly from bytes,
  the model for `\uXXXX` handling), `rev_onto`, `append`. No JSON anything.
- `air/http.bend`: `Request.body(r)` is the body as `String`;
  `Request.header(r, name)` is lowercase-keyed; `Response.json(body: String)`
  sets `content-type: application/json` on a 200.
- `examples/dashboard/main.bend` lines 118–166: `json_str`, `field`, `task`,
  `stats`, `tasks`, `greet`, `echo` build JSON by concatenation; `json_str`
  does not escape quotes.
- `air.bend` re-exports through wrappers; a type is aliased by a def
  (`def Request() -> Data: Http.Request`) and constructors cannot be
  re-exported, so the facade offers builder defs (`Air.Limits.new`).
- Bend rules that bite here (from `AGENTS.md`, confirmed in Tier 2): defs above
  use; no mutual recursion (so `parse_value` cannot call `parse_array` which
  calls `parse_value` — use one recursive def over a fuel/depth `Nat` with an
  explicit state, or one def that matches on the next char and recurses on
  itself for nested values); `match` only on parameters; scrutinee order
  follows parameter order; a `match` cannot follow a let-binding in the same
  def; strings are lists of `Char` (code points), so `\uD83D\uDE00` must be
  combined into one `Char` and a lone surrogate refused.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Check and prove | `bend PROOF.bend` | `All terms check.` |
| Run the dashboard | `bend examples/dashboard/main.bend` | listens on 8080 |
| Probe | `curl -s -d '{"a":[1,2,{"b":"x\"y"}]}' localhost:8080/api/echo` | the same JSON, re-rendered |

## Implementation rules relevant to this plan

- New module `air/json.bend`, imported as `Json`; inside, name defs relative
  (`parse`, `render`, `get`), not `Json.parse`. Avoid Base names.
- Parsing is on request data: every loop over characters must be
  tail-recursive with an accumulator. Recursion on *structure* (a nested
  value) is allowed only under the depth cap.
- One law per behavior; laws compare `Json` values or rendered strings.
- Do not touch `air/server.bend`.

## Scope

**In scope**:
- `air/json.bend` (create)
- `air/http.bend` — `Request.json(r) -> Maybe<&2, Json.Value>` guarded by
  content-type, `Response.of_json(v)`.
- `air.bend` — `Air.Json()` type alias and builder/accessor wrappers.
- `LAWS.bend`, `PROOF.bend`, `README.md`
- `examples/dashboard/main.bend` — build its JSON from values; echo parses and re-renders (400 on bad JSON).
- `.factory/plans/README.md` — status row.

**Out of scope**: streaming parse, JSON schema validation (Tier 5), numbers
beyond `U32`/`F32` conversion helpers.

## Git workflow

- Do not commit or push unless asked. `bend PROOF.bend` before any commit.

## Steps

### Step 1: the value type

```
type Value is Data:
  Null{}
  Bool{b: Bool}
  Num{text: String}
  Str{s: String}
  Arr{items: List<&2, Value>}
  Obj{fields: List<&2, Field>}   # see note
```

`Field` must be declared before `Value` and refer to it, which Bend refuses
(no forward references). Use `Sigma<&2, &2, String, _ => Value>` inline for
a field, as `Text.Two()` does for string pairs, or declare
`Obj{fields: List<&2, Sigma<&2, &2, String, _ => Value>>}` directly. Add
`Field()` as a def alias after `Value`.

Accessors: `get(v, key) -> Maybe<&2, Value>` (first matching key), `at(v, i)`,
`str(v) -> Maybe String`, `u32(v)` (via `Text.digits`, strict; Base has no `F32.read`, so no `f32` accessor: apps parse the lexeme themselves), `bool(v)`, `is_null(v)`, `items(v)`,
`fields(v)`.

Builders: `obj(fields)`, `arr(items)`, `str(s)`, `num(text)`, `of_u32(n)`,
`of_bool(b)`, `null()`.

### Step 2: render

`render(v) -> String`. Strings escape `"`, `\`, control characters below
0x20 (as `\n`, `\t`, `\r`, `\b`, `\f`, else `\u00XX`); everything else,
including non-ASCII, is emitted as is (UTF-8 on the wire, which is what
`content-type: application/json` means). Build with an accumulator of
reversed text and `Text.rev_onto`, in the style of `Router.shape.go`.
Recursion on nested values is structural; document that it is bounded by
the parser's depth cap for parsed input and by the app for built values.

### Step 3: parse

`parse(s: String) -> Maybe<&2, Value>`: whitespace-tolerant, whole input
must be consumed (trailing garbage is `None`). Suggested shape, since
Bend forbids mutual recursion:

- `parse.value(fuel: Nat, s: String) -> Maybe<&2, Value & String>` where the
  result carries the unconsumed rest. It matches the first non-space char:
  `{` → `parse.fields(fuel, ...)`, `[` → `parse.items(fuel, ...)`, `"` →
  `parse.string`, `t`/`f`/`n` → literals, digit or `-` → `parse.number`.
  `parse.fields` and `parse.items` are defined *above* `parse.value` and take
  it as a template parameter (`~next: Nat -> String -> Maybe<..>`), the way
  `air/server.bend` threads `~app`. Templates are substituted at compile
  time, so this is not mutual recursion. Alternatively, write one def with
  a `Frame` stack type; the template approach is shorter.
- `fuel` starts at the depth cap (`64n`) and decrements on each nested
  container; `0n` → `None{}`.
- Strings: decode escapes; `\u` takes four hex digits via `Text.hex_val`;
  a high surrogate must be followed by `\u` low surrogate → combine; a lone
  surrogate → `None{}`. Raw control characters inside a string → `None{}`.
- Numbers: validate the JSON grammar (`-?(0|[1-9]\d*)(\.\d+)?([eE][+-]?\d+)?`)
  and store the lexeme.

Because `String & String` cannot live in a `Maybe`, the "value and rest"
pair must be `Sigma<&2, &2, Value, _ => String>`; add `def Parsed() -> Data`
for it, as `Text.Two()` does.

### Step 4: hooks

- `Http.Request.json(r) -> Maybe<&2, Json.Value>`: `None{}` unless the
  content-type's media type (before any `;`) is `application/json` (or ends
  with `+json`) and `Json.parse(body)` succeeds. Expose as `Air.Request.json`.
- `Http.Response.of_json(v)`: `Response.json(Json.render(v))`. Expose as
  `Air.Response.of_json`.
- `air.bend`: `def Json() -> Data: Json.Value` and wrappers `Air.Json.parse`,
  `render`, `get`, `str`, `u32`, `obj`, `arr`, `of_u32`, `of_bool`, `null`,
  `num`. Note in the facade comment that imports are not transitive, so an
  app matching on `Json` constructors imports `air/json.bend` itself.

### Step 5: dashboard

Rewrite `task`, `stats`, `tasks`, `greet` with `Air.Json.obj([...])` and
`Air.Response.of_json`. `echo` becomes: parse with `Air.Request.json`; on
`Some{v}` answer `of_json(obj([("received", v)]))`; on `None{}` answer
`Air.Response.bad_request()`. Delete `json_str`, `field`, `json_bool`.

### Step 6: laws

At least:

```
law json_parse_object:
  {Json.parse("{\"a\": [1, true, null, \"x\"]}")
    == Some{Json.Obj{[("a", Json.Arr{[Json.Num{"1"}, Json.Bool{True{}}, Json.Null{}, Json.Str{"x"}]})]}}
    : Maybe<&2, Json.Value>}

law json_roundtrip_escapes:
  {Json.render(Json.Str{"a\"b\\c\n"}) == "\"a\\\"b\\\\c\\n\"" : String}

law json_parse_unicode_escape:      "\"\\u00e9\""  -> Some{Str{"é"}}
law json_parse_surrogate_pair:      "\"\\ud83d\\ude00\"" -> Some{Str{"😀"}}
law json_rejects_lone_surrogate:    "\"\\ud83d\""  -> None
law json_rejects_trailing_comma:    "[1,]"          -> None
law json_rejects_trailing_garbage:  "{} x"          -> None
law json_rejects_depth:             65 nested "["   -> None   (build with String.repeat)
law json_number_lexeme:             "-1.5e3"        -> Some{Num{"-1.5e3"}}
law json_rejects_leading_zero:      "01"            -> None
law json_get_first_key:             get(Obj{[("a",1),("a",2)]}, "a") == Some{Num{"1"}}
law request_json_needs_content_type: Request.json on a text/plain body == None
```

Write the shorthand ones in full `law` syntax.

## Test plan

Laws above, plus the curl probe in the commands table and
`curl -s -d 'nope' -H 'content-type: application/json' localhost:8080/api/echo`
→ 400.

## Done criteria

- [ ] `bend PROOF.bend` prints `All terms check.` with the laws above present.
- [ ] `grep -n "json_str\|def field" examples/dashboard/main.bend` returns nothing.
- [ ] Echo probe returns re-rendered JSON with the inner quote escaped; bad JSON returns 400.
- [ ] README documents `Air.Json` and `Request.json` / `Response.of_json`.
- [ ] `git status --short` shows only in-scope files.

## STOP conditions

- The template-parameter approach to nested parsing is refused by the
  checker and a stack-frame rewrite would exceed the plan's effort by a lot;
  report with the error before switching designs.
- Rendering a value parsed at the depth cap overflows the machine stack in
  a live probe; lower the cap and report the number.

## Maintenance notes

- Plan 007's `Response` type change must keep `Response.of_json` working.
- Tier 5 schema validation will sit on `Json.Value`; keep accessors total
  (`Maybe`), never partial.
- Reviewer focus: escape handling in both directions and the depth cap.
