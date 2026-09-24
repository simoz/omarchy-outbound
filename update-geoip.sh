#!/usr/bin/env bash
set -euo pipefail
repository_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ "${1:-}" != "--help" ]]; then
  cargo build --manifest-path "$repository_dir/backend/Cargo.toml" --release --locked
fi
exec python3 -B "$repository_dir/tools/update_geoip.py" --backend "$repository_dir/backend/target/release/outbound-engine" "$@"
