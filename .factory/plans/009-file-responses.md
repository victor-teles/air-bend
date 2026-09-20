# Plan 009: Handlers answer with a file, with ETag, conditional 304, and byte ranges

> **Executor instructions**: Deliver the stated outcome within scope. Adapt routine
> implementation details to current code, preserve the listed contracts, and run
> the relevant acceptance checks. Fix task-caused failures and recheck affected
> behavior. Escalate only the material conditions below. Update the plan's status
> in `.factory/plans/README.md`.
>
> **Drift check**: Requires plan 007 (four-field `Response`, reasons 206 and
> 416). Independent of 008. Confirm `Text.take_bytes` exists and the dashboard
> still has its `read_loop` file reader.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: LOW
- **Depends on**: `.factory/plans/007-response-builders.md`
- **Category**: direction (roadmap Tier 3: file responses with ETag, Last-Modified, conditional 304, Range/206)
- **Planned at**: no commit yet, 2026-09-19

## Why this matters

The dashboard reads its own files with a 40-line loop copied into the
example. Every app serving a page needs the same loop plus caching headers,
and the loop belongs in Air. This plan moves it to `air/file.bend`, adds
`Response.file(path, mime)`, a content-derived ETag, `If-None-Match` → 304,
and `Range` → 206, so a browser reloading the dashboard sends a few bytes
instead of the page.

Decisions, forced by the runtime:

- **No `Last-Modified`.** `bend base File` has `open`, `read`, `read_bytes`,
  `write`, `close` and no stat, so the mtime is unknown. Record as rejected
  with that reason; revisit when a stat effect exists.
- **ETag is a strong tag from content**: 32-bit FNV-1a over the code points
  plus the byte length, rendered as `"<hex>-<len>"`. Reading the file is
  already the cost; hashing adds one pass. Tier 5 static serving may cache
  tags per path.
- **Text files only.** Files are read with `File.read` as UTF-8 text because
  `TCP.send` takes a `String` (README "Not yet"); a PNG is not preserved.
  `Response.file` is for HTML, CSS, JS, SVG, JSON, text. Document; the
  binary path waits on a byte-level send.
- **Ranges are byte ranges** computed with `Text.take_bytes`, which already
  refuses to split a character (`TakeBad`): such a range answers 416,
  which is honest given the text-only constraint.

## Current state

- `examples/dashboard/main.bend` lines 17–68: `OpenR()`, `ReadR()`,
  `FileState`, `read_more`, `read_step`, `read_loop(fuel, state)`,
  `read_opened`, `read_fallback`, `read_public`; then `with_type`,
  `serve_file.fin`, `serve_file`, `index`, `script`. The reader closes the
  handle on EOF, error or fuel exhaustion and uses `Text.append` to stay
  off the stack.
- `air/text.bend`: `take_bytes(s, n) -> Take` (`Took{head, rest}`,
  `TakeNeed`, `TakeBad`), `byte_length`, `hex_val`, `digits` (strict
  decimal), `split_at`, `split_str`.
- `air/http.bend` after 007: `Response.with_type`, `Status.reasons` with 206
  and 416, `Request.header`.
- Base: `U32.xor`, `U32.mul` (wraps mod 2^32, verify with a law), `U32.show`
  is decimal; hex rendering needs a small `Text.hex_show(n)` (nibbles
  through a lookup on `"0123456789abcdef"`).

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Check and prove | `bend PROOF.bend` | `All terms check.` |
| Probe | `curl -si localhost:8080/ \| grep -i "etag\|accept-ranges"` | both present |
| Probe 304 | `curl -si -H 'If-None-Match: "<tag>"' localhost:8080/ \| head -1` | `304 Not Modified` |
| Probe range | `curl -si -H 'Range: bytes=0-9' localhost:8080/app.js \| grep -i "^HTTP\|content-range"` | `206`, `bytes 0-9/<len>` |

## Implementation rules relevant to this plan

- `air/file.bend` (imported as `File`… collides with Base `File`; name it
  `air/disk.bend`, alias `Disk`) holds the reader; `Http` gets the pure
  parts (ETag, range parsing, 304/206 decisions) so they have laws. `Disk`
  imports `Http` and `Text`.
- The reader is IO with `Nat` fuel, exactly as the dashboard has it.
- Range parsing is strict: `bytes=a-b`, `bytes=a-`, `bytes=-n`; anything
  else, multiple ranges, or an unsatisfiable range → 416 with
  `content-range: bytes */<len>`. `If-Range` is ignored (deferred).

## Scope

**In scope**:
- `air/disk.bend` (create) — `read(path) -> IO(Maybe<&2, String>)` (None on open/read failure), `respond(req, path, mime) -> IO(Http.Response)`.
- `air/http.bend` — `etag(body) -> String`, `Range` type and `parse_range(header, len) -> RangeResult`, `Response.conditional(req, res)` (304 when `if-none-match` lists the tag or `*`), `Response.ranged(req, res)` (206/416), `accept-ranges: bytes`.
- `air/text.bend` — `hex_show`, `fnv1a`.
- `air.bend` — `Air.Response.file(req, path, mime) -> IO(Response)` (wrapper over `Disk.respond`), `Air.Disk.read`.
- `examples/dashboard/main.bend` — delete the reader; `index`/`script` call `Air.Response.file`, keeping the two-path fallback via a tiny helper.
- `LAWS.bend`, `PROOF.bend`, `README.md`, `.factory/plans/README.md`.

