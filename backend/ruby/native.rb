# Spinel FFI declarations for the local C adapters. Native buffers and the GeoIP
# database are process-global; the collector calls them sequentially.
module Native
  ffi_cflags "netlink.o geo.o input.o crypt.o maxmind.o"
  ffi_func :outbound_read_frame, [], :int
  ffi_func :outbound_frame_hex, [], :str

  # A successful dump exposes rows until the next dump call; failures are negative.
  ffi_func :outbound_dump, [:int, :int], :int
  ffi_func :outbound_omitted, [], :int
  ffi_func :outbound_row_family, [:int], :int
  ffi_func :outbound_row_state, [:int], :int
  ffi_func :outbound_row_uid, [:int], :long
  ffi_func :outbound_row_inode, [:int], :long
  ffi_func :outbound_row_local_address, [:int], :str
  ffi_func :outbound_row_local_port, [:int], :int
  ffi_func :outbound_row_remote_address, [:int], :str
  ffi_func :outbound_row_remote_port, [:int], :int
  ffi_func :outbound_row_remote_hex, [:int], :str
  ffi_func :outbound_row_cookie, [:int], :str
  # Textual address to normalized hex; the collector itself reads row hex.
  ffi_func :outbound_ip_hex, [:str], :str
  ffi_func :outbound_monotonic_ms, [], :long

  # Open returns a state index; lookup takes address hex and returns a country,
  # empty miss, or "!" error.
  ffi_func :outbound_geo_open, [:str], :int
  ffi_func :outbound_geo_epoch, [], :long
  ffi_func :outbound_geo_is_country, [], :int
  ffi_func :outbound_geo_lookup_hex, [:str], :str
end
