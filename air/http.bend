import Base
import ./text.bend as Text

# HTTP
# ====
#
# The message layer: request limits, methods, status reasons, the parsed
# `Request` with its body framing rules, and the `Response` renderer.
# Nothing here touches a socket.

# Limits
# ------

# Byte caps on a request: the head (request line plus headers), the
# number of header lines, the URL, and the body. Past them the server
# answers 431, 431, 414 or 413 and closes the connection.
type Limits is Data:
  Limits{head: U32, headers: U32, url: U32, body: U32}

def Limits.default() -> Limits:
  Limits{16384, 100, 8192, 1048576}

def Limits.head(l: Limits) -> U32:
  match l:
    case Limits{a, b, c, d}:
      a

def Limits.headers(l: Limits) -> U32:
  match l:
    case Limits{a, b, c, d}:
      b

def Limits.url(l: Limits) -> U32:
  match l:
    case Limits{a, b, c, d}:
      c

def Limits.body(l: Limits) -> U32:
  match l:
    case Limits{a, b, c, d}:
      d

# Method
# ------

type Method is Data:
  GET{}
  POST{}
  PUT{}
  DELETE{}
  PATCH{}
  HEAD{}
  OPTIONS{}
  Other{name: String}

def Method.parse(+s: String) -> Method:
  match s:
    case SCon{'G', SCon{'E', SCon{'T', SNil{}}}}:
      GET{}
    case SCon{'P', SCon{'O', SCon{'S', SCon{'T', SNil{}}}}}:
      POST{}
    case SCon{'P', SCon{'U', SCon{'T', SNil{}}}}:
      PUT{}
    case SCon{'D', SCon{'E', SCon{'L', SCon{'E', SCon{'T', SCon{'E', SNil{}}}}}}}:
      DELETE{}
    case SCon{'P', SCon{'A', SCon{'T', SCon{'C', SCon{'H', SNil{}}}}}}:
      PATCH{}
    case SCon{'H', SCon{'E', SCon{'A', SCon{'D', SNil{}}}}}:
      HEAD{}
    case SCon{'O', SCon{'P', SCon{'T', SCon{'I', SCon{'O', SCon{'N', SCon{'S', SNil{}}}}}}}}:
      OPTIONS{}
    case _:
      Other{s}

def Method.show(m: Method) -> String:
  match m:
    case GET{}:
      "GET"
    case POST{}:
      "POST"
    case PUT{}:
      "PUT"
    case DELETE{}:
      "DELETE"
    case PATCH{}:
      "PATCH"
    case HEAD{}:
      "HEAD"
    case OPTIONS{}:
      "OPTIONS"
    case Other{n}:
      n

def Method.is_eq(a: Method, b: Method) -> Bool:
  String.eq(Method.show(a), Method.show(b))

# Request
# -------

type Request is Data:
  Request{
    method: Method,
    version: String,
    target: String,
    path: String,
    query: Map<&2, String>,
    headers: Map<&2, String>,
    params: Map<&2, String>,
    body: String
  }

def Request.method(r: Request) -> Method:
  match r:
    case Request{m, v, tg, p, q, h, ps, b}:
      m

# "HTTP/1.1" or "HTTP/1.0", as the request line said.
def Request.version(r: Request) -> String:
  match r:
    case Request{m, v, tg, p, q, h, ps, b}:
      v

# The request-target as received: raw path and query, undecoded.
def Request.target(r: Request) -> String:
  match r:
    case Request{m, v, tg, p, q, h, ps, b}:
      tg

# The path in its normal form: percent-decoded, `.` and `..` resolved,
# repeated slashes collapsed, a trailing slash kept. `*` for `OPTIONS *`.
def Request.path(r: Request) -> String:
  match r:
    case Request{m, v, tg, p, q, h, ps, b}:
      p

def Request.body(r: Request) -> String:
  match r:
    case Request{m, v, tg, p, q, h, ps, b}:
      b

# A header by name, case-insensitive; "" when absent. A repeated header
# reads as its values joined with ", ".
def Request.header(r: Request, name: String) -> String:
  match r:
    case Request{m, v, tg, p, q, h, ps, b}:
      Text.map_get(h, String.to_lower(name), SNil{})

