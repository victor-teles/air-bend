# Plan 022: Lifecycle hooks as named middleware; plugins documented as route groups

> **Executor instructions**: Deliver the stated outcome within scope. Adapt routine
> implementation details to current code, preserve the listed contracts, and run
> the relevant acceptance checks. Fix task-caused failures and recheck affected
> behavior. Escalate only the material conditions below. Update the plan's status
> in `.factory/plans/README.md`.
>
> **Drift check**: `git diff --stat cea6656 -- air/lib/router.bend air/lib/errors.bend air.bend docs/content/docs/guides`
> should be empty or routine.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW (four small middleware, no server or router change)
- **Depends on**: none (019 recommended, for tests)
- **Category**: dx (roadmap Tier 6: "Lifecycle hooks (onRequest, preHandler, onSend, onResponse, onError)" and "Plugin/extension system with encapsulation rules")
- **Planned at**: commit `cea6656`, 2026-09-22, clean tree

## Why this matters

People arriving from Fastify look for `onRequest`, `preHandler`, `onSend`,
`onResponse` and `onError`, and for plugins that register routes and hooks
in their own scope. Air decided in Tier 4 (plan 010, recorded in
`.factory/plans/README.md`, "Findings considered and rejected") that
**hook phases are onion middleware with a name**. A callback registry
would be copied per request, and functions cannot be copied in Bend. This
plan keeps that promise. It adds four one-purpose middleware whose
argument is a plain function (no `next` to thread, so it cannot be
misused) and maps each Fastify phase to where it goes. It also documents
that a plugin is a def returning `List<Route>`, encapsulated by
`Route.wrap` and `Route.mount`. That needs no new machinery, only a
guide and one worked example.

## Decisions

- **Four hooks**, each `f` a def or a def applied to constants:

  | Air | Fastify phase | Signature of `f` | Runs |
  |---|---|---|---|
  | `Air.on_request(f)` | onRequest (global) / preHandler (inside `Route.wrap`, where params are bound) | `Request -> IO(Request)` | before `next`; `next` gets the returned request |
  | `Air.on_send(f)` | onSend | `Request -> Response -> IO(Response)` | after `next`; the client gets the returned response |
  | `Air.on_response(f)` | onResponse | `Request -> Response -> Nat -> IO(Unit)` (the `Nat` is elapsed ms) | after `next`, **before the write** (see below) |
  | `Air.on_fail(f)` | onError (observe only) | `Request -> Http.Error -> IO(Unit)` | when `next`'s response is `Failed`, before any renderer outside it |

  `on_error(render)` stays the renderer. `on_fail` only observes (to
  report to an error tracker) and returns the response unchanged. The
  request each hook receives is the one that entered the middleware:
  `Request` is `Data`, so it can be kept with `+req = req`.
- **"After the response is sent" is not available.** The server owns the
  socket and has no hook registry (by design, as above). `on_response`
  runs when the app has produced its response, before the server writes
  it. Say so plainly in its comment and the guide. A write failure is
  never seen by app code today either.
- **Short-circuiting stays a middleware's job.** A hook that wants to
  answer early (auth) is written as a middleware that drops `next`, as
  `auth` in `examples/hello/main.bend` does. `on_request` cannot answer.
  That keeps each hook's type simple.
- **Plugins are route groups.** Guide content: a plugin is
  `def my_plugin() -> List<Air.Route()>`, optionally taking constants
  (`my_plugin("/prefix")`). Encapsulation rules, all enforced by what
  exists:
  1. middleware applied with `Air.Route.wrap(~mw, plugin())` reaches only
     that plugin's routes;
  2. `Air.Route.mount(prefix, …)` scopes its paths;
  3. state goes in a store namespace named after the plugin
     (`Air.Store.get(req, "my_plugin", key)`);
  4. locals it sets are prefixed `my_plugin.`;
  5. the app composes plugins with `Air.Route.all([...])`, and
     `Air.Route.check` catches path collisions between plugins at startup.

  There is no `decorate`. Adding fields to `Request` per plugin would need
  an open record, and locals already cover it.

## Current state

- Middleware shape (`air/lib/router.bend:17-37`): `Middleware() = Handler() -> Handler()`,
  written as a def with `next` first. Settings go before `next`:
  `auth(+token, next, req)`. `use(mws, h)` puts the first element
  outermost. `Route.wrap(~mw, routes)` takes a template middleware (a def,
  or a def applied to constants) and applies it to each route.
