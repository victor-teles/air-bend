import Base
import ./text.bend as Text
import ./http.bend as Http
import ./router.bend as Router

# Shield
# ======
#
# Defensive response headers as one middleware. The shield is a list of
# (name, value) pairs; each is set only when the response lacks it, so a
# handler's own header wins. HSTS and CSP are opt-in: Air runs behind a
# TLS proxy, and HSTS from a plain-HTTP server is a trap.

def Shield() -> Data:
  List<&2, Text.Two()>

def pair(name: String, value: String) -> Text.Two():
  (name, value)

# nosniff, no framing, a tight referrer policy, and same-origin
# isolation for the opener and for cross-origin loads.
def default() -> Shield():
  [
    pair("x-content-type-options", "nosniff"),
    pair("x-frame-options", "DENY"),
    pair("referrer-policy", "strict-origin-when-cross-origin"),
    pair("cross-origin-opener-policy", "same-origin"),
    pair("cross-origin-resource-policy", "same-origin"),
    pair("x-permitted-cross-domain-policies", "none")
  ]

def key_is(kv: Text.Two(), +name: String) -> Bool:
  String.eq(Text.fst(kv), name)

def has(hs: Shield(), +name: String) -> Bool:
  match hs:
    case Nil{}:
      False{}
    case Con{kv, t}:
      Bool.or(key_is(kv, name), has(t, name))

def swap_value(kv: Text.Two(), +name: String, +value: String) -> Text.Two():
  (k, v) = kv
  +k = k
  Bool.pick(Text.Two(), String.eq(k, name), (k, value), (k, v))

def replace(hs: Shield(), +name: String, +value: String) -> Shield():
  match hs:
    case Nil{}:
      Nil{}
    case Con{kv, t}:
      Con{swap_value(kv, name, value), replace(t, name, value)}

def with_header.go(hs: Shield(), +name: String, +value: String, present: Bool) -> Shield():
  match present:
    case True{}:
      replace(hs, name, value)
    case False{}:
      List.append(&2, Text.Two(), hs, [pair(name, value)])

# Sets a header in the shield: replaces it by name, else appends it.
# Names are lowercased.
def with_header(hs: Shield(), name: String, value: String) -> Shield():
  +hs = hs
  +name = String.to_lower(name)
  with_header.go(hs, name, value, has(hs, name))

# `Strict-Transport-Security` for `seconds`, subdomains included. Only
# for a server reached over HTTPS.
def with_hsts(hs: Shield(), seconds: U32) -> Shield():
  with_header(hs, "strict-transport-security", "max-age=" ++ U32.show(seconds) ++ "; includeSubDomains")

def with_csp(hs: Shield(), policy: String) -> Shield():
  with_header(hs, "content-security-policy", policy)

# "DENY" or "SAMEORIGIN".
def with_frame(hs: Shield(), value: String) -> Shield():
  with_header(hs, "x-frame-options", value)

def apply.step(r: Http.Response, kv: Text.Two()) -> Http.Response:
  (k, v) = kv
  Http.Response.with_default_lower(r, k, v)

# Every header of the shield onto the response, where absent.
def apply(hs: Shield(), r: Http.Response) -> Http.Response:
  match hs:
    case Nil{}:
      r
    case Con{kv, t}:
      apply(t, apply.step(r, kv))

def applied(hs: Shield(), r: Http.Response) -> IO(Http.Response):
  IO.pure(Http.Response, apply(hs, r))

# `shield(hs)` is a middleware: runs `next`, then adds what is missing.
def shield(hs: Shield(), next: Router.Handler(), req: Http.Request) -> IO(Http.Response):
  IO.bind(Http.Response, Http.Response, next(req), applied(hs))
