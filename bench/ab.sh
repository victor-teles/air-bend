#!/usr/bin/env bash
# A/B throughput of two hello binaries built for the same port
# (bench/build.sh), run one at a time on the same machine, alternating
# base and head for each round so drift in the machine hits both alike.
# Usage: bench/ab.sh <base-bin> <head-bin>
# Env: ROUNDS (5), SECS (5), CONNS (32), BENCH_PORT (18080),
#      OUT (bench/out/ab.jsonl), HEADER ("name: value" on every request,
#      e.g. a traceparent). Compare with `node bench/compare.mjs`.
set -euo pipefail
cd "$(dirname "$0")/.."
BASE=$1
HEAD=$2
ROUNDS=${ROUNDS:-5}
SECS=${SECS:-5}
CONNS=${CONNS:-32}
PORT=${BENCH_PORT:-18080}
OUT=${OUT:-bench/out/ab.jsonl}
HEADER_ARGS=(); [[ -n "${HEADER:-}" ]] && HEADER_ARGS=(--header "$HEADER")
URL="http://localhost:$PORT"
BODY=$(head -c 1024 /dev/zero | tr '\0' x)
mkdir -p "$(dirname "$OUT")"
: > "$OUT"

PID=""
cleanup() { [[ -n "$PID" ]] && kill "$PID" 2>/dev/null || true; }
trap cleanup EXIT

if curl -s -o /dev/null --max-time 1 "$URL/"; then
  echo "ab.sh: something already answers on port $PORT; set BENCH_PORT" >&2
  exit 1
fi

# Starts a binary and waits until it answers, up to two minutes.
start() {
  "$1" > "bench/out/ab-$2.log" 2>&1 &
  PID=$!
  for _ in $(seq 240); do
    curl -s -o /dev/null --max-time 1 "$URL/hello/x" && return 0
    kill -0 "$PID" 2>/dev/null || { echo "ab.sh: $1 exited" >&2; cat "bench/out/ab-$2.log" >&2; exit 1; }
    sleep 0.5
  done
  echo "ab.sh: $1 did not answer on $URL" >&2
  exit 1
}

stop() {
  kill "$PID" 2>/dev/null || true
  wait "$PID" 2>/dev/null || true
  PID=""
}

# One line per measurement: the bench's JSON with side and round added.
record() {
  node -e 'const [side, round] = process.argv.slice(1); let s = ""; process.stdin.on("data", (c) => (s += c)).on("end", () => console.log(JSON.stringify({ side, round: Number(round), ...JSON.parse(s) })));' "$1" "$2" >> "$OUT"
}

for round in $(seq "$ROUNDS"); do
  for side in base head; do
    bin=$BASE; [[ $side == head ]] && bin=$HEAD
    echo "round $round: $side"
    start "$bin" "$side"
    node bench/bench.mjs --url "$URL/hello/world" --conns "$CONNS" --seconds "$SECS" ${HEADER_ARGS[@]+"${HEADER_ARGS[@]}"} --json | record "$side" "$round"
    node bench/bench.mjs --url "$URL/echo" --method POST --body "$BODY" --conns "$CONNS" --seconds "$SECS" ${HEADER_ARGS[@]+"${HEADER_ARGS[@]}"} --json | record "$side" "$round"
    stop
  done
done
echo "wrote $OUT"
