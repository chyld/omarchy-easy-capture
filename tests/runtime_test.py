import json
import os
import signal
import sys
import tempfile
import time
from pathlib import Path
import unittest
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from capture_runtime import Runner, CaptureError, CaptureFile, open_directory, read_config, environment
import capture_backend as backend

PYTHON = ['/usr/bin/python3', '-I', '-S', '-B', '-c']

class RuntimeTest(unittest.TestCase):
    def test_oversized_output_is_stopped_before_collection(self):
        runner = Runner()
        with self.assertRaisesRegex(CaptureError, 'output exceeded'):
            runner.run(PYTHON + ["import os; os.write(1,b'x'*1000000)"], limit=1024, timeout=2)
        self.assertEqual(runner.children, [])
    def test_deadline(self):
        start = time.monotonic()
        runner = Runner()
        with self.assertRaisesRegex(CaptureError, 'timed out'):
            runner.run(PYTHON + ['import time; time.sleep(20)'], timeout=0.1)
        self.assertLess(time.monotonic() - start, 2)
        self.assertEqual(runner.children, [])
    def test_group_cleanup_when_leader_exits_first(self):
        with tempfile.TemporaryDirectory() as folder:
            marker = Path(folder) / 'pid'
            code = """import os,signal,time,sys
pid=os.fork()
if pid:
    open(sys.argv[1],'w').write(str(pid))
    os._exit(0)
signal.signal(signal.SIGTERM,signal.SIG_IGN)
time.sleep(20)
"""
            runner = Runner()
            with self.assertRaises(CaptureError):
                runner.run(PYTHON + [code, str(marker)], timeout=0.3)
            pid = int(marker.read_text())
            for _ in range(50):
                try:
                    state = Path(f'/proc/{pid}/stat').read_text().rsplit(')', 1)[1].split()[0]
                    if state == 'Z': break
                except FileNotFoundError:
                    break
                time.sleep(0.01)
            else:
                os.kill(pid, signal.SIGKILL)
                self.fail('owned descendant survived group cleanup')
    def test_signals_do_not_reach_unrelated_child(self):
        runner = Runner()
        first = runner.start(PYTHON + ['import time; time.sleep(20)'])
        second = runner.start(PYTHON + ['import time; time.sleep(20)'])
        try:
            runner.release(first)
            self.assertFalse(second.exited())
        finally: runner.close()
    def test_hostile_environment_is_not_forwarded(self):
        with patch.dict(os.environ, {'PATH': '/untrusted', 'BASH_ENV': '/evil', 'LD_PRELOAD': '/evil',
                                    'PYTHONPATH': '/evil', 'HTTP_PROXY': 'http://evil'}):
            env = environment()
        self.assertEqual(env['PATH'], '/usr/bin:/bin')
        for key in ('BASH_ENV', 'LD_PRELOAD', 'PYTHONPATH', 'HTTP_PROXY'): self.assertNotIn(key, env)
    def test_json_bounds(self):
        for raw in (b'['*17+b']'*17, b'NaN', b'"'+b'x'*16385+b'"', b'0'*1048577):
            with self.assertRaises((CaptureError, ValueError)): backend.document(raw)
    def test_request_schema_rejects_audio_for_screenshot(self):
        data = dict(action='screenshot', target='region', monitor='', desktop=True, microphone=False, input='')
        with self.assertRaises(CaptureError): backend.request(json.dumps(data).encode())
    def test_microphones_filter_monitors_and_sanitize_labels(self):
        class Runner:
            def run(self, *args, **kwargs):
                return 0, json.dumps([{'name':'usb','description':'<img>&Headset\u202e'},
                                     {'name':'out.monitor'}, {'name':'other','monitor_source':'out'}]).encode()
        self.assertEqual(backend.microphones(Runner()), [{'name':'usb','label':'imgHeadset'}])

class CaptureFileTest(unittest.TestCase):
    def test_private_publish_and_no_clobber(self):
        with tempfile.TemporaryDirectory() as folder:
            output = CaptureFile(folder, 'screenshot')
            try:
                os.write(output.fd, b'private image')
                self.assertEqual(os.listdir(folder), [])
                name = output.publish()
                self.assertEqual((Path(folder)/name).read_bytes(), b'private image')
                self.assertEqual(os.stat(Path(folder)/name).st_mode & 0o777, 0o600)
            finally: output.close()
    def test_existing_symlink_is_not_followed(self):
        with tempfile.TemporaryDirectory() as folder, patch('capture_runtime.time.strftime', return_value='fixed'), patch('capture_runtime.secrets.token_hex', return_value='abcd1234'):
            victim = Path(folder)/'victim'; victim.write_text('must survive')
            (Path(folder)/'screenshot-fixed-abcd1234.png').symlink_to(victim)
            output = CaptureFile(folder, 'screenshot')
            try:
                os.write(output.fd, b'capture')
                with self.assertRaises(CaptureError): output.publish()
                self.assertEqual(victim.read_text(), 'must survive')
            finally: output.close()
    def test_parent_symlink_is_refused(self):
        with tempfile.TemporaryDirectory() as folder:
            (Path(folder)/'link').symlink_to(folder)
            with self.assertRaises(OSError): open_directory(folder+'/link')
    def test_fifo_and_symlink_configuration_do_not_block(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)/'user-dirs.dirs'
            os.mkfifo(path)
            env = {'HOME': folder, 'XDG_CONFIG_HOME': folder}
            with self.assertRaises(CaptureError): read_config(env)
            path.unlink(); path.symlink_to('/dev/null')
            with self.assertRaises(OSError): read_config(env)
    def test_config_is_data_not_shell(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)/'user-dirs.dirs'
            path.write_text('XDG_PICTURES_DIR="$HOME/Pictures"\n')
            env = {'HOME': folder, 'XDG_CONFIG_HOME': folder}
            self.assertEqual(read_config(env)['XDG_PICTURES_DIR'], folder+'/Pictures')
            path.write_text('XDG_PICTURES_DIR="$(touch victim)"\n')
            with self.assertRaises(CaptureError): read_config(env)
            self.assertFalse((Path(folder)/'victim').exists())

if __name__ == '__main__': unittest.main()
