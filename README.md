# macOS Networking Bug: "no route to host" After SSH Disconnect

**UPDATE**: After back and forth with Apple, the logs were showing:

```
2026-01-07 15:07:47.292 I  UserEventAgent[106:af8072] [com.apple.networkextension:] Got local network blocked notification: pid: 28122, uuid: 7B4C4BEF-2590-36B3-87B9-A55C3A91AF1F, bundle_id: (null)
```

The solution they provided was to run the following commands:

```
sudo defaults write com.apple.network.local-network AllowedEthernetLocalNetworkAddresses -array "10.8.0.0/16"
sudo defaults write com.apple.network.local-network AllowedWiFiLocalNetworkAddresses -array "10.8.0.0/16"
defaults write com.apple.network.local-network AllowedEthernetLocalNetworkAddresses -array "10.8.0.0/16"
defaults write com.apple.network.local-network AllowedWiFiLocalNetworkAddresses -array "10.8.0.0/16"
```

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

## Apple Feedback (TN3179)

Apple's response indicates this may be related to **Local Network Privacy** (introduced in macOS 15):

> macOS fails to display the local network alert when a process with a very short lifespan performs a local network operation (FB16131937). For example, if you create a launchd agent that performs a local network operation and immediately exits when that fails, macOS won't display the local network alert. To work around this, update your code to not exit immediately after a local network operation fails.

See: https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy/

The system logs show the issue:
```
Got local network blocked notification: pid: 2966, uuid: ..., bundle_id: (null)
Failed to get the signing identifier for 2966: No such process
LocalNetwork: did not find bundle ID for UUID ...
Failed to find bundle ID, ignoring
```

Key observations:
- The process has **no bundle ID** (`bundle_id: (null)`)
- By the time `UserEventAgent` processes the block event, the process context is lost
- Without a bundle ID, macOS cannot associate the permission with the app

## Related

- [Apple TN3179: Understanding Local Network Privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy/)
- Apple Feedback: FB16131937 (short-lived process issue)
