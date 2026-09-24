function filter(rows, query, app, country, family) {
    var needle = query.trim().toLowerCase();
    return rows.filter(function(row) {
        return (!app || (row.apps ? row.apps.indexOf(app) >= 0 : row.app === app)) && (!country || row.country === country)
            && (!family || row.family === family)
            && (!needle || [row.app, row.ip, row.country, row.state].join(" ").toLowerCase().indexOf(needle) >= 0);
    });
}

function groups(rows, key) {
    var counts = Object.create(null);
    rows.forEach(function(row) {
        var values = key === "app" && row.apps ? row.apps : [row[key]];
        values.forEach(function(value) { counts[value] = (counts[value] || 0) + 1; });
    });
    return Object.keys(counts).map(function(value) { return {value: value, count: counts[value]}; })
        .sort(function(a, b) { return b.count - a.count || a.value.localeCompare(b.value); });
}

function countryName(code, countries) {
    if (!code || code === "unknown") return "Unknown location";
    if (code === "local") return "Local / special";
    var country = countries.find(function(item) { return item.code === code; });
    return country ? country.name : code;
}

function selected(rows, id) {
    return rows.find(function(row) { return row.id === id; }) || null;
}

function countryBadge(code) {
    if (code === "local") return "⌂";
    if (code === "unknown" || !code) return "?";
    return String.fromCodePoint(127397 + code.charCodeAt(0), 127397 + code.charCodeAt(1));
}

function appBadge(name) {
    return {"Browser": "◎", "Code editor": "⌘", "Music": "♫", "Sync": "↻", "Terminal": ">_"}[name] || "◇";
}
