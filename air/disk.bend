import Base
import ./text.bend as Text
import ./http.bend as Http

# Disk
# ====
#
# Reading a file into a response. `File.read` hands the handle back
# beside each chunk; read until a chunk is empty, then close.
# `Text.append` keeps big files off the stack. Files are read as UTF-8
# text, because a socket is written as text: HTML, CSS, JavaScript,
# SVG and JSON are fine, a PNG is not preserved.

def OpenR() -> Type:
  Result<&1, &1, U32 & String, File>

def ReadR() -> Type:
  File & Result<&1, &1, U32 & String, String>

type Reading is Type:
  More{file: File, acc: String}
  Finished{file: File, acc: String}
  Failed{file: File}

def read.more(file: File, acc: String, eof: Bool) -> Reading:
  match eof:
    case True{}:
      Finished{file, acc}
    case False{}:
      More{file, acc}

def read.step(acc: String, r: ReadR()) -> Reading:
  (file, res) = r
  match res:
    case Fail{e}:
      Failed{file}
    case Done{+chunk}:
      read.more(file, Text.append(acc, chunk), String.is_empty(chunk))

# 64 KiB per read, up to 1000 reads: files past 64 MiB are cut short.
def read.loop(fuel: Nat, state: Reading) -> IO(Maybe<&2, String>):
  match fuel state:
    case _ Finished{file, acc}:
      do IO<Maybe<&2, String>>:
        File.close(file)
        return Some{acc}
    case _ Failed{file}:
      do IO<Maybe<&2, String>>:
        File.close(file)
        return None{}
    case 0n More{file, acc}:
      do IO<Maybe<&2, String>>:
        File.close(file)
        return Some{acc}
    case 1n+p More{file, acc}:
      do IO<Maybe<&2, String>>:
        r : ReadR() <- File.read(file, 65536)
        read.loop(p, read.step(acc, r))

def read.opened(r: OpenR()) -> IO(Maybe<&2, String>):
  match r:
    case Fail{e}:
      IO.pure(Maybe<&2, String>, None{})
    case Done{file}:
      read.loop(1000n, More{file, SNil{}})

# The whole file as text, or None when it cannot be opened or read.
def read(path: String) -> IO(Maybe<&2, String>):
  IO.bind(OpenR(), Maybe<&2, String>, File.open(path, "r"), read.opened)

def respond.fin(+req: Http.Request, mime: String, body: Maybe<&2, String>) -> IO(Http.Response):
  match body:
    case None{}:
      IO.pure(Http.Response, Http.Response.not_found())
    case Some{b}:
      IO.pure(Http.Response,
        Http.Response.ranged(req,
          Http.Response.conditional(req,
            Http.Response.with_etag(Http.Response.with_type(Http.Response.new(200, b), mime)))))

# The file at `path` as a response with `mime`: a tagged 200, a 304 when
# the client's `If-None-Match` has the tag, a 206 for a `Range`, or 404
# when the file cannot be read. The path is the app's to choose: nothing
# here guards against `..`.
def respond(req: Http.Request, path: String, mime: String) -> IO(Http.Response):
  IO.bind(Maybe<&2, String>, Http.Response, read(path), respond.fin(req, mime))
