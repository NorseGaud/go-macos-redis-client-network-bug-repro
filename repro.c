/*
 * Minimal C reproduction of macOS networking issue
 * 
 * After losing controlling terminal (SSH disconnect), connect() fails
 * to local network addresses with EHOSTUNREACH (65), while internet
 * addresses continue to work.
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

int test_connect(const char *label, const char *ip, int port) {
    int sock;
    struct sockaddr_in addr;
    int result;
    
    sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock < 0) {
        printf("  ❌ %s: socket() failed: %s\n", label, strerror(errno));
        return -1;
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
                return -1;
            }
        } else if (result == 0) {
            printf("  ❌ %s: connect timeout\n", label);
            close(sock);
            return -1;
        }
    }
    
    printf("  ❌ %s: connect failed: %s (errno %d)\n", 
           label, strerror(errno), errno);
    close(sock);
    return -1;
}

void print_tty_info(void) {
    char *tty = ttyname(STDIN_FILENO);
    printf("TTY: %s\n", tty ? tty : "not a tty");
    printf("PID: %d, PPID: %d\n", getpid(), getppid());
}

void run_tests(void) {
    time_t now;
    char timebuf[64];
    
    time(&now);
    strftime(timebuf, sizeof(timebuf), "%Y-%m-%dT%H:%M:%S", localtime(&now));
    
    printf("-------------------------------------------\n");
    printf("Test at: %s\n", timebuf);
    printf("-------------------------------------------\n");
    
    print_tty_info();
    
    printf("\n[TEST 1] C connect() to LOCAL network (%s:%d)...\n", 
           LOCAL_IP, LOCAL_PORT);
    test_connect("LOCAL", LOCAL_IP, LOCAL_PORT);
    
    printf("\n[TEST 2] C connect() to INTERNET (%s:%d)...\n",
           INET_IP, INET_PORT);
    test_connect("INTERNET", INET_IP, INET_PORT);
    
    printf("\n[TEST 3] System ping to local...\n");
    char cmd[256];
    snprintf(cmd, sizeof(cmd), "ping -c 1 -t 2 %s >/dev/null 2>&1", LOCAL_IP);
    if (system(cmd) == 0) {
        printf("  ✅ ping succeeded\n");
    } else {
        printf("  ❌ ping failed\n");
    }
    
    printf("\n-------------------------------------------\n\n");
}

int main(void) {
    /* Disable buffering so output appears in log immediately */
    setvbuf(stdout, NULL, _IONBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);
    
    printf("============================================\n");
    printf("macOS Networking Issue - C Reproduction\n");
    printf("============================================\n");
    printf("PID: %d, PPID: %d\n", getpid(), getppid());
    printf("Local target: %s:%d\n", LOCAL_IP, LOCAL_PORT);
    printf("Internet target: %s:%d\n", INET_IP, INET_PORT);
    printf("============================================\n\n");
    printf("Running tests every 10 seconds.\n");
    printf("Start via SSH, then disconnect.\n\n");
    
    while (1) {
        run_tests();
        sleep(10);
    }
    
    return 0;
}

