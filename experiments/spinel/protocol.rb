require "json"

# The command envelope is deliberately flat. Count keys before JSON.parse can
# discard duplicate members, including keys written with Unicode escapes.
module OutboundProtocol
  def self.parse(line)
    return {"error" => "commandTooLarge"} if line.bytesize > 4096
    return {"error" => "unterminatedCommand"} unless line.end_with?("\n")

    depth = 0
    quoted = false
    escaped = false
    start = 0
    key_expected = false
    strings = []
    keys = []
    invalid_string = false
    negative_number = false
    line.bytes.each_with_index do |byte, index|
      if quoted
        if escaped
          escaped = false
        elsif byte == 92
          escaped = true
        elsif byte == 34
          quoted = false
          is_key = depth == 1 && key_expected
          strings << [start, index - start + 1, is_key]
          key_expected = false if is_key
        end
      elsif byte == 34
        quoted = true
        start = index
      elsif byte == 123 || byte == 91
        depth += 1
        return {"error" => "commandTooDeep"} if depth > 8
        key_expected = true if depth == 1 && byte == 123
      elsif byte == 125 || byte == 93
        return {"error" => "invalidCommand"} if depth == 0
        depth -= 1
      elsif byte == 45
        negative_number = true
      elsif byte == 44 && depth == 1
        key_expected = true
      end
    end

    # Finish the depth check before decoding strings or allocating a JSON tree.
    strings.each do |part|
      value = JSON.parse(line.byteslice(part[0], part[1]))
      invalid_string = true unless value.force_encoding("UTF-8").valid_encoding?
      keys << value if part[2]
    end
    # The only numeric field is an unsigned byte; reject lexical -0 too.
    if negative_number || invalid_string || !line.force_encoding("UTF-8").valid_encoding?
      return {"error" => "invalidCommand"}
    end
    request = JSON.parse(line)
    unless request.is_a?(Hash) && keys.sort == ["command", "requestId", "version"]
      return {"error" => "invalidCommand"}
    end
    version = request["version"]
    unless version.is_a?(Integer) && version >= 0 && version <= 255 &&
           request["requestId"].is_a?(String) &&
           ["snapshot", "shutdown"].include?(request["command"])
      return {"error" => "invalidCommand"}
    end
    return {"error" => "unsupportedVersion"} unless version == 1
    id = request["requestId"]
    unless id.bytesize >= 1 && id.bytesize <= 64 &&
           id.bytes.all? { |b| (b >= 65 && b <= 90) || (b >= 97 && b <= 122) || (b >= 48 && b <= 57) || b == 95 || b == 45 }
      return {"error" => "invalidRequestId"}
    end
    request
  rescue JSON::ParserError
    {"error" => "invalidCommand"}
  end

  def self.read(input)
    line = input.gets(4097)
    return nil if line.nil?
    parse(line)
  end
end
