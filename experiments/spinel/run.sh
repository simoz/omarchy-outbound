#!/bin/sh
set -eu

# /src is mounted read-only; compiler output stays in the disposable container.
probe_work=$(mktemp -d /tmp/outbound-spinel.XXXXXX)
trap 'rm -rf "$probe_work"' EXIT
cd "$probe_work"
cp /src/native.c /src/probe.rb /src/check.py .
cc -std=c11 -D_GNU_SOURCE -O2 -Wall -Wextra -Werror -c native.c -o native.o
spinel --version
spinel probe.rb -o probe
file probe
ldd probe
python3 -B check.py
