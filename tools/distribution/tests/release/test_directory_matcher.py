# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-Present Datadog, Inc.
# -----------------------------------------------------------


import unittest
import os
from tempfile import TemporaryDirectory
from src.release.directory_matcher import DirectoryMatcher, DirectoryMatcherException


class DirectoryMatcherTestCase(unittest.TestCase):
    def test_initializing(self):
        with TemporaryDirectory() as tmp_dir:
            self.assertEqual(DirectoryMatcher(path=tmp_dir).path, tmp_dir)

        with self.assertRaises(DirectoryMatcherException):
            _ = DirectoryMatcher(path=f'{tmp_dir}/non-existing-path')

    def test_number_of_files(self):
        with TemporaryDirectory() as tmp_dir:
            dm = DirectoryMatcher(path=tmp_dir)
            dm.assert_number_of_files(expected_count=0)

            os.mkdir(os.path.join(tmp_dir, '1'))
            os.mkdir(os.path.join(tmp_dir, '2'))
            dm.assert_number_of_files(expected_count=2)

            with self.assertRaises(DirectoryMatcherException):
                dm.assert_number_of_files(expected_count=4)

    def test_has_file(self):
        with TemporaryDirectory() as tmp_dir:
            dm = DirectoryMatcher(path=tmp_dir)
            os.makedirs(os.path.join(tmp_dir, '1/1A/1AA.xyz'))
            os.makedirs(os.path.join(tmp_dir, '1/1A/1AB.xyz'))
            os.makedirs(os.path.join(tmp_dir, '2/2A/2AA/foo.xyz'))
            os.makedirs(os.path.join(tmp_dir, '2/2A/2AB/foo.xyz'))

            dm.assert_it_has_file('1')
            dm.assert_it_has_file('1/1A/1AA.xyz')
            dm.assert_it_has_file('1/1A/1AB.xyz')
            dm.assert_it_has_file('**/1AA.xyz')
            dm.assert_it_has_file('**/1AB.xyz')
            dm.assert_it_has_file('**/*.xyz')
            dm.assert_it_has_file('**/2A/**/*.xyz')
            dm.assert_it_has_file('2')

            with self.assertRaises(DirectoryMatcherException):
                dm.assert_it_has_file('foo')

            with self.assertRaises(DirectoryMatcherException):
                dm.assert_it_has_file('1A')

    def test_has_files(self):
        with TemporaryDirectory() as tmp_dir:
            dm = DirectoryMatcher(path=tmp_dir)
            os.makedirs(os.path.join(tmp_dir, '1/1A/1AA.xyz'))
            os.makedirs(os.path.join(tmp_dir, '1/1A/1AB.xyz'))
            os.makedirs(os.path.join(tmp_dir, '2/2A/2AA/foo.xyz'))
            os.makedirs(os.path.join(tmp_dir, '2/2A/2AB/foo.xyz'))

            dm.assert_it_has_files([
                '1',
                '1/1A/1AA.xyz',
                '1/1A/1AB.xyz',
                '**/1AA.xyz',
                '**/1AB.xyz',
                '**/*.xyz',
                '**/2A/**/*.xyz',
                '2',
            ])

            with self.assertRaises(DirectoryMatcherException):
                dm.assert_it_has_files(file_paths=['foo', 'bar'])

            with self.assertRaises(DirectoryMatcherException):
                dm.assert_it_has_files(file_paths=['2', '**/foo'])

    def test_get_submatcher(self):
        with TemporaryDirectory() as tmp_dir:
            os.makedirs(os.path.join(tmp_dir, '1/1A'))

            dm = DirectoryMatcher(path=tmp_dir)
            dm.assert_it_has_file('1')

            dm = dm.get('1')
            dm.assert_it_has_file('1A')

            with self.assertRaises(DirectoryMatcherException):
                dm.assert_it_has_file('1')
