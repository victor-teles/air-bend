import Base
import ./text.bend as Text
import ./http.bend as Http

# Router
# ======
#
# Routes pair a method and a path pattern with a handler. `dispatch`
# runs the first route that matches the request. A pattern is parsed
# once, when the route is made: `/users/:id` binds `id`, `/files/*path`
# binds the rest of the path. There is no tree: handlers are affine
# closures rebuilt per request, so a tree would be rebuilt too.

def Handler() -> Type:
  Http.Request -> IO(Http.Response)

# Middleware
# ----------
#
# A middleware takes the next handler and gives a handler. Written as a
# def with `next` first,
#
#   def logger(next: Handler(), req: Http.Request) -> IO(Http.Response)
#
# the bare name `logger` is a middleware and `logger(h)` a handler. One
# that takes a setting takes it before `next`, `auth(+token, next, req)`,
# and `auth("secret")` is the middleware. To answer without running the
# rest of the chain, drop `next`: it is affine, so that is free, and the
# checker sees that it runs at most once.
def Middleware() -> Type:
  Handler() -> Handler()

# Wraps `h` in each middleware, the first in the list outermost: with
# `use([a, b], h)`, `a` runs first on the way in and last on the way out.
def use(mws: List<Middleware()>, h: Handler()) -> Handler():
  match mws:
    case Nil{}:
      h
    case Con{m, rest}:
      m(use(rest, h))

# One segment of a route pattern. `Rest` is `*name`: it must be last and
# binds the remaining path, joined with "/", possibly "".
type Seg is Data:
  Lit{text: String}
  Param{name: String}
  Rest{name: String}

def classify(+s: String) -> Seg:
  match s:
    case SCon{':', name}:
      Param{name}
    case SCon{'*', name}:
      Rest{name}
    case _:
      Lit{s}

def parse_pattern.go(segs: List<&2, String>, acc: List<&2, Seg>) -> List<&2, Seg>:
  match segs:
    case Nil{}:
      List.reverse(&2, Seg, acc)
    case Con{h, t}:
      parse_pattern.go(t, Con{classify(h), acc})

def parse_pattern(+path: String) -> List<&2, Seg>:
  parse_pattern.go(Text.segments(path), Nil{})

# Whether a path ends with a slash that is not the root's.
def has_slash(+path: String) -> Bool:
  Bool.and(Text.last_is(path, '/'), Bool.not(String.eq(path, "/")))

# `slash` remembers whether the pattern ended with a slash, for the
# strict policy.
type Route is Type:
  Route{method: Http.Method, pattern: List<&2, Seg>, slash: Bool, handler: Handler()}

def new(method: Http.Method, +path: String, handler: Handler()) -> Route:
  Route{method, parse_pattern(path), has_slash(path), handler}

def get(path: String, handler: Handler()) -> Route:
  new(Http.GET{}, path, handler)

def post(path: String, handler: Handler()) -> Route:
  new(Http.POST{}, path, handler)

def put(path: String, handler: Handler()) -> Route:
  new(Http.PUT{}, path, handler)

def delete(path: String, handler: Handler()) -> Route:
  new(Http.DELETE{}, path, handler)

def patch(path: String, handler: Handler()) -> Route:
  new(Http.PATCH{}, path, handler)

# A HEAD route is optional: without one, HEAD runs the GET route and the
# server drops the body.
def head(path: String, handler: Handler()) -> Route:
  new(Http.HEAD{}, path, handler)

# An OPTIONS route is optional: without one, OPTIONS answers 204 with
# the methods the path allows.
def options(path: String, handler: Handler()) -> Route:
  new(Http.OPTIONS{}, path, handler)

# Mounting
# --------

