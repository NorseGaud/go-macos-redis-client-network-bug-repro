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

echo ""
echo "┌──────────────────────────────────────────────────────────────┐"
echo "│         macOS Local Network Bug - Reproduction               │"
echo "└──────────────────────────────────────────────────────────────┘"
echo ""
echo "This script will:"
echo "  1. Copy and compile test code on remote Mac"
echo "  2. Start a background process that tests network connectivity"
echo "  3. Disconnect SSH (this triggers the bug)"
echo "  4. Reconnect to check if local network access broke"
echo ""
echo "Remote host: $REMOTE"
echo ""

# ─────────────────────────────────────────────────────────────────────
# STEP 1: Setup on remote
# ─────────────────────────────────────────────────────────────────────
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 1/5: Uploading source code to remote Mac"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  [LOCAL]  Copying repro.c → $REMOTE:/tmp/repro.c"
scp -q "$DIR/repro.c" "$REMOTE:/tmp/repro.c"
echo "  [LOCAL]  Copying start.sh → $REMOTE:/tmp/start.sh"
scp -q "$DIR/start.sh" "$REMOTE:/tmp/start.sh"
ssh "$REMOTE" "chmod +x /tmp/start.sh"
echo "  ✓ Done"
echo ""

# ─────────────────────────────────────────────────────────────────────
# STEP 2: Compile on remote
# ─────────────────────────────────────────────────────────────────────
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 2/5: Compiling test binary on remote Mac"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  [REMOTE] Running: clang -o /tmp/repro /tmp/repro.c"
ssh "$REMOTE" "clang -o /tmp/repro /tmp/repro.c"
echo "  ✓ Done"
echo ""

# ─────────────────────────────────────────────────────────────────────
# STEP 3: Start test process on remote (via SSH)
# ─────────────────────────────────────────────────────────────────────
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 3/5: Starting test process on remote Mac"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  [REMOTE] The test process will:"
echo "           - Run in background (survives SSH disconnect)"
echo "           - Test local network + internet connectivity every 10s"
echo "           - Log results to /tmp/repro.log"
echo ""
echo "  [REMOTE] Running first test cycle BEFORE SSH disconnect..."
echo "           (This establishes baseline - both should work)"
echo ""
echo "┌─────────────────── REMOTE OUTPUT ───────────────────┐"
ssh -t "$REMOTE" "/tmp/start.sh"
echo "└─────────────────────────────────────────────────────┘"
echo ""

# ─────────────────────────────────────────────────────────────────────
# STEP 4: Wait for post-disconnect test
# ─────────────────────────────────────────────────────────────────────
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 4/5: SSH disconnected - waiting for post-disconnect test"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  [LOCAL]  SSH session has ended."
echo "  [REMOTE] Test process is still running in background."
echo "  [REMOTE] It will run another test cycle without SSH."
echo ""
echo "  [LOCAL]  Waiting 45 seconds..."
echo "           - 10s for test loop interval"
echo "           - 30s for macOS permission dialog delay (per TN3179)"
echo "           - 5s buffer"
echo ""
echo "  ⏳ If local network fails, check remote Mac for permission dialog!"
echo ""

for i in {45..1}; do
    printf "\r  [LOCAL]  Waiting... %2d seconds remaining " "$i"
    sleep 1
done
echo ""
echo ""

# ─────────────────────────────────────────────────────────────────────
# STEP 5: Check results
# ─────────────────────────────────────────────────────────────────────
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 5/5: Fetching results from remote Mac"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "┌─────────────── POST-DISCONNECT RESULTS ─────────────┐"
ssh "$REMOTE" "tail -60 /tmp/repro.log"
echo "└─────────────────────────────────────────────────────┘"
echo ""

# ─────────────────────────────────────────────────────────────────────
# Cleanup
# ─────────────────────────────────────────────────────────────────────
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Cleanup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  [REMOTE] Stopping test process..."
ssh "$REMOTE" "kill \$(cat /tmp/repro.pid) 2>/dev/null || true"
echo "  [REMOTE] Removing temporary files..."
ssh "$REMOTE" "rm -f /tmp/repro /tmp/repro.c /tmp/repro.pid /tmp/start.sh"
echo "  ✓ Done (log preserved at $REMOTE:/tmp/repro.log)"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "EXPECTED RESULT (if bug present):"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  BEFORE disconnect: ✅ LOCAL connected,  ✅ INTERNET connected"
echo "  AFTER disconnect:  ❌ LOCAL failed,     ✅ INTERNET connected"
echo ""
