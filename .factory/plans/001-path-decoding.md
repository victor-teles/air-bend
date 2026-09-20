# Plan 001: Requests carry a percent-decoded, dot-normalized path and decoded query

> **Executor instructions**: Deliver the stated outcome within scope. Adapt routine
> implementation details to current code, preserve the listed contracts, and run
> the relevant acceptance checks. Fix task-caused failures and recheck affected
> behavior. Escalate only the material conditions below. Update the plan's status
> in `.factory/plans/README.md`.
>
> **Drift check**: The repo had no commits when this was planned; the whole tree
> was staged as an initial import. Compare `git status --short` against that
> state (every file `A`, `roadmap.md` also modified). If `air/http.bend` or
> `air/text.bend` differ from the excerpts below, reconcile before editing.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED (touches request parsing; a mistake breaks every route)
- **Depends on**: none
- **Category**: direction (roadmap Tier 2: "Path decoding and normalization")
- **Planned at**: no commit yet (initial import staged), 2026-09-19

## Why this matters

Today `Request.path` is the raw request-target with the query split off. A
client asking for `/hello/Ol%C3%A1` reaches the handler with the literal
`%C3%A1` in its param, `/a/../b` is routed as three segments, and `%2F` is
indistinguishable from a real slash only by luck. The roadmap's Tier 2 wants
one canonical path form so routing, later static-file serving, and the
trailing-slash policy (plan 002) all reason about the same string. After this
plan, a handler sees decoded UTF-8 text in path and query, dot segments are
resolved before routing, and a malformed escape or an escape above root is a
400 before any handler runs.

## Current state

Files:

- `air/text.bend` — tail-recursive string helpers. Already has `hex_val`
  (line 128, hex digit value or 16), `hex` (a hex string to U32),
  `char_bytes`, `byte_length`, `split_at`, `split_all`, `segments`
  (non-empty `/`-separated segments), `Two()` (the `String & String` pair).
- `air/http.bend` — `Request` type and `Request.parse`. Path and query are
  produced in `Request.parse.fin` (around line 217):

  ```
  def Request.parse.fin(method: String, version: String, url_ok: Bool, version_ok: Bool, count_ok: Bool, headers: Maybe<&2, Map<&2, String>>, pq: Text.Two()) -> Parsed:
    match url_ok version_ok count_ok headers:
      case False{} _ _ _:
        Refused{414}
      ...
      case True{} True{} True{} Some{h}:
        (path, qs) = pq
        Parsed{Request{
          Method.parse(method),
          version,
          path,
          Request.parse_query(Text.split_all(qs, '&'), Map.new(&2, String)),
          h,
          Map.new(&2, String),
          SNil{}
        }}
  ```

  `pq` comes from `Text.split_at(target, '?')` in `Request.parse.line`.
  `Request.parse_query` / `Request.add_query` (lines 196–207) split each
  `k=v` on the first `=` and `Map.set` it, no decoding.
- `Request` (line 100) is
  `Request{method, version, path, query, headers, params, body}`; every
  accessor matches all seven fields positionally (`case Request{m, v, p, q, h, ps, b}`).
  There are nine such matches in `air/http.bend`; none elsewhere.
- `air/server.bend` logs `Http.Request.path(req)` in `respond` (line 452)
  and `refuse`; nothing else in the server reads the path.
- `air/router.bend` calls `Text.segments(Http.Request.path(req))` in
  `consider.route`. It must keep working unchanged on the new path form.
- `LAWS.bend` / `PROOF.bend`: laws are `law name: {expr == expected : T}`,
  proved by `def Laws.name(): {==}` in the same order. `Http.Parsed`
  currently exposes `Parsed.framing` and `Parsed.keep_alive` for laws that
  drive the full parser.
- `README.md` "Not yet" lists "Percent-decoding of paths and queries".
  `examples/dashboard/main.bend` `tasks` lists "Percent-decode paths" as
  `False{}`.

Bend constraints that shape this work (from `AGENTS.md`, verified against the
code above):

- A def must be declared above every use; no mutual recursion.
- `match` only on parameters or pattern-bound names; carry computed
  conditions as parameters. No `if`.
- Everything on request data must be tail-recursive with an accumulator,
  reversed at the end (`Text.split_once` is the exemplar).
- Bend strings are lists of `Char` (Unicode code points). `TCP.recv` already
  decoded the wire bytes as UTF-8, so a raw non-ASCII character in the
  target arrives as one `Char`; only `%XX` escapes yield bytes that must be
  assembled into code points here.
