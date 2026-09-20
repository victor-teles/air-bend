# Plan 005: Handlers read urlencoded and multipart forms, and repeated query keys

> **Executor instructions**: Deliver the stated outcome within scope. Adapt routine
> implementation details to current code, preserve the listed contracts, and run
> the relevant acceptance checks. Fix task-caused failures and recheck affected
> behavior. Escalate only the material conditions below. Update the plan's status
> in `.factory/plans/README.md`.
>
> **Drift check**: No commits yet; Tier 2 work is uncommitted and DONE. This plan
> does not depend on plan 004. Confirm `Http.Request.parse_query` still returns
> `Maybe<&2, Map<&2, String>>` and `Text.percent_decode(s, plus)` exists.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: LOW
- **Depends on**: none
- **Category**: direction (roadmap Tier 3: query parsing decision, urlencoded and multipart body parsers)
- **Planned at**: no commit yet, 2026-09-19

## Why this matters

A form POST is the second most common body after JSON and today an app must
split `a=1&b=2` itself. The query decision the roadmap asks for was made in
plan 001 (flat, percent-decoded, `+` as space, last value wins) but repeated
keys (`?tag=a&tag=b`) are unreachable. Multipart is how browsers upload
files; Air reads bodies whole under the body limit (1 MiB default), so an
in-memory multipart parser is both feasible and safe.

Decisions:

- **Query stays flat.** `a[b]=1` is a key named `a[b]`. Nested and array
  conventions (`a[]`) are app-level; document and reject.
- **Repeated keys** are reachable through `Request.query_all(r, key)`, which
  re-scans `Request.target`, and `Request.form_all` likewise re-scans the
  body. The maps keep last-wins.
- **Multipart is in memory, text-safe.** Parts are `String`s because bodies
  arrive through `TCP.recv` as UTF-8 text (README "Not yet"): a binary upload
  is not preserved byte-for-byte. Per-file limits and disk spooling are
  deferred; the body limit bounds the whole.
- **No `stream` and no `raw` body parser.** The runtime has no byte-level
  socket receive (`TCP.recv` returns `String`; only `File.read_bytes` exists),
  and bodies are read whole before the handler runs. Both are recorded as
  rejected in the index with that reason.

## Current state

- `air/http.bend`: `Request.parse_query(parts, Some{map})` decodes `k=v`
  pairs with `Text.percent_decode(_, True{})`; `Request.add_query` skips
  empty parts. `Request.body`, `Request.header` (lowercase keys),
  `Request.target` (raw). `Text.split_all(s, '&')`, `Text.split_at(s, '=')`,
  `Text.split_str(s, sep) -> Maybe<Two>` (first occurrence of a substring),
  `Text.has_token`.
- Header parsing lives in `Request.parse_headers(lines, Some{map})` and
  `Request.header_line`; multipart part headers have the same `name: value`
  shape and can reuse them.
- No `Content-Disposition` parameter parser exists; `Text.split_all(v, ';')`
  then `split_at(p, '=')` and quote stripping is enough.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Check and prove | `bend PROOF.bend` | `All terms check.` |
| Probe urlencoded | `curl -s -d 'a=1&b=x+y%21' localhost:8080/form` | app-defined |
| Probe multipart | `curl -s -F 'title=hi' -F 'f=@README.md' localhost:8080/upload` | app-defined |

## Implementation rules relevant to this plan

- Everything walks request data: tail recursion with accumulators only.
  `Text.split_str` is the exemplar for finding a boundary.
- Parsing failures return `None{}` / empty, never die.
- Put multipart in a new `air/form.bend` (imported as `Form`) to keep
  `air/http.bend` about the message layer; urlencoded helpers can live in
  `Http` since they reuse the query parser.

## Scope

**In scope**:
- `air/http.bend` — `Request.query_all`, `Request.form(r, key)`, `Request.form_all`, `Request.media_type(r)` (content-type before `;`, lowercased).
- `air/form.bend` (create) — multipart: `Part{name, filename: Maybe, mime, body}`, `parse(content_type, body) -> Maybe<&2, List<&2, Part>>`, `field(parts, name)`, `file(parts, name)`.
- `air.bend` — wrappers: `Request.query_all`, `Request.form`, `Request.form_all`, `Request.parts`, `Air.Part()` alias and accessors.
- `LAWS.bend`, `PROOF.bend`, `README.md`.
- `examples/hello/main.bend` — add `POST /form` echoing a field, to have a live route.
- `.factory/plans/README.md`.

