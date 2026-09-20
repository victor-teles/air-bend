# Plan 006: Handlers read cookies, negotiate content, and resolve client IP, host and scheme behind a trusted proxy

> **Executor instructions**: Deliver the stated outcome within scope. Adapt routine
> implementation details to current code, preserve the listed contracts, and run
> the relevant acceptance checks. Fix task-caused failures and recheck affected
> behavior. Escalate only the material conditions below. Update the plan's status
> in `.factory/plans/README.md`.
>
> **Drift check**: No commits yet; Tier 2 uncommitted and DONE. Independent of
> plans 004 and 005. Confirm `Http.Request.header` lowercases names and
> `Text.has_token` / `Text.split_all` exist.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: LOW
- **Depends on**: none
- **Category**: direction (roadmap Tier 3: cookie parsing, content negotiation, client IP + trust-proxy, protocol/host resolution)
- **Planned at**: no commit yet, 2026-09-19

## Why this matters

These are the request-side reads every real app needs and each is a small,
pure parser. Header access is already case-insensitive (plan 001 and before),
so that roadmap item is done. The one runtime fact that shapes this plan:
`TCP.accept` returns only the `Socket` (`bend base TCP.accept`), so Air never
learns the peer address. Client IP therefore exists only when a proxy the
app trusts says so, which is also the documented deployment (README: run
behind a TLS-terminating proxy).

Decisions:

- **Trust is explicit and off by default.** `Trust.none()` ignores every
  `X-Forwarded-*` and `Forwarded` header; `Trust.proxy()` believes them.
  With no trust and no peer address, `client_ip` is `None{}`.
- **Rightmost `X-Forwarded-For` entry wins** under `Trust.proxy()`: it is the
  one the trusted proxy appended. `Forwarded: for=` is read the same way
  (last `for=` pair). This is the single-proxy model; a hop count is deferred.
- **Negotiation is one algorithm** (RFC 9110 §12.4.2 q-values, `*` and
  `type/*` wildcards, most specific then highest q, offer order as tiebreak)
  applied to `Accept`, `Accept-Encoding`, `Accept-Language`, `Accept-Charset`.
  An absent header accepts everything, so the first offer wins.

## Current state

- `air/http.bend`: `Request.header(r, name)` (a repeated header reads joined
  with `", "`, so `Cookie` sent twice still parses), `Request.version`.
- `air/text.bend`: `has_token(v, tok)`, `split_all(s, c)`, `split_at(s, c)`,
  `Two()`, `fst`, `snd`, `map_get`.
- Base `String.trim`, `String.to_lower`, `String.starts_with`. There is no
  `F32.read` (verified 2026-09-20): parse q as thousandths into a `U32`
  (`q=0.8` → 800, `q=1` → 1000, up to three decimals), which is all the
  ordering needs.
- No `Cookie` handling anywhere; `air.bend` has no `Trust` type.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Check and prove | `bend PROOF.bend` | `All terms check.` |
| Probe | `curl -s -H 'Cookie: a=1; b=2' localhost:8080/cookie/b` | `2` (temporary route or law) |

## Implementation rules relevant to this plan

- New module `air/negotiate.bend` (imported as `Negotiate`) for the q-value
  algorithm; cookies, proxy and host helpers go in `air/http.bend` as
  `Request.*` defs since they are plain header reads.
- q comparisons on integers (thousandths) avoid `F32` equality subtleties.
- All walks over header values are tail-recursive.

## Scope

**In scope**:
- `air/http.bend` — `Request.cookie(r, name)`, `Request.cookies(r) -> List<Two>`,
  `Trust` type (`NoProxy{}`, `Proxy{}`), `Request.client_ip(r, trust) -> Maybe String`,
  `Request.host(r, trust)`, `Request.scheme(r, trust)`.
- `air/negotiate.bend` (create) — `pick(header_value, offers) -> Maybe String`, `parse(header_value) -> List<Pref>`.
- `air/http.bend` — `Request.accepts(r, offers)`, `accepts_encoding`, `accepts_language`, thin wrappers over `Negotiate.pick`. (`Http` may import `Negotiate`; `Negotiate` imports only `Text`.)
- `air.bend` — wrappers plus `Air.Trust.none()` / `Air.Trust.proxy()`.
- `LAWS.bend`, `PROOF.bend`, `README.md`, `.factory/plans/README.md`.

**Out of scope**: `Set-Cookie` writing (plan 007), `air/server.bend`,
multi-hop proxy trust, `Forwarded` `by=`/`proto=`/`host=` beyond what
`scheme` and `host` need.

## Git workflow

