"""Check bar clicks and surface state with host button/controller and a simulated layer surface, offscreen."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

repository = Path(__file__).resolve().parents[1]
preview = Path(subprocess.check_output(
    [sys.executable, "-B", str(repository / "tools/prepare_preview.py")], text=True).strip())
try:
    # Layer-shell windows require Wayland; keep only the surface simulated.
    (preview / "Ui/KeyboardPanel.qml").write_text('''import QtQuick
Item {
    property var bar
    property var owner
    property var anchorItem
    property bool open: false
    property var focusTarget
    property int contentWidth
    property int contentHeight
    width: contentWidth
    height: contentHeight
    function fittedContentWidth(value) { return value; }
    function fittedContentHeight(value) { return value; }
}
''')
    (preview / "shell.qml").write_text('''import QtQuick
import Quickshell
import "plugin" as Plugin

ShellRoot {
    Plugin.Service { id: service; paused: true }
    Plugin.BarWidget { id: widget }
    Timer {
        interval: 100
        running: true
        onTriggered: {
            function check(ok, message) {
                if (!ok) { console.error("PANEL_FAIL", message); Qt.quit(); throw new Error(message); }
            }
            var button = null;
            var panel = null;
            for (var child of widget.children) {
                if (child.objectName === "outboundBarButton") button = child;
                if ("openExpanded" in child) panel = child;
            }
            check(button && panel, "widget children");
            panel.service = service;
            var scene = panel.scene;
            check(scene, "dashboard loaded");
            scene.globe.zoom = 2;
            service.query = "preserved";
            button.triggerPress(Qt.RightButton);
            check(widget.opened && panel.expanded, "right click opens expanded");
            button.triggerPress(Qt.RightButton);
            check(widget.opened && panel.expanded, "repeated right click stays open");
            widget.close();
            check(!widget.opened && !panel.expanded, "close resets surface");
            button.triggerPress(Qt.LeftButton);
            check(widget.opened && !panel.expanded, "left click opens compact");
            button.triggerPress(Qt.RightButton);
            check(widget.opened && panel.expanded, "right click expands compact");
            check(panel.scene === scene && scene.globe.zoom === 2 && service.query === "preserved",
                  "surface switch preserves scene and state");
            button.triggerPress(Qt.LeftButton);
            check(!widget.opened, "left click closes expanded");
            console.log("PANEL_PASS");
            Qt.quit();
        }
    }
}
''')
    with tempfile.TemporaryDirectory(prefix="outbound-panel-config-") as config:
        env = dict(os.environ, XDG_CONFIG_HOME=config,
                   QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME="basic")
        result = subprocess.run(["qs", "-p", str(preview), "--no-color"],
                                env=env, capture_output=True, text=True, timeout=15)
        output = result.stdout + result.stderr
        if result.returncode or "PANEL_PASS" not in output or "PANEL_FAIL" in output:
            raise RuntimeError(output)
        print("PASS bar clicks and compact/expanded scene preservation (offscreen)")
finally:
    shutil.rmtree(preview)
