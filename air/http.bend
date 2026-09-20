import Base
import ./text.bend as Text
import ./json.bend as Json
import ./negotiate.bend as Negotiate

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

# The content type's media type: lowercased, without parameters.
def Request.media_type(r: Request) -> String:
  String.trim(String.to_lower(Text.fst(Text.split_at(Request.header(r, "content-type"), ';'))))

def Request.is_json(+mt: String) -> Bool:
  Bool.or(String.eq(mt, "application/json"), String.ends_with(mt, "+json"))

def Request.json.pick(body: String, json: Bool) -> Maybe<&2, Json.Value>:
  match json:
    case True{}:
      Json.parse(body)
    case False{}:
      None{}

# The body as JSON, when the content type says so and it parses.
def Request.json(+r: Request) -> Maybe<&2, Json.Value>:
  Request.json.pick(Request.body(r), Request.is_json(Request.media_type(r)))

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

# Forms
# -----
#
# Query strings and urlencoded bodies are flat: `a[b]=1` is a key named
# `a[b]`, and a repeated key keeps its last value in the map. `query_all`
# and `form_all` walk the raw pairs for every value of a key, in order.

def Request.same_key(k: Maybe<&2, String>, +key: String) -> Bool:
  match k:
    case None{}:
      False{}
    case Some{s}:
      String.eq(s, key)

def Request.collect.push(acc: List<&2, String>, v: Maybe<&2, String>, same: Bool) -> List<&2, String>:
  match v same:
    case Some{s} True{}:
      Con{s, acc}
    case _ _:
      acc

def Request.collect.add(acc: List<&2, String>, +key: String, kv: Text.Two()) -> List<&2, String>:
  (k, v) = kv
  Request.collect.push(acc, Text.percent_decode(v, True{}), Request.same_key(Text.percent_decode(k, True{}), key))

# Every decoded value of `key` among `k=v` pairs, in order; a pair that
# does not decode is skipped.
def Request.collect(parts: List<&2, String>, +key: String, acc: List<&2, String>) -> List<&2, String>:
  match parts:
    case Nil{}:
      List.reverse(&2, String, acc)
    case Con{+h, t}:
      Request.collect(t, key, Request.collect.add(acc, key, Text.split_at(h, '=')))

def Request.query_all(r: Request, key: String) -> List<&2, String>:
  Request.collect(Text.split_all(Text.snd(Text.split_at(Request.target(r), '?')), '&'), key, Nil{})

def Request.is_form(+mt: String) -> Bool:
  String.eq(mt, "application/x-www-form-urlencoded")

def Request.form.fin(m: Maybe<&2, Map<&2, String>>, key: String) -> String:
  match m:
    case None{}:
      SNil{}
    case Some{m2}:
      Text.map_get(m2, key, SNil{})

def Request.form.pick(body: String, key: String, form: Bool) -> String:
  match form:
    case True{}:
      Request.form.fin(Request.parse_query(Text.split_all(body, '&'), Some{Map.new(&2, String)}), key)
    case False{}:
      SNil{}

# A field of an `application/x-www-form-urlencoded` body; "" when the
# body is not one, the key is absent, or an escape is bad.
def Request.form(+r: Request, key: String) -> String:
  Request.form.pick(Request.body(r), key, Request.is_form(Request.media_type(r)))

def Request.form_all.pick(body: String, key: String, form: Bool) -> List<&2, String>:
  match form:
    case True{}:
      Request.collect(Text.split_all(body, '&'), key, Nil{})
    case False{}:
      Nil{}

def Request.form_all(+r: Request, key: String) -> List<&2, String>:
  Request.form_all.pick(Request.body(r), key, Request.is_form(Request.media_type(r)))

# Cookies
# -------

def Request.cookie_pair(+piece: String) -> Text.Two():
  (String.trim(Text.fst(Text.split_at(String.trim(piece), '='))), String.trim(Text.snd(Text.split_at(String.trim(piece), '='))))

