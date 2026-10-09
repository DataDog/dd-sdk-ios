"""Tests for generated Flags package identity.

Unless explicitly stated otherwise, all files in this repository are licensed under the
Apache License Version 2.0. This product includes software developed at Datadog
(https://www.datadoghq.com/). Copyright 2019-Present Datadog, Inc.
"""
from pathlib import Path
import tempfile
import unittest

from generate_flags_metadata import generate_metadata


class FlagsSDKVersionTests(unittest.TestCase):
    def test_checked_in_metadata_matches_package(self):
        generate_metadata(Path(__file__).resolve().parents[1], check=True)

    def test_version_changes_and_drift_detection(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest = root / "DatadogFlags.podspec"
            for version in ["3.18.0", "4.0.0", "4.1.0-rc.1"]:
                manifest.write_text(f'  s.version = "{version}"\n')
                with self.assertRaisesRegex(ValueError, "missing or stale"):
                    generate_metadata(root, check=True)
                output = generate_metadata(root)
                self.assertIn(f'version = "{version}"', output.read_text())
                generate_metadata(root, check=True)

    def test_invalid_or_duplicate_versions_fail(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            manifest = root / "DatadogFlags.podspec"
            for version in ["", "v3.1.0", "01.0.0", "1.0.0-01", "1.0.0-a..b"]:
                manifest.write_text(f'  s.version = "{version}"\n')
                with self.assertRaises(ValueError):
                    generate_metadata(root)
            manifest.write_text('s.version = "1.0.0"\ns.version = "2.0.0"\n')
            with self.assertRaises(ValueError):
                generate_metadata(root)
