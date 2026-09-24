import QtQuick
import Quickshell.Io

// Explicit searches only. Late/cancelled responses never update editor results.
Item {
    id: root
    property var service: null
    property bool busy: false
    property string query: ""
    property var results: []
    property string error: ""
    property var cache: []
    property double lastSearch: 0
    property string buffer: ""
    function clear() {
        query = ""; results = []; error = ""; buffer = "";
        deadline.stop();
        if (process.processId > 0) process.signal(15);
    }
    function search(value) {
        value = value.trim().slice(0,120);
        if (!service || service.openViews === 0 || busy || value.length < 2) return;
        query = value; results = []; error = "";
        var previous = cache.find(function(entry) { return entry.query === value.toLowerCase(); });
        if (previous) { results = previous.places; if (!results.length) error = "No cities found. Try adding the country."; return; }
        if (Date.now() - lastSearch < 1100) { error = "Please wait a moment before searching again."; return; }
        lastSearch = Date.now(); buffer = ""; busy = true;
        process.command = ["python3", "-B", decodeURIComponent(Qt.resolvedUrl("tools/search_city.py").toString().slice(7)), query];
        deadline.restart(); process.running = true;
    }
    function receive(data) {
        if (!query) return;
        if (buffer.length + data.length > 32768) { clear(); error = "Invalid city search response."; return; }
        buffer += data;
    }
    Connections {
        target: root.service
        function onOpenViewsChanged() { if (root.service.openViews === 0) root.clear(); }
    }
    Component.onDestruction: clear()
    Timer { id: deadline; interval: 15000; onTriggered: { root.clear(); root.error = "City search timed out. Try again."; } }
    Process {
        id: process
        property bool started: false
        stdout: SplitParser { splitMarker: ""; onRead: function(data) { root.receive(data); } }
        stderr: SplitParser { splitMarker: ""; onRead: function(data) {} }
        onStarted: { started = true; if (!root.query && processId > 0) signal(15); }
        onRunningChanged: {
            if (running) started = false;
            else if (!started && root.busy) { root.busy = false; deadline.stop(); root.error = "City search needs Python 3."; }
        }
        // qmllint disable signal-handler-parameters
        onExited: function(exitCode) {
            root.busy = false; deadline.stop();
            if (!root.query) return;
            try {
                var reply = JSON.parse(root.buffer);
                if (exitCode !== 0 || reply.query !== root.query || !reply.ok || !Array.isArray(reply.places) || reply.places.length > 6) throw new Error("Invalid search");
                if (!reply.places.every(function(p) { return p && typeof p.label === "string" && p.label.length <= 240 && typeof p.lat === "number" && isFinite(p.lat) && Math.abs(p.lat) <= 90 && typeof p.lon === "number" && isFinite(p.lon) && Math.abs(p.lon) <= 180; })) throw new Error("Invalid place");
                root.results = reply.places;
                root.cache = root.cache.slice(-19).concat([{query:root.query.toLowerCase(),places:reply.places}]);
                if (!root.results.length) root.error = "No cities found. Try adding the country.";
            } catch (e) { root.error = "City search unavailable. Try again or enter coordinates manually."; }
            root.buffer = "";
        }
        // qmllint enable signal-handler-parameters
    }
}
