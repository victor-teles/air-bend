import Base
import ./text.bend as Text
import ./json.bend as Json
import ./http.bend as Http
import ./router.bend as Router
import ./store.bend as Store

# Test
# ====
#
# Runs an app on a request without a socket. The request is raw HTTP
# text, read the way the server reads it: the head up to the blank line
# is parsed under the default limits, the body is framed by its
# `Content-Length`, and a head the server would refuse comes back as the
# refusal it would send. The app gets a store, as under `serve`, and its
# response is settled as the server settles it before writing.
#
# What is not simulated: timeouts (there is no connection to watch),
# keep-alive, `Expect: 100-continue`, and chunked request bodies, which
# are passed through as they are written.
#
# A test program is a `main` that runs checks and ends with `finish`:
#
#   def main() -> IO(Unit):
#     do IO<Unit>:
#       res : Air.Response() <- Air.Test.inject(app, Air.Test.get("/hello/ada"))
#       ok : Bool <- Air.Test.expect("greets", Air.Response.body(res), "Olá, ada!")
#       Air.Test.finish([ok])

# Requests
# --------

# A GET for `target` ("/path?query") with a `host` header.
def get(target: String) -> String:
  "GET " ++ target ++ " HTTP/1.1\r\nhost: test\r\n\r\n"

# A POST of `body` with its type and its length in bytes.
def post(target: String, content_type: String, +body: String) -> String:
  "POST " ++ target ++ " HTTP/1.1\r\nhost: test\r\ncontent-type: " ++ content_type
    ++ "\r\ncontent-length: " ++ U32.show(Text.byte_length(body, 0)) ++ "\r\n\r\n" ++ body

def with_header.fin(line: String, raw: String, found: Maybe<&2, Text.Two()>) -> String:
  match found:
    case None{}:
      raw
    case Some{hr}:
      (head, rest) = hr
      head ++ "\r\n" ++ line ++ "\r\n\r\n" ++ rest

# `raw` with one more header line, at the end of the head.
def with_header(name: String, value: String, +raw: String) -> String:
  with_header.fin(name ++ ": " ++ value, raw, Text.split_str(raw, "\r\n\r\n"))

# Framing
# -------

# What the server would do with the raw text: serve the parsed request
# with its body, or refuse it with a status.
type Prepared is Data:
  Serve{req: Http.Request, body: String}
  Refuse{status: U32}

def prepare.take(req: Http.Request, t: Text.Take) -> Prepared:
  match t:
    case Text.Took{body, rest}:
      Serve{req, body}
    case Text.TakeNeed{}:
      Refuse{400}
    case Text.TakeBad{}:
      Refuse{400}

def prepare.sized(req: Http.Request, rest: String, +n: U32, over: Bool) -> Prepared:
  match over:
    case True{}:
      Refuse{413}
    case False{}:
      prepare.take(req, Text.take_bytes(rest, n))

# A body shorter than its `Content-Length` is a 400 here; the server
# would wait for the rest until the body timeout.
def prepare.body(req: Http.Request, rest: String, +max: U32, framing: Http.Framing) -> Prepared:
  match framing:
    case Http.NoBody{}:
      Serve{req, SNil{}}
    case Http.Fixed{+n}:
      prepare.sized(req, rest, n, U32.is_gt(n, max))
    case Http.Chunked{}:
      Serve{req, rest}
    case Http.Unframed{status}:
      Refuse{status}

def prepare.parsed(+limits: Http.Limits, rest: String, p: Http.Parsed) -> Prepared:
  match p:
    case Http.Parsed{+req}:
      prepare.body(req, rest, Http.Limits.body(limits), Http.Request.framing(req))
    case Http.Refused{status}:
      Refuse{status}

def prepare.head(+limits: Http.Limits, head: String, rest: String, over: Bool) -> Prepared:
  match over:
    case True{}:
      Refuse{431}
    case False{}:
      prepare.parsed(limits, rest, Http.Request.parse(limits, head))

def prepare.sized_head(+limits: Http.Limits, +head: String, rest: String) -> Prepared:
  prepare.head(limits, head, rest, U32.is_gt(Text.byte_length(head, 0), Http.Limits.head(limits)))

# Text without a blank line is a head that never ended: 400.
def prepare.split(+limits: Http.Limits, found: Maybe<&2, Text.Two()>) -> Prepared:
  match found:
    case None{}:
      Refuse{400}
    case Some{hr}:
      (head, rest) = hr
      prepare.sized_head(limits, head, rest)

def prepare(+limits: Http.Limits, raw: String) -> Prepared:
  prepare.split(limits, Text.split_str(Text.drop_crlf(raw), "\r\n\r\n"))

# The status a prepared request would be refused with, 0 when served;
# for laws.
def Prepared.refused(p: Prepared) -> U32:
  match p:
    case Serve{req, body}:
      0
    case Refuse{status}:
      status

