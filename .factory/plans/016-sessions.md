# Plan 016: Cookie-keyed server-side sessions with a TTL

> **Executor instructions**: Deliver the stated outcome within scope. Adapt routine
> implementation details to current code, preserve the listed contracts, and run
> the relevant acceptance checks. Fix task-caused failures and recheck affected
> behavior. Escalate only the material conditions below. Update the plan's status
> in `.factory/plans/README.md`.
>
> **Drift check**: plans 014 and 015 must be DONE. Confirm `Store.update`,
> `Store.swap`, `Store.drop` and `Store.namespaces` exist in `air/store.bend`,
> that `Log.fresh_id` (or its moved equivalent) mints 32 hex chars, and that
> `Http.Cookie.new` still defaults to `Path=/; HttpOnly; SameSite=Lax`
> (`air.bend`, "Cookie" section).

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: LOW (a namespace convention over the store; one middleware; no server change)
- **Depends on**: 015 (store), 014 (random ids)
- **Category**: direction (roadmap Tier 5: sessions)
- **Planned at**: commit `13be69e`, 2026-09-20, clean tree

## Why this matters

A login, a cart, a flash message: each is state tied to one browser across
requests. Air has cookies (plan 006/007) and, after 015, a store. This plan
ties them: a random id in a cookie names a namespace in the store, a
middleware makes sure every request has one, and handlers read and write
fields by name.

Decisions:

- **Server-side only.** Bend has no SHA or HMAC, and FNV-1a is not a MAC, so
  a signed cookie that carries data cannot be built safely. The cookie
  carries only an id; the data lives in the store. Sessions do not survive a
  restart, and every process has its own (documented; a shared store is a
  Tier 6+ question).
- **Id**: 32 hex characters from four random draws, as request ids. Lookup
  is by exact namespace `session:<id>`; an id that names no namespace (or an
  expired one) is replaced, so a guessed or stale cookie never attaches to
  data.
- **Cookie**: name `air_session` by default, `Path=/`, `HttpOnly`,
  `SameSite=Lax`, session-long (no `Max-Age`; the browser drops it when it
  closes, the server drops the data after the TTL). `Secure` is off by
  default and turned on with `Session.secure(cfg, True{})` for production
  behind the TLS proxy. Configurable name via `Session.with_name`.
- **TTL**: `_seen` in each namespace holds the last touch in ms
  (`Nat.show(IO.now())`); a session whose `_seen` is older than `ttl_ms`
  is treated as absent. Default 24 h.
- **Sweep, lazily**: on every `start`, after touching the session, when
  the number of `session:` namespaces exceeds `max` (default 10000) the
  middleware drops every expired one in one `Store.swap` over the shelf.
  Bounded memory, no background task, and no sleeper per request (the
  event loop rule in AGENTS.md).
- **API for handlers**: `Session.get(req, key) -> IO(String)`,
  `Session.set(req, key, value) -> IO(Unit)`, `Session.fields(req) -> IO(Map<&2, String>)`,
  `Session.clear(req) -> IO(Unit)` (drops the data; the id and cookie stay,
  so the next `set` starts fresh), `Session.end(req, res) -> IO(Response)`
  (drops the data and expires the cookie). The id itself is in the local
  `session_id`. Keys starting with `_` are reserved.
