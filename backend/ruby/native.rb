module Native
  ffi_cflags "netlink.o geo.o maxmind.o"
  ffi_func :outbound_dump, [:int, :int], :int
  ffi_func :outbound_omitted, [], :int
  ffi_func :outbound_row_json, [:int], :str
  ffi_func :outbound_ip_hex, [:str], :str
  ffi_func :outbound_monotonic_ms, [], :long
  ffi_func :outbound_geo_open, [:str], :int
  ffi_func :outbound_geo_epoch, [], :long
  ffi_func :outbound_geo_is_country, [], :int
  ffi_func :outbound_geo_lookup, [:str], :str
end
