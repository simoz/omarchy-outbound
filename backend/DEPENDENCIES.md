# Native collector dependencies

The collector is built with Spinel revision
`66ae8c07f2d94f86f31fe7902650e796a79895fc` and static libmaxminddb 1.12.2.
The compiler and library are prepared outside the repository; no vendor tree or
binary is committed. See [build instructions](../docs/development.md#build-the-rubyspinel-collector).

Spinel's compiler/runtime uses the MIT license; libmaxminddb uses Apache-2.0.
Redistributing compiled binaries requires retaining the applicable upstream
license texts and notices, including those of bundled runtime components.
Release archives built by `.github/workflows/release.yml` contain the binary,
Outbound's `LICENSE`, `licenses/spinel-LICENSE`, `licenses/libmaxminddb-LICENSE`,
`licenses/libmaxminddb-NOTICE` and a `NOTICE.txt` with the source commit and
glibc requirement. The in-app installer keeps these files beside the binary.

The compiled collector does not require a Ruby interpreter, Spinel or Rust at
runtime. It statically links libmaxminddb and uses system C runtime libraries;
release builds run on Ubuntu 22.04 (glibc 2.35) natively for x86_64 and ARM64
and pass `backend/ruby/check.sh` there before packaging.

The generated MMDB used by tests is original synthetic data under this project's
MIT license. No provider database is bundled. Managed DB-IP Lite data has its
own attribution and CC BY 4.0 license; see [GeoIP details](../docs/geoip.md).
