pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic as C

Item {
    id: root
    required property var service
    signal copyRequested(string text)
    readonly property bool narrow: width < 680
    readonly property var proportions: [0.21, 0.27, 0.2, 0.07, 0.17, 0.08]
    function columnX(index, available) {
        var offset = 0;
        for (var i = 0; i < index; i++) offset += proportions[i];
        return offset * available;
    }
    implicitHeight: narrow ? 308 : 230
    Theme { id: theme }
    Frame { anchors.fill: parent; emphasized: true }
    Label {
        x: 14; y: 10
        width: parent.width - 28
        text: "CONNECTIONS  /  " + root.service.filtered.length + " SHOWN"
        font.pixelSize: theme.size * 1.05
        font.letterSpacing: 1.2
        color: theme.accent
    }
    Item {
        x: 14; y: 38; width: parent.width - 36; height: 23
        visible: !root.narrow
        Repeater {
            model: ["APPLICATION", "REMOTE IP", "COUNTRY", "PORT", "TCP STATE", "FAMILY"]
            Label {
                required property string modelData
                required property int index
                x: root.columnX(index, parent.width)
                width: root.proportions[index] * parent.width
                text: modelData
                color: theme.subdued
                font.pixelSize: theme.size * 0.7
            }
        }
    }
    ListView {
        id: list
        objectName: "outboundConnections"
        anchors { left: parent.left; right: parent.right; top: parent.top; bottom: details.top; leftMargin: 12; rightMargin: 8; topMargin: root.narrow ? 39 : 61; bottomMargin: 6 }
        model: root.service.filtered
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        C.ScrollBar.vertical: C.ScrollBar {}
        delegate: C.ItemDelegate {
            id: row
            required property var modelData
            required property int index
            readonly property bool selected: root.service.selection === modelData.id
            objectName: "connection-" + modelData.id
            width: list.width - 8
            height: root.narrow ? 66 : Math.max(38, theme.size * 2.9)
            padding: 2
            focusPolicy: Qt.StrongFocus
            Accessible.name: modelData.app + ", " + modelData.ip + ", port " + modelData.port + ", " + root.service.countryName(modelData.country) + ", " + modelData.state
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
                color: row.selected || row.hovered ? theme.fade(theme.accent, 0.08) : "transparent"
                border.color: row.activeFocus || row.selected ? theme.accent : "transparent"
                Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: theme.border }
            }
            contentItem: Item {
                id: rowCells
                Repeater {
                    model: [root.service.appBadge(row.modelData.app) + "  " + (row.selected ? "› " : "") + row.modelData.app,
                            row.modelData.ip, root.service.countryName(row.modelData.country),
                            String(row.modelData.port), "● " + row.modelData.state, row.modelData.family]
                    Label {
                        required property string modelData
                        required property int index
                        x: root.narrow ? (index % 2) * rowCells.width / 2 : root.columnX(index, rowCells.width)
                        y: root.narrow ? Math.floor(index / 2) * 20 : (rowCells.height - height) / 2
                        width: (root.narrow ? rowCells.width / 2 : root.proportions[index] * rowCells.width) - 10
                        text: modelData
                        font.bold: row.selected && index === 0
                        font.pixelSize: index >= 3 ? theme.size * 0.84 : theme.size
                        color: index === 4 ? theme.accent : theme.text
                    }
                }
            }
        }
        Label {
            anchors.fill: parent
            visible: root.service.filtered.length === 0
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.Wrap
            text: root.service.scenario === "error" ? "Simulated collector error. Open settings and choose Sample to recover."
                : root.service.scenario === "empty" ? "No connections in this simulated snapshot."
                : "No matches. Clear filters to see all simulated connections."
            color: theme.subdued
        }
    }
    Item {
        id: details
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 12 }
        height: Math.max(32, theme.size * 2.6)
        Rectangle { y: -5; width: parent.width; height: 1; color: theme.border }
        Label {
            anchors { left: parent.left; right: copy.left; rightMargin: 10; verticalCenter: parent.verticalCenter }
            text: root.service.selected
                ? root.service.selected.app + " · PID " + (root.service.selected.pid || "unavailable") + " · " + root.service.selected.ip
                : "Select a socket for details · Direction unknown"
            font.pixelSize: theme.size * 0.85
            color: theme.subdued
        }
        ActionButton {
            id: copy
            objectName: "copyIpButton"
            anchors.right: parent.right
            text: "Copy IP"
            enabled: root.service.selected !== null
            onClicked: root.copyRequested(root.service.selected.ip)
        }
    }
}
