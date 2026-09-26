import QtQuick

// The same two-headed diagonal arrow for both directions, as in Vessel, so the
// panel/window toggle keeps one recognisable shape; the hint names the action.
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
        c.moveTo(3, 15); c.lineTo(15, 3);
        c.moveTo(3, 9); c.lineTo(3, 15); c.lineTo(9, 15);
        c.moveTo(9, 3); c.lineTo(15, 3); c.lineTo(15, 9);
        c.stroke();
    }
}
