# Input is the native adapter's normalized hex address: eight digits for IPv4,
# including IPv4-mapped IPv6, or 32 digits for other IPv6 addresses.
module Scope
  # Compare nibble prefixes to avoid depending on 128-bit integer arithmetic.
  def self.prefix(hex, base, bits)
    digits = bits / 4
    return false unless hex[0, digits] == base[0, digits]
    remainder = bits % 4
    return true if remainder == 0

    shift = 4 - remainder
    (hex[digits].to_i(16) >> shift) == (base[digits].to_i(16) >> shift)
  end

  def self.classify(hex)
    hex.length == 8 ? classify_ipv4(hex) : classify_ipv6(hex)
  end

  def self.classify_ipv4(hex)
    return "unspecified" if hex == "00000000"
    return "loopback" if prefix(hex, "7f", 8)
    # RFC 1918: 10/8, 172.16/12 and 192.168/16.
    return "private" if prefix(hex, "0a", 8) || prefix(hex, "ac1", 12) || prefix(hex, "c0a8", 16)
    return "linkLocal" if prefix(hex, "a9fe", 16)
    return "multicast" if prefix(hex, "e", 4)
    # Documentation ranges: 192.0.2/24, 198.51.100/24 and 203.0.113/24.
    return "documentation" if prefix(hex, "c00002", 24) ||
      prefix(hex, "c63364", 24) || prefix(hex, "cb0071", 24)
    return "shared" if prefix(hex, "644", 10)
    # 192.0.0.9 and .10 are public exceptions to the reserved 192.0.0.0/24.
    return "public" if hex == "c0000009" || hex == "c000000a"
    return "reserved" if prefix(hex, "00", 8) || prefix(hex, "c00000", 24) ||
      prefix(hex, "c05863", 24) || prefix(hex, "c612", 15) || prefix(hex, "f", 4)
    "public"
  end

  def self.classify_ipv6(hex)
    return "unspecified" if hex == "00000000000000000000000000000000"
    return "loopback" if hex == "00000000000000000000000000000001"
    return "multicast" if prefix(hex, "ff", 8)
    return "private" if prefix(hex, "fc", 7)
    return "linkLocal" if prefix(hex, "fe8", 10)
    return "documentation" if prefix(hex, "20010db8", 32) || prefix(hex, "3fff0", 20)
    return "reserved" if prefix(hex, "2002", 16)
    if prefix(hex, "200100", 23)
      # Public exceptions inside the otherwise reserved 2001::/23 block.
      public_hosts = [
        "20010001000000000000000000000001",
        "20010001000000000000000000000002",
        "20010001000000000000000000000003"
      ]
      return "public" if public_hosts.include?(hex) ||
        prefix(hex, "20010003", 32) || prefix(hex, "200100040112", 48) ||
        prefix(hex, "2001002", 28) || prefix(hex, "2001003", 28)
      return "reserved"
    end
    prefix(hex, "2", 3) ? "public" : "reserved"
  end

  # Mapped IPv6 must use its IPv4 address when querying an IPv4-only database.
  def self.lookup_address(hex, original)
    return original unless hex.length == 8
    [hex[0, 2].to_i(16), hex[2, 2].to_i(16), hex[4, 2].to_i(16), hex[6, 2].to_i(16)].join(".")
  end
end
