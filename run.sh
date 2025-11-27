#!/bin/bash
# run.sh - Run from your local machine
# Usage: ./run.sh user@remote-mac

set -e

if [[ -z "$1" ]]; then
    echo "Usage: $0 user@remote-mac"
    exit 1
fi

REMOTE="$1"
DIR="$(cd "$(dirname "$0")" && pwd)"

echo "============================================"
echo "macOS Network Bug - C Reproduction"
echo "============================================"
echo "Remote: $REMOTE"
echo ""

echo "[1/3] Compiling on remote..."
scp "$DIR/repro.c" "$REMOTE:/tmp/repro.c"
ssh "$REMOTE" "clang -o /tmp/repro /tmp/repro.c"

echo "[2/3] Copying start script..."
scp "$DIR/start.sh" "$REMOTE:/tmp/start.sh"
ssh "$REMOTE" "chmod +x /tmp/start.sh"

echo "[3/3] Starting test (SSH will disconnect after)..."
ssh -t "$REMOTE" "/tmp/start.sh"

echo ""
echo "SSH closed. Waiting 15s..."
sleep 10

echo ""
echo "=== Results after disconnect ==="
ssh "$REMOTE" "tail -50 /tmp/repro.log"

echo ""
echo "=== Cleaning up (keeping log) ==="
ssh "$REMOTE" "kill \$(cat /tmp/repro.pid) 2>/dev/null || true; rm -f /tmp/repro /tmp/repro.c /tmp/repro.pid /tmp/start.sh"
echo "Done. Log saved at $REMOTE:/tmp/repro.log"
