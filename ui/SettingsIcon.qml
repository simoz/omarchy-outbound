import QtQuick

// Draw the gear with the theme ink instead of a font-dependent emoji glyph.
Canvas {
    property color ink: "white"
    implicitWidth: 18
    implicitHeight: 18
    onInkChanged: requestPaint()
    onPaint: {
        var c = getContext("2d");
        c.reset();
        c.strokeStyle = ink;
        c.lineWidth = 1.5;
        c.lineJoin = "round";
        c.beginPath();
        for (var i = 0; i < 32; i++) {
            var angle = i * Math.PI / 16;
            var radius = i % 4 < 2 ? 7.5 : 5.5;
            var x = 9 + Math.cos(angle) * radius;
            var y = 9 + Math.sin(angle) * radius;
            if (i === 0) c.moveTo(x, y); else c.lineTo(x, y);
        }
        c.closePath();
        c.stroke();
        c.beginPath();
        c.arc(9, 9, 2.5, 0, Math.PI * 2);
        c.stroke();
    }
}
