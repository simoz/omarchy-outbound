pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic as C
import QtQuick.Shapes
import "../assets/Countries.js" as Geography
import "Projection.js" as Projection

FocusScope {
    id: root
    objectName: "outboundGlobe"
    required property var service
    property bool active: true
    property real longitude: -15
    property real latitude: 18
    property string renderer: "canvas"
    property bool rotating: false
    readonly property real radius: Math.max(1, Math.min(width - 44, height - 40) * 0.48)
    readonly property var grid: Projection.graticule()
    // Keep other destinations visible when a country is selected; its arc and
    // marker carry the emphasis while the table shows the filtered sockets.
    readonly property var destinations: service.countries.filter(function(c) {
        return service.destinations.some(function(group) { return group.value === c.code; });
    })
    readonly property var layers: active ? [
        Projection.paths(grid, longitude, latitude, radius, width/2, height/2),
        Projection.paths(Geography.outlines, longitude, latitude, radius, width/2, height/2),
        Projection.paths(destinations.map(function(c) { return Projection.arc([12.5, 41.9], [c.lon, c.lat]); }),
                         longitude, latitude, radius, width/2, height/2)
    ] : [[], [], []]
    property int paintCount: 0
    Theme { id: theme }
    clip: true
    activeFocusOnTab: true
    Accessible.role: Accessible.Canvas
    Accessible.name: "Destination globe. Drag or use arrow keys to rotate. Home resets the view."

    function rotate(dx, dy) {
        longitude = Projection.wrap(longitude + dx);
        latitude = Math.max(-80, Math.min(80, latitude + dy));
    }
    function reset() { longitude = -15; latitude = 18; }
    function focusCountry() {
        var country = service.countries.find(function(c) { return c.code === service.country; });
        if (country) { longitude = country.lon; latitude = country.lat; }
    }
    Connections {
        target: root.service
        function onCountryChanged() { root.focusCountry(); canvas.redraw(); }
        function onGlowChanged() { canvas.redraw(); }
    }
    Keys.onPressed: function(event) {
        if (event.modifiers !== Qt.NoModifier) return;
        if (event.key === Qt.Key_Left) rotate(-8, 0);
        else if (event.key === Qt.Key_Right) rotate(8, 0);
        else if (event.key === Qt.Key_Up) rotate(0, 8);
        else if (event.key === Qt.Key_Down) rotate(0, -8);
        else if (event.key === Qt.Key_Home) reset();
        else return;
        event.accepted = true;
    }
    Rectangle {
        anchors.fill: parent
        color: "transparent"
        border.color: root.activeFocus ? theme.accent : "transparent"
    }
    Canvas {
        id: canvas
        anchors.fill: parent
        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            if (!root.active) return;
            var cx = width/2, cy = height/2, r = root.radius;
            var halo = ctx.createRadialGradient(cx, cy, r * 0.7, cx, cy, r * 1.12);
            halo.addColorStop(0, "transparent");
            halo.addColorStop(0.78, theme.fade(theme.accent, root.service.glow ? 0.09 : 0.025));
            halo.addColorStop(1, "transparent");
            ctx.fillStyle = halo;
            ctx.fillRect(0, 0, width, height);
            ctx.beginPath(); ctx.arc(cx, cy, r, 0, Math.PI*2);
            ctx.fillStyle = theme.fade(theme.accent, 0.025); ctx.fill();
            ctx.strokeStyle = theme.fade(theme.accent, 0.55); ctx.lineWidth = 0.8; ctx.stroke();
            ctx.beginPath(); ctx.arc(cx, cy, r + 5, 0, Math.PI*2);
            ctx.strokeStyle = theme.fade(theme.accent, 0.15); ctx.stroke();
            // Compass ticks are static geometry, not a continuously animated overlay.
            ctx.beginPath();
            for (var degree = 0; degree < 360; degree += 2) {
                var angle = degree * Math.PI/180;
                var extent = degree % 10 === 0 ? 7 : 3;
                ctx.moveTo(cx + Math.cos(angle)*(r+10), cy + Math.sin(angle)*(r+10));
                ctx.lineTo(cx + Math.cos(angle)*(r+10+extent), cy + Math.sin(angle)*(r+10+extent));
            }
            ctx.strokeStyle = theme.fade(theme.accent, 0.45); ctx.stroke();
            ctx.fillStyle = theme.fade(theme.accent, 0.56);
            Geography.landDots.forEach(function(p) {
                var point = Projection.project(p[0], p[1], root.longitude, root.latitude);
                if (point.z > 0) ctx.fillRect(cx + point.x*r, cy - point.y*r, 1.25, 1.25);
            });
            function stroke(points, color, weight) {
                ctx.beginPath();
                points.forEach(function(p) {
                    if (p[0] === "M") ctx.moveTo(p[1], p[2]);
                    else ctx.lineTo(p[1], p[2]);
                });
                ctx.strokeStyle = color; ctx.lineWidth = weight; ctx.stroke();
            }
            if (root.renderer === "canvas") {
                stroke(root.layers[0], theme.fade(theme.accent, 0.16), 0.6);
                stroke(root.layers[1], theme.fade(theme.accent, 0.5), 0.7);
                root.destinations.forEach(function(c) {
                    var selected = !root.service.country || root.service.country === c.code;
                    var arc = Projection.path(Projection.arc([12.5, 41.9], [c.lon, c.lat]), root.longitude, root.latitude, r, cx, cy);
                    if (root.service.glow && selected) {
                        stroke(arc, theme.fade(theme.accent, 0.05), 9);
                        stroke(arc, theme.fade(theme.accent, 0.13), 4);
                    }
                    stroke(arc, theme.fade(theme.accent, selected ? 0.95 : 0.2), selected ? 1.4 : 0.8);
                });
            }
            var origin = Projection.project(12.5, 41.9, root.longitude, root.latitude);
            if (origin.z > 0) {
                var ox = cx + origin.x*r, oy = cy - origin.y*r;
                if (root.service.glow) {
                    var glow = ctx.createRadialGradient(ox, oy, 0, ox, oy, 19);
                    glow.addColorStop(0, theme.fade(theme.text, 0.75));
                    glow.addColorStop(0.3, theme.fade(theme.accent, 0.3));
                    glow.addColorStop(1, "transparent");
                    ctx.fillStyle = glow; ctx.fillRect(ox-19, oy-19, 38, 38);
                }
                ctx.beginPath(); ctx.arc(ox, oy, 3, 0, Math.PI*2);
                ctx.fillStyle = theme.text; ctx.fill();
            }
            root.paintCount++;
        }
        function redraw() { if (root.active) requestPaint(); }
        Connections {
            target: root
            function onLayersChanged() { canvas.redraw(); }
            function onActiveChanged() { canvas.redraw(); }
            function onRendererChanged() { canvas.redraw(); }
        }
        Connections {
            target: theme
            function onTextChanged() { canvas.redraw(); }
            function onAccentChanged() { canvas.redraw(); }
        }
    }
    // The alternative renderer shares the decorative Canvas; compare vector
    // geometry paths independently when profiling on another graphics backend.
    Loader {
        anchors.fill: parent
        active: root.renderer === "shapes" && root.active
        sourceComponent: Shape {
            ShapePath {
                fillColor: "transparent"; strokeColor: theme.fade(theme.accent, 0.16); strokeWidth: 0.6
                PathSvg { path: Projection.svg(root.layers[0]) }
            }
            ShapePath {
                fillColor: "transparent"; strokeColor: theme.fade(theme.accent, 0.5); strokeWidth: 0.7
                PathSvg { path: Projection.svg(root.layers[1]) }
            }
            ShapePath {
                fillColor: "transparent"; strokeColor: theme.accent; strokeWidth: 1.4
                PathSvg { path: Projection.svg(root.layers[2]) }
            }
        }
    }
    MouseArea {
        anchors.fill: parent
        property real lastX: 0
        property real lastY: 0
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        onPressed: function(mouse) { lastX = mouse.x; lastY = mouse.y; root.forceActiveFocus(); }
        onPositionChanged: function(mouse) {
            if (!pressed) return;
            root.rotate((lastX - mouse.x) * 0.45, (mouse.y - lastY) * 0.45);
            lastX = mouse.x; lastY = mouse.y;
        }
    }
    Repeater {
        model: root.destinations
        C.AbstractButton {
            id: marker
            required property var modelData
            readonly property var point: Projection.project(modelData.lon, modelData.lat, root.longitude, root.latitude)
            readonly property bool selected: root.service.country === modelData.code
            visible: point.z > 0.05
            opacity: !root.service.country || selected ? 1 : 0.5
            x: root.width/2 + point.x*root.radius - width/2
            y: root.height/2 - point.y*root.radius - height/2
            width: 24; height: 24
            hoverEnabled: true
            focusPolicy: Qt.StrongFocus
            Accessible.name: "Filter simulated destinations: " + modelData.name
            C.ToolTip.visible: hovered
            C.ToolTip.text: Accessible.name
            onClicked: root.service.chooseCountry(modelData.code)
            background: Item {
                Rectangle {
                    anchors.centerIn: parent
                    width: root.service.glow ? 26 : 12; height: width; radius: width/2
                    color: theme.fade(theme.accent, 0.12)
                    border.color: marker.activeFocus || marker.selected ? theme.text : "transparent"
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: 6; height: width; radius: width/2
                    color: marker.selected ? theme.text : theme.accent
                }
                Label {
                    x: marker.point.x < 0 ? -width - 2 : parent.width + 2
                    y: marker.modelData.code === "GB" ? -26 : marker.modelData.code === "DE" ? 15 : 0
                    text: marker.modelData.code + (root.width > 550 ? "\n" + Math.abs(marker.modelData.lat).toFixed(1) + "°" + (marker.modelData.lat >= 0 ? "N" : "S") : "")
                    font.pixelSize: theme.size * 0.72
                    color: theme.text
                }
            }
        }
    }
    Repeater {
        model: ["N", "E", "S", "W"]
        Label {
            required property string modelData
            required property int index
            x: root.width/2 + Math.sin(index*Math.PI/2)*(root.radius+23) - width/2
            y: root.height/2 - Math.cos(index*Math.PI/2)*(root.radius+23) - height/2
            text: modelData
            font.pixelSize: theme.size * 0.7
            color: theme.accent
        }
    }
    Repeater {
        model: root.service.scanlines ? Math.floor(root.height/6) : 0
        Rectangle {
            required property int index
            y: index*6; width: root.width; height: 1
            color: theme.fade(theme.text, 0.025)
        }
    }
    Label {
        anchors { left: parent.left; bottom: parent.bottom; margins: 12 }
        text: "LAT " + root.latitude.toFixed(1) + "°\nLON " + root.longitude.toFixed(1) + "°"
        font.pixelSize: theme.size * 0.72
        color: theme.subdued
    }
    Label {
        anchors { right: parent.right; bottom: parent.bottom; margins: 12 }
        text: "ILLUSTRATIVE ORIGIN / ROME\nENDPOINT ARCS · NOT ROUTES"
        horizontalAlignment: Text.AlignRight
        font.pixelSize: theme.size * 0.65
        color: theme.subdued
    }
    Timer {
        interval: 33; repeat: true
        running: root.active && root.rotating && !root.service.reducedMotion
        onTriggered: root.rotate(0.3, 0)
    }
}
