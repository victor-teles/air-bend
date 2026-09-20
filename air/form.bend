import Base
import ./text.bend as Text
import ./http.bend as Http

# Form
# ====
#
# `multipart/form-data`, the encoding browsers use to upload files,
# parsed in memory: Air reads bodies whole under the body limit. Parts
# are text, because the runtime receives UTF-8 text from a socket; a
# binary upload is not preserved byte for byte.

type Part is Data:
  Part{name: String, filename: Maybe<&2, String>, mime: String, body: String}

def Part.name(p: Part) -> String:
  match p:
    case Part{n, f, m, b}:
      n

# The uploaded file's name, when the part is a file.
def Part.filename(p: Part) -> Maybe<&2, String>:
  match p:
    case Part{n, f, m, b}:
      f

# The part's content type; "text/plain" when it had none.
def Part.mime(p: Part) -> String:
  match p:
    case Part{n, f, m, b}:
      m

def Part.body(p: Part) -> String:
  match p:
    case Part{n, f, m, b}:
      b

# Header parameters
# -----------------

def drop_quote(+s: String) -> String:
  match s:
    case SCon{'"', t}:
      t
    case _:
      s

def unquote(v: String) -> String:
  String.reverse(drop_quote(String.reverse(drop_quote(v))))

def lookup.pick(v: String, same: Bool) -> Maybe<&2, String>:
  match same:
    case True{}:
      Some{v}
    case False{}:
      None{}

def lookup.try(+name: String, kv: Text.Two()) -> Maybe<&2, String>:
  (k, v) = kv
  lookup.pick(unquote(String.trim(v)), String.eq(String.to_lower(String.trim(k)), name))

def lookup.go(pieces: List<&2, String>, +name: String, found: Maybe<&2, String>) -> Maybe<&2, String>:
  match pieces found:
    case _ Some{v}:
      Some{v}
    case Nil{} None{}:
      None{}
    case Con{+h, t} None{}:
      lookup.go(t, name, lookup.try(name, Text.split_at(h, '=')))

# A `name=value` parameter of a header like `form-data; name="x"`,
# quotes stripped; None when absent.
def param(+value: String, name: String) -> Maybe<&2, String>:
  lookup.go(Text.split_all(value, ';'), name, None{})

def media_type(+ct: String) -> String:
  String.trim(String.to_lower(Text.fst(Text.split_at(ct, ';'))))

def boundary.pick(b: Maybe<&2, String>, multipart: Bool) -> Maybe<&2, String>:
  match b multipart:
    case Some{SCon{h, t}} True{}:
      Some{SCon{h, t}}
    case _ _:
      None{}

# The boundary of a `multipart/form-data` content type; None for any
# other type or when the parameter is missing or empty.
def boundary(+ct: String) -> Maybe<&2, String>:
  boundary.pick(param(ct, "boundary"), String.eq(media_type(ct), "multipart/form-data"))

# Parts
# -----

def part.build(name: Maybe<&2, String>, filename: Maybe<&2, String>, mime: String, body: String) -> Maybe<&2, Part>:
  match name:
    case None{}:
      None{}
    case Some{n}:
      Some{Part{n, filename, mime, body}}

def part.mime(+ct: String) -> String:
  match ct:
    case SNil{}:
      "text/plain"
    case SCon{h, t}:
      ct

def part.headers(m: Maybe<&2, Map<&2, String>>, body: String) -> Maybe<&2, Part>:
  match m:
    case None{}:
      None{}
    case Some{+h}:
      part.build(
        param(Text.map_get(h, "content-disposition", SNil{}), "name"),
        param(Text.map_get(h, "content-disposition", SNil{}), "filename"),
        part.mime(Text.map_get(h, "content-type", SNil{})),
        body)

def part.split(hb: Maybe<&2, Text.Two()>) -> Maybe<&2, Part>:
  match hb:
    case None{}:
      None{}
    case Some{pair}:
      (head, body) = pair
      part.headers(Http.Request.parse_headers(Text.split_all(head, '\n'), Some{Map.new(&2, String)}), body)

