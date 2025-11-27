// go-macos-network-repro
// Reproduces a Go networking issue on macOS where TCP connections to local network
// addresses fail with "no route to host" after the SSH session that started the
// process ends, even though system tools (ping, nc) work fine.
//
// Build: go build -o network-test .
// Run via SSH: ssh user@host "/tmp/start-test.bash"

package main

import (
	"context"
	"fmt"
	"net"
	"net/http"
	"os"
	"os/exec"
	"runtime"
	"syscall"
	"time"

	"github.com/redis/go-redis/v9"
)

const (
	// Target addresses for testing
	redisHost     = "10.8.100.100"
	redisPort     = 6379
	redisAddr     = "10.8.100.100:6379"
	googleAddr    = "google.com:443"
	googleDNSAddr = "8.8.8.8:53"

	// Test interval
	testInterval = 10 * time.Second
)

var redisClient *redis.Client

func main() {
	fmt.Println("===========================================")
	fmt.Println("Go macOS Network Reproduction Test")
	fmt.Println("===========================================")
	fmt.Printf("PID: %d\n", os.Getpid())
	fmt.Printf("PPID: %d\n", os.Getppid())
	fmt.Printf("OS: %s\n", runtime.GOOS)
	fmt.Printf("Arch: %s\n", runtime.GOARCH)
	fmt.Printf("Target Redis: %s\n", redisAddr)
	fmt.Println("===========================================")
	fmt.Println()
	fmt.Println("This test will run every 10 seconds.")
	fmt.Println("After starting via SSH, disconnect the SSH session.")
	fmt.Println("Watch the logs to see Go networking fail while system tools succeed.")
	fmt.Println()

	// Initialize Redis client
	redisClient = redis.NewClient(&redis.Options{
		Addr:        redisAddr,
		DialTimeout: 5 * time.Second,
	})

	// Run test immediately
	runTest()

	// Then run periodically
	ticker := time.NewTicker(testInterval)
	defer ticker.Stop()

	for range ticker.C {
		runTest()
	}
}

func runTest() {
	fmt.Println("-------------------------------------------")
	fmt.Printf("Test run at: %s\n", time.Now().Format(time.RFC3339))
	fmt.Println("-------------------------------------------")

	// Get process info
	printProcessInfo()

	// Test 1: go-redis client PING - this will fail after SSH disconnect
	fmt.Println("\n[TEST 1] go-redis client PING to Redis...")
	testGoRedisPing()

	// Test 2: go-redis client SET/GET - this will fail after SSH disconnect
	fmt.Println("\n[TEST 2] go-redis client SET/GET...")
	testGoRedisSetGet()

	// Test 3: Go net.Dial to Redis (local network) - this will fail after SSH disconnect
	fmt.Println("\n[TEST 3] Go net.DialTimeout to Redis (local network)...")
	testGoDialRedis()

	// Test 4: Go net.Dial to Google (internet) - this will succeed
	fmt.Println("\n[TEST 4] Go net.DialTimeout to Google (internet)...")
	testGoDialGoogle()

	// Test 5: Go net.Dial to 8.8.8.8 (internet IP) - this will succeed
	fmt.Println("\n[TEST 5] Go net.DialTimeout to 8.8.8.8 (internet IP)...")
	testGoDialGoogleDNS()

	// Test 6: System ping to Redis host - this will succeed!
	fmt.Println("\n[TEST 6] System ping to Redis host...")
	testSystemPing()

	// Test 7: System nc (netcat) to Redis - this will succeed!
	fmt.Println("\n[TEST 7] System nc (netcat) to Redis...")
	testSystemNetcat()

	// Test 8: Go with explicit interface binding - still fails!
	fmt.Println("\n[TEST 8] Go net.Dial with explicit en0 binding...")
	testGoDialWithInterfaceBinding()

	// Test 9: Check route
	fmt.Println("\n[TEST 9] Route to Redis host...")
	testRouteGet()

	// Test 10: Check ARP
	fmt.Println("\n[TEST 10] ARP entry for Redis host...")
	testArp()

	fmt.Println("\n-------------------------------------------")
	fmt.Println("Test complete. Waiting for next run...")
	fmt.Println("-------------------------------------------")
	fmt.Println()
}

func printProcessInfo() {
	cmd := exec.Command("sh", "-c", "ps -o pid,ppid,pgid,sess,tty,comm -p $$")
	out, _ := cmd.CombinedOutput()
	fmt.Printf("Process info:\n%s\n", string(out))

	ttyCmd := exec.Command("tty")
	ttyOut, _ := ttyCmd.CombinedOutput()
	fmt.Printf("TTY: %s", string(ttyOut))
}

func testGoRedisPing() {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	start := time.Now()
	result, err := redisClient.Ping(ctx).Result()
	latency := time.Since(start)

	if err != nil {
		fmt.Printf("  ❌ FAILED: %v (latency: %v)\n", err, latency)
	} else {
		fmt.Printf("  ✅ SUCCEEDED: %s (latency: %v)\n", result, latency)
	}
}

func testGoRedisSetGet() {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	testKey := "go-macos-network-repro-test"
	testValue := fmt.Sprintf("test-value-%d", time.Now().Unix())

	// SET
	start := time.Now()
	err := redisClient.Set(ctx, testKey, testValue, 60*time.Second).Err()
	setLatency := time.Since(start)

	if err != nil {
		fmt.Printf("  ❌ SET FAILED: %v (latency: %v)\n", err, setLatency)
		return
	}
	fmt.Printf("  ✅ SET SUCCEEDED (latency: %v)\n", setLatency)

	// GET
	start = time.Now()
	result, err := redisClient.Get(ctx, testKey).Result()
	getLatency := time.Since(start)

	if err != nil {
		fmt.Printf("  ❌ GET FAILED: %v (latency: %v)\n", err, getLatency)
	} else {
		fmt.Printf("  ✅ GET SUCCEEDED: %s (latency: %v)\n", result, getLatency)
	}
}

