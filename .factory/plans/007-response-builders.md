# Plan 007: Responses carry cookies with full attributes, typed content, and every redirect status

> **Executor instructions**: Deliver the stated outcome within scope. Adapt routine
> implementation details to current code, preserve the listed contracts, and run
> the relevant acceptance checks. Fix task-caused failures and recheck affected
> behavior. Escalate only the material conditions below. Update the plan's status
> in `.factory/plans/README.md`.
>
> **Drift check**: No commits yet; Tier 2 uncommitted and DONE. This plan
> changes the `Response` constructor. Plans 004–006 add `Response.of_json`
> and read-side helpers; if they landed first, keep their defs compiling
> through the new constructor. Grep `case Response{` before starting.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED (every `Response` match changes; the server renders it)
- **Depends on**: none (004–006 are independent; 008 and 009 depend on this)
- **Category**: direction (roadmap Tier 3: status/header/json/text/html/send, Content-Type inference and charset, redirects, cookie writing)
- **Planned at**: no commit yet, 2026-09-19

## Why this matters

`Response{status, headers: Map, body}` holds one value per header name, so a
handler cannot set two cookies: the second `Set-Cookie` overwrites the
first. Redirects are 302 only. `Response.new(status, body)` sends no
content-type at all. This plan gives `Response` a cookie list rendered as
repeated `Set-Cookie` lines, a cookie builder with every RFC 6265 attribute,
a content-type helper that adds the charset for text types, `send` with
inference, and the redirect family. It is the base for streaming (008) and
file responses (009), which both extend the same type.

Decisions:

- **Cookies are a separate list on `Response`**, not a multi-valued header
  map: `Set-Cookie` is the one header that must not be joined with `, `.
- **`send(body)` infers only three types** from the first non-space char:
  `<` → `text/html`, `{` or `[` → `application/json`, else `text/plain`,
  each with `charset=utf-8` where the type is textual. An explicit
  `with_type` always wins. Sniffing beyond that is Tier 5's static-file job
  by extension.
- **Redirect defaults**: `redirect(url)` stays 302 (compatibility);
  `redirect_with(status, url)` for 301/303/307/308; `see_other(url)` = 303.

## Current state

- `air/http.bend`: `type Response is Data: Response{status: U32, headers: Map<&2, String>, body: String}`;
  accessors `status`, `body`, `header`, `with_status`, `with_header` (lowercases
  the name), builders `empty`, `text`, `html`, `json`, `redirect` (302),
  `not_found`, `method_not_allowed(allow)`, `bad_request`, `options(allow)`;
  `Response.render(r, head_only, keep)` writes `HTTP/1.1 <status> <reason>`,
  the headers from `Map.to_list` (sorted) plus `connection`, then
  `content-length` (skipped for 1xx/204), blank line, body. Laws
  `render_head_only`, `render_204_has_no_length`, `render_options` pin the
  exact wire text and will need their expected strings unchanged (no
  cookies → no extra lines).
- `air/server.bend` reads `Http.Response.status`, `Http.Response.header(res, "connection")`,
  and calls `Http.Response.render`; it never constructs a `Response` by
  constructor (it uses `Response.text`, `with_status`). `grep -n "Response{" air/server.bend`
  should confirm zero constructor uses.
- `air.bend` wraps every builder; `README.md` "API" lists them.
- Tier 2 laws use `Http.Response.header(...)` and `render(...)` on responses
  built by builders only.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Check and prove | `bend PROOF.bend` | `All terms check.` |
| Probe | `curl -si localhost:8080/login \| grep -i set-cookie` | two `set-cookie:` lines (temporary route) |

## Implementation rules relevant to this plan

- Change the constructor once, update every `case Response{s, h, b}` in
  `air/http.bend` (about ten), and keep accessor names unchanged so the
  server and the facade compile without edits beyond new wrappers.
- Cookie rendering is app data, small: Base string ops are fine there.
- Header names stay lowercase on the wire, as today.

## Scope

**In scope**:
- `air/http.bend` — `Response` gains `cookies: List<&2, String>`; `Cookie`
  type and builder; `with_cookie`, `expire_cookie`, `with_type`, `send`,
  `redirect_with`, `see_other`, `permanent_redirect`; `render` emits cookies.
- `air.bend` — wrappers and `Air.Cookie()` alias with builder defs.
- `LAWS.bend`, `PROOF.bend`, `README.md`, `.factory/plans/README.md`.
- `Status.reasons`: add 301 exists; add 303 `See Other`, 307 `Temporary Redirect`, 308 exists, 206 `Partial Content`, 416 `Range Not Satisfiable` (009 needs the last two; adding them here avoids a second edit).

