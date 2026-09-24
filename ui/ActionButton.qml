import QtQuick
import QtQuick.Controls.Basic as C

C.Button {
    id: root
    property bool selected: false
    property string hint: text
    Theme { id: theme }
    implicitHeight: Math.max(32, theme.size * 2.6)
    implicitWidth: label.implicitWidth + 24
    padding: 8
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    Accessible.name: hint
    C.ToolTip.visible: hovered && hint !== ""
    C.ToolTip.text: hint
    C.ToolTip.delay: 500
    contentItem: Label {
        id: label
        text: root.text
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        font.bold: root.selected
        opacity: root.enabled ? 1 : 0.45
    }
    background: Rectangle {
        color: root.selected || root.hovered || root.down ? theme.fade(theme.text, 0.12) : theme.wash
        border.color: root.activeFocus ? theme.text : root.selected ? theme.accent : theme.border
        border.width: root.activeFocus || root.selected ? 2 : 1
    }
}