# Prefixes every route with `prefix`: "/api" + "/users/:id" is
# "/api/users/:id". The prefix may hold params; a wildcard in it would
# make every route under it unreachable.
def mount.go(+prefix: List<&2, Seg>, routes: List<Route>) -> List<Route>:
  match routes:
    case Nil{}:
      Nil{}
    case Con{Route{m, pat, slash, h}, rest}:
      Con{Route{m, List.append(&2, Seg, prefix, pat), slash, h}, mount.go(prefix, rest)}

def mount(prefix: String, routes: List<Route>) -> List<Route>:
  mount.go(parse_pattern(prefix), routes)

# Wraps every route's handler in `mw`. The middleware is a template,
# since one function value cannot serve N routes: pass a def, or a def
# applied to constants (`~auth("secret")`), never a local variable.
def wrap(~mw: Middleware(), routes: List<Route>) -> List<Route>:
  match routes:
    case Nil{}:
      Nil{}
    case Con{Route{m, pat, slash, h}, rest}:
      Con{Route{m, pat, slash, mw(h)}, wrap(~mw, rest)}

def append_routes(xs: List<Route>, ys: List<Route>) -> List<Route>:
  match xs:
    case Nil{}:
      ys
    case Con{h, t}:
      Con{h, append_routes(t, ys)}

# Joins route groups in order: `all([pages(), mount("/api", api())])`.
def all(groups: List<List<Route>>) -> List<Route>:
  match groups:
    case Nil{}:
      Nil{}
    case Con{g, rest}:
      append_routes(g, all(rest))

# Conflicts
# ---------

def seg_shape(seg: Seg) -> String:
  match seg:
    case Lit{text}:
      "/" ++ text
    case Param{name}:
      "/:"
    case Rest{name}:
      "/*"

def shape.go(pat: List<&2, Seg>, rev: String) -> String:
  match pat:
    case Nil{}:
      String.reverse(rev)
    case Con{h, t}:
      shape.go(t, Text.rev_onto(seg_shape(h), rev))

# The shape of a pattern, params and wildcards anonymized: "/users/:/*".
# Two routes with the same method and shape conflict.
def shape(pat: List<&2, Seg>) -> String:
  match pat:
    case Nil{}:
      "/"
    case Con{h, t}:
      shape.go(Con{h, t}, SNil{})

# The shape with the pattern's trailing slash, so "/s" and "/s/" are
# two keys: the strict policy tells them apart, and under the others
# the first registered wins.
def shape_with_slash(pat: List<&2, Seg>, slash: Bool) -> String:
  match slash:
    case True{}:
      shape(pat) ++ "/"
    case False{}:
      shape(pat)

# A wildcard anywhere but last can never match.
def rest_misplaced(pat: List<&2, Seg>) -> Bool:
  match pat:
    case Nil{}:
      False{}
    case Con{Rest{n}, Nil{}}:
      False{}
    case Con{Rest{n}, Con{h, t}}:
      True{}
    case Con{p, t}:
      rest_misplaced(t)

def conflicts.note(acc: List<&2, String>, key: String, misplaced: Bool, dup: Bool) -> List<&2, String>:
  match misplaced dup:
    case True{} _:
      Con{"wildcard not last: " ++ key, acc}
    case False{} True{}:
      Con{"duplicate route: " ++ key, acc}
    case False{} False{}:
      acc

def conflicts.go(routes: List<Route>, +seen: Map<&2, String>, acc: List<&2, String>) -> List<&2, String>:
  match routes:
    case Nil{}:
      List.reverse(&2, String, acc)
    case Con{Route{m, +pat, slash, h}, rest}:
      +key = Http.Method.show(m) ++ " " ++ shape_with_slash(pat, slash)
      conflicts.go(
        rest,
        Map.set(&2, String, seen, key, "x"),
        conflicts.note(acc, key, rest_misplaced(pat), String.eq(Text.map_get(seen, key, ""), "x")))

# Every problem in a route list, one line each, in list order:
# "duplicate route: GET /users/:" or "wildcard not last: GET /a/*/b".
# Empty when the list is clean. The list is consumed.
def conflicts(routes: List<Route>) -> List<&2, String>:
  conflicts.go(routes, Map.new(&2, String), Nil{})

