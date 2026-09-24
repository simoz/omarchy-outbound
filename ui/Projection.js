var radians = Math.PI / 180;

function project(lon, lat, centerLon, centerLat) {
    var phi = lat * radians, lambda = (lon - centerLon) * radians;
    var center = centerLat * radians;
    return {
        x: Math.cos(phi) * Math.sin(lambda),
        y: Math.cos(center) * Math.sin(phi) - Math.sin(center) * Math.cos(phi) * Math.cos(lambda),
        z: Math.sin(center) * Math.sin(phi) + Math.cos(center) * Math.cos(phi) * Math.cos(lambda)
    };
}

function path(points, lon, lat, radius, cx, cy) {
    var segments = [], previous = null, pen = false;
    points.forEach(function(point) {
        var next = project(point[0], point[1], lon, lat);
        if (previous && (previous.z >= 0) !== (next.z >= 0)) {
            var t = previous.z / (previous.z - next.z);
            var x = previous.x + (next.x - previous.x) * t;
            var y = previous.y + (next.y - previous.y) * t;
            var length = Math.hypot(x, y);
            // The clipped endpoint lies on the sphere's visible limb.
            segments.push([pen ? "L" : "M", cx + radius * x / length, cy - radius * y / length]);
            pen = next.z >= 0;
        }
        if (next.z >= 0) {
            segments.push([pen ? "L" : "M", cx + radius * next.x, cy - radius * next.y]);
            pen = true;
        } else pen = false;
        previous = next;
    });
    return segments;
}

function graticule() {
    var lines = [];
    for (var lat = -60; lat <= 60; lat += 30) {
        var parallel = [];
        for (var lon = -180; lon <= 180; lon += 3) parallel.push([lon, lat]);
        lines.push(parallel);
    }
    for (var meridian = -180; meridian < 180; meridian += 30) {
        var points = [];
        for (var angle = -90; angle <= 90; angle += 3) points.push([meridian, angle]);
        lines.push(points);
    }
    return lines;
}

function arc(from, to) {
    function vector(p) {
        var lat = p[1] * radians, lon = p[0] * radians;
        return [Math.cos(lat) * Math.cos(lon), Math.cos(lat) * Math.sin(lon), Math.sin(lat)];
    }
    var a = vector(from), b = vector(to);
    var omega = Math.acos(Math.max(-1, Math.min(1, a[0]*b[0]+a[1]*b[1]+a[2]*b[2])));
    if (omega < 0.00001) return [from, to];
    var points = [];
    for (var i = 0; i <= 40; i++) {
        var u = Math.sin((1 - i / 40) * omega) / Math.sin(omega);
        var v = Math.sin(i / 40 * omega) / Math.sin(omega);
        var x = u*a[0]+v*b[0], y = u*a[1]+v*b[1], z = u*a[2]+v*b[2];
        points.push([Math.atan2(y, x)/radians, Math.atan2(z, Math.hypot(x,y))/radians]);
    }
    return points;
}

function paths(lines, lon, lat, radius, cx, cy) {
    var result = [];
    lines.forEach(function(line) { result = result.concat(path(line, lon, lat, radius, cx, cy)); });
    return result;
}

function svg(points) {
    return points.map(function(p) { return p[0] + p[1].toFixed(2) + "," + p[2].toFixed(2); }).join(" ");
}

function wrap(value) { return ((value + 180) % 360 + 360) % 360 - 180; }
