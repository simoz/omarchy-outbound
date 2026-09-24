# Ruby/Spinel Linux feasibility probe

An isolated experiment for Outbound's backend on **Linux x86_64 and ARM64**.
It does not replace the Rust collector, change QML, or install the plugin.

The Ruby program compiles to an ELF executable using
[Spinel](https://github.com/matz/spinel), pinned for this experiment to
`66ae8c07f2d94f86f31fe7902650e796a79895fc`.
The compiler's version banner in this build says `unreleased (unknown)` because
the container has no Git executable; the checkout revision above identifies the
source used. This is a development snapshot, not a stability guarantee.

## What the experiment exercises

- Ruby: line-delimited JSON requests/responses, Unicode/escaping, repeated
  requests, bounded input, shutdown/EOF, and `/proc/<pid>/fd` ownership checks.
- A C adapter called through Spinel FFI: Linux `NETLINK_SOCK_DIAG` dumps for
  established IPv4 and IPv6 TCP sockets. It returns only the inode of the
  controlled loopback endpoint requested by the harness, with bounded receive
  time and packet count. Failures return negative errno, not a successful empty
  result.
- A second C adapter: local `libmaxminddb` lookup and copying the result before
  closing its mmap. The test builds an original, synthetic MMDB using the format
  already used in `backend/tests/geo.rs`. Its `IT` result for a documentation IP
  is fictional test data, not a geolocation claim.

`check.py` creates real loopback sockets and passes its own PID to the probe.
It never prints unrelated connections, scans other processes, downloads a
country database, or connects to external services. Tests run as UID 65534,
with all capabilities dropped and the external network disabled. Docker's
loopback interface remains available.

## Reproduce

Docker must support both platforms; on an ARM host the amd64 lane requires
emulation. Fetching the source and building the images requires network access.
The project is mounted read-only for the test; output is temporary inside each
container. Run from the repository root:

```sh
spinel_source=$(mktemp -d /tmp/outbound-spinel-source.XXXXXX)
git -C "$spinel_source" init
git -C "$spinel_source" fetch --depth 1 https://github.com/matz/spinel.git \
  66ae8c07f2d94f86f31fe7902650e796a79895fc
git -C "$spinel_source" checkout --detach FETCH_HEAD

for arch in arm64 amd64; do
  docker build --platform "linux/$arch" \
    -f "$PWD/experiments/spinel/Dockerfile" \
    -t "outbound-spinel-probe:$arch" "$spinel_source"
  docker run --rm --platform "linux/$arch" \
    --network none --cap-drop ALL --security-opt no-new-privileges \
    --user 65534:65534 \
    -v "$PWD/experiments/spinel:/src:ro" \
    "outbound-spinel-probe:$arch" sh /src/run.sh
done
```

The script compiles the adapter with `-Wall -Wextra -Werror`, compiles Ruby with
Spinel, prints the executable's architecture and dynamic dependencies, then
runs the integration checks. No compiler or Ruby installation is required on
the host. The source is pinned; the Debian base and apt package versions are
not, so this is a repeatable procedure, not a bit-for-bit reproducible build.

## Recorded results — 2026-09-24

Host: macOS ARM64, Docker Desktop with an ARM64 Linux VM. Both lanes used
Debian bookworm and GCC 12.2.0, running the same source and harness.

| Target | Execution environment | ELF architecture | Integration checks |
| --- | --- | --- | --- |
| Linux ARM64 | ARM64 container in the Linux VM | AArch64 | 8/8 passed |
| Linux x86_64 | amd64 container under emulation | x86-64 | 8/8 passed |

Both builds passed C compilation with warnings treated as errors. The eight
checks cover IPv4/IPv6 and repeated JSON round trips, rejecting a wrong owner,
excluding a listening socket, missing/corrupt MMDB, invalid JSON/commands and
recovery, oversized input, unterminated input, and shutdown/EOF. `file` verified
both ELF architectures; `ldd` showed the libraries listed below and no Ruby
shared library. Shell/Ruby syntax checks and `git diff --check` also passed.

This was **not** a test on physical x86_64 hardware or within Omarchy/Quickshell.
No performance comparison or production collector test suite was run: the
production implementation is unchanged.

## Limits and next decision

This demonstrates the integration path, not a drop-in `outbound-engine`.
The probe accepts a separate, trusted harness protocol. It does not implement
the production command schema, complete input validation, whole-system process
enumeration, PID reuse handling, socket cookies, aggregation, GeoIP policy and
cache, complete error/coverage reporting, or the service lifecycle contract.
The C code is an experimental adapter, not a port of all Rust collector safety
checks. Production intentionally does not geolocate documentation/loopback IPs;
the synthetic lookup here tests the library boundary only.

There is no Ruby runtime dependency, but this build dynamically links glibc,
libm, libcrypt and **libmaxminddb**. Shipping it would require deciding whether
to depend on or bundle/link that library, checking licenses and ABI baselines,
and testing on actual Omarchy installations. No static/self-contained binary,
performance improvement, or full gem compatibility is demonstrated.

A next step would port one real snapshot to the existing JSON protocol and
compare it against the Rust collector on controlled connections before any
decision to replace the backend.