def check.report(problems: List<&2, String>) -> IO(Unit):
  match problems:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{h, t}:
      do IO<Unit>:
        IO.print("air: " ++ h)
        check.report(t)

def check.fin(problems: List<&2, String>, clean: Bool) -> IO(Unit):
  match clean:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      do IO<Unit>:
        check.report(problems)
        IO.die(Unit, 1, "air: routes conflict")

# Prints each conflict and ends the process with code 1; returns quietly
# when the routes are clean. Call it in `main` before serving.
def check(routes: List<Route>) -> IO(Unit):
  +problems = conflicts(routes)
  check.fin(problems, List.is_empty(&2, String, problems))

# The patterns of a route list, handlers dropped; for laws.
def pattern_of(routes: List<Route>) -> List<&2, List<&2, Seg>>:
  match routes:
    case Nil{}:
      Nil{}
    case Con{Route{m, pat, slash, h}, rest}:
      Con{pat, pattern_of(rest)}

# Matching
# --------

def bind_segment.lit(m: Map<&2, String>, same: Bool) -> Maybe<&2, Map<&2, String>>:
  match same:
    case True{}:
      Some{m}
    case False{}:
      None{}

# A `Param` binds the request segment; a `Lit` must equal it.
def bind_segment(m: Map<&2, String>, seg: Seg, +s: String) -> Maybe<&2, Map<&2, String>>:
  match seg:
    case Lit{text}:
      bind_segment.lit(m, String.eq(text, s))
    case Param{name}:
      Some{Map.set(&2, String, m, name, s)}
    case Rest{name}:
      Some{Map.set(&2, String, m, name, s)}

# The remaining segments joined with "/": ["a", "b"] is "a/b", [] is "".
def join_rest(segs: List<&2, String>, rev: String) -> String:
  match segs:
    case Nil{}:
      String.drop(String.reverse(rev), 1n)
    case Con{h, t}:
      join_rest(t, Text.rev_onto("/" ++ h, rev))

def match_path(pat: List<&2, Seg>, segs: List<&2, String>, params: Maybe<&2, Map<&2, String>>) -> Maybe<&2, Map<&2, String>>:
  match pat segs params:
    case _ _ None{}:
      None{}
    case Nil{} Nil{} Some{m}:
      Some{m}
    case Nil{} Con{h, t} Some{m}:
      None{}
    case Con{Rest{name}, pt} _ Some{m}:
      Some{Map.set(&2, String, m, name, join_rest(segs, SNil{}))}
    case Con{p, pt} Nil{} Some{m}:
      None{}
    case Con{p, pt} Con{+s, st} Some{m}:
      match_path(pt, st, bind_segment(m, p, s))

# Slash policy
# ------------

# What a trailing slash means. `Ignore` (the default) treats "/a/" and
# "/a" as the same path. `Strict` matches a route only when the request
# and the pattern agree on the slash. `Redirect` answers 308 to the path
# without the slash, query kept, and never redirects "/".
type Slash is Data:
  Ignore{}
  Strict{}
  Redirect{}

def is_strict(policy: Slash) -> Bool:
  match policy:
    case Strict{}:
      True{}
    case Ignore{}:
      False{}
    case Redirect{}:
      False{}

# Under the strict policy a route is only considered when its slash
# agrees with the request's.
def slash_ok(strict: Bool, route_slash: Bool, path_slash: Bool) -> Bool:
  Bool.or(Bool.not(strict), Bool.not(Bool.xor(route_slash, path_slash)))

def gate(ok: Bool, m: Maybe<&2, Map<&2, String>>) -> Maybe<&2, Map<&2, String>>:
  match ok:
    case True{}:
      m
    case False{}:
      None{}

def drop_slashes(+s: String) -> String:
  match s:
    case SCon{'/', t}:
      drop_slashes(t)
    case _:
      s

