# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-Present Datadog, Inc.
# -----------------------------------------------------------

import re
from dataclasses import dataclass
from src.semver import Version


@dataclass
class Simulator:
    """
    A simulator compatible with this host. Parsed from `xcversion simulators`:

    ...
    iOS 11.4 Simulator (not installed)
    iOS 12.0 Simulator (installed)
    watchOS 5.0 Simulator (not installed)
    tvOS 12.0 Simulator (not installed)
    ...
    """
    os_name: str  # "iOS" | "watchOS" | "tvOS"
    os_version: Version  # e.g. 12.2
    is_installed: bool  # if it is already installed on this host or needs to be downloaded

    def __repr__(self):
        availability = 'installed' if self.is_installed else 'not installed'
        return f'{self.os_name} Simulator ({self.os_version}) ({availability})'


class Simulators:
    """
    Lists all 'Simulator' objects compatible with this host.
    """

    def __init__(self, xcversion_simulators_output: str):
        """
        :param the output of `xcversion simulators`
        """
        self.all: [Simulator] = []

        lines = xcversion_simulators_output.split(sep='\n')
        os_regex = r'(iOS|watchOS|tvOS) ([0-9.]+)? Simulator \((not installed|installed)\)'

        for line in lines:
            match = re.match(os_regex, line)
            if match:
                simulator = Simulator(
                    os_name=match.groups()[0],
                    os_version=Version.parse(match.groups()[1]),
                    is_installed=match.groups()[2] == 'installed'
                )
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
