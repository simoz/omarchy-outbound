#!/usr/bin/env bash
set -euo pipefail

repository_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

backend=$("$repository_dir/backend/ruby/build.sh")
printf '%s\n' '{"version":1,"requestId":"manual-1","command":"snapshot"}' | "$backend" "$@"
