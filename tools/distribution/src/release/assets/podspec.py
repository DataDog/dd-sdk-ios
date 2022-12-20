#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-Present Datadog, Inc.
# -----------------------------------------------------------

import os
import re
import time
import random
from src.utils import shell, read_sdk_version


class CPPodspec:
    """
    The Cocoapods podspec pushed to `pod trunk`.
    """

    __name: str  # The name of the spec, e.g. `DatadogSDK`
    __file_name: str  # The name of the spec file, e.g. `DatadogSDK.podspec`
    __path: str  # The path to the `podspec` file

    def __init__(self, name: str):
        file_name = f'{name}.podspec'
        print(f'⌛️ Searching for `{file_name}` in {os.getcwd()}')

        file_path = f'{os.getcwd()}/{file_name}'
        if not os.path.isfile(file_path):
            raise Exception(f'Cannot find `{file_name}` in {os.getcwd()}')

        self.__name = name
        self.__file_name = file_name
        self.__path = file_path
        print(f'   → `{file_name}` found')

    def __repr__(self):
        return f'[CPPodspec: name = {self.__name}, path = {self.__path}]'

    def validate(self, git_tag: str):
        """
        Checks the `.podspec` integrity with given `git_tag`.
        """
        print(f'🔎️️ Validating {self} against: {git_tag}')

        # Check if spec `.version` matches the git tag name and `sdk_version`:
        sdk_version = read_sdk_version()
        pod_version = self.__read_pod_version()
        if not (pod_version == git_tag and sdk_version == git_tag):
            raise Exception(f'`sdk_version` ({sdk_version}), `pod_version` ({pod_version})'
                            f' and git tag ({git_tag}) do not match')
        print(f'   → `sdk_version` ({sdk_version}), `pod_version` ({pod_version})'
              f' and git tag ({git_tag}) do match')

    def publish(self, dry_run: bool):
        """
        Publishes the `.podspec` to pods trunk.
        """
        print(f'📦 Publishing {self} ({self.__read_pod_version()})')

        # Because some of our pods depend on others and due to https://github.com/CocoaPods/CocoaPods/issues/9497
        # we need to retry `pod trunk push` until it succeeds. The maximum number of attempts is 100 (arbitrary),
        # but this is also limited by the CI job timeout.
        retry_time = 30  # seconds
        attempt = 0
        while attempt < 100:
            attempt += 1
            try:
                if attempt == 1:
                    shell(f'pod repo update', skip=dry_run)
                    shell(f'pod spec lint --allow-warnings {self.__file_name}', skip=dry_run)
                    shell(f'pod trunk push --synchronous --allow-warnings {self.__file_name}', skip=dry_run)
                else:
                    shell(f'pod repo update --silent', skip=dry_run)
                    shell(f'pod spec lint  --silent --allow-warnings {self.__file_name}', skip=dry_run)
                    shell(f'pod trunk push --allow-warnings {self.__file_name}', skip=dry_run)

                if dry_run and random.choice([True, False]):  # to enable testing in `dry_run` mode
                    retry_time = 1
                    raise Exception('Running in dry_run mode, simulating `pod` command failure')

                print(f'   → succeeded in {attempt} attempt(s)')
                break  # break the while loop once all succeed without raising an exception

            except Exception:
                print(f'   → failed on attempt {attempt} (retrying in {retry_time}s)')

            time.sleep(retry_time)

    def __read_pod_version(self) -> str:
        """
        Reads pod version from podspec file.
        """
        version_regex = r'^.*\.version.*=.*\"([0-9]+\.[0-9]+\.[0-9]+[\-a-z0-9]*)\"'  # e.g. 's.version = "1.7.1-alpha1"'

        versions: [str] = []
        with open(self.__path) as podspec_file:
            for line in podspec_file.readlines():
                if match := re.match(version_regex, line):
                    versions.append(match.groups()[0])

        if len(versions) != 1:
            raise Exception(f'Expected one spec `version` in {podspec_file}, but found {len(versions)}: {versions}')

        return versions[0]
