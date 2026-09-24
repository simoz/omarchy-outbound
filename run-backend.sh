#!/usr/bin/env bash
set -euo pipefail

repository_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

case "${OUTBOUND_ENGINE:-ruby}" in
  ruby)
    backend=$("$repository_dir/backend/ruby/build.sh")
    printf '%s\n' '{"version":1,"requestId":"manual-1","command":"snapshot"}' | "$backend" "$@"
    ;;
  rust)
    printf '%s\n' '{"version":1,"requestId":"manual-1","command":"snapshot"}' |
      cargo run --manifest-path "$repository_dir/backend/Cargo.toml" --release --locked -- "$@"
    ;;
  *) printf '%s\n' 'OUTBOUND_ENGINE must be ruby or rust.' >&2; exit 2 ;;
esac
