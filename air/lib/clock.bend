import Base

# Clock
# =====
#
# The wall clock: milliseconds since the Unix epoch, as decimal text.
# `IO.now` is the time since the process started, which orders events
# but cannot be joined with another host's. The number does not fit a
# `U32`, and nothing in Air does arithmetic on it, so it stays text.
# A custom effect (`effs/wall_ms.c` for native builds, `.js` for the
# JS backend); replace it with Base's if Bend gains one.

def wall_ms() -> IO(String):
  import "./effs/wall_ms.c"
  import "./effs/wall_ms.js"