**Out of scope**: `air/server.bend`; streaming bodies (008); file responses (009).

## Git workflow

- Do not commit or push unless asked. `bend PROOF.bend` before any commit.

## Steps

### Step 1: the type

```
type Response is Data:
  Response{status: U32, headers: Map<&2, String>, cookies: List<&2, String>, body: String}
```

Update every match. `Response.new(status, body)` starts with `Nil{}`.

### Step 2: cookies

```
# A cookie to set. `max_age` 0 means "session"; `same_site` is "Lax",
# "Strict", "None" or "" for unset.
type Cookie is Data:
  Cookie{name: String, value: String, path: String, domain: String, max_age: U32, secure: Bool, http_only: Bool, same_site: String}
```

Builders: `Cookie.new(name, value)` → path `/`, no domain, session,
`http_only` true, `secure` false, `same_site` `Lax` (safe defaults);
`Cookie.with_path`, `with_domain`, `with_max_age`, `secure`, `insecure`,
`http_only(b)`, `same_site(s)`. `Cookie.render(c)`:
`name=value; Path=/; Domain=d; Max-Age=n; Secure; HttpOnly; SameSite=Lax`,
omitting empty/false attributes; `SameSite=None` forces `Secure` (browsers
reject it otherwise). `Response.with_cookie(r, c)` appends
`Cookie.render(c)`; `Response.expire_cookie(r, name)` appends
`name=; Path=/; Max-Age=0`. Names and values are emitted as given; a name
with `;`, `=` or whitespace, or a value with `;`, is the app's bug: document
rather than validate (keep the builder total).

### Step 3: content type and send

- `Response.with_type(r, mime)`: sets `content-type`; when `mime` starts
  with `text/` or is `application/json` / `application/javascript` and has
  no `;`, appends `; charset=utf-8`.
- `Response.send(body)`: `with_type(new(200, body), infer(body))` with the
  three-way inference above (skip leading whitespace tail-recursively;
  empty body → `text/plain`).
- Keep `text`, `html`, `json` as they are (they already set charset).

### Step 4: redirects

`redirect_with(status, url)` = `with_header(empty(status), "location", url)`;
`redirect(url)` = `redirect_with(302, url)`; `see_other(url)` = 303;
`permanent_redirect(url)` = 308; `moved(url)` = 301. Add the reasons.

### Step 5: render

After the header lines and before `content-length`, emit one
`set-cookie: <line>\r\n` per cookie in insertion order (walk with an
accumulator; `Response.render_headers` is the model). The three existing
render laws must still pass unchanged.

### Step 6: facade, README, laws

`Air.Cookie()`, `Air.Cookie.new / with_path / with_domain / with_max_age /
secure / http_only / same_site`, `Air.Response.with_cookie / expire_cookie /
with_type / send / redirect_with / see_other / permanent_redirect / moved`.
README "API" Response line grows accordingly; a "Cookies" sentence notes
the defaults.

Laws:

```
cookie_render_defaults:   Cookie.render(Cookie.new("sid","abc")) == "sid=abc; Path=/; HttpOnly; SameSite=Lax"
cookie_render_full:       with domain, max_age 3600, secure, SameSite=Strict -> exact string
cookie_same_site_none_forces_secure
expire_cookie_line:       "sid=; Path=/; Max-Age=0"
render_two_cookies:       render(with_cookie(with_cookie(text("x"), a), b), False, True) == exact string with two set-cookie lines in order
with_type_adds_charset:   header(with_type(empty(200), "text/css"), "content-type") == "text/css; charset=utf-8"
with_type_keeps_binary:   "image/png" unchanged
send_infers_html / send_infers_json / send_infers_text
see_other_status:         status(see_other("/x")) == 303 and location set
reason_303 / reason_206
```

## Test plan

Laws above; a live probe with a temporary two-cookie route on a scratch
copy of the hello example (delete it after).

## Done criteria

- [ ] `bend PROOF.bend` prints `All terms check.`; the three pre-existing render laws are byte-identical.
- [ ] `grep -c "case Response{" air/http.bend` equals the number of accessor/builder matches, all with four fields.
- [ ] `air/server.bend` is unchanged (`git diff --stat air/server.bend` empty).
- [ ] Live probe shows two `set-cookie` lines.
- [ ] `git status --short` shows only in-scope files.

## STOP conditions

- The server turns out to construct `Response{..}` directly somewhere;
  report rather than editing it (a one-line accessor added to `Http` is
  the in-scope fix).

## Maintenance notes

- 008 adds a body variant and 009 adds range headers on top of this type;
  keep `render` as the single place that writes the wire form.
- Reviewer focus: `SameSite=None` forcing `Secure`, and cookie order.