def Request.push_cookie.pick(acc: List<&2, Text.Two()>, +k: String, v: String) -> List<&2, Text.Two()>:
  match k:
    case SNil{}:
      acc
    case SCon{h, t}:
      Con{(k, v), acc}

def Request.push_cookie(acc: List<&2, Text.Two()>, kv: Text.Two()) -> List<&2, Text.Two()>:
  (k, v) = kv
  Request.push_cookie.pick(acc, k, v)

def Request.cookies.go(pieces: List<&2, String>, acc: List<&2, Text.Two()>) -> List<&2, Text.Two()>:
  match pieces:
    case Nil{}:
      List.reverse(&2, Text.Two(), acc)
    case Con{h, t}:
      Request.cookies.go(t, Request.push_cookie(acc, Request.cookie_pair(h)))

# The cookies sent, as (name, value) pairs in order. Values are as
# sent: RFC 6265 leaves their encoding to the app.
def Request.cookies(r: Request) -> List<&2, Text.Two()>:
  Request.cookies.go(Text.split_all(Request.header(r, "cookie"), ';'), Nil{})

def Request.cookie.pick(v: String, same: Bool) -> Maybe<&2, String>:
  match same:
    case True{}:
      Some{v}
    case False{}:
      None{}

def Request.cookie.try(kv: Text.Two(), +name: String) -> Maybe<&2, String>:
  (k, v) = kv
  Request.cookie.pick(v, String.eq(k, name))

def Request.cookie.go(pairs: List<&2, Text.Two()>, +name: String, found: Maybe<&2, String>) -> String:
  match pairs found:
    case _ Some{v}:
      v
    case Nil{} None{}:
      SNil{}
    case Con{kv, t} None{}:
      Request.cookie.go(t, name, Request.cookie.try(kv, name))

# The first cookie named `name`; "" when absent.
def Request.cookie(r: Request, name: String) -> String:
  Request.cookie.go(Request.cookies(r), name, None{})

# Negotiation
# -----------

# The offer the client's Accept header prefers, or None; see
# `Negotiate.pick`. An absent header takes the first offer.
def Request.accepts(r: Request, offers: List<&2, String>) -> Maybe<&2, String>:
  Negotiate.pick(Request.header(r, "accept"), offers, False{})

def Request.accepts_encoding(r: Request, offers: List<&2, String>) -> Maybe<&2, String>:
  Negotiate.pick(Request.header(r, "accept-encoding"), offers, False{})

# With the language prefix rule: `en` accepts `en-us`.
def Request.accepts_language(r: Request, offers: List<&2, String>) -> Maybe<&2, String>:
  Negotiate.pick(Request.header(r, "accept-language"), offers, True{})

# Behind a proxy
# --------------
#
# `TCP.accept` hands back the socket alone, so Air never learns the
# peer address. The client's address, host and scheme are known only
# when a proxy the app trusts forwards them, and trust is off by
# default: with `NoProxy` every forwarding header is ignored.

type Trust is Data:
  NoProxy{}
  Proxy{}

def Request.last.go(xs: List<&2, String>, last: String) -> String:
  match xs:
    case Nil{}:
      last
    case Con{h, t}:
      Request.last.go(t, h)

# The last non-empty comma-separated entry, trimmed; the rightmost one
# is what the trusted proxy appended.
def Request.last_entry(v: String) -> String:
  String.trim(Request.last.go(Text.split_all(v, ','), SNil{}))

def Request.first_entry(v: String) -> String:
  String.trim(Text.fst(Text.split_at(v, ',')))

def Request.unquote.tail(+s: String) -> String:
  match s:
    case SCon{'"', t}:
      t
    case _:
      s

def Request.unquote(v: String) -> String:
  String.reverse(Request.unquote.tail(String.reverse(Request.unquote.tail(v))))

# A `for=` node: `"[2001:db8::1]:8080"` is `2001:db8::1`, `1.2.3.4:80`
# is `1.2.3.4`.
def Request.node(+v: String) -> String:
  match v:
    case SCon{'[', t}:
      Text.fst(Text.split_at(t, ']'))
    case _:
      Text.fst(Text.split_at(v, ':'))

