require "json"
require_relative "../protocol"
require_relative "../input"

# Test driver only: accepted snapshots acknowledge parsing without collecting
# or fabricating socket data. It is not an outbound-engine executable.
STDOUT.sync = true
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
  puts JSON.generate({"experiment" => "protocol", "requestId" => request["requestId"]})
end
