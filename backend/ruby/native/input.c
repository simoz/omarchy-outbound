/* This single-threaded collector needs a blocking pipe reader, not the pinned
 * Spinel cooperative runtime's 1 ms readiness polling. Keep all buffers bounded
 * and leave command validation and fatal framing decisions to Ruby. */
#include <errno.h>
#include <stddef.h>
#include <unistd.h>

static unsigned char input[4096];
static size_t offset, available;
static char frame_hex[4097 * 2 + 1];

/* 0 = EOF, 1 = frame (possibly partial/oversized), -1 = read failure.
 * Hex preserves embedded NUL through the NUL-terminated FFI string boundary. */
int outbound_read_frame(void) {
    static const char digits[] = "0123456789abcdef";
    size_t length = 0;
    while (length < 4097) {
        if (offset == available) {
            ssize_t count;
            do { count = read(STDIN_FILENO, input, sizeof(input)); }
            while (count < 0 && errno == EINTR);
            if (count < 0) return -1;
            if (!count) break;
            offset = 0;
            available = (size_t)count;
        }
        unsigned char byte = input[offset++];
        frame_hex[length * 2] = digits[byte >> 4];
        frame_hex[length * 2 + 1] = digits[byte & 15];
        length++;
        if (byte == '\n') break;
    }
    frame_hex[length * 2] = '\0';
    return length ? 1 : 0;
}
const char *outbound_frame_hex(void) { return frame_hex; }
