Tier 1 — Transport & protocol

- [x] Socket listener, connection accept loop
- [x] HTTP/1.1 request parser: request line, headers, body
- [x] Content-Length vs Transfer-Encoding: chunked (reject conflicting/duplicate headers — this is where request smuggling lives)
- [x] Keep-alive and connection reuse, Connection: close handling
- [x] Response serializer (status line, headers, body framing)
- [x] Limits: max header size, max header count, max URL length, max body size
- [x] Timeouts: idle, headers, body, app, response write — a race on a channel between the effect and a per-connection watchdog (`air/race.bend`); a receive that loses closes its socket when it returns, since Bend cannot cancel it
- [x] Graceful shutdown (stop accepting, drain in-flight) — a switch the app flips and a tally of requests in flight (`air/drain.bend`); no signals in Bend 2.0.10, so the trigger is in-process
- [x] Expect: 100-continue
- [x] No-body rules: HEAD, 204, 304
- [x] TLS termination (or explicit "we run behind a proxy" decision) — decision: run behind a TLS-terminating proxy (documented in README)

Tier 2 — Routing

- [x] Method + path matching
- [x] Path params (/users/:id), wildcards, optional segments — `:id` and `*rest` shipped; optional segments rejected: register two routes (`.factory/plans/README.md`)
- [x] Radix/prefix tree instead of linear regex scan — rejected: handlers are affine closures rebuilt per request, so a tree would be too; patterns are parsed once per route instead
- [x] Sub-routers / mounting / prefix groups — `Air.Route.mount(prefix, routes)` and `Air.Route.all(groups)`
- [x] 404 handling; 405 with a correct Allow header — `Allow` lists the methods routes offer for the path, plus HEAD with GET and always OPTIONS
- [x] Automatic HEAD from GET, automatic OPTIONS — HEAD runs the GET route (explicit HEAD route wins); OPTIONS answers 204 with `Allow`, `OPTIONS *` lists every method
- [x] Trailing-slash policy (strict / redirect / ignore) — `Air.dispatch_with(Air.Slash.strict() / redirect() / ignore(), routes, req)`; redirect is a 308 with the query kept
- [x] Route conflict detection at registration time, not at request time — `Air.Route.check(routes())` in `main`: duplicates and misplaced wildcards exit 1 before the server listens
- [x] Path decoding and normalization (%2F, .., double slashes) — `Text.percent_decode` and `Http.Request.normalize`; a bad escape, escaped NUL, or `..` above root answers 400


Tier 3 — Request / Response objects

Request:

- [x] Case-insensitive header access — names are lowercased at parse
- [x] Query parsing (decide early: flat, or nested/arrays — a[b]=1&c[]=2) — flat, percent-decoded, last wins (plan 001); repeated keys via `query_all` in plan 005; nested rejected
- [x] Body parsers: JSON, urlencoded, text, raw buffer, stream, multipart/form-data (file uploads are their own mini-project: disk vs memory, temp cleanup, per-file limits) — text (`Request.body`), JSON (`Request.json`, `air/json.bend`: strict, depth-capped at 64, numbers kept as text), urlencoded (`Request.form`, `form_all`) and multipart (`Request.parts`, `air/form.bend`, in memory under the body limit, text only) shipped; raw buffer and stream rejected (`TCP.recv` is UTF-8 text, bodies read whole); disk spooling and per-file limits deferred
- [x] Cookie parsing — `Request.cookie(r, name)` and `cookies(r)`, values as sent
- [x] Content negotiation: Accept, Accept-Encoding, Accept-Language — `Request.accepts / accepts_encoding / accepts_language(r, offers)` on one q-value algorithm (`air/negotiate.bend`)
- [x] Client IP + trust-proxy config (X-Forwarded-For/Forwarded) — `Request.client_ip(r, Air.Trust.proxy())`, rightmost entry; `TCP.accept` gives no peer address, so `Trust.none()` (the default stance) always answers None
- [x] Protocol/host resolution — `Request.host(r, trust)` and `Request.scheme(r, trust)`

Response:

