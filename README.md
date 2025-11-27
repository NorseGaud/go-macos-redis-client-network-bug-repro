# macOS Networking Bug: "no route to host" After SSH Disconnect

## Summary

On macOS, when a process is started via SSH and the SSH session disconnects,
`connect()` fails to reach **local network** addresses with EHOSTUNREACH (65),
while **internet** addresses continue to work.

## Reproduction

### Prerequisites

1. A remote macOS machine accessible via SSH
2. A TCP service on your local network (e.g., Redis on port 6379)
   - Must be on a **different host** than the remote Mac
   - Must be reachable from the remote Mac

### Steps

1. Edit `repro.c` and set your local network target:
   ```c
   #define LOCAL_IP   "10.8.100.100"  // Change to your LAN IP
   #define LOCAL_PORT 6379            // Change to your port
   ```

2. Run:
   ```bash
   ./run.sh user@remote-mac
   ```

### Expected Result

**Before SSH disconnect:**
```
[TEST 1] C connect() to LOCAL network...
  ✅ LOCAL: connected

[TEST 2] C connect() to INTERNET...
  ✅ INTERNET: connected
```

**After SSH disconnect:**
```
[TEST 1] C connect() to LOCAL network...
  ❌ LOCAL: connect failed: No route to host (errno 65)

[TEST 2] C connect() to INTERNET...
  ✅ INTERNET: connected

[TEST 3] System ping to local...
  ✅ ping succeeded
```

## Analysis

The route to the local network has the `IFSCOPE` flag:
```
flags: <UP,HOST,DONE,LLINFO,WASCLONED,IFSCOPE,IFREF>
```

When SSH disconnects and the process loses its controlling terminal,
macOS appears to invalidate the process's network interface context,
causing interface-scoped route lookups to fail.

- **Internet works**: Routes via default gateway aren't interface-scoped
- **Ping works**: Spawned as new process with fresh network context
- **Local fails**: Interface-scoped routes require valid context

## Files

```
repro.c   - C reproduction (~140 lines, zero dependencies)
run.sh    - Run from your local machine
start.sh  - Runs on the remote macOS host
```

## Workarounds

1. Use `setsid` before starting the process
2. Use `launchd` instead of SSH + nohup
3. Use `screen -dmS name ./binary`
