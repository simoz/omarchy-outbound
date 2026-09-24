pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic as C

C.ComboBox {
    id: root
    Theme { id: theme }
    property string description: ""
    implicitHeight: Math.max(32, theme.size * 2.6)
    implicitWidth: 170
    leftPadding: 0
    rightPadding: 0
    topPadding: 0
    bottomPadding: 0
    font.family: theme.font
    font.pixelSize: theme.size
    Accessible.name: description
    palette.window: theme.background
    palette.base: theme.background
    palette.text: theme.text
    palette.buttonText: theme.text
    palette.highlight: theme.text
    palette.highlightedText: theme.background
    delegate: C.ItemDelegate {
        id: option
        required property int index
        width: root.popup.width
        text: root.textAt(index)
        highlighted: root.highlightedIndex === index
        hoverEnabled: root.hoverEnabled
        contentItem: Label {
            text: option.text
            color: option.highlighted ? theme.background : theme.text
            font.bold: root.currentIndex === option.index
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        background: Rectangle {
            color: option.highlighted ? theme.text : theme.background
        }
    }
    indicator: Label {
        x: root.width - width - 8
        y: (root.height - height) / 2
        text: "⌄"
    }
    contentItem: Label {
        text: root.displayText
        leftPadding: 10
        rightPadding: 26
        verticalAlignment: Text.AlignVCenter
    }
    background: Rectangle {
        color: theme.wash
        border.width: root.activeFocus ? 2 : 1
        border.color: root.activeFocus ? theme.text : theme.border
    }
}
