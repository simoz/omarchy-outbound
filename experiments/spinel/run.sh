#!/bin/sh
set -eu

# /src is mounted read-only; compiler output stays in the disposable container.
probe_work=$(mktemp -d /tmp/outbound-spinel.XXXXXX)
trap 'rm -rf "$probe_work"' EXIT
cd "$probe_work"
cp /src/native.c /src/probe.rb /src/check.py /src/protocol.rb /src/protocol_probe.rb /src/check_protocol.py .
cc -std=c11 -D_GNU_SOURCE -O2 -Wall -Wextra -Werror -c native.c -o native.o
spinel --version
spinel probe.rb -o probe
file probe
ldd probe
python3 -B check.py
spinel protocol_probe.rb -o protocol-probe
python3 -B check_protocol.py
