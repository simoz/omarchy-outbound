pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtQuick.Controls.Basic as C
import QtQuick.Layouts

FocusScope {
    id: root
    objectName: "outboundDashboard"
    required property var service
    property bool active: true
    property bool expanded: false
    property alias globe: globe
    property alias searchField: search
    property string feedback: ""
    signal expandRequested()
    signal closeRequested()
    signal copyRequested(string text)
    Theme { id: theme }
    // Bubble only Escape; Tab and input/navigation keys retain their usual owner.
    Keys.onEscapePressed: function(event) { closeRequested(); event.accepted = true; }
    Connections {
        target: root.Window.window
        function onActiveFocusItemChanged() {
            var item = root.Window.window.activeFocusItem;
            var ancestor = item;
            while (ancestor && ancestor !== root) ancestor = ancestor.parent;
            if (!item || ancestor !== root) return;
            Qt.callLater(function() {
                var position = item.mapToItem(scroll.contentItem, 0, 0);
                if (position.y < scroll.contentY) scroll.contentY = Math.max(0, position.y - 12);
                else if (position.y + item.height > scroll.contentY + scroll.height)
                    scroll.contentY = Math.min(scroll.contentHeight - scroll.height, position.y + item.height - scroll.height + 12);
            });
        }
    }
    Rectangle { anchors.fill: parent; color: theme.background }
    Flickable {
        id: scroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight + 32
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        C.ScrollBar.vertical: C.ScrollBar {}
        ColumnLayout {
            id: content
            x: 16
            y: 16
            width: Math.max(160, scroll.width - 32)
            spacing: 16
            GridLayout {
                Layout.fillWidth: true
                columns: content.width < 560 ? 1 : 2
                Column {
                    Layout.fillWidth: true
                    spacing: 4
                    Label { text: "OUTBOUND"; font.pixelSize: theme.size * 2; font.letterSpacing: 5; font.bold: true }
                    Label { text: "SEE WHERE YOUR APPS CONNECT"; font.pixelSize: theme.size * 0.75; color: theme.subdued }
                }
                RowLayout {
                    ActionButton { text: root.expanded ? "Collapse" : "Expand"; onClicked: root.expandRequested() }
                    ActionButton { text: "Close"; onClicked: root.closeRequested() }
                }
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: banner.implicitHeight + 20
                color: theme.wash
                border.color: theme.text
                Label {
                    id: banner
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                    wrapMode: Text.Wrap
                    text: "SIMULATED DATA / UI PROTOTYPE\nNo live connections are collected. IPs, applications and country assignments are examples."
                    font.pixelSize: theme.size * 0.85
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Repeater {
                    model: [
                        {value: root.service.rows.length, label: "SOCKETS"},
                        {value: root.service.countryCount, label: "COUNTRIES"},
                        {value: root.service.applications.length, label: "APPLICATIONS"}
                    ]
                    Column {
                        required property var modelData
                        Layout.fillWidth: true
                        Label { text: String(parent.modelData.value).padStart(2, "0"); font.pixelSize: theme.size * 2.3 }
                        Label { text: parent.modelData.label; font.pixelSize: theme.size * 0.75; color: theme.subdued }
                    }
                }
            }
            Flow {
                Layout.fillWidth: true
                Layout.preferredHeight: implicitHeight
                spacing: 7
                SearchField {
                    id: search
                    objectName: "connectionSearch"
                    width: Math.min(240, content.width)
                    placeholderText: "Search application, IP, state…"
                    text: root.service.query
                    onTextEdited: root.service.query = text
                }
                Choice {
                    objectName: "applicationFilter"
                    width: Math.min(205, content.width)
                    description: "Application filter"
                    model: ["All applications"].concat(root.service.applications.map(function(a) { return a.value; }))
                    currentIndex: root.service.application ? model.indexOf(root.service.application) : 0
                    onActivated: root.service.application = currentIndex === 0 ? "" : currentText
                }
                Choice {
                    objectName: "familyFilter"
                    width: 112
                    description: "IP address family"
                    model: ["All IPs", "IPv4", "IPv6"]
                    currentIndex: root.service.family ? model.indexOf(root.service.family) : 0
                    onActivated: root.service.family = currentIndex === 0 ? "" : currentText
                }
                ActionButton { text: "Clear filters"; onClicked: root.service.clearFilters() }
            }
            GridLayout {
                Layout.fillWidth: true
                columns: content.width >= 700 ? 2 : 1
                columnSpacing: 16
                rowSpacing: 12
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 620
                    Globe {
                        id: globe
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.min(430, Math.max(270, width * 0.73))
                        service: root.service
                        active: root.active
                    }
                    Flow {
                        Layout.fillWidth: true
                        Layout.preferredHeight: implicitHeight
                        spacing: 6
                        ActionButton { text: "Reset view"; onClicked: globe.reset() }
                        ActionButton {
                            text: globe.rotating && !root.service.reducedMotion ? "Pause rotation" : "Rotate"
                            enabled: !root.service.reducedMotion
                            onClicked: globe.rotating = !globe.rotating
                        }
                        Label { height: 32; verticalAlignment: Text.AlignVCenter; text: "Drag / arrow keys"; color: theme.subdued; font.pixelSize: theme.size * 0.8 }
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 245
                    Layout.alignment: Qt.AlignTop
                    CountryList { Layout.fillWidth: true; service: root.service }
                    Label {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: "COUNTRY FILTER\n" + (root.service.country ? root.service.countryName(root.service.country) : "All destinations")
                        color: theme.subdued
                        font.pixelSize: theme.size * 0.85
                    }
                    Label {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: "APPLICATION\n" + (root.service.application || "All applications") + "\n" + root.service.filtered.length + " matching sockets"
                    }
                    Label {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: "Country markers are illustrative. Unknown and local destinations stay in the list."
                        color: theme.subdued
                        font.pixelSize: theme.size * 0.8
                    }
                }
            }
            ConnectionTable {
                Layout.fillWidth: true
                service: root.service
                onCopyRequested: function(text) { root.copyRequested(text); }
            }
            Label {
                Layout.fillWidth: true
                visible: root.feedback !== ""
                text: root.feedback
                wrapMode: Text.Wrap
            }
            Flow {
                Layout.fillWidth: true
                Layout.preferredHeight: implicitHeight
                spacing: 7
                Choice {
                    objectName: "scenarioChoice"
                    description: "Simulated data scenario"
                    model: ["Sample", "Empty", "Error", "Busy / long names"]
                    currentIndex: ["sample", "empty", "error", "busy"].indexOf(root.service.scenario)
                    onActivated: root.service.setScenario(["sample", "empty", "error", "busy"][currentIndex])
                }
                ActionButton {
                    text: "Reduced motion: " + (root.service.reducedMotion ? "on" : "off")
                    selected: root.service.reducedMotion
                    onClicked: root.service.reducedMotion = !root.service.reducedMotion
                }
                ActionButton {
                    text: "Scanlines: " + (root.service.scanlines ? "on" : "off")
                    selected: root.service.scanlines
                    onClicked: root.service.scanlines = !root.service.scanlines
                }
            }
            Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: "Made with Natural Earth · public-domain geometry\nDirection unknown · Endpoint arcs are not packet routes · No GeoIP lookup in this prototype"
                color: theme.subdued
                font.pixelSize: theme.size * 0.8
            }
        }
    }
}
