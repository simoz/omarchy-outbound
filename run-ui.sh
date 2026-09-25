#!/usr/bin/env bash
set -euo pipefail

repository_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ "${1:-}" == "--help" ]]; then
  printf '%s\n' 'Usage: ./run-ui.sh' 'Build and open the live Outbound UI (Ruby/Spinel by default).' 'Set OUTBOUND_ENGINE=rust to compare with Rust; OUTBOUND_DATABASE selects a local MMDB.'
  exit 0
fi
if (( $# )); then
  printf '%s\n' 'Unexpected argument. Use --help.' >&2
  exit 2
fi
case "${OUTBOUND_ENGINE:-ruby}" in
  ruby) default_backend=$("$repository_dir/backend/ruby/build.sh") ;;
  rust)
    cargo build --manifest-path "$repository_dir/backend/Cargo.toml" --release --locked
    default_backend="$repository_dir/backend/target/release/outbound-engine"
    ;;
  *) printf '%s\n' 'OUTBOUND_ENGINE must be ruby or rust.' >&2; exit 2 ;;
esac
# Explicitly override a saved preview path so switching engines really switches.
export OUTBOUND_BACKEND="${OUTBOUND_BACKEND:-$default_backend}"
printf 'Outbound backend: %s\n' "$OUTBOUND_BACKEND" >&2
outbound_preview=$(python3 -B "$repository_dir/tools/prepare_preview.py")
exec qs -p "$outbound_preview"
