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
        intervalSeconds: root.mode === "refresh" ? 60 : 1
        paused: root.mode.indexOf("refresh-") === 0
        Component.onCompleted: setView("first",root.mode !== "normal")
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
            if (root.mode === "normal" && !service.openViews && root.stage === 0) {
                root.check(!c.busy && !(c.processId > 0) && !c.retryWaiting && service.snapshot === null,"bar alone stays idle");
                if (root.ticks > 8) service.setView("first",true);
                return;
            }
            if (root.mode === "normal" || root.mode === "native") {
                if (root.stage === 0 && service.snapshot && service.snapshot.sequence >= 2) {
                    root.check(service.phase !== "error","collection");
                    if (root.mode === "normal") root.check(service.rows[0].app === "船🦀","Unicode chunks");
                    root.oldPid=c.processId; root.oldSession=service.snapshot.session;
                    service.setView("second",true); service.removeView("first");
                    root.check(service.openViews === 1 && c.processId === root.oldPid,"second monitor survives");
                    service.setView("second",false);
                    root.check(!service.demanded && service.snapshot === null && service.rows.length === 0,"last close clears snapshot");
                    root.next();
                } else if(root.stage === 1 && !c.busy) {
                    root.check(!c.retryWaiting && service.status === "IDLE","last close stops collection");
                    service.paused=true;
                    service.setView("second",true); root.next();
                } else if(root.stage === 2 && root.ticks-root.stageTick > 8) {
                    root.check(!c.busy && service.paused,"pause survives reopen"); service.paused=false; root.next();
                } else if(root.stage === 3 && service.snapshot && service.snapshot.session !== root.oldSession) {
                    service.removeView("second"); root.next();
                } else if(root.stage === 4 && !c.busy && root.ticks-root.stageTick > 8) {
                    root.check(!service.demanded && !c.retryWaiting,"no orphan or retry"); root.pass();
                }
            } else if(root.mode === "refresh") {
                if(root.stage === 0 && service.snapshot) {
                    root.oldPid=c.processId; root.oldSession=service.snapshot.session;
                    service.query="preserved";
                    service.refresh(); service.refresh(); root.next();
                } else if(root.stage === 1 && service.snapshot.sequence === 2) {
                    root.check(c.processId === root.oldPid && service.snapshot.session === root.oldSession,"refresh reuses live process");
                    service.paused=true;
                    // Refresh while the previous process is still shutting down.
                    service.refresh(); service.refresh(); root.next();
                } else if(root.stage === 2 && service.snapshot.session !== root.oldSession && !c.busy) {
                    root.check(service.paused && service.snapshot.sequence === 1,"paused refresh collects once");
                    root.check(service.query === "preserved" && !service.refreshing,"refresh preserves filters and finishes");
                    root.oldSession=service.snapshot.session; root.next();
                } else if(root.stage === 3 && root.ticks-root.stageTick > 45) {
                    root.check(!c.busy && !c.retryWaiting && service.snapshot.session === root.oldSession,"paused refresh stays stopped");
                    service.refresh(); service.setView("first",false); root.next();
                } else if(root.stage === 4 && root.ticks-root.stageTick > 8) {
                    root.check(!c.busy && !service.refreshing && service.snapshot === null,"close cancels deferred refresh"); root.pass();
                }
            } else if(root.mode === "refresh-failure" || root.mode === "refresh-late") {
                if(root.stage === 0) { service.refresh(); root.next(); }
                else if(root.stage === 1 && root.mode === "refresh-late" && c.pending) {
                    service.setView("first",false); root.next();
                } else if(root.stage === 1 && root.mode === "refresh-failure" && service.error && !c.busy) root.next();
                else if(root.stage === 2 && root.ticks-root.stageTick > 50) {
                    root.check(!c.busy && !c.retryWaiting && !service.refreshing && service.paused && service.snapshot === null,"one-shot failure or closure stays stopped"); root.pass();
                }
            } else if(root.mode === "retry") {
                if(root.stage === 0 && c.retries >= 2) { service.setView("first",false); root.next(); }
                else if(root.stage === 1 && root.ticks-root.stageTick > 85) {
                    root.check(!c.busy && !c.retryWaiting,"retry cancelled"); root.pass();
                }
            } else if(root.mode === "late") {
                if(root.stage === 0 && c.pending) { root.oldPid=c.processId; service.setView("first",false); root.next(); }
                else if(root.stage === 1 && root.ticks-root.stageTick > 2) { service.setView("first",true); root.check(c.processId === root.oldPid,"wait for old process exit"); root.next(); }
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
