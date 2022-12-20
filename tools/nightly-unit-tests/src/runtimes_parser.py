# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-Present Datadog, Inc.
# -----------------------------------------------------------

import re
import json as j
from dataclasses import dataclass
from src.semver import Version


@dataclass
class Runtime:
    """
    A simulator runtime installed on this host. Parsed from `xcrun simctl list runtimes`:

    == Runtimes ==
    iOS 11.0 (11.0.1 - 15A8401) - com.apple.CoreSimulator.SimRuntime.iOS-11-0 (unavailable, ...)
    iOS 11.1 (11.1 - 15B87) - com.apple.CoreSimulator.SimRuntime.iOS-11-1 (unavailable, ...)
    iOS 12.1 (12.1 - 16B91) - com.apple.CoreSimulator.SimRuntime.iOS-12-1
    ...
    """
    is_available: bool  # although installed, runtimes may not be available (e.g. iOS 11.0 after macOS 10.15.99)
    identifier: str  # e.g. "com.apple.CoreSimulator.SimRuntime.iOS-13-3"
    os_name: str  # "iOS" | "watchOS" | "tvOS"
    os_version: Version  # e.g. 12.2
    build_version: str  # e.g. "15A8401", "15B87", ...
    availability_comment: str  # unavailability reason or empty string '' (if runtime is available)

    def __repr__(self):
        availability = 'available' if self.is_available else 'unavailable'
        return f'{self.os_name} {self.os_version} ({self.build_version}) - {availability}'


class Runtimes:
    """
    Lists all 'Runtime' objects installed on the host.
    """

    def __init__(self, xcrun_simctl_list_runtimes_json_output: str):
        """
        :param json_string: the JSON output of `xcrun simctl list runtimes --json`
        """
        self.all: [Runtime] = []

        json = j.loads(xcrun_simctl_list_runtimes_json_output)
        os_regex = r'(iOS|watchOS|tvOS) .*'

        for runtime_json in json['runtimes']:
            os_match = re.match(os_regex, runtime_json['name'])
            runtime = Runtime(
                is_available=runtime_json['isAvailable'],
                identifier=runtime_json['identifier'],
                os_name=os_match.groups()[0],
                os_version=Version.parse(runtime_json['version']),
                build_version=runtime_json['buildversion'],
                availability_comment=runtime_json.get('availabilityError') or ''
            )
            self.all.append(runtime)

        self.available = list(filter(lambda r: r.is_available, self.all))
        self.unavailable = list(filter(lambda r: not r.is_available, self.all))

    def get_runtime(self, identifier: str):
        for runtime in self.all:
            if runtime.identifier == identifier:
                return runtime
        return None
