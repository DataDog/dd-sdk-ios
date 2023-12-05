# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-Present Datadog, Inc.
# -----------------------------------------------------------

from src.semver import Version


def test_parsing():
    assert Version.parse('10.0.3') == Version(major=10, minor=0, patch=3)
    assert Version.parse('11.4') == Version(major=11, minor=4, patch=0)
    assert Version.parse('12') == Version(major=12, minor=0, patch=0)


def test_comparing():
    assert Version.parse('14.0.0').is_newer_than(Version.parse('13.1.2')) == True
    assert Version.parse('14.1.1').is_newer_than(Version.parse('14.1.0')) == True
    assert Version.parse('14.2.3').is_newer_than(Version.parse('14.2.2')) == True
    assert Version.parse('14.0.3').is_newer_than(Version.parse('15.0.2')) == False
    assert Version.parse('14.0.3').is_newer_than(Version.parse('14.1.0')) == False
    assert Version.parse('14.0.3').is_newer_than(Version.parse('14.0.4')) == False
    assert Version.parse('14.0.3').is_newer_than(Version.parse('14.0.3')) == False
    assert Version.parse('14.0.3').is_newer_than_or_equal(Version.parse('14.0.3')) == True
    assert Version.parse('14.0.2').is_newer_than_or_equal(Version.parse('14.0.3')) == False
