require "json"
require_relative "native"
require_relative "scope"
require_relative "geo"
require_relative "owners"

class Engine
  def initialize(geo)
    @geo = geo
    @session = File.open("/dev/urandom", "rb") { |file| file.read(16) }.unpack1("H*")
    @sequence = 0
    @fallback = {}
    @next_id = 0
  end

  def aggregates(rows)
    countries = {}
    applications = {}
    unknown = 0
    rows.each do |row|
      country = row["country"] || (row["scope"] == "public" ? "unknown" : "nonInternet")
      countries[country] = (countries[country] || 0) + 1
      unknown += 1 if row["owners"].empty?
      row["owners"].map { |owner| owner["name"] }.uniq.each do |name|
        applications[name] = (applications[name] || 0) + 1
      end
    end
    {"sockets" => rows.length, "countries" => countries, "applications" => applications, "unknownOwners" => unknown}
  end

  def sample(request_id)
    sockets = []
    failures = []
    omitted = 0
    [2, 10].each do |family|
      count = Native.outbound_dump(family, 4096 - sockets.length)
      if count < 0
        failures << ["denied", "timeout", "unavailable", "interrupted", "malformed", "io"][-count - 1]
      else
        failures << nil
        count.times { |i| sockets << JSON.parse(Native.outbound_row_json(i)) }
        omitted += Native.outbound_omitted
      end
    end
    wanted = {}
    sockets.each { |row| wanted[row["inode"]] = true unless row["inode"] == 0 }
    scan = Owners.new.scan(wanted)
    snapshot(request_id, sockets, scan["owners"], {
      "ipv4" => failures[0], "ipv6" => failures[1], "processes" => scan["coverage"],
      "omittedRows" => omitted, "truncated" => omitted > 0, "namespace" => "current"
    })
  end

  def snapshot(request_id, sockets, owners, coverage)
    @sequence += 1
    next_fallback = {}
    states = ["", "ESTABLISHED", "SYN_SENT", "SYN_RECV", "FIN_WAIT1", "FIN_WAIT2", "TIME_WAIT", "CLOSE", "CLOSE_WAIT", "LAST_ACK", "LISTEN", "CLOSING", "NEW_SYN_RECV"]
    connections = sockets.map do |row|
      if row["cookie"] != "ffffffffffffffff"
        id = "#{@session}:#{row['family']}:#{row['cookie']}"
      else
        key = JSON.generate([row["family"], row["inode"], row["local"], row["remote"]])
        id = @fallback[key]
        if id.nil?
          @next_id += 1
          id = "#{@session}:fallback:#{@next_id}"
        end
        next_fallback[key] = id
      end
      address = row["remote"]["address"]
      hex = Native.outbound_ip_hex(address)
      scope = Scope.classify(hex)
      {"id" => id, "family" => row["family"] == 2 ? "IPv4" : "IPv6",
       "local" => row["local"], "remote" => row["remote"], "state" => states[row["state"]],
       "uid" => row["uid"], "owners" => owners[row["inode"]] || [], "scope" => scope,
       "direction" => "unknown", "country" => @geo.lookup(address, hex, scope)}
    end
    # An incomplete observation cannot support fallback continuity next time.
    @fallback = coverage["truncated"] || coverage["ipv4"] || coverage["ipv6"] ? {} : next_fallback
    process = coverage["processes"]
    partial = coverage["ipv4"] || coverage["ipv6"] || coverage["truncated"] ||
      process["timedOut"] || process["scanLimited"] ||
      process["denied"] + process["races"] + process["errors"] + process["ownersOmitted"] > 0 ||
      connections.any? { |row| row["owners"].empty? }
    status = coverage["ipv4"] && coverage["ipv6"] ? "error" : (partial ? "partial" : "ok")
    {"version" => 1, "kind" => "snapshot", "requestId" => request_id, "session" => @session,
     "sequence" => @sequence, "observedAtMs" => (Time.now.to_f * 1000).to_i,
     "status" => status, "coverage" => coverage, "database" => @geo.status,
     "connections" => connections, "aggregates" => aggregates(connections)}
  end

  def encode(snapshot)
    loop do
      # The Qt reader decodes chunks independently; ASCII preserves all names.
      json = JSON.generate(snapshot)
      # Most snapshots are already ASCII; keep their buffer instead of allocating
      # a codepoint array and one temporary string for every wire character.
      wire = json
      unless json.ascii_only?
        wire = +""
        json.codepoints.each do |code|
          if code < 128
            wire << code.chr
          elsif code <= 65535
            wire << ("\\u%04x" % code)
          else
            value = code - 65536
            wire << ("\\u%04x\\u%04x" % [55296 + (value >> 10), 56320 + (value & 1023)])
          end
        end
      end
      return wire + "\n" if wire.bytesize < 2 * 1024 * 1024
      rows = snapshot["connections"]
      keep = rows.length / 2
      snapshot["coverage"]["omittedRows"] += rows.length - keep
      snapshot["coverage"]["truncated"] = true
      snapshot["status"] = "partial"
      snapshot["connections"] = rows.take(keep)
      snapshot["aggregates"] = aggregates(snapshot["connections"])
      @fallback = {}
    end
  end
end
