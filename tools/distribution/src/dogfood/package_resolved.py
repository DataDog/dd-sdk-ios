# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-Present Datadog, Inc.
# -----------------------------------------------------------

import json
from dataclasses import dataclass
from copy import deepcopy
from typing import Optional


@dataclass()
class PackageID:
    """
    Identifies package in `package.resolved` file.
    It supports `version: 1` and `version: 2` of `package.resolved` format:
    - v1 uses package name (e.g. `DatadogSDK`) as package identifier
    - v2 uses package identity (e.g. `dd-sdk-ios`) as package identifier
    - v2 is not backward compatible with v1 - the v1 package name cannot be read from v2's `package.resolved`
    - v1 is forward compatible with v2 - the v2 package identity can be read from `repositoryURL` in v1's `package.resolved`
    """
    v1: Optional[str]  # can be `None` if read from v2's `package.resolved`
    v2: str


def v2_package_id_from_repository_url(repository_url: str) -> str:
    """Reads v2 package id from repository URL."""
    components = repository_url.split('/')  # e.g. ['https:/', '', 'github.com', 'A-org', 'abc.git']
    return components[-1].split('.')[0]


class PackageResolvedContent:
    """An interface for manipulating `package.resolved` content."""

    def has_dependency(self, package_id: PackageID) -> bool:
        """Checks if dependency with given ID exists."""
        pass

    def update_dependency(self, package_id: PackageID, new_branch: Optional[str], new_revision: str, new_version: Optional[str]):
        """
        Updates dependency resolution values.
        :param package_id: identifies dependency to update
        :param new_branch: the new branch name (pass `None` for `null`)
        :param new_revision: the new revision (pass `None` for `null`)
        :param new_version: the new version name (pass `None` for `null`)
        :return:
        """
        pass

    def add_dependency(self, package_id: PackageID, repository_url: str, branch: Optional[str], revision: str, version: Optional[str]):
        """
        Adds new dependency resolution.
        """
        pass

    def read_dependency_ids(self) -> [PackageID]:
        """
        Returns package IDs for all dependencies.
        :return: list of package IDs (PackageIDs)
        """
        pass

    def read_dependency(self, package_id: PackageID) -> dict:
        """
        Returns resolution info for given dependency.
        :param package_id: the `PackageID` of dependency
        :return: the `pin` object from `Package.resolved`
        """
        pass


class PackageResolvedFile(PackageResolvedContent):
    """
    Abstracts operations on `Package.resolved` file.
    """

    version: int
    wrapped: PackageResolvedContent

    def __init__(self, path: str):
        print(f'⚙️ Opening {path}')
        self.path = path
        with open(path, 'r') as file:
            self.packages = json.load(file)
            self.version = self.packages['version']
            if self.version == 1:
                self.wrapped = PackageResolvedContentV1(self.path, self.packages)
            elif self.version == 2:
                self.wrapped = PackageResolvedContentV2(self.path, self.packages)
            else:
                raise Exception(
                    f'{path} uses version {self.version} but `PackageResolvedFile` only supports ' +
                    f'versions `1` and `2`. Update `PackageResolvedFile` to support new version.'
                )

    def save(self):
        """
        Saves changes to initial `path`.
        """
        print(f'⚙️ Saving {self.path}')
        with open(self.path, 'w') as file:
            json.dump(
                self.packages,
                fp=file,
                indent=2,  # preserve `swift package` indentation
                separators=(',', ': ' if self.version == 1 else ' : '),  # v1: `"key": "value"`, v2: `"key" : "value"`
                sort_keys=True  # preserve `swift package` packages sorting
            )
            file.write('\n')  # add new line to the EOF

    def print(self):
        """
        Prints the content of this file.
        """
        with open(self.path, 'r') as file:
            print(f'⚙️ Content of {file.name}:')
            print(file.read())

    def has_dependency(self, package_id: PackageID) -> bool:
        return self.wrapped.has_dependency(package_id)

    def update_dependency(self, package_id: PackageID, new_branch: Optional[str], new_revision: str, new_version: Optional[str]):
        self.wrapped.update_dependency(package_id, new_branch, new_revision, new_version)

    def add_dependency(self, package_id: PackageID, repository_url: str, branch: Optional[str], revision: str, version: Optional[str]):
        self.wrapped.add_dependency(package_id, repository_url, branch, revision, version)

    def read_dependency_ids(self) -> [PackageID]:
        return self.wrapped.read_dependency_ids()

    def read_dependency(self, package_id: PackageID) -> dict:
        return self.wrapped.read_dependency(package_id)


