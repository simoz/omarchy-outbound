/* Experimental adapters only; not the production collector's implementation. */
#include <arpa/inet.h>
#include <errno.h>
#include <linux/inet_diag.h>
#include <linux/netlink.h>
#include <linux/sock_diag.h>
#include <maxminddb.h>
#include <stdint.h>
#include <string.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

static int64_t milliseconds(void) {
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return (int64_t)now.tv_sec * 1000 + now.tv_nsec / 1000000;
}

/* Inspect only the controlled loopback pair, never return unrelated sockets.
 * Negative errno values distinguish a failed dump from an absent connection.
 * Consume the complete dump even after finding a match to detect interruption.
 */
long outbound_loopback_inode(int version, int local_port, int remote_port) {
    int family = version == 4 ? AF_INET : AF_INET6;
    int fd = socket(AF_NETLINK, SOCK_RAW | SOCK_CLOEXEC, NETLINK_SOCK_DIAG);
    if (fd < 0) return -errno;
    long result = 0;
    struct timeval timeout = {.tv_sec = 1};
    if (setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout)) < 0) {
        result = -errno;
        goto done;
    }
    struct {
        struct nlmsghdr header;
        struct inet_diag_req_v2 request;
    } query = {0};
    query.header.nlmsg_len = sizeof(query);
    query.header.nlmsg_type = SOCK_DIAG_BY_FAMILY;
    query.header.nlmsg_flags = NLM_F_REQUEST | NLM_F_DUMP;
    query.header.nlmsg_seq = 1;
    query.request.sdiag_family = family;
    query.request.sdiag_protocol = IPPROTO_TCP;
    query.request.idiag_states = 1U << 1; /* TCP_ESTABLISHED */
    struct sockaddr_nl kernel = {.nl_family = AF_NETLINK};
    if (sendto(fd, &query, sizeof(query), 0,
               (struct sockaddr *)&kernel, sizeof(kernel)) != sizeof(query)) {
        result = -errno;
        goto done;
    }
    int64_t deadline = milliseconds() + 2000;
    for (int packet = 0; packet < 256 && milliseconds() < deadline; packet++) {
        union { struct nlmsghdr align; char bytes[65536]; } buffer;
        struct sockaddr_nl sender = {0};
        struct iovec iov = {.iov_base = buffer.bytes, .iov_len = sizeof(buffer.bytes)};
        struct msghdr message = {.msg_name = &sender, .msg_namelen = sizeof(sender),
                                 .msg_iov = &iov, .msg_iovlen = 1};
        ssize_t size = recvmsg(fd, &message, 0);
        if (size < 0) { result = -errno; goto done; }
        if (size == 0 || (message.msg_flags & MSG_TRUNC) || sender.nl_pid != 0) {
            result = -EPROTO;
            goto done;
        }
        int remaining = (int)size;
        for (struct nlmsghdr *h = (void *)buffer.bytes; NLMSG_OK(h, remaining);
             h = NLMSG_NEXT(h, remaining)) {
            if (h->nlmsg_seq != 1 || (h->nlmsg_flags & NLM_F_DUMP_INTR)) {
                result = -EINTR;
                goto done;
            }
            if (h->nlmsg_type == NLMSG_DONE) {
                if (h->nlmsg_len >= NLMSG_LENGTH(sizeof(int))) {
                    int status;
                    memcpy(&status, NLMSG_DATA(h), sizeof(status));
                    if (status != 0) result = status < 0 ? status : -EPROTO;
                }
                goto done;
            }
            if (h->nlmsg_type == NLMSG_ERROR) {
                result = -EPROTO;
                if (h->nlmsg_len >= NLMSG_LENGTH(sizeof(struct nlmsgerr))) {
                    struct nlmsgerr error;
                    memcpy(&error, NLMSG_DATA(h), sizeof(error));
                    if (error.error < 0) result = error.error;
                }
                goto done;
            }
            if (h->nlmsg_type != SOCK_DIAG_BY_FAMILY ||
                h->nlmsg_len < NLMSG_LENGTH(sizeof(struct inet_diag_msg))) {
                result = -EPROTO;
                goto done;
            }
            struct inet_diag_msg row;
            memcpy(&row, NLMSG_DATA(h), sizeof(row));
            if (row.idiag_family != family || row.idiag_state != 1) continue;
            if (ntohs(row.id.idiag_sport) != local_port ||
                ntohs(row.id.idiag_dport) != remote_port) continue;
            int loopback;
            if (family == AF_INET) {
                loopback = row.id.idiag_src[0] == htonl(INADDR_LOOPBACK) &&
                           row.id.idiag_dst[0] == htonl(INADDR_LOOPBACK);
            } else {
                loopback = memcmp(row.id.idiag_src, &in6addr_loopback, 16) == 0 &&
                           memcmp(row.id.idiag_dst, &in6addr_loopback, 16) == 0;
            }
            if (loopback) result = row.idiag_inode;
        }
        if (remaining != 0) { result = -EPROTO; goto done; }
    }
    result = -ETIMEDOUT;
done:
    close(fd);
    return result;
}

/* Copy the country before closing the mmap. Empty/missing data is explicit. */
const char *outbound_country(const char *path, const char *ip) {
    static char country[3];
    MMDB_s database;
    if (MMDB_open(path, MMDB_MODE_MMAP, &database) != MMDB_SUCCESS) return "openError";
    int gai_error = 0, mmdb_error = 0;
    MMDB_lookup_result_s lookup = MMDB_lookup_string(&database, ip, &gai_error, &mmdb_error);
    const char *result = "missing";
    if (gai_error || mmdb_error != MMDB_SUCCESS) result = "lookupError";
    else if (lookup.found_entry) {
        MMDB_entry_data_s data;
        int status = MMDB_get_value(&lookup.entry, &data, "country", "iso_code", NULL);
        if (status == MMDB_SUCCESS && data.has_data &&
            data.type == MMDB_DATA_TYPE_UTF8_STRING && data.data_size == 2) {
            memcpy(country, data.utf8_string, 2);
            country[2] = '\0';
            result = country;
        } else result = "dataError";
    }
    MMDB_close(&database);
    return result;
}
