pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic as C
import QtQuick.Layouts

Column {
    id: root
    required property var service
    signal copyRequested(string text)
    spacing: 8
    Theme { id: theme }
    Label {
        width: parent.width
        text: "03 / CONNECTIONS  ·  " + root.service.filtered.length + " SHOWN"
        font.pixelSize: theme.size * 0.85
        color: theme.subdued
    }
    Label {
        width: parent.width
        text: "APPLICATION  /  REMOTE ENDPOINT  /  COUNTRY  /  TCP STATE"
        font.pixelSize: theme.size * 0.7
        color: theme.subdued
    }
    ListView {
        id: list
        objectName: "outboundConnections"
        width: parent.width
        height: root.service.filtered.length ? 215 : 72
        model: root.service.filtered
        clip: true
        spacing: 3
        boundsBehavior: Flickable.StopAtBounds
        C.ScrollBar.vertical: C.ScrollBar {}
        delegate: C.ItemDelegate {
            id: row
            required property var modelData
            required property int index
            objectName: "connection-" + modelData.id
            width: list.width - 12
            height: list.width < 640 ? 72 : 43
            focusPolicy: Qt.StrongFocus
            Accessible.name: modelData.app + ", " + modelData.ip + ", " + root.service.countryName(modelData.country) + ", " + modelData.state
            onClicked: root.service.selection = modelData.id
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
                color: root.service.selection === row.modelData.id ? theme.fade(theme.text, 0.12) : row.hovered ? theme.wash : "transparent"
                border.width: row.activeFocus ? 2 : 1
                border.color: row.activeFocus || root.service.selection === row.modelData.id ? theme.text : theme.border
            }
            contentItem: GridLayout {
                columns: list.width < 640 ? 2 : 4
                columnSpacing: 12
                Label {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 180
                    text: (root.service.selection === row.modelData.id ? "● " : "") + row.modelData.app
                    font.bold: root.service.selection === row.modelData.id
                }
                Label {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 240
                    text: (row.modelData.family === "IPv6" ? "[" + row.modelData.ip + "]" : row.modelData.ip) + ":" + row.modelData.port
                }
                Label {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 135
                    text: root.service.countryName(row.modelData.country)
                    color: theme.subdued
                }
                Label {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 110
                    text: row.modelData.state
                    font.pixelSize: theme.size * 0.85
                }
            }
        }
        Label {
            anchors.fill: parent
            visible: root.service.filtered.length === 0
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.Wrap
            text: root.service.scenario === "error" ? "Simulated collector error. Choose Sample to recover."
                : root.service.scenario === "empty" ? "No connections in this simulated snapshot."
                : "No matches. Clear filters to see all simulated connections."
        }
    }
    Rectangle {
        width: parent.width
        height: details.implicitHeight + 24
        color: theme.wash
        border.color: theme.border
        Column {
            id: details
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
            spacing: 8
            Label {
                width: parent.width
                wrapMode: Text.WrapAnywhere
                text: root.service.selected
                    ? root.service.selected.app + " · PID " + (root.service.selected.pid || "unavailable")
                      + "\n" + root.service.selected.ip + "  /  " + root.service.selected.family
                      + "  /  Direction: unknown"
                    : "Select a connection to inspect its application and copy its IP."
            }
            ActionButton {
                objectName: "copyIpButton"
                text: "Copy IP"
                enabled: root.service.selected !== null
                onClicked: root.copyRequested(root.service.selected.ip)
            }
        }
    }
}
