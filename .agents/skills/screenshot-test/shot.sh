#!/usr/bin/env bash
# Render the booker GUI to a PNG for visual inspection, optionally after typing
# a query live via System Events (which reproduces bugs that pre-filled state
# hides). Prints the PNG path on success.
#
# Usage: shot.sh [keystrokes] [out.png]
#   shot.sh                 -> empty query (initial list)
#   shot.sh '@a'            -> types "@a" live, then renders
#   shot.sh 'git' /tmp/x.png
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
QUERY="${1:-}"
OUT="${2:-/tmp/booker-shot.png}"
DELAY="${BOOKER_SHOT_DELAY:-4}"

cd "$ROOT"
swift build >/dev/null 2>&1

rm -f "$OUT"
BOOKER_SHOT="$OUT" BOOKER_SHOT_DELAY="$DELAY" ./.build/debug/booker >/dev/null 2>&1 &
PID=$!

sleep 1.2
if [ -n "$QUERY" ]; then
    osascript -e "tell application \"System Events\" to keystroke \"$QUERY\"" >/dev/null 2>&1 || true
fi

# Poll for the render (the app writes the PNG then self-terminates). This
# avoids a cold-start race where a fixed sleep+kill can kill the app before it
# has rendered.
deadline=$(( SECONDS + DELAY + 8 ))
while [ ! -s "$OUT" ] && [ "$SECONDS" -lt "$deadline" ] && kill -0 "$PID" 2>/dev/null; do
    sleep 0.3
done
kill "$PID" >/dev/null 2>&1 || true

if [ -s "$OUT" ]; then
    echo "$OUT"
else
    echo "ERROR: no PNG produced at $OUT" >&2
    exit 1
fi
