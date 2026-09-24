pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: root
    property color accent: theme.accent
    property bool emphasized: false
    Theme { id: theme }
    Rectangle {
        anchors.fill: parent
        color: "transparent"
        radius: 3
        border.color: theme.fade(root.accent, root.emphasized ? 0.8 : 0.3)
    }
    Repeater {
        model: 4
        Item {
            required property int index
            x: index % 2 ? root.width - 12 : 0
            y: index > 1 ? root.height - 12 : 0
            width: 12
            height: 12
            Rectangle {
                width: 12
                height: root.emphasized ? 2 : 1
                y: parent.index > 1 ? parent.height - height : 0
                color: root.accent
            }
            Rectangle {
                width: root.emphasized ? 2 : 1
                height: 12
                x: parent.index % 2 ? parent.width - width : 0
                color: root.accent
            }
        }
    }
}
