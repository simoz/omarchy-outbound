import QtQuick
import QtQuick.Window
import Quickshell
import qs.Commons
import "plugin" as Plugin
import "plugin/ui" as Outbound

// Scripted launch video: title card, the real Dashboard fed by
// demo/fixtures/outbound-engine with captions, end card with install command.
ShellRoot {
    id: root
    readonly property int fps: Number(Quickshell.env("DEMO_FPS")) || 30
    readonly property string outDir: Quickshell.env("DEMO_FRAMES") || ""
    readonly property real duration: 28
    property int frame: 0
    property real t: 0
    property var fired: ({})
    readonly property string typed: "2001:db8"

    // Camera keyframes in dashboard coordinates: centre (x, y) and scale s.
    readonly property var camera: [
        {t: 0.0, x: 600, y: 500, s: 0.9},
        {t: 2.6, x: 600, y: 500, s: 0.9},
        {t: 5.6, x: 590, y: 480, s: 0.98},
        {t: 6.6, x: 400, y: 330, s: 1.45},
        {t: 9.2, x: 400, y: 330, s: 1.45},
        {t: 10.2, x: 900, y: 250, s: 1.55},
        {t: 12.4, x: 900, y: 250, s: 1.55},
        {t: 13.2, x: 900, y: 500, s: 1.55},
        {t: 15.2, x: 900, y: 500, s: 1.55},
        {t: 16.0, x: 440, y: 330, s: 1.6},
        {t: 18.0, x: 440, y: 330, s: 1.6},
        {t: 18.8, x: 760, y: 740, s: 1.25},
        {t: 21.4, x: 760, y: 740, s: 1.25},
        {t: 22.4, x: 600, y: 500, s: 0.9},
        {t: 28.0, x: 600, y: 500, s: 0.9}
    ]
    // Cursor keyframes: p is dashboard coordinates or a named target resolved each frame.
    readonly property var cursor: [
        {t: 0.0, p: [1250, 1100]},
        {t: 5.4, p: [1250, 1100]},
        {t: 6.6, p: "zoomIn"},
        {t: 9.2, p: "zoomIn"},
        {t: 10.4, p: "country:DE"},
        {t: 12.6, p: "country:DE"},
        {t: 13.4, p: "app:firefox"},
        {t: 15.2, p: "app:firefox"},
        {t: 16.0, p: "search"},
        {t: 18.0, p: "search"},
        {t: 18.9, p: "row:0"},
        {t: 19.8, p: "row:0"},
        {t: 20.4, p: "copy"},
        {t: 21.2, p: "copy"},
        {t: 22.0, p: "clear"},
        {t: 22.8, p: "clear"},
        {t: 24.0, p: [1250, 1100]},
        {t: 28.0, p: [1250, 1100]}
    ]
    readonly property var clicks: [
        {t: 7.0, run: function() { root.animate(dashboard.globe, "zoom", 1.44, 0.5); }},
        {t: 10.8, run: function() {
            var g = dashboard.globe, lon = g.longitude, lat = g.latitude;
            service.chooseCountry("DE");
            var lon2 = g.longitude, lat2 = g.latitude;
            g.longitude = lon; g.latitude = lat;
            root.animate(g, "longitude", lon2, 1.0); root.animate(g, "latitude", lat2, 1.0);
        }},
        {t: 13.8, run: function() { service.chooseApplication("firefox"); }},
        {t: 16.3, run: function() {}},
        {t: 19.2, run: function() { var r = root.row(0); if (r) service.selection = r.modelData.id; }},
        {t: 20.7, run: function() { dashboard.feedback = "Copied " + service.selected.ip; }},
        {t: 22.3, run: function() {
            dashboard.feedback = ""; service.clearFilters(); service.selection = "";
            root.animate(dashboard.globe, "zoom", 1, 1.0);
        }}
    ]
    // Lower-third captions, in stage coordinates.
    readonly property var captions: [
        {from: 3.0, to: 6.3, label: "LIVE", text: "Every TCP connection your apps open"},
        {from: 6.6, to: 9.9, label: "GLOBE", text: "Rotate it, zoom up to 4×"},
        {from: 10.2, to: 13.0, label: "COUNTRIES", text: "See who talks to each country"},
        {from: 13.3, to: 15.7, label: "APPS", text: "Filter by application"},
        {from: 16.0, to: 18.4, label: "SEARCH", text: "Find any IP or process"},
        {from: 18.7, to: 21.8, label: "DETAILS", text: "Inspect and copy any connection"},
        {from: 22.2, to: 24.6, label: "LOCAL", text: "Local collector · offline GeoIP"}
    ]
    readonly property var caption: captions.find(function(c) { return t >= c.from && t < c.to; }) || null
    function fade(from, to, span) { return Math.max(0, Math.min(1, (t - from) / span, (to - t) / span)); }

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
        else if (p === "search") item = find(dashboard, function(i) { return i.objectName === "connectionSearch"; });
        else if (p === "clear") item = find(dashboard, function(i) { return i.hint === "Clear filters"; });
        else if (parts[0] === "row") item = row(Number(parts[1]));
        else item = find(dashboard.contentHolder, function(i) {
            return i.modelData && i.modelData.value === parts[1] && i.visible && i.width > 0 && (parts[0] === "app") === root.inBreakdown(i);
        });
        if (!item) return null;
        var m = item.mapToItem(dashboard, item.width * (parts[0] === "row" ? 0.3 : p === "search" ? 0.8 : 0.5), item.height * 0.55);
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
        // Type the search one character at a time, as a user would.
        if (t >= 16.5 && t < 22.3) {
            var q = typed.slice(0, Math.min(typed.length, Math.floor((t - 16.5) / 0.11) + 1));
            if (service.query !== q) service.query = q;
        }
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
    Outbound.Theme { id: theme }
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
                opacity: root.fade(4.6, 24.2, 0.4)
                Rectangle {
                    id: ripple
                    property real at: -10
                    readonly property real k: Math.max(0, Math.min(1, (root.t - at) / 0.45))
                    visible: k > 0 && k < 1
                    width: 16 + 44*k; height: width; radius: width/2
                    x: -width/2; y: -height/2
                    color: "transparent"; border.width: 3
                    border.color: Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 1 - k)
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
            // Lower-third caption.
            Rectangle {
                id: captionBox
                readonly property var current: root.caption
                visible: current !== null
                opacity: current ? root.fade(current.from, current.to, 0.3) : 0
                anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 64 - 12 * (1 - opacity) }
                width: captionRow.implicitWidth + 44; height: 64
                color: Qt.rgba(theme.background.r, theme.background.g, theme.background.b, 0.94)
                border.color: theme.fade(theme.accent, 0.55); border.width: 1.5
                Row {
                    id: captionRow
                    anchors.centerIn: parent
                    spacing: 16
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: captionBox.current ? captionBox.current.label : ""
                        color: theme.accent; font.family: theme.font; font.pixelSize: 17; font.letterSpacing: 2.5
                    }
                    Rectangle { width: 1.5; height: 26; color: theme.fade(theme.accent, 0.5); anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: captionBox.current ? captionBox.current.text : ""
                        color: theme.text; font.family: theme.font; font.pixelSize: 26
                    }
                }
            }
            // Title card, fading into the live dashboard.
            Rectangle {
                anchors.fill: parent
                color: Color.background
                opacity: 1 - Math.max(0, Math.min(1, (root.t - 2.2) / 0.8))
                visible: opacity > 0
                Column {
                    anchors.centerIn: parent
                    spacing: 22
                    opacity: root.fade(0.2, 2.6, 0.5)
                    Outbound.GlobeIcon { ink: theme.accent; width: 120; height: 120; anchors.horizontalCenter: parent.horizontalCenter }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "OUTBOUND"; color: theme.text
                        font.family: theme.font; font.pixelSize: 84; font.letterSpacing: 14
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "See where your apps connect."; color: theme.subdued
                        font.family: theme.font; font.pixelSize: 32
                    }
                }
            }
            // End card with the install command.
            Rectangle {
                anchors.fill: parent
                color: Color.background
                opacity: Math.max(0, Math.min(1, (root.t - 24.4) / 0.8))
                visible: opacity > 0
                Column {
                    anchors.centerIn: parent
                    spacing: 20
                    opacity: Math.max(0, Math.min(1, (root.t - 25.0) / 0.6))
                    Outbound.GlobeIcon { ink: theme.accent; width: 96; height: 96; anchors.horizontalCenter: parent.horizontalCenter }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "OUTBOUND"; color: theme.text
                        font.family: theme.font; font.pixelSize: 72; font.letterSpacing: 12
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "A network globe for your Omarchy bar"; color: theme.subdued
                        font.family: theme.font; font.pixelSize: 28
                    }
                    Item { width: 1; height: 26 }
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: command.implicitWidth + 48; height: 64
                        color: theme.wash; border.color: theme.fade(theme.accent, 0.55); border.width: 1.5
                        Text {
                            id: command
                            anchors.centerIn: parent
                            text: "<font color='" + theme.accent + "'>$</font> omarchy plugin add https://github.com/simoz/omarchy-outbound.git --enable"
                            textFormat: Text.RichText
                            color: theme.text; font.family: theme.font; font.pixelSize: 19
                        }
                    }
                }
            }
        }
    }

    // Wait for live data, then step through frames: apply(t) → let canvases paint → grab.
    Timer {
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