def Request.pair_value.pick(v: String, same: Bool, +found: String) -> String:
  match same:
    case True{}:
      v
    case False{}:
      found

def Request.pair_value.try(+found: String, +name: String, kv: Text.Two()) -> String:
  (k, v) = kv
  Request.pair_value.pick(Request.unquote(String.trim(v)), String.eq(String.to_lower(String.trim(k)), name), found)

# The value of `name=` among `;`-separated pairs, the last one winning.
def Request.pair_value(pairs: List<&2, String>, +name: String, +found: String) -> String:
  match pairs:
    case Nil{}:
      found
    case Con{+h, t}:
      Request.pair_value(t, name, Request.pair_value.try(found, name, Text.split_at(h, '=')))

# The `name=` value of the last element of a `Forwarded` header, "" when
# absent: `for=1.1.1.1, for=2.2.2.2;proto=https` gives 2.2.2.2 for `for`.
def Request.forwarded(r: Request, +name: String) -> String:
  Request.pair_value(Text.split_all(Request.last_entry(Request.header(r, "forwarded")), ';'), name, SNil{})

def Request.or_else(+a: String, b: String) -> String:
  match a:
    case SNil{}:
      b
    case SCon{h, t}:
      a

def Request.some_if(+v: String) -> Maybe<&2, String>:
  match v:
    case SNil{}:
      None{}
    case SCon{h, t}:
      Some{v}

# The client's address as a trusted proxy reports it: the rightmost
# `X-Forwarded-For` entry, else the last `Forwarded` `for=` node; None
# without trust or without either header.
def Request.client_ip(+r: Request, trust: Trust) -> Maybe<&2, String>:
  match trust:
    case NoProxy{}:
      None{}
    case Proxy{}:
      Request.some_if(Request.or_else(Request.last_entry(Request.header(r, "x-forwarded-for")), Request.node(Request.forwarded(r, "for"))))

# The host the client asked for: `X-Forwarded-Host` (first entry), then
# `Forwarded` `host=`, under a trusted proxy; else the `Host` header.
def Request.host(+r: Request, trust: Trust) -> String:
  match trust:
    case NoProxy{}:
      String.trim(Request.header(r, "host"))
    case Proxy{}:
      Request.or_else(Request.first_entry(Request.header(r, "x-forwarded-host")), Request.or_else(Request.forwarded(r, "host"), String.trim(Request.header(r, "host"))))

# "https" when a trusted proxy says so (`X-Forwarded-Proto`, then
# `Forwarded` `proto=`); else "http", since Air itself speaks only that.
def Request.scheme(+r: Request, trust: Trust) -> String:
  match trust:
    case NoProxy{}:
      "http"
    case Proxy{}:
      Request.or_else(String.to_lower(Request.first_entry(Request.header(r, "x-forwarded-proto"))), Request.or_else(String.to_lower(Request.forwarded(r, "proto")), "http"))

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

# A response body: text sent whole, or a channel the server drains as
# chunks until the producer closes it. A `Chan` is Data, so a `Response`
# stays Data.
type Body is Data:
  Whole{text: String}
  Stream{chan: Chan(String)}

# `cookies` are rendered `Set-Cookie` lines, one header each: it is the
# one header that must never be joined with ", ".
type Response is Data:
  Response{status: U32, headers: Map<&2, String>, cookies: List<&2, String>, body: Body}

def Response.new(status: U32, body: String) -> Response:
  Response{status, Map.new(&2, String), Nil{}, Whole{body}}

def Response.status(r: Response) -> U32:
  match r:
    case Response{s, h, c, b}:
      s

def Body.text(b: Body) -> String:
  match b:
    case Whole{text}:
      text
    case Stream{chan}:
      SNil{}

# The body's text; "" for a stream.
def Response.body(r: Response) -> String:
  match r:
    case Response{s, h, c, b}:
      Body.text(b)

# The body itself, for the server to branch on.
def Response.payload(r: Response) -> Body:
  match r:
    case Response{s, h, c, b}:
      b

