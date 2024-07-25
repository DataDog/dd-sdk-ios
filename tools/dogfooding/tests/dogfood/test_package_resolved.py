# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-Present Datadog, Inc.
# -----------------------------------------------------------


import unittest
from tempfile import NamedTemporaryFile
from src.dogfood.package_resolved import PackageResolvedFile, PackageID, v2_package_id_from_repository_url


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
      "pins" : [
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
      ],
      "version" : 2
    }
    '''

    v3_file_content = b'''
    {
      "originHash" : "ea83017c944c7850b8f60207e6143eb17cb6b5e6b734b3fa08787a5d920dba7b",
      "pins" : [
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
      ],
      "version" : 3
    }
    '''

    def test_it_reads_version1_files(self):
        with NamedTemporaryFile() as file:
            file.write(self.v1_file_content)
            file.seek(0)

            package_resolved = PackageResolvedFile(path=file.name)
            self.assertTrue(package_resolved.has_dependency(package_id=PackageID(v1='A', v2='a')))
            self.assertTrue(package_resolved.has_dependency(package_id=PackageID(v1='B', v2='b')))
            self.assertFalse(package_resolved.has_dependency(package_id=PackageID(v1='C', v2='c')))
            self.assertListEqual(
                [PackageID(v1='A', v2='a'), PackageID(v1='B', v2='b')],
                package_resolved.read_dependency_ids()
            )
            self.assertDictEqual(
                {
                    'package': 'A',
                    'repositoryURL': 'https://github.com/A-org/a.git',
                    'state': {'branch': 'a-branch', 'revision': 'a-revision', 'version': None}
                },
                package_resolved.read_dependency(package_id=PackageID(v1='A', v2='a'))
            )
            self.assertDictEqual(
                {
                    'package': 'B',
                    'repositoryURL': 'https://github.com/B-org/b.git',
                    'state': {'branch': None, 'revision': 'b-revision', 'version': '1.0.0'}
                },
                package_resolved.read_dependency(package_id=PackageID(v1='B', v2='b'))
            )

    def test_it_changes_version1_files(self):
        with NamedTemporaryFile() as file:
            file.write(self.v1_file_content)
            file.seek(0)

            package_resolved = PackageResolvedFile(path=file.name)
            package_resolved.update_dependency(
                package_id=PackageID(v1='B', v2='b'),
                new_branch='b-branch-new', new_revision='b-revision-new', new_version=None
            )
            package_resolved.add_dependency(
                package_id=PackageID(v1='C', v2='c'), repository_url='https://github.com/C-org/c.git',
                branch='c-branch', revision='c-revision', version=None
            )
            package_resolved.add_dependency(
                package_id=PackageID(v1='D', v2='d'), repository_url='https://github.com/D-org/d.git',
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
            self.assertTrue(package_resolved.has_dependency(package_id=PackageID(v1=None, v2='a')))
            self.assertTrue(package_resolved.has_dependency(package_id=PackageID(v1=None, v2='b')))
            self.assertFalse(package_resolved.has_dependency(package_id=PackageID(v1=None, v2='c')))
            self.assertListEqual(
                [PackageID(v1=None, v2='a'), PackageID(v1=None, v2='b')],
                package_resolved.read_dependency_ids()
            )
            self.assertDictEqual(
                {
                    'identity': 'a',
                    'kind': 'remoteSourceControl',
                    'location': 'https://github.com/A-org/a',
                    'state': {'branch': 'a-branch', 'revision': 'a-revision'}
                },
                package_resolved.read_dependency(package_id=PackageID(v1=None, v2='a'))
            )
            self.assertDictEqual(
                {
                    'identity': 'b',
                    'kind': 'remoteSourceControl',
                    'location': 'https://github.com/B-org/b.git',
                    'state': {'revision': 'b-revision', 'version': '1.0.0'}
                },
                package_resolved.read_dependency(PackageID(v1=None, v2='b'))
            )

    def test_it_changes_version2_files(self):
        with NamedTemporaryFile() as file:
            file.write(self.v2_file_content)
            file.seek(0)

            package_resolved = PackageResolvedFile(path=file.name)
            package_resolved.update_dependency(
                package_id=PackageID(v1=None, v2='b'), new_branch='b-branch-new',
                new_revision='b-revision-new', new_version=None
            )
            package_resolved.add_dependency(
                package_id=PackageID(v1=None, v2='c'), repository_url='https://github.com/C-org/c.git',
                branch='c-branch', revision='c-revision', version=None
            )
            package_resolved.add_dependency(
                package_id=PackageID(v1=None, v2='d'), repository_url='https://github.com/D-org/d.git',
                branch=None, revision='d-revision', version='1.1.0'
            )
            package_resolved.save()

            actual_new_content = file.read().decode('utf-8')
            expected_new_content = '''{
  "pins" : [
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
        "branch" : "b-branch-new",
        "revision" : "b-revision-new"
      }
    },
    {
      "identity" : "c",
      "kind" : "remoteSourceControl",
      "location" : "https://github.com/C-org/c.git",
      "state" : {
        "branch" : "c-branch",
        "revision" : "c-revision"
      }
    },
    {
      "identity" : "d",
      "kind" : "remoteSourceControl",
      "location" : "https://github.com/D-org/d.git",
      "state" : {
        "revision" : "d-revision",
        "version" : "1.1.0"
      }
    }
  ],
  "version" : 2
}
'''
            self.assertEqual(expected_new_content, actual_new_content)

    def test_v2_package_id_from_repository_url(self):
        self.assertEqual('abc', v2_package_id_from_repository_url(repository_url='https://github.com/A-org/abc.git'))
        self.assertEqual('abc', v2_package_id_from_repository_url(repository_url='https://github.com/A-org/abc'))
        self.assertEqual('abc', v2_package_id_from_repository_url(repository_url='git@github.com:DataDog/abc.git'))
        self.assertEqual('abc', v2_package_id_from_repository_url(repository_url='git@github.com:DataDog/abc'))

    def test_it_reads_version3_files(self):
        with NamedTemporaryFile() as file:
            file.write(self.v3_file_content)
            file.seek(0)

            package_resolved = PackageResolvedFile(path=file.name)
            self.assertTrue(package_resolved.has_dependency(package_id=PackageID(v1=None, v2='a')))
            self.assertTrue(package_resolved.has_dependency(package_id=PackageID(v1=None, v2='b')))
            self.assertFalse(package_resolved.has_dependency(package_id=PackageID(v1=None, v2='c')))
            self.assertListEqual(
                [PackageID(v1=None, v2='a'), PackageID(v1=None, v2='b')],
                package_resolved.read_dependency_ids()
            )
            self.assertDictEqual(
                {
                    'identity': 'a',
                    'kind': 'remoteSourceControl',
                    'location': 'https://github.com/A-org/a',
                    'state': {'branch': 'a-branch', 'revision': 'a-revision'}
                },
                package_resolved.read_dependency(package_id=PackageID(v1=None, v2='a'))
            )
            self.assertDictEqual(
                {
                    'identity': 'b',
                    'kind': 'remoteSourceControl',
                    'location': 'https://github.com/B-org/b.git',
                    'state': {'revision': 'b-revision', 'version': '1.0.0'}
                },
                package_resolved.read_dependency(PackageID(v1=None, v2='b'))
            )
            self.assertEqual(
                "ea83017c944c7850b8f60207e6143eb17cb6b5e6b734b3fa08787a5d920dba7b",
                package_resolved.origin_hash()
            )