# A query-string value; "" when absent.
def Request.query(r: Request, key: String) -> String:
  match r:
    case Request{m, v, tg, p, q, h, ps, b}:
      Text.map_get(q, key, SNil{})

# A path parameter bound by the route, like `:id`; "" when absent.
def Request.param(r: Request, key: String) -> String:
  match r:
    case Request{m, v, tg, p, q, h, ps, b}:
      Text.map_get(ps, key, SNil{})

def Request.with_params(r: Request, params: Map<&2, String>) -> Request:
  match r:
    case Request{m, v, tg, p, q, h, ps, b}:
      Request{m, v, tg, p, q, h, params, b}

def Request.with_body(r: Request, body: String) -> Request:
  match r:
    case Request{m, v, tg, p, q, h, ps, b}:
      Request{m, v, tg, p, q, h, ps, body}

def Request.joined(old: String, v: String) -> String:
  match old:
    case SNil{}:
      v
    case SCon{h, t}:
      Text.append(SCon{h, t}, ", " ++ v)

def Request.merge_header(r: Map<&2, String> & String, key: String, v: String) -> Map<&2, String>:
  (m, old) = r
  Map.set(&2, String, m, key, Request.joined(old, v))

def Request.add_header(m: Map<&2, String>, +key: String, v: String) -> Maybe<&2, Map<&2, String>>:
  match key:
    case SNil{}:
      None{}
    case SCon{h, t}:
      Some{Request.merge_header(Map.get(String, SNil{}, m, key), key, v)}

# A header line is `name: value`. Blank lines are skipped; a line that
# starts with whitespace (obsolete folding) or has no colon is refused.
def Request.header_line.fin(m: Map<&2, String>, blank: Bool, folded: Bool, split: Maybe<&2, Text.Two()>) -> Maybe<&2, Map<&2, String>>:
  match blank folded split:
    case True{} _ _:
      Some{m}
    case False{} True{} _:
      None{}
    case False{} False{} None{}:
      None{}
    case False{} False{} Some{kv}:
      (k, v) = kv
      Request.add_header(m, String.to_lower(String.trim(k)), String.trim(v))

def Request.header_line(m: Map<&2, String>, +line: String) -> Maybe<&2, Map<&2, String>>:
  Request.header_line.fin(
    m,
    String.is_empty(String.trim(line)),
    Bool.or(Text.head_is(line, ' '), Text.head_is(line, '\t')),
    Text.split_str(line, ":"))

def Request.parse_headers(lines: List<&2, String>, m: Maybe<&2, Map<&2, String>>) -> Maybe<&2, Map<&2, String>>:
  match lines m:
    case _ None{}:
      None{}
    case Nil{} Some{m2}:
      Some{m2}
    case Con{h, t} Some{m2}:
      Request.parse_headers(t, Request.header_line(m2, h))

def Request.set_decoded(m: Map<&2, String>, k: Maybe<&2, String>, v: Maybe<&2, String>) -> Maybe<&2, Map<&2, String>>:
  match k v:
    case Some{k2} Some{v2}:
      Some{Map.set(&2, String, m, k2, v2)}
    case _ _:
      None{}

# A query pair is `key=value`, both percent-decoded with '+' as space;
# a bad escape in either refuses the request.
def Request.add_query(m: Map<&2, String>, skip: Bool, kv: Text.Two()) -> Maybe<&2, Map<&2, String>>:
  match skip:
    case True{}:
      Some{m}
    case False{}:
      (k, v) = kv
      Request.set_decoded(m, Text.percent_decode(k, True{}), Text.percent_decode(v, True{}))

def Request.parse_query(parts: List<&2, String>, m: Maybe<&2, Map<&2, String>>) -> Maybe<&2, Map<&2, String>>:
  match parts m:
    case _ None{}:
      None{}
    case Nil{} Some{m2}:
      Some{m2}
    case Con{+h, t} Some{m2}:
      Request.parse_query(t, Request.add_query(m2, String.is_empty(h), Text.split_at(h, '=')))

