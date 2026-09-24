"""Assemble an isolated Quickshell config with the installed host UI modules."""

from pathlib import Path
import json
import shutil
import tempfile

repository = Path(__file__).resolve().parents[1]
target = Path(tempfile.mkdtemp(prefix="outbound-preview-"))
plugin = target / "plugin"
plugin.mkdir()
for pattern in ("*.qml", "*.js"):
    for source in repository.glob(pattern):
        shutil.copy2(source, plugin / source.name)
for folder in ("ui", "assets", "fixtures"):
    shutil.copytree(repository / folder, plugin / folder)
for folder in ("Commons", "Ui"):
    shutil.copytree(Path("/usr/share/omarchy/shell") / folder, target / folder)
preview = (repository / "tools" / "preview.qml").read_text()
preview = preview.replace('import ".." as Plugin', 'import "plugin" as Plugin')
preview = preview.replace('import "../ui" as Outbound', 'import "plugin/ui" as Outbound')
preview = preview.replace('"__OUTBOUND_BACKEND__"', json.dumps(str(repository / "backend/target/release/outbound-engine")))
(target / "shell.qml").write_text(preview)
print(target)
