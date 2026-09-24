"""Verify saved origin across fresh preview directories; no personal settings."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

repository = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="outbound-settings-test-") as config:
    for mode in ["save", "read"]:
        preview = Path(subprocess.check_output([sys.executable, "-B", str(repository / "tools/prepare_preview.py")], text=True).strip())
        try:
            path = preview / "shell.qml"
            source = path.read_text().replace("standalone: true", "standalone: false")
            source = source.replace('            var palette = Quickshell.env("OUTBOUND_THEME");', '''
            function check(ok,message) { if(!ok) { console.error("SETTINGS_FAIL",message); Qt.quit(); throw new Error(message); } }
            if (Quickshell.env("SETTINGS_MODE") === "save") {
                check(service.configure("/tmp/test-backend", "", "41.9", "12.5", "3", "Test origin") === "", "save");
                console.log("SETTINGS_PASS save"); Qt.quit(); return;
            }
            check(service.origin && service.origin.name === "Test origin" && service.origin.lat === 41.9 && service.origin.lon === 12.5, "origin restored");
            check(service.intervalSeconds === 3, "interval restored");
            service.demoMode=false;
            service.liveRows=[{id:"test",app:"Test",country:"US",family:"IPv4",ip:"192.0.2.1"}];
            check(dashboard.globe.layers[2].length > 0, "restored origin produces arcs");
            check(dashboard.globe.linksAnimating, "arcs animate");
            console.log("SETTINGS_PASS read"); Qt.quit(); return;
            var palette = Quickshell.env("OUTBOUND_THEME");''')
            path.write_text(source)
            env = dict(os.environ, XDG_CONFIG_HOME=config, SETTINGS_MODE=mode,
                       QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME="basic")
            for name in ("OUTBOUND_BACKEND", "OUTBOUND_DATABASE", "OUTBOUND_LIVE"):
                env.pop(name, None)
            result = subprocess.run(["qs", "-p", str(preview), "--no-color"], env=env, capture_output=True, text=True, timeout=10)
            output = result.stdout + result.stderr
            if result.returncode or f"SETTINGS_PASS {mode}" not in output or "SETTINGS_FAIL" in output:
                raise RuntimeError(output)
            print(f"PASS preview settings: {mode}")
        finally:
            shutil.rmtree(preview)
    assert (Path(config) / "outbound/preview.ini").is_file()