**Out of scope**: `air/server.bend`; disk spooling; per-file limits; binary safety.

## Git workflow

- Do not commit or push unless asked. `bend PROOF.bend` before any commit.

## Steps

### Step 1: urlencoded and repeated keys (`air/http.bend`)

- `Request.media_type(r)`: lowercase content-type up to the first `;`, trimmed.
- `Request.form(r, key)`: if media type is `application/x-www-form-urlencoded`,
  parse the body with `Request.parse_query` (once per call; bodies are small,
  and caching would change the `Request` type) and look up `key`; else `""`.
- `Request.query_all(r, key)` / `Request.form_all(r, key)`: walk the raw
  pairs (`Text.split_all(qs, '&')`), decode each, collect values whose key
  equals `key`, in order. Share one `collect(parts, key, acc)` def.
  The raw query is `Text.snd(Text.split_at(Request.target(r), '?'))`.

### Step 2: multipart (`air/form.bend`)

- `boundary(content_type) -> Maybe<&2, String>`: media type must be
  `multipart/form-data`; find the `boundary=` parameter (quoted or not).
- `parse(content_type, body)`: split the body on `"--" ++ boundary`; drop the
  preamble; each piece up to the terminating `"--"` is `\r\n` + headers +
  `\r\n\r\n` + content + `\r\n`. Use `Text.split_str` iteratively with an
  accumulator; a piece without the blank line is a parse failure → `None{}`.
- Part headers: reuse `Http.Request.parse_headers` on the header lines
  (split on `\n`, as `Request.parse` does). `content-disposition` gives
  `name="..."` and optional `filename="..."`; `content-type` gives `mime`
  (default `text/plain`).
- Accessors: `field(parts, name) -> String` (first part without a filename
  and with that name, else `""`), `file(parts, name) -> Maybe<&2, Part>`.
- `Http.Request.parts(r) -> Maybe<&2, List<&2, Form.Part>>` cannot live in
  `Http` (it would import `Form`, which imports `Http`: a cycle). Put it in
  `Form` as `Form.parts(req)` and wrap it in `air.bend`.

### Step 3: facade, example, README

`Air.Request.form / form_all / query_all / parts`, `Air.Part()`,
`Air.Part.name / filename / mime / body`, `Air.Form.field / file`. Hello
gets `POST /form` answering `Air.Request.form(req, "name")`. README: a
"Forms" paragraph with the decisions above and the text-only caveat.

### Step 4: laws

```
law query_all_repeats:
  {Http.Request.query_all(<request for "GET /t?tag=a&tag=b%20c&x=1">, "tag") == ["a", "b c"] : List<&2, String>}
law form_decodes:              body "a=1&b=x+y%21" with the urlencoded type; form(r,"b") == "x y!"
law form_needs_media_type:     same body as text/plain; form(r,"b") == ""
law media_type_strips_params:  "Multipart/Form-Data; boundary=xyz" -> "multipart/form-data"
law boundary_quoted:           Form.boundary("multipart/form-data; boundary=\"ab c\"") == Some{"ab c"}
law multipart_two_parts:       a fixed two-part body -> Some{[Part{"title", None, "text/plain", "hi"}, Part{"f", Some{"a.txt"}, "text/plain", "data"}]}
law multipart_missing_blank:   a part without the blank line -> None
law multipart_wrong_type:      application/json body -> None
```

Build requests in laws with the `request(head)` helper from `LAWS.bend`
plus `Http.Request.with_body`.

## Test plan

Laws above; live: the two curl probes against the hello example (add a
temporary `/upload` route if you want to see multipart end to end, and
remove it, or keep `POST /form` only and prove multipart by laws).

## Done criteria

- [ ] `bend PROOF.bend` prints `All terms check.` with the eight laws.
- [ ] `curl -s -d 'name=x+y' localhost:8080/form` answers `x y` on the hello example.
- [ ] README has the Forms paragraph and the index records `stream` and `raw` as rejected.
- [ ] `git status --short` shows only in-scope files.

## STOP conditions

- `Text.split_str` on a 1 MiB multipart body is measurably slow (seconds)
  in a live probe; report before optimizing with a different search.

## Maintenance notes

- When the runtime gains a byte-level receive, `Part.body` should become
  bytes; keep `Part` accessors as the only way apps read it.
- Reviewer focus: boundary matching at piece edges (`\r\n--boundary` versus a
  boundary string appearing inside content is handled by requiring the
  preceding `\r\n`).