**Out of scope**: static-file routing and path traversal checks (Tier 5;
this plan takes a path the app chose), `Last-Modified`, `If-Range`,
multipart ranges, binary files, `air/server.bend`.

## Git workflow

- Do not commit or push unless asked. `bend PROOF.bend` before any commit.

## Steps

### Step 1: hashing (`air/text.bend`)

`fnv1a(s, acc)`: start `2166136261`, per char `acc = (acc xor code) * 16777619`
(U32 wraps). `hex_show(n)`: eight lowercase hex digits. Both tail-recursive.

### Step 2: ETag and conditionals (`air/http.bend`)

- `etag(body) = "\"" ++ hex_show(fnv1a(body, seed)) ++ "-" ++ U32.show(byte_length) ++ "\""`.
- `Response.with_etag(r)`: computes over the body and sets `etag` and
  `accept-ranges: bytes`.
- `Response.conditional(req, res)`: if `if-none-match` is `*` or its
  comma-separated list (trim, drop a `W/` prefix) contains the response's
  `etag` header → `Response.empty(304)` carrying `etag`, `content-type`
  and `cache-control` from `res` (304 keeps validators; `render` already
  omits the body and keeps `content-length` for 304 per the Tier 1 law, so
  set the body to the original to keep the length, or document the choice).
- Ranges: `parse_range(h, len)`: `NoRange{}`, `Range{first, last}`
  (inclusive, clamped last to len-1), `Bad{}`. `Response.ranged(req, res)`:
  `NoRange` → res; `Bad` → 416 with `content-range: bytes */len`; `Range`
  → 206 with `content-range: bytes first-last/len` and the body sliced by
  `Text.take_bytes` twice (drop `first`, take `last-first+1`); a `TakeBad`
  from either slice → 416. Only for GET and HEAD; other methods ignore
  `Range`.

### Step 3: the reader (`air/disk.bend`)

Move the dashboard's loop: `read(path) -> IO(Maybe<&2, String>)`, 64 KiB
chunks, fuel 1000n (that is 64 MiB; the body limit is not involved on the
way out). `respond(req, path, mime)`: `None` → `not_found()`; `Some{body}`
→ `ranged(req, conditional(req, with_etag(with_type(new(200, body), mime))))`.
Order matters: the conditional check uses the full-body tag; a range on a
304 is moot.

### Step 4: dashboard, facade, README

`index` and `script` become `Air.Response.file(req, "public/index.html", mime)`
with the repo-root fallback path tried when the first answers 404 (a small
`or_else` in the example, since `respond` is IO). Delete the reader defs.
README "API": `Air.Response.file(req, path, mime)` and a "Files" paragraph
with the ETag, 304, 206/416 behavior and the text-only note.

### Step 5: laws

```
fnv1a_known:        fnv1a("a") == 0xe40c292c (3826002220)
hex_show_pads:      hex_show(255) == "000000ff"
etag_shape:         etag("hello") == "\"<hex>-5\""  (compute the hex once and pin it)
parse_range_forms:  "bytes=0-9" -> Range{0,9}; "bytes=5-" len 10 -> Range{5,9}; "bytes=-3" len 10 -> Range{7,9}
parse_range_clamps: "bytes=0-99" len 10 -> Range{0,9}
parse_range_bad:    "bytes=9-3", "bytes=10-" len 10, "chars=0-1", "bytes=0-1,3-4" -> Bad
conditional_304:    if-none-match matching -> status 304 with etag kept
conditional_weak:   "W/\"tag\"" matches
ranged_206:         body "hello world", bytes=0-4 -> 206, body "hello", content-range "bytes 0-4/11"
ranged_multibyte_416: body "héllo", bytes=0-1 -> 416
```

## Test plan

Laws above; the three probes against the dashboard.

## Done criteria

- [ ] `bend PROOF.bend` prints `All terms check.`
- [ ] `grep -n "read_loop\|FileState" examples/dashboard/main.bend` returns nothing.
- [ ] Probes: ETag present; matching `If-None-Match` → 304 with no body; `Range: bytes=0-9` → 206 with `content-range`.
- [ ] README documents files and the index records `Last-Modified` as rejected (no stat effect).
- [ ] `git status --short` shows only in-scope files.

## STOP conditions

- `U32.mul` does not wrap modulo 2^32 (the `fnv1a_known` law fails on
  overflow semantics); report and switch to a different 32-bit hash before
  pinning tags.

## Maintenance notes

- Tier 5 static serving must add path normalization against `..` before
  calling `Disk.respond`, and may memoize `etag` per path.
- Reviewer focus: `Text.take_bytes` used for both the drop and the take so
  the slice is byte-accurate; 416 on a split character.
