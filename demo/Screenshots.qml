import QtQuick
import QtQuick.Window
import Quickshell
import qs.Commons
import "plugin" as Plugin
import "plugin/ui" as Outbound

// README and marketplace stills from demo/fixtures/outbound-engine (fictional data):
//   DEMO_SCENE=Screenshots DEMO_STILLS=/tmp/outbound-shots demo/run
// Each shot sets a view state, waits for the globe to repaint, then saves <name>.png.
ShellRoot {
    id: root
    readonly property string outDir: Quickshell.env("DEMO_FRAMES") || ""
    property int step: 0
    readonly property var shots: [
        {name: "overview", width: 1280, height: 1080, run: function() {
            globe.longitude = 12; globe.latitude = 32; globe.zoom = 1;
        }},
        {name: "country", width: 1280, height: 1080, run: function() {
            service.chooseCountry("DE");
            service.chooseApplication("firefox");
            globe.zoom = 1.8;
            var r = row(0); if (r) service.selection = r.modelData.id;
        }},
        {name: "connections", width: 1280, height: 860, run: function() {
            service.clearFilters(); service.selection = "";
            find(board, function(i) { return i.objectName === "connectionListToggleButton"; }).clicked();
        }}
    ]
    readonly property Item globe: board.globe

    function find(item, test) {
        if (!item) return null;
        if (test(item)) return item;
        for (var i = 0; i < item.children.length; i++) {
            var hit = find(item.children[i], test);
            if (hit) return hit;
        }
        if (item.contentItem && item.contentItem !== item) return find(item.contentItem, test);
        return null;
    }
    function row(n) {
        var list = find(board, function(i) { return i.objectName === "outboundConnections"; });
        return list ? find(list, function(i) { return i.objectName && i.objectName.indexOf("connection-") === 0 && i.index === n; }) : null;
    }

    Plugin.Service {
        id: service
        standalone: true
        saveConfiguration: function(config) { return true; }
        Component.onCompleted: {
            // Still frames: no pulse, so every capture shows the arcs at full strength.
            reducedMotion = true;
            loadConfiguration({backendPath: Quickshell.env("OUTBOUND_BACKEND"), databasePath: "",
                               origin: {lat: 45.46, lon: 9.19, name: "Milano"}, intervalSeconds: 2});
        }
    }
    Window {
        id: window
        visible: true
        width: 1280; height: 1080
        color: Color.background
        Component.onCompleted: service.setView(window, true)
        Outbound.Dashboard {
            id: board
            width: root.shots[Math.min(root.step, root.shots.length - 1)].width
            height: root.shots[Math.min(root.step, root.shots.length - 1)].height
            service: service
            expanded: true
            surfaceSwitchAvailable: false
        }
    }

    Timer {
        interval: 300; repeat: true; running: true
        onTriggered: if (service.rows.length > 0) { stop(); root.shoot(); }
    }
    function shoot() {
        shots[step].run();
        settle.start();
    }
    Timer {
        id: settle
        interval: 1200
        onTriggered: board.grabToImage(function(result) {
            if (root.outDir) result.saveToFile(root.outDir + "/" + root.shots[root.step].name + ".png");
            if (++root.step >= root.shots.length) { console.log("DEMO_COMPLETE", root.step); Qt.quit(); }
            else root.shoot();
        })
    }
}
