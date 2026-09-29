pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtQuick.Controls.Basic as C
import QtQuick.Layouts

C.Popup {
    id: root
    objectName: "outboundKeyboardHelp"
    modal: true
    focus: true
    padding: 16
    closePolicy: C.Popup.CloseOnEscape | C.Popup.CloseOnPressOutside
    property var previousFocus: null
    Theme { id: theme }
    onAboutToShow: {
        previousFocus = root.parent.Window.window.activeFocusItem;
        scroll.contentY = 0;
    }
    onOpened: closeButton.forceActiveFocus()
    onClosed: if (previousFocus) previousFocus.forceActiveFocus()
    background: Rectangle {
        color: theme.background
        Frame { anchors.fill: parent; emphasized: true }
    }
    contentItem: ColumnLayout {
        spacing: 16
        RowLayout {
            Layout.fillWidth: true
            Label { Layout.fillWidth: true; text: "KEYS"; color: theme.accent; font.letterSpacing: 3 }
            ActionButton { id: closeButton; text: "Esc ×"; hint: "Close keyboard guide"; onClicked: root.close() }
        }
        Flickable {
            id: scroll
            objectName: "keyboardHelpScroll"
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: contents.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            C.ScrollBar.vertical: C.ScrollBar {}
            Column {
                id: contents
                width: parent.width
                spacing: 14
                Repeater {
                    model: [
                        [[], "GENERAL"],
                        [["F1"], "Open or close this guide (outside Settings)"],
                        [["Tab", "Shift+Tab"], "Move to the next / previous control"],
                        [["Enter", "Space"], "Activate the focused button or list row"],
                        [["Esc"], "Close the open dropdown, Settings or guide; otherwise close Outbound"],
                        [[], "BUTTONS · FOCUS WITH TAB, THEN ENTER / SPACE"],
                        [["LIVE", "PAUSED"], "Pause or resume collection"],
                        [["Refresh"], "Collect once; stay paused if already paused"],
                        [["Header", "arrows"], "Switch between compact panel and expanded window"],
                        [["List", "arrows"], "Expand or restore the connection list"],
                        [["Gear"], "Open Collection, Globe and Credits settings"],
                        [[], "GLOBE · WHEN FOCUSED"],
                        [["←", "↑", "→", "↓"], "Rotate the globe"],
                        [["+", "=", "−"], "Zoom in (+ or =) / out (−); scrolling also zooms"],
                        [["Home"], "Reset globe orientation and zoom"],
                        [[], "FILTERS AND CONNECTIONS"],
                        [["↑", "↓"], "Move between rows in the focused country, application or connection list"],
                        [["Enter", "Space"], "Toggle a country/application filter, or select a connection"],
                        [["Space", "↑", "↓", "Enter"], "Open a dropdown, choose an option and confirm"],
                        [[], "SETTINGS"],
                        [["Enter"], "Search for a city when the city field is focused"],
                        [["Tab", "Enter", "Space"], "Focus and choose a city result; the origin is saved immediately"],
                        [[], "THIS GUIDE"],
                        [["↑", "↓", "PgUp", "PgDn"], "Scroll the guide"]
                    ]
                    Column {
                        id: entry
                        required property var modelData
                        width: contents.width
                        spacing: 4
                        Label {
                            width: parent.width
                            visible: entry.modelData[0].length === 0
                            text: entry.modelData[1]
                            color: theme.accent
                            wrapMode: Text.Wrap
                            font.bold: true
                        }
                        Row {
                            visible: entry.modelData[0].length > 0
                            width: parent.width
                            spacing: 12
                            Flow {
                                id: keyCaps
                                width: contents.width >= 480 ? 180 : 110
                                spacing: 4
                                Repeater {
                                    model: entry.modelData[0]
                                    Rectangle {
                                        required property string modelData
                                        width: Math.max(24, keyLabel.implicitWidth + 12)
                                        height: Math.max(24, keyLabel.implicitHeight + 8)
                                        color: "transparent"
                                        border.color: theme.subdued
                                        Label {
                                            id: keyLabel
                                            anchors.centerIn: parent
                                            text: parent.modelData
                                            font.pixelSize: theme.size * 0.85
                                        }
                                    }
                                }
                            }
                            Label {
                                width: parent.width - keyCaps.width - parent.spacing
                                text: entry.modelData[1]
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }
                Rectangle { width: parent.width; height: 1; color: theme.border }
                Label {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    color: theme.subdued
                    text: "Use Play/Pause inside the globe to control rotation independently of collection.\nType in Search to filter by IP or application. Choose a country/application again to clear that filter; the ↺ button clears all filters. Select a connection, then focus Copy IP and press Enter or Space.\nIn Settings, Done saves edited paths, interval and manual coordinates. Esc closes without saving those edits; choosing a city saves its origin immediately.\nThe bar icon opens the compact panel with a left-click and the expanded window with a right-click. Switching views preserves filters, selection and globe position."
                }
            }
        }
        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_F1) { root.close(); event.accepted = true; return; }
            var delta = 0;
            if (event.key === Qt.Key_Down) delta = 32;
            else if (event.key === Qt.Key_Up) delta = -32;
            else if (event.key === Qt.Key_PageDown) delta = scroll.height * 0.8;
            else if (event.key === Qt.Key_PageUp) delta = -scroll.height * 0.8;
            else return;
            scroll.contentY = Math.max(0, Math.min(Math.max(0, scroll.contentHeight - scroll.height), scroll.contentY + delta));
            event.accepted = true;
        }
    }
}
