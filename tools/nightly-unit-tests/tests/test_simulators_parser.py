# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-Present Datadog, Inc.
# -----------------------------------------------------------

from src.semver import Version
from src.simulators_parser import Simulators, Simulator


mock_xcversion_simulators_output = """
iOS 12.4 Simulator (installed)
iOS 13.0 Simulator (not installed)
watchOS 7.1 Simulator (installed)
tvOS 13.3 Simulator (not installed)
iOS 14.2 Simulator (not installed)
iOS 15.0 Simulator (installed)
watchOS 8.3 Simulator (not installed)
"""


def test_get_all_simulators():
    simulators = Simulators(mock_xcversion_simulators_output)

    assert simulators.get_all_simulators(os_name='iOS') == [
        Simulator(os_name='iOS', os_version=Version.parse('12.4'), is_installed=True),
        Simulator(os_name='iOS', os_version=Version.parse('13.0'), is_installed=False),
        Simulator(os_name='iOS', os_version=Version.parse('14.2'), is_installed=False),
        Simulator(os_name='iOS', os_version=Version.parse('15.0'), is_installed=True),
    ]
    assert simulators.get_all_simulators(os_name='tvOS') == [
        Simulator(os_name='tvOS', os_version=Version.parse('13.3'), is_installed=False),
    ]
    assert simulators.get_all_simulators(os_name='watchOS') == [
        Simulator(os_name='watchOS', os_version=Version.parse('7.1'), is_installed=True),
        Simulator(os_name='watchOS', os_version=Version.parse('8.3'), is_installed=False),
    ]


def test_get_simulator():
    simulators = Simulators(mock_xcversion_simulators_output)

    assert simulators.get_simulator(os_name='tvOS', os_version=Version.parse('13.3')) == \
        Simulator(os_name='tvOS', os_version=Version.parse('13.3'), is_installed=False)
    assert simulators.get_simulator(os_name='tvOS', os_version=Version.parse('10.0')) == None


def test_get_installed_simulators():
    simulators = Simulators(mock_xcversion_simulators_output)

    assert simulators.get_installed_simulators(os_name='iOS') == [
        Simulator(os_name='iOS', os_version=Version.parse('12.4'), is_installed=True),
        Simulator(os_name='iOS', os_version=Version.parse('15.0'), is_installed=True),
    ]


def test_skipping_duplicates():
    duplicated_output = mock_xcversion_simulators_output + '\n' + mock_xcversion_simulators_output
    simulators = Simulators(duplicated_output)

    assert simulators.get_all_simulators(os_name='iOS') == [
        Simulator(os_name='iOS', os_version=Version.parse('12.4'), is_installed=True),
        Simulator(os_name='iOS', os_version=Version.parse('13.0'), is_installed=False),
        Simulator(os_name='iOS', os_version=Version.parse('14.2'), is_installed=False),
        Simulator(os_name='iOS', os_version=Version.parse('15.0'), is_installed=True),
    ]