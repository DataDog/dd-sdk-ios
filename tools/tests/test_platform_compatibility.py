# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-Present Datadog, Inc.
# -----------------------------------------------------------

import tempfile
import unittest
from pathlib import Path

from tools.validate_platform_compatibility import (
    parse_package_manifest,
    parse_podspec,
    parse_xcconfig,
    validate_platforms,
)


class PlatformCompatibilityTests(unittest.TestCase):
    manifest_platforms = {
        "ios": "12.0",
        "tvos": "12.0",
        "macos": "12.6",
        "watchos": "7.0",
        "visionos": "1.0",
    }

    xcconfig = {
        "IPHONEOS_DEPLOYMENT_TARGET": "12.0",
        "TVOS_DEPLOYMENT_TARGET": "12.0",
        "MACOSX_DEPLOYMENT_TARGET": "12.6",
        "WATCHOS_DEPLOYMENT_TARGET": "7.0",
        "XROS_DEPLOYMENT_TARGET": "1.0",
    }

    def test_accepts_matching_deployment_targets(self):
        errors = validate_platforms(
            self.manifest_platforms,
            self.xcconfig,
            {"DatadogRUM.podspec": {"ios": "12", "tvos": "12.0", "watchos": "7.0"}},
        )

        self.assertEqual(errors, [])

    def test_rejects_xcconfig_deployment_target_drift(self):
        xcconfig = self.xcconfig | {"WATCHOS_DEPLOYMENT_TARGET": "6.0"}

        errors = validate_platforms(self.manifest_platforms, xcconfig, {})

        self.assertIn(
            "watchos is 7.0 in Package.swift but 6.0 in WATCHOS_DEPLOYMENT_TARGET",
            errors,
        )

    def test_rejects_podspec_deployment_target_drift(self):
        errors = validate_platforms(
            self.manifest_platforms,
            self.xcconfig,
            {"DatadogRUM.podspec": {"watchos": "8.0"}},
        )

        self.assertIn(
            "watchos is 7.0 in Package.swift but 8.0 in DatadogRUM.podspec",
            errors,
        )

    def test_reads_manifest_platforms(self):
        with tempfile.TemporaryDirectory() as directory:
            manifest = Path(directory) / "Package.swift"
            manifest.write_text(
                "platforms: [.iOS(.v12), .macOS(\"12.6\"), .watchOS(.v7)]"
            )

            self.assertEqual(
                parse_package_manifest(manifest),
                {"ios": "12", "macos": "12.6", "watchos": "7"},
            )

    def test_reads_xcconfig_and_podspec_deployment_targets(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            xcconfig = root / "Base.xcconfig"
            xcconfig.write_text("WATCHOS_DEPLOYMENT_TARGET=7.0\nTVOS_DEPLOYMENT_TARGET = 12.0\n")
            podspec = root / "DatadogRUM.podspec"
            podspec.write_text(
                "  s.tvos.deployment_target = '12.0'\n"
                "  s.watchos.deployment_target = \"7.0\"\n"
            )

            self.assertEqual(
                parse_xcconfig(xcconfig),
                {"WATCHOS_DEPLOYMENT_TARGET": "7.0", "TVOS_DEPLOYMENT_TARGET": "12.0"},
            )
            self.assertEqual(parse_podspec(podspec), {"tvos": "12.0", "watchos": "7.0"})


if __name__ == "__main__":
    unittest.main()
