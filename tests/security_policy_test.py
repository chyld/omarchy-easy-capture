"""Repository invariants from the linked Omarchy security review skill."""
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parent.parent

class SecurityPolicyTest(unittest.TestCase):
    def test_all_qml_text_is_plain(self):
        for path in ROOT.glob('*.qml'):
            source = path.read_text()
            for match in re.finditer(r'\b(?:Text|Label|TextEdit|StyledText)\s*\{', source):
                start, depth = match.end(), 1
                end = start
                while end < len(source) and depth:
                    depth += (source[end] == '{') - (source[end] == '}')
                    end += 1
                self.assertIn('textFormat: Text.PlainText', source[start:end], str(path))
    def test_no_shell_or_whole_output_collection_in_runtime(self):
        for path in list(ROOT.glob('*.qml')) + list(ROOT.glob('*.py')):
            source = path.read_text()
            for forbidden in ('StdioCollector', 'shell=True', 'capture_output=True', 'pkill', 'killall', 'execDetached'):
                self.assertNotIn(forbidden, source, str(path))
        self.assertFalse(list(ROOT.glob('*.sh')), 'runtime shell helpers should not return')
    def test_store_description_matches_readme(self):
        manifest = json.loads((ROOT / 'manifest.json').read_text())
        self.assertEqual(manifest['description'], (ROOT / 'README.md').read_text().split('\n\n')[1])
        self.assertEqual(manifest['id'], 'chyld.easy-capture')
    def test_no_public_capture_ipc(self):
        self.assertNotIn('IpcHandler', (ROOT/'BarWidget.qml').read_text())
        self.assertNotIn('IpcHandler', (ROOT/'CaptureService.qml').read_text())
        self.assertIn('manageIpc: false', (ROOT/'CapturePanel.qml').read_text())

if __name__ == '__main__': unittest.main()
