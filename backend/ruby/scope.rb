module Scope
  # Compare nibble prefixes to avoid depending on 128-bit integer arithmetic.
  def self.prefix(hex, base, bits)
    digits = bits / 4
    return false unless hex[0, digits] == base[0, digits]
    remainder = bits % 4
    remainder == 0 || (hex[digits].to_i(16) >> (4 - remainder)) == (base[digits].to_i(16) >> (4 - remainder))
  end

  def self.classify(hex)
    if hex.length == 8
      return "unspecified" if hex == "00000000"
      return "loopback" if prefix(hex, "7f", 8)
      return "private" if prefix(hex, "0a", 8) || prefix(hex, "ac1", 12) || prefix(hex, "c0a8", 16)
      return "linkLocal" if prefix(hex, "a9fe", 16)
      return "multicast" if prefix(hex, "e", 4)
      return "documentation" if prefix(hex, "c00002", 24) || prefix(hex, "c63364", 24) || prefix(hex, "cb0071", 24)
      return "shared" if prefix(hex, "644", 10)
      return "public" if hex == "c0000009" || hex == "c000000a"
      return "reserved" if prefix(hex, "00", 8) || prefix(hex, "c00000", 24) || prefix(hex, "c05863", 24) || prefix(hex, "c612", 15) || prefix(hex, "f", 4)
      return "public"
    end
    return "unspecified" if hex == "00000000000000000000000000000000"
    return "loopback" if hex == "00000000000000000000000000000001"
    return "multicast" if prefix(hex, "ff", 8)
    return "private" if prefix(hex, "fc", 7)
    return "linkLocal" if prefix(hex, "fe8", 10)
    return "documentation" if prefix(hex, "20010db8", 32) || prefix(hex, "3fff0", 20)
    return "reserved" if prefix(hex, "2002", 16)
    if prefix(hex, "200100", 23)
      return "public" if ["20010001000000000000000000000001", "20010001000000000000000000000002", "20010001000000000000000000000003"].include?(hex) || prefix(hex, "20010003", 32) || prefix(hex, "200100040112", 48) || prefix(hex, "2001002", 28) || prefix(hex, "2001003", 28)
      return "reserved"
    end
    prefix(hex, "2", 3) ? "public" : "reserved"
  end

  def self.lookup_address(hex, original)
    return original unless hex.length == 8
    [hex[0, 2].to_i(16), hex[2, 2].to_i(16), hex[4, 2].to_i(16), hex[6, 2].to_i(16)].join(".")
  end
end
