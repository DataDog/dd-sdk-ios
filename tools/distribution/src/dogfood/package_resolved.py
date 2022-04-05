# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-2020 Datadog, Inc.
# -----------------------------------------------------------

import json
from copy import deepcopy
from typing import Optional


class PackageID:
    """Identifies package in `package.resolved` file."""

    v1: str  # used in `package.resolved` version 1
    v2: str  # used in `package.resolved` version 2

    def __init__(self, package_name: str, repository_url: str):
        self.v1 = package_name
        self.v2 = package_name


class PackageResolvedContent:
    """An interface for manipulating `package.resolved` content."""

    def has_dependency(self, package_name: str) -> bool:
        """Checks if dependency with given name exists."""
        pass

    def update_dependency(self, package_name: str, new_branch: Optional[str], new_revision: str, new_version: Optional[str]):
        """
        Updates dependency resolution values.
        :param package_name: the name of the package to update
        :param new_branch: the new branch name (pass `None` for `null`)
        :param new_revision: the new revision (pass `None` for `null`)
        :param new_version: the new version name (pass `None` for `null`)
        :return:
        """
        pass

    def add_dependency(self, package_name: str, repository_url: str, branch: Optional[str], revision: str, version: Optional[str]):
        """
        Adds new dependency resolution.
        """
        pass

    def read_dependency_names(self) -> [str]:
        """
        Returns package names for all dependencies.
        :return: list of package names (strings)
        """
        pass

    def read_dependency(self, package_name) -> dict:
        """
        Returns resolution info for given dependency.
        :param package_name: the name of dependency
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

    def has_dependency(self, package_name: str) -> bool:
        return self.wrapped.has_dependency(package_name)

    def update_dependency(self, package_name: str, new_branch: Optional[str], new_revision: str, new_version: Optional[str]):
        self.wrapped.update_dependency(package_name, new_branch, new_revision, new_version)

    def add_dependency(self, package_name: str, repository_url: str, branch: Optional[str], revision: str, version: Optional[str]):
        self.wrapped.add_dependency(package_name, repository_url, branch, revision, version)

    def read_dependency_names(self) -> [str]:
        return self.wrapped.read_dependency_names()

    def read_dependency(self, package_name) -> dict:
        return self.wrapped.read_dependency(package_name)


class PackageResolvedContentV1(PackageResolvedContent):
    """
    In `package.resolved` version `1`, sample package pin looks this:

    {
        "package": "DatadogSDK",
        "repositoryURL": "https://github.com/DataDog/dd-sdk-ios",
        "state": {
            "branch": "dogfooding",
            "revision": "4e93a8f1f662d9126074a0f355b4b6d20f9f30a7",
            "version": null
        }
    }
    """

    def __init__(self, path: str, json_content: dict):
        self.path = path
        self.packages = json_content

    def has_dependency(self, package_name: str):
        pins = self.packages['object']['pins']
        return package_name in [p['package'] for p in pins]

    def update_dependency(self, package_name: str, new_branch: Optional[str], new_revision: str, new_version: Optional[str]):
        package = self.__get_package(package_name=package_name)

        old_state = deepcopy(package['state'])

        package['state']['branch'] = new_branch
        package['state']['revision'] = new_revision
        package['state']['version'] = new_version

        new_state = deepcopy(package['state'])

        diff = old_state.items() ^ new_state.items()

        if len(diff) > 0:
            print(f'✏️️ Updated "{package_name}" in {self.path}:')
            print(f'    → old: {old_state}')
            print(f'    → new: {new_state}')
        else:
            print(f'✏️️ "{package_name}" is up-to-date in {self.path}')

    def add_dependency(self, package_name: str, repository_url: str, branch: Optional[str], revision: str, version: Optional[str]):
        pins = self.packages['object']['pins']

        # Find the index in `pins` array where the new dependency should be inserted.
        # The `pins` array seems to follow the alphabetical order, but not always
        # - I've seen `Package.resolved` where some dependencies were misplaced.
        index = next((i for i in range(len(pins)) if pins[i]['package'].lower() > package_name.lower()), len(pins))

        new_pin = {
            'package': package_name,
            'repositoryURL': repository_url,
            'state': {
                'branch': branch,
                'revision': revision,
                'version': version
            }
        }

        pins.insert(index, new_pin)

        print(f'✏️️ Added "{package_name}" at index {index} in {self.path}:')
        print(f'    → branch: {branch}')
        print(f'    → revision: {revision}')
        print(f'    → version: {version}')

    def read_dependency_names(self):
        pins = self.packages['object']['pins']
        package_names = [pin['package'] for pin in pins]
        return package_names

    def read_dependency(self, package_name):
        package = self.__get_package(package_name=package_name)
        return deepcopy(package)

    def __get_package(self, package_name: str):
        pins = self.packages['object']['pins']
        package_pins = [index for index, p in enumerate(pins) if p['package'] == package_name]

        if len(package_pins) == 0:
            raise Exception(
                f'{self.path} does not contain pin named "{package_name}"'
            )

        package_pin_index = package_pins[0]
        return self.packages['object']['pins'][package_pin_index]


class PackageResolvedContentV2(PackageResolvedContent):
    """
    In `package.resolved` version `2`, sample package pin looks this:

    {
      "identity" : "dd-sdk-ios",
      "kind" : "remoteSourceControl",
      "location" : "https://github.com/DataDog/dd-sdk-ios",
      "state" : {
        "branch" : "dogfooding",
        "revision" : "6f662103771eb4523164e64f7f936bf9276f6bd0"
      }
    }

    It can also have `version`, e.g. `version: 1.0.0` and then `branch` is not set. In V1 it was
    using `null` value to indicate this mutual exclusion.
    """

    def __init__(self, path: str, json_content: dict):
        self.path = path
        self.packages = json_content

    def has_dependency(self, package_name: str):
        pins = self.packages['object']['pins']
        return package_name in [p['identity'] for p in pins]

    def update_dependency(self, package_name: str, new_branch: Optional[str], new_revision: str, new_version: Optional[str]):
        package = self.__get_package(package_name=package_name)

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
            print(f'✏️️ Updated "{package_name}" in {self.path}:')
            print(f'    → old: {old_state}')
            print(f'    → new: {new_state}')
        else:
            print(f'✏️️ "{package_name}" is up-to-date in {self.path}')

    def add_dependency(self, package_name: str, repository_url: str, branch: Optional[str], revision: str, version: Optional[str]):
        pins = self.packages['object']['pins']

        # Find the index in `pins` array where the new dependency should be inserted.
        # The `pins` array seems to follow the alphabetical order.
        index = next((i for i in range(len(pins)) if pins[i]['identity'].lower() > package_name.lower()), len(pins))

        new_pin = {
            'identity': package_name,
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

        print(f'✏️️ Added "{package_name}" at index {index} in {self.path}:')
        print(f'    → branch: {branch}')
        print(f'    → revision: {revision}')
        print(f'    → version: {version}')

    def read_dependency_names(self):
        pins = self.packages['object']['pins']
        package_names = [pin['identity'] for pin in pins]
        return package_names

    def read_dependency(self, package_name):
        package = self.__get_package(package_name=package_name)
        return deepcopy(package)

    def __get_package(self, package_name: str):
        pins = self.packages['object']['pins']
        package_pins = [index for index, p in enumerate(pins) if p['identity'] == package_name]

        if len(package_pins) == 0:
            raise Exception(
                f'{self.path} does not contain pin named "{package_name}"'
            )

        package_pin_index = package_pins[0]
        return self.packages['object']['pins'][package_pin_index]
