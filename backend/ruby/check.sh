#!/usr/bin/env bash
set -euo pipefail
source_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
"$source_dir/build.sh" >/dev/null
cd "$source_dir/build"
cc -std=c11 -D_GNU_SOURCE -O2 -Wall -Wextra -Werror "$source_dir/tests/netlink.c" -o netlink-tests
./netlink-tests
"${SPINEL:-spinel}" "$source_dir/tests/unit.rb" -o unit-tests
"${SPINEL:-spinel}" "$source_dir/tests/protocol.rb" -o protocol-probe
python3 -B "$source_dir/tests/check_protocol.py"
python3 -B "$source_dir/tests/check.py"