- The middleware **always sets the cookie** when it minted an id, on
  whatever response comes back, including errors rendered by `on_error`
  (plan 013's `inherit` keeps cookies too). It never sets it when the id
  came from the client, so an idle chatty client is not re-cookied.

## Current state

- `air/store.bend` (015): `Shelf`, `Store`, `swap`, `update`, `read`, `get`, `set`, `drop`, `namespaces`; request-level helpers.
- `air/log.bend` (014): `draw`, `hex_id`, `fresh_id`; move to `air/random.bend`
  if `Session` importing `Log` reads wrong (it does: do the move, alias `Random`, and
  update `Log` to import it).
- `air/http.bend` — `Request.cookie(r, name)`, `Response.with_cookie`,
  `Response.expire_cookie`, `Cookie.new` and its `with_*`/`secure`.
- `air/http.bend:157-170` — locals.
- Base: `Nat.read(s) -> Maybe<Nat>`, `Nat.sub`, `Nat.show`, `Map.keys`, `Map.del`, `Map.to_list`, `Map.from_list`.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Check and prove | `bend PROOF.bend` | `All terms check.` |
| Run the example | `bend examples/hello/main.bend` | listens on 8080 |
| First visit | `curl -si -c /tmp/jar localhost:8080/count` | `set-cookie: air_session=<32 hex>; Path=/; HttpOnly; SameSite=Lax`, body `1` |
| Second visit | `curl -si -b /tmp/jar localhost:8080/count` | no `set-cookie`, body `2` |
| Forged cookie | `curl -si -b 'air_session=0000…' localhost:8080/count` | a new `set-cookie`, body `1` |
| Logout | `curl -si -b /tmp/jar localhost:8080/logout` | `set-cookie: air_session=; …Max-Age=0` |

## Implementation rules relevant to this plan

- New module `air/session.bend` (alias `Session`), importing `Base`,
  `./text.bend`, `./http.bend`, `./router.bend`, `./store.bend`, `./random.bend`.
- `type Config is Data: Config{name: String, ttl_ms: Nat, max: U32, secure: Bool}`
  (name it `Config` inside the module; the facade calls it `Air.Session()`),
  `default()`, `with_name`, `with_ttl(ms: Nat)`, `with_max`, `secure(cfg, on)`.
- Pure, law-checked:
  - `ns_of(+id: String) -> String`: `"session:" ++ id`.
  - `is_session_ns(+ns: String) -> Bool`.
  - `alive(now: Nat, +ttl: Nat, m: Map<&2, String>) -> Bool`: `_seen` parses
    and `now - seen < ttl`; an absent or unparsable `_seen` is dead. `Nat.sub`
    saturates, so also require `seen <= now`.
  - `touch(now: Nat, m) -> Map<&2, String>`: sets `_seen`.
  - `sweep(now: Nat, +ttl: Nat, shelf: Shelf) -> Shelf`: keeps every
    non-session namespace and every alive session. Build from
    `Map.to_list`/`Map.from_list` (or a fold with `Map.del`); it runs rarely.
  - `count_sessions(shelf) -> U32` over `Map.keys`.
  - `cookie(+cfg, +id) -> Http.Cookie`: `Cookie.new(name, id)` with `secure`.
- IO:
  - `attach(+cfg, req) -> IO(Attached)` where
    `type Attached is Data: Attached{req: Http.Request, id: String, minted: Bool}`:
    reads the cookie; when non-empty and `safe_id` (reuse `Log.safe_id` or
    move it to `Random`) and the namespace is alive → touch, `minted = False`;
    otherwise → `fresh_id`, create the namespace with `_seen`, `minted = True`.
    Both paths end with `with_local(req, "session_id", id)`. Two store calls
    at most; the read and the write are separate `update`s, which is fine
    (two requests with the same cookie racing only touch twice).
  - `maybe_sweep(+cfg, req) -> IO(Unit)`: `Store.namespaces`, count, and
    when over `max`, `Store.swap(sweep(now, ttl))`.
  - `start(+cfg: Config, next: Router.Handler(), req: Http.Request) -> IO(Http.Response)`:
    `attach`, `maybe_sweep`, `next(req')`, then set the cookie when `minted`.
  - `get(req, key)`, `set(req, key, value)`, `fields(req)`, `clear(req)`,
    `end(req, res)`: over `Store.*` with `ns_of(Request.local(req, "session_id"))`;
    an empty id (no `start` in the chain) reads `""` and writes nothing.
    `set` refuses keys starting with `_` (drops the write; document).
- Facade: `Air.Session()` (type), `Air.Session.default/with_name/with_ttl/with_max/secure`,
  `Air.session(cfg)` (the middleware, in "Batteries"), `Air.Session.get/set/fields/clear/end`,
  `Air.Request.session_id(req)` as sugar for the local.

## Scope

**In scope**:
- `air/session.bend`, `air/random.bend` (new; `Log` re-pointed); `air.bend`;
  `LAWS.bend`; `PROOF.bend`.
- `examples/hello/main.bend`: `Air.session(Air.Session.default())` in the
  `use` list after `request_id`/`log` and before `on_error`; routes `/count`
  (reads `n`, writes `n+1`, answers it) and `/logout` (`Session.end`).
- `README.md`: a "Sessions" section: server-side, cookie carries the id,
  no signed cookies (why), TTL and sweep, `secure` for production, the
  reserved `_` keys.
- `roadmap.md`: tick "Sessions".
- `.factory/plans/README.md`: row 016; "Findings": signed cookies rejected (no MAC).

**Out of scope**: flash messages, session regeneration on login (one line for
an app: `clear` then it keeps the id; true regeneration needs `end` plus a
new `start`, note it as a follow-up), persistence, cross-process stores,
`SameSite=None` sessions.

## Git workflow

- Current worktree branch. Do not commit or push unless asked. `bend PROOF.bend` first.

## Steps

### Step 1: `air/random.bend`; `Log` imports it

### Step 2: `air/session.bend` pure defs and laws

```
session_ns:               Session.ns_of("ab") == "session:ab"
session_alive_fresh:      Session.alive(1000n, 500n, Session.touch(800n, Map.new(&2, String))) == True{}
session_dead_old:         Session.alive(2000n, 500n, Session.touch(800n, Map.new(&2, String))) == False{}
session_dead_unseen:      Session.alive(2000n, 500n, Map.new(&2, String)) == False{}
session_sweep_keeps_rate: Map.keys(&2, Map<&2, String>, Session.sweep(2000n, 500n, <shelf with "rate" and one dead session>)) == ["rate"]
session_cookie_defaults:  Http.Cookie.render(Session.cookie(Session.default(), "id")) == "air_session=id; Path=/; HttpOnly; SameSite=Lax"
session_cookie_secure:    Http.Cookie.render(Session.cookie(Session.secure(Session.default(), True{}), "id")) == "air_session=id; Path=/; Secure; HttpOnly; SameSite=Lax"
```

(check the exact attribute order `Cookie.render` emits and pin that.)

### Step 3: the middleware, helpers, facade, example

### Step 4: live checks

Record in the index:

1. First visit mints a cookie and answers `1`; second with the jar answers `2` and no `set-cookie`.
2. A forged 32-zero cookie is replaced and starts at `1`.
3. A malformed cookie (`air_session=<script>`) is replaced.
4. `/logout` expires the cookie; the next visit with the old jar mints a new one and answers `1`.
5. `/boom` on a first visit → 500 rendered by `on_error` **with** `set-cookie` (013's `inherit`).
6. TTL: run once with `Session.with_ttl(2000n)`, wait 3 s, the same jar answers `1` with a new cookie.
7. Sweep: with `with_max(2)`, mint three sessions with three jars, then a fourth after the TTL of the first: `Store.namespaces` (print it from a debug route, remove after) shows only the alive ones.

## Test plan

Seven laws; seven live checks.

## Done criteria

- [ ] `bend PROOF.bend` prints `All terms check.` with the new laws.
- [ ] Live checks 1–7 pass and are noted in the index.
- [ ] `Air.session`, `Air.Session.*`, `Air.Request.session_id` exist with comments.
- [ ] README, roadmap, index updated; `air/server.bend` unchanged.

## STOP conditions

- `Map.from_list`/`Map.to_list` cannot rebuild a `Map<&2, Map<&2, String>>`
  (kind mismatch): write `sweep` as a fold over `Map.keys` with `Map.del`.
  Not a stop.
- The cookie is not set on error responses even after 013: report; the fix
  belongs to `Response.inherit`, not here.

## Maintenance notes

- Plan 017/018 do not touch sessions. A future "flash" helper is
  `Session.get` + `Session.set(.., "")` in the same request.
