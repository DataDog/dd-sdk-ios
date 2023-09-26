# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-Present Datadog, Inc.
# -----------------------------------------------------------

from dataclasses import dataclass
from src.semver import Version


@dataclass
class Simulator:
    """
    A simulator compatible with this host. Parsed from `xcodes runtimes`:

    ...
    iOS 12.4 (Installed)
    iOS 13.0
    iOS 13.1
    iOS 13.2.2
    iOS 14.0.1 (Installed)
    iOS 15.5 (Installed)
    iOS 16.0
    iOS 16.1
    iOS 16.2
    iOS 16.4 (Installed)
    iOS 17.0 (Installed)
    ...
    """
    os_name: str  # "iOS" | "watchOS" | "tvOS" | "visionOS"
    os_version: Version  # e.g. 12.2
    is_installed: bool  # if it is already installed on this host or needs to be downloaded

    def __repr__(self):
        availability = 'installed' if self.is_installed else 'not installed'
        return f'{self.os_name} Simulator ({self.os_version}) ({availability})'

class Simulators:
    """
    Lists all 'Simulator' objects compatible with this host.
    """

    def __init__(self, xcodes_runtimes_output: str):
        """
        :param the output of `xcodes runtimes`

        Example output:
        xcodes runtimes
        -- iOS --
        iOS 12.4 (Installed)
        iOS 13.0
        iOS 13.1
        iOS 13.2.2
        iOS 14.0.1 (Installed)
        iOS 15.5 (Installed)
        iOS 16.0
        iOS 16.1 (Bundled with selected Xcode)
        iOS 16.2
        iOS 16.4 (Installed)
        iOS 17.0 (Installed)
        -- watchOS --
        watchOS 9.1
        watchOS 9.4 (Installed)
        watchOS 10.0
        -- tvOS --
        tvOS 15.4
        tvOS 16.0 (Installed)
        tvOS 16.1
        tvOS 16.4 (Installed)
        tvOS 17.0
        -- visionOS --

        Note: Bundled runtimes are indicated for the currently selected Xcode, more bundled runtimes may exist in other Xcode(s)
        """
        self.all: [Simulator] = []

        lines = xcodes_runtimes_output.split(sep='\n')

        for line in lines:
            if line.startswith('iOS') or line.startswith('watchOS') or line.startswith('tvOS') or line.startswith('visionOS'):
                components = line.split(sep=' ')
                os_name = components[0]
                os_version = Version.parse(components[1])
                is_installed = '(Installed)' in line or '(Bundled with selected Xcode)' in line
                simulator = Simulator(
                    os_name=os_name,
                    os_version=os_version,
                    is_installed=is_installed
                )

                if simulator not in self.all:
                    self.all.append(simulator)

        self.installed = list(filter(lambda s: s.is_installed, self.all))
        self.not_installed = list(filter(lambda s: not s.is_installed, self.all))

    def get_all_simulators(self, os_name: str):
        return list(filter(lambda s: s.os_name == os_name, self.all))

    def get_simulator(self, os_name: str, os_version: Version):
        for simulator in self.all:
            if simulator.os_name == os_name and simulator.os_version == os_version:
                return simulator
        return None

    def get_installed_simulators(self, os_name: str):
        return list(filter(lambda s: s.os_name == os_name, self.installed))
