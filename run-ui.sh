#!/usr/bin/env bash
set -euo pipefail

repository_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ "${1:-}" == "--help" ]]; then
  printf '%s\n' 'Usage: ./run-ui.sh' 'Build and open the live Outbound UI. Set OUTBOUND_DATABASE to a local MMDB path if available.'
  exit 0
fi
if (( $# )); then
  printf '%s\n' 'Unexpected argument. Use --help.' >&2
  exit 2
fi
cargo build --manifest-path "$repository_dir/backend/Cargo.toml" --release --locked
outbound_preview=$(python3 -B "$repository_dir/tools/prepare_preview.py")
OUTBOUND_LIVE=1 exec qs -p "$outbound_preview"
