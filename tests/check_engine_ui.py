"""Quickshell collector installer lifecycle checks with a local fixture installer, no downloads."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

repository = Path(__file__).resolve().parents[1]
preview = Path(subprocess.check_output([sys.executable, "-B", str(repository / "tools/prepare_preview.py")], text=True).strip())
# The fixture installer copies the locally built collector to the managed path.
(preview / "plugin/tools/install_engine.py").write_text('''import os, pathlib, shutil, sys, time
pathlib.Path(os.environ['ENGINE_PID']).write_text(str(os.getpid()))
mode=os.environ['ENGINE_MODE']
if mode == 'failure': sys.exit(1)
if mode == 'unavailable': sys.exit(3)
if mode == 'cancel': time.sleep(30)
folder=pathlib.Path(os.environ['XDG_DATA_HOME'])/'outbound/bin'
folder.mkdir(parents=True,exist_ok=True)
shutil.copy2(os.environ['ENGINE_FIXTURE'],folder/'outbound-engine')
''')
(preview / "shell.qml").write_text('''import QtQuick
import Quickshell
import "plugin" as Plugin
import "plugin/ui" as Outbound
ShellRoot {
    id: root
    property int ticks: 0
    property int stage: 0
    property string mode: Quickshell.env("ENGINE_MODE")
    Plugin.Service { id: service; standalone: true; backendPath: root.mode === "custom" ? "/missing/outbound-engine" : ""; intervalSeconds:1; Component.onCompleted: setView("test",true) }
    Outbound.Dashboard { id: dashboard; width:1000; height:900; service:service }
    function find(item, name) {
        if(item.objectName === name) return item;
        var children=item.children || [];
        for(var i=0;i<children.length;i++){ var found=find(children[i], name); if(found) return found; }
        return null;
    }
    function check(ok, message) { if(!ok) { console.error("ENGINE_FAIL",message); Qt.quit(); throw new Error(message); } }
    function pass() { console.log("ENGINE_PASS",mode); Qt.quit(); }
    Timer {
        interval:25; repeat:true; running:true
        onTriggered: {
            if(++root.ticks > 400) { root.check(false,"deadline"); return; }
            if(root.stage === 0 && service.needsEngine) {
                var button=root.find(dashboard,"installEngineButton");
                root.check(button && button.visible,"collector install offered before GeoIP");
                root.check(!root.find(dashboard,"installGeoIpButton").visible,"GeoIP install hidden without a collector");
                button.clicked();
                root.check(service.engineInstalling && !service.geoInstalling,"click starts collector installer");
                root.stage=1;
            } else if(root.stage === 1) {
                if(root.mode === "cancel" && root.ticks > 30) { service.setView("test",false); root.stage=2; }
                else if(root.mode === "failure" && !service.engineInstalling) {
                    root.check(service.engineInstallError.indexOf("failed") >= 0 && service.needsEngine,"failure visible"); root.pass();
                } else if(root.mode === "unavailable" && !service.engineInstalling) {
                    root.check(service.engineInstallError.indexOf("No prebuilt collector") >= 0 && service.needsEngine,"unavailable asset explained"); root.pass();
                } else if((root.mode === "success" || root.mode === "custom") && service.snapshot) {
                    root.check(service.backendPath === "","managed path selected");
                    root.check(!service.engineInstalling && !service.needsEngine && service.engineInstallError === "","ready UI");
                    root.pass();
                }
            } else if(root.stage === 2 && !service.engineInstalling) {
                root.check(service.engineInstallError.indexOf("cancelled") >= 0,"cancel visible"); root.pass();
            }
        }
    }
}
''')
try:
    for mode in ["success", "custom", "failure", "unavailable", "cancel"]:
        with tempfile.TemporaryDirectory(prefix="outbound-engine-test-") as data:
            pid = Path(data) / "pid"
            env = dict(os.environ, XDG_DATA_HOME=data, ENGINE_MODE=mode, ENGINE_PID=str(pid),
                       ENGINE_FIXTURE=os.environ.get("OUTBOUND_TEST_NATIVE_BACKEND", str(repository / "backend/ruby/build/outbound-engine")),
                       QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME="basic")
            result = subprocess.run(["qs", "-p", str(preview), "--no-color"], env=env, text=True, capture_output=True, timeout=15)
            output = result.stdout + result.stderr
            if result.returncode or f"ENGINE_PASS {mode}" not in output or "ENGINE_FAIL" in output:
                raise RuntimeError(output)
            assert pid.exists(), "Installer did not start"
            assert not Path(f"/proc/{pid.read_text()}").exists(), "Installer survived"
            print(f"PASS collector UI: {mode}")
finally:
    shutil.rmtree(preview)