def Response.header(r: Response, name: String) -> String:
  match r:
    case Response{s, h, c, b}:
      Text.map_get(h, String.to_lower(name), SNil{})

def Response.with_status(r: Response, status: U32) -> Response:
  match r:
    case Response{s, h, c, b}:
      Response{status, h, c, b}

def Response.with_header(r: Response, name: String, value: String) -> Response:
  match r:
    case Response{s, h, c, b}:
      Response{s, Map.set(&2, String, h, String.to_lower(name), value), c, b}

def Response.empty(status: U32) -> Response:
  Response.new(status, SNil{})

def Response.text(body: String) -> Response:
  Response.with_header(Response.new(200, body), "content-type", "text/plain; charset=utf-8")

def Response.html(body: String) -> Response:
  Response.with_header(Response.new(200, body), "content-type", "text/html; charset=utf-8")

def Response.json(body: String) -> Response:
  Response.with_header(Response.new(200, body), "content-type", "application/json")

# A 200 with a JSON value rendered as its body.
def Response.of_json(v: Json.Value) -> Response:
  Response.json(Json.render(v))

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

# Content type
# ------------

# Text types, JSON and JavaScript get `; charset=utf-8` unless the mime
# already carries a parameter.
def Response.textual(+mime: String) -> Bool:
  Bool.and(Bool.not(String.contains(mime, ";")),
    Bool.or(String.starts_with(mime, "text/"),
      Bool.or(String.eq(mime, "application/json"),
        Bool.or(String.eq(mime, "application/javascript"), String.eq(mime, "image/svg+xml")))))

def Response.charset(+mime: String, textual: Bool) -> String:
  match textual:
    case True{}:
      mime ++ "; charset=utf-8"
    case False{}:
      mime

def Response.with_type(r: Response, +mime: String) -> Response:
  Response.with_header(r, "content-type", Response.charset(mime, Response.textual(mime)))

# What a body looks like, from its first non-space character: markup,
# JSON, or plain text.
def Response.infer(body: String) -> String:
  match body:
    case SNil{}:
      "text/plain"
    case SCon{' ', t}:
      Response.infer(t)
    case SCon{'\n', t}:
      Response.infer(t)
    case SCon{'\r', t}:
      Response.infer(t)
    case SCon{'\t', t}:
      Response.infer(t)
    case SCon{'<', t}:
      "text/html"
    case SCon{'{', t}:
      "application/json"
    case SCon{'[', t}:
      "application/json"
    case SCon{h, t}:
      "text/plain"

# A 200 whose content type is inferred from the body. `with_type` after
# it overrides the guess.
def Response.send(+body: String) -> Response:
  Response.with_type(Response.new(200, body), Response.infer(body))

# Redirects
# ---------

def Response.redirect_with(status: U32, url: String) -> Response:
  Response.with_header(Response.empty(status), "location", url)

def Response.moved(url: String) -> Response:
  Response.redirect_with(301, url)

def Response.see_other(url: String) -> Response:
  Response.redirect_with(303, url)

def Response.temporary_redirect(url: String) -> Response:
  Response.redirect_with(307, url)

def Response.permanent_redirect(url: String) -> Response:
  Response.redirect_with(308, url)

# Cookies
# -------

# A cookie to set. `max_age` 0 means a session cookie; `same_site` is
# "Lax", "Strict", "None" or "" for unset. Names and values are emitted
# as given: a `;` in either is the app's bug.
type Cookie is Data:
  Cookie{name: String, value: String, path: String, domain: String, max_age: U32, secure: Bool, http_only: Bool, same_site: String}

# Safe defaults: Path=/, HttpOnly, SameSite=Lax, session, not Secure.
def Cookie.new(name: String, value: String) -> Cookie:
  Cookie{name, value, "/", SNil{}, 0, False{}, True{}, "Lax"}

def Cookie.with_path(c: Cookie, path: String) -> Cookie:
  match c:
    case Cookie{n, v, p, d, m, s, h, ss}:
      Cookie{n, v, path, d, m, s, h, ss}

