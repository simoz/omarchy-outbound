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
    property bool surfaceSwitchAvailable: true
    property alias globe: globe
    property alias searchField: search
    property string feedback: ""
    readonly property bool wide: width >= 800
    signal expandRequested()
    signal closeRequested()
    signal copyRequested(string text)
    Theme { id: theme }
    Shortcut {
        sequence: "F1"
        enabled: root.active && !settings.opened
        onActivated: keyboardHelp.visible ? keyboardHelp.close() : keyboardHelp.open()
    }
    KeyboardHelp { id: keyboardHelp; width: Math.min(680, root.width - 24); height: Math.min(580, root.height - 24); x: (root.width - width) / 2; y: (root.height - height) / 2 }
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
                    scroll.contentY = Math.max(0, Math.min(scroll.contentHeight - scroll.height, position.y + item.height - scroll.height + 12));
            });
        }
    }
    Rectangle { anchors.fill: parent; color: theme.background }
    Frame { anchors.fill: parent; anchors.margins: 1; emphasized: true }
    Flickable {
        id: scroll
        objectName: "outboundPage"
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight + 24
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        C.ScrollBar.vertical: C.ScrollBar {}
        ColumnLayout {
            id: content
            x: 12; y: 12
            width: Math.max(200, scroll.width - 24)
            spacing: 10
            RowLayout {
                id: header
                Layout.fillWidth: true
                Layout.minimumHeight: 36
                spacing: root.wide ? 12 : 4
                Label { text: "OUTBOUND"; color: theme.accent; font.pixelSize: theme.size * (root.wide ? 1.75 : 1.2); font.letterSpacing: root.wide ? 3 : 1 }
                Label { visible: root.width > 920; text: "NETWORK OBSERVATORY"; color: theme.subdued; font.pixelSize: theme.size * 0.75; font.letterSpacing: 1 }
                Item { Layout.fillWidth: true }
                Label { text: "● " + root.service.status; color: theme.accent; font.pixelSize: theme.size * 0.8 }
                ActionButton {
                    visible: root.wide
                    text: globe.rotating ? "Ⅱ" : "▷"
                    implicitWidth: 30
                    hint: root.service.reducedMotion ? "Rotation disabled by reduced motion" : globe.rotating ? "Pause rotation" : "Rotate globe"
                    enabled: !root.service.reducedMotion
                    onClicked: globe.rotating = !globe.rotating
                }
                ActionButton { objectName: "keyboardHelpButton"; text: "?"; implicitWidth: 30; hint: "Keyboard guide (F1)"; onClicked: keyboardHelp.open() }
                ActionButton { objectName: "displaySettingsButton"; text: "⚙"; implicitWidth: 30; hint: "Collection and display settings"; onClicked: settings.open() }
                ActionButton { visible: root.surfaceSwitchAvailable; text: root.expanded ? "↙" : "↗"; implicitWidth: 30; hint: root.expanded ? "Collapse into panel" : "Expand into window"; onClicked: root.expandRequested() }
                ActionButton { text: "×"; implicitWidth: 30; hint: "Close Outbound"; onClicked: root.closeRequested() }
            }
            GridLayout {
                id: hero
                Layout.fillWidth: true
                Layout.preferredHeight: root.wide
                    ? Math.max(350, root.height - Math.max(36, header.implicitHeight) - table.implicitHeight - footer.implicitHeight - 54)
                    : 900
                columns: root.wide ? 2 : 1
                columnSpacing: 10
                rowSpacing: 10
                Item {
                    id: plot
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: root.wide ? content.width * 0.63 : content.width
                    Layout.preferredHeight: root.wide ? 1 : 390
                    Frame { anchors.fill: parent }
                    Flow {
                        id: filters
                        x: 12; y: 12
                        width: parent.width - 24
                        spacing: 6
                        Choice {
                            objectName: "applicationFilter"
                            width: Math.min(184, filters.width)
                            description: "Application filter"
                            model: ["All applications"].concat(root.service.applications.map(function(a) { return a.value; }))
                            currentIndex: root.service.application ? model.indexOf(root.service.application) : 0
                            onActivated: root.service.application = currentIndex === 0 ? "" : currentText
                        }
                        Choice {
                            objectName: "familyFilter"
                            width: 108
                            description: "IP address family"
                            model: ["All IPs", "IPv4", "IPv6"]
                            currentIndex: root.service.family ? model.indexOf(root.service.family) : 0
                            onActivated: root.service.family = currentIndex === 0 ? "" : currentText
                        }
                        SearchField {
                            id: search
                            objectName: "connectionSearch"
                            width: Math.max(128, Math.min(190, filters.width - 346))
                            placeholderText: "Search IP / app…"
                            text: root.service.query
                            onTextEdited: root.service.query = text
                        }
                        ActionButton { text: "↺"; implicitWidth: 30; hint: "Clear filters"; onClicked: root.service.clearFilters() }
                    }
                    Globe {
                        onOriginRequested: settings.open()
                        id: globe
                        anchors { top: filters.bottom; bottom: parent.bottom; left: parent.left; right: parent.right; topMargin: 3; bottomMargin: 6 }
                        service: root.service
                        active: root.active
                    }
                    ActionButton {
                        anchors { right: parent.right; bottom: parent.bottom; rightMargin: 12; bottomMargin: 47 }
                        text: "⌖"; implicitWidth: 28; implicitHeight: 26
                        hint: "Reset globe orientation (Home when globe is focused)"
                        onClicked: globe.reset()
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: root.wide ? content.width * 0.37 : content.width
                    Layout.preferredHeight: root.wide ? 1 : 500
                    spacing: 10
                    CountryList { Layout.fillWidth: true; Layout.fillHeight: true; service: root.service }
                    Breakdown {
                        objectName: "outboundApplications"
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        denominator: root.service.applicationFacetRows.length
                        groups: root.service.countryApplications
                        title: root.service.country ? root.service.countryName(root.service.country).toUpperCase() : "APPLICATIONS"
                        subtitle: (root.service.country ? "APPLICATIONS IN SELECTED COUNTRY" : "ALL DESTINATIONS") + "  /  " + denominator + " SOCKETS"
                        selectedValue: root.service.application
                        accent: root.service.country ? theme.text : theme.accent
                        labelFor: function(name) { return name; }
                        badgeFor: function(name) { return root.service.appBadge(name); }
                        onChosen: function(name) { root.service.chooseApplication(name); }
                    }
                }
            }
            ConnectionTable {
                id: table
                Layout.fillWidth: true
                service: root.service
                onCopyRequested: function(text) { root.copyRequested(text); }
            }
            GridLayout {
                id: footer
                Layout.fillWidth: true
                columns: root.wide ? 2 : 1
                Label {
                    Layout.fillWidth: true
                    text: root.feedback || (root.service.demoMode ? "LOCAL GEOMETRY / NATURAL EARTH · DIRECTION UNKNOWN" : (root.service.error || root.service.geoStatus) + (root.service.snapshot ? " · " + new Date(root.service.snapshot.observedAtMs).toLocaleTimeString() : ""))
                    color: theme.subdued
                    font.pixelSize: theme.size * 0.7
                }
                Label {
                    text: (root.service.demoMode ? "SIMULATED DATA / " : "OBSERVED / ") + root.service.rows.length + " SOCKETS / " + root.service.countryCount + " COUNTRIES"
                    color: theme.accent
                    font.pixelSize: theme.size * 0.7
                }
            }
        }
    }
    Settings { id: settings; service: root.service }
}
