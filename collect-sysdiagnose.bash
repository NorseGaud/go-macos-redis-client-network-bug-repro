#!/bin/bash
set -exo pipefail
# collect-sysdiagnose.sh - Collect sysdiagnose from all machines involved in reproduction
#
# Usage: ./collect-sysdiagnose.sh <remote-mac> <service-host>
#
# Example: ./collect-sysdiagnose.sh veertu@10.8.1.131 veertu@10.8.100.100
#
# This collects sysdiagnose from:
#   1. Local machine (this machine)
#   2. Remote Mac (where the test process runs)
#   3. Service host (where Redis/target service runs)

# ─────────────────────────────────────────────────────────────────────
# Parse arguments
# ─────────────────────────────────────────────────────────────────────
REMOTE_MAC="$1"
SERVICE_HOST="$2"

if [[ -z "$REMOTE_MAC" ]]; then
    echo "Usage: $0 <remote-mac> [service-host]"
    echo ""
    echo "Examples:"
    echo "  $0 veertu@10.8.1.131 veertu@10.8.100.100"
    echo "  $0 veertu@10.8.1.131                      # Skip service host"
    echo ""
    echo "This script collects sysdiagnose files from:"
    echo "  1. Local machine (this machine)"
    echo "  2. Remote Mac (where test process runs)"
    echo "  3. Service host (optional - where Redis runs)"
    exit 1
fi

# Output directory
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_DIR="$HOME/Desktop/sysdiagnose_collection_$TIMESTAMP"
mkdir -p "$OUTPUT_DIR"

echo ""
echo "┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓"
echo "┃  Sysdiagnose Collection for Apple Support                      ┃"
echo "┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛"
echo ""
echo "Machines to collect from:"
echo "  1. LOCAL:        $(hostname) (this machine)"
echo "  2. REMOTE MAC:   $REMOTE_MAC"
if [[ -n "$SERVICE_HOST" ]]; then
    echo "  3. SERVICE HOST: $SERVICE_HOST"
else
    echo "  3. SERVICE HOST: (skipped)"
fi
echo ""
echo "Output directory: $OUTPUT_DIR"
echo ""
echo "⚠️  NOTE: sysdiagnose requires sudo and takes 5-10 minutes per machine."
echo "⚠️  You may be prompted for passwords multiple times."
echo ""
read -p "Press Enter to continue (or Ctrl+C to cancel)..."
echo ""

# ─────────────────────────────────────────────────────────────────────
# Function to run sysdiagnose on a remote machine
# ─────────────────────────────────────────────────────────────────────
collect_remote_sysdiagnose() {
    local HOST="$1"
    local LABEL="$2"
    local OUTPUT_SUBDIR="$OUTPUT_DIR/$LABEL"
    
    mkdir -p "$OUTPUT_SUBDIR"
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "[$LABEL] Collecting sysdiagnose from: $HOST"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  [REMOTE] Checking connectivity to $HOST..."
    
    if ! ssh -o ConnectTimeout=10 "$HOST" "echo 'Connected successfully'" 2>/dev/null; then
        echo "  ❌ Cannot connect to $HOST - skipping"
        echo "$HOST: FAILED - could not connect" > "$OUTPUT_SUBDIR/ERROR.txt"
        return 1
    fi
    
    echo "  [REMOTE] Running sysdiagnose on $HOST..."
    echo "           This will take 5-10 minutes. Please wait..."
    echo ""
    
    # Run sysdiagnose on remote machine
    # -f: specify output directory
    # -b: run in background mode (non-interactive)
    ssh -t "$HOST" "sudo sysdiagnose -f /tmp -b" || {
        echo "  ❌ sysdiagnose failed on $HOST"
        echo "$HOST: FAILED - sysdiagnose error" > "$OUTPUT_SUBDIR/ERROR.txt"
        return 1
    }
    
    echo ""
    echo "  [REMOTE] Finding the generated sysdiagnose file..."
    
    # Find the most recent sysdiagnose file
    REMOTE_FILE=$(ssh "$HOST" "ls -t /tmp/sysdiagnose_*.tar.gz 2>/dev/null | head -1")
    
    if [[ -z "$REMOTE_FILE" ]]; then
        echo "  ❌ Could not find sysdiagnose file on $HOST"
        echo "$HOST: FAILED - no output file found" > "$OUTPUT_SUBDIR/ERROR.txt"
        return 1
    fi
    
    echo "  [REMOTE] Found: $REMOTE_FILE"
    echo "  [LOCAL]  Downloading to $OUTPUT_SUBDIR/..."
    
    scp "$HOST:$REMOTE_FILE" "$OUTPUT_SUBDIR/" || {
        echo "  ❌ Failed to download sysdiagnose from $HOST"
        return 1
    }
    
    echo "  [REMOTE] Cleaning up remote file..."
    ssh "$HOST" "sudo rm -f '$REMOTE_FILE'"
    
    echo "  ✅ Done: $LABEL"
    echo ""
}

