import Base
import ./text.bend as Text
import ./http.bend as Http
import ./disk.bend as Disk

# Static
# ======
#
# A directory as a handler. Register it on a wildcard route,
#
#   Air.Route.get("/assets/*path", Air.static("public"))
#
# and the `path` param names the file under `public/`. The request path
# is already percent-decoded segment by segment with `.` and `..`
# resolved, so what is left to refuse is a segment that still holds a
# `/` or `\` (from `%2F`, `%5C`), a `.` or `..` that survived, and a
# dotfile. Anything refused is a 404, like a missing file: whether a
# path exists is not for a client to learn. A directory serves its
# `index.html`; there is no listing and no stat, so a symlink inside
# the directory is followed wherever it points.

# Refusing
# --------

def bad_char(+c: Char) -> Bool:
  Bool.or(Char.is_eq(c, '/'), Char.is_eq(c, '\\'))

def has_bad_char(s: String) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{h, t}:
      Bool.or(bad_char(h), has_bad_char(t))

# A segment is safe when it is non-empty, does not start with `.` (so
# neither `.`, `..` nor a dotfile), and holds no slash of either kind.
def safe_segment(+s: String) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{'.', t}:
      False{}
    case SCon{h, t}:
      Bool.not(has_bad_char(SCon{h, t}))

def safe(segs: List<&2, String>) -> Bool:
  match segs:
    case Nil{}:
      True{}
    case Con{h, t}:
      Bool.and(safe_segment(h), safe(t))

# Naming
# ------

def ext.go(s: String, acc: String, has_dot: Bool) -> String:
  match s:
    case SNil{}:
      Bool.pick(String, has_dot, String.reverse(acc), SNil{})
    case SCon{'.', t}:
      ext.go(t, SNil{}, True{})
    case SCon{h, t}:
      ext.go(t, SCon{h, acc}, has_dot)

# The text after the last `.` of the last segment, lowercased; "" when
# there is no dot.
def ext(+name: String) -> String:
  String.to_lower(ext.go(String.reverse(Text.fst(Text.split_at(String.reverse(name), '/'))), SNil{}, False{}))

def mime_table() -> Map<&2, String>:
  m = Map.new(&2, String)
  m = Map.set(&2, String, m, "html", "text/html")
  m = Map.set(&2, String, m, "htm", "text/html")
  m = Map.set(&2, String, m, "css", "text/css")
  m = Map.set(&2, String, m, "js", "text/javascript")
  m = Map.set(&2, String, m, "mjs", "text/javascript")
  m = Map.set(&2, String, m, "json", "application/json")
  m = Map.set(&2, String, m, "map", "application/json")
  m = Map.set(&2, String, m, "svg", "image/svg+xml")
  m = Map.set(&2, String, m, "txt", "text/plain")
  m = Map.set(&2, String, m, "xml", "application/xml")
  m = Map.set(&2, String, m, "md", "text/markdown")
  m = Map.set(&2, String, m, "csv", "text/csv")
  m = Map.set(&2, String, m, "webmanifest", "application/manifest+json")
  m

# By extension; `application/octet-stream` for anything unknown.
def mime_of(+name: String) -> String:
  Text.map_get(mime_table(), ext(name), "application/octet-stream")

def target.go(+rest: String, dir: Bool) -> String:
  match dir:
    case True{}:
      Bool.pick(String, String.is_empty(rest), "index.html", rest ++ "/index.html")
    case False{}:
      rest

# The file the wildcard names: `rest` itself, or its `index.html` when
# the request path ends in `/` or the wildcard bound nothing.
def target(+path: String, +rest: String) -> String:
  target.go(rest, Bool.or(String.is_empty(rest), Text.last_is(path, '/')))

# Serving
# -------

def respond.go(+dir: String, +req: Http.Request, +t: String, segs: List<&2, String>, ok: Bool) -> IO(Http.Response):
  match ok:
    case False{}:
      IO.pure(Http.Response, Http.Response.not_found())
    case True{}:
      Disk.respond(req, dir ++ "/" ++ String.join(segs, "/"), mime_of(t))

# The file under `dir` that the request's `path` param names, with the
# guarantees above; a failed 404 otherwise, so `on_error` renders it.
def respond(+dir: String, req: Http.Request) -> IO(Http.Response):
  +req = req
  +t = target(Http.Request.path(req), Http.Request.param(req, "path"))
  +segs = Text.segments("/" ++ t)
  respond.go(dir, req, t, segs, safe(segs))
