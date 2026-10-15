"""Negative controls for physical source/build/install identity."""
import copy
import json
from pathlib import Path
import plistlib
import tempfile
import unittest

from installed_code import inventory, read_receipt, validate


class InstalledCodeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.app = Path(self.temp.name) / "Fixture.app"
        self.app.mkdir()
        (self.app / "Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "com.example.fixture", "CFBundleExecutable": "Fixture"}))
        (self.app / "Fixture").write_bytes(bytes.fromhex("cffaedfe") + b"main")
        (self.app / "Fixture.debug.dylib").write_bytes(bytes.fromhex("cffaedfe") + b"debug" * 20000)
        (self.app / "asset").write_bytes(b"not code")
        self.run_id, self.revision, self.pid = "exp187-test", "1" * 40, 123
        self.receipt = dict(schemaVersion=1, runID=self.run_id, sourceRevision=self.revision,
                            processID=self.pid, boundary="before-sdk-initialization", **inventory(self.app))

    def check(self, receipt):
        return validate(receipt, self.app, self.run_id, self.revision, self.pid)

    def test_accepts_complete_signed_inventory(self):
        self.assertEqual(self.check(self.receipt)["state"], "PASS")
        self.assertEqual(len(self.receipt["binaries"]), 2)

    def test_rejects_stale_or_malformed_identity(self):
        for key, bad in [("runID", "exp187-old"), ("sourceRevision", "2" * 40),
                         ("processID", 124), ("processID", True),
                         ("schemaVersion", True), ("schemaVersion", 2),
                         ("boundary", "after-scenario"), ("bundleIdentifier", "com.example.wrong"),
                         ("executable", "Fixture.debug.dylib")]:
            with self.subTest(key=key, value=bad):
                receipt = copy.deepcopy(self.receipt)
                receipt[key] = bad
                with self.assertRaises(ValueError):
                    self.check(receipt)

    def test_rejects_missing_extra_or_changed_installed_code(self):
        for operation in ("missing", "extra", "changed", "empty"):
            with self.subTest(operation=operation):
                receipt = copy.deepcopy(self.receipt)
                if operation == "missing":
                    del receipt["binaries"]["Fixture.debug.dylib"]
                elif operation == "extra":
                    receipt["binaries"]["unexpected.dylib"] = "0" * 64
                elif operation == "changed":
                    receipt["binaries"]["Fixture.debug.dylib"] = "0" * 64
                else:
                    receipt["binaries"] = {}
                with self.assertRaises(ValueError):
                    self.check(receipt)

    def test_rejects_local_code_changed_after_signing_inventory(self):
        with (self.app / "Fixture.debug.dylib").open("ab") as output:
            output.write(b"mutation")
        with self.assertRaises(ValueError):
            self.check(self.receipt)

    def test_rejects_incomplete_or_extended_receipt(self):
        for operation in ("missing", "extra"):
            receipt = copy.deepcopy(self.receipt)
            if operation == "missing":
                del receipt["boundary"]
            else:
                receipt["unexpected"] = True
            with self.assertRaises(ValueError):
                self.check(receipt)

    def test_rejects_duplicate_json_keys(self):
        path = self.app.parent / "receipt.json"
        path.write_text('{"runID":"old","runID":"new"}')
        with self.assertRaisesRegex(ValueError, "duplicate"):
            read_receipt(path)

    def test_non_code_files_do_not_change_identity(self):
        (self.app / "asset").write_bytes(b"changed asset")
        self.assertEqual(self.check(self.receipt)["state"], "PASS")

    def test_rejects_missing_signed_main_executable(self):
        (self.app / "Fixture").unlink()
        with self.assertRaises(ValueError):
            self.check(self.receipt)

    def test_receipt_round_trip(self):
        path = self.app.parent / "receipt.json"
        path.write_text(json.dumps(self.receipt))
        self.assertEqual(self.check(read_receipt(path))["state"], "PASS")


if __name__ == "__main__":
    unittest.main()