func testGoDialRedis() {
	start := time.Now()
	conn, err := net.DialTimeout("tcp", redisAddr, 5*time.Second)
	latency := time.Since(start)

	if err != nil {
		fmt.Printf("  ❌ FAILED: %v (latency: %v)\n", err, latency)
	} else {
		conn.Close()
		fmt.Printf("  ✅ SUCCEEDED (latency: %v)\n", latency)
	}
}

func testGoDialGoogle() {
	start := time.Now()
	conn, err := net.DialTimeout("tcp", googleAddr, 5*time.Second)
	latency := time.Since(start)

	if err != nil {
		fmt.Printf("  ❌ FAILED: %v (latency: %v)\n", err, latency)
	} else {
		conn.Close()
		fmt.Printf("  ✅ SUCCEEDED (latency: %v)\n", latency)
	}
}

func testGoDialGoogleDNS() {
	start := time.Now()
	conn, err := net.DialTimeout("tcp", googleDNSAddr, 5*time.Second)
	latency := time.Since(start)

	if err != nil {
		fmt.Printf("  ❌ FAILED: %v (latency: %v)\n", err, latency)
	} else {
		conn.Close()
		fmt.Printf("  ✅ SUCCEEDED (latency: %v)\n", latency)
	}
}

func testSystemPing() {
	cmd := exec.Command("ping", "-c", "1", "-t", "2", redisHost)
	out, err := cmd.CombinedOutput()

	if err != nil {
		fmt.Printf("  ❌ FAILED: %v\n  Output: %s\n", err, string(out))
	} else {
		fmt.Printf("  ✅ SUCCEEDED\n")
	}
}

func testSystemNetcat() {
	cmd := exec.Command("nc", "-z", "-w", "2", redisHost, fmt.Sprintf("%d", redisPort))
	out, err := cmd.CombinedOutput()

	if err != nil {
		fmt.Printf("  ❌ FAILED: %v\n  Output: %s\n", err, string(out))
	} else {
		fmt.Printf("  ✅ SUCCEEDED\n")
	}
}

func testGoDialWithInterfaceBinding() {
	// Get en0's IP address
	iface, err := net.InterfaceByName("en0")
	if err != nil {
		fmt.Printf("  ❌ Failed to get en0 interface: %v\n", err)
		return
	}

	addrs, err := iface.Addrs()
	if err != nil {
		fmt.Printf("  ❌ Failed to get en0 addresses: %v\n", err)
		return
	}

	var localIP net.IP
	for _, addr := range addrs {
		if ipnet, ok := addr.(*net.IPNet); ok && ipnet.IP.To4() != nil {
			localIP = ipnet.IP
			break
		}
	}

	if localIP == nil {
		fmt.Printf("  ❌ No IPv4 address found on en0\n")
		return
	}

	fmt.Printf("  Using local IP: %s, interface index: %d\n", localIP, iface.Index)

	dialer := &net.Dialer{
		Timeout:   5 * time.Second,
		LocalAddr: &net.TCPAddr{IP: localIP, Port: 0},
		Control: func(network, address string, c syscall.RawConn) error {
			var sockErr error
			err := c.Control(func(fd uintptr) {
				// IP_BOUND_IF = 25 on macOS
				sockErr = syscall.SetsockoptInt(int(fd), syscall.IPPROTO_IP, 25, iface.Index)
				if sockErr != nil {
					fmt.Printf("  Failed to set IP_BOUND_IF: %v\n", sockErr)
				} else {
					fmt.Printf("  Set IP_BOUND_IF to en0 (index %d)\n", iface.Index)
				}
			})
			if err != nil {
				return err
			}
			return sockErr
		},
	}

	start := time.Now()
	conn, err := dialer.DialContext(context.Background(), "tcp", redisAddr)
	latency := time.Since(start)

	if err != nil {
		fmt.Printf("  ❌ FAILED: %v (latency: %v)\n", err, latency)
	} else {
		conn.Close()
		fmt.Printf("  ✅ SUCCEEDED (latency: %v)\n", latency)
	}
}

func testRouteGet() {
	cmd := exec.Command("route", "-n", "get", redisHost)
	out, err := cmd.CombinedOutput()

	if err != nil {
		fmt.Printf("  ❌ FAILED: %v\n", err)
	} else {
		fmt.Printf("  Output:\n%s\n", string(out))
	}
}

func testArp() {
	cmd := exec.Command("arp", "-n", redisHost)
	out, err := cmd.CombinedOutput()

	if err != nil {
		fmt.Printf("  ❌ FAILED: %v\n  Output: %s\n", err, string(out))
	} else {
		fmt.Printf("  Output: %s\n", string(out))
	}
}

// HTTPTest tests if HTTP requests work (uses Go's http package)
func testHTTPGet() {
	client := &http.Client{Timeout: 5 * time.Second}
	start := time.Now()
	resp, err := client.Get("https://www.google.com")
	latency := time.Since(start)

	if err != nil {
		fmt.Printf("  ❌ FAILED: %v (latency: %v)\n", err, latency)
	} else {
		resp.Body.Close()
		fmt.Printf("  ✅ SUCCEEDED (status: %d, latency: %v)\n", resp.StatusCode, latency)
	}
}
