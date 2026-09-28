import QtQuick

// Vertical arrows for the connection list, distinct from the diagonal panel/window
// icon: outward to grow the list to page height, inward (onto a rule) to restore it.
Canvas {
    property color ink: "white"
    property bool collapse: false
    implicitWidth: 18
    implicitHeight: 18
    onInkChanged: requestPaint()
    onCollapseChanged: requestPaint()
    onPaint: {
        var c = getContext("2d");
        c.reset();
        c.strokeStyle = ink;
        c.lineWidth = 1.5;
        c.lineCap = "round";
        c.lineJoin = "round";
        c.beginPath();
        if (collapse) {
            c.moveTo(9, 2); c.lineTo(9, 7);
            c.moveTo(6, 4); c.lineTo(9, 7); c.lineTo(12, 4);
            c.moveTo(3, 9); c.lineTo(15, 9);
            c.moveTo(9, 16); c.lineTo(9, 11);
            c.moveTo(6, 14); c.lineTo(9, 11); c.lineTo(12, 14);
        } else {
            c.moveTo(9, 3); c.lineTo(9, 15);
            c.moveTo(6, 6); c.lineTo(9, 3); c.lineTo(12, 6);
            c.moveTo(6, 12); c.lineTo(9, 15); c.lineTo(12, 12);
        }
        c.stroke();
    }
}