def Cookie.with_domain(c: Cookie, domain: String) -> Cookie:
  match c:
    case Cookie{n, v, p, d, m, s, h, ss}:
      Cookie{n, v, p, domain, m, s, h, ss}

# Seconds; 0 for a session cookie.
def Cookie.with_max_age(c: Cookie, seconds: U32) -> Cookie:
  match c:
    case Cookie{n, v, p, d, m, s, h, ss}:
      Cookie{n, v, p, d, seconds, s, h, ss}

def Cookie.secure(c: Cookie, on: Bool) -> Cookie:
  match c:
    case Cookie{n, v, p, d, m, s, h, ss}:
      Cookie{n, v, p, d, m, on, h, ss}

def Cookie.http_only(c: Cookie, on: Bool) -> Cookie:
  match c:
    case Cookie{n, v, p, d, m, s, h, ss}:
      Cookie{n, v, p, d, m, s, on, ss}

# "Lax", "Strict", "None" or "". `None` needs `Secure`, or browsers drop
# the cookie, so rendering adds it.
def Cookie.same_site(c: Cookie, mode: String) -> Cookie:
  match c:
    case Cookie{n, v, p, d, m, s, h, ss}:
      Cookie{n, v, p, d, m, s, h, mode}

def Cookie.attr(name: String, +value: String) -> String:
  match value:
    case SNil{}:
      SNil{}
    case SCon{h, t}:
      "; " ++ name ++ "=" ++ value

def Cookie.flag(name: String, on: Bool) -> String:
  match on:
    case True{}:
      "; " ++ name
    case False{}:
      SNil{}

def Cookie.age(+seconds: U32) -> String:
  Bool.pick(String, U32.is_eq(seconds, 0), SNil{}, "; Max-Age=" ++ U32.show(seconds))

def Cookie.render(c: Cookie) -> String:
  match c:
    case Cookie{n, v, p, d, m, s, h, +ss}:
      n ++ "=" ++ v
        ++ Cookie.attr("Path", p)
        ++ Cookie.attr("Domain", d)
        ++ Cookie.age(m)
        ++ Cookie.flag("Secure", Bool.or(s, String.eq(ss, "None")))
        ++ Cookie.flag("HttpOnly", h)
        ++ Cookie.attr("SameSite", ss)

def Response.with_cookie_line(r: Response, line: String) -> Response:
  match r:
    case Response{s, h, c, b}:
      Response{s, h, List.append(&2, String, c, [line]), b}

# Adds a `Set-Cookie` line; several cookies are several lines, in order.
def Response.with_cookie(r: Response, c: Cookie) -> Response:
  Response.with_cookie_line(r, Cookie.render(c))

# Tells the browser to drop a cookie set with the default path.
def Response.expire_cookie(r: Response, name: String) -> Response:
  Response.with_cookie_line(r, name ++ "=; Path=/; Max-Age=0")

# Files
# -----
#
# What a file response needs: a strong ETag from the content, 304 when
# the client already has it, and byte ranges. `Last-Modified` is not
# offered: Bend's `File` has no stat, so the mtime is unknown.

def Response.with_body(r: Response, body: String) -> Response:
  match r:
    case Response{s, h, c, b}:
      Response{s, h, c, Whole{body}}

# A strong ETag: the FNV-1a hash of the body and its byte length.
def etag(+body: String) -> String:
  "\"" ++ Text.hex_show(Text.fnv1a(body, Text.fnv_seed())) ++ "-" ++ U32.show(Text.byte_length(body, 0)) ++ "\""

def Response.with_etag.go(r: Response, +body: String) -> Response:
  Response.with_header(Response.with_header(r, "etag", etag(body)), "accept-ranges", "bytes")

# Tags the response with its body's ETag and offers byte ranges.
def Response.with_etag(+r: Response) -> Response:
  Response.with_etag.go(r, Response.body(r))

def strip_weak(+s: String) -> String:
  match s:
    case SCon{'W', SCon{'/', t}}:
      t
    case _:
      s

