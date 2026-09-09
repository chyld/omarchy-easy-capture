import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import unittest

HELPER = Path(__file__).resolve().parent.parent / 'capture-region.sh'


class PickerTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name)
        self.env = dict(os.environ, PATH=f'{self.path}:/usr/bin:/bin',
                        XDG_RUNTIME_DIR=str(self.path), PICKER_TEST_DIR=str(self.path))
        self.monitors = [
            dict(id=0, name='HDMI-A-1', focused=True, x=0, y=0, width=1920, height=1080,
                 scale=1, transform=0, activeWorkspace={'id': 1}, specialWorkspace={'id': 0}),
            dict(id=1, name='eDP-1', focused=False, x=-1280, y=0, width=2560, height=1600,
                 scale=2, transform=0, activeWorkspace={'id': 2}, specialWorkspace={'id': -99})]
        def client(monitor, workspace, x, y, **extra):
            return dict(monitor=monitor, workspace={'id': workspace}, at=[x, y], size=[600, 400], **extra)
        self.clients = [client(0, 1, 10, 30), client(1, 2, -1200, 30),
                        client(1, 8, -1200, 450),  # Hidden workspace.
                        client(1, 2, -600, 30, hidden=True),
                        client(1, 2, -600, 50, mapped=False),
                        client(1, -99, -1000, 60),  # Open special workspace.
                        client(1, 8, -900, 70, pinned=True)]
        self.write_command('hyprctl', '''#!/usr/bin/python3
import os, pathlib, sys
print((pathlib.Path(os.environ['PICKER_TEST_DIR']) / (sys.argv[1] + '.json')).read_text())
''')
        self.write_command('hyprpicker', '#!/bin/sh\nexec sleep 20\n')
        self.write_command('slurp', '''#!/usr/bin/python3
import os, pathlib, sys
p = pathlib.Path(os.environ['PICKER_TEST_DIR'])
rects = sys.stdin.read().splitlines()
(p / 'candidates.json').write_text(__import__('json').dumps(rects))
selection = os.environ.get('PICKER_TEST_SELECTION', '')
if selection in rects:
    print(selection)
else:
    sys.exit(1)
''')

    def write_command(self, name, text):
        path = self.path / name
        path.write_text(text)
        path.chmod(0o755)

    def run_picker(self, selection):
        for name, data in [('monitors', self.monitors), ('clients', self.clients)]:
            (self.path / f'{name}.json').write_text(json.dumps(data))
        result = subprocess.run(['bash', str(HELPER), 'windows', '--match-monitor', '--keep-freeze'],
                                env=dict(self.env, PICKER_TEST_SELECTION=selection),
                                text=True, capture_output=True, timeout=5)
        lines = result.stdout.splitlines()
        if lines and lines[0].isdigit():
            try:
                os.kill(int(lines[0]), signal.SIGTERM)
            except ProcessLookupError:
                pass
        self.assertTrue(lines and lines[0].isdigit(), 'freeze PID protocol')
        return result, lines[1:]

    def test_app_on_other_monitor_in_both_directions(self):
        for focus, selection in [(0, '-1200,30 600x400'), (1, '10,30 600x400')]:
            with self.subTest(focus=focus):
                for monitor in self.monitors:
                    monitor['focused'] = monitor['id'] == focus
                result, lines = self.run_picker(selection)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(lines, [selection])

    def test_hidden_windows_excluded_special_and_pinned_included(self):
        self.run_picker('-1200,30 600x400')
        candidates = json.loads((self.path / 'candidates.json').read_text())
        self.assertNotIn('-1200,450 600x400', candidates)
        self.assertNotIn('-600,30 600x400', candidates)
        self.assertNotIn('-600,50 600x400', candidates)
        self.assertIn('-1000,60 600x400', candidates)
        self.assertIn('-900,70 600x400', candidates)
        self.assertIn('-1280,0 1280x800', candidates)

    def test_monitor_match_and_transformed_geometry(self):
        self.monitors[1]['transform'] = 5
        result, lines = self.run_picker('-1280,0 800x1280')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(lines, ['monitor:eDP-1'])

    def test_cancel_returns_no_selection(self):
        result, lines = self.run_picker('')
        self.assertEqual(result.returncode, 1)
        self.assertEqual(lines, [])


if __name__ == '__main__':
    unittest.main()