# Path
# ----
#
# The path a route sees is the request-target's path in one normal form:
# an absolute-form target loses its scheme and authority, each segment
# is percent-decoded (after the split, so `%2F` stays inside its
# segment), `.` and `..` are resolved, and empty segments are dropped. A
# trailing slash is kept for the router's slash policy. A bad escape, an
# escaped NUL, or a `..` above the root refuses the request.

def Request.after_authority(rest: String) -> String:
  "/" ++ Text.snd(Text.split_at(rest, '/'))

def Request.strip_origin.pick(+target: String, http: Bool, https: Bool) -> String:
  match http https:
    case True{} _:
      Request.after_authority(String.drop(target, 7n))
    case False{} True{}:
      Request.after_authority(String.drop(target, 8n))
    case False{} False{}:
      target

# "http://host/x" and "https://host/x" become "/x"; anything else is
# returned as is.
def Request.strip_origin(+target: String) -> String:
  Request.strip_origin.pick(target,
    String.starts_with(String.to_lower(String.take(target, 7n)), "http://"),
    String.starts_with(String.to_lower(String.take(target, 8n)), "https://"))

def Request.push_decoded(acc: List<&2, String>, d: Maybe<&2, String>) -> Maybe<&2, List<&2, String>>:
  match d:
    case None{}:
      None{}
    case Some{s}:
      Some{Con{s, acc}}

def Request.decode_segments(segs: List<&2, String>, acc: Maybe<&2, List<&2, String>>) -> Maybe<&2, List<&2, String>>:
  match segs acc:
    case _ None{}:
      None{}
    case Nil{} Some{a}:
      Some{List.reverse(&2, String, a)}
    case Con{h, t} Some{a}:
      Request.decode_segments(t, Request.push_decoded(a, Text.percent_decode(h, False{})))

def Request.pop_segment(acc: List<&2, String>) -> Maybe<&2, List<&2, String>>:
  match acc:
    case Nil{}:
      None{}
    case Con{h, t}:
      Some{t}

# `.` is dropped, `..` pops the segment before it, and `..` at the root
# is refused.
def Request.step_dot(acc: List<&2, String>, +seg: String) -> Maybe<&2, List<&2, String>>:
  match seg:
    case SCon{'.', SNil{}}:
      Some{acc}
    case SCon{'.', SCon{'.', SNil{}}}:
      Request.pop_segment(acc)
    case _:
      Some{Con{seg, acc}}

def Request.resolve_dots.go(segs: List<&2, String>, acc: Maybe<&2, List<&2, String>>) -> Maybe<&2, List<&2, String>>:
  match segs acc:
    case _ None{}:
      None{}
    case Nil{} Some{a}:
      Some{List.reverse(&2, String, a)}
    case Con{+h, t} Some{a}:
      Request.resolve_dots.go(t, Request.step_dot(a, h))

def Request.resolve_dots(segs: Maybe<&2, List<&2, String>>) -> Maybe<&2, List<&2, String>>:
  match segs:
    case None{}:
      None{}
    case Some{s}:
      Request.resolve_dots.go(s, Some{Nil{}})

# Builds the path reversed, so each segment is prepended in constant
# time; `render_path.fin` turns it around.
def Request.render_path.go(segs: List<&2, String>, rev: String) -> String:
  match segs:
    case Nil{}:
      rev
    case Con{h, t}:
      Request.render_path.go(t, Text.rev_onto("/" ++ h, rev))

def Request.render_path.fin(rev: String, trailing: Bool) -> String:
  match trailing:
    case True{}:
      String.reverse(SCon{'/', rev})
    case False{}:
      String.reverse(rev)

def Request.render_path(segs: List<&2, String>, trailing: Bool) -> String:
  match segs:
    case Nil{}:
      "/"
    case Con{h, t}:
      Request.render_path.fin(Request.render_path.go(Con{h, t}, SNil{}), trailing)

def Request.normalize.fin(resolved: Maybe<&2, List<&2, String>>, trailing: Bool) -> Maybe<&2, String>:
  match resolved:
    case None{}:
      None{}
    case Some{segs}:
      Some{Request.render_path(segs, trailing)}

