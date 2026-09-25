"""Real Quickshell search lifecycle with a local helper; no provider requests."""
import os
from pathlib import Path
import shutil
import subprocess
import sys

repository = Path(__file__).resolve().parents[1]
preview = Path(subprocess.check_output([sys.executable, "-B", str(repository / "tools/prepare_preview.py")], text=True).strip())
(preview / "plugin/tools/search_city.py").write_text('''import json, os, signal, sys, time
with open(os.environ['CITY_CALLS'],'a') as record: record.write(sys.argv[1]+'\\n')
if sys.argv[1] == 'Late':
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    time.sleep(0.3)
print(json.dumps(dict(ok=True,query=sys.argv[1],places=[dict(label='Test city',lat=44.4,lon=8.9)])))
''')
(preview / "shell.qml").write_text('''import QtQuick
import Quickshell
import "plugin" as Plugin
ShellRoot {
    id: root
    property int stage:0
    property int ticks:0
    property int startTick:0
    Plugin.Service { id: service; standalone:true; paused:true; Component.onCompleted:setView("test",true) }
    function check(ok,msg) { if(!ok) { console.error("CITY_FAIL",msg); Qt.quit(); throw new Error(msg); } }
    Timer {
        interval:25; repeat:true; running:true
        onTriggered: {
            if(++root.ticks > 200) { root.check(false,"deadline"); return; }
            if(root.stage === 0 && service.citySearch) { service.searchCity("Test"); root.stage=1; }
            else if(root.stage === 1 && !service.searchingCity) {
                root.check(service.cityResults.length === 1,"results");
                service.clearCitySearch(); service.searchCity("test");
                root.check(!service.searchingCity && service.cityResults.length === 1,"cache");
                service.clearCitySearch(); service.searchCity("Too soon");
                root.check(!service.searchingCity && service.cityError !== "","rate limit");
                root.startTick=root.ticks; root.stage=2;
            } else if(root.stage === 2 && root.ticks-root.startTick > 45) { service.searchCity("Late"); root.startTick=root.ticks; root.stage=3; }
            else if(root.stage === 3 && root.ticks-root.startTick > 3) { service.setView("test",false); root.stage=4; }
            else if(root.stage === 4 && !service.searchingCity) {
                root.check(service.cityResults.length === 0 && service.cityError === "","late response ignored");
                service.searchCity("Closed");
                root.check(!service.searchingCity,"no hidden request");
                console.log("CITY_PASS"); Qt.quit();
            }
        }
    }
}
''')
try:
    calls = preview / "calls"
    env = dict(os.environ, CITY_CALLS=str(calls), QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME="basic")
    result = subprocess.run(["qs", "-p", str(preview), "--no-color"], env=env, text=True, capture_output=True, timeout=10)
    output = result.stdout + result.stderr
    if result.returncode or "CITY_PASS" not in output or "CITY_FAIL" in output:
        raise RuntimeError(output)
    assert calls.read_text().splitlines() == ["Test", "Late"]
    print("PASS origin search: results, cache, rate limit, cancellation and late replies")
finally:
    shutil.rmtree(preview)
