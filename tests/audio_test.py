"""Audio option validation and the exact recorder argv."""
import sys
from pathlib import Path
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import capture_backend as backend
from capture_runtime import CaptureError

class AudioArgumentsTest(unittest.TestCase):
    def test_all_audio_combinations(self):
        for desktop in (False, True):
            for microphone in (False, True):
                for source in ('', 'alsa_input.usb-headset'):
                    with self.subTest(desktop=desktop, microphone=microphone, source=source):
                        data = dict(desktop=desktop, microphone=microphone, input=source)
                        cmd = backend.recorder_arguments(data, '10,20 640x480', 17)
                        self.assertEqual(cmd[0], '/usr/bin/gpu-screen-recorder')
                        self.assertEqual(cmd[cmd.index('-w') + 1], 'region')
                        self.assertEqual(cmd[cmd.index('-region') + 1], '640x480+10+20')
                        self.assertEqual(cmd[cmd.index('-o') + 1], '/proc/self/fd/17')
                        self.assertEqual(cmd[cmd.index('-c') + 1], 'mp4')
                        expected = []
                        if desktop: expected.append('default_output')
                        if microphone: expected.append('device:' + source if source else 'default_input')
                        if expected:
                            self.assertEqual(cmd[cmd.index('-a') + 1], '|'.join(expected))
                            self.assertEqual(cmd[cmd.index('-ac') + 1], 'aac')
                        else:
                            self.assertNotIn('-a', cmd)
    def test_input_cannot_add_sources_or_options(self):
        for source in ('bad|default_output', '-option', 'bad;options', 'bad\nname'):
            with self.assertRaises(CaptureError):
                backend.audio_arguments(dict(desktop=False, microphone=True, input=source))
    def test_monitor_resolution_cap(self):
        cmd = backend.recorder_arguments(dict(desktop=False, microphone=False),
                                        dict(name='DP-1', width=5120, height=2880), 8)
        self.assertEqual(cmd[cmd.index('-s') + 1], '3840x2160')

if __name__ == '__main__': unittest.main()
