/*
 * Minimal C reproduction of macOS networking issue
 * 
 * After losing controlling terminal (SSH disconnect), connect() fails
 * to local network addresses with EHOSTUNREACH (65), while internet
 * addresses continue to work.
 *
 * NOTE: Per Apple TN3179, macOS fails to display the local network alert
 * when a process with a very short lifespan performs a local network 
 * operation. We add delays after failures to allow the system to process
 * the block event and potentially show a permission dialog.
 * See: https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy/
 *
 * Compile: clang -o repro_c repro.c
 * Usage:   See README.md for reproduction steps
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <time.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <fcntl.h>

/* Change this to a local network IP on your LAN */
#define LOCAL_IP   "10.8.100.100"
#define LOCAL_PORT 6379

/* Internet address for comparison */
#define INET_IP    "8.8.8.8"
#define INET_PORT  53

/* Delay after local network failure to allow macOS to process block event */
#define POST_FAILURE_DELAY_SECS 30

int test_connect(const char *label, const char *ip, int port, int is_local) {
    int sock;
    struct sockaddr_in addr;
    int result;
    int failed = 0;
    
    sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock < 0) {
        printf("  ❌ %s: socket() failed: %s\n", label, strerror(errno));
        failed = 1;
        goto done;
    }
    
    /* Set non-blocking for timeout */
    fcntl(sock, F_SETFL, O_NONBLOCK);
    
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(port);
    inet_pton(AF_INET, ip, &addr.sin_addr);
    
    result = connect(sock, (struct sockaddr *)&addr, sizeof(addr));
    
    if (result == 0) {
        printf("  ✅ %s: connected immediately\n", label);
        close(sock);
        return 0;
    }
    
    if (errno == EINPROGRESS) {
        /* Wait for connection with timeout */
        fd_set wfds;
        struct timeval tv;
        int so_error;
        socklen_t len = sizeof(so_error);
        
        FD_ZERO(&wfds);
        FD_SET(sock, &wfds);
        tv.tv_sec = 5;
        tv.tv_usec = 0;
        
        result = select(sock + 1, NULL, &wfds, NULL, &tv);
        
        if (result > 0) {
            getsockopt(sock, SOL_SOCKET, SO_ERROR, &so_error, &len);
            if (so_error == 0) {
                printf("  ✅ %s: connected\n", label);
                close(sock);
                return 0;
            } else {
                printf("  ❌ %s: connect failed: %s (errno %d)\n", 
                       label, strerror(so_error), so_error);
                close(sock);
                failed = 1;
                goto done;
            }
        } else if (result == 0) {
            printf("  ❌ %s: connect timeout\n", label);
            close(sock);
            failed = 1;
            goto done;
        }
    }
    
    printf("  ❌ %s: connect failed: %s (errno %d)\n", 
           label, strerror(errno), errno);
    close(sock);
    failed = 1;

done:
    /*
     * Per Apple TN3179: macOS fails to display local network alert when a 
     * process exits too quickly after a local network operation fails.
     * We wait here to give UserEventAgent time to process the block event
     * and potentially show a permission dialog.
     */
    if (failed && is_local) {
        printf("  ⏳ Waiting %d seconds for macOS to process block event...\n", 
               POST_FAILURE_DELAY_SECS);
        printf("     (Check if a Local Network permission dialog appears)\n");
        sleep(POST_FAILURE_DELAY_SECS);
        printf("  ⏳ Wait complete.\n");
    }
    
    return failed ? -1 : 0;
}

static int test_cycle = 0;
static int had_tty = -1;  /* -1 = unknown, 0 = no, 1 = yes */

void run_tests(void) {
    time_t now;
    char timebuf[64];
    char *tty;
    int has_tty;
    
    test_cycle++;
    
    time(&now);
    strftime(timebuf, sizeof(timebuf), "%Y-%m-%d %H:%M:%S", localtime(&now));
    
    tty = ttyname(STDIN_FILENO);
    has_tty = (tty != NULL);
    
    printf("╔══════════════════════════════════════════════════════════════╗\n");
    printf("║  TEST CYCLE #%d                                               \n", test_cycle);
    printf("║  Time: %s                                    \n", timebuf);
    printf("╠══════════════════════════════════════════════════════════════╣\n");
    
    /* Detect TTY change (SSH disconnect) */
    if (had_tty == -1) {
        had_tty = has_tty;
        printf("║  TTY:  %s\n", tty ? tty : "(none - no controlling terminal)");
    } else if (had_tty == 1 && has_tty == 0) {
        printf("║  TTY:  *** CHANGED: was connected, now DETACHED ***\n");
        printf("║        (SSH session likely disconnected)\n");
        had_tty = 0;
    } else {
        printf("║  TTY:  %s\n", tty ? tty : "(none - no controlling terminal)");
    }
    
    printf("║  PID:  %d   PPID: %d\n", getpid(), getppid());
    printf("╚══════════════════════════════════════════════════════════════╝\n");
    
    printf("\n[TEST 1/3] connect() to LOCAL network %s:%d\n", LOCAL_IP, LOCAL_PORT);
    test_connect("LOCAL", LOCAL_IP, LOCAL_PORT, 1 /* is_local */);
    
    printf("\n[TEST 2/3] connect() to INTERNET %s:%d\n", INET_IP, INET_PORT);
    test_connect("INTERNET", INET_IP, INET_PORT, 0 /* is_local */);
    
    printf("\n[TEST 3/3] System ping to local network\n");
    char cmd[256];
    snprintf(cmd, sizeof(cmd), "ping -c 1 -t 2 %s >/dev/null 2>&1", LOCAL_IP);
    if (system(cmd) == 0) {
        printf("  ✅ ping succeeded (spawned as new process)\n");
    } else {
        printf("  ❌ ping failed\n");
    }
    
    printf("\n────────────────────────────────────────────────────────────────\n");
    printf("  CYCLE #%d SUMMARY:\n", test_cycle);
    printf("    Next test in 10 seconds...\n");
    printf("────────────────────────────────────────────────────────────────\n\n");
}

int main(void) {
    /* Disable buffering so output appears in log immediately */
    setvbuf(stdout, NULL, _IONBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);
    
    printf("\n");
    printf("┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓\n");
    printf("┃  macOS Local Network Bug - Test Process                        ┃\n");
    printf("┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫\n");
    printf("┃  PID:      %d\n", getpid());
    printf("┃  PPID:     %d\n", getppid());
    printf("┃  Local:    %s:%d\n", LOCAL_IP, LOCAL_PORT);
    printf("┃  Internet: %s:%d\n", INET_IP, INET_PORT);
    printf("┣━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┫\n");
    printf("┃  Running connectivity tests every 10 seconds.                  ┃\n");
    printf("┃  Watch for TTY change = SSH disconnect detected.               ┃\n");
    printf("┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛\n");
    printf("\n");
    
    while (1) {
        run_tests();
        sleep(10);
    }
    
    return 0;
}

