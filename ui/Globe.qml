pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import "../assets/Countries.js" as Geography
import "Projection.js" as Projection

FocusScope {
    id: root
    objectName: "outboundGlobe"
    required property var service
    property bool active: true
    property real longitude: 12
    property real latitude: 24
    property string renderer: "canvas"
    property bool rotating: false
    readonly property real radius: Math.max(1, Math.min(width, height) * 0.415)
    readonly property var grid: Projection.graticule()
    readonly property var destinations: service.countries.filter(function(c) {
        return service.filtered.some(function(row) { return row.country === c.code; });
    })
    readonly property var layers: active ? [
        Projection.paths(grid, longitude, latitude, radius, width/2, height/2),
        Projection.paths(Geography.outlines, longitude, latitude, radius, width/2, height/2),
        Projection.paths(destinations.map(function(c) { return Projection.arc([12.5, 41.9], [c.lon, c.lat]); }),
                         longitude, latitude, radius, width/2, height/2)
    ] : [[], [], []]
    property int paintCount: 0
    Theme { id: theme }
    activeFocusOnTab: true
    Accessible.role: Accessible.Canvas
    Accessible.name: "Destination globe. Drag or use arrow keys to rotate. Home resets the view."

    function rotate(dx, dy) {
        longitude = Projection.wrap(longitude + dx);
        latitude = Math.max(-80, Math.min(80, latitude + dy));
    }
    function reset() { longitude = 12; latitude = 24; }
    function focusCountry() {
        var country = service.countries.find(function(c) { return c.code === service.country; });
        if (country) { longitude = country.lon; latitude = country.lat; }
    }
    Connections {
        target: root.service
        function onCountryChanged() { root.focusCountry(); }
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
        color: theme.wash
        border.color: root.activeFocus ? theme.text : theme.border
        border.width: root.activeFocus ? 2 : 1
    }
    Rectangle {
        width: root.radius * 2
        height: width
        radius: width / 2
        anchors.centerIn: parent
        color: "transparent"
        border.color: theme.border
    }
    Canvas {
        id: canvas
        anchors.fill: parent
        visible: root.renderer === "canvas"
        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            var colors = [theme.fade(theme.text, 0.16), theme.fade(theme.text, 0.62), theme.accent];
            for (var i = 0; i < root.layers.length; i++) {
                ctx.beginPath();
                root.layers[i].forEach(function(p) {
                    if (p[0] === "M") ctx.moveTo(p[1], p[2]);
                    else ctx.lineTo(p[1], p[2]);
                });
                ctx.strokeStyle = colors[i];
                ctx.lineWidth = i === 2 ? 1.4 : 0.8;
                ctx.stroke();
            }
            root.paintCount++;
        }
        function redraw() { if (root.active && visible) requestPaint(); }
        onVisibleChanged: redraw()
        Connections {
            target: root
            function onLayersChanged() { canvas.redraw(); }
            function onActiveChanged() { canvas.redraw(); }
        }
        Connections {
            target: theme
            function onTextChanged() { canvas.redraw(); }
            function onAccentChanged() { canvas.redraw(); }
        }
    }
    // Identical projected geometry permits a controlled renderer comparison.
    Loader {
        anchors.fill: parent
        active: root.renderer === "shapes" && root.active
        sourceComponent: Shape {
            ShapePath {
                fillColor: "transparent"
                strokeColor: theme.fade(theme.text, 0.16)
                strokeWidth: 0.8
                PathSvg { path: Projection.svg(root.layers[0]) }
            }
            ShapePath {
                fillColor: "transparent"
                strokeColor: theme.fade(theme.text, 0.62)
                strokeWidth: 0.8
                PathSvg { path: Projection.svg(root.layers[1]) }
            }
            ShapePath {
                fillColor: "transparent"
                strokeColor: theme.accent
                strokeWidth: 1.4
                PathSvg { path: Projection.svg(root.layers[2]) }
            }
        }
    }
    MouseArea {
        anchors.fill: parent
        property real lastX: 0
        property real lastY: 0
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        onPressed: function(mouse) {
            lastX = mouse.x; lastY = mouse.y;
            root.forceActiveFocus();
        }
        onPositionChanged: function(mouse) {
            if (!pressed) return;
            root.rotate((lastX - mouse.x) * 0.45, (mouse.y - lastY) * 0.45);
            lastX = mouse.x; lastY = mouse.y;
        }
    }
    Repeater {
        model: root.destinations
        ActionButton {
            id: marker
            required property var modelData
            readonly property var point: Projection.project(modelData.lon, modelData.lat, root.longitude, root.latitude)
            visible: point.z > 0.05
            // Separate the close European callouts at the initial globe scale.
            x: root.width/2 + point.x*root.radius - width/2 + (modelData.code === "GB" ? -12 : modelData.code === "DE" ? 12 : 0)
            y: root.height/2 - point.y*root.radius - height/2 + (modelData.code === "GB" ? -12 : modelData.code === "DE" ? 12 : 0)
            width: 34
            height: 26
            padding: 2
            text: modelData.code
            selected: root.service.country === modelData.code
            hint: "Filter simulated destinations: " + modelData.name
            Accessible.name: hint
            onClicked: root.service.chooseCountry(modelData.code)
        }
    }
    Repeater {
        model: root.service.scanlines ? Math.floor(root.height/6) : 0
        Rectangle {
            required property int index
            y: index * 6
            width: root.width
            height: 1
            color: theme.fade(theme.text, 0.025)
        }
    }
    Label {
        anchors { top: parent.top; left: parent.left; margins: 12 }
        text: "01 / DESTINATION FIELD"
        font.pixelSize: theme.size * 0.8
        color: theme.subdued
    }
    Label {
        anchors { bottom: parent.bottom; left: parent.left; right: parent.right; margins: 12 }
        text: root.latitude.toFixed(1) + "° LAT  /  " + root.longitude.toFixed(1) + "° LON\nSIMULATED ORIGIN: ROME · ARCS ARE NOT ROUTES"
        font.pixelSize: theme.size * 0.75
        color: theme.subdued
    }
    Timer {
        interval: 33
        repeat: true
        running: root.active && root.rotating && !root.service.reducedMotion
        onTriggered: root.rotate(0.3, 0)
    }
}
