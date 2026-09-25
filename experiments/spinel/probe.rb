require "json"

module Native
  ffi_cflags "native.o"
  ffi_lib "maxminddb"
  ffi_func :outbound_loopback_inode, [:int, :int, :int], :long
  ffi_func :outbound_country, [:str, :str], :str
end

# This deliberately separate protocol cannot be substituted for outbound-engine.
# The harness owns the sockets and passes its PID; do not enumerate other apps.
STDOUT.sync = true
while line = STDIN.gets(4097)
  if line.bytesize > 4096 || !line.end_with?("\n")
    puts JSON.generate({"experiment" => "spinel", "error" => "invalidFrame"})
    break
  end
  begin
    request = JSON.parse(line)
    if request["command"] == "shutdown"
      break
    end
    if request["command"] != "probe"
      puts JSON.generate({"experiment" => "spinel", "error" => "invalidCommand"})
      next
    end
    family = request["family"].to_i
    local_port = request["localPort"].to_i
    remote_port = request["remotePort"].to_i
    owner_pid = request["ownerPid"].to_i
    if (family != 4 && family != 6) || local_port < 1 || local_port > 65535 ||
       remote_port < 1 || remote_port > 65535 || owner_pid < 1
      puts JSON.generate({"experiment" => "spinel", "error" => "invalidProbe"})
      next
    end
    inode = Native.outbound_loopback_inode(family, local_port, remote_port)
    owner_verified = false
    if inode > 0
      Dir.children("/proc/#{owner_pid}/fd").each do |fd|
        begin
          target = File.readlink("/proc/#{owner_pid}/fd/#{fd}")
          owner_verified = true if target == "socket:[#{inode}]"
        rescue SystemCallError
          # The harness may close a descriptor between listing and readlink.
        end
      end
    end
    # This documentation address belongs to the synthetic MMDB fixture only.
    country = Native.outbound_country(request["database"].to_s, "192.0.2.1")
    puts JSON.generate({
      "experiment" => "spinel",
      "requestId" => request["requestId"],
      "family" => family,
      "inode" => inode,
      "ownerVerified" => owner_verified,
      "syntheticCountry" => country
    })
  rescue JSON::ParserError
    puts JSON.generate({"experiment" => "spinel", "error" => "invalidJson"})
  end
end