# ─────────────────────────────────────────────────────────────────────
# STEP 1: Local machine sysdiagnose
# ─────────────────────────────────────────────────────────────────────
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "[1_LOCAL] Collecting sysdiagnose from: $(hostname) (this machine)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  [LOCAL] Running sysdiagnose locally..."
echo "          This will take 5-10 minutes. Please wait..."
echo ""

LOCAL_SUBDIR="$OUTPUT_DIR/1_local_$(hostname)"
mkdir -p "$LOCAL_SUBDIR"

sudo sysdiagnose -f /tmp -b || {
    echo "  ❌ Local sysdiagnose failed"
    echo "LOCAL: FAILED - sysdiagnose error" > "$LOCAL_SUBDIR/ERROR.txt"
}

# Find and move the local sysdiagnose file
LOCAL_FILE=$(ls -t /tmp/sysdiagnose_*.tar.gz 2>/dev/null | head -1)

if [[ -n "$LOCAL_FILE" ]]; then
    echo ""
    echo "  [LOCAL] Found: $LOCAL_FILE"
    echo "  [LOCAL] Moving to $LOCAL_SUBDIR/"
    sudo mv "$LOCAL_FILE" "$LOCAL_SUBDIR/"
    sudo chown "$USER" "$LOCAL_SUBDIR"/*.tar.gz
    echo "  ✅ Done: LOCAL"
else
    echo "  ❌ Could not find local sysdiagnose file"
fi
echo ""

# ─────────────────────────────────────────────────────────────────────
# STEP 2: Remote Mac sysdiagnose
# ─────────────────────────────────────────────────────────────────────
collect_remote_sysdiagnose "$REMOTE_MAC" "2_remote_mac"

# ─────────────────────────────────────────────────────────────────────
# STEP 3: Service host sysdiagnose (if provided)
# ─────────────────────────────────────────────────────────────────────
if [[ -n "$SERVICE_HOST" ]]; then
    collect_remote_sysdiagnose "$SERVICE_HOST" "3_service_host"
else
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "[3_SERVICE_HOST] Skipped (no service host specified)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
fi

# ─────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────
echo ""
echo "┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓"
echo "┃  Collection Complete                                           ┃"
echo "┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛"
echo ""
echo "Output directory: $OUTPUT_DIR"
echo ""
echo "Contents:"
ls -la "$OUTPUT_DIR"
echo ""
echo "Files collected:"
find "$OUTPUT_DIR" -name "*.tar.gz" -exec ls -lh {} \;
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Next steps:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  1. Zip the entire folder for Apple Support:"
echo "     zip -r sysdiagnose_collection.zip '$OUTPUT_DIR'"
echo ""
echo "  2. Upload to your Apple Feedback report or share via"
echo "     the method requested by Apple Support."
echo ""
echo "  ⚠️  These files contain sensitive system information."
echo "     Only share with Apple Support."
echo ""
