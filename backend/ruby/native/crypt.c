/* Spinel's runtime references crypt(3) for String#crypt, which the collector
 * never calls. Defining it here keeps libcrypt out of the binary: its soname is
 * libcrypt.so.1 on the release build host but libcrypt.so.2 on Arch. */
#include <errno.h>
#include <stddef.h>

char *crypt(const char *key, const char *salt) {
  (void)key;
  (void)salt;
  errno = ENOSYS;
  return NULL;
}
