import QtQuick
import qs.Ui as UI

UI.BarWidget {
    id: root
    moduleName: "io.github.simoz.outbound"
    readonly property var host: bar
    readonly property var service: host && host.shell ? host.shell.serviceFor(moduleName) : null
    readonly property bool opened: panel.opened
    readonly property bool popoutSwitchClosing: panel.popoutSwitchClosing
    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight
    function open() { panel.open(); }
    function close() { panel.close(); }
    function toggle() { panel.toggle(); }
    function closeForPopoutSwitch() { panel.closeForPopoutSwitch(); }

    UI.WidgetButton {
        id: button
        objectName: "outboundBarButton"
        anchors.fill: parent
        bar: root.bar
        text: root.vertical ? "OB\n" + (root.service ? root.service.rows.length + "/" + root.service.countryCount : "—") + "\nDEMO"
            : "◎ " + (root.service ? root.service.rows.length + " / " + root.service.countryCount : "—") + "  DEMO"
        tooltipText: "Outbound — simulated sockets / countries. Open network globe."
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: tooltipText
        Accessible.onPressAction: root.toggle()
        Keys.onSpacePressed: root.toggle()
        Keys.onReturnPressed: root.toggle()
        onPressed: function(button) { if (button === Qt.LeftButton) root.toggle(); }
    }
    Panel {
        id: panel
        bar: root.bar
        service: root.service
        anchorItem: button
        hostWidget: root
    }
}