- Do not commit or push unless asked. `bend PROOF.bend` before any commit.

## Steps

### Step 1: cookies

`Request.cookies(r)`: split the `cookie` header on `;`, trim each, split at
the first `=`, drop empty names, keep order. `Request.cookie(r, name)`:
first match or `""`. Values are returned as sent (no percent-decoding;
RFC 6265 leaves encoding to the app).

### Step 2: negotiation (`air/negotiate.bend`)

```
# One preference: "text/*;q=0.5" is Pref{"text/*", 500}.
type Pref is Data:
  Pref{range: String, q: U32}
```

`parse(v)`: split on `,`, each on `;`; the first piece is the range
(lowercased, trimmed); a `q=` parameter sets q in thousandths (missing →
1000, malformed → 0); other parameters are ignored. `matches(range, offer)`:
equal, or `*`, or `type/*` matching the offer's type (for `Accept`); for
languages `en` matches `en-us` by prefix before `-`. `pick(v, offers)`:
empty `v` → first offer; else for each offer find the best matching pref
(most specific range wins ties in q), drop offers with q = 0, return the
offer with the highest q, earliest offer on ties; `None{}` when nothing
matches. The language prefix rule can be a `Bool` parameter of `pick`.

### Step 3: proxy, host, scheme

- `type Trust is Data: NoProxy{} Proxy{}`.
- `Request.client_ip(r, trust)`: `Proxy{}` → last entry of
  `x-forwarded-for` (split on `,`, trim), else last `for=` pair of
  `forwarded` (strip quotes and `[ ]`), else `None{}`. `NoProxy{}` → `None{}`.
- `Request.host(r, trust)`: `Proxy{}` and `x-forwarded-host` present → it;
  else `host` header; `""` when absent (HTTP/1.0 clients may omit it).
- `Request.scheme(r, trust)`: `Proxy{}` and `x-forwarded-proto` present →
  lowercased first token; else `"http"`.

### Step 4: facade, README

`Air.Request.cookie / cookies / accepts / accepts_encoding /
accepts_language / client_ip / host / scheme`, `Air.Trust()`,
`Air.Trust.none()`, `Air.Trust.proxy()`. README "API" lines and a short
"Behind a proxy" paragraph: why the peer address is unknown, what trust
enables, rightmost-entry rule.

### Step 5: laws

```
cookie_parses:            "a=1; b=x=y" -> cookie "b" == "x=y"
cookie_missing:           -> ""
negotiate_q_order:        pick("text/html;q=0.8, application/json", ["text/html","application/json"]) == Some{"application/json"}
negotiate_wildcard:       pick("*/*", ["text/plain"]) == Some{"text/plain"}
negotiate_specific_wins:  pick("text/*;q=1, text/plain;q=0.2", ["text/plain","text/html"]) == Some{"text/html"}
negotiate_zero_excludes:  pick("gzip;q=0, identity", ["gzip","identity"]) == Some{"identity"}
negotiate_absent_first:   pick("", ["a","b"]) == Some{"a"}
negotiate_nothing:        pick("image/png", ["text/plain"]) == None
negotiate_language_prefix: pick("en, fr;q=0.5", ["fr-ca","en-us"]) with prefix rule == Some{"en-us"}
client_ip_untrusted:      XFF present, Trust NoProxy -> None
client_ip_rightmost:      "1.1.1.1, 2.2.2.2" Proxy -> Some{"2.2.2.2"}
client_ip_forwarded:      'Forwarded: for="[2001:db8::1]";proto=https' Proxy -> Some{"2001:db8::1"}
scheme_forwarded:         x-forwarded-proto: HTTPS, Proxy -> "https"; NoProxy -> "http"
host_header:              Host: example.com -> "example.com"
```

## Test plan

Laws above; one live probe of `cookie` via a temporary route or by
extending the hello example with `GET /cookie/:name` (keep it: it is a
useful demo).

## Done criteria

- [ ] `bend PROOF.bend` prints `All terms check.` with the 14 laws.
- [ ] README documents cookies, negotiation, and the proxy paragraph.
- [ ] Roadmap Tier 3 rows for these four items and "case-insensitive header access" are ticked at build time.
- [ ] `git status --short` shows only in-scope files.

## STOP conditions

- Thousandths parsing turns out ambiguous for inputs like `q=1.` or `q=.5`;
  treat malformed as 0 and report.

## Maintenance notes

- Plan 009 (file responses) may call `accepts` for `Accept-Ranges` no, but
  Tier 5 compression-at-proxy notes and CORS will use `accepts_encoding`
  and `host`.
- Reviewer focus: specificity ordering in `pick` and the rightmost rule.
