pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic as C

Item {
    id: root
    required property var groups
    required property string title
    property string subtitle: ""
    property string selectedValue: ""
    property var labelFor: function(value) { return value; }
    property var badgeFor: function(value) { return value.slice(0, 2).toUpperCase(); }
    property bool flags: false
    property color accent: theme.accent
    readonly property int total: groups.reduce(function(n, group) { return n + group.count; }, 0)
    readonly property real rowHeight: Math.max(39, theme.size * 3)
    signal chosen(string value)
    Theme { id: theme }
    implicitHeight: 260
    Frame { anchors.fill: parent; accent: root.accent; emphasized: root.selectedValue !== "" }
    Label {
        x: 14; y: 12
        width: parent.width - 28
        text: root.title
        color: root.accent
        font.pixelSize: theme.size * 1.12
        font.letterSpacing: 1.5
    }
    Label {
        x: 14; y: 37
        width: parent.width - 28
        text: root.subtitle
        font.pixelSize: theme.size * 0.76
        color: theme.subdued
    }
    Rectangle { x: 14; y: 61; width: parent.width - 28; height: 1; color: theme.border }
    ListView {
        id: list
        x: 12; y: 66
        width: parent.width - 20
        height: Math.max(root.rowHeight, Math.floor((root.height - 74) / root.rowHeight) * root.rowHeight)
        model: root.groups
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        C.ScrollBar.vertical: C.ScrollBar {}
        delegate: C.ItemDelegate {
            id: row
            required property var modelData
            required property int index
            readonly property bool selected: root.selectedValue === modelData.value
            readonly property int percentage: Math.round(100 * modelData.count / root.total)
            width: list.width - 8
            height: root.rowHeight
            focusPolicy: Qt.StrongFocus
            Accessible.name: root.labelFor(modelData.value) + ", " + modelData.count + " sockets, " + percentage + " percent"
            onClicked: root.chosen(modelData.value)
            onActiveFocusChanged: if (activeFocus) {
                list.currentIndex = index;
                list.positionViewAtIndex(index, ListView.Contain);
            }
            Keys.onPressed: function(event) {
                if (event.modifiers !== Qt.NoModifier || (event.key !== Qt.Key_Up && event.key !== Qt.Key_Down)) return;
                var next = Math.max(0, Math.min(list.count - 1, index + (event.key === Qt.Key_Down ? 1 : -1)));
                list.currentIndex = next;
                list.positionViewAtIndex(next, ListView.Contain);
                list.forceLayout();
                list.currentItem.forceActiveFocus();
                event.accepted = true;
            }
            background: Rectangle {
                color: row.selected || row.hovered ? theme.fade(root.accent, 0.09) : "transparent"
                border.color: row.activeFocus || row.selected ? root.accent : "transparent"
                Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: theme.border }
            }
            contentItem: Item {
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 27
                    text: root.badgeFor(row.modelData.value)
                    font.family: root.flags ? "Noto Color Emoji" : theme.font
                    font.pixelSize: root.flags ? 21 : 17
                    color: root.accent
                }
                Label {
                    x: 34
                    width: parent.width - 34 - numbers.width - 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: (row.selected ? "› " : "") + root.labelFor(row.modelData.value)
                    font.bold: row.selected
                }
                Row {
                    id: numbers
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    spacing: 8
                    Label { width: 22; horizontalAlignment: Text.AlignRight; text: row.modelData.count }
                    Rectangle {
                        width: Math.max(28, row.width * 0.2)
                        height: 9
                        anchors.verticalCenter: parent.verticalCenter
                        color: theme.fade(root.accent, 0.13)
                        Rectangle {
                            width: parent.width * row.modelData.count / root.total
                            height: parent.height
                            color: root.accent
                        }
                    }
                    Label { width: 33; horizontalAlignment: Text.AlignRight; text: row.percentage + "%"; color: theme.subdued }
                }
            }
        }
        Label {
            anchors.fill: parent
            visible: list.count === 0
            text: "No matching connections"
            wrapMode: Text.Wrap
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignHCenter
            color: theme.subdued
        }
    }
}
