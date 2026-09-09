"""Real QML integration with a controlled helper and bounded test runner."""
from pathlib import Path
import shutil
import sys
import tempfile
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from capture_runtime import Runner


def main():
    root = Path(__file__).resolve().parent.parent
    with tempfile.TemporaryDirectory(prefix='easy-capture-interface-') as folder:
        target = Path(folder)
        plugin = target / 'plugin'
        plugin.mkdir()
        for path in list(root.glob('*.qml')) + list(root.glob('*.js')) + [root / 'qmldir']:
            shutil.copy2(path, plugin / path.name)
        shutil.copy2(root / 'tests/fake_backend.py', plugin / 'capture_backend.py')
        for name in ('Ui', 'Commons'):
            (target / name).symlink_to(Path('/usr/share/omarchy/shell') / name)
        shutil.copy2(root / 'tests/interface.qml', target / 'shell.qml')
        runner = Runner()
        code, raw = runner.run(['/usr/bin/qs', '-p', str(target), '--no-color'], timeout=15, limit=262144)
        output = raw.decode('utf-8', 'replace')
        print(output)
        if code or 'FAIL' in output or 'PASS interface' not in output or not (plugin / 'cancelled-test-marker').exists():
            raise SystemExit(1)


if __name__ == '__main__': main()
