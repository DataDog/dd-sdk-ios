#!/usr/bin/env python3

# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-Present Datadog, Inc.
# -----------------------------------------------------------

import re
import sys
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
PACKAGE_MANIFEST = REPOSITORY_ROOT / "Package.swift"
BASE_XCCONFIG = REPOSITORY_ROOT / "xcconfigs" / "Base.xcconfig"

PLATFORM_XCCONFIG_KEYS = {
    "ios": "IPHONEOS_DEPLOYMENT_TARGET",
    "tvos": "TVOS_DEPLOYMENT_TARGET",
    "macos": "MACOSX_DEPLOYMENT_TARGET",
    "watchos": "WATCHOS_DEPLOYMENT_TARGET",
    "visionos": "XROS_DEPLOYMENT_TARGET",
}

PODSPEC_PLATFORM_NAMES = {
    "ios": "ios",
    "tvos": "tvos",
    "osx": "macos",
    "watchos": "watchos",
    "visionos": "visionos",
}


def parse_package_manifest(path: Path) -> dict[str, str]:
    platforms = {}
    declaration = re.compile(
        r"\.(iOS|tvOS|macOS|watchOS|visionOS)\(\s*(?:\.v([0-9_]+)|\"([0-9.]+)\")\s*\)"
    )
    for match in declaration.finditer(path.read_text()):
        version = match.group(2).replace("_", ".") if match.group(2) else match.group(3)
        platforms[match.group(1).lower()] = version
    return platforms


def parse_xcconfig(path: Path) -> dict[str, str]:
    settings = {}
    assignment = re.compile(r"^\s*([A-Z0-9_]+)\s*=\s*([^\s/]+)\s*$")
    for line in path.read_text().splitlines():
        match = assignment.match(line)
        if match:
            settings[match.group(1)] = match.group(2)
    return settings


def parse_podspec(path: Path) -> dict[str, str]:
    platforms = {}
    deployment_target = re.compile(
        r"^\s*s\.(ios|tvos|osx|watchos|visionos)\.deployment_target\s*=\s*['\"]([^'\"]+)['\"]"
    )
    for line in path.read_text().splitlines():
        match = deployment_target.match(line)
        if match:
            platforms[PODSPEC_PLATFORM_NAMES[match.group(1)]] = match.group(2)
    return platforms


def normalized_version(version: str) -> tuple[int, ...]:
    components = [int(component) for component in version.split(".")]
    while components and components[-1] == 0:
        components.pop()
    return tuple(components)


def validate_platforms(
    manifest_platforms: dict[str, str],
    xcconfig: dict[str, str],
    podspec_platforms: dict[str, dict[str, str]],
) -> list[str]:
    errors = []

    for platform, setting in PLATFORM_XCCONFIG_KEYS.items():
        manifest_version = manifest_platforms.get(platform)
        xcconfig_version = xcconfig.get(setting)
        if manifest_version is None:
            errors.append(f"Package.swift does not declare {platform}")
        elif xcconfig_version is None:
            errors.append(f"xcconfigs/Base.xcconfig does not declare {setting}")
        elif normalized_version(manifest_version) != normalized_version(xcconfig_version):
            errors.append(
                f"{platform} is {manifest_version} in Package.swift but "
                f"{xcconfig_version} in {setting}"
            )

    for podspec, platforms in podspec_platforms.items():
        for platform, podspec_version in platforms.items():
            manifest_version = manifest_platforms.get(platform)
            if manifest_version is None:
                errors.append(f"{podspec} declares unsupported platform {platform}")
            elif normalized_version(manifest_version) != normalized_version(podspec_version):
                errors.append(
                    f"{platform} is {manifest_version} in Package.swift but "
                    f"{podspec_version} in {podspec}"
                )

    return errors


def main() -> None:
    manifest_platforms = parse_package_manifest(PACKAGE_MANIFEST)
    xcconfig = parse_xcconfig(BASE_XCCONFIG)
    podspec_platforms = {
        podspec.name: parse_podspec(podspec)
        for podspec in sorted(REPOSITORY_ROOT.glob("*.podspec"))
    }
    errors = validate_platforms(manifest_platforms, xcconfig, podspec_platforms)

    if errors:
        print("Platform compatibility validation failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        raise SystemExit(1)

    platforms = ", ".join(
        f"{platform} {version}" for platform, version in manifest_platforms.items()
    )
    print(f"Platform compatibility validated: {platforms}")
    print("All xcconfig and podspec deployment targets match Package.swift.")


if __name__ == "__main__":
    main()
