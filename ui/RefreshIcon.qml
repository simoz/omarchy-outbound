import QtQuick

// Draw the arrow independently of the theme font's symbol coverage.
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
        c.lineCap = "round";
        c.lineJoin = "round";
        c.beginPath();
        c.arc(9, 9, 6, -Math.PI / 4, Math.PI * 1.5);
        c.stroke();
        c.beginPath();
        c.moveTo(9, 3); c.lineTo(6, 1); c.moveTo(9, 3); c.lineTo(6, 6);
        c.stroke();
    }
}
