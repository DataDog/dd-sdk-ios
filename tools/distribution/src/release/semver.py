# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-Present Datadog, Inc.
# -----------------------------------------------------------

# This file is a copied and enhanced version of `tools/nightly-unit-tests/src/semver.py`
# TODO: RUMM-1860 Share this code between both tools

import re
from dataclasses import dataclass
from typing import Optional

main_regex = r'([0-9]+)(\.[0-9]+)?(\.[0-9]+)?'  # regex describing the main version component, e.g. '1.3.2'
pre_release_regex = r'-(alpha|beta|rc)([0-9]+)'  # regex describing the pre-release version component, e.g. '-alpha3'


class VersionParsingException(Exception):
    pass


@dataclass
class PreRelease:
    identifier: str  # 'alpha' | 'beta' | 'rc'
    iteration: int  # iteration of version within given identifier, e.g. 2 for 2nd 'beta'

    def __repr__(self):
        return f'-{self.identifier}.{self.iteration}'

    def is_newer_than(self, other_version: 'PreRelease'):
        grades = {'alpha': 1, 'beta': 2, 'rc': 3}

        if grades[self.identifier] > grades[other_version.identifier]:
            return True
        elif grades[self.identifier] == grades[other_version.identifier]:
            if self.iteration > other_version.iteration:
                return True

        return False


@dataclass
class Version:
    major: int
    minor: int
    patch: int
    pre_release: Optional[PreRelease]  # optional pre-release version, e.g. '1.0.0-alpha3' has PreRelease('alpha', 3)

    def __repr__(self):
        pre_release_repr = '' if not self.pre_release else f'{self.pre_release}'
        if self.patch == 0:
            return f'{self.major}.{self.minor}{pre_release_repr}'
        else:
            return f'{self.major}.{self.minor}.{self.patch}{pre_release_repr}'

    @staticmethod
    def parse(string: str):
        """
        Reads `Version` from string like '1.5' or '1.3.1-beta3', where '1.5' and 1.3.1' are main
        version components and '-beta3' is a pre-release component.
        """
        regex = re.compile(f'^(?P<m>{main_regex})(?P<pr>{pre_release_regex})?$')
        match = re.match(regex, string)

        if not match:
            raise VersionParsingException(f'Invalid version string: {string} - not matching `{regex}`')

        if m_string := match.groupdict().get('m'):
            pr = None

            if pr_string := match.groupdict().get('pr'):
                if pr_match := re.match(re.compile(pre_release_regex), pr_string):
                    pr = PreRelease(
                        identifier=pr_match[1],
                        iteration=int(pr_match[2])
                    )
                else:
                    raise VersionParsingException(f'Invalid pre-release version string: {pr_string}')

            if m_match := re.match(re.compile(main_regex), m_string):
                return Version(
                    major=0 if not m_match[1] else int(m_match[1]),
                    minor=0 if not m_match[2] else int(m_match[2][1:]),
                    patch=0 if not m_match[3] else int(m_match[3][1:]),
                    pre_release=pr
                )
            else:
                raise VersionParsingException(f'Invalid main version string: {m_string}')
        else:
            raise VersionParsingException(f'Invalid version string: {string}')

    def is_newer_than(self, other_version: 'Version'):
        if self.major > other_version.major:
            return True
        elif self.major == other_version.major:
            if self.minor > other_version.minor:
                return True
            elif self.minor == other_version.minor:
                if self.patch > other_version.patch:
                    return True
                elif self.patch == other_version.patch:
                    if self.pre_release and other_version.pre_release:
                        return self.pre_release.is_newer_than(other_version.pre_release)
                    elif self.pre_release and not other_version.pre_release:
                        return False
                    elif not self.pre_release and other_version.pre_release:
                        return True

        return False

    def is_newer_than_or_equal(self, other_version: 'Version'):
        return self.is_newer_than(other_version=other_version) or self == other_version

    def is_older_than(self, other_version: 'Version'):
        return not self.is_newer_than_or_equal(other_version)