- Bit operations: `U32.and`, `U32.or`, `U32.shln(a, n: Nat)`, `U32.shrn`.
  `Char.from_u32`, `Char.to_u32` convert.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Check everything and prove laws | `bend PROOF.bend` | prints `All terms check.` |
| Run the starter app | `bend examples/hello/main.bend` | listens on 8080 |
| Manual probe | `curl -i 'localhost:8080/hello/Ol%C3%A1'` | `Olá, Olá!` |
| Manual probe | `curl -i --path-as-is 'localhost:8080/../hello/x'` | `400 Bad Request` |

`bend PROOF.bend` type-checks every module `LAWS.bend` imports, so it is the
gate for compile errors as well as laws.

## Implementation rules relevant to this plan

- Keep the style of `air/text.bend`: small defs, one `match`, computed
  Bools passed as parameters, helper `.go` / `.fin` suffixes.
- New Text defs are named relative to the module (`percent_decode`, not
  `Text.percent_decode`); callers use `Text.percent_decode`.
- Do not use `String.append`, `String.length`, `String.split` on request
  data; use `Text.append`, `Text.byte_length`, `Text.split_all`.
- Refusals go through the existing `Parsed`/`Refused{status}` channel so the
  server's `on_parsed` answers and closes as it does for other 400s.
- Every new pure def that makes a decision gets a law. Laws and proofs stay
  in the same order in both files.

## Scope

**In scope** (the only files you should modify):
- `air/text.bend` — `percent_decode` and its helpers.
- `air/http.bend` — `Request` gains a `target` field; parse normalizes path
  and decodes query; `Parsed.path` accessor for laws.
- `air.bend` — `Air.Request.target` wrapper.
- `LAWS.bend`, `PROOF.bend` — new laws and proofs.
- `README.md` — API line for `target`, a "Paths" note, drop the "Not yet" item.
- `examples/dashboard/main.bend` — flip the "Percent-decode paths" task to `True{}`.
- `.factory/plans/README.md` — status row only.

**Out of scope**:
- `air/router.bend`, `air/server.bend` — untouched; plans 002/003 own the router.
- Query semantics beyond decoding (nested keys, arrays, repeated keys): Tier 3.
- Percent-decoding of header values or bodies.

## Git workflow

- No commits exist. Do not commit or push unless the operator asks; if asked,
  run `bend PROOF.bend` first (repo rule).

## Steps

### Step 1: `Text.percent_decode`

Add to `air/text.bend`, after `hex` and `char_bytes`:

```
# Decodes `%XX` escapes into UTF-8 code points; `plus` turns '+' into a
# space (query strings). None on a bad or truncated escape, an invalid,
# overlong or surrogate UTF-8 sequence, or an escaped NUL.
def percent_decode(+s: String, +plus: Bool) -> Maybe<&2, String>:
```

Implement it as a tail-recursive state machine over
`(s, plus, acc: String, need: U32, cp: U32)`:

- Plain char `c` (not `%`, not `+`): if `need > 0` → `None{}` (a raw char
  interrupted a multi-byte sequence); else push `c`.
- `+`: push `' '` when `plus`, else push `'+'` (same `need` rule).
- `%`: take the next two chars; both must satisfy `hex_val(..) < 16`, else
  `None{}`. Byte `b = h1*16 + h2`:
  - `need == 0`: `b == 0` → `None{}`; `b < 128` → push `Char.from_u32(b)`;
    `0xC2..0xDF` → `need=1, cp=b & 0x1F`; `0xE0..0xEF` → `need=2, cp=b & 0x0F`;
    `0xF0..0xF4` → `need=3, cp=b & 0x07`; anything else → `None{}`.
  - `need > 0`: `b` must be `0x80..0xBF`, else `None{}`;
    `cp = (cp << 6) | (b & 0x3F)`, `need - 1`. When `need` reaches 0, reject
    overlong forms (`cp < 0x80` from a 2-byte lead, `< 0x800` from 3, `< 0x10000`
    from 4), surrogates (`0xD800..0xDFFF`), and `cp > 0x10FFFF`; otherwise push
    `Char.from_u32(cp)`. Track the lead length with a fourth parameter or
    derive the floor from the initial `need`.
- End of string with `need > 0` → `None{}`; else `Some{String.reverse(acc)}`.

Because Bend has no `if`, express the byte classification through one helper
def that takes the computed range Bools (`Bool.and(U32.is_ge(b, 194), U32.is_le(b, 223))`
and so on) as parameters and matches on them, in the style of `take_bytes.go`.

**Evidence**: laws in step 4.

### Step 2: normalize the path in `Http.Request.parse`

In `air/http.bend`:

