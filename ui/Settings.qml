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
    property string originName: ""
    property int section: 0
    onSectionChanged: { scroll.contentY = 0; service.clearCitySearch(); }
    function openOrigin() { open(); section = 1; Qt.callLater(function() { city.forceActiveFocus(); }); }
    function chooseOrigin(place) {
        originName=place.label; city.text=place.label;
        latitude.text=String(place.lat); longitude.text=String(place.lon);
        service.clearCitySearch();
        // Choosing a result commits only the origin; other editor drafts stay intact.
        validationError = service.configure(service.backendPath, service.databasePath,
            latitude.text, longitude.text, String(service.intervalSeconds), originName);
    }
    onClosed: service.clearCitySearch()
    width: Math.min(560,parent.width-24)
    height: Math.min(parent.height-24,680)
    x: Math.max(12,parent.width-width-12)
    y: Math.max(12,Math.min(58,parent.height-height-12))
    padding: 16
    focus: true
    closePolicy: C.Popup.CloseOnEscape | C.Popup.CloseOnPressOutside
    Theme { id: theme }
    onAboutToShow: {
        originName = service.origin ? service.origin.name || "" : "";
        city.text = originName; service.clearCitySearch();
        backend.text = service.backendPath; database.text = service.databasePath;
        latitude.text = service.origin ? String(service.origin.lat) : "";
        longitude.text = service.origin ? String(service.origin.lon) : "";
        interval.text = String(service.intervalSeconds); validationError = ""; scroll.contentY=0;
    }
    background: Rectangle { color: theme.background; Frame { anchors.fill: parent; emphasized: true } }
    contentItem: ColumnLayout {
        spacing: 12
        Label { text: "OUTBOUND / SETTINGS"; color: theme.accent; font.letterSpacing: 1 }
        RowLayout {
            Layout.fillWidth: true
            spacing: 4
            Repeater {
                objectName: "settingsSections"
                model: ["Collection", "Globe", "Appearance", "Credits"]
                ActionButton {
                    required property int index
                    required property string modelData
                    objectName: "settingsSection" + index
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    text: modelData
                    selected: root.section === index
                    onClicked: root.section = index
                }
            }
        }
        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: theme.border }
        Flickable {
            id: scroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: body.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            C.ScrollBar.vertical: C.ScrollBar {}
            ColumnLayout {
                id: body
                width: scroll.width - 12
                spacing: 10
                ColumnLayout {
                    visible: root.section === 0
                    Layout.fillWidth: true
                    spacing: 10
                    Label { text: "Connection collection"; font.bold: true }
                    Label { Layout.fillWidth: true; wrapMode: Text.Wrap; text: "Control how often real connections refresh."; color: theme.subdued; font.pixelSize: theme.size * 0.9 }
                    Label {
                        Layout.fillWidth:true; wrapMode:Text.Wrap
                        text:root.service.error || root.service.geoStatus
                        font.pixelSize:theme.size*0.9
                    }
                    RowLayout {
                        Layout.fillWidth:true
                        ActionButton { Layout.fillWidth:true; text:root.service.paused ? "Resume collection" : "Pause collection"; onClicked:root.service.paused=!root.service.paused }
                        ActionButton { text:"Retry"; onClicked:root.service.retry() }
                    }
                    Label { Layout.fillWidth:true; wrapMode:Text.Wrap; text:root.service.coverageStatus; font.pixelSize:theme.size*0.85 }
                    Label { text:"Refresh interval · seconds (1–60)" }
                    SearchField { id:interval; Layout.fillWidth:true; Accessible.name:"Refresh interval in seconds" }
                    Label { text:"Backend executable"; color: theme.subdued }
                    SearchField { id:backend; objectName:"backendPathField"; Layout.fillWidth:true; placeholderText:"Default: ~/.local/share/outbound/bin/outbound-engine"; Accessible.name:"Backend executable path" }
                }
                ColumnLayout {
                    visible: root.section === 1
                    Layout.fillWidth: true
                    spacing: 10
                    Label { text: "Globe & location"; font.bold: true }
                    Label { Layout.fillWidth: true; wrapMode: Text.Wrap; text: "Configure country lookup and the starting point of connection arcs."; color: theme.subdued; font.pixelSize: theme.size * 0.9 }
                    Label { text:"Country database"; font.bold:true }
                    SearchField { id:database; Layout.fillWidth:true; placeholderText:"Default: managed DB-IP Lite database"; Accessible.name:"Local GeoIP database path" }
                    Label { Layout.fillWidth:true; wrapMode:Text.Wrap; text:"Install from the globe or update below. A custom path overrides the managed database."; font.pixelSize:theme.size*0.85 }
                    ActionButton { Layout.fillWidth:true; enabled:!root.service.geoInstalling; text:root.service.geoInstalling ? "Downloading and validating…" : "Install / update managed GeoIP"; onClicked:root.service.installGeoIp() }
                    Label { Layout.fillWidth:true; wrapMode:Text.Wrap; visible:root.service.geoInstallError !== ""; text:root.service.geoInstallError }
                    Label { text:"Origin · search a city or enter coordinates"; font.bold:true; Layout.topMargin:12; Layout.fillWidth:true; wrapMode:Text.Wrap }
                    RowLayout {
                        Layout.fillWidth:true
                        SearchField {
                            id:city; objectName:"originCityField"; Layout.fillWidth:true
                            placeholderText:"City, e.g. Genoa, Italy"; maximumLength:120
                            Accessible.name:"Search origin city"
                            onTextEdited:root.service.clearCitySearch()
                            onAccepted:root.service.searchCity(text)
                        }
                        ActionButton { text:root.service.searchingCity ? "Searching…" : "Search"; enabled:!root.service.searchingCity && city.text.trim().length >= 2; onClicked:root.service.searchCity(city.text) }
                    }
                    Repeater {
                        model:root.service.cityResults
                        ActionButton {
                            required property var modelData
                            Layout.fillWidth:true
                            text:modelData.label
                            onClicked:root.chooseOrigin(modelData)
                        }
                    }
                    Label { Layout.fillWidth:true; wrapMode:Text.Wrap; text:"Choosing a city saves the origin immediately. Use Done to save manual coordinates."; color:theme.subdued; font.pixelSize:theme.size*0.85 }
                    Label { Layout.fillWidth:true; wrapMode:Text.Wrap; visible:root.originName !== ""; text:"Selected: " + root.originName }
                    Label { Layout.fillWidth:true; wrapMode:Text.Wrap; visible:root.service.cityError !== ""; text:root.service.cityError }
                    RowLayout {
                        Layout.fillWidth:true
                        SearchField { id:latitude; objectName:"originLatitude"; Layout.fillWidth:true; Layout.preferredWidth:1; placeholderText:"Latitude"; Accessible.name:"Origin latitude"; onTextEdited:root.originName="" }
                        SearchField { id:longitude; objectName:"originLongitude"; Layout.fillWidth:true; Layout.preferredWidth:1; placeholderText:"Longitude"; Accessible.name:"Origin longitude"; onTextEdited:root.originName="" }
                    }
                }
                ColumnLayout {
                    visible: root.section === 2
                    Layout.fillWidth: true
                    spacing: 10
                    Label { text: "Appearance"; font.bold: true }
                    Label { Layout.fillWidth: true; wrapMode: Text.Wrap; text: "Display changes apply immediately for this session."; color: theme.subdued; font.pixelSize: theme.size * 0.9 }
                    ActionButton { Layout.fillWidth:true; text:"Reduced motion: " + (root.service.reducedMotion ? "on" : "off"); selected:root.service.reducedMotion; onClicked:root.service.reducedMotion=!root.service.reducedMotion }
                    ActionButton { Layout.fillWidth:true; text:"Glow: " + (root.service.glow ? "on" : "off"); selected:root.service.glow; onClicked:root.service.glow=!root.service.glow }
                    ActionButton { Layout.fillWidth:true; text:"Scanlines: " + (root.service.scanlines ? "on" : "off"); selected:root.service.scanlines; onClicked:root.service.scanlines=!root.service.scanlines }
                }
                ColumnLayout {
                    visible: root.section === 3
                    Layout.fillWidth: true
                    spacing: 10
                    Label { text: "Credits"; font.bold: true }
                    Label { Layout.fillWidth: true; wrapMode: Text.Wrap; text: "Sources, licenses and limits of the connection view."; color: theme.subdued; font.pixelSize: theme.size * 0.9 }
                    Label { Layout.fillWidth:true; wrapMode:Text.Wrap; text:"Country markers are approximate. Direction is unknown. Shared sockets can belong to several applications. No automatic GeoIP downloads."; font.pixelSize:theme.size*0.85 }
                    Label {
                        Layout.fillWidth:true; wrapMode:Text.Wrap; font.pixelSize:theme.size*0.85
                        text:"Made with Natural Earth. Managed database: IP Geolocation by DB-IP · CC BY 4.0. Outbound code: MIT."
                    }
                    ActionButton { Layout.fillWidth:true; text:"City search: Photon / © OpenStreetMap contributors"; onClicked:Qt.openUrlExternally("https://photon.komoot.io/") }
                    ActionButton { Layout.fillWidth:true; text:"DB-IP data and attribution"; onClicked:Qt.openUrlExternally("https://db-ip.com/db/lite.php") }
                    ActionButton { Layout.fillWidth:true; text:"CC BY 4.0 license"; onClicked:Qt.openUrlExternally("https://creativecommons.org/licenses/by/4.0/") }
                }
            }
        }
        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: theme.border }
        Label { visible:root.validationError !== ""; Layout.fillWidth:true; wrapMode:Text.Wrap; text:root.validationError }
        ActionButton {
            objectName:"applyCollectionSettings"; Layout.fillWidth:true; text:"Done"
            onClicked: {
                root.validationError = root.service.configure(backend.text.trim(), database.text.trim(), latitude.text, longitude.text, interval.text, root.originName);
                if (root.validationError === "") root.close();
            }
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
