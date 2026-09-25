#!/usr/bin/env bash
set -euo pipefail
repository_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
backend="$repository_dir/backend/ruby/build/outbound-engine"
if [[ "${1:-}" != "--help" ]]; then
  backend=$("$repository_dir/backend/ruby/build.sh")
fi
exec python3 -B "$repository_dir/tools/update_geoip.py" --backend "$backend" "$@"