1. Add `target: String` as the third field of `Request` (after `version`),
   update all nine positional matches, add `Request.target(r)` returning
   the raw request-target as received (path plus `?query`, undecoded).
   `Request.with_params` and `Request.with_body` must carry it through.
2. Add a path pipeline, all above `Request.parse.fin`:
   - `Request.strip_origin(+target)`: an absolute-form target
     (`http://host/x` or `https://host/x`, case-insensitive scheme) drops
     everything up to and including the first `/` after `://`; a target
     without a scheme is unchanged. `*` stays `*`.
   - `Request.decode_segments(segs, acc) -> Maybe<&2, List<&2, String>>`:
     `Text.percent_decode(seg, False{})` on each raw segment. Decoding
     happens after `Text.segments` split on `/`, so `%2F` stays inside its
     segment (it becomes a literal `/` in that one segment).
   - `Request.resolve_dots(segs, acc) -> Maybe<&2, List<&2, String>>`:
     drop `.`; on `..` pop `acc`, and `None{}` when `acc` is empty (an
     escape above root); the result is `List.reverse(acc)`.
   - `Request.render_path(segs, trailing: Bool) -> String`: `"/" ++ join`,
     with a trailing `/` appended when `trailing` and `segs` is non-empty.
     `trailing` is whether the raw path ended with `/` and is longer than
     one char. Do not use `String.join` on request data; fold with
     `Text.append` into an accumulator (`"/" ++ seg` per segment). `*` (the
     OPTIONS asterisk-form) renders as `"*"`, not `"/*"`: special-case the
     raw path `*` before the pipeline.
   - Compose them into `Request.normalize(+raw_path) -> Maybe<&2, String>`.
3. Query: change `Request.add_query` to decode key and value with
   `Text.percent_decode(_, True{})`; a `None{}` from either refuses the
   request. The clean way is to make `Request.parse_query` return
   `Maybe<&2, Map<&2, String>>` (like `Request.parse_headers`) and thread it.
4. `Request.parse.fin` gains the two Maybes as parameters
   (`path: Maybe<&2, String>`, `query: Maybe<&2, Map<..>>`) and adds the
   refusal arms. Suggested order of the head checks: 414 (URL length,
   measured on the raw target as today), 505, 431, 400 for headers, then
   400 for path/query. Keep `Text.byte_length(target, 0)` on the raw target
   so the URL limit is judged on the wire form.
5. Add `Parsed.path(p: Parsed) -> String` (`""` for `Refused`) so laws can
   drive the full parser, matching `Parsed.framing`'s shape.

### Step 3: facade, README, dashboard

- `air.bend`: add `Request.target` next to `Request.path`, with the doc
  comment "The request-target as received: raw path and query, undecoded."
  Update the comment on `Request.path` to say it is percent-decoded, with
  `.` and `..` resolved and repeated slashes collapsed; a trailing slash is
  kept.
- `README.md`: in "API", extend the `Air.Request` accessor line with
  `target`; add a short "Paths" paragraph after "Framing" describing the
  normal form and that a bad escape, an escaped NUL, or `..` above root
  answers 400 and closes the connection. Remove "Percent-decoding of paths
  and queries" from "Not yet" (keep the rest of that bullet).
- `examples/dashboard/main.bend`: `task(4, "Percent-decode paths", True{})`.

### Step 4: laws

Append under a new `# Paths` heading in `LAWS.bend`, with matching
`def Laws.<name>(): {==}` entries in `PROOF.bend` at the same position:

```
law decode_plain:
  {Text.percent_decode("a%20b", False{}) == Some{"a b"} : Maybe<&2, String>}

law decode_utf8:
  {Text.percent_decode("Ol%C3%A1", False{}) == Some{"Olá"} : Maybe<&2, String>}

law decode_plus_in_query:
  {Text.percent_decode("a+b", True{}) == Some{"a b"} : Maybe<&2, String>}

law decode_plus_in_path:
  {Text.percent_decode("a+b", False{}) == Some{"a+b"} : Maybe<&2, String>}

law decode_rejects_short:
  {Text.percent_decode("a%2", False{}) == None{} : Maybe<&2, String>}

law decode_rejects_bad_hex:
  {Text.percent_decode("%zz", False{}) == None{} : Maybe<&2, String>}

law decode_rejects_nul:
  {Text.percent_decode("%00", False{}) == None{} : Maybe<&2, String>}

law decode_rejects_overlong:
  {Text.percent_decode("%C0%80", False{}) == None{} : Maybe<&2, String>}

law decode_rejects_lone_continuation:
  {Text.percent_decode("%C3", False{}) == None{} : Maybe<&2, String>}

law path_decoded:
  {Http.Parsed.path(Http.Request.parse(Http.Limits.default(), "GET /hello/Ol%C3%A1 HTTP/1.1\r"))
    == "/hello/Olá" : String}

law path_keeps_encoded_slash:
  {Http.Parsed.path(Http.Request.parse(Http.Limits.default(), "GET /a%2Fb HTTP/1.1\r"))
    == "/a/b" : String}
```

