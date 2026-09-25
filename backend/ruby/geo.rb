# The native adapter retains an immutable database image for this process.
# Ruby owns presentation metadata and a bounded cache, including negative hits.
class Geo
  OPEN_STATES = ["ready", "missing", "unreadable", "invalid"]
  CACHE_CAPACITY = 8192
  STALE_AFTER_SECONDS = 90 * 86400

  def initialize(path)
    state = OPEN_STATES[Native.outbound_geo_open(path)]
    build_epoch = state == "ready" ? Native.outbound_geo_epoch : nil
    @status = {
      "state" => state,
      "buildEpochSeconds" => build_epoch,
      "releaseMonth" => build_epoch.nil? ? nil : Time.at(build_epoch).utc.strftime("%Y-%m"),
      "stale" => false,
      "lookupErrors" => 0
    }
    @cache = {}
    @insertion_order = []
  end

  def status
    build_epoch = @status["buildEpochSeconds"]
    @status["stale"] = !build_epoch.nil? && Time.now.to_i - build_epoch > STALE_AFTER_SECONDS
    @status
  end

  def country_database?
    Native.outbound_geo_is_country == 1
  end

  def lookup(address, hex_address, scope)
    return nil unless scope == "public" && @status["state"] == "ready"
    # key? distinguishes a cached miss (nil) from an address not yet queried.
    return @cache[hex_address] if @cache.key?(hex_address)

    result = Native.outbound_geo_lookup(Scope.lookup_address(hex_address, address))
    @status["lookupErrors"] += 1 if result == "!"
    country = result == "!" || result == "" ? nil : result

    # FIFO eviction bounds memory without updating an LRU list on every hit.
    @cache.delete(@insertion_order.shift) if @insertion_order.length == CACHE_CAPACITY
    @insertion_order << hex_address
    @cache[hex_address] = country
    country
  end
end
