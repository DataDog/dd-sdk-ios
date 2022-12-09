# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-Present Datadog, Inc.
# -----------------------------------------------------------

import os
import glob


class DirectoryMatcherException(Exception):
    pass


class DirectoryMatcher:
    path: str

    def __init__(self, path: str):
        if os.path.exists(path):
            self.path = path
        else:
            raise DirectoryMatcherException(f'Directory does not exist: {path}')

    def assert_number_of_files(self, expected_count: int):
        actual_count = len(os.listdir(self.path))
        if expected_count != actual_count:
            raise DirectoryMatcherException(f'Expected {expected_count} files in "{self.path}", but '
                                            f'found {actual_count} instead.')

    def assert_it_has_file(self, file_path: str):
        search_path = os.path.join(self.path, file_path)
        result = list(glob.iglob(search_path, recursive=True))

        if not result:
            raise DirectoryMatcherException(f'Expected "{self.path}" to include {file_path}, but it is missing.')

    def assert_it_has_files(self, file_paths: [str]):
        for file_path in file_paths:
            self.assert_it_has_file(file_path)

    def get(self, file: str) -> 'DirectoryMatcher':
        return DirectoryMatcher(path=os.path.join(self.path, file))
