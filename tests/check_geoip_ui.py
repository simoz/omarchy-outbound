"""Quickshell installer lifecycle checks with a local fixture installer, no downloads."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

repository = Path(__file__).resolve().parents[1]
preview = Path(subprocess.check_output([sys.executable, "-B", str(repository / "tools/prepare_preview.py")], text=True).strip())

# Original synthetic country MMDB for local integration tests.
def text(value):
    data = value.encode()
    return bytes([0x40 | len(data)]) + data


def mapping(items):
    return bytes([0xe0 | len(items)]) + b"".join(text(key) + value for key, value in items)


def small(value):
    return b"\xa2" + value.to_bytes(2, "big")


database = b"\x00\x00\x11\x00\x00\x11" + bytes(16)
database += mapping([("country", mapping([("iso_code", text("IT"))]))])
database += b"\xab\xcd\xefMaxMind.com" + mapping([
    ("binary_format_major_version", small(2)), ("binary_format_minor_version", small(0)),
    ("build_epoch", b"\x08\x02" + (1704067200).to_bytes(8, "big")),
    ("database_type", text("Outbound-Synthetic-Country")),
    ("description", mapping([("en", text("Synthetic test data"))])),
    ("ip_version", small(6)), ("languages", b"\x01\x04" + text("en")),
    ("node_count", b"\xc1\x01"), ("record_size", small(24)),
])
(preview / "synthetic.mmdb").write_bytes(database)
(preview / "plugin/tools/update_geoip.py").write_text('''import os, pathlib, shutil, signal, sys, time
pathlib.Path(os.environ['GEO_PID']).write_text(str(os.getpid()))
mode=os.environ['GEO_MODE']
if mode == 'failure': sys.exit(1)
if mode == 'cancel': time.sleep(30)
folder=pathlib.Path(os.environ['XDG_DATA_HOME'])/'outbound/data/current'
folder.mkdir(parents=True,exist_ok=True)
shutil.copyfile(os.environ['GEO_FIXTURE'],folder/'country.mmdb')
''')
(preview / "shell.qml").write_text('''import QtQuick
import Quickshell
import "plugin" as Plugin
import "plugin/ui" as Outbound
ShellRoot {
    id: root
    property int ticks: 0
    property int stage: 0
    property string oldSession: ""
    property string mode: Quickshell.env("GEO_MODE")
    Plugin.Service { id: service; standalone: true; backendPath: Quickshell.env("GEO_BACKEND"); intervalSeconds:1; databasePath:root.mode === "custom" ? "/missing/custom.mmdb" : ""; Component.onCompleted: setView("test",true) }
    Outbound.Dashboard { id: dashboard; width:1000; height:900; service:service }
    function find(item) {
        if(item.objectName === "installGeoIpButton") return item;
        var children=item.children || [];
        for(var i=0;i<children.length;i++){ var found=find(children[i]); if(found) return found; }
        return null;
    }
    function check(ok, message) { if(!ok) { console.error("GEO_FAIL",message); Qt.quit(); throw new Error(message); } }
    function pass() { console.log("GEO_PASS",mode); Qt.quit(); }
    Timer {
        interval:25; repeat:true; running:true
        onTriggered: {
            if(++root.ticks > 400) { root.check(false,"deadline"); return; }
            if(root.stage === 0 && service.snapshot) {
                root.check(service.needsGeoIp,"initially missing");
                root.oldSession=service.snapshot.session;
                root.find(dashboard).clicked();
                root.check(service.geoInstalling,"click starts installer");
                root.stage=1;
            } else if(root.stage === 1) {
                if(root.mode === "cancel" && root.ticks > 30) { service.setView("test",false); root.stage=2; }
                else if(root.mode === "failure" && !service.geoInstalling) {
                    root.check(service.geoInstallError !== "" && service.needsGeoIp,"failure visible"); root.pass();
                } else if((root.mode === "success" || root.mode === "custom") && service.snapshot.database.state === "ready") {
                    root.check(service.databasePath === "","managed path selected");
                    root.check(!service.geoInstalling && !service.needsGeoIp && service.geoInstallError === "","ready UI");
                    root.check(service.snapshot.session !== root.oldSession,"collector reloaded"); root.pass();
                }
            } else if(root.stage === 2 && !service.geoInstalling) {
                root.check(service.geoInstallError.indexOf("cancelled") >= 0,"cancel visible"); root.pass();
            }
        }
    }
}
''')
try:
    for mode in ["success", "custom", "failure", "cancel"]:
        with tempfile.TemporaryDirectory(prefix="outbound-geoip-test-") as data:
            pid = Path(data) / "pid"
            env = dict(os.environ, XDG_DATA_HOME=data, GEO_MODE=mode, GEO_PID=str(pid),
                       GEO_FIXTURE=str(preview / "synthetic.mmdb"),
                       GEO_BACKEND=os.environ.get("OUTBOUND_TEST_NATIVE_BACKEND", str(repository / "backend/ruby/build/outbound-engine")),
                       QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME="basic")
            result = subprocess.run(["qs", "-p", str(preview), "--no-color"], env=env, text=True, capture_output=True, timeout=15)
            output = result.stdout + result.stderr
            if result.returncode or f"GEO_PASS {mode}" not in output or "GEO_FAIL" in output:
                raise RuntimeError(output)
            assert pid.exists(), "Installer did not start"
            assert not Path(f"/proc/{pid.read_text()}").exists(), "Installer survived"
            print(f"PASS GeoIP UI: {mode}")
finally:
    import shutil
    shutil.rmtree(preview)
