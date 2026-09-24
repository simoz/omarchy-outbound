/* Immutable, bounded local database image; no resolver or external requests. */
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <maxminddb.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#define MAX_DB (64 * 1024 * 1024)
static MMDB_s database;
static int loaded;
static long build_epoch;
static int country_database;

/* Check the complete search graph, including cycles and invalid data records.
 * Heights bound every path to the address width even for shared subtrees. */
static int verify_node(uint32_t index, unsigned depth, unsigned char *marks,
                       unsigned char *heights, unsigned char *records) {
    if (depth >= database.depth || marks[index] == 1) return -1;
    if (marks[index] == 2) return heights[index];
    marks[index] = 1;
    MMDB_search_node_s node;
    if (MMDB_read_node(&database, index, &node) != MMDB_SUCCESS) return -1;
    uint64_t links[2] = {node.left_record, node.right_record};
    uint8_t types[2] = {node.left_record_type, node.right_record_type};
    MMDB_entry_s entries[2] = {node.left_record_entry, node.right_record_entry};
    int height = 1;
    for (int i = 0; i < 2; i++) {
        if (types[i] == MMDB_RECORD_TYPE_SEARCH_NODE) {
            if (links[i] >= database.metadata.node_count) return -1;
            int child = verify_node((uint32_t)links[i], depth + 1, marks, heights, records);
            if (child < 0 || child + 1 > database.depth) return -1;
            if (child + 1 > height) height = child + 1;
        } else if (types[i] == MMDB_RECORD_TYPE_DATA) {
            uint32_t offset = entries[i].offset;
            if (offset >= database.data_section_size) return -1;
            if (!(records[offset / 8] & (1u << (offset % 8)))) {
                MMDB_entry_data_list_s *list = NULL;
                int status = MMDB_get_entry_data_list(&entries[i], &list);
                MMDB_free_entry_data_list(list);
                if (status != MMDB_SUCCESS) return -1;
                records[offset / 8] |= 1u << (offset % 8);
            }
        } else if (types[i] != MMDB_RECORD_TYPE_EMPTY) return -1;
    }
    marks[index] = 2;
    heights[index] = (unsigned char)height;
    return height;
}
/* 0 ready, 1 missing, 2 unreadable, 3 invalid. */
int outbound_geo_open(const char *path) {
    if (loaded) MMDB_close(&database);
    loaded = 0;
    build_epoch = 0;
    country_database = 0;
    if (!path[0]) return 1;
    int input = open(path, O_RDONLY | O_CLOEXEC | O_NONBLOCK);
    if (input < 0) return errno == ENOENT ? 1 : (errno == EACCES || errno == EPERM ? 2 : 3);
    struct stat stat;
    int result = 3;
    int image = -1;
    if (fstat(input, &stat) || !S_ISREG(stat.st_mode) || stat.st_size > MAX_DB) goto done;
    image = memfd_create("outbound-geoip", MFD_CLOEXEC | MFD_ALLOW_SEALING);
    if (image < 0) goto done;
    unsigned char buffer[65536];
    size_t total = 0;
    for (;;) {
        ssize_t count = read(input, buffer, sizeof(buffer));
        if (count < 0) { if (errno == EINTR) continue; goto done; }
        if (!count) break;
        total += (size_t)count;
        if (total > MAX_DB) goto done;
        ssize_t written = 0;
        while (written < count) {
            ssize_t n = write(image, buffer + written, (size_t)(count - written));
            if (n < 0 && errno == EINTR) continue;
            if (n <= 0) goto done;
            written += n;
        }
    }
    if (fcntl(image, F_ADD_SEALS, F_SEAL_WRITE | F_SEAL_GROW | F_SEAL_SHRINK | F_SEAL_SEAL) < 0) goto done;
    char filename[64];
    snprintf(filename, sizeof(filename), "/proc/self/fd/%d", image);
    if (MMDB_open(filename, MMDB_MODE_MMAP, &database) != MMDB_SUCCESS) goto done;
    loaded = 1;
    uint64_t epoch = database.metadata.build_epoch;
    if (epoch < 946684800 || epoch > (uint64_t)time(NULL)) goto invalid;
    unsigned char *marks = calloc(database.metadata.node_count, 1);
    unsigned char *heights = calloc(database.metadata.node_count, 1);
    unsigned char *records = calloc((size_t)database.data_section_size / 8 + 1, 1);
    int valid = marks && heights && records && database.metadata.node_count;
    for (uint32_t i = 0; valid && i < database.metadata.node_count; i++) {
        if (verify_node(i, 0, marks, heights, records) < 0) valid = 0;
    }
    free(marks); free(heights); free(records);
    if (!valid) goto invalid;
    build_epoch = (long)epoch;
    country_database = database.metadata.ip_version == 6 && strcasestr(database.metadata.database_type, "country") != NULL;
    result = 0;
    goto done;
invalid:
    MMDB_close(&database);
    loaded = 0;
done:
    if (image >= 0) close(image);
    close(input);
    return result;
}
long outbound_geo_epoch(void) { return build_epoch; }
int outbound_geo_is_country(void) { return country_database; }
/* Empty = no country, ! = invalid lookup, otherwise two upper-case letters. */
const char *outbound_geo_lookup(const char *ip) {
    static char country[3];
    if (!loaded) return "";
    struct sockaddr_storage address = {0};
    struct sockaddr_in *v4 = (void *)&address;
    struct sockaddr_in6 *v6 = (void *)&address;
    if (inet_pton(AF_INET, ip, &v4->sin_addr) == 1) v4->sin_family = AF_INET;
    else if (inet_pton(AF_INET6, ip, &v6->sin6_addr) == 1) v6->sin6_family = AF_INET6;
    else return "!";
    int error = 0;
    MMDB_lookup_result_s lookup = MMDB_lookup_sockaddr(&database, (struct sockaddr *)&address, &error);
    if (error != MMDB_SUCCESS) return "!";
    if (!lookup.found_entry) return "";
    MMDB_entry_data_s data;
    int status = MMDB_get_value(&lookup.entry, &data, NULL);
    if (status != MMDB_SUCCESS || !data.has_data || data.type != MMDB_DATA_TYPE_MAP) return "!";
    status = MMDB_get_value(&lookup.entry, &data, "country", NULL);
    if (status == MMDB_LOOKUP_PATH_DOES_NOT_MATCH_DATA_ERROR) return "";
    if (status != MMDB_SUCCESS) return "!";
    if (!data.has_data) return "";
    if (data.type != MMDB_DATA_TYPE_MAP) return "!";
    status = MMDB_get_value(&lookup.entry, &data, "country", "iso_code", NULL);
    if (status == MMDB_LOOKUP_PATH_DOES_NOT_MATCH_DATA_ERROR) return "";
    if (status != MMDB_SUCCESS) return "!";
    if (!data.has_data) return "";
    if (data.type != MMDB_DATA_TYPE_UTF8_STRING || data.data_size != 2) return "!";
    memcpy(country, data.utf8_string, 2);
    country[2] = 0;
    if (country[0] < 'A' || country[0] > 'Z' || country[1] < 'A' || country[1] > 'Z') return "!";
    return strcmp(country, "ZZ") ? country : "";
}
