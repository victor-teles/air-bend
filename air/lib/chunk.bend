import Base
import ./text.bend as Text

# Chunked bodies
# ==============
#
# A decoder for `Transfer-Encoding: chunked`. `buf` is undecoded input,
# `acc` the decoded body reversed, `used` its byte count. `ChunkWait`
# wraps a state that needs more input; `feed` gives it some.

type Decoder is Data:
  ChunkSize{buf: String, acc: String, used: U32}
  ChunkData{buf: String, acc: String, used: U32, n: U32}
  ChunkTrail{buf: String, acc: String}
  ChunkWait{state: Decoder}
  ChunkDone{body: String, rest: String}
  ChunkBad{status: U32}

def size_line.fin(+rest: String, +acc: String, +used: U32, +max: U32, size: Maybe<&2, U32>) -> Decoder:
  match size:
    case None{}:
      ChunkBad{400}
    case Some{+n}:
      Bool.pick(Decoder, U32.is_eq(n, 0), ChunkTrail{rest, acc},
        Bool.pick(Decoder, U32.is_gt(n, U32.sub(max, used)), ChunkBad{413}, ChunkData{rest, acc, used, n}))

# A size line is hex digits, then optional `;extensions`, then CRLF.
def size_line(+buf: String, acc: String, used: U32, max: U32, split: Maybe<&2, Text.Two()>) -> Decoder:
  match split:
    case None{}:
      Bool.pick(Decoder, U32.is_gt(Text.byte_length(buf, 0), 1024), ChunkBad{400}, ChunkWait{ChunkSize{buf, acc, used}})
    case Some{lr}:
      (line, rest) = lr
      size_line.fin(rest, acc, used, max, Text.hex(String.trim(Text.fst(Text.split_at(line, ';')))))

def size(+buf: String, acc: String, used: U32, max: U32) -> Decoder:
  size_line(buf, acc, used, max, Text.split_str(buf, "\r\n"))

def data.crlf(buf: String, acc: String, used: U32, n: U32, data: String, rest: String) -> Decoder:
  match rest:
    case SCon{'\r', SCon{'\n', t}}:
      ChunkSize{t, Text.rev_onto(data, acc), U32.add(used, n)}
    case SNil{}:
      ChunkWait{ChunkData{buf, acc, used, n}}
    case SCon{'\r', SNil{}}:
      ChunkWait{ChunkData{buf, acc, used, n}}
    case _:
      ChunkBad{400}

def data.fin(buf: String, acc: String, used: U32, n: U32, take: Text.Take) -> Decoder:
  match take:
    case Text.TakeNeed{}:
      ChunkWait{ChunkData{buf, acc, used, n}}
    case Text.TakeBad{}:
      ChunkBad{400}
    case Text.Took{data, rest}:
      data.crlf(buf, acc, used, n, data, rest)

def data(+buf: String, acc: String, used: U32, +n: U32) -> Decoder:
  data.fin(buf, acc, used, n, Text.take_bytes(buf, n))

def trail.fin(rest: String, acc: String, blank: Bool) -> Decoder:
  match blank:
    case True{}:
      ChunkDone{String.reverse(acc), rest}
    case False{}:
      ChunkTrail{rest, acc}

# Trailer lines are read and ignored; the empty line ends the body.
def trail(+buf: String, acc: String, split: Maybe<&2, Text.Two()>) -> Decoder:
  match split:
    case None{}:
      Bool.pick(Decoder, U32.is_gt(Text.byte_length(buf, 0), 8192), ChunkBad{400}, ChunkWait{ChunkTrail{buf, acc}})
    case Some{lr}:
      (line, rest) = lr
      trail.fin(rest, acc, String.is_empty(line))

def trail_at(+buf: String, acc: String) -> Decoder:
  trail(buf, acc, Text.split_str(buf, "\r\n"))

# Decodes as far as the input allows, or until `fuel` runs out.
def drain(fuel: Nat, +max: U32, c: Decoder) -> Decoder:
  match fuel c:
    case _ ChunkWait{s}:
      ChunkWait{s}
    case _ ChunkDone{body, rest}:
      ChunkDone{body, rest}
    case _ ChunkBad{status}:
      ChunkBad{status}
    case 0n ChunkSize{buf, acc, used}:
      ChunkSize{buf, acc, used}
    case 0n ChunkData{buf, acc, used, n}:
      ChunkData{buf, acc, used, n}
    case 0n ChunkTrail{buf, acc}:
      ChunkTrail{buf, acc}
    case 1n+p ChunkSize{buf, acc, used}:
      drain(p, max, size(buf, acc, used, max))
    case 1n+p ChunkData{buf, acc, used, n}:
      drain(p, max, data(buf, acc, used, n))
    case 1n+p ChunkTrail{buf, acc}:
      drain(p, max, trail_at(buf, acc))

# Appends fresh input and unwraps a waiting state so it can be drained.
def feed(c: Decoder, data: String) -> Decoder:
  match c:
    case ChunkSize{buf, acc, used}:
      ChunkSize{Text.append(buf, data), acc, used}
    case ChunkData{buf, acc, used, n}:
      ChunkData{Text.append(buf, data), acc, used, n}
    case ChunkTrail{buf, acc}:
      ChunkTrail{Text.append(buf, data), acc}
    case ChunkWait{s}:
      feed(s, data)
    case ChunkDone{body, rest}:
      ChunkDone{body, Text.append(rest, data)}
    case ChunkBad{status}:
      ChunkBad{status}
