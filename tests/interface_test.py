from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix='easy-capture-interface-') as folder:
    target = Path(folder)
    plugin = target / 'plugin'
    plugin.mkdir()
    for path in list(root.glob('*.qml')) + list(root.glob('*.js')) + list(root.glob('*.sh')):
        shutil.copy2(path, plugin / path.name)
    for name in ('Ui', 'Commons'):
        (target / name).symlink_to(Path('/usr/share/omarchy/shell') / name)
    shutil.copy2(root / 'tests/interface.qml', target / 'shell.qml')
    result = subprocess.run(['qs', '-p', str(target), '--no-color'], capture_output=True, text=True, timeout=15)
    output = result.stdout + result.stderr
    print(output)
    if result.returncode or 'FAIL' in output or 'PASS tabs' not in output:
        raise SystemExit(1)
