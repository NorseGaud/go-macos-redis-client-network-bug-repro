# Go macOS Network Issue Reproduction

This reproduces a Go networking bug/limitation on macOS where TCP connections to local network addresses fail with "no route to host" after the SSH session that started the process ends.

## The Issue

When a Go process is started via SSH → bash script → nohup/disown, after the parent bash script exits:

| Test | Result |
|------|--------|
| go-redis client PING | ❌ **FAILS** - "no route to host" |
| go-redis client SET/GET | ❌ **FAILS** - "no route to host" |
| Go `net.Dial` to local network (10.8.x.x) | ❌ **FAILS** - "no route to host" |
| Go `net.Dial` to internet (google.com) | ✅ Works |
| Go `net.Dial` to internet IP (8.8.8.8) | ✅ Works |
| System `ping` to local network | ✅ Works |
| System `nc` (netcat) to local network | ✅ Works |

**Key observation**: The OS networking works perfectly (ping, nc succeed). Only Go's networking fails, and only for local network addresses.

## Environment

- **OS**: macOS (tested on Apple Silicon M1/M2)
- **Go**: 1.21+
- **Network**: Local LAN with addresses in 10.8.x.x range
- **Redis**: 10.8.100.100:6379
- **Route type**: Interface-scoped (`IFSCOPE` flag) on en0

## Root Cause

The route to the local network has the `IFSCOPE` flag:
```
route to: 10.8.100.100
interface: en0
flags: <UP,HOST,DONE,LLINFO,WASCLONED,IFSCOPE,IFREF>
```

When the SSH session ends and the process is orphaned:
- System tools (ping, nc) handle IFSCOPE routes correctly
- Go's networking does not properly use IFSCOPE routes for orphaned processes
- Internet addresses work because they use different routing paths

## Reproduction Steps

1. **Prerequisites**:
   - macOS host accessible via SSH at `veertu@10.8.1.131` (configured in `~/.ssh/config`)
   - Redis running at `10.8.100.100:6379`

2. **Run the reproduction**:
   ```bash
   ./run-repro.bash
   ```

3. **Wait ~10 seconds** for the first test cycle after SSH disconnects

4. **View the logs**:
   ```bash
   ssh veertu@10.8.1.131 'tail -f /tmp/network-test.log'
   ```

5. **Expected output** (after parent script exits):
   ```
   [TEST 1] go-redis client PING to Redis...
     ❌ FAILED: dial tcp 10.8.100.100:6379: connect: no route to host

   [TEST 2] go-redis client SET/GET...
     ❌ SET FAILED: dial tcp 10.8.100.100:6379: connect: no route to host

   [TEST 3] Go net.DialTimeout to Redis (local network)...
     ❌ FAILED: dial tcp 10.8.100.100:6379: connect: no route to host

   [TEST 4] Go net.DialTimeout to Google (internet)...
     ✅ SUCCEEDED

   [TEST 6] System ping to Redis host...
     ✅ SUCCEEDED

   [TEST 7] System nc (netcat) to Redis...
     ✅ SUCCEEDED
   ```

## How It Works

The reproduction uses two scripts:

1. **`run-repro.bash`** (wrapper - runs locally):
   - Builds the Go binary for macOS ARM64
   - SCPs the binary and start script to the remote host
   - Executes the start script via SSH

2. **`start-test.bash`** (inner - runs on remote host):
   - Starts the Go binary with `nohup ... & disown`
   - **Exits** - this is when the issue manifests
   - The Go process continues running but can't reach local network

## Things That Don't Fix It

- `nohup` - does not help
- `disown` - does not help  
- `setsid` - does not help
- Removing `-t` flag from SSH - does not help
- Explicit `LocalAddr` binding to en0's IP - does not help
- Setting `IP_BOUND_IF` socket option - does not help

## Workarounds

1. **Keep SSH session alive**: Don't let the SSH session end (e.g., `tail -f` the logs)
2. **Use screen/tmux**: Start the process in a detached screen session
3. **Use launchd**: Run the process as a proper macOS service via launchd
4. **Proxy through nc**: Shell out to `nc` for local network connections (hacky)

## Files

- `main.go` - Go test program using go-redis client
- `go.mod` / `go.sum` - Go module files
- `run-repro.bash` - Wrapper script (runs locally)
- `start-test.bash` - Inner script (copied to and runs on remote host)
- `README.md` - This file

## Cleanup

To stop the test on the remote host:
```bash
ssh veertu@10.8.1.131 'pkill -f network-test'
```
