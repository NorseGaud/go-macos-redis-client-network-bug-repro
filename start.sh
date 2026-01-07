#!/bin/bash
# start.sh - Runs on remote macOS host (called by run.sh)
set -e

BINARY="/tmp/repro"
LOG="/tmp/repro.log"
PID="/tmp/repro.pid"

echo ""
echo "  [REMOTE] Cleaning up any previous test..."

# Kill existing
if [[ -f "$PID" ]]; then
    kill "$(cat "$PID")" 2>/dev/null || true
fi
rm -f "$PID" "$LOG"

if [[ ! -x "$BINARY" ]]; then
    echo "  [REMOTE] ERROR: $BINARY not found or not executable"
    exit 1
fi

echo "  [REMOTE] Starting background process: $BINARY"
echo "  [REMOTE] Output logging to: $LOG"

nohup "$BINARY" > "$LOG" 2>&1 &
disown
echo $! > "$PID"

echo "  [REMOTE] Process started with PID: $(cat $PID)"
echo ""
echo "  [REMOTE] Waiting ~45s for first test cycle to complete..."
echo "           (includes 30s delay if local network is blocked)"
echo ""

# Wait for first test cycle
sleep 45

echo ""
echo "  [REMOTE] First test cycle complete. Results so far:"
echo ""
head -50 "$LOG"
echo ""
echo "  [REMOTE] Now exiting SSH session..."
echo "  [REMOTE] Test process (PID $(cat $PID)) will continue running."
echo ""
