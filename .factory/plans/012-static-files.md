# Plan 012: Static files from a directory, with path traversal protection

> **Executor instructions**: Deliver the stated outcome within scope. Adapt routine
> implementation details to current code, preserve the listed contracts, and run
> the relevant acceptance checks. Fix task-caused failures and recheck affected
> behavior. Escalate only the material conditions below. Update the plan's status
> in `.factory/plans/README.md`.
>
> **Drift check**: `git diff --stat 13be69e -- air.bend air/disk.bend air/http.bend air/router.bend examples/dashboard LAWS.bend PROOF.bend README.md roadmap.md`
> should be empty or routine. Confirm `Disk.respond(req, path, mime)` still exists
> at `air/disk.bend:81`, that a `*name` segment binds the rest of the path
> (`Router.Rest` at `air/router.bend:47`, law `wildcard_binds_empty` in
> `LAWS.bend`), and that `Request.path` keeps a trailing slash (`air/http.bend:132`).

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW (a handler over `Disk.respond`; no server change)
- **Depends on**: none
- **Category**: direction (roadmap Tier 5: static file serving with path traversal protection)
- **Planned at**: commit `13be69e`, 2026-09-20, clean tree

## Why this matters

Today every static file is its own route (`examples/dashboard/main.bend:26-43`),
and `Response.file` says in its own comment that "nothing here guards against
`..`". An app that maps a wildcard onto a directory by hand can be walked out of
that directory. This plan ships one handler, `Air.static(dir)`, registered on a
wildcard route, that maps the wildcard onto a file under `dir` and refuses
anything that could leave it.

