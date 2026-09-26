Tier 1 — Transport & protocol

- [x] Socket listener, connection accept loop
- [x] HTTP/1.1 request parser: request line, headers, body
- [x] Content-Length vs Transfer-Encoding: chunked (reject conflicting/duplicate headers — this is where request smuggling lives)
- [x] Keep-alive and connection reuse, Connection: close handling
- [x] Response serializer (status line, headers, body framing)
- [x] Limits: max header size, max header count, max URL length, max body size
- [x] Timeouts: idle, headers, body, app, response write — a race on a channel between the effect and a per-connection watchdog (`air/lib/race.bend`); a receive that loses closes its socket when it returns, since Bend cannot cancel it
- [x] Graceful shutdown (stop accepting, drain in-flight) — a switch the app flips and a tally of requests in flight (`air/lib/drain.bend`); no signals in Bend 2.0.10, so the trigger is in-process
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
- [x] Body parsers: JSON, urlencoded, text, raw buffer, stream, multipart/form-data (file uploads are their own mini-project: disk vs memory, temp cleanup, per-file limits) — text (`Request.body`), JSON (`Request.json`, `air/lib/json.bend`: strict, depth-capped at 64, numbers kept as text), urlencoded (`Request.form`, `form_all`) and multipart (`Request.parts`, `air/lib/form.bend`, in memory under the body limit, text only) shipped; raw buffer and stream rejected (`TCP.recv` is UTF-8 text, bodies read whole); disk spooling and per-file limits deferred
- [x] Cookie parsing — `Request.cookie(r, name)` and `cookies(r)`, values as sent
- [x] Content negotiation: Accept, Accept-Encoding, Accept-Language — `Request.accepts / accepts_encoding / accepts_language(r, offers)` on one q-value algorithm (`air/lib/negotiate.bend`)
- [x] Client IP + trust-proxy config (X-Forwarded-For/Forwarded) — `Request.client_ip(r, Air.Trust.proxy())`, rightmost entry; `TCP.accept` gives no peer address, so `Trust.none()` (the default stance) always answers None
- [x] Protocol/host resolution — `Request.host(r, trust)` and `Request.scheme(r, trust)`

Response:

