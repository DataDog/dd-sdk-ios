#!/usr/bin/python3

# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-Present Datadog, Inc.
# -----------------------------------------------------------

# Usage:
# $ ./tools/utils/find-simulator.py --platform "iOS Simulator" --os "26.5" --device "iPhone 17 Pro"
#
# Prints the UDID of the simulator that matches an xcodebuild destination. OS 'latest' picks the newest runtime of
# the platform. Exits with status 1 and prints nothing when no available simulator matches.

import argparse
import json
import subprocess
import sys

# `simctl` names the visionOS runtimes 'xrOS'.
SIMCTL_PLATFORM_NAMES = {"visionOS": "xrOS"}


def version_components(version):
    """
    Returns a version string, e.g. '26.0.1', as a list of numbers that sorts in version order.
    """
    return [int(component) for component in version.split(".")]


def matches_os(runtime, os_version):
    """
    Returns whether the runtime has the requested OS version. '26.0' matches both '26.0' and '26.0.1'.
    """
    return os_version == "latest" or runtime["version"] == os_version or runtime["version"].startswith(os_version + ".")


def find_simulator_udid(simulators, platform, os_version, device):
    """
    Returns the UDID of the first available `device` simulator on the newest matching runtime, or `None`.
    """
    simctl_platform = SIMCTL_PLATFORM_NAMES.get(platform, platform)
    runtimes = [
        runtime for runtime in simulators["runtimes"]
        if runtime.get("isAvailable") and runtime.get("platform") == simctl_platform and matches_os(runtime, os_version)
    ]
    runtimes.sort(key=lambda runtime: version_components(runtime["version"]), reverse=True)

    for runtime in runtimes:
        for simulator in simulators["devices"].get(runtime["identifier"], []):
            if simulator.get("isAvailable") and simulator["name"] == device:
                return simulator["udid"]
    return None


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Prints the UDID of the simulator that matches an xcodebuild destination.")
    parser.add_argument("--platform", required=True, help="xcodebuild destination platform, e.g. 'iOS Simulator'")
    parser.add_argument("--os", required=True, help="OS version, e.g. '26.5', or 'latest'")
    parser.add_argument("--device", required=True, help="Simulator name, e.g. 'iPhone 17 Pro'")
    args = parser.parse_args()

    simctl_output = subprocess.run(["xcrun", "simctl", "list", "-j"], capture_output=True, text=True, check=True).stdout
    platform = args.platform.removesuffix(" Simulator")
    udid = find_simulator_udid(json.loads(simctl_output), platform, args.os, args.device)

    if udid is None:
        sys.exit(1)
    print(udid)
