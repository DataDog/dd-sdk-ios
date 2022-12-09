# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-Present Datadog, Inc.
# -----------------------------------------------------------

import json as j
from dataclasses import dataclass
from src.semver import Version
from src.runtimes_parser import Runtimes, Runtime


@dataclass
class Device:
    """
    A device available on this host. Parsed from `xcrun simctl list devices`:

    == Devices ==
    -- iOS 13.0 --
    iPhone 8 (3EBBFEB1-5264-449E-A858-FCF68C095FE3) (Shutdown)
    iPhone 8 Plus (DF44EB3D-8509-417D-8AD3-6722870E0ED7) (Shutdown)
    iPhone 11 (C9BF0737-6936-4D09-92FC-8673070400C8) (Shutdown)
    iPhone 11 Pro (9408469A-E702-4750-AD63-A4B6320149C5) (Shutdown)
    ...
    """
    is_available: bool  # device may not be available (e.g. devices with iOS 11.0 runtime on macOS 10.15.99 host)
    name: str  # e.g. "iPhone 8", "iPhone 8 Plus", ...
    runtime: Runtime  # runtime for this device
    availability_comment: str  # unavailability reason or empty string '' (if device is available)

    def __repr__(self):
        availability = 'available' if self.is_available else 'unavailable'
        return f'{self.name} - {availability} [runtime: {self.runtime}]'


class Devices:
    """
    Lists all 'Device' objects installed on the host.
    """

    def __init__(self, runtimes: Runtimes, xcrun_simctl_list_devices_json_output: str):
        """
        :param runtimes: the list of Runtimes parsed from `xcrun simctl list runtime`
        :param json_string: the JSON output of `xcrun simctl list devices --json`
        """
        self.all: [Device] = []

        json = j.loads(xcrun_simctl_list_devices_json_output)

        for runtime_identifier in json['devices'].keys():
            runtime = runtimes.get_runtime(identifier=runtime_identifier)

            if runtime:
                runtime_devices = json['devices'][runtime_identifier]
                for device_json in runtime_devices:
                    device = Device(
                        is_available=device_json['isAvailable'],
                        name=device_json['name'],
                        runtime=runtimes.get_runtime(identifier=runtime_identifier),
                        availability_comment=device_json.get('availabilityError') or ''
                    )
                    self.all.append(device)
            else:
                print(f'⚠️ Cannot find runtime with identifier: {runtime_identifier}')

        self.available = list(filter(lambda d: d.is_available, self.all))
        self.unavailable = list(filter(lambda d: not d.is_available, self.all))

    def get_available_devices(self, os_name: str, os_version: Version):
        result: [Device] = []

        # Try to get devices matching the full os_version (major.minor.patch):
        for device in self.all:
            if device.runtime.os_name == os_name and device.runtime.os_version == os_version:
                if device.is_available and device.runtime.is_available:
                    result.append(device)

        # If no device was found for the full os_version, check only `major` and `minor` components
        if len(result) == 0:
            for device in self.all:
                os_name_match = device.runtime.os_name == os_name
                os_version_major_match = device.runtime.os_version.major == os_version.major
                os_version_minor_match = device.runtime.os_version.minor == os_version.minor
                is_available = device.is_available and device.runtime.is_available

                if os_name_match and os_version_major_match and os_version_minor_match and is_available:
                    result.append(device)

        return result