def Request.normalize.go(+path: String) -> Maybe<&2, String>:
  Request.normalize.fin(
    Request.resolve_dots(Request.decode_segments(Text.segments(path), Some{Nil{}})),
    Text.last_is(path, '/'))

# The normal form of a raw path, or None when it must be refused.
def Request.normalize(+raw: String) -> Maybe<&2, String>:
  match raw:
    case SCon{'*', SNil{}}:
      Some{"*"}
    case _:
      Request.normalize.go(Request.strip_origin(raw))

# A parsed head, or the status that refuses it.
type Parsed is Data:
  Parsed{req: Request}
  Refused{status: U32}

# The refusals in order: 414 for the URL, 505 for the version, 431 for
# the header count, 400 for a bad header, path or query.
def Request.parse.fin(method: String, version: String, target: String, url_ok: Bool, version_ok: Bool, count_ok: Bool, headers: Maybe<&2, Map<&2, String>>, path: Maybe<&2, String>, query: Maybe<&2, Map<&2, String>>) -> Parsed:
  match url_ok version_ok count_ok headers path query:
    case False{} _ _ _ _ _:
      Refused{414}
    case True{} False{} _ _ _ _:
      Refused{505}
    case True{} True{} False{} _ _ _:
      Refused{431}
    case True{} True{} True{} None{} _ _:
      Refused{400}
    case True{} True{} True{} Some{h} None{} _:
      Refused{400}
    case True{} True{} True{} Some{h} Some{p} None{}:
      Refused{400}
    case True{} True{} True{} Some{h} Some{p} Some{q}:
      Parsed{Request{
        Method.parse(method),
        version,
        target,
        p,
        q,
        h,
        Map.new(&2, String),
        SNil{}
      }}

# Splits the target once into path and query, then normalizes each.
def Request.parse.url(method: String, version: String, target: String, url_ok: Bool, version_ok: Bool, count_ok: Bool, headers: Maybe<&2, Map<&2, String>>, pq: Text.Two()) -> Parsed:
  (path, qs) = pq
  Request.parse.fin(
    method,
    version,
    target,
    url_ok,
    version_ok,
    count_ok,
    headers,
    Request.normalize(path),
    Request.parse_query(Text.split_all(qs, '&'), Some{Map.new(&2, String)}))

def Request.parse.line(+limits: Limits, parts: List<&2, String>, +lines: List<&2, String>) -> Parsed:
  match parts:
    case Con{method, Con{+target, Con{+version, Nil{}}}}:
      Request.parse.url(
        method,
        version,
        target,
        U32.is_le(Text.byte_length(target, 0), Limits.url(limits)),
        String.starts_with(version, "HTTP/1."),
        U32.is_le(Text.count(lines, 0), Limits.headers(limits)),
        Request.parse_headers(lines, Some{Map.new(&2, String)}),
        Text.split_at(target, '?'))
    case _:
      Refused{400}

def Request.parse.go(+limits: Limits, lr: Text.Two()) -> Parsed:
  (line, rest) = lr
  Request.parse.line(limits, Text.split_all(String.trim(line), ' '), Text.split_all(rest, '\n'))

# Parses the request head (everything before the blank line) under the
# limits. The body is attached later with `Request.with_body`.
def Request.parse(+limits: Limits, head: String) -> Parsed:
  Request.parse.go(limits, Text.split_at(head, '\n'))

# How the body is delimited, decided from the head alone.
type Framing is Data:
  NoBody{}
  Fixed{size: U32}
  Chunked{}
  Unframed{status: U32}

def Framing.readable(f: Framing, +max: U32) -> Bool:
  match f:
    case NoBody{}:
      False{}
    case Fixed{n}:
      U32.is_le(n, max)
    case Chunked{}:
      True{}
    case Unframed{status}:
      False{}

def Request.framing.fixed(n: Maybe<&2, U32>) -> Framing:
  match n:
    case None{}:
      Unframed{400}
    case Some{+k}:
      Bool.pick(Framing, U32.is_eq(k, 0), NoBody{}, Fixed{k})

