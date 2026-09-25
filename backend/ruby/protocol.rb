require "json"

# The command envelope is deliberately flat. Count keys before JSON.parse can
# discard duplicate members, including keys written with Unicode escapes.
module OutboundProtocol
  MAX_COMMAND_BYTES = 4096
  MAX_DEPTH = 8
  MAX_REQUEST_ID_BYTES = 64
  REQUIRED_KEYS = ["command", "requestId", "version"]
  COMMANDS = ["snapshot", "shutdown"]

  def self.parse(line)
    return {"error" => "commandTooLarge"} if line.bytesize > MAX_COMMAND_BYTES
    return {"error" => "unterminatedCommand"} unless line.end_with?("\n")

    depth = 0
    quoted = false
    escaped = false
    string_start = 0
    key_expected = false
    string_spans = []
    keys = []
    invalid_string = false
    negative_number = false
    line.bytes.each_with_index do |byte, index|
      if quoted
        if escaped
          escaped = false
        elsif byte == 92 # Backslash escapes the next string byte.
          escaped = true
        elsif byte == 34 # Double quote.
          quoted = false
          is_key = depth == 1 && key_expected
          string_spans << [string_start, index - string_start + 1, is_key]
          key_expected = false if is_key
        end
      elsif byte == 34 # Double quote.
        quoted = true
        string_start = index
      elsif byte == 123 || byte == 91 # Opening object or array.
        depth += 1
        return {"error" => "commandTooDeep"} if depth > MAX_DEPTH
        key_expected = true if depth == 1 && byte == 123
      elsif byte == 125 || byte == 93 # Closing object or array.
        return {"error" => "invalidCommand"} if depth == 0
        depth -= 1
      elsif byte == 45 # Minus outside a string.
        negative_number = true
      elsif byte == 44 && depth == 1 # Next top-level member.
        key_expected = true
      end
    end

    # Finish the depth check before decoding strings or allocating a JSON tree.
    string_spans.each do |offset, length, is_key|
      value = JSON.parse(line.byteslice(offset, length))
      invalid_string = true unless value.force_encoding("UTF-8").valid_encoding?
      keys << value if is_key
    end
    # The only numeric field is an unsigned byte; reject lexical -0 too.
    if negative_number || invalid_string || !line.force_encoding("UTF-8").valid_encoding?
      return {"error" => "invalidCommand"}
    end
    request = JSON.parse(line)
    unless request.is_a?(Hash) && keys.sort == REQUIRED_KEYS
      return {"error" => "invalidCommand"}
    end
    version = request["version"]
    unless version.is_a?(Integer) && version >= 0 && version <= 255 &&
           request["requestId"].is_a?(String) &&
           COMMANDS.include?(request["command"])
      return {"error" => "invalidCommand"}
    end
    return {"error" => "unsupportedVersion"} unless version == 1
    request_id = request["requestId"]
    unless request_id.bytesize >= 1 && request_id.bytesize <= MAX_REQUEST_ID_BYTES &&
           request_id.bytes.all? { |byte| request_id_byte?(byte) }
      return {"error" => "invalidRequestId"}
    end
    request
  rescue JSON::ParserError
    {"error" => "invalidCommand"}
  end

  def self.request_id_byte?(byte)
    (byte >= 65 && byte <= 90) ||   # A-Z
      (byte >= 97 && byte <= 122) || # a-z
      (byte >= 48 && byte <= 57) ||  # 0-9
      byte == 95 || byte == 45      # underscore or hyphen
  end

end