def with_query(path: String, qs: String) -> String:
  match qs:
    case SNil{}:
      path
    case SCon{h, t}:
      Text.append(path, SCon{'?', SCon{h, t}})

def redirect_target.fin(pq: Text.Two()) -> String:
  (path, qs) = pq
  with_query(String.reverse(drop_slashes(String.reverse(path))), qs)

# Where a redirected request goes: the raw target, undecoded, minus its
# trailing slashes, query kept.
def redirect_target(+target: String) -> String:
  redirect_target.fin(Text.split_at(target, '?'))

# Dispatch
# --------

# The outcome of walking the routes. `Hit` is an exact match. `Fallback`
# is a GET route found while serving HEAD, kept unless an explicit HEAD
# route turns up later. `Miss` carries the methods routes offered for
# this path, so 405 and OPTIONS can list them.
type Pick is Type:
  Hit{handler: Handler(), params: Map<&2, String>}
  Fallback{handler: Handler(), params: Map<&2, String>, allowed: Map<&2, String>}
  Miss{allowed: Map<&2, String>}

def mark(m: Map<&2, String>, name: String) -> Map<&2, String>:
  Map.set(&2, String, m, name, "x")

def marked(+m: Map<&2, String>, name: String) -> Bool:
  String.eq(Text.map_get(m, name, ""), "x")

def with_head(+m: Map<&2, String>, has_get: Bool) -> Map<&2, String>:
  match has_get:
    case True{}:
      mark(m, "HEAD")
    case False{}:
      m

# The `Allow` value: the methods offered, plus HEAD when GET is, plus
# OPTIONS, sorted and joined with ", ".
def render_allow(+allowed: Map<&2, String>) -> String:
  String.join(Map.keys(&2, String, mark(with_head(allowed, marked(allowed, "GET")), "OPTIONS")), ", ")

# Folds one path-matching route into the pick. `same` is an exact method
# match, `head_get` a GET route seen by a HEAD request.
def consider.fin(acc: Pick, handler: Handler(), name: String, same: Bool, head_get: Bool, matched: Maybe<&2, Map<&2, String>>) -> Pick:
  match acc same head_get matched:
    case _ _ _ None{}:
      acc
    case Hit{h, p} _ _ Some{params}:
      Hit{h, p}
    case Miss{allowed} True{} _ Some{params}:
      Hit{handler, params}
    case Fallback{h, p, allowed} True{} _ Some{params}:
      Hit{handler, params}
    case Miss{allowed} False{} True{} Some{params}:
      Fallback{handler, params, mark(allowed, name)}
    case Miss{allowed} False{} False{} Some{params}:
      Miss{mark(allowed, name)}
    case Fallback{h, p, allowed} False{} _ Some{params}:
      Fallback{h, p, mark(allowed, name)}

# `OPTIONS *` asks about the server, not a path: every route counts as
# matching and none is run.
def star_match(star: Bool, matched: Maybe<&2, Map<&2, String>>) -> Maybe<&2, Map<&2, String>>:
  match star:
    case True{}:
      Some{Map.new(&2, String)}
    case False{}:
      matched

# What the walk needs from the request, computed once: its path split
# into segments, its method's name, and the slash and star flags.
type Ask is Data:
  Ask{segs: List<&2, String>, method: String, strict: Bool, path_slash: Bool, star: Bool}

def consider.route(acc: Pick, route: Route, +ask: Ask) -> Pick:
  match route ask:
    case Route{m, pat, slash, handler} Ask{segs, method, strict, path_slash, star}:
      +name = Http.Method.show(m)
      consider.fin(
        acc,
        handler,
        name,
        Bool.and(Bool.not(star), String.eq(name, method)),
        Bool.and(Bool.not(star), Bool.and(String.eq(method, "HEAD"), String.eq(name, "GET"))),
        star_match(star,
          gate(slash_ok(strict, slash, path_slash),
            match_path(pat, segs, Some{Map.new(&2, String)}))))

