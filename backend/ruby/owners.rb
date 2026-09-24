# A streaming /proc walk bounds work before allocating directory listings.
# PID start times bracket matching descriptors; cmdline/environ are never read.
class Owners
  def initialize(root = "/proc")
    @root = root
    @coverage = {"denied" => 0, "races" => 0, "errors" => 0, "ownersOmitted" => 0,
                 "timedOut" => false, "scanLimited" => false}
    @result = {}
    @fd_count = 0
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
    @coverage["timedOut"] = true if Native.outbound_monotonic_ms >= @deadline
    @coverage["timedOut"] || @coverage["scanLimited"]
  end

  def read_small(path)
    value = File.open(path, "rb") { |file| file.read(4097) || +"" }
    raise IOError, "invalid proc file" if value.bytesize > 4096
    value.force_encoding("UTF-8").scrub
  end

  def identity(path)
    stat = read_small("#{path}/stat")
    ending = stat.rindex(")")
    raise IOError, "invalid proc identity" if ending.nil?
    ticks = stat[(ending + 1)..-1].split[19]
    raise IOError, "invalid proc identity" if ticks.nil? || !ticks.match?(/\A[0-9]{1,20}\z/) || ticks.to_i > 18446744073709551615
    ticks.to_i.to_s
  end

  def scan_process(pid, wanted)
    path = "#{@root}/#{pid}"
    before = identity(path)
    matches = {}
    Dir.open("#{path}/fd") do |fds|
      while fd = fds.read
        next if fd == "." || fd == ".."
        break if expired?
        @fd_count += 1
        if @fd_count > 262144
          @coverage["scanLimited"] = true
          break
        end
        begin
          target = File.readlink("#{path}/fd/#{fd}")
          if target.match?(/\Asocket:\[[0-9]+\]\z/)
            inode = target[8..-2].to_i
            matches[inode] = true if wanted.key?(inode)
          end
        rescue SystemCallError => error
          record_error(error)
        end
      end
    end
    return if expired? || matches.empty?
    name = read_small("#{path}/comm").chars.reject { |c| c.ord < 32 || (c.ord >= 127 && c.ord <= 159) }.take(128).join
    after = identity(path)
    if before != after
      @coverage["races"] += 1
      return
    end
    owner = {"pid" => pid, "startTimeTicks" => before, "name" => name}
    matches.each_key do |inode|
      owners = @result[inode] || []
      if owners.length < 16
        owners << owner
        @result[inode] = owners
      else
        @coverage["ownersOmitted"] += 1
      end
    end
  rescue SystemCallError, IOError => error
    record_error(error)
  end

  def scan(wanted)
    @deadline = Native.outbound_monotonic_ms + 400
    unless wanted.empty?
      count = 0
      begin
        Dir.open(@root) do |entries|
          while entry = entries.read
            next if entry == "." || entry == ".."
            break if expired?
            if count >= 65536
              @coverage["scanLimited"] = true
              break
            end
            count += 1
            next unless entry.match?(/\A[0-9]+\z/)
            pid = entry.to_i
            next if pid < 1 || pid > 4294967295
            scan_process(pid, wanted)
          end
        end
      rescue SystemCallError => error
        record_error(error)
      end
    end
    {"owners" => @result, "coverage" => @coverage}
  end
end
