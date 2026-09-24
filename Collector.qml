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
    readonly property string database: service ? service.databasePath : ""
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

    function startLater() {
        var token = generation;
        Qt.callLater(function() { if (!root.destroying && token === root.generation) root.start(); });
    }
    function start() {
        if (!wanted || busy || fatal || destroying || retryTimer.running) return;
        if (executable[0] !== "/" || (database && database[0] !== "/")) { fatal = true; service.phase = "error"; service.error = "Configure absolute backend and database paths."; return; }
        generation++; busy = true; accepting = true; stopping = false; started = false;
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
    Component.onDestruction: { destroying = true; stop(); if (process.processId > 0) process.signal(15); }
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
                root.failed("Backend unavailable. Build it and set its absolute path in settings.",true);
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
