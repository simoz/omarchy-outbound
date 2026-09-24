import QtQuick
import Quickshell
import "plugin" as Plugin

ShellRoot {
    id: root
    property string mode: Quickshell.env("OUTBOUND_TRANSPORT_TEST")
    property int stage: 0
    property int ticks: 0
    property int stageTick: 0
    property var oldPid: null
    property var oldSession: null
    Plugin.Service {
        id: service
        standalone: true
        backendPath: Quickshell.env("OUTBOUND_TEST_BACKEND")
        intervalSeconds: 1
        Component.onCompleted: setView("first",true)
    }
    function check(value, message) { if (!value) { console.error("OUTBOUND_TEST_FAILED",mode,message); Qt.quit(); throw new Error(message); } }
    function next() { stage++; stageTick=ticks; }
    function pass() { console.log("OUTBOUND_TEST_PASS",mode); Qt.quit(); }
    Timer {
        interval: 25; repeat:true; running:true
        onTriggered: {
            root.ticks++;
            if (root.ticks > 400) { root.check(false,"deadline"); return; }
            var c=service.collector;
            if (!c) return;
            if (root.mode === "normal" || root.mode === "native") {
                if (root.stage === 0 && service.snapshot && service.snapshot.sequence >= 2) {
                    root.check(service.phase !== "error","collection");
                    if (root.mode === "normal") root.check(service.rows[0].app === "船🦀","Unicode chunks");
                    root.oldPid=c.processId; root.oldSession=service.snapshot.session;
                    service.setView("second",true); service.removeView("first");
                    root.check(service.openViews === 1 && c.processId === root.oldPid,"second monitor survives");
                    service.setView("second",false);
                    root.check(service.pollInterval === 10000 && c.processId === root.oldPid,"bar-only keeps process");
                    service.paused=true; root.next();
                } else if(root.stage === 1 && !c.busy) {
                    service.setView("second",true); root.next();
                } else if(root.stage === 2 && root.ticks-root.stageTick > 8) {
                    root.check(!c.busy && service.paused,"pause survives reopen"); service.paused=false; root.next();
                } else if(root.stage === 3 && service.snapshot.session !== root.oldSession) {
                    service.removeView("second"); root.next();
                } else if(root.stage === 4 && !c.busy && root.ticks-root.stageTick > 8) {
                    root.check(!service.demanded && !c.retryWaiting,"no orphan or retry"); root.pass();
                }
            } else if(root.mode === "retry") {
                if(root.stage === 0 && c.retries >= 2) { service.paused=true; root.next(); }
                else if(root.stage === 1 && root.ticks-root.stageTick > 85) {
                    root.check(!c.busy && !c.retryWaiting,"retry cancelled"); root.pass();
                }
            } else if(root.mode === "late") {
                if(root.stage === 0 && c.pending) { root.oldPid=c.processId; service.paused=true; root.next(); }
                else if(root.stage === 1 && root.ticks-root.stageTick > 2) { service.paused=false; root.check(c.processId === root.oldPid,"wait for old process exit"); root.next(); }
                else if(root.stage === 2 && root.ticks-root.stageTick > 13) { root.check(service.snapshot === null,"cancelled output ignored"); root.next(); }
                else if(root.stage === 3 && service.snapshot) { service.removeView("first"); root.next(); }
                else if(root.stage === 4 && !c.busy) root.pass();
            } else {
                if(service.phase === "error" && c.fatal && !c.busy) {
                    root.check(service.snapshot === null && c.buffer.length === 0 && !c.retryWaiting,"invalid data rejected without retry"); root.pass();
                }
            }
        }
    }
}