# The body a prepared request would be served with; for laws.
def Prepared.body(p: Prepared) -> String:
  match p:
    case Serve{req, body}:
      body
    case Refuse{status}:
      SNil{}

# Running
# -------

def settle(res: Http.Response) -> IO(Http.Response):
  IO.pure(Http.Response, Http.Response.settle(Http.Prod{}, res))

def run(app: Router.Handler(), +store: Store.Store(), p: Prepared) -> IO(Http.Response):
  match p:
    case Serve{req, body}:
      IO.bind(Http.Response, Http.Response, app(Http.Request.with_store(Http.Request.with_body(req, body), Some{store})), settle)
    case Refuse{status}:
      IO.pure(Http.Response, Http.Response.refusal(status))

# Runs `app` on `raw` with a store the caller keeps, so state carries
# from one request to the next: counters, sessions, rate limits.
def inject_shared(app: Router.Handler(), store: Store.Store(), raw: String) -> IO(Http.Response):
  +store = store
  run(app, store, prepare(Http.Limits.default(), raw))

# Runs `app` on `raw` with a fresh store.
def inject(app: Router.Handler(), raw: String) -> IO(Http.Response):
  IO.bind(Store.Store(), Http.Response, Store.new(), s => inject_shared(app, s, raw))

# Bodies
# ------

# A stream being read: still filling, or closed with its text.
type Reading is Data:
  Filling{acc: String}
  Filled{text: String}

def drain.next(acc: String, got: Maybe<&1, String>) -> IO(Reading):
  match got:
    case None{}:
      IO.pure(Reading, Filled{acc})
    case Some{piece}:
      IO.pure(Reading, Filling{Text.append(acc, piece)})

def drain.step(+chan: Chan(String), acc: String) -> IO(Reading):
  IO.bind(Maybe<&1, String>, Reading, Chan.recv(String, chan), got => drain.next(acc, got))

def drain(fuel: Nat, +chan: Chan(String), st: Reading) -> IO(String):
  match fuel st:
    case _ Filled{text}:
      IO.pure(String, text)
    case 0n Filling{acc}:
      do IO<String>:
        Chan.close(String, chan)
        return acc
    case 1n+p Filling{acc}:
      do IO<String>:
        next : Reading <- drain.step(chan, acc)
        drain(p, chan, next)

# The body as the client would read it: a stream's pieces joined, once
# the producer closes the channel. A failed body (never seen after
# `inject`, which settles) reads as "".
def body.of(b: Http.Body) -> IO(String):
  match b:
    case Http.Whole{text}:
      IO.pure(String, text)
    case Http.Stream{chan}:
      drain(1000000n, chan, Filling{SNil{}})
    case Http.Failed{err}:
      IO.pure(String, SNil{})

def body(res: Http.Response) -> IO(String):
  body.of(Http.Response.payload(res))

# Checks
# ------

def quote(s: String) -> String:
  Json.render(Json.of_str(s))

def verdict(+name: String, ok: Bool, why: String) -> IO(Bool):
  match ok:
    case True{}:
      do IO<Bool>:
        IO.print("ok - " ++ name)
        return True{}
    case False{}:
      do IO<Bool>:
        IO.print("not ok - " ++ name ++ ": " ++ why)
        return False{}

def expect.go(+name: String, +got: String, +want: String) -> IO(Bool):
  verdict(name, String.eq(got, want), "want " ++ quote(want) ++ " got " ++ quote(got))

# Prints `ok - name`, or `not ok - name: want "…" got "…"`; answers
# whether it passed.
def expect(name: String, got: String, want: String) -> IO(Bool):
  expect.go(name, got, want)

def expect_u32(name: String, got: U32, want: U32) -> IO(Bool):
  expect.go(name, U32.show(got), U32.show(want))

# A condition with a note shown when it fails.
def expect_true(name: String, ok: Bool, note: String) -> IO(Bool):
  verdict(name, ok, note)

def passed(xs: List<&2, Bool>, +acc: U32) -> U32:
  match xs:
    case Nil{}:
      acc
    case Con{True{}, t}:
      passed(t, U32.inc(acc))
    case Con{False{}, t}:
      passed(t, acc)

def finish.fin(line: String, clean: Bool) -> IO(Unit):
  match clean:
    case True{}:
      IO.print(line)
    case False{}:
      do IO<Unit>:
        IO.print(line)
        IO.die(Unit, 1, "tests failed")

def finish.go(+pass: U32, +total: U32) -> IO(Unit):
  +line = U32.show(pass) ++ " passed, " ++ U32.show(U32.sub(total, pass)) ++ " failed"
  finish.fin(line, U32.is_eq(pass, total))

def count(xs: List<&2, Bool>, +acc: U32) -> U32:
  match xs:
    case Nil{}:
      acc
    case Con{h, t}:
      count(t, U32.inc(acc))

# Prints the tally and ends the process with code 1 when any check
# failed.
def finish(results: List<&2, Bool>) -> IO(Unit):
  +results = results
  finish.go(passed(results, 0), count(results, 0))
