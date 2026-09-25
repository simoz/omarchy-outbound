require "json"
require_relative "protocol"
require_relative "input"
require_relative "engine"

# Stdout is reserved for newline-delimited protocol responses. Flush each one
# before waiting for the next command; diagnostics belong on stderr.
STDOUT.sync = true
Signal.trap("PIPE", "IGNORE")
begin
  database_path = ""
  database_given = false
  check_database = false
  until ARGV.empty?
    argument = ARGV.shift
    if argument == "--help"
      STDERR.puts "outbound-engine (Ruby/Spinel) [--database FILE.mmdb] [--check-database]"
      exit 0
    elsif argument == "--check-database" && !check_database
      check_database = true
    elsif argument == "--database" && !database_given && !ARGV.empty?
      database_given = true
      database_path = ARGV.shift
    else
      raise ArgumentError, "invalid arguments"
    end
  end
  raise ArgumentError, "missing database" if check_database && !database_given
  geo = Geo.new(database_path)
  if check_database
    raise ArgumentError, "invalid database" unless geo.country_database?
    puts JSON.generate(geo.status)
    exit 0
  end
  # Database validation exits above without collecting any socket information.
  engine = Engine.new(geo)
  while line = Input.read
    request = OutboundProtocol.parse(line)
    if request["error"]
      puts JSON.generate({
        "version" => 1, "kind" => "error", "requestId" => nil,
        "code" => request["error"], "fatal" => true
      })
      exit 1
    end
    if request["command"] == "shutdown"
      puts JSON.generate({"version" => 1, "kind" => "stopped", "requestId" => request["requestId"]})
      break
    end
    STDOUT.write(engine.encode(engine.sample(request["requestId"])))
  end
rescue Errno::EPIPE
  # The UI closed its read end; there is no remaining consumer to report to.
  exit 0
rescue StandardError
  STDERR.puts "outbound-engine: stopped after an input or I/O error"
  exit 1
end