# Content-Length and Transfer-Encoding together, a repeated or
# non-numeric Content-Length, and any encoding but `chunked` are refused.
def Request.framing.pick(+te: String, +cl: String) -> Framing:
  match te cl:
    case SNil{} SNil{}:
      NoBody{}
    case SNil{} SCon{h, t}:
      Request.framing.fixed(Text.digits(cl))
    case SCon{h, t} SNil{}:
      Bool.pick(Framing, String.eq(String.to_lower(te), "chunked"), Chunked{}, Unframed{501})
    case SCon{a, b} SCon{c, d}:
      Unframed{400}

def Request.framing(+req: Request) -> Framing:
  Request.framing.pick(Request.header(req, "transfer-encoding"), Request.header(req, "content-length"))

def Request.keep_alive.pick(conn: String, http10: Bool) -> Bool:
  match http10:
    case True{}:
      Text.has_token(conn, "keep-alive")
    case False{}:
      Bool.not(Text.has_token(conn, "close"))

# HTTP/1.1 keeps the connection unless asked to close; HTTP/1.0 closes
# unless asked to keep it.
def Request.keep_alive(+req: Request) -> Bool:
  Request.keep_alive.pick(Request.header(req, "connection"), String.eq(Request.version(req), "HTTP/1.0"))

def Request.expects_continue(+req: Request) -> Bool:
  String.eq(String.to_lower(Request.header(req, "expect")), "100-continue")

def Parsed.framing(p: Parsed) -> Framing:
  match p:
    case Parsed{req}:
      Request.framing(req)
    case Refused{status}:
      Unframed{status}

def Parsed.keep_alive(p: Parsed) -> Bool:
  match p:
    case Parsed{req}:
      Request.keep_alive(req)
    case Refused{status}:
      False{}

def Parsed.path(p: Parsed) -> String:
  match p:
    case Parsed{req}:
      Request.path(req)
    case Refused{status}:
      SNil{}

def Parsed.query(p: Parsed, key: String) -> String:
  match p:
    case Parsed{req}:
      Request.query(req, key)
    case Refused{status}:
      SNil{}

# Response
# --------

type Response is Data:
  Response{status: U32, headers: Map<&2, String>, body: String}

def Response.new(status: U32, body: String) -> Response:
  Response{status, Map.new(&2, String), body}

def Response.status(r: Response) -> U32:
  match r:
    case Response{s, h, b}:
      s

def Response.body(r: Response) -> String:
  match r:
    case Response{s, h, b}:
      b

def Response.header(r: Response, name: String) -> String:
  match r:
    case Response{s, h, b}:
      Text.map_get(h, String.to_lower(name), SNil{})

def Response.with_status(r: Response, status: U32) -> Response:
  match r:
    case Response{s, h, b}:
      Response{status, h, b}

def Response.with_header(r: Response, name: String, value: String) -> Response:
  match r:
    case Response{s, h, b}:
      Response{s, Map.set(&2, String, h, String.to_lower(name), value), b}

def Response.empty(status: U32) -> Response:
  Response.new(status, SNil{})

def Response.text(body: String) -> Response:
  Response.with_header(Response.new(200, body), "content-type", "text/plain; charset=utf-8")

def Response.html(body: String) -> Response:
  Response.with_header(Response.new(200, body), "content-type", "text/html; charset=utf-8")

def Response.json(body: String) -> Response:
  Response.with_header(Response.new(200, body), "content-type", "application/json")

def Response.redirect(url: String) -> Response:
  Response.with_header(Response.empty(302), "location", url)

def Response.not_found() -> Response:
  Response.with_status(Response.text("Not Found"), 404)

# A 405 must say what would have worked: `allow` is "GET, HEAD, OPTIONS".
def Response.method_not_allowed(allow: String) -> Response:
  Response.with_header(Response.with_status(Response.text("Method Not Allowed"), 405), "allow", allow)

# The answer to an OPTIONS request no route claims: 204 with `Allow`.
def Response.options(allow: String) -> Response:
  Response.with_header(Response.empty(204), "allow", allow)

