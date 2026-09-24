// ASCII JSON permits arbitrary pipe chunk boundaries without splitting UTF-8.
var maxLine = 2 * 1024 * 1024;
function frame(buffer, chunk) {
    if (typeof chunk !== "string" || /[^\x00-\x7f]/.test(chunk) || chunk.length > maxLine) throw new Error("Invalid transport encoding or size");
    var lines = [], start = 0, end;
    while ((end = chunk.indexOf("\n", start)) >= 0) {
        if (buffer.length + end - start + 1 > maxLine) throw new Error("Snapshot too large");
        lines.push(buffer + chunk.slice(start, end));
        if (lines.length > 1) throw new Error("Unsolicited snapshots");
        buffer = ""; start = end + 1;
    }
    buffer += chunk.slice(start);
    if (buffer.length >= maxLine) throw new Error("Unterminated snapshot too large");
    return {buffer: buffer, lines: lines};
}
function integer(value, max) { return Number.isSafeInteger(value) && value >= 0 && value <= max; }
function text(value, max) { return typeof value === "string" && Array.from(value).length <= max && !/[\x00-\x1f\x7f]/.test(value); }
function object(value) { return value !== null && typeof value === "object" && !Array.isArray(value); }
function countMap(value) { return object(value) && Object.keys(value).length <= 65536 && Object.keys(value).every(function(k) { return text(k,128) && integer(value[k],4096); }); }
function ip(value, family) {
    if (typeof value !== "string" || value.length > 45) return false;
    function v4(v) { var parts = v.split("."); return parts.length === 4 && parts.every(function(p) { return /^(0|[1-9][0-9]{0,2})$/.test(p) && Number(p) <= 255; }); }
    if (family === "IPv4") return v4(value);
    var tail = value.lastIndexOf(":");
    if (value.indexOf(".") >= 0) { if (!v4(value.slice(tail+1))) return false; value = value.slice(0,tail+1) + "0:0"; }
    if (!/^[0-9a-f:]+$/i.test(value)) return false;
    var halves = value.split("::");
    if (halves.length > 2 || halves.some(function(h) { return h !== "" && h.split(":").some(function(p) { return p === ""; }); })) return false;
    var parts = halves.filter(function(v) { return v !== ""; }).join(":").split(":").filter(function(v) { return v !== ""; });
    return parts.every(function(v) { return /^[0-9a-f]{1,4}$/i.test(v); }) && (halves.length === 2 ? parts.length < 8 : parts.length === 8 && value[0] !== ":" && value[value.length-1] !== ":");
}
function parse(line, requestId, session, sequence) {
    var depth=0, quoted=false, escaped=false;
    for (var i=0;i<line.length;i++) {
        var c=line[i];
        if (quoted) { if (escaped) escaped=false; else if(c === "\\") escaped=true; else if(c === '"') quoted=false; }
        else if(c === '"') quoted=true;
        else if(c === "{" || c === "[") { if (++depth > 8) throw new Error("Snapshot nesting too deep"); }
        else if(c === "}" || c === "]") --depth;
    }
    var s = JSON.parse(line);
    function require(ok) { if (!ok) throw new Error("Invalid or incompatible backend snapshot"); }
    require(object(s) && s.version === 1 && s.kind === "snapshot" && s.requestId === requestId);
    require(typeof s.session === "string" && /^[0-9a-f]{32}$/.test(s.session) && (!session || s.session === session));
    require(integer(s.sequence,Number.MAX_SAFE_INTEGER) && s.sequence > sequence && integer(s.observedAtMs,Number.MAX_SAFE_INTEGER));
    require(["ok","partial","error"].indexOf(s.status)>=0);
    require(Array.isArray(s.connections) && s.connections.length <= 4096);
    var ids = Object.create(null), countries=Object.create(null), apps=Object.create(null), unknown=0;
    s.connections.forEach(function(r) {
        require(object(r) && text(r.id,160) && r.id.length > 0 && !ids[r.id]); ids[r.id]=true;
        require(["IPv4","IPv6"].indexOf(r.family)>=0 && object(r.local) && object(r.remote));
        [r.local,r.remote].forEach(function(e) { require(ip(e.address,r.family) && integer(e.port,65535)); });
        require(["ESTABLISHED","SYN_SENT","SYN_RECV","FIN_WAIT1","FIN_WAIT2","TIME_WAIT","CLOSE_WAIT","LAST_ACK","CLOSING","NEW_SYN_RECV"].indexOf(r.state)>=0);
        require(integer(r.uid,4294967295) && r.direction === "unknown");
        require(["public","loopback","private","linkLocal","shared","documentation","multicast","unspecified","reserved"].indexOf(r.scope)>=0);
        require(r.country === null || (typeof r.country === "string" && /^[A-Z]{2}$/.test(r.country) && r.country !== "ZZ" && r.scope === "public"));
        require(Array.isArray(r.owners) && r.owners.length <= 16);
        var names=Object.create(null), owners=Object.create(null);
        r.owners.forEach(function(o) {
            require(object(o) && integer(o.pid,4294967295) && o.pid>0 && typeof o.startTimeTicks === "string" && /^[0-9]{1,20}$/.test(o.startTimeTicks) && text(o.name,128));
            var key=o.pid+":"+o.startTimeTicks; require(!owners[key]); owners[key]=true; names[o.name]=true;
        });
        Object.keys(names).forEach(function(n) { apps[n]=(apps[n]||0)+1; });
        if(!r.owners.length) unknown++;
        var country=r.country || (r.scope === "public" ? "unknown" : "nonInternet"); countries[country]=(countries[country]||0)+1;
    });
    var coverage=s.coverage, db=s.database, a=s.aggregates;
    require(object(coverage) && coverage.namespace === "current" && typeof coverage.truncated === "boolean" && integer(coverage.omittedRows,Number.MAX_SAFE_INTEGER));
    [coverage.ipv4,coverage.ipv6].forEach(function(v) { require(v === null || ["denied","timeout","unavailable","interrupted","malformed","io"].indexOf(v)>=0); });
    var p=coverage.processes; require(object(p));
    ["denied","races","errors","ownersOmitted"].forEach(function(k) { require(integer(p[k],Number.MAX_SAFE_INTEGER)); });
    require(typeof p.timedOut === "boolean" && typeof p.scanLimited === "boolean");
    require(object(db) && ["ready","missing","unreadable","invalid"].indexOf(db.state)>=0 && typeof db.stale === "boolean" && integer(db.lookupErrors,Number.MAX_SAFE_INTEGER));
    require(db.buildEpochSeconds === null || integer(db.buildEpochSeconds,Number.MAX_SAFE_INTEGER));
    require(db.releaseMonth === null || (typeof db.releaseMonth === "string" && /^[0-9]{4}-(0[1-9]|1[0-2])$/.test(db.releaseMonth)));
    require(object(a) && a.sockets === s.connections.length && a.unknownOwners === unknown && countMap(a.countries) && countMap(a.applications));
    function equalCounts(left,right) { return Object.keys(left).length === Object.keys(right).length && Object.keys(left).every(function(k) { return left[k] === right[k]; }); }
    require(equalCounts(a.countries,countries) && equalCounts(a.applications,apps));
    return s;
}
function rows(snapshot) {
    return snapshot.connections.map(function(r) {
        var names=Array.from(new Set(r.owners.map(function(o) { return o.name || "Unnamed process"; })));
        return { id:r.id, app:names.length ? names.join(" / ") : "Unknown process", apps:names.length ? names : ["Unknown process"],
            pid:r.owners.length === 1 ? r.owners[0].pid : null, owners:r.owners, family:r.family,
            ip:r.remote.address, port:r.remote.port, state:r.state, country:r.country || (r.scope === "public" ? "unknown" : "local"), direction:"Unknown" };
    });
}
