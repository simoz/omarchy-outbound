# Spinel FFI declarations for the local C adapters. Native buffers and the GeoIP
# database are process-global; the collector calls them sequentially.
module Native
  ffi_cflags "netlink.o geo.o input.o maxmind.o"
  ffi_func :outbound_read_frame, [], :int
  ffi_func :outbound_frame_hex, [], :str

  # A successful dump exposes rows until the next dump call; failures are negative.
  ffi_func :outbound_dump, [:int, :int], :int
  ffi_func :outbound_omitted, [], :int
  ffi_func :outbound_row_json, [:int], :str
  ffi_func :outbound_ip_hex, [:str], :str
  ffi_func :outbound_monotonic_ms, [], :long

  # Open returns a state index; lookup returns a country, empty miss, or "!" error.
  ffi_func :outbound_geo_open, [:str], :int
  ffi_func :outbound_geo_epoch, [], :long
  ffi_func :outbound_geo_is_country, [], :int
  ffi_func :outbound_geo_lookup, [:str], :str
end
