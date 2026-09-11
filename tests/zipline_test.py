"""Zipline share settings, multipart upload, and request-schema coverage."""
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from capture_runtime import (CaptureError, validate_zipline, read_zipline_config,
                             write_zipline_config, plugin_config_directory)
import capture_backend as backend


def env_for(folder):
    return {'HOME': folder, 'XDG_CONFIG_HOME': folder}


class ZiplineConfigTest(unittest.TestCase):
    def test_round_trip_is_private_0600(self):
        with tempfile.TemporaryDirectory() as folder:
            env = env_for(folder)
            self.assertIsNone(read_zipline_config(env))
            write_zipline_config(env, 'https://zipline.example.com', 'secret-token')
            self.assertEqual(read_zipline_config(env), ('https://zipline.example.com', 'secret-token'))
            path = Path(plugin_config_directory(env)) / 'zipline.json'
            self.assertEqual(os.stat(path).st_mode & 0o777, 0o600)
            self.assertEqual(os.stat(path.parent).st_mode & 0o777, 0o700)
    def test_rewrite_replaces_existing(self):
        with tempfile.TemporaryDirectory() as folder:
            env = env_for(folder)
            write_zipline_config(env, 'https://one.example', 'a')
            write_zipline_config(env, 'https://two.example', 'b')
            self.assertEqual(read_zipline_config(env), ('https://two.example', 'b'))
    def test_validation_rejects_insecure_and_control(self):
        for server, token in [('http://zipline.example', 'x'), ('https://x', ''), ('https://x', 'x' * 4097),
                              ('https://x', 'bad\x00token'), ('ftp://x', 'x')]:
            with self.assertRaises(CaptureError): validate_zipline(server, token)
    def test_hostile_file_is_refused(self):
        with tempfile.TemporaryDirectory() as folder:
            env = env_for(folder)
            directory = Path(plugin_config_directory(env))
            directory.mkdir(parents=True)
            (directory / 'zipline.json').write_text('{"server":"http://evil","token":"x"}')
            with self.assertRaises(CaptureError): read_zipline_config(env)
    def test_symlink_file_is_not_followed(self):
        with tempfile.TemporaryDirectory() as folder:
            env = env_for(folder)
            directory = Path(plugin_config_directory(env))
            directory.mkdir(parents=True)
            victim = Path(folder) / 'victim'
            victim.write_text('must survive')
            (directory / 'zipline.json').symlink_to(victim)
            with self.assertRaises(OSError): read_zipline_config(env)
            self.assertEqual(victim.read_text(), 'must survive')