- [x] status(), header(), json(), text(), html(), send() — `send` infers the type from the first character
- [x] Content-Type inference and charset — `with_type` adds `; charset=utf-8` to text types, JSON, JavaScript and SVG
- [x] Redirects — 301, 302, 303, 307, 308 and `redirect_with`
- [x] Cookie writing with full attribute support (HttpOnly, Secure, SameSite, Max-Age, Domain, Path) — `Air.Cookie` builder; each cookie is its own `Set-Cookie` line; `SameSite=None` forces `Secure`
- [x] Streaming bodies + SSE — `Air.Response.stream(chan)` / `sse(chan)` over `Air.Stream.new()`: the server drains the channel as chunks under the send timeout per piece, closes it when the client leaves (the producer's send answers False), HEAD gets the head only, HTTP/1.0 gets it unframed; `Air.Sse.event` / `data` format events
- [x] Compression (gzip/brotli) negotiated, with a min-size threshold — rejected: no zlib or brotli effect in Bend 2.0.10; compress at the proxy, like TLS
- [x] File responses: ETag, Last-Modified, conditional 304, Range/206 — `Air.Response.file(req, path, mime)` (`air/disk.bend`): FNV-1a ETag, `If-None-Match` → 304, single byte range → 206 or 416; `Last-Modified` rejected (no file stat effect); text files only

Tier 4 — Middleware & errors

- [x] Pipeline model — pick one and commit: onion/await next() (Koa/Hono) or hook phases (Fastify). This decision shapes the whole public API. — onion: `Air.Middleware()` is `Handler -> Handler`, a def with `next` first; hook phases rejected, since a callback registry would be copied per request and functions cannot be copied
- [x] Global vs per-route vs per-group middleware — `Air.use(mws, handler)` for the app (first in the list outermost); `Air.Route.wrap(~mw, routes)` for a group, a template so one middleware serves every route; `mw(handler)` for one route
- [x] Short-circuiting (middleware returns a response, chain stops) — a middleware that answers without calling `next` drops it; `next` is affine, so the checker enforces at most one call
- [x] Per-request context/state object — `Air.Request.with_local` / `local`: string values, like params and query
- [x] Centralized error handler — `Air.on_error(render)` middleware renders a `Failed` response body (`air/errors.bend`); the router's 404/405/400 are failed bodies too; whatever no renderer catches is settled by the server in prod style
- [x] Typed HTTP error class hierarchy (BadRequest, NotFound, …) — `Http.Error` sum type, `Air.Error.not_found(detail)` and friends plus `Air.Error.other(status, detail)`; `Air.fail(e)` returns one from a handler
- [x] Async rejection capture — no unhandled promise rejections killing the process — `Air.attempt(A, effect, k)` turns a failed effect into a 500 value; `IO.try`/`IO.die` in handlers are documented as forbidden; a runtime crash cannot be caught in Bend 2.0.10
- [x] Dev vs prod error rendering (stack traces only in dev) — `Air.Env` from `AIR_ENV`; `Error.plain(env)` / `Error.json(env)` add method, path and detail in dev only; no stack traces in Bend, the detail string is the closest thing; the server never writes a detail
- [x] Response-already-sent guard (double-send detection) — by construction: a handler is one `IO(Response)` and the server owns the socket; documented, no code

Tier 5 — Batteries
Static file serving (with path traversal protection)
CORS, including preflight
Security headers
Rate limiting
Sessions
Request ID + structured request logging
Schema validation hooks (params/query/body/response)
Template/view rendering
WebSocket upgrade handling

Tier 6 — DX & ops
Type inference from route definitions (params, body, response) if you're in TS — this is the main reason people pick a new framework in 2026
Plugin/extension system with encapsulation rules
Testing helper: inject a request without opening a socket
OpenAPI generation from route schemas
Lifecycle hooks (onRequest, preHandler, onSend, onResponse, onError)
Config + env handling
Metrics + OpenTelemetry tracing hooks
Health/readiness endpoints
Benchmark suite in CI so you catch regressions
Backpressure handling on streaming responses