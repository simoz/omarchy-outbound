require_relative "../engine"

def check(condition, message)
  raise message unless condition
end

# Test both sides of special-use boundaries, including mapped IPv4.
[
  ["0.0.0.0", "unspecified"], ["127.1.2.3", "loopback"], ["10.0.0.1", "private"],
  ["100.127.255.255", "shared"], ["100.128.0.1", "public"], ["169.254.1.1", "linkLocal"],
  ["192.0.0.8", "reserved"], ["192.0.0.9", "public"], ["192.0.0.10", "public"],
  ["192.0.2.1", "documentation"], ["198.18.0.1", "reserved"], ["224.1.2.3", "multicast"],
  ["255.255.255.255", "reserved"], ["::ffff:192.168.1.1", "private"], ["::ffff:8.8.8.8", "public"],
  ["::1", "loopback"], ["::", "unspecified"], ["fc00::1", "private"], ["fe80::1", "linkLocal"],
  ["ff02::1", "multicast"], ["2001:db8::1", "documentation"], ["3fff:fff::", "documentation"],
  ["3fff:1000::", "public"], ["2001:2::1", "reserved"], ["2001:1::1", "public"],
  ["2001:3::1", "public"], ["2001:4860::8888", "public"], ["64:ff9b::808:808", "reserved"], ["2002::1", "reserved"]
].each do |address, expected_scope|
  hex_address = Native.outbound_ip_hex(address)
  check(Scope.classify(hex_address) == expected_scope, "address scope: #{address}")
end

def coverage
  {
    "ipv4" => nil, "ipv6" => nil, "namespace" => "current",
    "omittedRows" => 0, "truncated" => false,
    "processes" => {
      "denied" => 0, "races" => 0, "errors" => 0,
      "ownersOmitted" => 0, "timedOut" => false, "scanLimited" => false
    }
  }
end

socket = {
  "family" => 2,
  "local" => {"address" => "127.0.0.1", "port" => 10},
  "remote" => {"address" => "192.0.2.1", "port" => 20},
  "state" => 1, "uid" => 1000, "inode" => 7, "cookie" => "ffffffffffffffff"
}
geo = Geo.new("")
engine = Engine.new(geo)
owners = {
  7 => [
    {"pid" => 1, "startTimeTicks" => "8", "name" => "Browser"},
    {"pid" => 2, "startTimeTicks" => "9", "name" => "Browser"},
    {"pid" => 3, "startTimeTicks" => "10", "name" => "Helper"}
  ]
}
first_snapshot = engine.snapshot("a", [socket], owners, coverage)
repeated_snapshot = engine.snapshot("b", [socket], owners, coverage)
check(first_snapshot["connections"][0]["id"] == repeated_snapshot["connections"][0]["id"], "stable fallback")
check(
  first_snapshot["aggregates"]["applications"] == {"Browser" => 1, "Helper" => 1},
  "shared ownership aggregation"
)
engine.snapshot("empty", [], {}, coverage)
reappeared_snapshot = engine.snapshot("c", [socket], {}, coverage)
check(
  first_snapshot["connections"][0]["id"] != reappeared_snapshot["connections"][0]["id"],
  "retired fallback"
)
# A failed or truncated dump breaks fallback identity continuity.
failed = coverage
failed["ipv4"] = "interrupted"
engine.snapshot("failed", [], {}, failed)
after_failure = engine.snapshot("d", [socket], {}, coverage)
check(
  reappeared_snapshot["connections"][0]["id"] != after_failure["connections"][0]["id"],
  "failed observation retires fallback"
)
truncated = coverage
truncated["truncated"] = true
truncated["omittedRows"] = 1
engine.snapshot("truncated", [socket], {}, truncated)
after_truncation = engine.snapshot("e", [socket], {}, coverage)
check(
  after_failure["connections"][0]["id"] != after_truncation["connections"][0]["id"],
  "truncation retires fallback"
)

# Coverage is independent of GeoIP availability: a missing database alone is not partial.
check(engine.snapshot("complete", [socket], owners, coverage)["status"] == "ok", "complete coverage")
check(engine.snapshot("unowned", [socket], {}, coverage)["status"] == "partial", "missing owner")
["denied", "races", "errors", "ownersOmitted", "timedOut", "scanLimited"].each do |reason|
  incomplete = coverage
  incomplete["processes"][reason] = ["timedOut", "scanLimited"].include?(reason) ? true : 1
  check(engine.snapshot("partial", [socket], owners, incomplete)["status"] == "partial", reason)
