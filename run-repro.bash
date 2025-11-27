#!/bin/bash
# run-repro.bash
# Wrapper script that reproduces the Go + macOS + SSH + interface-scoped routing issue
#
# This script:
# 1. Builds the Go test binary for macOS ARM64
# 2. SCPs the binary and start script to the remote host
# 3. Executes the start script via SSH (which starts the binary with nohup/disown)
# 4. The start script exits, SSH session ends
# 5. The Go process continues running but networking to local network fails
#
# Usage: ./run-repro.bash
# Usage: ./run-repro.bash --clean   # Just clean up any existing process

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REMOTE_HOST="veertu@10.8.1.131"
REMOTE_BINARY_PATH="/tmp/network-test"
REMOTE_SCRIPT_PATH="/tmp/start-test.bash"
LOG_PATH="/tmp/network-test.log"
PID_FILE="/tmp/network-test.pid"

# SSH options - uses ~/.ssh/config for connection settings
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"

# Cleanup function to kill remote process
cleanup_remote() {
    echo ""
    echo "Cleaning up remote process..."
    ssh ${SSH_OPTS} "${REMOTE_HOST}" "pkill -f network-test 2>/dev/null || true; rm -f ${PID_FILE}" 2>/dev/null || true
    echo "  Done"
}

# Handle --clean flag
if [[ "${1}" == "--clean" ]]; then
    echo "==========================================="
    echo "Cleaning up remote network-test process"
    echo "==========================================="
    cleanup_remote
    exit 0
fi

# Trap to clean up on script exit/interrupt
trap cleanup_remote EXIT

echo "==========================================="
echo "Go macOS Network Issue Reproduction"
echo "==========================================="
echo "Remote host: ${REMOTE_HOST}"
echo ""

# Step 0: Clean up any existing process
echo "[0/5] Cleaning up any existing process..."
ssh ${SSH_OPTS} "${REMOTE_HOST}" "pkill -f network-test 2>/dev/null || true; rm -f ${PID_FILE}" 2>/dev/null || true
echo "  Done"

# Step 1: Build the binary
echo ""
echo "[1/5] Building Go binary for macOS ARM64..."
cd "${SCRIPT_DIR}"

# Get dependencies
go mod download
go mod tidy

GOOS=darwin GOARCH=arm64 go build -o network-test .
echo "  Built: ${SCRIPT_DIR}/network-test"

# Step 2: Copy binary to remote host
echo ""
echo "[2/5] Copying binary to remote host..."
scp ${SSH_OPTS} "${SCRIPT_DIR}/network-test" "${REMOTE_HOST}:${REMOTE_BINARY_PATH}"
echo "  Copied to: ${REMOTE_HOST}:${REMOTE_BINARY_PATH}"

# Step 3: Copy start script to remote host
echo ""
echo "[3/5] Copying start script to remote host..."
scp ${SSH_OPTS} "${SCRIPT_DIR}/start-test.bash" "${REMOTE_HOST}:${REMOTE_SCRIPT_PATH}"
ssh ${SSH_OPTS} "${REMOTE_HOST}" "chmod +x ${REMOTE_SCRIPT_PATH}"
echo "  Copied to: ${REMOTE_HOST}:${REMOTE_SCRIPT_PATH}"

# Step 4: Execute the start script via SSH with -t (PTY allocation)
# The -t flag is important - it allocates a pseudo-terminal which affects process behavior
echo ""
echo "[4/5] Executing start script on remote host..."
echo "  Running: ssh -t ${REMOTE_HOST} ${REMOTE_SCRIPT_PATH}"
echo ""

# Remove the trap before starting - we don't want to clean up on successful completion
trap - EXIT

ssh -t ${SSH_OPTS} "${REMOTE_HOST}" "${REMOTE_SCRIPT_PATH}"

# Step 5: SSH session has ended, the process continues running
echo ""
echo "[5/5] SSH session has ended. The process continues running."
echo ""
echo "==========================================="
echo "REPRODUCTION COMPLETE"
echo "==========================================="
echo ""
echo "The test is now running on the remote host with the parent script exited."
echo "It runs network tests every 10 seconds."
echo ""
echo "EXPECTED BEHAVIOR (the bug):"
echo "  - go-redis PING/SET/GET: ❌ WILL FAIL with 'no route to host'"
echo "  - Go net.Dial to Redis: ❌ WILL FAIL with 'no route to host'"
echo "  - System ping/nc: ✅ WILL WORK"
echo "  - Go net.Dial to Google: ✅ WILL WORK"
echo ""
echo "To view the logs (wait ~10 seconds for the first failed test):"
echo "  ssh ${REMOTE_HOST} 'tail -f ${LOG_PATH}'"
echo ""
echo "To stop the test and clean up:"
echo "  ./run-repro.bash --clean"
echo "  # or manually:"
echo "  ssh ${REMOTE_HOST} 'pkill -f network-test'"
echo ""
echo "==========================================="
