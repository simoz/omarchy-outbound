pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtQuick.Controls.Basic as C
import QtQuick.Layouts

C.Popup {
    id: root
    objectName: "outboundSettings"
    required property var service
    property string validationError: ""
    width: Math.min(480,parent.width-24)
    height: Math.min(parent.height-24,body.implicitHeight+32)
    x: Math.max(12,parent.width-width-12)
    y: Math.max(12,Math.min(58,parent.height-height-12))
    padding: 16
    focus: true
    closePolicy: C.Popup.CloseOnEscape | C.Popup.CloseOnPressOutside
    Theme { id: theme }
    onAboutToShow: {
        backend.text = service.backendPath; database.text = service.databasePath;
        latitude.text = service.origin ? String(service.origin.lat) : "";
        longitude.text = service.origin ? String(service.origin.lon) : "";
        interval.text = String(service.intervalSeconds); validationError = ""; scroll.contentY=0;
    }
    background: Rectangle { color: theme.background; Frame { anchors.fill: parent; emphasized: true } }
    contentItem: Flickable {
        id: scroll
        contentHeight: body.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        C.ScrollBar.vertical: C.ScrollBar {}
        ColumnLayout {
            id: body
            width: scroll.width
            spacing: 10
            Label { text: "OUTBOUND / SETTINGS"; color:theme.accent; font.letterSpacing:1 }
            Choice {
                Layout.fillWidth:true
                description:"Data source"
                model:["Real connections", "Simulated data"]
                currentIndex:root.service.demoMode ? 1 : 0
                onActivated:root.service.demoMode=currentIndex === 1
            }
            Label {
                Layout.fillWidth:true; wrapMode:Text.Wrap
                text:root.service.demoMode ? "IPs, applications and country assignments are simulated." : root.service.error || root.service.geoStatus
                font.pixelSize:theme.size*0.9
            }
            Choice {
                objectName:"scenarioChoice"
                visible:root.service.demoMode
                Layout.fillWidth:true
                description:"Simulated data scenario"
                model:["Sample","Empty","Error","Busy / long names"]
                currentIndex:["sample","empty","error","busy"].indexOf(root.service.scenario)
                onActivated:root.service.setScenario(["sample","empty","error","busy"][currentIndex])
            }
            RowLayout {
                visible:!root.service.demoMode
                Layout.fillWidth:true
                ActionButton { Layout.fillWidth:true; text:root.service.paused ? "Resume collection" : "Pause collection"; onClicked:root.service.paused=!root.service.paused }
                ActionButton { text:"Retry"; onClicked:root.service.retry() }
            }
            Label { visible:!root.service.demoMode; Layout.fillWidth:true; wrapMode:Text.Wrap; text:root.service.coverageStatus; font.pixelSize:theme.size*0.85 }
            Label { text:"Backend executable · absolute path" }
            SearchField { id:backend; objectName:"backendPathField"; Layout.fillWidth:true; placeholderText:"Default: ~/.local/share/outbound/bin/outbound-engine"; Accessible.name:"Backend executable path" }
            Label { text:"Country MMDB · optional local file" }
            SearchField { id:database; Layout.fillWidth:true; placeholderText:"/path/to/country.mmdb"; Accessible.name:"Local GeoIP database path" }
            Label { text:"Manual origin · leave both blank for markers only"; Layout.fillWidth:true; wrapMode:Text.Wrap }
            RowLayout {
                Layout.fillWidth:true
                SearchField { id:latitude; Layout.fillWidth:true; Layout.preferredWidth:1; placeholderText:"Latitude"; Accessible.name:"Origin latitude" }
                SearchField { id:longitude; Layout.fillWidth:true; Layout.preferredWidth:1; placeholderText:"Longitude"; Accessible.name:"Origin longitude" }
            }
            Label { text:"Refresh interval · seconds (1–60)" }
            SearchField { id:interval; Layout.fillWidth:true; Accessible.name:"Refresh interval in seconds" }
            Label { visible:root.validationError !== ""; Layout.fillWidth:true; wrapMode:Text.Wrap; text:root.validationError }
            ActionButton {
                Layout.fillWidth:true; text:"Apply collection settings"
                onClicked:root.validationError=root.service.configure(backend.text.trim(),database.text.trim(),latitude.text,longitude.text,interval.text)
            }
            ActionButton { Layout.fillWidth:true; text:"Reduced motion: " + (root.service.reducedMotion ? "on" : "off"); selected:root.service.reducedMotion; onClicked:root.service.reducedMotion=!root.service.reducedMotion }
            ActionButton { Layout.fillWidth:true; text:"Glow: " + (root.service.glow ? "on" : "off"); selected:root.service.glow; onClicked:root.service.glow=!root.service.glow }
            ActionButton { Layout.fillWidth:true; text:"Scanlines: " + (root.service.scanlines ? "on" : "off"); selected:root.service.scanlines; onClicked:root.service.scanlines=!root.service.scanlines }
            Label { Layout.fillWidth:true; wrapMode:Text.Wrap; text:"Country markers are approximate. Direction is unknown. Shared sockets can belong to several applications. No GeoIP downloads."; font.pixelSize:theme.size*0.85 }
            Label {
                Layout.fillWidth:true; wrapMode:Text.Wrap; font.pixelSize:theme.size*0.85
                text:"Made with Natural Earth. For DB-IP Lite: IP Geolocation by DB-IP · CC BY 4.0."
            }
            ActionButton { Layout.fillWidth:true; text:"DB-IP data and attribution"; onClicked:Qt.openUrlExternally("https://db-ip.com/db/lite.php") }
            ActionButton { Layout.fillWidth:true; text:"CC BY 4.0 license"; onClicked:Qt.openUrlExternally("https://creativecommons.org/licenses/by/4.0/") }
            ActionButton { Layout.fillWidth:true; text:"Done"; onClicked:root.close() }
        }
    }
    Connections {
        target: root.visible ? root.parent.Window.window : null
        function onActiveFocusItemChanged() {
            if (!root.visible) return;
            var item=root.parent.Window.window.activeFocusItem, ancestor=item;
            while (ancestor && ancestor !== body) ancestor=ancestor.parent;
            if (!item || ancestor !== body) return;
            var pos=item.mapToItem(body,0,0);
            if(pos.y < scroll.contentY) scroll.contentY=pos.y;
            else if(pos.y+item.height > scroll.contentY+scroll.height) scroll.contentY=Math.min(scroll.contentHeight-scroll.height,pos.y+item.height-scroll.height);
        }
    }
}
