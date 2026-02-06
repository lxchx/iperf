#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>
/*
 * A small LD_PRELOAD shim used by tests to simulate loss / injection of the
 * 4-byte UDP "connect" control messages.  This lets us regression-test UDP
 * handshake retry behavior deterministically.
 *
 * Controls (env vars):
 * - IPERF_SHIM_DROP_FIRST_UDP_4B_WRITE=1
 *     Drop (pretend to send) the first 4-byte write() on a UDP socket.
 *     On the client this corresponds to UDP_CONNECT_MSG; on the server it
 *     corresponds to UDP_CONNECT_REPLY.
 *
 * - IPERF_SHIM_INJECT_UDP_CONNECT_MSG_AFTER_FIRST_DATA_WRITE=1
 *     After the first UDP write() larger than 4 bytes, inject a 4-byte
 *     UDP_CONNECT_MSG.  Used to simulate a late/duplicate control message
 *     during the data phase.
 */

/* Keep these consistent with src/iperf.h */
#ifndef BYTE_ORDER
#if defined(__BYTE_ORDER)
#define BYTE_ORDER __BYTE_ORDER
#elif defined(__BYTE_ORDER__)
#define BYTE_ORDER __BYTE_ORDER__
#endif
#endif
#ifndef BIG_ENDIAN
#if defined(__BIG_ENDIAN)
#define BIG_ENDIAN __BIG_ENDIAN
#elif defined(__ORDER_BIG_ENDIAN__)
#define BIG_ENDIAN __ORDER_BIG_ENDIAN__
#endif
#endif

#if BYTE_ORDER == BIG_ENDIAN
#define UDP_CONNECT_MSG 0x39383736
#define UDP_CONNECT_REPLY 0x36373839
#else
#define UDP_CONNECT_MSG 0x36373839
#define UDP_CONNECT_REPLY 0x39383736
#endif

static ssize_t (*real_write)(int, const void *, size_t);
static __thread int in_write;

static int
env_flag_set(const char *name)
{
    const char *v = getenv(name);
    if (v == NULL)
        return 0;
    if (v[0] == '\0')
        return 0;
    if (strcmp(v, "0") == 0)
        return 0;
    return 1;
}

static int
is_udp_socket(int fd)
{
    int type = 0;
    socklen_t len = sizeof(type);
    if (getsockopt(fd, SOL_SOCKET, SO_TYPE, &type, &len) != 0)
        return 0;
    return type == SOCK_DGRAM;
}

ssize_t
write(int fd, const void *buf, size_t count)
{
    static int dropped_once;
    static int injected_once;

    if (!real_write)
        real_write = dlsym(RTLD_NEXT, "write");

    if (in_write)
        return real_write(fd, buf, count);

    if (env_flag_set("IPERF_SHIM_DROP_FIRST_UDP_4B_WRITE") && !dropped_once &&
        is_udp_socket(fd) && count == 4) {
        dropped_once = 1;
        return (ssize_t)count;
    }

    in_write = 1;
    ssize_t r = real_write(fd, buf, count);

    if (r > 0 && env_flag_set("IPERF_SHIM_INJECT_UDP_CONNECT_MSG_AFTER_FIRST_DATA_WRITE") &&
        !injected_once && is_udp_socket(fd) && count > 4) {
        injected_once = 1;
        unsigned int msg = UDP_CONNECT_MSG;
        (void) real_write(fd, &msg, sizeof(msg));
    }

    in_write = 0;
    return r;
}

