import QtQuick
import QtQuick.Shapes

// Keep the design canvas fixed: Shape derives implicit size from its path bounds.
Item {
    id: root
    required property color ink
    implicitWidth: 20
    implicitHeight: 20
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: root.ink
            strokeWidth: 1.25
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathSvg {
                path: "M 17.5 10 A 7.5 7.5 0 1 1 2.5 10 A 7.5 7.5 0 1 1 17.5 10 "
                    + "M 2.5 10 H 17.5 M 10 2.5 C 4.2 5.8 4.2 14.2 10 17.5 C 15.8 14.2 15.8 5.8 10 2.5"
            }
        }
    }
}