# One piece between delimiters: header lines, a blank line, content.
# A piece without the blank line or without a `name` is refused.
def part(piece: String) -> Maybe<&2, Part>:
  part.split(Text.split_str(piece, "\r\n\r\n"))

def push_part(acc: List<&2, Part>, p: Maybe<&2, Part>) -> Maybe<&2, List<&2, Part>>:
  match p:
    case None{}:
      None{}
    case Some{p2}:
      Some{Con{p2, acc}}

# Walks the pieces after the preamble. A piece starting with `--` is the
# closing delimiter; one starting with CRLF is a part; anything else,
# or running out before the close, is a malformed body.
def parts.go(pieces: List<&2, String>, acc: Maybe<&2, List<&2, Part>>) -> Maybe<&2, List<&2, Part>>:
  match pieces acc:
    case _ None{}:
      None{}
    case Nil{} Some{a}:
      None{}
    case Con{SCon{'-', SCon{'-', t}}, rest} Some{a}:
      Some{List.reverse(&2, Part, a)}
    case Con{SCon{'\r', SCon{'\n', piece}}, rest} Some{a}:
      parts.go(rest, push_part(a, part(piece)))
    case Con{h, rest} Some{a}:
      None{}

def parts.split(pieces: List<&2, String>) -> Maybe<&2, List<&2, Part>>:
  match pieces:
    case Nil{}:
      None{}
    case Con{preamble, rest}:
      parts.go(rest, Some{Nil{}})

def parse.pick(body: String, b: Maybe<&2, String>) -> Maybe<&2, List<&2, Part>>:
  match b:
    case None{}:
      None{}
    case Some{bd}:
      parts.split(Text.split_seq_all(SCon{'\r', SCon{'\n', body}}, "\r\n--" ++ bd))

# The parts of a multipart body, given its content type. The body is
# split on CRLF + "--" + boundary (a CRLF is prepended so the first
# delimiter matches too), then each piece is read as a part.
def parse(+content_type: String, body: String) -> Maybe<&2, List<&2, Part>>:
  parse.pick(body, boundary(content_type))

# The parts of a request, when it is multipart/form-data and well formed.
def parts(+req: Http.Request) -> Maybe<&2, List<&2, Part>>:
  parse(Http.Request.header(req, "content-type"), Http.Request.body(req))

# Reading
# -------

def is_field(p: Part, +name: String) -> Bool:
  match p:
    case Part{n, None{}, m, b}:
      String.eq(n, name)
    case Part{n, Some{f}, m, b}:
      False{}

def is_file(p: Part, +name: String) -> Bool:
  match p:
    case Part{n, None{}, m, b}:
      False{}
    case Part{n, Some{f}, m, b}:
      String.eq(n, name)

def field.try(+p: Part, +name: String) -> Maybe<&2, String>:
  lookup.pick(Part.body(p), is_field(p, name))

def field.go(ps: List<&2, Part>, +name: String, found: Maybe<&2, String>) -> String:
  match ps found:
    case _ Some{v}:
      v
    case Nil{} None{}:
      SNil{}
    case Con{+p, t} None{}:
      field.go(t, name, field.try(p, name))

def file.pick(p: Part, hit: Bool) -> Maybe<&2, Part>:
  match hit:
    case True{}:
      Some{p}
    case False{}:
      None{}

def file.try(+p: Part, +name: String) -> Maybe<&2, Part>:
  file.pick(p, is_file(p, name))

def file.go(ps: List<&2, Part>, +name: String, found: Maybe<&2, Part>) -> Maybe<&2, Part>:
  match ps found:
    case _ Some{p}:
      Some{p}
    case Nil{} None{}:
      None{}
    case Con{+p, t} None{}:
      file.go(t, name, file.try(p, name))

# The first plain field (no filename) named `name`; "" when absent.
def field(ps: List<&2, Part>, name: String) -> String:
  field.go(ps, name, None{})

# The first file part named `name`.
def file(ps: List<&2, Part>, name: String) -> Maybe<&2, Part>:
  file.go(ps, name, None{})
