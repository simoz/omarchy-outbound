import QtQuick
import QtQuick.Window
import Quickshell
import qs.Commons
import "plugin" as Plugin
import "plugin/ui" as Outbound

// Beat-cut launch video for X (28.8 s = 12 bars at 100 BPM).
// Cut to "First Contact" from 150.24 s so the drop lands on the 2.4 s cut:
//   DEMO_SCENE=Launch DEMO_AUDIO="demo/First Contact.mp3" DEMO_AUDIO_START=150.24 demo/run demo/outbound-launch.mp4
// All data comes from demo/fixtures/outbound-engine (fictional documentation ranges).
ShellRoot {
    id: root
    readonly property int fps: Number(Quickshell.env("DEMO_FPS")) || 30
    readonly property string outDir: Quickshell.env("DEMO_FRAMES") || ""
    readonly property real beat: 0.6
    readonly property real drop: 2.4
    readonly property real duration: 28.8
    property int frame: 0
    property real t: 0
    property var fired: ({})
    readonly property string typed: "2001:db8"
    readonly property real fitScale: 1080 / 1280

    // Camera shots in dashboard coordinates. `at` names a region resolved each frame;
    // `cut` jumps on its time instead of easing from the previous key.
    readonly property var camera: [
        {t: 0.0, at: "globe", s: 2.3},
        {t: 2.4, at: "globe", s: 2.3, cut: true},
        {t: 4.7, at: "globe", s: 2.0},
        {t: 4.8, at: "apps", s: 2.25, cut: true},
        {t: 7.1, at: "apps", s: 2.0},
        {t: 7.2, at: "countries", s: 2.25, cut: true},
        {t: 9.5, at: "countries", s: 2.0},
        {t: 9.6, at: "full", s: 1.05, cut: true},
        {t: 11.9, at: "full", s: 0.86},
        {t: 12.0, at: "globe", s: 1.6, cut: true},
        {t: 13.1, at: "globe", s: 1.7},
        {t: 13.2, at: "countries", s: 2.1, cut: true},
        {t: 14.3, at: "countries", s: 2.2},
        {t: 14.4, at: "apps", s: 2.1, cut: true},
        {t: 15.5, at: "apps", s: 2.2},
        {t: 15.6, at: "filters", s: 2.4, cut: true},
        {t: 16.7, at: "filters", s: 2.5},
        {t: 16.8, at: "table", s: 1.55, cut: true},
        {t: 17.6, at: "table", s: 1.6},
        {t: 18.0, at: "copy", s: 2.1},
        {t: 19.1, at: "copy", s: 2.2},
        {t: 19.2, at: "globe", s: 2.2, cut: true},
        {t: 21.5, at: "globe", s: 1.9},
        {t: 21.6, at: "full", s: 0.84, cut: true},
        {t: 24.0, at: "full", s: 0.95},
        {t: 28.8, at: "full", s: 0.95}
    ]
    // Cursor keys, same cut semantics; p is a named target or dashboard coordinates.
    readonly property var cursor: [
        {t: 0.0, p: [1400, 1300]},
        {t: 12.0, p: [1400, 1300]},
        {t: 12.0, p: "zoomIn+", cut: true},
        {t: 12.35, p: "zoomIn"},
        {t: 13.2, p: "country:DE+", cut: true},
        {t: 13.55, p: "country:DE"},
        {t: 14.4, p: "app:firefox+", cut: true},
        {t: 14.75, p: "app:firefox"},
        {t: 15.6, p: "search+", cut: true},
        {t: 15.9, p: "search"},
        {t: 16.8, p: "row:0+", cut: true},
        {t: 17.1, p: "row:0"},
        {t: 17.7, p: "row:0"},
        {t: 18.1, p: "copy"},
        {t: 19.2, p: [1400, 1300], cut: true},
        {t: 28.8, p: [1400, 1300]}
    ]
    readonly property var clicks: [
        // Face Europe before zooming so the arcs from the origin fill the shot.
        {t: 12.0, click: false, run: function() {
            root.animate(dashboard.globe, "longitude", 10, 0.4); root.animate(dashboard.globe, "latitude", 42, 0.4);
        }},
        {t: 12.45, run: function() { root.animate(dashboard.globe, "zoom", 2.2, 0.55); }},
        {t: 13.65, run: function() {
            var g = dashboard.globe, lon = g.longitude, lat = g.latitude;
            service.chooseCountry("DE");
            var lon2 = g.longitude, lat2 = g.latitude;
            g.longitude = lon; g.latitude = lat;
            root.animate(g, "longitude", lon2, 0.7); root.animate(g, "latitude", lat2, 0.7);
        }},
        {t: 14.85, run: function() { service.chooseApplication("firefox"); }},
        // Search the whole list: the country and app filters would leave a single row.
        {t: 15.6, click: false, run: function() { service.clearFilters(); }},
        {t: 16.0, run: function() {}},
        {t: 17.2, run: function() { var r = root.row(0); if (r) service.selection = r.modelData.id; }},
        {t: 18.2, run: function() { dashboard.feedback = "Copied " + service.selected.ip; }},
        {t: 19.2, click: false, run: function() {
            dashboard.feedback = ""; service.clearFilters(); service.selection = "";
            root.animate(dashboard.globe, "zoom", 1.35, 0.9);
        }}
    ]
    // Kinetic type: each line lands on its own beat.
    readonly property var words: [
        {from: 2.4, to: 4.8, lines: [[2.4, "EVERY"], [3.0, "CONNECTION."]]},
        {from: 4.8, to: 7.2, lines: [[4.8, "EVERY"], [5.4, "APP."]]},
        {from: 7.2, to: 9.6, lines: [[7.2, "EVERY"], [7.8, "COUNTRY."]]},
        {from: 9.6, to: 12.0, lines: [[9.6, "LIVE"], [10.2, "FROM YOUR BAR."]]},
        {from: 12.0, to: 13.2, small: true, lines: [[12.0, "ZOOM IN"]]},
        {from: 13.2, to: 14.4, small: true, lines: [[13.2, "PICK A COUNTRY"]]},
        {from: 14.4, to: 15.6, small: true, lines: [[14.4, "FILTER BY APP"]]},
        {from: 15.6, to: 16.8, small: true, lines: [[15.6, "SEARCH ANY IP"]]},
        {from: 16.8, to: 19.2, small: true, lines: [[16.8, "INSPECT."], [18.0, "COPY."]]},
        {from: 19.2, to: 21.6, small: true, lines: [[19.2, "LOCAL"], [19.8, "COLLECTOR."], [20.4, "OFFLINE"], [21.0, "GEOIP."]]},
        {from: 21.6, to: 24.0, lines: [[21.6, "SEE WHERE"], [22.2, "YOUR APPS"], [22.8, "CONNECT."]]}
    ]
    readonly property var cuts: [2.4, 4.8, 7.2, 9.6, 12.0, 13.2, 14.4, 15.6, 16.8, 19.2, 21.6, 24.0]
    readonly property var block: words.find(function(w) { return t >= w.from && t < w.to; }) || null

    function clamp(x) { return Math.max(0, Math.min(1, x)); }
    function fade(from, to, span) { return clamp(Math.min((t - from) / span, (to - t) / span)); }
    // Decaying pulse on every beat after the drop; downbeats hit harder.
    function pulse(amount) {
        if (t < drop) return 0;
        var n = Math.floor((t - drop) / beat), phase = t - drop - n * beat;
        return amount * (n % 4 === 0 ? 1 : 0.45) * Math.exp(-phase * 9);
    }
    function flash() {
        var best = 0;
        cuts.forEach(function(c) { if (t >= c) best = Math.max(best, (c === drop || c === 24.0 ? 0.85 : 0.35) * Math.exp(-(t - c) * 10)); });
        return best;
    }

    property var tweens: []
    function animate(target, prop, to, seconds) {
        tweens = tweens.filter(function(w) { return !(w.target === target && w.prop === prop); })
            .concat([{target: target, prop: prop, from: target[prop], to: to, start: t, end: t + seconds}]);
    }
    function ease(x) { x = clamp(x); return x < 0.5 ? 4*x*x*x : 1 - Math.pow(-2*x + 2, 3) / 2; }
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
    function named(name) { return find(board, function(i) { return i.objectName === name; }); }
    function row(n) {
        var list = named("outboundConnections");
        return list ? find(list, function(i) { return i.objectName && i.objectName.indexOf("connection-") === 0 && i.index === n; }) : null;
    }
    function inBreakdown(i) {
        for (var p = i; p; p = p.parent) if (p.objectName === "outboundApplications") return true;
        return false;
    }
    function centre(item, fx, fy) {
        var m = item.mapToItem(dashboard, item.width * fx, item.height * fy);
        return {x: m.x, y: m.y};
    }
    function region(name) {
        if (name === "full") return {x: 640, y: 600};
        if (name === "globe") return centre(dashboard.globe, 0.5, 0.5);
        if (name === "apps") return centre(named("outboundApplications"), 0.5, 0.4);
        if (name === "countries") {
            var apps = named("outboundApplications");
            var list = apps.parent.children.find(function(c) { return c !== apps && c.visible && c.height > 0; });
            return centre(list, 0.5, 0.45);
        }
        if (name === "filters") return centre(named("connectionSearch"), 0.3, 0.9);
        if (name === "table") return centre(named("outboundConnections"), 0.45, 0.3);
        // Keep the button above the kinetic type, in the right half of the frame.
        if (name === "copy") { var c = centre(named("copyIpButton"), 0.5, 0.5); return {x: c.x - 143, y: c.y + 29}; }
        return {x: 640, y: 600};
    }
    // "+" marks the cursor entry point just off the target, so each cut starts with a short move.
    function locate(p) {
        if (Array.isArray(p)) return {x: p[0], y: p[1]};
        var offset = p.slice(-1) === "+";
        if (offset) p = p.slice(0, -1);
        var item = null, parts = p.split(":");
        if (p === "zoomIn") item = named("globeZoomIn");
        else if (p === "copy") item = named("copyIpButton");
        else if (p === "search") item = named("connectionSearch");
        else if (parts[0] === "row") item = row(Number(parts[1]));
        else item = find(board, function(i) {
            return i.modelData && i.modelData.value === parts[1] && i.visible && i.width > 0 && (parts[0] === "app") === root.inBreakdown(i);
        });
        if (!item) return null;
        var m = centre(item, parts[0] === "row" ? 0.3 : p === "search" ? 0.8 : 0.5, 0.55);
        return offset ? {x: m.x + 70, y: m.y + 90} : m;
    }
    function track(keys, time, value) {
        var i = 0;
        while (i < keys.length - 2 && keys[i + 1].t <= time) i++;
        var a = keys[i], b = keys[i + 1];
        if (b.cut) return value(a, a, 0);
        return value(a, b, ease((time - a.t) / Math.max(0.001, b.t - a.t)));
    }
    property var lastCursor: ({x: 1400, y: 1300})
    function apply() {
        tweens.forEach(function(w) { w.target[w.prop] = w.from + (w.to - w.from) * ease((t - w.start) / (w.end - w.start)); });
        tweens = tweens.filter(function(w) { return t < w.end; });
        clicks.forEach(function(c, i) {
            if (!root.fired[i] && t >= c.t) { root.fired[i] = true; c.run(); if (c.click !== false) ripple.at = t; }
        });
        if (t >= 16.0 && t < 19.2) {
            var q = typed.slice(0, Math.min(typed.length, Math.floor((t - 16.0) / 0.07) + 1));
            if (service.query !== q) service.query = q;
        }
        // Spin hard on the drop, then settle to a steady drift.
        if (!service.country && !tweens.some(function(w) { return w.prop === "longitude"; })) {
            var spin = t >= drop && t < 4.8 ? 14 + 70 * Math.exp(-(t - drop) * 1.4) : 14;
            dashboard.globe.longitude += spin / fps;
        }
        var cam = track(camera, t, function(a, b, k) {
            var pa = root.region(a.at), pb = root.region(b.at);
            return {x: pa.x + (pb.x - pa.x)*k, y: pa.y + (pb.y - pa.y)*k, s: a.s + (b.s - a.s)*k};
        });
        var s = cam.s * (1 + pulse(0.05));
        camScale.xScale = camScale.yScale = s;
        camMove.x = stage.width/2 - cam.x*s;
        camMove.y = stage.height/2 - cam.y*s;
        var pos = track(cursor, t, function(a, b, k) {
            var pa = root.locate(a.p) || root.lastCursor, pb = root.locate(b.p) || pa;
            return {x: pa.x + (pb.x - pa.x)*k, y: pa.y + (pb.y - pa.y)*k};
        });
        lastCursor = pos;
        pointer.x = camMove.x + pos.x*s;
        pointer.y = camMove.y + pos.y*s;
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
                width: 1280; height: 1200
                transform: [Scale { id: camScale }, Translate { id: camMove }]
                Outbound.Dashboard {
                    id: board
                    anchors.fill: parent
                    service: service
                    expanded: true
                    surfaceSwitchAvailable: false
                }
            }
            // Vignette keeps the eye centred and the type readable over busy frames.
            Canvas {
                anchors.fill: parent
                onPaint: {
                    var c = getContext("2d");
                    var g = c.createRadialGradient(width/2, height/2, width*0.3, width/2, height/2, width*0.75);
                    g.addColorStop(0, Qt.rgba(theme.background.r, theme.background.g, theme.background.b, 0));
                    g.addColorStop(1, Qt.rgba(theme.background.r, theme.background.g, theme.background.b, 0.85));
                    c.fillStyle = g; c.fillRect(0, 0, width, height);
                }
            }
            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 460
                visible: root.block !== null
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.rgba(theme.background.r, theme.background.g, theme.background.b, 0) }
                    GradientStop { position: 0.55; color: Qt.rgba(theme.background.r, theme.background.g, theme.background.b, 0.82) }
                    GradientStop { position: 1; color: Qt.rgba(theme.background.r, theme.background.g, theme.background.b, 0.95) }
                }
            }
            Item {
                id: pointer
                width: 1; height: 1
                opacity: root.t >= 12.0 && root.t < 19.2 ? 1 : 0
                Rectangle {
                    id: ripple
                    property real at: -10
                    readonly property real k: root.clamp((root.t - at) / 0.4)
                    visible: k > 0 && k < 1
                    width: 16 + 56*k; height: width; radius: width/2
                    x: -width/2; y: -height/2
                    color: "transparent"; border.width: 4
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
            // Kinetic type, bottom-left; each line snaps up on its beat.
            Column {
                id: type
                readonly property var current: root.block
                x: 64
                anchors { bottom: parent.bottom; bottomMargin: 72 }
                spacing: current && current.small ? 0 : -8
                opacity: current ? root.clamp((current.to - root.t) / 0.08) : 0
                Rectangle {
                    width: 72; height: 6; color: theme.accent
                    visible: type.current !== null
                }
                Item { width: 1; height: 14 }
                Repeater {
                    model: type.current ? type.current.lines : []
                    Text {
                        required property var modelData
                        required property int index
                        readonly property real k: root.clamp((root.t - modelData[0]) / 0.12)
                        visible: root.t >= modelData[0]
                        opacity: k
                        transform: Translate { y: 36 * (1 - root.ease(k)) }
                        width: 960
                        text: modelData[1]
                        fontSizeMode: Text.HorizontalFit
                        minimumPixelSize: 40
                        font.family: theme.font
                        font.pixelSize: type.current.small ? 88 : 118
                        font.bold: true
                        font.letterSpacing: 2
                        // Lines alternate text/accent so the second hit reads as the punchline.
                        color: index % 2 ? theme.accent : theme.text
                    }
                }
            }
            // Title card: logo, name and tagline, with a short build into the drop.
            Rectangle {
                anchors.fill: parent
                color: Color.background
                visible: root.t < root.drop
                Column {
                    anchors.centerIn: parent
                    spacing: 22
                    opacity: root.clamp((root.t - 0.2) / 0.5)
                    scale: 1 + 0.08 * root.ease(root.clamp((root.t - 1.2) / 1.2))
                    Outbound.GlobeIcon { ink: theme.accent; width: 120; height: 120; anchors.horizontalCenter: parent.horizontalCenter }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "OUTBOUND"; color: theme.text
                        font.family: theme.font; font.pixelSize: 84
                        font.letterSpacing: 14 + 10 * root.ease(root.clamp((root.t - 1.2) / 1.2))
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "See where your apps connect."; color: theme.subdued
                        font.family: theme.font; font.pixelSize: 32
                    }
                }
            }
            // End card with the install command; the logo pulses on the beat.
            Rectangle {
                anchors.fill: parent
                color: Color.background
                visible: root.t >= 24.0
                Column {
                    anchors.centerIn: parent
                    spacing: 20
                    Outbound.GlobeIcon {
                        ink: theme.accent; width: 120; height: 120
                        anchors.horizontalCenter: parent.horizontalCenter
                        scale: 1 + root.pulse(0.14)
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "OUTBOUND"; color: theme.text
                        font.family: theme.font; font.pixelSize: 96; font.bold: true
                        font.letterSpacing: 14
                        scale: 1.25 - 0.25 * root.ease(root.clamp((root.t - 24.0) / 0.5))
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "A network globe for your Omarchy bar"; color: theme.subdued
                        font.family: theme.font; font.pixelSize: 30
                        opacity: root.clamp((root.t - 24.6) / 0.3)
                    }
                    Item { width: 1; height: 26 }
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: command.implicitWidth + 48; height: 64
                        color: theme.wash; border.color: theme.fade(theme.accent, 0.55); border.width: 1.5
                        opacity: root.clamp((root.t - 25.2) / 0.3)
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
            // Cut flash, strongest on the drop and on the end card.
            Rectangle {
                anchors.fill: parent
                color: theme.text
                opacity: root.flash()
                visible: opacity > 0.01
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
            if (++root.frame >= root.duration * root.fps) { console.log("DEMO_COMPLETE", root.frame); Qt.quit(); }
            else root.nextFrame();
        })
    }
}
