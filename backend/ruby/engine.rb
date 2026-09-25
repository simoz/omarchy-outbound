require "json"
require_relative "native"
require_relative "scope"
require_relative "geo"
require_relative "owners"

# One engine owns socket identity across snapshots in a single collector session.
class Engine
  MAX_SOCKETS = 4096
  MAX_WIRE_BYTES = 2 * 1024 * 1024
  UNKNOWN_COOKIE = "ffffffffffffffff"
  ADDRESS_FAMILIES = [2, 10] # Linux AF_INET and AF_INET6, in coverage field order.
  DUMP_ERRORS = ["denied", "timeout", "unavailable", "interrupted", "malformed", "io"]
  TCP_STATES = [
    "", "ESTABLISHED", "SYN_SENT", "SYN_RECV", "FIN_WAIT1", "FIN_WAIT2",
    "TIME_WAIT", "CLOSE", "CLOSE_WAIT", "LAST_ACK", "LISTEN", "CLOSING", "NEW_SYN_RECV"
  ]

  def initialize(geo)
    @geo = geo
    @session = File.open("/dev/urandom", "rb") { |file| file.read(16) }.unpack1("H*")
    @sequence = 0
    @fallback_ids = {}
    @next_fallback_id = 0
  end

  def aggregates(connections)
    countries = {}
    applications = {}
    unknown_owners = 0

    connections.each do |connection|
      country = connection["country"] || (connection["scope"] == "public" ? "unknown" : "nonInternet")
      countries[country] = (countries[country] || 0) + 1
      unknown_owners += 1 if connection["owners"].empty?

      # Shared descriptors count once per application name, not once per PID.
      connection["owners"].map { |owner| owner["name"] }.uniq.each do |name|
        applications[name] = (applications[name] || 0) + 1
      end
    end

    {
      "sockets" => connections.length,
      "countries" => countries,
      "applications" => applications,
      "unknownOwners" => unknown_owners
    }
  end

  def sample(request_id)
    sockets = []
    family_errors = []
    omitted_sockets = 0

    ADDRESS_FAMILIES.each do |family|
      count = Native.outbound_dump(family, MAX_SOCKETS - sockets.length)
      if count < 0
        family_errors << DUMP_ERRORS[-count - 1]
      else
        family_errors << nil
        # The native adapter replaces its row buffer on the next family dump.
        count.times { |index| sockets << JSON.parse(Native.outbound_row_json(index)) }
        omitted_sockets += Native.outbound_omitted
      end
    end

    wanted_inodes = {}
    sockets.each { |socket| wanted_inodes[socket["inode"]] = true unless socket["inode"] == 0 }
    process_scan = Owners.new.scan(wanted_inodes)
    coverage = {
      "ipv4" => family_errors[0],
      "ipv6" => family_errors[1],
      "processes" => process_scan["coverage"],
      "omittedRows" => omitted_sockets,
      "truncated" => omitted_sockets > 0,
      "namespace" => "current"
    }
    snapshot(request_id, sockets, process_scan["owners"], coverage)
  end

  def snapshot(request_id, sockets, owners, coverage)
    @sequence += 1
    next_fallback_ids = {}
    connections = sockets.map do |socket|
      address = socket["remote"]["address"]
      hex_address = Native.outbound_ip_hex(address)
      scope = Scope.classify(hex_address)
      {
        "id" => connection_id(socket, next_fallback_ids),
        "family" => socket["family"] == 2 ? "IPv4" : "IPv6",
        "local" => socket["local"],
        "remote" => socket["remote"],
        "state" => TCP_STATES[socket["state"]],
        "uid" => socket["uid"],
        "owners" => owners[socket["inode"]] || [],
        "scope" => scope,
        "direction" => "unknown",
        "country" => @geo.lookup(address, hex_address, scope)
      }
    end

    # Reuse fallback IDs only across consecutive, complete socket observations.
    # A missing row could otherwise hide inode reuse between two snapshots.
    incomplete = coverage["truncated"] || coverage["ipv4"] || coverage["ipv6"]
    @fallback_ids = incomplete ? {} : next_fallback_ids
    {
      "version" => 1,
      "kind" => "snapshot",
      "requestId" => request_id,
      "session" => @session,
      "sequence" => @sequence,
      "observedAtMs" => (Time.now.to_f * 1000).to_i,
      "status" => snapshot_status(connections, coverage),
      "coverage" => coverage,
      "database" => @geo.status,
      "connections" => connections,
      "aggregates" => aggregates(connections)
    }
  end

  def connection_id(socket, next_fallback_ids)
    if socket["cookie"] != UNKNOWN_COOKIE
      return "#{@session}:#{socket['family']}:#{socket['cookie']}"
    end

    key = JSON.generate([socket["family"], socket["inode"], socket["local"], socket["remote"]])
    id = @fallback_ids[key]
    if id.nil?
      @next_fallback_id += 1
      id = "#{@session}:fallback:#{@next_fallback_id}"
    end
    next_fallback_ids[key] = id
    id
  end

  def snapshot_status(connections, coverage)
    return "error" if coverage["ipv4"] && coverage["ipv6"]

    processes = coverage["processes"]
    partial = coverage["ipv4"] || coverage["ipv6"] || coverage["truncated"] ||
      processes["timedOut"] || processes["scanLimited"] ||
      processes["denied"] + processes["races"] + processes["errors"] + processes["ownersOmitted"] > 0 ||
      connections.any? { |connection| connection["owners"].empty? }
    partial ? "partial" : "ok"
  end

  def encode(snapshot)
    loop do
      wire = ascii_json(snapshot)
      # Reserve the final byte for the newline framing delimiter.
      return wire + "\n" if wire.bytesize < MAX_WIRE_BYTES

      connections = snapshot["connections"]
      retained_count = connections.length / 2
      snapshot["coverage"]["omittedRows"] += connections.length - retained_count
      snapshot["coverage"]["truncated"] = true
      snapshot["status"] = "partial"
      snapshot["connections"] = connections.take(retained_count)
      snapshot["aggregates"] = aggregates(snapshot["connections"])
      @fallback_ids = {}
    end
  end

  def ascii_json(snapshot)
    json = JSON.generate(snapshot)
    # Keep the common ASCII path allocation-light. Qt decodes pipe chunks
    # independently, so escape Unicode to prevent splitting a UTF-8 sequence.
    return json if json.ascii_only?

    wire = +""
    json.codepoints.each do |codepoint|
      if codepoint < 128
        wire << codepoint.chr
      elsif codepoint <= 65535
        wire << ("\\u%04x" % codepoint)
      else
        # JSON represents supplementary characters as UTF-16 surrogate pairs.
        offset = codepoint - 65536
        wire << ("\\u%04x\\u%04x" % [55296 + (offset >> 10), 56320 + (offset & 1023)])
      end
    end
    wire
  end
end