class PackageResolvedContentV1(PackageResolvedContent):
    """
    Example of `package.resolved` in version `1` looks this::

        {
            "object": {
                "pins": [
                    {
                        "package": "DatadogSDK",
                        "repositoryURL": "https://github.com/DataDog/dd-sdk-ios",
                        "state": {
                            "branch": "dogfooding",
                            "revision": "4e93a8f1f662d9126074a0f355b4b6d20f9f30a7",
                            "version": null
                        }
                    },
                    ...
                ]
            },
            "version": 1
        }
    """

    def __init__(self, path: str, json_content: dict):
        self.path = path
        self.packages = json_content

    def has_dependency(self, package_id: PackageID):
        pins = self.packages['object']['pins']
        return package_id.v1 in [p['package'] for p in pins]

    def update_dependency(self, package_id: PackageID, new_branch: Optional[str], new_revision: str, new_version: Optional[str]):
        package = self.__get_package(package_id=package_id)

        old_state = deepcopy(package['state'])

        package['state']['branch'] = new_branch
        package['state']['revision'] = new_revision
        package['state']['version'] = new_version

        new_state = deepcopy(package['state'])

        diff = old_state.items() ^ new_state.items()

        if len(diff) > 0:
            print(f'✏️️ Updated "{package_id.v1}" in {self.path}:')
            print(f'    → old: {old_state}')
            print(f'    → new: {new_state}')
        else:
            print(f'✏️️ "{package_id.v1}" is up-to-date in {self.path}')

    def add_dependency(self, package_id: PackageID, repository_url: str, branch: Optional[str], revision: str, version: Optional[str]):
        pins = self.packages['object']['pins']

        # Find the index in `pins` array where the new dependency should be inserted.
        # The `pins` array seems to follow the alphabetical order, but not always
        # - I've seen `Package.resolved` where some dependencies were misplaced.
        index = next((i for i in range(len(pins)) if pins[i]['package'].lower() > package_id.v1.lower()), len(pins))

        new_pin = {
            'package': package_id.v1,
            'repositoryURL': repository_url,
            'state': {
                'branch': branch,
                'revision': revision,
                'version': version
            }
        }

        pins.insert(index, new_pin)

        print(f'✏️️ Added "{package_id.v1}" at index {index} in {self.path}:')
        print(f'    → branch: {branch}')
        print(f'    → revision: {revision}')
        print(f'    → version: {version}')

    def read_dependency_ids(self):
        pins = self.packages['object']['pins']
        package_ids = [PackageID(v1=pin['package'], v2=v2_package_id_from_repository_url(pin['repositoryURL'])) for pin in pins]
        return package_ids

    def read_dependency(self, package_id: PackageID):
        package = self.__get_package(package_id=package_id)
        return deepcopy(package)

    def __get_package(self, package_id: PackageID):
        pins = self.packages['object']['pins']
        package_pins = [index for index, p in enumerate(pins) if p['package'] == package_id.v1]

        if len(package_pins) == 0:
            raise Exception(
                f'{self.path} does not contain pin named "{package_id.v1}"'
            )

        package_pin_index = package_pins[0]
        return self.packages['object']['pins'][package_pin_index]


class PackageResolvedContentV2(PackageResolvedContent):
    """
    Example of `package.resolved` in version `2` looks this::

        {
            "pins" : [
                {
                    "identity" : "dd-sdk-ios",
                    "kind" : "remoteSourceControl",
                    "location" : "https://github.com/DataDog/dd-sdk-ios",
                    "state" : {
                        "branch" : "dogfooding",
                        "revision" : "6f662103771eb4523164e64f7f936bf9276f6bd0"
                    }
                },
                ...
            ]
            "version" : 2
        }

    In v2 `branch` and `version` are mutually exclusive: if one is set, the other
    is not present (unlike v1, where one was always set to `null`).
    """

    def __init__(self, path: str, json_content: dict):
        self.path = path
        self.packages = json_content

    def has_dependency(self, package_id: PackageID):
        pins = self.packages['pins']
        return package_id.v2 in [p['identity'] for p in pins]

    def update_dependency(self, package_id: PackageID, new_branch: Optional[str], new_revision: str, new_version: Optional[str]):
        package = self.__get_package(package_id=package_id)

        old_state = deepcopy(package['state'])

        if new_branch:
            package['state']['branch'] = new_branch
        else:
            package['state'].pop('branch', None)  # delete key regardless of whether it exists

        if new_revision:
            package['state']['revision'] = new_revision
        else:
            package['state'].pop('revision', None)

        if new_version:
            package['state']['version'] = new_version
        else:
            package['state'].pop('version', None)

        new_state = deepcopy(package['state'])

        diff = old_state.items() ^ new_state.items()

        if len(diff) > 0:
            print(f'✏️️ Updated "{package_id.v2}" in {self.path}:')
            print(f'    → old: {old_state}')
            print(f'    → new: {new_state}')
        else:
            print(f'✏️️ "{package_id.v2}" is up-to-date in {self.path}')

    def add_dependency(self, package_id: PackageID, repository_url: str, branch: Optional[str], revision: str, version: Optional[str]):
        pins = self.packages['pins']

        # Find the index in `pins` array where the new dependency should be inserted.
        # The `pins` array seems to follow the alphabetical order.
        index = next((i for i in range(len(pins)) if pins[i]['identity'].lower() > package_id.v2.lower()), len(pins))

        new_pin = {
            'identity': package_id.v2,
            'kind': 'remoteSourceControl',
            'location': repository_url,
            'state': {}
        }

        if branch:
            new_pin['state']['branch'] = branch

        if revision:
            new_pin['state']['revision'] = revision

        if version:
            new_pin['state']['version'] = version

        pins.insert(index, new_pin)

        print(f'✏️️ Added "{package_id.v2}" at index {index} in {self.path}:')
        print(f'    → branch: {branch}')
        print(f'    → revision: {revision}')
        print(f'    → version: {version}')

    def read_dependency_ids(self) -> [PackageID]:
        pins = self.packages['pins']
        package_ids = [PackageID(v1=None, v2=pin['identity']) for pin in pins]
        return package_ids

    def read_dependency(self, package_id: PackageID):
        package = self.__get_package(package_id=package_id)
        return deepcopy(package)

    def __get_package(self, package_id: PackageID):
        pins = self.packages['pins']
        package_pins = [index for index, p in enumerate(pins) if p['identity'] == package_id.v2]

        if len(package_pins) == 0:
            raise Exception(
                f'{self.path} does not contain pin named "{package_id.v2}"'
            )

        package_pin_index = package_pins[0]
        return self.packages['pins'][package_pin_index]
