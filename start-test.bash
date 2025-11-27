#!/bin/bash
# start-test.bash
# This script is copied to the remote host and executed there.
# It starts the network test binary with nohup and disown, then exits.
# This simulates the exact scenario where Go networking fails after
# the parent bash script exits.

set -eo pipefail

SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
BINARY_PATH="/tmp/network-test"
LOG_PATH="/tmp/network-test.log"
PID_FILE="/tmp/network-test.pid"

echo "==========================================="
echo "START ${SCRIPT_NAME}"
echo "==========================================="
echo "PID: $$"
echo "PPID: $PPID"
echo "Binary: ${BINARY_PATH}"
echo "Log: ${LOG_PATH}"
echo ""

# Clean up any existing process
if [[ -f "${PID_FILE}" ]]; then
    OLD_PID=$(cat "${PID_FILE}")
    if ps -p "${OLD_PID}" > /dev/null 2>&1; then
        echo "Killing existing process: ${OLD_PID}"
        kill "${OLD_PID}" 2>/dev/null || true
        sleep 1
    fi
    rm -f "${PID_FILE}"
fi

# Clean up old log
rm -f "${LOG_PATH}"

# Make sure binary exists and is executable
if [[ ! -x "${BINARY_PATH}" ]]; then
    echo "ERROR: Binary not found or not executable: ${BINARY_PATH}"
    exit 1
fi

echo "Starting network test binary..."

# Start the binary with nohup, background it, and disown
# This is the exact pattern that triggers the Go networking issue
nohup "${BINARY_PATH}" > "${LOG_PATH}" 2>&1 &
disown

# Get the PID
NETWORK_TEST_PID=$!
echo "${NETWORK_TEST_PID}" > "${PID_FILE}"

echo "Process started with PID: ${NETWORK_TEST_PID}"

# Wait a moment for it to start
sleep 10

# Verify it's running
if ps -p "${NETWORK_TEST_PID}" > /dev/null 2>&1; then
    echo "Process is running"
else
    echo "ERROR: Process failed to start"
    echo "Log output:"
    cat "${LOG_PATH}" 2>/dev/null || echo "(no log file)"
    exit 1
fi

# Show initial log output
echo ""
echo "Initial log output:"
echo "-------------------------------------------"
head -80 "${LOG_PATH}" 2>/dev/null || echo "(waiting for output...)"
echo "-------------------------------------------"

echo ""
echo "==========================================="
echo "END ${SCRIPT_NAME}"
echo "==========================================="
echo ""
echo "The script is now exiting."
echo "This is when the Go networking issue manifests."
echo ""
echo "To view ongoing logs:"
echo "  tail -f ${LOG_PATH}"
echo ""
echo "To stop the test:"
echo "  kill \$(cat ${PID_FILE})"
echo ""

# Exit - this is when the parent process ends and triggers the issue
exit 0

