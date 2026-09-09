"""Cross-monitor candidates, transforms, cancellation and numeric validation."""
import json
import sys
from pathlib import Path
import unittest
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import capture_backend as backend
from capture_runtime import CaptureError, Cancelled

class FixtureRunner:
    def __init__(self, displays, clients):
        self.displays, self.clients = displays, clients
    def run(self, argv, **kwargs):
        return 0, json.dumps(self.displays if 'monitors' in argv else self.clients).encode()

class PickerTest(unittest.TestCase):
    def setUp(self):
        self.displays = [dict(id=0, name='HDMI-A-1', focused=True, x=0, y=0, width=1920, height=1080,
                             scale=1, transform=0, activeWorkspace={'id': 1}, specialWorkspace={'id': 0}),
                         dict(id=1, name='eDP-1', focused=False, x=-1280, y=0, width=2560, height=1600,
                             scale=2, transform=0, activeWorkspace={'id': 2}, specialWorkspace={'id': -99})]
        def client(monitor, workspace, x, y, **extra):
            return dict(monitor=monitor, workspace={'id': workspace}, at=[x, y], size=[600, 400], **extra)
        self.clients = [client(0, 1, 10, 30), client(1, 2, -1200, 30), client(1, 8, -1200, 450),
                        client(1, 2, -600, 30, hidden=True), client(1, 2, -600, 50, mapped=False),
                        client(1, -99, -1000, 60), client(1, 8, -900, 70, pinned=True)]
        self.runner = FixtureRunner(self.displays, self.clients)
    def candidates(self):
        return backend.app_rectangles(self.runner, backend.monitors(self.runner))
    def test_app_on_other_monitor_in_both_directions(self):
        for focused in (0, 1):
            for m in self.displays: m['focused'] = m['id'] == focused
            self.assertIn('-1200,30 600x400', self.candidates())
            self.assertIn('10,30 600x400', self.candidates())
    def test_hidden_windows_excluded_special_and_pinned_included(self):
        rects = self.candidates()
        for rect in ('-1200,450 600x400', '-600,30 600x400', '-600,50 600x400'):
            self.assertNotIn(rect, rects)
        for rect in ('-1000,60 600x400', '-900,70 600x400', '-1280,0 1280x800'):
            self.assertIn(rect, rects)
    def test_transformed_geometry(self):
        for transform in (1, 3, 5, 7):
            self.displays[1]['transform'] = transform
            self.assertIn('-1280,0 800x1280', self.candidates())
    def test_cancel_cleans_owned_freeze(self):
        class Freeze:
            def exited(self): return False
        class Runner:
            released = False
            def check(self): pass
            def start(self, *args, **kwargs): return Freeze()
            def run(self, *args, **kwargs): return 1, b''
            def release(self, child): self.released = True
        runner = Runner()
        with patch('capture_backend.time.sleep'), self.assertRaises(Cancelled):
            backend.choose(runner, {'target': 'region'}, backend.monitors(self.runner))
        self.assertTrue(runner.released)
    def test_invalid_geometry_rejected(self):
        for bad in ('1,2 0x400', '1,2 99999x99999', '1,2 $(command)x4', '<img>'):
            with self.assertRaises(CaptureError): backend.geometry(bad)
        self.clients[0]['at'][0] = 'a[$(touch victim)]'
        with self.assertRaises(CaptureError): self.candidates()

if __name__ == '__main__': unittest.main()
