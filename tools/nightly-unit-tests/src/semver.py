# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-Present Datadog, Inc.
# -----------------------------------------------------------

import re
from dataclasses import dataclass


@dataclass
class Version:
    major: int
    minor: int
    patch: int

    def __repr__(self):
        if self.patch == 0:
            return f'{self.major}.{self.minor}'
        else:
            return f'{self.major}.{self.minor}.{self.patch}'

    @staticmethod
    def parse(string: str):
        matches = re.findall(r'([0-9]+)(.[0-9]+)?(.[0-9]+)?', string)
        if len(matches) > 0:
            match = matches[0]
            return Version(
                major=0 if match[0] == '' else int(match[0]),
                minor=0 if match[1] == '' else int(match[1][1:]),
                patch=0 if match[2] == '' else int(match[2][1:])
            )
        else:
            raise Exception(f'Not a valid version string: {string}')

    def is_newer_than(self, other_version: 'Version'):
        if self.major > other_version.major:
            return True
        elif self.major == other_version.major:
            if self.minor > other_version.minor:
                return True
            elif self.minor == other_version.minor:
                if self.patch > other_version.patch:
                    return True

        return False

    def is_newer_than_or_equal(self, other_version: 'Version'):
        return self.is_newer_than(other_version=other_version) or self == other_version
