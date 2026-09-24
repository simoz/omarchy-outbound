/* Linux ABI boundary. Ruby owns snapshot policy, identity and aggregation. */
#include <arpa/inet.h>
#include <errno.h>
#include <limits.h>
#include <linux/inet_diag.h>
#include <linux/netlink.h>
#include <linux/sock_diag.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

#define ROW_LIMIT 4096
struct outbound_row { struct inet_diag_msg diag; };
static struct outbound_row rows[ROW_LIMIT];
static int row_count, omitted;
static char row_json[512];

long outbound_monotonic_ms(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (long)t.tv_sec * 1000 + t.tv_nsec / 1000000;
}
static int failure(int error) {
    if (error == EPERM || error == EACCES) return -1;
    if (error == EAFNOSUPPORT || error == EPROTONOSUPPORT || error == ENOENT) return -3;
    if (error == ENOBUFS) return -4;
    return -6;
}
/* Return 1 for multipart completion, 0 for continuation, negative on failure.
 * Decode copied headers to avoid alignment assumptions about external bytes. */
int outbound_parse(const void *bytes, size_t size, int family, unsigned sequence, int limit) {
    const unsigned char *data = bytes;
    size_t offset = 0;
    while (offset < size) {
        struct nlmsghdr h;
        if (size - offset < sizeof(h)) return -5;
        memcpy(&h, data + offset, sizeof(h));
        if (h.nlmsg_len < sizeof(h) || h.nlmsg_len > size - offset || h.nlmsg_seq != sequence) return -5;
        if (h.nlmsg_flags & NLM_F_DUMP_INTR) return -4;
        size_t length = h.nlmsg_len - sizeof(h);
        const unsigned char *body = data + offset + sizeof(h);
        size_t aligned = NLMSG_ALIGN((size_t)h.nlmsg_len);
        if (h.nlmsg_type == NLMSG_NOOP) { /* no payload */ }
        else if (h.nlmsg_type == NLMSG_ERROR) {
            int error;
            if (length < sizeof(error)) return -5;
            memcpy(&error, body, sizeof(error));
            if (error == INT_MIN) return -5;
            if (error) return failure(-error);
        } else if (h.nlmsg_type == NLMSG_DONE) {
            int status = 0;
            if (length && length < sizeof(status)) return -4;
            if (length) memcpy(&status, body, sizeof(status));
            if (status) return -4;
            if (offset + aligned < size) return -5;
            return 1;
        } else if (h.nlmsg_type == NLMSG_OVERRUN) return -4;
        else if (h.nlmsg_type == SOCK_DIAG_BY_FAMILY) {
            struct inet_diag_msg row;
            if (length < sizeof(row)) return -5;
            memcpy(&row, body, sizeof(row));
            if (row.idiag_family != family || row.idiag_state < 1 || row.idiag_state > 12) return -5;
            if (row.idiag_state != 7 && row.idiag_state != 10) {
                if (row_count < limit) rows[row_count++].diag = row;
                else omitted++;
            }
        } else return -5;
        if (aligned > size - offset && offset + h.nlmsg_len != size) return -5;
        offset += aligned;
    }
    return 0;
}
int outbound_dump(int family, int limit) {
    row_count = 0;
    omitted = 0;
    int result = -6;
    int fd = socket(AF_NETLINK, SOCK_RAW | SOCK_CLOEXEC | SOCK_NONBLOCK, NETLINK_SOCK_DIAG);
    if (fd < 0) return failure(errno);
    struct sockaddr_nl kernel = {.nl_family = AF_NETLINK};
    if (bind(fd, (struct sockaddr *)&kernel, sizeof(kernel))) { result = failure(errno); goto done; }
    struct { struct nlmsghdr header; struct inet_diag_req_v2 request; } query = {0};
    query.header.nlmsg_len = sizeof(query);
    query.header.nlmsg_type = SOCK_DIAG_BY_FAMILY;
    query.header.nlmsg_flags = NLM_F_REQUEST | NLM_F_DUMP;
    query.header.nlmsg_seq = 1;
    query.request.sdiag_family = family;
    query.request.sdiag_protocol = IPPROTO_TCP;
    query.request.idiag_states = 0x1ffe;
    query.request.id.idiag_cookie[0] = INET_DIAG_NOCOOKIE;
    query.request.id.idiag_cookie[1] = INET_DIAG_NOCOOKIE;
    if (sendto(fd, &query, sizeof(query), 0, (struct sockaddr *)&kernel, sizeof(kernel)) != sizeof(query)) {
        result = failure(errno); goto done;
    }
    long deadline = outbound_monotonic_ms() + 1000;
    for (int packet = 0; packet < 4096; packet++) {
        long remaining = deadline - outbound_monotonic_ms();
        if (remaining <= 0) { result = -2; goto done; }
        struct pollfd poll_fd = {.fd = fd, .events = POLLIN};
        int ready = poll(&poll_fd, 1, (int)remaining);
        if (!ready) { result = -2; goto done; }
        if (ready < 0) { if (errno == EINTR) continue; result = failure(errno); goto done; }
        unsigned char buffer[256 * 1024];
        struct sockaddr_nl sender = {0};
        struct iovec iov = {.iov_base = buffer, .iov_len = sizeof(buffer)};
        struct msghdr message = {.msg_name = &sender, .msg_namelen = sizeof(sender), .msg_iov = &iov, .msg_iovlen = 1};
        ssize_t size = recvmsg(fd, &message, 0);
        if (size < 0) {
            if (errno == EINTR || errno == EAGAIN) continue;
            result = failure(errno); goto done;
        }
        if (!size || (message.msg_flags & (MSG_TRUNC | MSG_CTRUNC)) ||
            message.msg_namelen != sizeof(sender) || sender.nl_family != AF_NETLINK || sender.nl_pid || sender.nl_groups) {
            result = -5; goto done;
        }
        result = outbound_parse(buffer, (size_t)size, family, 1, limit);
        if (result < 0) goto done;
        if (result == 1) { result = row_count; goto done; }
    }
    result = -2;
done:
    close(fd);
    if (result < 0) { row_count = 0; omitted = 0; }
    return result;
}
int outbound_omitted(void) { return omitted; }
const char *outbound_row_json(int index) {
    struct inet_diag_msg *r = &rows[index].diag;
    char local[INET6_ADDRSTRLEN], remote[INET6_ADDRSTRLEN];
    inet_ntop(r->idiag_family, r->id.idiag_src, local, sizeof(local));
    inet_ntop(r->idiag_family, r->id.idiag_dst, remote, sizeof(remote));
    snprintf(row_json, sizeof(row_json),
        "{\"family\":%u,\"local\":{\"address\":\"%s\",\"port\":%u},"
        "\"remote\":{\"address\":\"%s\",\"port\":%u},\"state\":%u,\"uid\":%u,\"inode\":%u,"
        "\"cookie\":\"%08x%08x\"}", r->idiag_family, local, ntohs(r->id.idiag_sport), remote,
        ntohs(r->id.idiag_dport), r->idiag_state, r->idiag_uid, r->idiag_inode,
        r->id.idiag_cookie[0], r->id.idiag_cookie[1]);
    return row_json;
}
/* Numeric parsing only; this boundary never resolves hostnames. */
const char *outbound_ip_hex(const char *ip) {
    static char hex[33];
    unsigned char bytes[16];
    int length = 4;
    if (inet_pton(AF_INET, ip, bytes) != 1) {
        if (inet_pton(AF_INET6, ip, bytes) != 1) return "";
        length = 16;
        static const unsigned char mapped[12] = {0,0,0,0,0,0,0,0,0,0,255,255};
        if (!memcmp(bytes, mapped, 12)) { memmove(bytes, bytes + 12, 4); length = 4; }
    }
    for (int i = 0; i < length; i++) snprintf(hex + i * 2, 3, "%02x", bytes[i]);
    return hex;
}
