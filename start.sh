#!/bin/bash
# start.sh - Runs on remote macOS host
set -e

BINARY="/tmp/repro"
LOG="/tmp/repro.log"
PID="/tmp/repro.pid"

echo "=== Starting test ==="

# Kill existing
[[ -f "$PID" ]] && kill "$(cat "$PID")" 2>/dev/null || true
rm -f "$PID" "$LOG"

[[ ! -x "$BINARY" ]] && echo "ERROR: $BINARY not found" && exit 1

nohup "$BINARY" > "$LOG" 2>&1 &
disown
echo $! > "$PID"

echo "PID: $(cat $PID)"
echo "Waiting for first test cycle (includes 30s delay if local network fails)..."
sleep 45

echo ""
head -40 "$LOG"
echo ""
echo "=== Exiting SSH ==="