- [x] status(), header(), json(), text(), html(), send() — `send` infers the type from the first character
- [x] Content-Type inference and charset — `with_type` adds `; charset=utf-8` to text types, JSON, JavaScript and SVG
- [x] Redirects — 301, 302, 303, 307, 308 and `redirect_with`
- [x] Cookie writing with full attribute support (HttpOnly, Secure, SameSite, Max-Age, Domain, Path) — `Air.Cookie` builder; each cookie is its own `Set-Cookie` line; `SameSite=None` forces `Secure`
- [x] Streaming bodies + SSE — `Air.Response.stream(chan)` / `sse(chan)` over `Air.Stream.new()`: the server drains the channel as chunks under the send timeout per piece, closes it when the client leaves (the producer's send answers False), HEAD gets the head only, HTTP/1.0 gets it unframed; `Air.Sse.event` / `data` format events
- [x] Compression (gzip/brotli) negotiated, with a min-size threshold — rejected: no zlib or brotli effect in Bend 2.0.10; compress at the proxy, like TLS
- [x] File responses: ETag, Last-Modified, conditional 304, Range/206 — `Air.Response.file(req, path, mime)` (`air/lib/disk.bend`): FNV-1a ETag, `If-None-Match` → 304, single byte range → 206 or 416; `Last-Modified` rejected (no file stat effect); text files only

Tier 4 — Middleware & errors

- [x] Pipeline model — pick one and commit: onion/await next() (Koa/Hono) or hook phases (Fastify). This decision shapes the whole public API. — onion: `Air.Middleware()` is `Handler -> Handler`, a def with `next` first; hook phases rejected, since a callback registry would be copied per request and functions cannot be copied
- [x] Global vs per-route vs per-group middleware — `Air.use(mws, handler)` for the app (first in the list outermost); `Air.Route.wrap(~mw, routes)` for a group, a template so one middleware serves every route; `mw(handler)` for one route
- [x] Short-circuiting (middleware returns a response, chain stops) — a middleware that answers without calling `next` drops it; `next` is affine, so the checker enforces at most one call
- [x] Per-request context/state object — `Air.Request.with_local` / `local`: string values, like params and query
- [x] Centralized error handler — `Air.on_error(render)` middleware renders a `Failed` response body (`air/lib/errors.bend`); the router's 404/405/400 are failed bodies too; whatever no renderer catches is settled by the server in prod style
- [x] Typed HTTP error class hierarchy (BadRequest, NotFound, …) — `Http.Error` sum type, `Air.Error.not_found(detail)` and friends plus `Air.Error.other(status, detail)`; `Air.fail(e)` returns one from a handler
- [x] Async rejection capture — no unhandled promise rejections killing the process — `Air.attempt(A, effect, k)` turns a failed effect into a 500 value; `IO.try`/`IO.die` in handlers are documented as forbidden; a runtime crash cannot be caught in Bend 2.0.10
- [x] Dev vs prod error rendering (stack traces only in dev) — `Air.Env` from `AIR_ENV`; `Error.plain(env)` / `Error.json(env)` add method, path and detail in dev only; no stack traces in Bend, the detail string is the closest thing; the server never writes a detail
- [x] Response-already-sent guard (double-send detection) — by construction: a handler is one `IO(Response)` and the server owns the socket; documented, no code

Tier 5 — Batteries
- [x] Static file serving (with path traversal protection) — `Air.static(dir)` on a `*path` route (`air/lib/static.bend`): refuses a segment with `/` or `\`, `.`/`..` or a leading dot with a 404; `index.html` for a directory; mime by extension; ETag, 304 and ranges from `Response.file`; no listing (no `Dir` effect), symlinks followed
- [x] CORS, including preflight — `Air.cors(cfg)` middleware (`air/lib/cors.bend`): a preflight is answered 204 before the router; `Cors.any()` sends `*`, an origin list echoes the origin with `Vary: origin`; credentials, exposed headers and max-age are settings
- [x] Security headers — `Air.shield(hs)` middleware (`air/lib/shield.bend`): six defaults set only where the handler did not; HSTS and CSP opt-in
- [x] Rate limiting — `Air.rate(n, window_ms, key)` middleware (`air/lib/rate.bend`), a fixed window over the shared store (`air/lib/store.bend`: namespaces of string maps behind a one-slot channel, carried on every request since a template app cannot close over state); 429 with `Retry-After` and `X-RateLimit-*`; keys by trusted client IP or a header
- [x] Sessions — `Air.session(cfg)` middleware (`air/lib/session.bend`): server-side in the store's `sessions` namespace as one JSON string per token, a 32-hex token in an `HttpOnly` `SameSite=Lax` cookie, TTL with a lazy sweep past `max` sessions; signed cookies rejected, no HMAC in Bend; `Air.Session.get/set/incr/fields/clear/end`
- [x] Request ID + structured request logging — `Air.request_id` keeps a safe client id or mints 16 hex chars (one random word plus the clock: a draw is a worker-pool trip), sets `x-request-id`; `Air.log` prints one JSON line per request (`air/lib/log.bend`); the server logs refusals only; `ts` is process uptime, Bend has no wall clock
- [x] Schema validation hooks (params/query/body/response) — `Air.validate_json/query/params(schema)` middleware (`air/lib/schema.bend`): a schema value, every error listed with its path, 422 as JSON bypassing `on_error`; query and params lenient; response validation rejected (a re-parse on the hot path for what laws give)
- [x] Template/view rendering — `Air.Response.view(template, ctx)` and `Air.View.render` (`air/lib/view.bend`): a Mustache subset over a `Json` context, escaped by default, sections, inverted sections, dotted names and an outward lookup stack; malformed templates render; no partials, no cache
- [x] WebSocket upgrade handling — rejected: `TCP.recv` decodes the socket as UTF-8 text and there is no bytes receive, while every client frame is masked binary; SSE (`Air.Response.sse`) covers server push until the runtime gains one

Tier 6 — DX & ops
- [x] Type inference from route definitions (params, body, response) if you're in TS — this is the main reason people pick a new framework in 2026 — rejected: Bend already type-checks every handler, but cannot derive a record type from a pattern string or a `Schema`; the OpenAPI document is the contract clients generate types from
- [x] Plugin/extension system with encapsulation rules — a plugin is a def returning `List<Route>`: `Route.wrap` scopes its middleware, `Route.mount` its paths, a store namespace and prefixed locals its state, `Route.check` catches collisions at startup; no registry and no `decorate` (functions cannot be copied in Bend); guide `plugins.mdx`
- [x] Testing helper: inject a request without opening a socket — `Air.Test.inject(app, raw)` (`air/lib/test.bend`): raw HTTP text read as the server reads it (refusals included), a fresh or shared store, the response settled as the server settles it, streams drained by `Air.Test.body`; `expect`/`finish` print `ok`/`not ok` and exit 1 on failure; `tests/hello.bend` and `tests/dashboard.bend`; timeouts and keep-alive not simulated
- [x] OpenAPI generation from route schemas — routes carry notes (`Router.Note`); `Air.Api.body/query` validate and document with one schema, `Api.returns/summary/tag` document; `Air.openapi(title, version, routes)` serves an OpenAPI 3.1 document (`air/lib/openapi.bend`): path params from patterns, inline JSON Schema, `operationId` from method and path, 400/422 for bodies; lints clean with Redocly's spec rules; no security schemes or `$ref` yet
- [x] Lifecycle hooks (onRequest, preHandler, onSend, onResponse, onError) — `Air.on_request/on_send/on_response/on_fail` (`air/lib/hooks.bend`): middleware that take a function; `on_request` in `use` is onRequest, inside `Route.wrap` preHandler; `on_fail` observes a failure before `on_error` renders it; `on_response` runs before the write (after-write rejected: the server owns the socket)
- [x] Config + env handling — `Air.serve_env(~app, 8080)` (`air/lib/config.bend`): `PORT`, `AIR_MAX_*` limits and `AIR_TIMEOUT_*` timeouts from the environment, a `.env` file loaded and installed in the store for `Air.Config.get(req, name, fallback)`; environment beats `.env` beats code; a set but malformed number ends the process at startup with its name; secret-looking names are never printed; no `${VAR}` expansion (Bend cannot list or set the environment)
- [x] Metrics + OpenTelemetry tracing hooks — Prometheus metrics; W3C trace context with a span exporter hook; OTLP export deferred. Metrics (025): `Air.metrics` and `Air.Metrics.expose` (`air/lib/metrics.bend`) count requests by method, route pattern and status, with a latency histogram per route, in the store's `metrics` namespace; the route label is the pattern the router leaves on the response (`air-route`, removed before writing); unknown methods are `OTHER`; `Air.Metrics.count` adds app counters. Tracing (026): `Air.trace(exporter)` (`air/lib/trace.bend`) continues a valid `traceparent` or starts a trace, gives handlers `trace_id`/`span_id`/`parent_id`/`trace_flags`/`traceparent`/`tracestate` as locals, and hands a `Span` per sampled request to the exporter (`Air.Trace.print` for JSON lines with OpenTelemetry attribute names, `Air.Trace.drop`); `Air.trace_sampled(every, exporter)` samples new roots by trace id; Air's first custom effect, `Air.Clock.wall_ms` (`air/lib/effs/wall_ms.{c,js}`), gives spans and `Air.log`'s `ts` epoch milliseconds; no OTLP, baggage or in-flight gauge
- [x] Health/readiness endpoints — `Air.health()` (`air/lib/health.bend`): `/healthz` and `/readyz`, both `no-store`; `/readyz` is 503 once the stop switch flips (the stopper marks `air/draining` in the store) and while any check the app marked down (`Air.Ready.down/up`, store namespace `ready`); an optional drain delay (`Ready.delay` or `AIR_DRAIN_DELAY`, default 0) keeps serving before the gate closes so balancers see the 503; checks never run inside the probe
- [x] Benchmark suite in CI so you catch regressions — `.github/workflows/ci.yml`: proof, native-built tests, native example builds, docs build, and on pull requests an A/B of hello built from base and head, alternated for five rounds on one runner (`bench/build.sh`, `bench/ab.sh`, `bench/compare.mjs`); fails under 85% of base on GET or POST unless labelled `bench-accepted`; Bend pinned by version and sha256 with clang 19
- [x] Backpressure handling on streaming responses — bounded channel (room 8, `with_room`) + non-blocking send; measured: under a 1 MB/s client, RSS stays flat for room 8 (~4 MB above idle) and room 64 (~25 MB) while the producer keeps the client's pace. A killed client releases the producer in 0.03 s, and a client that never reads is ended by the send timeout. Pieces are not split or capped (keep them at 64 KiB or less); `streaming.mdx`