# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-Present Datadog, Inc.
# -----------------------------------------------------------

from src.semver import Version
from src.simulators_parser import Simulators, Simulator


mock_xcodes_runtimes_output = """
-- iOS --
iOS 13.2.2
iOS 14.0.1 (Installed)
iOS 16.1 (Bundled with selected Xcode)
iOS 16.4 (Installed)
iOS 17.0 (Installed)
-- watchOS --
watchOS 6.0
watchOS 6.1.1
watchOS 7.0
watchOS 9.4 (Installed)
watchOS 10.0
-- tvOS --
tvOS 12.4
tvOS 16.0 (Installed)
tvOS 16.1
tvOS 16.4 (Installed)
tvOS 17.0
-- visionOS --
visionOS 1.0

Note: Bundled runtimes are indicated for the currently selected Xcode, more bundled runtimes may exist in other Xcode(s)
"""

def test_get_all_simulators():
    simulators = Simulators(mock_xcodes_runtimes_output)

    assert simulators.get_all_simulators(os_name='iOS') == [
        Simulator(os_name='iOS', os_version=Version.parse('13.2.2'), is_installed=False),
        Simulator(os_name='iOS', os_version=Version.parse('14.0.1'), is_installed=True),
        Simulator(os_name='iOS', os_version=Version.parse('16.1'), is_installed=True),
        Simulator(os_name='iOS', os_version=Version.parse('16.4'), is_installed=True),
        Simulator(os_name='iOS', os_version=Version.parse('17.0'), is_installed=True),
    ]
    assert simulators.get_all_simulators(os_name='tvOS') == [
        Simulator(os_name='tvOS', os_version=Version.parse('12.4'), is_installed=False),
        Simulator(os_name='tvOS', os_version=Version.parse('16.0'), is_installed=True),
        Simulator(os_name='tvOS', os_version=Version.parse('16.1'), is_installed=False),
        Simulator(os_name='tvOS', os_version=Version.parse('16.4'), is_installed=True),
        Simulator(os_name='tvOS', os_version=Version.parse('17.0'), is_installed=False),
    ]
    assert simulators.get_all_simulators(os_name='watchOS') == [
        Simulator(os_name='watchOS', os_version=Version.parse('6.0'), is_installed=False),
        Simulator(os_name='watchOS', os_version=Version.parse('6.1.1'), is_installed=False),
        Simulator(os_name='watchOS', os_version=Version.parse('7.0'), is_installed=False),
        Simulator(os_name='watchOS', os_version=Version.parse('9.4'), is_installed=True),
        Simulator(os_name='watchOS', os_version=Version.parse('10.0'), is_installed=False),
    ]
    assert simulators.get_all_simulators(os_name='visionOS') == [
        Simulator(os_name='visionOS', os_version=Version.parse('1.0'), is_installed=False),
    ]


def test_get_simulator():
    simulators = Simulators(mock_xcodes_runtimes_output)

    assert simulators.get_simulator(os_name='tvOS', os_version=Version.parse('12.4')) == \
        Simulator(os_name='tvOS', os_version=Version.parse('12.4'), is_installed=False)
    assert simulators.get_simulator(os_name='tvOS', os_version=Version.parse('10.0')) == None


def test_get_installed_simulators():
    simulators = Simulators(mock_xcodes_runtimes_output)

    assert simulators.get_installed_simulators(os_name='iOS') == [
        Simulator(os_name='iOS', os_version=Version.parse('14.0.1'), is_installed=True),
        Simulator(os_name='iOS', os_version=Version.parse('16.1'), is_installed=True),
        Simulator(os_name='iOS', os_version=Version.parse('16.4'), is_installed=True),
        Simulator(os_name='iOS', os_version=Version.parse('17.0'), is_installed=True),
    ]


def test_skipping_duplicates():
    duplicated_output = mock_xcodes_runtimes_output + '\n' + mock_xcodes_runtimes_output
    simulators = Simulators(duplicated_output)

    assert simulators.get_all_simulators(os_name='iOS') == [
        Simulator(os_name='iOS', os_version=Version.parse('13.2.2'), is_installed=False),
        Simulator(os_name='iOS', os_version=Version.parse('14.0.1'), is_installed=True),
        Simulator(os_name='iOS', os_version=Version.parse('16.1'), is_installed=True),
        Simulator(os_name='iOS', os_version=Version.parse('16.4'), is_installed=True),
        Simulator(os_name='iOS', os_version=Version.parse('17.0'), is_installed=True),
    ]