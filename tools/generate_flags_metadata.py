"""Generate Flags request identity from the Flags podspec.

Unless explicitly stated otherwise, all files in this repository are licensed under the
Apache License Version 2.0. This product includes software developed at Datadog
(https://www.datadoghq.com/). Copyright 2019-Present Datadog, Inc.
"""
import argparse
from pathlib import Path
import re


def generate_metadata(root: Path, check: bool = False) -> Path:
    versions = re.findall(r'^\s*s\.version\s*=\s*"([^"]+)"\s*$', (root / "DatadogFlags.podspec").read_text(), re.MULTILINE)
    number = r"(?:0|[1-9][0-9]*)"
    prerelease = rf"(?:{number}|[0-9]*[A-Za-z-][0-9A-Za-z-]*)"
    semver = rf"{number}\.{number}\.{number}(?:-{prerelease}(?:\.{prerelease})*)?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?"
    if len(versions) != 1 or not re.fullmatch(semver, versions[0]):
        raise ValueError("DatadogFlags.podspec must contain one valid package version.")
    expected = f'''/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

// Generated from DatadogFlags.podspec. Do not edit.
internal enum FlagsSDKMetadata {{
    internal static let name = "dd-sdk-ios"
    internal static let version = "{versions[0]}"
}}
'''
    output = root / "DatadogFlags/Sources/Client/FlagsSDKMetadata.swift"
    if check:
        if not output.is_file() or output.read_text() != expected:
            raise ValueError("Flags SDK metadata is missing or stale. Run tools/generate_flags_metadata.py.")
    else:
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(expected)
    return output


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    generate_metadata(args.root, args.check)
