class Geo
  def initialize(path)
    state = ["ready", "missing", "unreadable", "invalid"][Native.outbound_geo_open(path)]
    epoch = state == "ready" ? Native.outbound_geo_epoch : nil
    @status = {"state" => state, "buildEpochSeconds" => epoch,
               "releaseMonth" => epoch.nil? ? nil : Time.at(epoch).utc.strftime("%Y-%m"),
               "stale" => false, "lookupErrors" => 0}
    @cache = {}
    @order = []
  end

  def status
    epoch = @status["buildEpochSeconds"]
    @status["stale"] = !epoch.nil? && Time.now.to_i - epoch > 90 * 86400
    @status
  end

  def country_database?
    Native.outbound_geo_is_country == 1
  end

  def lookup(address, hex, scope)
    return nil unless scope == "public" && @status["state"] == "ready"
    return @cache[hex] if @cache.key?(hex)
    value = Native.outbound_geo_lookup(Scope.lookup_address(hex, address))
    @status["lookupErrors"] += 1 if value == "!"
    country = value == "!" || value == "" ? nil : value
    @cache.delete(@order.shift) if @order.length == 8192
    @order << hex
    @cache[hex] = country
    country
  end
end