- Exemplar middleware: `air/lib/errors.bend:17-34` (`on_error`: run
  `next`, inspect the response with `Http.Response.error(res) -> Maybe<&2, Http.Error>`)
  and `air/lib/log.bend` (`log`: `IO.now()` before and after, `Nat.sub`
  for elapsed ms).
- Params are bound by the router before the route's handler runs
  (`router.bend` `run`: `handler(Http.Request.with_params(req, params))`),
  so a middleware inside `Route.wrap` sees `Request.param`. A global one
  (in `use`) does not.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Proof | `bend PROOF.bend` | `All terms check.` |
| Tests (019) | `bend tests/hello.bend` | exit 0 |
| Docs | `cd docs && pnpm build` | exit 0 |
| Native | `bend examples/hello/main.bend -o /tmp/h` | exit 0 |

## Implementation rules relevant to this plan

- New module `air/lib/hooks.bend` importing `Base`, `./http.bend` and
  `./router.bend`. Each hook is `def on_x(f: …, next: Router.Handler(), req: Http.Request) -> IO(Http.Response)`.
  Keep `f` plain (not `+`): it is used once per request.
- Bend: no `if` (a helper def matching a parameter); match only on
  parameters; `+req = req` to keep the request for after `next`.
- Facade: `Air.on_request`, `Air.on_send`, `Air.on_response`,
  `Air.on_fail`, in the middleware section next to `on_error`, each with a
  one-line comment naming its Fastify phase.

## Scope

**In scope**: `air/lib/hooks.bend` (new), `air.bend`, `LAWS.bend` and
`PROOF.bend` (laws where the hook's IO is `IO.pure`, if the checker can
normalize them; see the test plan), `examples/hello/main.bend` (hello
gains: a global `on_response` that counts responses per status class into
the store, and an `on_request` inside the admin group's `wrap` that sets a
local, showing preHandler), `tests/hello.bend` cases (if 019 landed),
`docs/content/docs/guides/hooks.mdx` and `guides/plugins.mdx` (new) +
`meta.json`, roadmap: tick both lines, index row.

**Out of scope**: server-side after-write hooks, an app-wide hook
registry, `decorate`, async/background hooks (a hook can `IO.spawn`
itself if it wants to).

## Steps

### Step 1: `hooks.bend` and the facade

### Step 2: example use and tests

With 019: tests that (a) an `on_send` header appears on a 200 and on a
404; (b) `on_fail` saw the `/boom` error (it writes to the store; the
test reads the store through a second injected request with
`inject_shared`); (c) the preHandler local is visible to `/admin/whoami`.

Without 019: the same as live `curl` checks, recorded in the index row.

### Step 3: the two guides

`hooks.mdx`: the table above, one example per hook, the "before the
write" caveat, and why there is no registry (one sentence). `plugins.mdx`:
the five encapsulation rules, a complete plugin (a `/status` group with
its own middleware and store namespace) and how an app mounts two
plugins.

## Test plan

Laws are only possible if `IO.pure`-built chains normalize under `==`.
Try one law (`on_send` adding a header to `IO.pure(res)`). If the checker
cannot compare `IO` values, drop hook laws and rely on the tests (019) or
the live checks. Record which in the index.

## Done criteria

- [ ] Four hooks exported with comments naming their phases.
- [ ] Hello uses `on_response` globally and `on_request` inside a `wrap`. Both are verified by tests or recorded live checks.
- [ ] `hooks.mdx` and `plugins.mdx` build (`pnpm build`).
- [ ] Both roadmap lines ticked with notes: "named onion middleware; after-write rejected" and "route groups; no registry".
- [ ] `bend PROOF.bend` passes. Hello native-builds.

## STOP conditions

- None expected beyond the generic ones. If `Request` turns out not to be
  duplicable with `+` (it is `Data`, so it should be), pass only
  `method`/`path`/`locals` to the post-`next` hooks and adjust the
  signatures.

## Maintenance notes

- Plan 025 (metrics) and 026 (tracing) are built from the same pieces
  (`on_response` with elapsed ms). If their middleware duplicates timing
  code, factor it here.
