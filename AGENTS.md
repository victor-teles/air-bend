# Air

A web framework written in Bend 2 (`bend --version` → 2.0.10). Layout:

- `air.bend`: the public surface. Import it as `Air`. It re-exports the
  modules under `air/lib/` (imports are not transitive in Bend):
  - `air/lib/text.bend`: string helpers that are safe on request buffers (`Text`).
  - `air/lib/chunk.bend`: the chunked transfer-coding decoder (`Chunk`).
  - `air/lib/http.bend`: Limits, Method, Status, Request parsing and framing, Response (`Http`).
  - `air/lib/router.bend`: Route, Handler, dispatch (`Router`).
  - `air/lib/race.bend`: deadlines as a race between an effect and a watchdog (`Race`).
  - `air/lib/drain.bend`: the stop switch and the tally of requests in flight (`Drain`).
  - `air/lib/server.bend`: Timeouts and the HTTP/1.1 connection loop over TCP (`Server`).
  - `air/lib/json.bend`, `form.bend`, `negotiate.bend`, `disk.bend`, `static.bend`,
    `errors.bend`, `log.bend`, `random.bend`, `store.bend`, `rate.bend`,
    `session.bend`, `cors.bend`, `shield.bend`: the batteries.
  - `air/lib/test.bend`: running an app on raw HTTP text without a socket (`Test`).
  New features go in a new or existing `air/lib/` module; `air.bend` only
  gains a wrapper when the name is meant for apps. The modules sit one
  level down on purpose: the C backend names a def by its path with every
  punctuation mark turned into `_`, so `air.Json.parse` (the facade) and
  `air/json.parse` (a module) would be the same C symbol and the native
  build would fail with "two names mangle to"; `air/lib/json.parse` cannot
  collide with anything in the facade.
- `examples/`: one folder per demo app. The app (routes, handlers,
  middleware) is in `app.bend`, and `main.bend` serves it, so tests can
  import the app without a second `main`. Each folder has a README.
  - `examples/hello/`: the four-route starter. Run with `bend examples/hello/main.bend`.
  - `examples/dashboard/`: an HTML page with JavaScript and Tailwind served
    from `public/`, plus JSON routes. Run with `bend examples/dashboard/main.bend`.
- `docs/`: the documentation site (Next.js + Fumadocs). Pages are MDX in
  `docs/content/docs/`, ordered by the `meta.json` next to them. Document a
  new feature there, not in the README. Check with `pnpm build` inside `docs/`.
- `LAWS.bend`: claims about the framework, written by the human.
- `PROOF.bend`: their proofs. `bend PROOF.bend` is the gate; run it before committing.
- `tests/`: programs that run the example apps in-process with
  `Air.Test` (`air/lib/test.bend`). `bend tests/hello.bend` and
  `bend tests/dashboard.bend` from the repo root. Each exits 1 on a
  failed check; run them before committing too.

When using Bend:
- run `bend guide` to learn it, and `bend base <Name>` to read a Base def
- use `LAWS.bend` to keep important rules
- run `bend PROOF.bend` before committing
- parallelize the code whenever possible

## Bend rules learned the hard way

The checker enforces these; the guide only hints at some of them.

- A def must be declared above every use. No mutual recursion, and the
  `law` forward-declaration trick Base uses is refused in user code
  ("an unfilled law is a dead claim").
- To loop on a computed condition, carry the condition as a parameter of the
  recursive def and compute it for the next step at the call site. For IO
  loops, keep a state type (`Reading{..}` / `Done{..}`), advance it with a
  pure non-recursive helper, and recurse on a `Nat` fuel that comes first.
- `match` and destructuring `(a, b) = v` work only on parameters and
  pattern-bound variables, never on a `let` or a computed value. Pass the
  value to a helper def instead. A do-block `x : T <- m` binds a plain name;
  no tuple patterns there either.
- Scrutinees must follow parameter order: `match b a:` is refused when `a`
  is declared before `b`, and so is destructuring `a` inside a branch of a
  match on `b`.
- `String & String` is the affine pair, so it cannot live in a `Maybe<&2, ..>`
  or any Data. Use `Sigma<&2, &2, A, _ => B>` (see `Text.Pair`).
- A value that holds a handle (Socket, Listener) can never be `+`. `Chan` is
  Data, so a channel can be shared: that is how tasks talk. A `+` parameter
  cannot be the one abstracted by a partial application (`f(a, b)` passed as
  `c => ...`): take it plain and rebind `+c = c` at the top of the body.
- The event loop scans every parked task on each wait, so never leave a
  sleeper per request behind: one watchdog per connection, re-armed.
- A module's defs are seen through its import alias (`Text.segments`), and
  imports are not transitive: `Air.Text.x` does not exist. Inside `air/`,
  name defs relative to the module (`segments`, not `Text.segments`) and
  avoid Base names (`Pair` collides; `Two` does not). Constructors are
  addressed through the alias too (`Http.GET{}`, `Text.Took{..}`).
- A type cannot be re-exported, only aliased by a def: `Air.Request()` is
  `def Request() -> Data: Http.Request`. Constructors cannot be re-exported at
  all, so the facade offers `Air.Limits.new(..)` instead of `Air.Limits{..}`.
- Bend has no `if`: every branch on a computed Bool goes through a helper
  def that matches on a parameter. Field names in a pattern shadow defs, so
  a def `arm` cannot match `Clock{race, arm, step}` (the field is `dial`).
- A def named after a JavaScript reserved word (`await`) checks but breaks
  the JS backend. An absolute import path with a `-` in it does the same;
  scratch drivers must import with relative paths from inside the repo.
- A `match` with many string-literal arms (`case "html":` times thirteen)
  compiles into something that makes the program take many times longer
  to start. Use a `Map` for lookup tables.
- The C backend mangles `path.Def.name` with every non-alphanumeric
  character as `_`, and refuses two live defs that mangle alike. Keep the
  implementation under `air/lib/` (see the layout above) and native-build
  the examples (`bench/run.sh`) after adding facade names.
- Self-calls must decrease: arguments are read left to right, each passed
  unchanged until one shrinks. Put the list or fuel being consumed first.
- `Nat.read` guards overflow against 2^48 built in unary, so a law that
  reaches it never finishes checking. Parse with `Text.digits` into `U32`
  in anything a law touches.
- Runtime: non-tail recursion on long data overflows the machine stack.
  `String.append(a, b)` recurses on `a`, `Nat.add(a, b)` on `a`,
  `String.length` and `String.split` on the whole string. Keep lengths in
  `U32`, use `Text.append` for big buffers, and put the small operand first.
