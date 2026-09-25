import QtQuick

// Small vector globe for the bar; independent of icon-font availability.
Canvas {
    id: root
    required property color ink
    implicitWidth: 20
    implicitHeight: 20
    onInkChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onPaint: {
        var context = getContext("2d");
        context.reset();
        context.scale(width / 24, height / 24);
        context.strokeStyle = ink;
        context.lineWidth = 1.6;
        context.lineCap = "round";
        context.beginPath();
        context.arc(12, 12, 9, 0, Math.PI * 2);
        context.moveTo(3, 12);
        context.lineTo(21, 12);
        context.moveTo(12, 3);
        context.bezierCurveTo(5, 7, 5, 17, 12, 21);
        context.bezierCurveTo(19, 17, 19, 7, 12, 3);
        context.stroke();
    }
}
