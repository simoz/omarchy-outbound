pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import "Protocol.js" as Protocol

// One transport per service. Never replace a process until it has actually exited.
Item {
    id: root
    property var service: null
    readonly property bool wanted: service !== null && service.demanded
    readonly property string executable: service && service.backendPath ? service.backendPath : (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/outbound/bin/outbound-engine"
    readonly property string database: service && service.databasePath ? service.databasePath : (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/outbound/data/current/country.mmdb"
    property bool ready: false
    Component.onCompleted: { ready = true; startLater(); }
    property bool busy: false
    property bool accepting: false
    property bool stopping: false
    property bool started: false
    property bool fatal: false
    property bool destroying: false
    property int generation: 0
    property int retries: 0
    property int serial: 0
    property string pending: ""
    property string buffer: ""
    property string session: ""
    property double sequence: 0
    property int killStage: 0
    readonly property bool retryWaiting: retryTimer.running
    readonly property var processId: process.processId

    // One explicit helper at a time: "geoip" (DB-IP database) or "engine" (prebuilt collector).
    property string installTask: ""
    readonly property bool geoInstalling: installTask === "geoip"
    readonly property bool engineInstalling: installTask === "engine"
    property string geoInstallError: ""
    property string engineInstallError: ""
    property bool engineMissing: false
    property bool installCancelled: false
    property string installOriginalPath: ""
    function helper(name) { return decodeURIComponent(Qt.resolvedUrl("tools/" + name).toString().slice(7)); }
    function runInstaller(task, command, originalPath) {
        if (installTask || !service || service.openViews === 0) return;
        if (task === "geoip") geoInstallError = ""; else engineInstallError = "";
        installCancelled = false; installTask = task;
        installOriginalPath = originalPath;
        installer.command = command;
        installDeadline.restart();
        installer.running = true;
    }
    function installGeoIp() {
        if (service) runInstaller("geoip", ["python3", "-B", helper("update_geoip.py"), "--backend", executable], service.databasePath);
    }
    function installEngine() {
        if (service) runInstaller("engine", ["python3", "-B", helper("install_engine.py")], service.backendPath);
    }
    function cancelInstall() {
        if (!installTask) return;
        installCancelled = true;
        if (installer.processId > 0) installer.signal(15);
        installKill.restart();
    }
    function installFinished(message) {
        if (installTask === "geoip") geoInstallError = message; else engineInstallError = message;
        installTask = ""; installDeadline.stop(); installKill.stop();
    }
    Connections {
        target: root.service
        function onOpenViewsChanged() { if (root.service.openViews === 0) root.cancelInstall(); }
    }
    Timer { id: installDeadline; interval: 165000; onTriggered: root.cancelInstall() }
    Timer { id: installKill; interval: 500; onTriggered: if (installer.processId > 0) installer.signal(9) }
    Process {
        id: installer
        property bool started: false
        stdout: SplitParser { splitMarker: ""; onRead: function(data) {} }
        stderr: SplitParser { splitMarker: ""; onRead: function(data) {} }
        onStarted: { started = true; if (root.installCancelled) root.cancelInstall(); }
        onRunningChanged: {
            if (running) started = false;
            else if (!started && root.installTask) root.installFinished("Installer unavailable. Python 3 is required.");
        }
        // qmllint disable signal-handler-parameters
        onExited: function(exitCode) {
            var task = root.installTask;
            var name = task === "geoip" ? "GeoIP" : "Collector";
            if (root.destroying) { root.installTask = ""; return; }
            if (root.installCancelled) { root.installFinished(name + " installation cancelled."); return; }
            if (exitCode !== 0) {
                // install_engine.py exits with 3 when no asset is pinned for this version and machine.
                root.installFinished(task === "geoip"
                    ? "GeoIP installation failed. Check your connection and retry, or run update-geoip.sh for details."
                    : exitCode === 3
                    ? "No prebuilt collector is published yet for this version and architecture. Update the plugin later, or build the collector from source."
                    : "Collector installation failed. Check your connection and retry, or build it from source.");
                return;
            }
            root.installFinished("");
            // Switch to the managed file unless the user chose another path meanwhile.
            var origin = root.service.origin;
            var coordinates = [origin ? String(origin.lat) : "", origin ? String(origin.lon) : "", String(root.service.intervalSeconds)];
            if (task === "geoip" && root.service.databasePath === root.installOriginalPath)
                root.geoInstallError = root.service.configure(root.service.backendPath, "", coordinates[0], coordinates[1], coordinates[2]);
            else if (task === "engine" && root.service.backendPath === root.installOriginalPath)
                root.engineInstallError = root.service.configure("", root.service.databasePath, coordinates[0], coordinates[1], coordinates[2]);
            root.retry();
        }
        // qmllint enable signal-handler-parameters
    }

    function startLater() {
        var token = generation;
        Qt.callLater(function() { if (!root.destroying && token === root.generation) root.start(); });
    }
    function start() {
        if (!wanted || busy || fatal || destroying || retryTimer.running) return;
        if (executable[0] !== "/" || (database && database[0] !== "/")) { fatal = true; service.phase = "error"; service.error = "Configure absolute backend and database paths."; return; }
        generation++; busy = true; accepting = true; stopping = false; started = false; engineMissing = false;
        pending = ""; buffer = ""; session = ""; sequence = 0;
        service.phase = "starting"; service.error = "";
        process.stdinEnabled = true;
        process.command = database ? [executable,"--database",database] : [executable];
        watchdog.restart();
        process.running = true;
    }
    function stop() {
        generation++; accepting = false; stopping = true; pending = ""; buffer = "";
        poll.stop(); watchdog.stop(); retryTimer.stop();
        if (busy) { process.stdinEnabled = false; killStage = 0; killTimer.restart(); }
    }
    function failed(message, permanent) {
        service.phase = "error"; service.error = message;
        fatal = permanent;
        stop();
        // A failed active run retries after exit; an intentional stop does not.
        stopping = false;
        if (!busy && !permanent) scheduleRetry();
    }
    function scheduleRetry() {
        if (!wanted || fatal || destroying) return;
        if (retries >= 5) { fatal = true; service.phase = "error"; service.error = "Backend stopped repeatedly. Check settings and retry."; return; }
        retryTimer.interval = Math.pow(2,retries++) * 1000;
        service.phase = "retrying"; retryTimer.start();
    }
    function retry() {
        fatal = false; retries = 0; stop();
        if (!busy) startLater();
    }
    function request() {
        if (!wanted || !accepting || !started || pending) return;
        pending = "g" + generation + "-r" + (++serial);
        process.write(JSON.stringify({version:1,requestId:pending,command:"snapshot"}) + "\n");
        watchdog.restart();
    }
    function receive(chunk) {
        if (!accepting || !wanted) return;
        try {
            var framed = Protocol.frame(buffer, chunk); buffer = framed.buffer;
            framed.lines.forEach(function(line) {
                if (!root.pending) throw new Error("Unsolicited snapshot");
                var snapshot = Protocol.parse(line,root.pending,root.session,root.sequence);
                root.session = snapshot.session; root.sequence = snapshot.sequence; root.pending = "";
                watchdog.stop(); root.retries = 0;
                root.service.snapshot = snapshot;
                root.service.liveRows = Protocol.rows(snapshot);
                root.service.phase = snapshot.status === "ok" ? "live" : snapshot.status;
                root.service.error = snapshot.status === "error" ? "Socket collection failed. See coverage in settings." : "";
                poll.restart();
            });
        } catch (e) { failed("Invalid or incompatible backend output. Check the backend version and retry.",true); }
    }
    onWantedChanged: {
        if (!ready) return;
        if (wanted) startLater();
        else { stop(); if (service && !fatal) service.phase = service.paused ? "paused" : "idle"; }
    }
    onExecutableChanged: if (ready) retry()
    onDatabaseChanged: if (ready) retry()
    Component.onDestruction: { destroying = true; cancelInstall(); stop(); if (process.processId > 0) process.signal(15); }
    Timer { id: poll; interval: root.service ? root.service.pollInterval : 2000; onTriggered: root.request() }
    Timer { id: retryTimer; onTriggered: root.start() }
    Timer { id: watchdog; interval: 5000; onTriggered: root.failed("Backend response timed out.", false) }
    Timer {
        id: killTimer
        interval: 250
        onTriggered: {
            if (!root.busy || !(process.processId > 0)) return;
            process.signal(root.killStage === 0 ? 15 : 9);
            if (root.killStage++ === 0) restart();
        }
    }
    Process {
        id: process
        stdinEnabled: true
        stdout: SplitParser { splitMarker: ""; onRead: function(data) { root.receive(data); } }
        // Drain diagnostics without retaining or displaying raw process contents.
        stderr: SplitParser { splitMarker: ""; onRead: function(data) {} }
        onStarted: {
            root.started = true;
            if (root.accepting && root.wanted) root.request(); else process.stdinEnabled = false;
        }
        onRunningChanged: {
            if (root.busy && !running && !root.started) {
                root.busy = false; killTimer.stop(); watchdog.stop();
                root.engineMissing = true;
                root.failed("Collector unavailable. Install it or set its absolute path in settings.",true);
            }
        }
        // Quickshell exposes QProcess::ExitStatus without its enum in qmltypes.
        // qmllint disable signal-handler-parameters
        onExited: function() {
            var intentional = root.stopping;
            root.busy = false; root.accepting = false; root.pending = ""; root.buffer = "";
            watchdog.stop(); poll.stop(); killTimer.stop();
            if (!root.wanted || root.fatal || root.destroying) return;
            if (intentional) root.startLater();
            else { root.service.error = "Backend exited. Retrying…"; root.scheduleRetry(); }
        }
        // qmllint enable signal-handler-parameters
    }
}
