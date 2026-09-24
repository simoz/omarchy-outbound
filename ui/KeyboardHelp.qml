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
                        ["GENERAL", ""],
                        ["F1", "Open or close this guide"],
                        ["Tab / Shift+Tab", "Move to the next / previous control"],
                        ["Enter / Space", "Activate the focused button or list row"],
                        ["Esc", "Close the open menu or guide; otherwise close Outbound"],
                        ["GLOBE · WHEN FOCUSED", ""],
                        ["← ↑ → ↓", "Rotate the globe"],
                        ["Home", "Reset globe orientation"],
                        ["FILTERS AND CONNECTIONS", ""],
                        ["↑ / ↓", "Move between rows in the focused country, application or connection list"],
                        ["Enter / Space", "Toggle a country/application filter, or select a connection"],
                        ["Space, ↑ / ↓, Enter", "Open a dropdown, choose an option and confirm"],
                        ["Search", "Type to filter by IP or application. Editing keys keep their normal behavior."],
                        ["Copy IP", "Select a connection, then focus and activate Copy IP"],
                        ["THIS GUIDE", ""],
                        ["↑ / ↓ · PgUp / PgDn", "Scroll the guide"]
                    ]
                    Column {
                        id: entry
                        required property var modelData
                        width: contents.width
                        spacing: 4
                        Label { width: parent.width; text: entry.modelData[0]; color: theme.accent; wrapMode: Text.Wrap; font.bold: true }
                        Label { width: parent.width; visible: text !== ""; text: entry.modelData[1]; wrapMode: Text.Wrap }
                    }
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