Note on the last law: after decoding, the segment is the single string
`a/b`; `Request.render_path` joins it as `/a/b`. The router (plan 002) will
split it again, so document in the README that `%2F` is not a routing
boundary-preserving escape in Air. If you prefer to keep the segment list
on the request instead of re-rendering, that is a routine choice, but
`Request.path` must still render as shown and the router must not change
in this plan.

```
law path_collapses_slashes:
  {Http.Parsed.path(Http.Request.parse(Http.Limits.default(), "GET //a///b/ HTTP/1.1\r"))
    == "/a/b/" : String}

law path_resolves_dots:
  {Http.Parsed.path(Http.Request.parse(Http.Limits.default(), "GET /a/./b/../c HTTP/1.1\r"))
    == "/a/c" : String}

law path_rejects_climb:
  {Http.Parsed.framing(Http.Request.parse(Http.Limits.default(), "GET /../etc HTTP/1.1\r"))
    == Http.Unframed{400} : Http.Framing}

law path_rejects_bad_escape:
  {Http.Parsed.framing(Http.Request.parse(Http.Limits.default(), "GET /a%G1 HTTP/1.1\r"))
    == Http.Unframed{400} : Http.Framing}

law path_absolute_form:
  {Http.Parsed.path(Http.Request.parse(Http.Limits.default(), "GET http://h.example/x/y?q=1 HTTP/1.1\r"))
    == "/x/y" : String}

law path_asterisk:
  {Http.Parsed.path(Http.Request.parse(Http.Limits.default(), "OPTIONS * HTTP/1.1\r"))
    == "*" : String}

law query_decoded:
  {Http.Parsed.query(Http.Request.parse(Http.Limits.default(), "GET /s?q=caf%C3%A9+au+lait HTTP/1.1\r"), "q")
    == "café au lait" : String}
```

For the last one add a small `Parsed.query(p, key)` accessor (`""` for
`Refused`) rather than matching a `Parsed` inside the law.

**Evidence**: `bend PROOF.bend` → `All terms check.`

### Step 5: live check

Run `bend examples/hello/main.bend` and probe:

| Request | Expect |
|---|---|
| `curl -s 'localhost:8080/hello/Ol%C3%A1'` | `Olá, Olá!` |
| `curl -s 'localhost:8080/search?q=a+b%21'` | `{"q": "a b!"}` |
| `curl -si --path-as-is 'localhost:8080/../hello/x' \| head -1` | `HTTP/1.1 400 Bad Request` |
| `curl -s --path-as-is 'localhost:8080//hello//x/'` | `Olá, x!` (segments drop empties; trailing slash ignored by today's router) |

## Test plan

Laws above are the tests; there is no other test harness. Add the live
probes' results to the plan status row or the PR description.

## Done criteria

- [ ] `bend PROOF.bend` prints `All terms check.` with the new laws present in both files.
- [ ] `grep -n "percent_decode" air/text.bend air/http.bend` shows the def and both call sites (path segments, query).
- [ ] `Air.Request.target` exists in `air.bend` and is documented in `README.md`.
- [ ] README "Not yet" no longer mentions percent-decoding.
- [ ] The five live probes match.
- [ ] `git status --short` shows changes only in the in-scope files.

## STOP conditions

- The Bend checker refuses the state-machine shape (for example a `match` on
  a computed value) and no tail-recursive alternative fits in `air/text.bend`.
- Keeping `%2F` inside a segment turns out to require changing the router
  in this plan; report instead of editing `air/router.bend`.
- The URL limit or the 414/505/431 order changes behavior for any existing
  law; do not weaken an existing law to pass.

## Maintenance notes

- Plan 002's trailing-slash policy relies on `Request.path` keeping a
  trailing `/` and on `Request.target` to rebuild a redirect with the raw
  query; keep both.
- Plan 003 relies on the `OPTIONS *` target rendering as `"*"`.
- Deferred: raw-query access (`Request.query_string`), nested query keys,
  and a `Request.segments` accessor that would let the router skip
  re-splitting. Tier 3 owns query semantics.
- Reviewer focus: the UTF-8 assembly (overlong and surrogate rejection) and
  that every refusal arm in `Request.parse.fin` is reachable.
