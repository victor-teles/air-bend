# Plan 018: HTML templates rendered from a JSON context

> **Executor instructions**: Deliver the stated outcome within scope. Adapt routine
> implementation details to current code, preserve the listed contracts, and run
> the relevant acceptance checks. Fix task-caused failures and recheck affected
> behavior. Escalate only the material conditions below. Update the plan's status
> in `.factory/plans/README.md`.
>
> **Drift check**: `git diff --stat 13be69e -- air/json.bend air/text.bend air/disk.bend`
> should be empty or routine. Confirm `Text.rev_onto` (`air/text.bend:23`)
> and `Text.append` (`:32`) exist, and `Disk.read(path) -> IO(Maybe<String>)`.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: LOW (a pure renderer; one response builder)
- **Depends on**: none (012 for the example's static assets is nice, not required)
- **Category**: direction (roadmap Tier 5: template/view rendering)
- **Planned at**: commit `13be69e`, 2026-09-20, clean tree

## Why this matters

Server-rendered HTML in Air is string concatenation today, and nothing
escapes. This plan ships a small Mustache-style renderer: a template string
plus a JSON context gives HTML with every interpolated value escaped unless
the template asks for raw. JSON is the context because apps already build
`Json.Value`s for their APIs (plan 004), it carries lists and nested
objects, and its accessors are total.

Decisions:

- **Syntax**: `{{name}}` escaped; `{{{name}}}` raw; `{{#name}}…{{/name}}`
  renders the block once per item when `name` is an array, once with the
  same context when it is a truthy non-array (non-empty string, non-zero
  number, `true`, non-empty object), and not at all otherwise;
  `{{^name}}…{{/name}}` the inverse; `{{.}}` the current item; `{{! … }}`
  a comment. Names may be dotted (`{{user.name}}`); lookup walks a context
  stack from the innermost item outwards, so a block over a list of objects
  can still read a top-level field. No partials, no set-delimiters, no
  lambdas in this cut.
- **Values as text**: strings as-is; numbers as written; `true`/`false`;
  `null` and a missing name as `""`; arrays and objects as `""` (a template
  that prints an object is a bug, and `""` is the mustache answer).
- **Escaping**: `& < > " '` to `&amp; &lt; &gt; &quot; &#39;`.
- **Malformed templates render, never fail**: an unclosed `{{` is emitted
  literally from that point; an unclosed section renders to the end of the
  template; a stray `{{/x}}` is ignored. Total, no `Maybe`.
- **Templates are strings**: read from disk with `Disk.read` (already in
  the facade) per request, or held in a def. No cache: Bend has no globals,
  and the store (015) is for strings so it could hold them, but a file read
  is fast enough for now and keeps the module pure. Note in the docs.
- **Output building**: append pieces onto a reversed accumulator with
  `Text.rev_onto` and reverse once at the end, so a long template does not
  recurse on the whole output (AGENTS.md runtime rule).

## Current state

- `air/json.bend` — `Value` constructors and `get`, `items`, `fields`, `str`, `u32`, `boolean`, `is_null`, `render`.
- `air/text.bend:23-32` — `rev_onto`, `append`; `split_once`/`split_seq` for finding `{{`.
- `air/http.bend` — `Response.html`.
- `air/disk.bend:79` — `read`.
- `examples/dashboard/public/index.html` — static markup that could take a rendered header (optional).

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Check and prove | `bend PROOF.bend` | `All terms check.` |
| Run the example | `bend examples/hello/main.bend` | listens on 8080 |
| Render | `curl -s 'localhost:8080/page/Ada%20%3Cx%3E'` | `<h1>Hello, Ada &lt;x&gt;</h1>` and a `<li>` per item |

## Implementation rules relevant to this plan

- New module `air/view.bend` (alias `View`), importing `Base`, `./text.bend`,
  `./json.bend`, `./http.bend`.
- Tokenizer: `type Tok is Data: Text{s: String} Var{name: String} Raw{name: String} Open{name: String} Inverted{name: String} Close{name: String} Comment{}`.
  `lex(template: String) -> List<&2, Tok>` scanning for `{{`, then `{{{`,
  `#`, `^`, `/`, `!`, trimming spaces inside the tag; an unterminated tag
  yields `Text` with the rest. Build the list reversed then reverse.
- Lookup: `find(stack: List<&2, Json.Value>, +name: String) -> Json.Value`:
  `.` is the head; a dotted name walks `Json.get` from the first frame that
  has its head segment; absent is `Json.null()`.
- `text_of(v: Json.Value) -> String`, `truthy(v) -> Bool`, `escape(s) -> String`
  (onto a reversed accumulator).
- Renderer: `render.go(toks: List<&2, Tok>, stack, rev: String) -> String & List<&2, Tok>`
  renders until a `Close` or the end and answers the reversed output and the
  remaining tokens. Since `String & List` is an affine pair, return a small
  `type Out is Type: Out{rev: String, rest: List<&2, Tok>}` instead. A
  section: on `Open{name}`, split off its body up to the matching `Close`
  (nesting-aware, counting `Open`/`Inverted` vs `Close`) with
  `body(toks, +name, depth) -> Out-like pair`, then render the body per item
  (or once, or skip) and continue with the rest. Rendering the same body for
  N items needs the token list N times: tokens are Data (strings), so the
  list is `+`-rebindable.
- `render(template: String, ctx: Json.Value) -> String`: `lex`, then
  `render.go` with `[ctx]`, reverse.
- Facade: `Air.View.render(template, ctx)`, `Air.Response.view(template, ctx)`
  (`Response.html(render(..))`), and in the comment the recipe
  `IO.bind(Disk.read("views/page.html"), t => …)` with `None` as a 500 via
  `fail(Internal{"template missing"})`.

## Scope

**In scope**:
- `air/view.bend` (new); `air.bend`; `LAWS.bend`; `PROOF.bend`.
- `examples/hello/main.bend`: route `/page/:name` rendering a template held
  in a def (a heading with `{{name}}`, a list with `{{#items}}<li>{{.}}</li>{{/items}}`,
  an `{{^items}}` empty state) from a `Json.obj` context.
- `README.md`: a "Templates" section with the syntax table and the escaping rule.
- `roadmap.md`: tick "Template/view rendering".
- `.factory/plans/README.md`: row 018.

**Out of scope**: partials, layouts/inheritance, a template cache, compile-
time checking, non-HTML escaping modes.

## Git workflow

- Current worktree branch. Do not commit or push unless asked. `bend PROOF.bend` first.

## Steps

### Step 1: lexer with laws

```
view_lex_text_var:     View.lex("a {{b}} c") == [View.Text{"a "}, View.Var{"b"}, View.Text{" c"}]
view_lex_raw:          View.lex("{{{b}}}") == [View.Raw{"b"}]
view_lex_section:      View.lex("{{#x}}y{{/x}}") == [View.Open{"x"}, View.Text{"y"}, View.Close{"x"}]
view_lex_unterminated: View.lex("a {{b") == [View.Text{"a "}, View.Text{"{{b"}]
```

### Step 2: renderer with laws

```
view_escapes:          View.render("<b>{{x}}</b>", Json.obj([Json.field("x", Json.of_str("<&>\"'"))])) == "<b>&lt;&amp;&gt;&quot;&#39;</b>"
view_raw:              View.render("{{{x}}}", Json.obj([Json.field("x", Json.of_str("<i>"))])) == "<i>"
view_missing_empty:    View.render("[{{x}}]", Json.obj([])) == "[]"
view_list:             View.render("{{#xs}}<{{.}}>{{/xs}}", Json.obj([Json.field("xs", Json.arr([Json.of_u32(1), Json.of_u32(2)]))])) == "<1><2>"
view_inverted:         View.render("{{^xs}}none{{/xs}}", Json.obj([Json.field("xs", Json.arr([]))])) == "none"
view_truthy_object:    View.render("{{#u}}{{name}}{{/u}}", Json.obj([Json.field("u", Json.obj([Json.field("name", Json.of_str("n"))]))])) == "n"
view_stack_lookup:     View.render("{{#xs}}{{.}}{{sep}}{{/xs}}", Json.obj([Json.field("sep", Json.of_str(",")), Json.field("xs", Json.arr([Json.of_str("a"), Json.of_str("b")]))])) == "a,b,"
view_dotted:           View.render("{{u.name}}", Json.obj([Json.field("u", Json.obj([Json.field("name", Json.of_str("n"))]))])) == "n"
view_nested_sections:  View.render("{{#a}}{{#b}}x{{/b}}{{/a}}", Json.obj([Json.field("a", Json.of_bool(True{})), Json.field("b", Json.of_bool(True{}))])) == "x"
view_unclosed_section: View.render("{{#a}}x", Json.obj([Json.field("a", Json.of_bool(True{}))])) == "x"
```

### Step 3: facade, example, docs

### Step 4: live checks

1. `/page/Ada%20%3Cx%3E` → escaped heading, list items, no empty state.
2. A context with an empty list → the empty state.
3. A 10 000-item list rendered without a stack overflow (temporary route or a scratch driver; remove after).

## Test plan

Fourteen laws; three live checks.

## Done criteria

- [ ] `bend PROOF.bend` prints `All terms check.` with the new laws.
- [ ] Live checks 1–3 pass and are noted in the index.
- [ ] `Air.View.render`, `Air.Response.view` exist with comments.
- [ ] README, roadmap, index updated; `air/server.bend` unchanged.

## STOP conditions

- The affine `+` rebinding of a token list across N items is refused
  (`List<&2, Tok>` with `Tok` holding strings should be Data; if the checker
  says otherwise, make the body a `String` re-lexed per item; slower but total).
- The 10 000-item render overflows: the accumulator is not reversed or the
  section body recursion is not tail-shaped; fix before reporting.

## Maintenance notes

- Partials would be `{{> name}}` resolved through a `Map<&2, String>` of
  templates; the lexer already has the shape for one more tag.
