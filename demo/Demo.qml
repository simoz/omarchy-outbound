import QtQuick
import QtQuick.Window
import Quickshell
import qs.Commons
import "plugin" as Plugin
import "plugin/ui" as Outbound

// Scripted promo: the real Dashboard fed by demo/fixtures/outbound-engine.
// Every frame is rendered from the timeline time t, then saved as PNG.
ShellRoot {
    id: root
    readonly property int fps: Number(Quickshell.env("DEMO_FPS")) || 30
    readonly property string outDir: Quickshell.env("DEMO_FRAMES") || ""
    readonly property real duration: 20
    property int frame: 0
    property real t: 0
    property var fired: ({})

    // Camera keyframes in dashboard coordinates: centre (x, y) and scale s.
    readonly property var camera: [
        {t: 0.0, x: 600, y: 500, s: 0.9},
        {t: 2.2, x: 590, y: 480, s: 0.97},
        {t: 3.4, x: 400, y: 330, s: 1.45},
        {t: 6.2, x: 400, y: 330, s: 1.45},
        {t: 7.2, x: 900, y: 250, s: 1.55},
        {t: 9.4, x: 900, y: 250, s: 1.55},
        {t: 10.3, x: 900, y: 500, s: 1.55},
        {t: 12.0, x: 900, y: 500, s: 1.55},
        {t: 13.0, x: 760, y: 740, s: 1.25},
        {t: 16.4, x: 760, y: 740, s: 1.25},
        {t: 17.6, x: 600, y: 500, s: 0.9},
        {t: 20.0, x: 600, y: 500, s: 0.9}
    ]
    // Cursor keyframes: target is an item finder, resolved each frame.
    readonly property var cursor: [
        {t: 0.0, p: [1250, 1100]},
        {t: 1.6, p: [1250, 1100]},
        {t: 3.0, p: "zoomIn"},
        {t: 6.0, p: "zoomIn"},
        {t: 7.4, p: "country:DE"},
        {t: 9.8, p: "country:DE"},
        {t: 10.8, p: "app:firefox"},
        {t: 12.4, p: "app:firefox"},
        {t: 13.4, p: "row:1"},
        {t: 14.6, p: "row:1"},
        {t: 15.4, p: "copy"},
        {t: 16.2, p: "copy"},
        {t: 17.2, p: "clear"},
        {t: 18.2, p: "clear"},
        {t: 20.0, p: [1250, 1100]}
    ]
    readonly property var clicks: [
        {t: 3.6, run: function() { root.animate(dashboard.globe, "zoom", 1.44, 0.5); }},
        {t: 8.0, run: function() {
            var g = dashboard.globe, lon = g.longitude, lat = g.latitude;
            service.chooseCountry("DE");
            var lon2 = g.longitude, lat2 = g.latitude;
            g.longitude = lon; g.latitude = lat;
            root.animate(g, "longitude", lon2, 1.0); root.animate(g, "latitude", lat2, 1.0);
        }},
        {t: 11.2, run: function() { service.chooseApplication("firefox"); }},
        {t: 14.0, run: function() { var r = root.row(1); if (r) service.selection = r.modelData.id; }},
        {t: 15.8, run: function() { dashboard.feedback = "Copied " + service.selected.ip; }},
        {t: 17.6, run: function() {
            dashboard.feedback = ""; service.clearFilters(); service.selection = "";
            root.animate(dashboard.globe, "zoom", 1, 1.0);
        }}
    ]

    property var tweens: []
    function animate(target, prop, to, seconds) {
        tweens = tweens.filter(function(w) { return !(w.target === target && w.prop === prop); })
            .concat([{target: target, prop: prop, from: target[prop], to: to, start: t, end: t + seconds}]);
    }
    function ease(x) { x = Math.max(0, Math.min(1, x)); return x < 0.5 ? 4*x*x*x : 1 - Math.pow(-2*x + 2, 3) / 2; }
    function find(item, test) {
        if (!item) return null;
        if (test(item)) return item;
        for (var i = 0; i < item.children.length; i++) {
            var hit = find(item.children[i], test);
            if (hit) return hit;
        }
        if (item.contentItem && item.contentItem !== item) return find(item.contentItem, test);
        return null;
    }
    function row(n) {
        var list = find(dashboard, function(i) { return i.objectName === "outboundConnections"; });
        return list ? find(list, function(i) { return i.objectName && i.objectName.indexOf("connection-") === 0 && i.index === n; }) : null;
    }
    function locate(p) {
        if (Array.isArray(p)) return {x: p[0], y: p[1]};
        var item = null, parts = p.split(":");
        if (p === "zoomIn") item = find(dashboard, function(i) { return i.objectName === "globeZoomIn"; });
        else if (p === "copy") item = find(dashboard, function(i) { return i.objectName === "copyIpButton"; });
        else if (p === "clear") item = find(dashboard, function(i) { return i.hint === "Clear filters"; });
        else if (parts[0] === "row") item = row(Number(parts[1]));
        else item = find(dashboard.contentHolder, function(i) {
            return i.modelData && i.modelData.value === parts[1] && i.visible && i.width > 0 && (parts[0] === "app") === (i.parent && root.inBreakdown(i));
        });
        if (!item) return null;
        var m = item.mapToItem(dashboard, item.width * (parts[0] === "row" ? 0.3 : 0.5), item.height * 0.55);
        return {x: m.x, y: m.y};
    }
    function inBreakdown(i) {
        for (var p = i; p; p = p.parent) if (p.objectName === "outboundApplications") return true;
        return false;
    }
    function track(keys, time, value) {
        var i = 0;
        while (i < keys.length - 2 && keys[i + 1].t <= time) i++;
        var a = keys[i], b = keys[i + 1];
        return value(a, b, ease((time - a.t) / Math.max(0.001, b.t - a.t)));
    }
    property var lastCursor: ({x: 1250, y: 1100})
    function apply() {
        tweens.forEach(function(w) { w.target[w.prop] = w.from + (w.to - w.from) * ease((t - w.start) / (w.end - w.start)); });
        tweens = tweens.filter(function(w) { return t < w.end; });
        clicks.forEach(function(c, i) {
            if (!root.fired[i] && t >= c.t) { root.fired[i] = true; c.run(); ripple.at = t; }
        });
        if (!service.country && !tweens.some(function(w) { return w.prop === "longitude"; }))
            dashboard.globe.longitude += 9 / fps;
        var cam = track(camera, t, function(a, b, k) {
            return {x: a.x + (b.x - a.x)*k, y: a.y + (b.y - a.y)*k, s: a.s + (b.s - a.s)*k};
        });
        camScale.xScale = camScale.yScale = cam.s;
        camMove.x = stage.width/2 - cam.x*cam.s;
        camMove.y = stage.height/2 - cam.y*cam.s;
        var pos = track(cursor, t, function(a, b, k) {
            var pa = root.locate(a.p) || root.lastCursor, pb = root.locate(b.p) || pa;
            return {x: pa.x + (pb.x - pa.x)*k, y: pa.y + (pb.y - pa.y)*k};
        });
        lastCursor = pos;
        pointer.x = camMove.x + pos.x*cam.s;
        pointer.y = camMove.y + pos.y*cam.s;
    }

    Plugin.Service {
        id: service
        standalone: true
        saveConfiguration: function(config) { return true; }
        Component.onCompleted: {
            reducedMotion = false;
            loadConfiguration({backendPath: Quickshell.env("OUTBOUND_BACKEND"), databasePath: "",
                               origin: {lat: 45.46, lon: 9.19, name: "Milano"}, intervalSeconds: 2});
        }
    }
    Window {
        id: window
        visible: true
        width: 1080; height: 1080
        color: Color.background
        Component.onCompleted: service.setView(window, true)
        Item {
            id: stage
            // Fixed size: the offscreen platform may not honour the window size.
            width: 1080; height: 1080
            clip: true
            Rectangle { anchors.fill: parent; color: Color.background }
            Item {
                id: dashboard
                // Wrapper so we can find items and read the Dashboard API in one place.
                property alias globe: board.globe
                property alias feedback: board.feedback
                readonly property Item contentHolder: board
                width: 1200; height: 1000
                transform: [Scale { id: camScale }, Translate { id: camMove }]
                Outbound.Dashboard {
                    id: board
                    anchors.fill: parent
                    service: service
                    expanded: true
                    surfaceSwitchAvailable: false
                }
            }
            Item {
                id: pointer
                width: 1; height: 1
                Rectangle {
                    id: ripple
                    property real at: -10
                    readonly property real k: Math.max(0, Math.min(1, (root.t - at) / 0.45))
                    visible: k > 0 && k < 1
                    width: 16 + 44*k; height: width; radius: width/2
                    x: -width/2; y: -height/2
                    color: "transparent"; border.width: 3
                    border.color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 1 - k)
                }
                Canvas {
                    width: 30; height: 36
                    onPaint: {
                        var c = getContext("2d");
                        c.beginPath(); c.moveTo(2, 2); c.lineTo(2, 27); c.lineTo(8.5, 21); c.lineTo(13, 31);
                        c.lineTo(17.5, 29); c.lineTo(13, 19.5); c.lineTo(21.5, 19.5); c.closePath();
                        c.fillStyle = "#f4f4f4"; c.fill();
                        c.lineWidth = 1.6; c.strokeStyle = "#111111"; c.stroke();
                    }
                }
            }
        }
    }

    // Wait for live data, then step through frames: apply(t) → let canvases paint → grab.
    Timer {
        id: warmup
        interval: 300; repeat: true; running: true
        onTriggered: if (service.rows.length > 0) { stop(); settleFrame.start(); }
    }
    Timer { id: settleFrame; interval: 1500; onTriggered: root.nextFrame() }
    function nextFrame() {
        t = frame / fps;
        apply();
        paintWait.start();
    }
    Timer {
        id: paintWait
        interval: 45
        onTriggered: stage.grabToImage(function(result) {
            if (root.outDir) result.saveToFile(root.outDir + "/f" + String(root.frame).padStart(4, "0") + ".png");
            if (++root.frame > root.duration * root.fps) { console.log("DEMO_COMPLETE", root.frame); Qt.quit(); }
            else root.nextFrame();
        })
    }
}
