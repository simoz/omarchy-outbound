#include <assert.h>
#include "../native/netlink.c"

static size_t message(unsigned char *buffer, int kind, int flags, const void *body, size_t size) {
    struct nlmsghdr h = {.nlmsg_len = sizeof(h) + size, .nlmsg_type = kind, .nlmsg_flags = flags, .nlmsg_seq = 1};
    memcpy(buffer, &h, sizeof(h));
    if (size) memcpy(buffer + sizeof(h), body, size);
    return sizeof(h) + size;
}
int main(void) {
    unsigned char buffer[1024];
    struct inet_diag_msg row = {.idiag_family = AF_INET, .idiag_state = 1, .idiag_inode = 123};
    row.id.idiag_sport = htons(1234);
    row.id.idiag_dport = htons(443);
    row.id.idiag_src[0] = htonl(INADDR_LOOPBACK);
    row.id.idiag_dst[0] = htonl(0xc0000201);
    for (int family = AF_INET; family <= AF_INET6; family += AF_INET6 - AF_INET) {
        row.idiag_family = family;
        size_t size = message(buffer, SOCK_DIAG_BY_FAMILY, 2, &row, sizeof(row));
        row_count = 0; omitted = 0;
        assert(outbound_parse(buffer, size, family, 1, 1) == 0);
        assert(row_count == 1 && rows[0].diag.idiag_inode == 123);
        assert(outbound_parse(buffer, size, family, 1, 1) == 0 && omitted == 1);
        for (size_t cut = 1; cut < size; cut++) assert(outbound_parse(buffer, cut, family, 1, 1) < 0);
        assert(outbound_parse(buffer, size, family, 2, 1) == -5);
        assert(outbound_parse(buffer, size, family == AF_INET ? AF_INET6 : AF_INET, 1, 1) == -5);
        size = message(buffer, SOCK_DIAG_BY_FAMILY, NLM_F_DUMP_INTR, &row, sizeof(row));
        assert(outbound_parse(buffer, size, family, 1, 1) == -4);
        row.idiag_state = 10;
        size = message(buffer, SOCK_DIAG_BY_FAMILY, 2, &row, sizeof(row));
        row_count = 0;
        assert(outbound_parse(buffer, size, family, 1, 1) == 0 && row_count == 0);
        row.idiag_state = 1;
    }
    int error = -EACCES;
    size_t size = message(buffer, NLMSG_ERROR, 0, &error, sizeof(error));
    assert(outbound_parse(buffer, size, AF_INET, 1, 1) == -1);
    error = -EINTR;
    size = message(buffer, NLMSG_DONE, 0, &error, sizeof(error));
    assert(outbound_parse(buffer, size, AF_INET, 1, 1) == -4);
    error = 0;
    size = message(buffer, NLMSG_DONE, 0, &error, sizeof(error));
    assert(outbound_parse(buffer, size, AF_INET, 1, 1) == 1);
    buffer[size] = 0;
    assert(outbound_parse(buffer, size + 1, AF_INET, 1, 1) == -5);
    unsigned seed = 1234;
    for (size_t n = 0; n < sizeof(buffer); n++) {
        for (size_t j = 0; j < n; j++) { seed = seed * 1664525 + 1013904223; buffer[j] = seed >> 16; }
        outbound_parse(buffer, n, AF_INET, 1, 1);
    }
    puts("PASS native netlink framing, bounds and malformed packets");
}
