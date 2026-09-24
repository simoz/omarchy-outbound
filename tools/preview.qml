import QtQuick
import QtQuick.Window
import Quickshell
import qs.Commons
import ".." as Plugin
import "../ui" as Outbound

// Isolated preview: real theme components, simulated host, no desktop changes.
ShellRoot {
    id: root
    property var sampleIntervals: []
    property double previousTick: 0
    Plugin.Service {
        id: service
        standalone: true
        demoMode: Quickshell.env("OUTBOUND_LIVE") !== "1"
        backendPath: Quickshell.env("OUTBOUND_BACKEND") || "__OUTBOUND_BACKEND__"
        databasePath: Quickshell.env("OUTBOUND_DATABASE") || ""
    }
    Window {
        id: window
        visible: true
        onVisibleChanged: {
            if (visible) service.setView(window,true); else service.removeView(window);
        }
        Component.onCompleted: service.setView(window,true)
        width: Number(Quickshell.env("OUTBOUND_WIDTH")) || 1440
        height: Number(Quickshell.env("OUTBOUND_HEIGHT")) || 940
        title: service.demoMode ? "Outbound — simulated preview" : "Outbound — live preview"
        Outbound.Dashboard {
            id: dashboard
            anchors.fill: parent
            service: service
            expanded: true
            surfaceSwitchAvailable: false
            onCloseRequested: Qt.quit()
            onCopyRequested: function(text) { feedback = "Preview copy request: " + text; }
        }
    }
    Timer {
        interval: 1000
        running: true
        onTriggered: {
            // Preserve the installed theme unless a visual-test palette is requested.
            var palette = Quickshell.env("OUTBOUND_THEME");
            if (palette === "light" || palette === "dark") {
                var light = palette === "light";
                Color.shellValues = {};
                Color.background = light ? "#f5f2e8" : "#061017";
                Color.foreground = light ? "#202a30" : "#c8e5eb";
                Color.accent = light ? "#23595b" : "#53d6e8";
            }
            if (service.demoMode) service.setScenario(Quickshell.env("OUTBOUND_SCENARIO") || "sample");
            dashboard.globe.renderer = Quickshell.env("OUTBOUND_RENDERER") || "canvas";
            if (Quickshell.env("OUTBOUND_BENCHMARK")) {
                previousTick = Date.now();
                benchmark.start();
            } else capture.start();
        }
    }
    Timer {
        id: benchmark
        interval: 16
        repeat: true
        onTriggered: {
            var now = Date.now();
            root.sampleIntervals.push(now - root.previousTick);
            root.previousTick = now;
            dashboard.globe.rotate(1.5, 0);
            if (root.sampleIntervals.length < 120) return;
            stop();
            var sorted = root.sampleIntervals.slice().sort(function(a,b) { return a-b; });
            console.log("OUTBOUND_PROFILE", JSON.stringify({
                renderer: dashboard.globe.renderer,
                ticks: sorted.length,
                meanIntervalMs: root.sampleIntervals.reduce(function(a,b) { return a+b; }, 0) / sorted.length,
                p95IntervalMs: sorted[Math.floor(sorted.length * 0.95)],
                canvasPaints: dashboard.globe.paintCount
            }));
            settle.start();
        }
    }
    Timer {
        id: settle
        interval: 100
        onTriggered: idleCheck.start()
    }
    Timer {
        id: idleCheck
        property int previousPaints: 0
        interval: 350
        onRunningChanged: if (running) previousPaints = dashboard.globe.paintCount
        onTriggered: {
            console.log("OUTBOUND_IDLE_PAINTS", dashboard.globe.paintCount - previousPaints);
            Qt.quit();
        }
    }
    Timer {
        id: capture
        interval: 700
        onTriggered: {
            var output = Quickshell.env("OUTBOUND_CAPTURE");
            if (!output) return;
            dashboard.grabToImage(function(result) {
                if (!result.saveToFile(output)) console.error("Unable to save preview");
                console.log("OUTBOUND_CAPTURE_COMPLETE", output);
                Qt.quit();
            });
        }
    }
}