def has_tag.go(entries: List<&2, String>, +tag: String, found: Bool) -> Bool:
  match entries found:
    case _ True{}:
      True{}
    case Nil{} False{}:
      False{}
    case Con{+h, t} False{}:
      has_tag.go(t, tag, Bool.or(String.eq(String.trim(h), "*"), String.eq(strip_weak(String.trim(h)), tag)))

# Whether an `If-None-Match` value names `tag` (weak or strong) or `*`.
def has_tag(+inm: String, +tag: String) -> Bool:
  Bool.and(Text.non_empty(String.trim(inm)), has_tag.go(Text.split_all(inm, ','), tag, False{}))

def Request.is_read(+req: Request) -> Bool:
  Bool.or(Method.is_eq(Request.method(req), GET{}), Method.is_eq(Request.method(req), HEAD{}))

def Response.conditional.pick(res: Response, unchanged: Bool) -> Response:
  match unchanged:
    case True{}:
      Response.with_status(res, 304)
    case False{}:
      res

# Turns a tagged 200 into a 304 when the request's `If-None-Match`
# lists its ETag. The body stays, so `content-length` is kept and the
# renderer omits the bytes, as for any 304. Only GET and HEAD qualify.
def Response.conditional(+req: Request, +res: Response) -> Response:
  Response.conditional.pick(res,
    Bool.and(Request.is_read(req),
      Bool.and(U32.is_eq(Response.status(res), 200),
        has_tag(Request.header(req, "if-none-match"), Response.header(res, "etag")))))

# A parsed `Range` header against a body of `len` bytes: no header, one
# satisfiable inclusive range, or a bad one (malformed, multiple, or
# unsatisfiable), which is a 416.
type Range is Data:
  NoRange{}
  Range{first: U32, last: U32}
  BadRange{}

def Range.suffix.pick(+n: U32, +len: U32, bad: Bool) -> Range:
  match bad:
    case True{}:
      BadRange{}
    case False{}:
      Range{U32.sub(len, U32.min(n, len)), U32.sub(len, 1)}

# `bytes=-n`: the last n bytes.
def Range.suffix(n: Maybe<&2, U32>, +len: U32) -> Range:
  match n:
    case None{}:
      BadRange{}
    case Some{+k}:
      Range.suffix.pick(k, len, Bool.or(U32.is_eq(k, 0), U32.is_eq(len, 0)))

def Range.from.pick(+f: U32, +len: U32, bad: Bool) -> Range:
  match bad:
    case True{}:
      BadRange{}
    case False{}:
      Range{f, U32.sub(len, 1)}

# `bytes=f-`: from f to the end.
def Range.from(f: Maybe<&2, U32>, +len: U32) -> Range:
  match f:
    case None{}:
      BadRange{}
    case Some{+k}:
      Range.from.pick(k, len, U32.is_ge(k, len))

def Range.both.pick(+f: U32, +l: U32, +len: U32, bad: Bool) -> Range:
  match bad:
    case True{}:
      BadRange{}
    case False{}:
      Range{f, U32.min(l, U32.sub(len, 1))}

# `bytes=f-l`, `l` clamped to the end.
def Range.both(f: Maybe<&2, U32>, l: Maybe<&2, U32>, +len: U32) -> Range:
  match f l:
    case Some{+a} Some{+b}:
      Range.both.pick(a, b, len, Bool.or(U32.is_gt(a, b), U32.is_ge(a, len)))
    case _ _:
      BadRange{}

def Range.of(+a: String, +b: String, +len: U32) -> Range:
  match a b:
    case SNil{} SNil{}:
      BadRange{}
    case SNil{} SCon{h, t}:
      Range.suffix(Text.digits(b), len)
    case SCon{h, t} SNil{}:
      Range.from(Text.digits(a), len)
    case SCon{h, t} SCon{h2, t2}:
      Range.both(Text.digits(a), Text.digits(b), len)

