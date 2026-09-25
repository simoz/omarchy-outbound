import QtQuick
import qs.Ui as UI
import "ui" as Outbound

UI.BarWidget {
    id: root
    moduleName: "io.github.simoz.outbound"
    readonly property var host: bar
    readonly property var service: host && host.shell ? host.shell.serviceFor(moduleName) : null
    readonly property bool opened: panel.opened
    readonly property bool popoutSwitchClosing: panel.popoutSwitchClosing
    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight
    property var registeredService: null
    function syncView() {
        if (registeredService && registeredService !== service) registeredService.removeView(root);
        registeredService = service;
        if (service) { service.loadConfiguration(settings); service.setView(root,panel.opened); }
    }
    onServiceChanged: syncView()
    onOpenedChanged: syncView()
    onSettingsChanged: if (service) service.loadConfiguration(settings)
    Component.onCompleted: syncView()
    Component.onDestruction: if (registeredService) registeredService.removeView(root)
    function open() { panel.open(); }
    function close() { panel.close(); }
    function toggle() { panel.toggle(); }
    function closeForPopoutSwitch() { panel.closeForPopoutSwitch(); }

    UI.WidgetButton {
        id: button
        objectName: "outboundBarButton"
        anchors.fill: parent
        bar: root.bar
        labelVisible: false
        hasVisualContent: true
        fixedWidth: root.vertical ? barSize : barContents.implicitWidth + scaledHorizontalMargin * 2
        fixedHeight: root.vertical ? barContents.implicitHeight + scaledVerticalPadding * 2 : barSize
        tooltipText: "Outbound · " + (root.service ? root.service.status : "IDLE") + " · Open network globe"
        Grid {
            id: barContents
            anchors.centerIn: parent
            columns: root.vertical ? 1 : 2
            spacing: 6
            horizontalItemAlignment: Grid.AlignHCenter
            verticalItemAlignment: Grid.AlignVCenter
            Outbound.GlobeIcon {
                objectName: "outboundBarIcon"
                ink: button.foreground
            }
            Text {
                text: root.service ? root.service.rows.length + " / " + root.service.countryCount : "—"
                color: button.foreground
                font.family: button.fontFamily
                font.pixelSize: button.fontSize
            }
        }
        Rectangle {
            anchors.fill: parent
            color: "transparent"
            border.color: button.activeFocus ? button.foreground : "transparent"
        }
        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: "Outbound sockets and countries. Open network globe."
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
