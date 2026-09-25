import QtQuick
import "Model.js" as Model
import "assets/Countries.js" as Geography

Item {
    id: root
    property var shell: null
    property var manifest: null
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
    readonly property bool demanded: views.length > 0 && !paused
    readonly property int pollInterval: openViews > 0 ? intervalSeconds * 1000 : 10000
    readonly property string status: paused ? "PAUSED" : !views.length ? "IDLE" : phase.toUpperCase()
    readonly property var globeOrigin: origin
    readonly property string geoStatus: !snapshot ? "GeoIP not sampled" : snapshot.database.state !== "ready" ? "GeoIP " + snapshot.database.state : "GeoIP " + snapshot.database.releaseMonth + (snapshot.database.stale ? " · outdated" : "") + (snapshot.database.lookupErrors ? " · lookup errors" : "")
    readonly property string coverageStatus: !snapshot ? "No snapshot" : "IPv4: " + (snapshot.coverage.ipv4 || "ok") + " · IPv6: " + (snapshot.coverage.ipv6 || "ok") + " · Unknown owners: " + snapshot.aggregates.unknownOwners + " · Denied: " + snapshot.coverage.processes.denied + " · Races: " + snapshot.coverage.processes.races + " · Errors: " + snapshot.coverage.processes.errors + " · Omitted sockets: " + snapshot.coverage.omittedRows + " · Omitted owners: " + snapshot.coverage.processes.ownersOmitted + (snapshot.coverage.processes.timedOut ? " · Process scan timed out" : "") + (snapshot.coverage.processes.scanLimited ? " · Process scan limited" : "")
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
    function clearCitySearch() { if (citySearch) citySearch.clear(); }
    function setView(token, open) {
        var next = views.filter(function(v) { return v.token !== token; });
        next.push({token:token, open:open}); views = next;
    }
    function removeView(token) { views = views.filter(function(v) { return v.token !== token; }); }
    readonly property var collector: transport.item
    function retry() { if (collector) collector.retry(); }
    readonly property bool geoInstalling: collector ? collector.geoInstalling : false
    readonly property string geoInstallError: collector ? collector.geoInstallError : ""
    readonly property bool needsGeoIp: (!snapshot || snapshot.database.state !== "ready")
    function installGeoIp() { if (collector) collector.installGeoIp(); }
    function configure(backend, database, latitude, longitude, interval, originName) {
        var lat = latitude.trim(), lon = longitude.trim(), seconds = Number(interval);
        if ((backend && backend[0] !== "/") || (database && database[0] !== "/") || backend.length > 4096 || database.length > 4096 || /[\x00-\x1f]/.test(backend + database)) return "Use absolute file paths.";
        if ((lat === "") !== (lon === "") || (lat !== "" && (!isFinite(Number(lat)) || !isFinite(Number(lon)) || Math.abs(Number(lat)) > 90 || Math.abs(Number(lon)) > 180))) return "Enter both coordinates: latitude −90…90, longitude −180…180.";
        if (!Number.isInteger(seconds) || seconds < 1 || seconds > 60) return "Refresh interval must be 1–60 seconds.";
        var name = typeof originName === "string" ? originName.slice(0,240) : origin && origin.lat === Number(lat) && origin.lon === Number(lon) ? origin.name || "" : "";
        var config = Object.assign({}, savedConfiguration, {backendPath:backend, databasePath:database, origin:lat === "" ? null : {lat:Number(lat),lon:Number(lon),name:name}, intervalSeconds:seconds});
        if (shell && !shell.updateEntryInline("io.github.simoz.outbound", config)) return "Unable to save settings.";
        if (!shell && saveConfiguration && !saveConfiguration(config)) return "Unable to save settings.";
        loadConfiguration(config); return "";
    }
    function loadConfiguration(config) {
        if (!config || JSON.stringify(config) === JSON.stringify(savedConfiguration)) return;
        savedConfiguration = config;
        backendPath = typeof config.backendPath === "string" ? config.backendPath : "";
        databasePath = typeof config.databasePath === "string" ? config.databasePath : "";
        origin = config.origin && typeof config.origin.lat === "number" && typeof config.origin.lon === "number" && isFinite(config.origin.lat) && isFinite(config.origin.lon) && Math.abs(config.origin.lat) <= 90 && Math.abs(config.origin.lon) <= 180 ? config.origin : null;
        intervalSeconds = Number.isInteger(config.intervalSeconds) && config.intervalSeconds >= 1 && config.intervalSeconds <= 60 ? config.intervalSeconds : 2;
    }
    property string query: ""
    property string application: ""
    property string country: ""
    property string family: ""
    property string selection: ""
    property bool reducedMotion: false
    property bool scanlines: false
    property bool glow: true
    readonly property var countries: Geography.markers
    readonly property var rows: liveRows
    readonly property var filtered: Model.filter(rows, query, application, country, family)
    readonly property var selected: Model.selected(filtered, selection)
    readonly property var applications: Model.groups(rows, "app")
    // Faceted counts ignore their own filter so choosing a country stays reversible.
    readonly property var destinations: Model.groups(Model.filter(rows, query, application, "", family), "country")
    readonly property var applicationFacetRows: Model.filter(rows, query, "", country, family)
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
    function appBadge(name) { return Model.appBadge(name); }

    function countryName(code) { return Model.countryName(code, countries); }
    onFilteredChanged: if (!Model.selected(filtered, selection)) selection = ""
}
