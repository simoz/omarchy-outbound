require_relative "native"

module Input
  def self.read
    status = Native.outbound_read_frame
    raise IOError, "input read failed" if status < 0
    return nil if status == 0
    [Native.outbound_frame_hex].pack("H*")
  end
end
