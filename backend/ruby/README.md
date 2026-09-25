# Ruby collector source guide

The collector is Ruby compiled with the project's pinned Spinel toolchain.
It runs one command at a time; the C adapters retain process-global buffers.
See [development instructions](../../docs/development.md#build-the-rubyspinel-collector)
for building and [the protocol](../../docs/protocol.md) for wire fields and bounds.

## Request flow

1. `main.rb` parses startup arguments and dispatches snapshot/shutdown commands.
2. `input.rb` reads one bounded frame through the blocking native adapter.
   `protocol.rb` checks framing, JSON depth, duplicate keys and command fields.
3. `Engine#sample` reads IPv4/IPv6 sockets and requests a bounded ownership scan.
4. `Engine#snapshot` assigns connection IDs, classifies addresses, looks up
   countries and calculates coverage and aggregates.
5. `Engine#encode` escapes Unicode for the Qt pipe reader and reduces oversized
   snapshots, updating omitted counts and aggregates before writing the frame.

## Supporting modules

- `owners.rb`: streaming `/proc` traversal. Matching descriptors are bracketed
  by process start-time reads to reject PID reuse. Names come from `comm`;
  command lines and environments are never read.
- `scope.rb`: special-use IPv4/IPv6 classification before GeoIP lookup. Input is
  normalized hexadecimal from the native adapter, including mapped IPv4.
- `geo.rb`: database metadata and bounded FIFO lookup cache. Missing results are
  cached too; repeated failures do not inflate error counts on every sample.
- `native.rb`: the Spinel FFI declarations; implementations live in `native/`.

Keep numeric protocol limits explicit and preserve validation order: callers
observe error codes, not just whether a command was rejected.

`tests/unit.rb` covers scope, identity, aggregation, encoding and fixture-based
ownership/GeoIP. `tests/protocol.rb` is a parsing-only driver. `check.sh` builds
both and runs the native, protocol and controlled-socket checks. Fixtures are
synthetic; these tests do not need public services or personal databases.
