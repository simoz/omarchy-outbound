# A streaming /proc walk bounds work before allocating directory listings.
# PID start times bracket matching descriptors; cmdline/environ are never read.
class Owners
  MAX_PROC_BYTES = 4096
  MAX_NAME_CHARACTERS = 128
  MAX_DIRECTORY_ENTRIES = 65536
  MAX_FILE_DESCRIPTORS = 262144
  MAX_OWNERS_PER_SOCKET = 16
  SCAN_BUDGET_MS = 400
  MAX_PID = 4294967295
  MAX_START_TIME_TICKS = 18446744073709551615

  def initialize(root = "/proc")
    @root = root
    @coverage = {
      "denied" => 0, "races" => 0, "errors" => 0,
      "ownersOmitted" => 0, "timedOut" => false, "scanLimited" => false
    }
    @owners_by_inode = {}
    @scanned_descriptors = 0
  end

  def record_error(error)
    key = if error.is_a?(Errno::EACCES) || error.is_a?(Errno::EPERM)
      "denied"
    elsif error.is_a?(Errno::ENOENT) || error.is_a?(Errno::ESRCH)
      "races"
    else
      "errors"
    end
    @coverage[key] += 1
  end

  def expired?
    @coverage["timedOut"] = true if Native.outbound_monotonic_ms >= @deadline_ms
    @coverage["timedOut"] || @coverage["scanLimited"]
  end

  def read_small(path)
    value = File.open(path, "rb") { |file| file.read(MAX_PROC_BYTES + 1) || +"" }
    raise IOError, "invalid proc file" if value.bytesize > MAX_PROC_BYTES
    value.force_encoding("UTF-8").scrub
  end

  def identity(path)
    stat = read_small("#{path}/stat")
    ending = stat.rindex(")")
    raise IOError, "invalid proc identity" if ending.nil?
    # /proc/PID/stat field 2 may contain spaces and closing parentheses.
    # After its last ')', index 19 is field 22: start time in clock ticks.
    ticks = stat[(ending + 1)..-1].split[19]
    if ticks.nil? || !ticks.match?(/\A[0-9]{1,20}\z/) || ticks.to_i > MAX_START_TIME_TICKS
      raise IOError, "invalid proc identity"
    end
    # Keep 64-bit tick counts as decimal strings across the JSON/JavaScript boundary.
    ticks.to_i.to_s
  end

  def scan_process(pid, wanted_inodes)
    path = "#{@root}/#{pid}"
    initial_identity = identity(path)
    # Multiple file descriptors in one process may refer to the same socket.
    matching_inodes = {}
    Dir.open("#{path}/fd") do |fds|
      while fd = fds.read
        next if fd == "." || fd == ".."
        break if expired?
        @scanned_descriptors += 1
        if @scanned_descriptors > MAX_FILE_DESCRIPTORS
          @coverage["scanLimited"] = true
          break
        end
        begin
          target = File.readlink("#{path}/fd/#{fd}")
          if target.match?(/\Asocket:\[[0-9]+\]\z/)
            inode = target[8..-2].to_i
            matching_inodes[inode] = true if wanted_inodes.key?(inode)
          end
        rescue SystemCallError => error
          record_error(error)
        end
      end
    end
    return if expired? || matching_inodes.empty?
    name = process_name(path)
    final_identity = identity(path)
    # A reused PID must not associate old descriptors with a new process name.
    if initial_identity != final_identity
      @coverage["races"] += 1
      return
    end
    owner = {"pid" => pid, "startTimeTicks" => initial_identity, "name" => name}
    matching_inodes.each_key do |inode|
      owners = @owners_by_inode[inode] || []
      if owners.length < MAX_OWNERS_PER_SOCKET
        owners << owner
        @owners_by_inode[inode] = owners
      else
        @coverage["ownersOmitted"] += 1
      end
    end
  rescue SystemCallError, IOError => error
    record_error(error)
  end

  def process_name(path)
    read_small("#{path}/comm").chars.reject do |character|
      codepoint = character.ord
      codepoint < 32 || (codepoint >= 127 && codepoint <= 159)
    end.take(MAX_NAME_CHARACTERS).join
  end

  # Each scanner is used once, with one shared budget across all processes.
  def scan(wanted_inodes)
    @deadline_ms = Native.outbound_monotonic_ms + SCAN_BUDGET_MS
    unless wanted_inodes.empty?
      entry_count = 0
      begin
        Dir.open(@root) do |entries|
          while entry = entries.read
            next if entry == "." || entry == ".."
            break if expired?
            if entry_count >= MAX_DIRECTORY_ENTRIES
              @coverage["scanLimited"] = true
              break
            end
            entry_count += 1
            next unless entry.match?(/\A[0-9]+\z/)
            pid = entry.to_i
            next if pid < 1 || pid > MAX_PID
            scan_process(pid, wanted_inodes)
          end
        end
      rescue SystemCallError => error
        record_error(error)
      end
    end
    {"owners" => @owners_by_inode, "coverage" => @coverage}
  end
end
