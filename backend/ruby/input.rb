require_relative "native"

# Blocking, bounded reads live in C to avoid Spinel readiness polling while idle.
# Validation remains in OutboundProtocol, including oversized/partial frames.
module Input
  def self.read
    status = Native.outbound_read_frame
    raise IOError, "input read failed" if status < 0
    return nil if status == 0
    # Hex carries embedded NUL bytes safely through the C string FFI.
    [Native.outbound_frame_hex].pack("H*")
  end
end
