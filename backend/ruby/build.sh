#!/usr/bin/env bash
set -euo pipefail
source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
build_dir="$source_dir/build"
mkdir -p "$build_dir"
exec 9>"$build_dir/build.lock"
flock 9
binary="$build_dir/outbound-engine"
if [[ "${1:-}" != --force && -x "$binary" ]] &&
   ! find "$source_dir" -path "$build_dir" -prune -o -type f -newer "$binary" -print -quit | read -r _; then
  printf '%s\n' "$binary"
  exit 0
fi
compiler="${SPINEL:-spinel}"
if ! command -v "$compiler" >/dev/null; then
  printf '%s\n' 'Spinel is required to build the Ruby backend. Set SPINEL to its executable; see docs/development.md.' >&2
  exit 1
fi
if [[ -n "${MAXMIND_PREFIX:-}" ]]; then
  include_dir="$MAXMIND_PREFIX/include"
  library_dir="$MAXMIND_PREFIX/lib"
else
  include_dir=$(pkg-config --variable=includedir libmaxminddb)
  library_dir=$(pkg-config --variable=libdir libmaxminddb)
fi
if [[ ! -f "$library_dir/libmaxminddb.a" ]]; then
  printf '%s\n' 'A static libmaxminddb build is required. Set MAXMIND_PREFIX; see docs/development.md.' >&2
  exit 1
fi
cd "$build_dir"
cc -std=c11 -D_GNU_SOURCE -O2 -Wall -Wextra -Werror -c "$source_dir/native/netlink.c" -o netlink.o
cc -std=c11 -D_GNU_SOURCE -O2 -Wall -Wextra -Werror -I "$include_dir" -c "$source_dir/native/geo.c" -o geo.o
cp "$library_dir/libmaxminddb.a" maxmind.o
"$compiler" "$source_dir/main.rb" -o "$binary.new" >&2
mv "$binary.new" "$binary"
printf '%s\n' "$binary"