def Response.bad_request() -> Response:
  Response.with_status(Response.text("Bad Request"), 400)

def Status.reasons() -> Map<&2, String>:
  m = Map.new(&2, String)
  m = Map.set(&2, String, m, "100", "Continue")
  m = Map.set(&2, String, m, "200", "OK")
  m = Map.set(&2, String, m, "201", "Created")
  m = Map.set(&2, String, m, "202", "Accepted")
  m = Map.set(&2, String, m, "204", "No Content")
  m = Map.set(&2, String, m, "301", "Moved Permanently")
  m = Map.set(&2, String, m, "302", "Found")
  m = Map.set(&2, String, m, "304", "Not Modified")
  m = Map.set(&2, String, m, "308", "Permanent Redirect")
  m = Map.set(&2, String, m, "400", "Bad Request")
  m = Map.set(&2, String, m, "401", "Unauthorized")
  m = Map.set(&2, String, m, "403", "Forbidden")
  m = Map.set(&2, String, m, "404", "Not Found")
  m = Map.set(&2, String, m, "405", "Method Not Allowed")
  m = Map.set(&2, String, m, "408", "Request Timeout")
  m = Map.set(&2, String, m, "409", "Conflict")
  m = Map.set(&2, String, m, "411", "Length Required")
  m = Map.set(&2, String, m, "413", "Content Too Large")
  m = Map.set(&2, String, m, "414", "URI Too Long")
  m = Map.set(&2, String, m, "417", "Expectation Failed")
  m = Map.set(&2, String, m, "422", "Unprocessable Content")
  m = Map.set(&2, String, m, "429", "Too Many Requests")
  m = Map.set(&2, String, m, "431", "Request Header Fields Too Large")
  m = Map.set(&2, String, m, "500", "Internal Server Error")
  m = Map.set(&2, String, m, "501", "Not Implemented")
  m = Map.set(&2, String, m, "503", "Service Unavailable")
  m = Map.set(&2, String, m, "505", "HTTP Version Not Supported")
  m

def Status.reason(code: U32) -> String:
  Text.map_get(Status.reasons(), U32.show(code), "Unknown")

# 1xx, 204 and 304 responses never carry a body.
def Response.no_body(+status: U32) -> Bool:
  Bool.or(U32.is_lt(status, 200), Bool.or(U32.is_eq(status, 204), U32.is_eq(status, 304)))

def Response.render_header(kv: Text.Two()) -> String:
  (k, v) = kv
  k ++ ": " ++ v ++ "\r\n"

def Response.render_headers(kvs: List<&2, Text.Two()>, acc: String) -> String:
  match kvs:
    case Nil{}:
      acc
    case Con{kv, t}:
      Response.render_headers(t, acc ++ Response.render_header(kv))

def Response.render_body(body: String, omit: Bool) -> String:
  match omit:
    case True{}:
      SNil{}
    case False{}:
      body

# 1xx and 204 have no Content-Length; 304 and HEAD keep the one the full
# response would have had.
def Response.render_length(+n: U32, +status: U32) -> String:
  Bool.pick(String, Bool.or(U32.is_lt(status, 200), U32.is_eq(status, 204)),
    SNil{},
    "content-length: " ++ U32.show(n) ++ "\r\n")

# The wire form of a response. `head_only` drops the body, for HEAD
# requests. `keep` picks the Connection header.
def Response.render(r: Response, head_only: Bool, +keep: Bool) -> String:
  match r:
    case Response{+status, headers, +body}:
      "HTTP/1.1 " ++ U32.show(status) ++ " " ++ Status.reason(status) ++ "\r\n"
        ++ Response.render_headers(
             Map.to_list(&2, String,
               Map.set(&2, String, headers, "connection", Bool.pick(String, keep, "keep-alive", "close"))),
             SNil{})
        ++ Response.render_length(Text.byte_length(body, 0), status)
        ++ "\r\n"
        ++ Response.render_body(body, Bool.or(head_only, Response.no_body(status)))

# A full response that closes its connection.
def Response.serialize(r: Response) -> String:
  Response.render(r, False{}, False{})