class ShareBodyTest(unittest.TestCase):
    def test_multipart_shape(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'image'
            path.write_bytes(b'\x89PNG body')
            fd = os.open(path, os.O_RDONLY)
            try:
                boundary, body = backend.share_body('screenshot-2026-01-01_00-00-00-abcdef1234567890.png', fd)
            finally:
                os.close(fd)
            self.assertTrue(body.startswith(('--' + boundary + '\r\n').encode()))
            self.assertIn(b'name="files"', body)
            self.assertIn(b'filename="screenshot-2026-01-01_00-00-00-abcdef1234567890.png"', body)
            self.assertIn(b'Content-Type: image/png', body)
            self.assertTrue(body.endswith(('--' + boundary + '--\r\n').encode()))
            self.assertIn(b'\x89PNG body', body)


class UploadTest(unittest.TestCase):
    class Response:
        def __init__(self, status, raw):
            self.status = status
            self._raw = raw
        def read(self, _limit):
            return self._raw

    class Connection:
        calls = {}
        def __init__(self, host, timeout=None, *, status=200, raw=b''):
            self.status = status
            self.raw = raw
            self.calls = type(self).calls
        def putrequest(self, method, path, skip_accept_encoding=False): self.calls['path'] = path
        def putheader(self, key, value): self.calls.setdefault('headers', {})[key] = value
        def endheaders(self): pass
        def send(self, body): self.calls['size'] = len(body)
        def getresponse(self): return UploadTest.Response(self.status, self.raw)
        def close(self): pass

    def _run(self, folder, raw, status, name='screenshot-2026-01-01_00-00-00-abcdef1234567890.png'):
        env = env_for(folder)
        write_zipline_config(env, 'https://zipline.example', 'token-123')
        head = Path(folder) / name
        head.write_bytes(b'pngdata')
        fd = os.open(head, os.O_RDONLY)
        output = type('O', (), {'name': name, 'fd': fd})()
        self.Connection.calls = {}
        handler = lambda host, timeout=None: self.Connection(host, timeout, status=status, raw=raw)
        try:
            with patch.object(backend.http.client, 'HTTPSConnection', handler):
                return backend.upload_zipline(None, env, output)
        finally:
            os.close(fd)

    def test_success_returns_url_and_auth_header(self):
        with tempfile.TemporaryDirectory() as folder:
            url = self._run(folder, b'{"files":[{"id":"1","name":"x.png","type":"image/png","url":"https://zipline.example/r/abc"}]}', 200)
            self.assertEqual(url, 'https://zipline.example/r/abc')
            self.assertEqual(self.Connection.calls['path'], '/api/upload')
            self.assertEqual(self.Connection.calls['headers']['Authorization'], 'token-123')
    def test_missing_config_is_refused(self):
        with tempfile.TemporaryDirectory() as folder:
            env = env_for(folder)
            head = Path(folder) / 'screenshot-2026-01-01_00-00-00-abcdef1234567890.png'
            head.write_bytes(b'x')
            fd = os.open(head, os.O_RDONLY)
            try:
                with self.assertRaises(CaptureError): backend.upload_zipline(None, env, type('O', (), {'name': head.name, 'fd': fd})())
            finally:
                os.close(fd)
    def test_http_error_and_bad_body_are_refused(self):
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaises(CaptureError): self._run(folder, b'{}', 400)
            with self.assertRaises(CaptureError): self._run(folder, b'{"files":[]}', 200)
            with self.assertRaises(CaptureError): self._run(folder, b'{"files":[{"url":"http://evil"}]}', 200)


class RequestSchemaTest(unittest.TestCase):
    def test_share_requires_screenshot(self):
        record = dict(action='record', target='region', monitor='', desktop=False, microphone=False, input='', share=True)
        with self.assertRaises(CaptureError): backend.request(json.dumps(record).encode())
    def test_share_accepted_for_screenshot(self):
        shot = dict(action='screenshot', target='region', monitor='', desktop=False, microphone=False, input='', share=True)
        self.assertTrue(backend.request(json.dumps(shot).encode())['share'])
    def test_share_must_be_bool(self):
        shot = dict(action='screenshot', target='region', monitor='', desktop=False, microphone=False, input='', share='yes')
        with self.assertRaises(CaptureError): backend.request(json.dumps(shot).encode())


class ScreenshotShareFlowTest(unittest.TestCase):
    class Child:
        def exited(self): return True
    class Runner:
        def __init__(self): self.started = []; self.env = {}
        def check(self): pass
        def run(self, argv, **kwargs): return (0, b'')
        def start(self, argv, **kwargs): self.started.append(argv); return ScreenshotShareFlowTest.Child()
        def release(self, child): return 0

    HEADER = (b'\x89PNG\r\n\x1a\n' + b'\x00\x00\x00\rIHDR' + (4).to_bytes(4, 'big') + (4).to_bytes(4, 'big'))

    def _screenshot(self, share, upload):
        from contextlib import redirect_stdout
        import io
        from capture_runtime import CaptureFile
        with tempfile.TemporaryDirectory() as folder:
            output = CaptureFile(folder, 'screenshot')
            os.write(output.fd, self.HEADER)
            runner = self.Runner()
            events = io.StringIO()
            try:
                with patch.object(backend, 'upload_zipline', upload), redirect_stdout(events):
                    backend.screenshot(runner, {'share': share}, {'name': 'DP-1'}, None, output)
            finally:
                output.close()
            kinds = [json.loads(line)['event'] for line in events.getvalue().splitlines() if line]
            return runner, kinds

    def test_share_uploads_and_holds_url(self):
        calls = {}
        def upload(r, env, output):
            calls['uploaded'] = True
            return 'https://zipline.example/u/abc.png'
        runner, kinds = self._screenshot(True, upload)
        self.assertIn('shared', kinds)
        self.assertTrue(calls.get('uploaded'))
        self.assertNotIn('share_error', kinds)
        self.assertTrue(any(argv[0] == '/usr/bin/wl-copy' and 'text/plain' in argv for argv in runner.started),
                        'expected a text clipboard provider')
    def test_share_failure_falls_back_to_image_clipboard(self):
        def upload(r, env, output): raise CaptureError('Share server refused the upload')
        runner, kinds = self._screenshot(True, upload)
        self.assertIn('share_error', kinds)
        self.assertNotIn('shared', kinds)
        self.assertTrue(any(argv[0] == '/usr/bin/wl-copy' and 'image/png' in argv for argv in runner.started),
                        'expected the image clipboard fallback')
    def test_plain_screenshot_never_uploads(self):
        def upload(r, env, output): raise AssertionError('upload must not run')
        runner, kinds = self._screenshot(False, upload)
        self.assertNotIn('shared', kinds)
        self.assertTrue(any(argv[0] == '/usr/bin/wl-copy' and 'image/png' in argv for argv in runner.started))


if __name__ == '__main__': unittest.main()
