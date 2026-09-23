#!/usr/bin/env bash
# Builds examples/hello natively from a checkout, listening on a chosen
# port. Usage: bench/build.sh <repo-dir> <out-binary> [port]
#
# Hello's `main` serves on 8080. The A/B runner needs a port it knows is
# free, and the checkout may be `main` rather than this branch, so the
# port is swapped in a copy of `main.bend` next to the original (its
# relative imports must still resolve), built, and the copy removed.
set -euo pipefail
REPO=$(cd "$1" && pwd)
OUT=$2
PORT=${3:-18080}
MAIN="$REPO/examples/hello/main.bend"
COPY="$REPO/examples/hello/bench_main.bend"

grep -q ', 8080)' "$MAIN" || { echo "build.sh: no ', 8080)' in $MAIN to replace" >&2; exit 1; }
trap 'rm -f "$COPY"' EXIT
sed "s/, 8080)/, $PORT)/" "$MAIN" > "$COPY"
mkdir -p "$(dirname "$OUT")"
bend "$COPY" -o "$OUT"