What the request path already guarantees (verified in `air/http.bend:533-625`):
segments are percent-decoded one by one, so `%2F` stays inside a segment as a
literal `/`; `.` and `..` are resolved after decoding, so `%2E%2E` is a real
`..` and gets resolved; a `..` above the root or an escaped NUL refuses the
request with 400. What it does not guarantee: a segment may still contain `/`
or `\` (from `%2F`, `%5C`), and a dotfile like `.env` is a plain segment. The
handler closes those.

Decisions:

- **Wildcard convention**: the route is `Air.Route.get("/assets/*path", Air.static("public"))`
  and the handler reads the param named `path`. One name, documented; an app
  that wants another name writes a two-line handler over `Response.file`.
- **Directory requests**: a request path ending in `/` (or a wildcard that
  binds `""`) serves `index.html` under it. There is no `Dir` effect in Bend
  2.0.10 (`bend base Dir` is empty), so no listing and no stat: a path that
  names a directory without a trailing slash opens as a file and fails, which
  is a 404. No redirect from `/docs` to `/docs/`.
- **Refused segments answer 404, not 403**: revealing that a path exists but
  is forbidden is information; 404 is what a missing file gets too.
- **Mime by extension**, lowercased: `html htm` → `text/html`, `css`, `js mjs`
  → `text/javascript`, `json map` → `application/json`, `svg` →
  `image/svg+xml`, `txt` → `text/plain`, `xml`, `md` → `text/markdown`, `csv`
  → `text/csv`, `webmanifest` → `application/manifest+json`, anything else
  `application/octet-stream`. Files are read as UTF-8 text by the runtime, so
  binary files are not preserved (already documented for `Response.file`).
- **No `Cache-Control`**: `Response.file` already tags an ETag and answers 304
  and 206. A max-age is one `with_header` in a middleware; not in scope.
- **Symlinks** cannot be detected (no stat), so a symlink inside `dir` that
  points outside it is followed. Document it.

## Current state

- `air/disk.bend:81` — `respond(req, path, mime)`: 200 with ETag, 304, 206 or 404.
- `air/text.bend:127` — `segments(path)` splits on `/` and drops empties.
- `air/router.bend:47,189-191` — `Rest{name}` binds the remaining segments joined by `/`, possibly `""`.
- `air/http.bend:132-141` — `Request.path` is normalized and keeps a trailing slash.
- `air.bend:381-386` — `Response.file` facade with the "nothing guards against `..`" note.
- `examples/dashboard/main.bend:26-43` — `serve_file` with a retry from the repo
  root, and two page routes at `:107-111`.
- `README.md:63` — "Static files, and handlers that share state." under "Not yet".
- Conventions: defs in `air/` are named relative to the module; branch on a
  computed Bool through a helper def; `+` on any parameter read twice.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Check and prove | `bend PROOF.bend` | `All terms check.` |
| Run the example | `bend examples/dashboard/main.bend` (and once from `examples/dashboard`) | listens on 8080 |
| Probe | `curl -si localhost:8080/` | 200 `text/html`, `etag` present |
| Probe traversal | `curl -si --path-as-is 'localhost:8080/a%2F..%2F..%2Fmain.bend'` | 404 |

## Implementation rules relevant to this plan

- New module `air/static.bend`, alias `Static`, imported by `air.bend` and
  `LAWS.bend`. It imports `Base`, `./text.bend`, `./http.bend`, `./disk.bend`.
- Pure defs, each a law target:
  - `safe_segment(+s: String) -> Bool`: non-empty, not `.` or `..`, no `/`,
    no `\`, and does not start with `.`. Use `Text.head_is`/`String.contains`
    or a char walk; keep it total.
  - `safe(segs: List<&2, String>) -> Bool`: every segment is safe.
  - `mime_of(+name: String) -> String`: from the text after the last `.` of
    the last segment, lowercased; `application/octet-stream` when there is
    no dot.
  - `target(+path: String, +rest: String) -> String`: `rest` when `path`
    does not end in `/` and `rest` is not empty; otherwise `rest ++ "index.html"`
    when `rest` is empty, else `rest ++ "/index.html"`.
- `respond(+dir: String, req: Http.Request) -> IO(Http.Response)`: rebind
  `+req = req`; compute `t = target(Http.Request.path(req), Http.Request.param(req, "path"))`;
  `segs = Text.segments("/" ++ t)`; when `safe(segs)` is false answer
  `Http.Response.not_found()` (a failed body, so `on_error` renders it);
  otherwise `Disk.respond(req, dir ++ "/" ++ String.join("/", segs), mime_of(t))`.
  Do not pass the raw `rest` to `Disk.respond`: rebuild the path from the
  checked segments.
- Facade: `def static(+dir: String, req: Request()) -> IO(Response()): Static.respond(dir, req)`
  in the "Response" section next to `Response.file`, with a comment giving
  the route shape and the guarantees. `static` is not a JavaScript reserved
  word (`static` is reserved only in strict-mode class bodies; check the JS
  backend once by running the example under `bend --js` if that flag exists,
  otherwise skip and note). If the backend rejects it, name the facade
  `files` and note it in the index.
- Keep `Disk` unchanged; drop the "nothing here guards against `..`" sentence
  from the `Response.file` comment only if it is replaced by "use `static`
  for a directory".

## Scope

**In scope**:
- `air/static.bend` (new), `air.bend` (`Air.static`), `LAWS.bend`, `PROOF.bend`.
- `examples/dashboard/main.bend`: replace `index`/`script`/`serve_file*` with
  one route `Air.Route.get("/*path", public_files)` where `public_files`
  tries `Air.static("public")` and, on a 404, `Air.static("examples/dashboard/public")`
  (keep the existing two-directory behaviour). Put it after the `/api` mount
  in `Route.all` so API routes match first. `examples/dashboard/README.md`:
  drop "Air has no static-file middleware yet".
- `README.md`: "Not yet" loses "Static files"; a short "Static files" section
  with the route shape and the two guarantees (no escape from `dir`, dotfiles
  hidden) and the two gaps (no listing, symlinks followed).
- `roadmap.md`: tick "Static file serving (with path traversal protection)".
- `.factory/plans/README.md`: status row.

**Out of scope**:
- `Cache-Control`, `Last-Modified`, directory listing, binary files,
  precompressed variants, SPA fallback to `index.html` for unknown paths.

## Git workflow

- Current worktree branch. Do not commit or push unless asked. `bend PROOF.bend` first.

## Steps

### Step 1: `air/static.bend`

Write the four pure defs and `respond`. Prove the laws (step 3) before touching
the example.

### Step 2: facade and example

`Air.static`; rewrite the dashboard routes; check `Air.Route.check` still
passes with `/*path` beside the `/api` mount.

### Step 3: laws

Under a "Static files" heading in `LAWS.bend`, with `{==}` proofs in `PROOF.bend`:

```
static_safe_plain:       Static.safe(["css", "app.css"]) == True{}
static_refuses_dotdot:   Static.safe(["..", "main.bend"]) == False{}
static_refuses_slash:    Static.safe(["a/b"]) == False{}
static_refuses_backslash: Static.safe(["a\\b"]) == False{}
static_hides_dotfiles:   Static.safe([".env"]) == False{}
static_mime_html:        Static.mime_of("index.html") == "text/html"
static_mime_upper:       Static.mime_of("APP.JS") == "text/javascript"
static_mime_unknown:     Static.mime_of("archive") == "application/octet-stream"
static_index_root:       Static.target("/", "") == "index.html"
static_index_dir:        Static.target("/docs/", "docs") == "docs/index.html"
static_file:             Static.target("/docs/a.css", "docs/a.css") == "docs/a.css"
```

### Step 4: live checks

From the repo root and once from `examples/dashboard`, record in the index:

1. `curl -si localhost:8080/` → 200, `content-type: text/html; charset=utf-8`, `etag`.
2. `curl -si localhost:8080/app.js` → 200 `text/javascript`.
3. `curl -si -H 'If-None-Match: <etag>' localhost:8080/app.js` → 304.
4. `curl -si --path-as-is 'localhost:8080/..%2Fmain.bend'` → 404 (segment holds `/`).
5. `curl -si --path-as-is 'localhost:8080/%2e%2e/%2e%2e/air.bend'` → 400 from
   the parser (above root) or 404; never the file.
6. `curl -si localhost:8080/.hidden` after `touch examples/dashboard/public/.hidden`
   → 404; remove the file after.
7. `curl -si localhost:8080/api/nope` → 404 rendered as JSON (static's failed
   body goes through `on_error`).
8. `curl -sI localhost:8080/` → HEAD gets the head only.

## Test plan

Eleven laws for the pure parts; eight live checks. No bench run needed (the
dashboard is not the bench target).

## Done criteria

- [ ] `bend PROOF.bend` prints `All terms check.` with the eleven new laws.
- [ ] Dashboard serves `index.html` and `app.js` through `Air.static` from both working directories.
- [ ] Live checks 1–8 pass and are noted in the index.
- [ ] README and roadmap updated; `air/server.bend` unchanged.

## STOP conditions

- A route `/*path` alone (no literal before the wildcard) is refused by
  `Route.check` or never matches `/`. Fallback to try first: register both
  `Route.get("/", public_files)` and `Route.get("/*path", public_files)`. If
  the router cannot express a root wildcard at all, report; changing the
  router is a separate plan.
- `String.join` or `Text.segments` behaves differently from what the laws
  assume (for instance keeping empties): adjust `safe` to also refuse empty
  segments and note it.

## Maintenance notes

- Plan 013's `shield` middleware is what adds security headers to static
  responses; nothing here sets them.
- A future `Cache-Control` helper belongs in `Http.Response`, not here.
