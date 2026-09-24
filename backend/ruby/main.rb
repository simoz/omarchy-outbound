require "json"
require_relative "protocol"
require_relative "input"
require_relative "engine"

STDOUT.sync = true
Signal.trap("PIPE", "IGNORE")
begin
  path = ""
  database_given = false
  check = false
  until ARGV.empty?
    arg = ARGV.shift
    if arg == "--help"
      STDERR.puts "outbound-engine (Ruby/Spinel) [--database FILE.mmdb] [--check-database]"
      exit 0
    elsif arg == "--check-database" && !check
      check = true
    elsif arg == "--database" && !database_given && !ARGV.empty?
      database_given = true
      path = ARGV.shift
    else
      raise ArgumentError, "invalid arguments"
    end
  end
  raise ArgumentError, "missing database" if check && !database_given
  geo = Geo.new(path)
  if check
    raise ArgumentError, "invalid database" unless geo.country_database?
    puts JSON.generate(geo.status)
    exit 0
  end
  engine = Engine.new(geo)
  while line = Input.read
    request = OutboundProtocol.parse(line)
    if request["error"]
      puts JSON.generate({"version" => 1, "kind" => "error", "requestId" => nil,
                          "code" => request["error"], "fatal" => true})
      exit 1
    end
    if request["command"] == "shutdown"
      puts JSON.generate({"version" => 1, "kind" => "stopped", "requestId" => request["requestId"]})
      break
    end
    STDOUT.write(engine.encode(engine.sample(request["requestId"])))
  end
rescue Errno::EPIPE
  exit 0
rescue StandardError
  STDERR.puts "outbound-engine: stopped after an input or I/O error"
  exit 1
end
