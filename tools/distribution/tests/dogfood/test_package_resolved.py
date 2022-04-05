# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-2020 Datadog, Inc.
# -----------------------------------------------------------


import unittest
from tempfile import TemporaryDirectory, NamedTemporaryFile
from src.dogfood.package_resolved import PackageResolvedFile


class PackageResolvedFileTestCase(unittest.TestCase):
    v1_file_content = b'''
    {
      "object": {
        "pins": [
          {
            "package": "A",
            "repositoryURL": "https://github.com/A-org/a.git",
            "state": {
              "branch": "a-branch",
              "revision": "a-revision",
              "version": null
            }
          },
          {
            "package": "B",
            "repositoryURL": "https://github.com/B-org/b.git",
            "state": {
              "branch": null,
              "revision": "b-revision",
              "version": "1.0.0"
            }
          }
        ]
      },
      "version": 1
    }
    '''

    v2_file_content = b'''
    {
      "object": {
        "pins": [
          {
            "identity" : "a",
            "kind" : "remoteSourceControl",
            "location" : "https://github.com/A-org/a",
            "state" : {
              "branch" : "a-branch",
              "revision" : "a-revision"
            }
          },
          {
            "identity" : "b",
            "kind" : "remoteSourceControl",
            "location" : "https://github.com/B-org/b.git",
            "state" : {
              "revision" : "b-revision",
              "version" : "1.0.0"
            }
          }
        ]
      },
      "version": 2
    }
    '''

    def test_it_reads_version1_files(self):
        with NamedTemporaryFile() as file:
            file.write(self.v1_file_content)
            file.seek(0)

            package_resolved = PackageResolvedFile(path=file.name)
            self.assertTrue(package_resolved.has_dependency(package_name='A'))
            self.assertTrue(package_resolved.has_dependency(package_name='B'))
            self.assertFalse(package_resolved.has_dependency(package_name='C'))
            self.assertListEqual(['A', 'B'], package_resolved.read_dependency_names())
            self.assertDictEqual(
                {
                    'package': 'A',
                    'repositoryURL': 'https://github.com/A-org/a.git',
                    'state': {'branch': 'a-branch', 'revision': 'a-revision', 'version': None}
                },
                package_resolved.read_dependency(package_name='A')
            )
            self.assertDictEqual(
                {
                    'package': 'B',
                    'repositoryURL': 'https://github.com/B-org/b.git',
                    'state': {'branch': None, 'revision': 'b-revision', 'version': '1.0.0'}
                },
                package_resolved.read_dependency(package_name='B')
            )

    def test_it_changes_version1_files(self):
        with NamedTemporaryFile() as file:
            file.write(self.v1_file_content)
            file.seek(0)

            package_resolved = PackageResolvedFile(path=file.name)
            package_resolved.update_dependency(
                package_name='B', new_branch='b-branch-new', new_revision='b-revision-new', new_version=None
            )
            package_resolved.add_dependency(
                package_name='C', repository_url='https://github.com/C-org/c.git',
                branch='c-branch', revision='c-revision', version=None
            )
            package_resolved.add_dependency(
                package_name='D', repository_url='https://github.com/D-org/d.git',
                branch=None, revision='d-revision', version='1.1.0'
            )
            package_resolved.save()

            actual_new_content = file.read().decode('utf-8')
            expected_new_content = '''{
  "object": {
    "pins": [
      {
        "package": "A",
        "repositoryURL": "https://github.com/A-org/a.git",
        "state": {
          "branch": "a-branch",
          "revision": "a-revision",
          "version": null
        }
      },
      {
        "package": "B",
        "repositoryURL": "https://github.com/B-org/b.git",
        "state": {
          "branch": "b-branch-new",
          "revision": "b-revision-new",
          "version": null
        }
      },
      {
        "package": "C",
        "repositoryURL": "https://github.com/C-org/c.git",
        "state": {
          "branch": "c-branch",
          "revision": "c-revision",
          "version": null
        }
      },
      {
        "package": "D",
        "repositoryURL": "https://github.com/D-org/d.git",
        "state": {
          "branch": null,
          "revision": "d-revision",
          "version": "1.1.0"
        }
      }
    ]
  },
  "version": 1
}
'''
            self.assertEqual(expected_new_content, actual_new_content)

    def test_it_reads_version2_files(self):
        with NamedTemporaryFile() as file:
            file.write(self.v2_file_content)
            file.seek(0)

            package_resolved = PackageResolvedFile(path=file.name)
            self.assertTrue(package_resolved.has_dependency(package_name='a'))
            self.assertTrue(package_resolved.has_dependency(package_name='b'))
            self.assertFalse(package_resolved.has_dependency(package_name='c'))
            self.assertListEqual(['a', 'b'], package_resolved.read_dependency_names())
            self.assertDictEqual(
                {
                    'identity': 'a',
                    'kind': 'remoteSourceControl',
                    'location': 'https://github.com/A-org/a',
                    'state': {'branch': 'a-branch', 'revision': 'a-revision'}
                },
                package_resolved.read_dependency(package_name='a')
            )
            self.assertDictEqual(
                {
                    'identity': 'b',
                    'kind': 'remoteSourceControl',
                    'location': 'https://github.com/B-org/b.git',
                    'state': {'revision': 'b-revision', 'version': '1.0.0'}
                },
                package_resolved.read_dependency(package_name='b')
            )

    def test_it_changes_version2_files(self):
        with NamedTemporaryFile() as file:
            file.write(self.v2_file_content)
            file.seek(0)

            package_resolved = PackageResolvedFile(path=file.name)
            package_resolved.update_dependency(
                package_name='b', new_branch='b-branch-new', new_revision='b-revision-new', new_version=None
            )
            package_resolved.add_dependency(
                package_name='c', repository_url='https://github.com/C-org/c.git',
                branch='c-branch', revision='c-revision', version=None
            )
            package_resolved.add_dependency(
                package_name='d', repository_url='https://github.com/D-org/d.git',
                branch=None, revision='d-revision', version='1.1.0'
            )
            package_resolved.save()

            actual_new_content = file.read().decode('utf-8')
            expected_new_content = '''{
  "object": {
    "pins": [
      {
        "identity": "a",
        "kind": "remoteSourceControl",
        "location": "https://github.com/A-org/a",
        "state": {
          "branch": "a-branch",
          "revision": "a-revision"
        }
      },
      {
        "identity": "b",
        "kind": "remoteSourceControl",
        "location": "https://github.com/B-org/b.git",
        "state": {
          "branch": "b-branch-new",
          "revision": "b-revision-new"
        }
      },
      {
        "identity": "c",
        "kind": "remoteSourceControl",
        "location": "https://github.com/C-org/c.git",
        "state": {
          "branch": "c-branch",
          "revision": "c-revision"
        }
      },
      {
        "identity": "d",
        "kind": "remoteSourceControl",
        "location": "https://github.com/D-org/d.git",
        "state": {
          "revision": "d-revision",
          "version": "1.1.0"
        }
      }
    ]
  },
  "version": 2
}
'''
            self.assertEqual(expected_new_content, actual_new_content)
