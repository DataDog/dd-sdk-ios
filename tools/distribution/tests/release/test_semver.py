# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-Present Datadog, Inc.
# -----------------------------------------------------------

# This file is a copied and enhanced version of `tools/nightly-unit-tests/tests/test_semver.py`
# TODO: RUMM-1860 Share this code between both tools

import unittest
from src.release.semver import Version, PreRelease, VersionParsingException


class VersionTestCase(unittest.TestCase):
    def test_parsing(self):
        self.assertEqual(Version.parse('10.0.3'), Version(major=10, minor=0, patch=3, pre_release=None))
        self.assertEqual(Version.parse('11.4'), Version(major=11, minor=4, patch=0, pre_release=None))
        self.assertEqual(Version.parse('12'), Version(major=12, minor=0, patch=0, pre_release=None))
        self.assertEqual(
            Version.parse('10.0.3-alpha3'),
            Version(major=10, minor=0, patch=3, pre_release=PreRelease(identifier='alpha', iteration=3))
        )
        self.assertEqual(
            Version.parse('10.0.3-rc2'),
            Version(major=10, minor=0, patch=3, pre_release=PreRelease(identifier='rc', iteration=2))
        )
        self.assertEqual(
            Version.parse('10.0.3-beta12'),
            Version(major=10, minor=0, patch=3, pre_release=PreRelease(identifier='beta', iteration=12))
        )

    def test_invalid_parsing(self):
        with self.assertRaises(VersionParsingException):
            Version.parse('')
        with self.assertRaises(VersionParsingException):
            Version.parse('1.-2')
        with self.assertRaises(VersionParsingException):
            Version.parse('1x1x3')
        with self.assertRaises(VersionParsingException):
            Version.parse('1.1.0-unknown12')

    def test_comparing(self):
        self.assertTrue(Version.parse('14.0.0').is_newer_than(Version.parse('13.1.2')))
        self.assertTrue(Version.parse('14.1.1').is_newer_than(Version.parse('14.1.0')))
        self.assertTrue(Version.parse('14.2.3').is_newer_than(Version.parse('14.2.2')))
        self.assertFalse(Version.parse('14.0.3').is_newer_than(Version.parse('15.0.2')))
        self.assertFalse(Version.parse('14.0.3').is_newer_than(Version.parse('14.1.0')))
        self.assertFalse(Version.parse('14.0.3').is_newer_than(Version.parse('14.0.4')))
        self.assertFalse(Version.parse('14.0.3').is_newer_than(Version.parse('14.0.3')))
        self.assertTrue(Version.parse('14.0.3').is_newer_than_or_equal(Version.parse('14.0.3')))
        self.assertFalse(Version.parse('14.0.2').is_newer_than_or_equal(Version.parse('14.0.3')))

        self.assertTrue(Version.parse('14.0.0').is_newer_than(Version.parse('14.0.0-alpha1')))
        self.assertTrue(Version.parse('14.0.0').is_newer_than(Version.parse('14.0.0-alpha2')))
        self.assertTrue(Version.parse('14.0.0').is_newer_than(Version.parse('14.0.0-beta3')))
        self.assertTrue(Version.parse('14.0.0').is_newer_than(Version.parse('14.0.0-rc4')))
        self.assertTrue(Version.parse('1.0.2').is_newer_than(Version.parse('1.0.0-rc3')))
        self.assertTrue(Version.parse('1.2').is_newer_than(Version.parse('1.2-rc1')))
        self.assertTrue(Version.parse('1.2-beta1').is_newer_than(Version.parse('1.2-alpha2')))
        self.assertTrue(Version.parse('1.2-rc3').is_newer_than(Version.parse('1.2-rc2')))
        self.assertTrue(Version.parse('1.2-rc2').is_newer_than(Version.parse('1.2-beta4')))
        self.assertTrue(Version.parse('14.0.3-alpha2').is_newer_than_or_equal(Version.parse('14.0.3-alpha2')))
        self.assertFalse(Version.parse('14.0.2-alpha3').is_newer_than_or_equal(Version.parse('14.0.2-rc2')))

        self.assertTrue(Version.parse('1.8.1').is_newer_than(Version.parse('1.8')))
        self.assertTrue(Version.parse('1.8.1-beta1').is_newer_than(Version.parse('1.8')))
        self.assertTrue(Version.parse('1.9.0').is_newer_than(Version.parse('1.8')))
        self.assertTrue(Version.parse('1.80.0').is_newer_than(Version.parse('1.8')))