def Range.spec(+spec: String, +len: U32, multiple: Bool) -> Range:
  match multiple:
    case True{}:
      BadRange{}
    case False{}:
      Range.of(Text.fst(Text.split_at(spec, '-')), Text.snd(Text.split_at(spec, '-')), len)

def Range.parse.go(+h: String, +len: U32, bytes: Bool) -> Range:
  match bytes:
    case True{}:
      Range.spec(String.drop(h, 6n), len, String.contains(h, ","))
    case False{}:
      BadRange{}

# `bytes=a-b`, `bytes=a-` or `bytes=-n`; "" is no range; anything else,
# several ranges, or one past the end is bad.
def Range.parse(+h: String, +len: U32) -> Range:
  match h:
    case SNil{}:
      NoRange{}
    case _:
      Range.parse.go(h, len, String.starts_with(h, "bytes="))

def slice.second(t: Text.Take) -> Maybe<&2, String>:
  match t:
    case Text.Took{part, rest}:
      Some{part}
    case _:
      None{}

def slice.first(t: Text.Take, +count: U32) -> Maybe<&2, String>:
  match t:
    case Text.Took{head, rest}:
      slice.second(Text.take_bytes(rest, count))
    case _:
      None{}

# Bytes `first` through `last` of `body`; None when an end falls inside
# a character, since bodies are text.
def slice(body: String, +first: U32, +last: U32) -> Maybe<&2, String>:
  slice.first(Text.take_bytes(body, first), U32.add(U32.sub(last, first), 1))

def Response.unsatisfiable(+len: U32) -> Response:
  Response.with_header(Response.empty(416), "content-range", "bytes */" ++ U32.show(len))

def Response.partial(res: Response, +first: U32, +last: U32, +len: U32, part: Maybe<&2, String>) -> Response:
  match part:
    case None{}:
      Response.unsatisfiable(len)
    case Some{p}:
      Response.with_header(Response.with_status(Response.with_body(res, p), 206), "content-range",
        "bytes " ++ U32.show(first) ++ "-" ++ U32.show(last) ++ "/" ++ U32.show(len))

def Response.ranged.pick(+res: Response, r: Range, +len: U32) -> Response:
  match r:
    case NoRange{}:
      res
    case BadRange{}:
      Response.unsatisfiable(len)
    case Range{+first, +last}:
      Response.partial(res, first, last, len, slice(Response.body(res), first, last))

def Response.ranged.go(+req: Request, +res: Response, +len: U32, applies: Bool) -> Response:
  match applies:
    case True{}:
      Response.ranged.pick(res, Range.parse(Request.header(req, "range"), len), len)
    case False{}:
      res

# Answers a `Range` request on a 200 with a 206 slice, or 416 when the
# range is bad or an end splits a character. Other statuses and other
# methods than GET and HEAD pass through.
def Response.ranged(+req: Request, +res: Response) -> Response:
  Response.ranged.go(req, res, Text.byte_length(Response.body(res), 0),
    Bool.and(Request.is_read(req), U32.is_eq(Response.status(res), 200)))

def Status.reasons() -> Map<&2, String>:
  m = Map.new(&2, String)
  m = Map.set(&2, String, m, "100", "Continue")
  m = Map.set(&2, String, m, "200", "OK")
  m = Map.set(&2, String, m, "201", "Created")
  m = Map.set(&2, String, m, "202", "Accepted")
  m = Map.set(&2, String, m, "204", "No Content")
  m = Map.set(&2, String, m, "206", "Partial Content")
  m = Map.set(&2, String, m, "301", "Moved Permanently")
  m = Map.set(&2, String, m, "302", "Found")
  m = Map.set(&2, String, m, "303", "See Other")
  m = Map.set(&2, String, m, "304", "Not Modified")
  m = Map.set(&2, String, m, "307", "Temporary Redirect")
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
  m = Map.set(&2, String, m, "416", "Range Not Satisfiable")
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

def Response.render_cookies(lines: List<&2, String>, acc: String) -> String:
  match lines:
    case Nil{}:
      acc
    case Con{line, t}:
      Response.render_cookies(t, acc ++ "set-cookie: " ++ line ++ "\r\n")

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

