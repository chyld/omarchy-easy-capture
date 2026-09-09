"""Run the real recording shell script with fake recorder and notification commands."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent


class AudioArgumentsTest(unittest.TestCase):
    def test_all_audio_combinations(self):
        qml = (ROOT / 'BarWidget.qml').read_text()
        source = qml.split('readonly property string recordScript: [', 1)[1].split('].join("\\n")', 1)[0]
        script = '\n'.join(json.loads('[' + source + ']'))
        subprocess.run(['bash', '-n'], input=script, text=True, check=True)
        with tempfile.TemporaryDirectory() as folder:
            temp = Path(folder)
            recorder = temp / 'gpu-screen-recorder'
            recorder.write_text('''#!/usr/bin/python3
import json, os, pathlib, sys, time
pathlib.Path(os.environ['CAPTURE_TEST_ARGS']).write_text(json.dumps(sys.argv[1:]))
pathlib.Path(sys.argv[sys.argv.index('-o') + 1]).touch()
time.sleep(0.3)
''')
            recorder.chmod(0o755)
            notify = temp / 'omarchy-notification-send'
            notify.write_text('#!/bin/sh\nexit 0\n')
            notify.chmod(0o755)
            args_file = temp / 'args.json'
            env = dict(os.environ, HOME=folder, PATH=f'{folder}:/usr/bin:/bin',
                       OMARCHY_SCREENRECORD_DIR=folder, CAPTURE_TEST_ARGS=str(args_file))
            for audio in ('', 'default_output', 'default_input', 'default_output|default_input', 'device:alsa_input.usb-headset', 'default_output|device:alsa_input.usb-headset'):
                with self.subTest(audio=audio):
                    result = subprocess.run(['bash', '-c', script, 'bash', 'rect', '640x480+0+0', audio],
                                            env=env, capture_output=True, text=True, timeout=4)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertIn('STARTED', result.stdout)
                    args = json.loads(args_file.read_text())
                    self.assertEqual(args[args.index('-w') + 1], '640x480+0+0')
                    if audio:
                        self.assertEqual(args[args.index('-a') + 1], audio)
                        self.assertEqual(args[args.index('-ac') + 1], 'aac')
                        self.assertEqual(args.count('-a'), 1)
                    else:
                        self.assertNotIn('-a', args)
                        self.assertNotIn('-ac', args)


if __name__ == '__main__':
    unittest.main()
