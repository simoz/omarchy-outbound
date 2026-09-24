// Documentation-only IP ranges. Countries and applications are fictional assignments,
// not GeoIP results; production collection must never geolocate these special ranges.
var countries = [
    {code: "US", name: "United States", lon: -100, lat: 39},
    {code: "DE", name: "Germany", lon: 10, lat: 51},
    {code: "GB", name: "United Kingdom", lon: -3, lat: 55},
    {code: "JP", name: "Japan", lon: 138, lat: 37},
    {code: "BR", name: "Brazil", lon: -52, lat: -12},
    {code: "ZA", name: "South Africa", lon: 25, lat: -29},
    {code: "AU", name: "Australia", lon: 134, lat: -25},
    {code: "IN", name: "India", lon: 79, lat: 23}
];

function connections(scenario) {
    if (scenario === "empty" || scenario === "error") return [];
    var apps = ["Browser", "Code editor", "Music", "Sync", "Terminal"];
    var rows = [];
    var count = scenario === "busy" ? 240 : 24;
    var sampleCountries = ["US", "DE", "GB", "JP", "BR", "ZA", "US", "DE", "AU", "IN", "US", "DE", "GB", "DE", "US", "DE", "unknown", "local", "DE", "US", "DE", "DE", "GB", "JP"];
    for (var i = 0; i < count; i++) {
        var ipv6 = i % 3 === 0;
        var country = countries[i % countries.length];
        rows.push({
            id: "demo-" + i,
            app: scenario === "busy" && i % 7 === 0
                ? "Development workspace — extraordinarily long application name"
                : apps[i % apps.length],
            pid: 1200 + i % apps.length,
            family: ipv6 ? "IPv6" : "IPv4",
            ip: ipv6 ? "2001:db8::" + (i + 1).toString(16) : "203.0.113." + (i + 1),
            port: i % 5 === 0 ? 22 : 443,
            state: i % 7 === 0 ? "CLOSE_WAIT" : "ESTABLISHED",
            country: scenario === "busy" ? (i === 16 ? "unknown" : i === 17 ? "local" : country.code) : sampleCountries[i],
            direction: "Unknown"
        });
    }
    rows[16].app = "Unknown process";
    rows[16].pid = null;
    rows[17].ip = "127.0.0.1";
    rows[17].family = "IPv4";
    return rows;
}
