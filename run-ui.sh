#!/usr/bin/env bash
set -euo pipefail

repository_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ "${1:-}" == "--help" ]]; then
  printf '%s\n' 'Usage: ./run-ui.sh' 'Build and open the live Outbound UI (Ruby/Spinel).' 'OUTBOUND_DATABASE selects a local MMDB.'
  exit 0
fi
if (( $# )); then
  printf '%s\n' 'Unexpected argument. Use --help.' >&2
  exit 2
fi
default_backend=$("$repository_dir/backend/ruby/build.sh")
# Use the current build instead of a backend path saved by an earlier preview.
export OUTBOUND_BACKEND="${OUTBOUND_BACKEND:-$default_backend}"
printf 'Outbound backend: %s\n' "$OUTBOUND_BACKEND" >&2
outbound_preview=$(python3 -B "$repository_dir/tools/prepare_preview.py")
exec qs -p "$outbound_preview"