end
one_family_failed = coverage
one_family_failed["ipv4"] = "denied"
check(engine.snapshot("ipv4", [], {}, one_family_failed)["status"] == "partial", "one family failed")
both_families_failed = coverage
both_families_failed["ipv4"] = "denied"
both_families_failed["ipv6"] = "timeout"
check(engine.snapshot("both", [], {}, both_families_failed)["status"] == "error", "both families failed")

# Both wire paths must preserve quotes, backslashes, BMP and astral names.
["Browser", "café 船🦀 \"quoted\" \\ path"].each do |name|
  sample = engine.snapshot("encoding", [socket], {7 => [{"pid" => 1, "startTimeTicks" => "8", "name" => name}]}, coverage)
  wire = engine.encode(sample)
  check(wire.ascii_only?, "ASCII wire for every process name")
  check(JSON.parse(wire) == sample, "exact wire roundtrip")
end

# Force output truncation with long Unicode names and maximum shared ownership.
many_owners = []
16.times do |index|
  many_owners << {"pid" => index + 1, "startTimeTicks" => "8", "name" => "船🦀" * 64}
end
large = engine.snapshot("large", [socket] * 4096, {7 => many_owners}, coverage)
wire = engine.encode(large)
check(wire.ascii_only? && wire.bytesize <= 2 * 1024 * 1024, "wire budget")
parsed = JSON.parse(wire)
check(parsed["connections"][0]["owners"][0]["name"] == "船🦀" * 64, "Unicode roundtrip")
check(parsed["aggregates"]["sockets"] + parsed["coverage"]["omittedRows"] == 4096, "truncated aggregates")
check(parsed["coverage"]["truncated"], "truncation reported")

# Simulate PID reuse between the identity reads that bracket descriptor scanning.
class ReusedOwners < Owners
  def identity(path)
    value = super(path)
    @reads = (@reads || 0) + 1
    @reads % 2 == 0 ? value + "0" : value
  end
end

# Optional fixture paths are created by check.py, never taken from personal data.
if ARGV.length > 0
  result = Owners.new(ARGV[0]).scan({7 => true})
  check(result["owners"][7].length == 16, "owners cap and duplicate fds")
  check(result["coverage"]["ownersOmitted"] == 2, "omitted owners count")
  check(result["coverage"]["errors"] == 1, "empty stat is a partial scan, not a crash")
  reused = ReusedOwners.new(ARGV[0]).scan({7 => true})
  check(reused["owners"].empty? && reused["coverage"]["races"] == 18, "PID reuse discards attribution")
  check(
    result["owners"][7].all? { |owner| owner["startTimeTicks"] == "123" && owner["name"] == "船🦀name" },
    "proc names and identity"
  )
end
if ARGV.length > 1
  geo = Geo.new(ARGV[1])
  check(geo.status["state"] == "ready" && geo.country_database?, "valid synthetic database")
  check(geo.status["releaseMonth"] == "2024-01", "database month")
  ["8.8.8.8", "::ffff:8.8.8.8", "2001:4860::8888"].each do |address|
    hex = Native.outbound_ip_hex(address)
    check(geo.lookup(address, hex, Scope.classify(hex)) == "IT", "synthetic public lookup")
  end
  ["127.0.0.1", "192.0.2.1", "fc00::1"].each do |address|
    hex = Native.outbound_ip_hex(address)
    check(geo.lookup(address, hex, Scope.classify(hex)).nil?, "special-use exclusion")
  end
  # Reloading the path on disk must not alter the retained immutable image.
  File.write(ARGV[1], "invalid")
  check(geo.lookup("9.9.9.9", Native.outbound_ip_hex("9.9.9.9"), "public") == "IT", "immutable database")
end
if ARGV.length > 2
  ["ZZ", "bad", "type"].each do |code|
    geo = Geo.new("#{ARGV[2]}/#{code}.mmdb")
    3.times { check(geo.lookup("8.8.8.8", "08080808", "public").nil?, "invalid country excluded") }
    check(geo.status["lookupErrors"] == (code == "ZZ" ? 0 : 1), "negative cache avoids repeated errors")
  end
end
puts "PASS Ruby scope, identity, aggregation, wire bounds, ownership and GeoIP"
