"""Source preparation must not become a compiler or native qualification receipt."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


class DisplayFixtureReceiptTests(unittest.TestCase):
    def test_cli_prepares_only_source_and_refuses_to_reuse_output(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve() / 'fixture'
            helper = Path(__file__).with_name('scene_background_display_fixture.py')
            command = [sys.executable, '-B', str(helper), '--destination', str(root)]
            result = subprocess.run(command, capture_output=True, text=True, timeout=30, check=True)
            summary = json.loads(result.stdout)
            self.assertFalse(summary['compiler_qualified']); self.assertFalse(summary['native_admitted'])
            self.assertEqual(summary['native_runs'], 0)
            raw = (root / 'source.json').read_bytes(); receipt = json.loads(raw)
            self.assertIn('not compiled', receipt['scope']); self.assertEqual(receipt['gates_closed'], [])
            self.assertEqual(set(receipt['original']), set(receipt['rendered']))
            again = subprocess.run(command, capture_output=True, text=True, timeout=30)
            self.assertNotEqual(again.returncode, 0)
            self.assertEqual((root / 'source.json').read_bytes(), raw)


if __name__ == '__main__':
    unittest.main()
