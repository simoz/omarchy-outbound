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
    property real zoom: 1
    readonly property real maximumZoom: 4
    signal originRequested()
    readonly property bool linksAnimating: active && visible && originPoint !== null && layers[2].length > 0 && !service.reducedMotion && !service.paused
    readonly property real radius: Math.max(1, Math.min(width - 44, height - 40) * 0.48) * zoom
    readonly property var originPoint: service.globeOrigin
    readonly property var grid: Projection.graticule()
    // Keep other destinations visible when a country is selected; its arc and
    // marker carry the emphasis while the table shows the filtered sockets.
    readonly property var destinations: service.countries.filter(function(c) {
        return service.destinations.some(function(group) { return group.value === c.code; });
    })
    readonly property var layers: active ? [
        Projection.paths(grid, longitude, latitude, radius, width/2, height/2),
        Projection.paths(Geography.outlines, longitude, latitude, radius, width/2, height/2),
        Projection.paths(originPoint ? destinations.map(function(c) { return Projection.arc([originPoint.lon, originPoint.lat], [c.lon, c.lat]); }) : [],
                         longitude, latitude, radius, width/2, height/2)
    ] : [[], [], []]
    readonly property var pulsePaths: !service.country ? layers[2] : Projection.paths(
        active && originPoint ? destinations.filter(function(c) { return c.code === root.service.country; }).map(function(c) { return Projection.arc([root.originPoint.lon, root.originPoint.lat], [c.lon, c.lat]); }) : [],
        longitude, latitude, radius, width/2, height/2)
    property int paintCount: 0
    Theme { id: theme }
    clip: true
    activeFocusOnTab: true
    Accessible.role: Accessible.Canvas
    Accessible.name: "Destination globe. Drag or use arrow keys to rotate. Scroll or use + and - to zoom. Home resets the view."

    function rotate(dx, dy) {
        longitude = Projection.wrap(longitude + dx);
        latitude = Math.max(-80, Math.min(80, latitude + dy));
    }
    function zoomBy(steps) { zoom = Math.max(1, Math.min(maximumZoom, zoom * Math.pow(1.2, steps))); }
    function reset() { longitude = -15; latitude = 18; zoom = 1; }
    function focusCountry() {
        var country = service.countries.find(function(c) { return c.code === service.country; });
        if (country) { longitude = country.lon; latitude = country.lat; }
    }
    Connections {
        target: root.service
        function onCountryChanged() { root.focusCountry(); canvas.redraw(); }
        function onGlowChanged() { canvas.redraw(); }
        // Stop existing motion, but allow a subsequent explicit Play request.
        function onReducedMotionChanged() { if (root.service.reducedMotion) root.rotating = false; }
    }
    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Plus && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
            zoomBy(1); event.accepted = true; return;
        }
        if (event.modifiers !== Qt.NoModifier) return;
        if (event.key === Qt.Key_Left) rotate(-8, 0);
        else if (event.key === Qt.Key_Right) rotate(8, 0);
        else if (event.key === Qt.Key_Up) rotate(0, 8);
        else if (event.key === Qt.Key_Down) rotate(0, -8);
        else if (event.key === Qt.Key_Minus) zoomBy(-1);
        else if (event.key === Qt.Key_Equal) zoomBy(1);
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
                (root.originPoint ? root.destinations : []).forEach(function(c) {
                    var selected = !root.service.country || root.service.country === c.code;
                    var arc = Projection.path(Projection.arc([root.originPoint.lon, root.originPoint.lat], [c.lon, c.lat]), root.longitude, root.latitude, r, cx, cy);
                    if (root.service.glow && selected) {
                        stroke(arc, theme.fade(theme.accent, 0.05), 9);
                        stroke(arc, theme.fade(theme.accent, 0.13), 4);
                    }
                    stroke(arc, theme.fade(theme.accent, selected ? 0.95 : 0.2), selected ? 1.4 : 0.8);
                });
            }
            var origin = root.originPoint ? Projection.project(root.originPoint.lon, root.originPoint.lat, root.longitude, root.latitude) : null;
            if (origin && origin.z > 0) {
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
    // Animate only a cached vector overlay: geography stays event-driven.
    // A simultaneous pulse expresses activity without claiming packet direction.
    Shape {
        id: linkPulse
        objectName: "connectionPulse"
        anchors.fill: parent
        visible: root.linksAnimating
        ShapePath {
            fillColor: "transparent"
            strokeColor: theme.fade(theme.accent, root.service.glow ? 0.22 : 0)
            strokeWidth: 6
            PathSvg { path: Projection.svg(root.pulsePaths) }
        }
        ShapePath {
            fillColor: "transparent"
            strokeColor: theme.text
            strokeWidth: 1.8
            PathSvg { path: Projection.svg(root.pulsePaths) }
        }
        SequentialAnimation on opacity {
            running: root.linksAnimating
            loops: Animation.Infinite
            NumberAnimation { from: 0.05; to: 0.9; duration: 950; easing.type: Easing.InOutSine }
            NumberAnimation { from: 0.9; to: 0.05; duration: 950; easing.type: Easing.InOutSine }
        }
    }
    MouseArea {
        anchors.fill: parent
        objectName: "globeNavigation"
        onWheel: function(wheel) {
            if (wheel.modifiers !== Qt.NoModifier) { wheel.accepted = false; return; }
            root.zoomBy(wheel.pixelDelta.y !== 0 ? wheel.pixelDelta.y / 80 : wheel.angleDelta.y / 120);
            wheel.accepted = true;
        }
        property real lastX: 0
        property real lastY: 0
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        onPressed: function(mouse) { lastX = mouse.x; lastY = mouse.y; root.forceActiveFocus(); }
        onPositionChanged: function(mouse) {
            if (!pressed) return;
            root.rotate((lastX - mouse.x) * 0.45 / root.zoom, (mouse.y - lastY) * 0.45 / root.zoom);
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
            Accessible.name: "Filter destinations: " + modelData.name
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
        text: root.originPoint ? "MANUAL ORIGIN / APPROXIMATE COUNTRIES\nENDPOINT ARCS · NOT ROUTES" : "ORIGIN NOT SET / DESTINATIONS ONLY"
        horizontalAlignment: Text.AlignRight
        font.pixelSize: theme.size * 0.65
        color: theme.subdued
    }
    ActionButton {
        objectName: "setGlobeOriginButton"
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 44 }
        width: Math.min(330, parent.width - 24)
        visible: !root.originPoint && !root.service.needsGeoIp
        text: "Set origin to connect destinations"
        onClicked: root.originRequested()
    }
    Column {
        id: installCard
        anchors.centerIn: parent
        width: Math.min(360, parent.width - 40)
        spacing: 8
        // Without a collector nothing can be observed, so its install precedes GeoIP.
        readonly property bool engineStep: root.service.needsEngine || root.service.engineInstalling || root.service.engineInstallError !== ""
        visible: engineStep || root.service.needsGeoIp || root.service.geoInstalling || root.service.geoInstallError !== ""
        Rectangle {
            width: parent.width
            height: installContent.implicitHeight + 24
            color: theme.background
            Frame { anchors.fill: parent; emphasized: true }
            Column {
                id: installContent
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                spacing: 8
                Label { width: parent.width; text: installCard.engineStep ? "CONNECTION COLLECTOR" : "COUNTRY GEOLOCATION"; color: theme.accent }
                Label {
                    width: parent.width; wrapMode: Text.Wrap
                    text: installCard.engineStep
                        ? root.service.engineInstallError || "Install the prebuilt collector to observe connections. It is downloaded from the Outbound GitHub release and checked against a pinned SHA-256."
                        : root.service.geoInstallError || "Install the local country database to show destinations on the globe."
                }
                ActionButton {
                    objectName: "installEngineButton"
                    width: parent.width
                    visible: installCard.engineStep
                    text: root.service.engineInstalling ? "Downloading and verifying…" : "Install collector"
                    enabled: !root.service.engineInstalling && !root.service.geoInstalling
                    onClicked: root.service.installEngine()
                }
                ActionButton {
                    objectName: "installGeoIpButton"
                    width: parent.width
                    visible: !installCard.engineStep
                    text: root.service.geoInstalling ? "Downloading and validating…" : "Install GeoIP"
                    enabled: !root.service.geoInstalling && !root.service.engineInstalling
                    onClicked: root.service.installGeoIp()
                }
            }
        }
    }
    Timer {
        interval: 33; repeat: true
        running: root.active && root.rotating
        onTriggered: root.rotate(0.3, 0)
    }
}
