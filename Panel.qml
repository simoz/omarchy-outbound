pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import Quickshell
import qs.Ui as UI
import "ui" as Outbound

UI.Panel {
    id: root
    moduleName: "io.github.simoz.outbound"
    manageIpc: false
    property var service: null
    property Item anchorItem: null
    property var hostWidget: null
    property bool expanded: false
    readonly property Item scene: dashboard.item as Item

    function close() {
        controller.hide();
        expanded = false;
    }
    function changeSurface() {
        expanded = !expanded;
        Qt.callLater(function() { if (root.scene) root.scene.forceActiveFocus(); });
    }

    UI.KeyboardPanel {
        id: popup
        bar: root.bar
        owner: root.hostWidget || root
        anchorItem: root.anchorItem
        open: root.opened && !root.expanded
        focusTarget: root.scene
        contentWidth: fittedContentWidth(1060)
        contentHeight: fittedContentHeight(820)
        Item {
            id: compactHost
            anchors.fill: parent
            Outbound.Label {
                anchors.fill: parent
                visible: root.service === null
                wrapMode: Text.Wrap
                text: "Outbound service unavailable. This prototype requires the built-in Omarchy bar."
            }
        }
    }
    Window {
        id: expandedWindow
        title: root.service && root.service.demoMode ? "Outbound — simulated data" : "Outbound"
        width: 1160
        height: 920
        minimumWidth: 380
        minimumHeight: 360
        visible: root.opened && root.expanded
        onClosing: function(event) { event.accepted = false; root.close(); }
    }
    // A single loaded scene is reparented; camera, focusable fields and scroll
    // state are not recreated when switching surfaces or closing the panel.
    Loader {
        id: dashboard
        parent: root.expanded ? expandedWindow.contentItem : compactHost
        anchors.fill: parent
        active: root.service !== null
        sourceComponent: Outbound.Dashboard {
            service: root.service
            active: root.opened
            expanded: root.expanded
            onCloseRequested: root.close()
            onExpandRequested: root.changeSurface()
            onCopyRequested: function(text) {
                Quickshell.clipboardText = text;
                feedback = "Copied IP";
            }
        }
    }
}
