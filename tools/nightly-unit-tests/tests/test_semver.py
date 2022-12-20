# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-Present Datadog, Inc.
# -----------------------------------------------------------

import unittest
from src.semver import Version


class VersionTestCase(unittest.TestCase):
    def test_parsing(self):
        self.assertEqual(Version.parse('10.0.3'), Version(major=10, minor=0, patch=3))
        self.assertEqual(Version.parse('11.4'), Version(major=11, minor=4, patch=0))
        self.assertEqual(Version.parse('12'), Version(major=12, minor=0, patch=0))

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