def Response.render_start(+status: U32, headers: Map<&2, String>, cookies: List<&2, String>, +keep: Bool) -> String:
  "HTTP/1.1 " ++ U32.show(status) ++ " " ++ Status.reason(status) ++ "\r\n"
    ++ Response.render_headers(
         Map.to_list(&2, String,
           Map.set(&2, String, headers, "connection", Bool.pick(String, keep, "keep-alive", "close"))),
         SNil{})
    ++ Response.render_cookies(cookies, SNil{})

def Response.render_framing(chunked: Bool) -> String:
  match chunked:
    case True{}:
      "transfer-encoding: chunked\r\n"
    case False{}:
      SNil{}

# The head of a streamed response: no `content-length`, and
# `transfer-encoding: chunked` when `chunked` (an HTTP/1.0 client gets
# the pieces raw and the close marks the end).
def Response.render_head(r: Response, +keep: Bool, chunked: Bool) -> String:
  match r:
    case Response{+status, headers, cookies, body}:
      Response.render_start(status, headers, cookies, keep)
        ++ Response.render_framing(chunked)
        ++ "\r\n"

# The wire form of a response. `head_only` drops the body, for HEAD
# requests. `keep` picks the Connection header. A stream renders as its
# chunked head; the server writes the pieces.
def Response.render(r: Response, head_only: Bool, +keep: Bool) -> String:
  match r:
    case Response{+status, headers, cookies, Whole{+body}}:
      Response.render_start(status, headers, cookies, keep)
        ++ Response.render_length(Text.byte_length(body, 0), status)
        ++ "\r\n"
        ++ Response.render_body(body, Bool.or(head_only, Response.no_body(status)))
    case Response{+status, headers, cookies, Stream{chan}}:
      Response.render_head(Response{status, headers, cookies, Stream{chan}}, keep, True{})

# Streaming
# ---------

def drop_zeros(+s: String) -> String:
  match s:
    case SCon{'0', SCon{h, t}}:
      drop_zeros(SCon{h, t})
    case _:
      s

# One chunk of a chunked body: the byte size in hex, CRLF, the bytes,
# CRLF. An empty piece is skipped, since "0" would end the body.
def chunk(+piece: String) -> String:
  match piece:
    case SNil{}:
      SNil{}
    case SCon{h, t}:
      drop_zeros(Text.hex_show(Text.byte_length(piece, 0))) ++ "\r\n" ++ piece ++ "\r\n"

def last_chunk() -> String:
  "0\r\n\r\n"

# A 200 whose body is whatever the producer sends on `chan`, written
# as it arrives, until the producer closes the channel. Each piece
# gets the send timeout; a producer that goes silent longer ends the
# connection. When the client goes away the server closes the channel,
# so the producer's next `Chan.send` answers False: stop then.
def Response.stream(chan: Chan(String)) -> Response:
  Response{200, Map.new(&2, String), Nil{}, Stream{chan}}

# A stream typed as Server-Sent Events; send `Sse.event` or `Sse.data`
# on the channel.
def Response.sse(chan: Chan(String)) -> Response:
  Response.with_header(Response.with_header(Response.stream(chan), "content-type", "text/event-stream"), "cache-control", "no-cache")

def Sse.lines(lines: List<&2, String>, acc: String) -> String:
  match lines:
    case Nil{}:
      acc
    case Con{h, t}:
      Sse.lines(t, acc ++ "data: " ++ h ++ "\n")

# `data:` lines, one per line of `data`, then the blank line that ends
# the event.
def Sse.data(data: String) -> String:
  Sse.lines(Text.split_all(data, '\n'), SNil{}) ++ "\n"

# A named event: "event: name" then the data lines.
def Sse.event(name: String, data: String) -> String:
  "event: " ++ name ++ "\n" ++ Sse.data(data)

# A full response that closes its connection.
def Response.serialize(r: Response) -> String:
  Response.render(r, False{}, False{})