def consider(acc: Pick, route: Route, +ask: Ask) -> Pick:
  match acc:
    case Hit{handler, params}:
      Hit{handler, params}
    case Fallback{h, p, allowed}:
      consider.route(Fallback{h, p, allowed}, route, ask)
    case Miss{allowed}:
      consider.route(Miss{allowed}, route, ask)

def select(routes: List<Route>, acc: Pick, +ask: Ask) -> Pick:
  match routes:
    case Nil{}:
      acc
    case Con{route, rest}:
      select(rest, consider(acc, route, ask), ask)

# Walks the routes for the request under the slash policy.
def pick(+policy: Slash, routes: List<Route>, +req: Http.Request) -> Pick:
  +path = Http.Request.path(req)
  select(routes, Miss{Map.new(&2, String)},
    Ask{Text.segments(path), Http.Method.show(Http.Request.method(req)), is_strict(policy), has_slash(path), String.eq(path, "*")})

# A path no route knows is 404. One that routes know under other methods
# is 405 with `Allow`, or 204 with `Allow` when the request is OPTIONS.
def miss.pick(+allowed: Map<&2, String>, options: Bool, none: Bool) -> Http.Response:
  match options none:
    case _ True{}:
      Http.Response.not_found()
    case True{} False{}:
      Http.Response.options(render_allow(allowed))
    case False{} False{}:
      Http.Response.method_not_allowed(render_allow(allowed))

def miss(+allowed: Map<&2, String>, options: Bool) -> Http.Response:
  miss.pick(allowed, options, List.is_empty(&2, String, Map.keys(&2, String, allowed)))

def run(pick: Pick, +req: Http.Request) -> IO(Http.Response):
  match pick:
    case Hit{handler, params}:
      handler(Http.Request.with_params(req, params))
    case Fallback{handler, params, allowed}:
      handler(Http.Request.with_params(req, params))
    case Miss{+allowed}:
      IO.pure(Http.Response, miss(allowed, Http.Method.is_eq(Http.Request.method(req), Http.OPTIONS{})))

def describe.miss(+allowed: Map<&2, String>, none: Bool) -> String:
  match none:
    case True{}:
      "none"
    case False{}:
      "miss: " ++ render_allow(allowed)

# What a pick would do, in a word; for laws. A miss lists its `Allow`.
def describe(pick: Pick) -> String:
  match pick:
    case Hit{handler, params}:
      "hit"
    case Fallback{handler, params, allowed}:
      "fallback"
    case Miss{+allowed}:
      describe.miss(allowed, List.is_empty(&2, String, Map.keys(&2, String, allowed)))

def dispatch.go(+policy: Slash, routes: List<Route>, +req: Http.Request, redirect: Bool) -> IO(Http.Response):
  match redirect:
    case True{}:
      IO.pure(Http.Response,
        Http.Response.with_header(Http.Response.empty(308), "location", redirect_target(Http.Request.target(req))))
    case False{}:
      run(pick(policy, routes, req), req)

def is_redirect(policy: Slash) -> Bool:
  match policy:
    case Redirect{}:
      True{}
    case Ignore{}:
      False{}
    case Strict{}:
      False{}

# Runs the first route whose method and path match the request under the
# slash policy. HEAD runs the GET route when no HEAD route matches. A path
# that matches only under other methods answers 405 with `Allow`, or 204
# with `Allow` to OPTIONS; no match answers 404.
def dispatch_with(+policy: Slash, routes: List<Route>, +req: Http.Request) -> IO(Http.Response):
  dispatch.go(policy, routes, req, Bool.and(is_redirect(policy), has_slash(Http.Request.path(req))))

# `dispatch_with` under the default policy: a trailing slash is ignored.
def dispatch(routes: List<Route>, +req: Http.Request) -> IO(Http.Response):
  dispatch_with(Ignore{}, routes, req)
