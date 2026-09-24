#!/usr/bin/env bash
set -euo pipefail

repository_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Cargo rebuilds only when needed; build messages stay on stderr.
printf '%s\n' '{"version":1,"requestId":"manual-1","command":"snapshot"}' |
  cargo run --manifest-path "$repository_dir/backend/Cargo.toml" --release --locked -- "$@"
