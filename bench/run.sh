#!/usr/bin/env bash
# Builds the example natively, benchmarks it, then benchmarks the Node
# reference server with the same load. Usage: bench/run.sh [conns] [seconds]
# SKIP_BUILD=1 reuses bench/out/hello.
set -euo pipefail
cd "$(dirname "$0")/.."
CONNS=${1:-64}
SECS=${2:-10}
mkdir -p bench/out

if [[ -z "${SKIP_BUILD:-}" || ! -x bench/out/hello ]]; then
  echo "building examples/hello/main.bend natively..."
  bend examples/hello/main.bend -o bench/out/hello
fi

cleanup() { kill "${AIR_PID:-}" "${NODE_PID:-}" 2>/dev/null || true; }
trap cleanup EXIT

bench/out/hello > bench/out/air.log 2>&1 & AIR_PID=$!
node bench/reference.mjs 8081 > bench/out/node.log 2>&1 & NODE_PID=$!
sleep 2

for target in "air http://localhost:8080" "node http://localhost:8081"; do
  set -- $target
  echo; echo "== $1: GET /hello/:name =="
  node bench/bench.mjs --url "$2/hello/world" --conns "$CONNS" --seconds "$SECS"
  echo; echo "== $1: POST /echo (1KB) =="
  node bench/bench.mjs --url "$2/echo" --method POST --body "$(head -c 1024 /dev/zero | tr '\0' x)" --conns "$CONNS" --seconds "$SECS"
done
