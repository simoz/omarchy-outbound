import QtQuick
import QtQuick.Controls.Basic as C

C.TextField {
    id: root
    Theme { id: theme }
    implicitHeight: Math.max(32, theme.size * 2.6)
    font.family: theme.font
    font.pixelSize: theme.size
    color: theme.text
    placeholderTextColor: theme.subdued
    selectionColor: theme.text
    selectedTextColor: theme.background
    selectByMouse: true
    Accessible.name: "Filter connections by application, IP or state"
    background: Rectangle {
        color: theme.wash
        border.color: root.activeFocus ? theme.text : theme.border
        border.width: root.activeFocus ? 2 : 1
    }
}
