import QtQuick
import "Model.js" as Model
import "assets/Countries.js" as Geography

Item {
    id: root
    property var shell: null
    property bool standalone: false
    property var saveConfiguration: null
    property bool paused: false
    property var views: []
    property string backendPath: ""
    property string databasePath: ""
    property var origin: null
    property int intervalSeconds: 2
    property var savedConfiguration: ({})
    property var liveRows: []
    property var snapshot: null
    property string phase: "idle"
    property string error: ""
    readonly property int openViews: views.filter(function(v) { return v.open; }).length
    readonly property bool demanded: openViews > 0 && !paused
    readonly property int pollInterval: intervalSeconds * 1000
    readonly property string status: !openViews ? "IDLE" : paused ? "PAUSED" : phase.toUpperCase()
    // Keep a paused snapshot available for inspection until the last view closes.
    onOpenViewsChanged: if (openViews === 0) {
        snapshot = null;
        liveRows = [];
    }
    readonly property string geoStatus: {
        if (!snapshot) return "GeoIP not sampled";
        var database = snapshot.database;
        if (database.state !== "ready") return "GeoIP " + database.state;
        return "GeoIP " + database.releaseMonth + (database.stale ? " · outdated" : "") + (database.lookupErrors ? " · lookup errors" : "");
    }
    readonly property string coverageStatus: {
        if (!snapshot) return "No snapshot";
        var coverage = snapshot.coverage, processes = coverage.processes;
        return ["IPv4: " + (coverage.ipv4 || "ok"), "IPv6: " + (coverage.ipv6 || "ok"),
                "Unknown owners: " + snapshot.aggregates.unknownOwners, "Denied: " + processes.denied,
                "Races: " + processes.races, "Errors: " + processes.errors,
                "Omitted sockets: " + coverage.omittedRows, "Omitted owners: " + processes.ownersOmitted]
            .concat(processes.timedOut ? ["Process scan timed out"] : [], processes.scanLimited ? ["Process scan limited"] : [])
            .join(" · ");
    }
    Loader {
        id: transport
        active: root.shell !== null || root.standalone
        source: "Collector.qml"
        onLoaded: item.service = root
    }
    Loader {
        id: originSearch
        active: root.shell !== null || root.standalone
        source: "OriginSearch.qml"
        onLoaded: item.service = root
    }
    readonly property var citySearch: originSearch.item
    readonly property bool searchingCity: citySearch ? citySearch.busy : false
    readonly property var cityResults: citySearch ? citySearch.results : []
    readonly property string cityError: citySearch ? citySearch.error : ""
    function searchCity(query) { if (citySearch) citySearch.search(query); }
    // Runtime helpers are Python scripts shipped in tools/ beside this file.
    function helperPath(name) { return decodeURIComponent(Qt.resolvedUrl("tools/" + name).toString().slice(7)); }
    function clearCitySearch() { if (citySearch) citySearch.clear(); }
    function setView(token, open) {
        var next = views.filter(function(v) { return v.token !== token; });
        next.push({token:token, open:open}); views = next;
    }
    function removeView(token) { views = views.filter(function(v) { return v.token !== token; }); }
    readonly property var collector: transport.item
    readonly property bool refreshing: collector ? collector.refreshing : false
    function refresh() { if (collector) collector.refresh(); }
    function retry() { if (collector) collector.retry(); }
    readonly property bool geoInstalling: collector ? collector.geoInstalling : false
    readonly property string geoInstallError: collector ? collector.geoInstallError : ""
    readonly property bool needsGeoIp: (!snapshot || snapshot.database.state !== "ready")
    function installGeoIp() { if (collector) collector.installGeoIp(); }
    readonly property bool engineInstalling: collector ? collector.engineInstalling : false
    readonly property string engineInstallError: collector ? collector.engineInstallError : ""
    readonly property bool needsEngine: collector ? collector.engineMissing : false
    function installEngine() { if (collector) collector.installEngine(); }
    function configure(backend, database, latitude, longitude, interval, originName) {
        var lat = latitude.trim(), lon = longitude.trim(), seconds = Number(interval);
        if (!validPath(backend) || !validPath(database) || /[\x00-\x1f]/.test(backend + database)) return "Use absolute file paths.";
        if ((lat === "") !== (lon === "") || (lat !== "" && !validCoordinates(Number(lat), Number(lon))))
            return "Enter both coordinates: latitude −90…90, longitude −180…180.";
        if (!validInterval(seconds)) return "Refresh interval must be 1–60 seconds.";
        var name = typeof originName === "string" ? originName.slice(0,240) : origin && origin.lat === Number(lat) && origin.lon === Number(lon) ? origin.name || "" : "";
        var config = Object.assign({}, savedConfiguration, {backendPath:backend, databasePath:database, origin:lat === "" ? null : {lat:Number(lat),lon:Number(lon),name:name}, intervalSeconds:seconds});
        // updateEntryInline returns whether shell.json changed, not whether saving
        // failed: an entry that is already up to date also returns false.
        if (shell) shell.updateEntryInline("io.github.simoz.outbound", config);
        else if (saveConfiguration && JSON.stringify(config) !== JSON.stringify(savedConfiguration) && !saveConfiguration(config)) return "Unable to save settings.";
        loadConfiguration(config); return "";
    }
    function loadConfiguration(config) {
        if (!config || JSON.stringify(config) === JSON.stringify(savedConfiguration)) return;
        savedConfiguration = config;
        backendPath = typeof config.backendPath === "string" ? config.backendPath : "";
        databasePath = typeof config.databasePath === "string" ? config.databasePath : "";
        origin = config.origin && validCoordinates(config.origin.lat, config.origin.lon) ? config.origin : null;
        intervalSeconds = validInterval(config.intervalSeconds) ? config.intervalSeconds : 2;
    }
    // Empty paths select the managed defaults.
    function validPath(path) { return !path || (path[0] === "/" && path.length <= 4096); }
    function validCoordinates(lat, lon) {
        return typeof lat === "number" && typeof lon === "number" && isFinite(lat) && isFinite(lon) && Math.abs(lat) <= 90 && Math.abs(lon) <= 180;
    }
    function validInterval(seconds) { return Number.isInteger(seconds) && seconds >= 1 && seconds <= 60; }
    property string query: ""
    property string application: ""
    property string country: ""
    property string family: ""
    property string selection: ""
    property bool reducedMotion: false
    readonly property var countries: Geography.markers
    readonly property var rows: liveRows
    readonly property var filtered: Model.filter(rows, query, application, country, family, countries)
    readonly property var selected: Model.selected(filtered, selection)
    readonly property var applications: Model.groups(rows, "app")
    // Faceted counts ignore their own filter so choosing a country stays reversible.
    readonly property var destinations: Model.groups(Model.filter(rows, query, application, "", family, countries), "country")
    readonly property var applicationFacetRows: Model.filter(rows, query, "", country, family, countries)
    readonly property var countryApplications: Model.groups(applicationFacetRows, "app")
    readonly property int countryCount: Model.groups(rows.filter(function(row) {
        return row.country && row.country !== "local" && row.country !== "unknown";
    }), "country").length

    function clearFilters() {
        query = "";
        application = "";
        country = "";
        family = "";
    }

    function chooseCountry(code) {
        country = country === code ? "" : code;
    }

    function chooseApplication(name) { application = application === name ? "" : name; }
    function countryBadge(code) { return Model.countryBadge(code); }

    function countryName(code) { return Model.countryName(code, countries); }
    onFilteredChanged: if (!Model.selected(filtered, selection)) selection = ""
}
