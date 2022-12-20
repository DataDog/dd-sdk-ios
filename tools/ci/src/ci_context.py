# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-Present Datadog, Inc.
# -----------------------------------------------------------

import json
import os
from typing import Optional
from dataclasses import dataclass
from src.utils import shell_output


@dataclass
class CIContext:
    trigger_env: 'TriggerENVs'
    build_env: 'BuildENVs'
    pull_request: Optional['PullRequest']


@dataclass
class TriggerENVs:
    """
    ENVs defined for a trigger in `bitrise.yml`.
    """
    DD_RUN_UNIT_TESTS: str
    DD_RUN_SR_UNIT_TESTS: str
    DD_RUN_INTEGRATION_TESTS: str
    DD_RUN_SMOKE_TESTS: str
    DD_RUN_TOOLS_TESTS: str


@dataclass
class BuildENVs:
    """
    Optional ENVs passed from outside (when starting build manually).
    """
    DD_OVERRIDE_RUN_UNIT_TESTS: Optional[str]
    DD_OVERRIDE_RUN_SR_UNIT_TESTS: Optional[str]
    DD_OVERRIDE_RUN_INTEGRATION_TESTS: Optional[str]
    DD_OVERRIDE_RUN_SMOKE_TESTS: Optional[str]
    DD_OVERRIDE_RUN_TOOLS_TESTS: Optional[str]


@dataclass
class PullRequest:
    """
    Pull request context fetched from GH (available only for pull request builds).
    """
    description: 'PullRequestDescription'
    modified_files: 'PullRequestFiles'


@dataclass
class PullRequestDescription:
    """
    Description of the PR.
    """
    description: str

    def contains(self, word: str) -> bool:
        return word in self.description


@dataclass
class PullRequestFiles:
    """
    List of files modified by the PR.
    """
    paths: [str]

    def contains_paths(self, path_prefixes: [str]) -> bool:
        for path in self.paths:
            for path_prefix in path_prefixes:
                if path.startswith(path_prefix):
                    return True
        return False

    def contains_extensions(self, file_extensions: [str]) -> bool:
        for path in self.paths:
            for file_extension in file_extensions:
                if path.endswith(file_extension):
                    return True
        return False


def get_ci_context() -> CIContext:
    trigger_env = TriggerENVs(
        DD_RUN_UNIT_TESTS=os.environ.get('DD_RUN_UNIT_TESTS') or "0",
        DD_RUN_SR_UNIT_TESTS=os.environ.get('DD_RUN_SR_UNIT_TESTS') or "0",
        DD_RUN_INTEGRATION_TESTS=os.environ.get('DD_RUN_INTEGRATION_TESTS') or "0",
        DD_RUN_SMOKE_TESTS=os.environ.get('DD_RUN_SMOKE_TESTS') or "0",
        DD_RUN_TOOLS_TESTS=os.environ.get('DD_RUN_TOOLS_TESTS') or "0"
    )

    build_env = BuildENVs(
        DD_OVERRIDE_RUN_UNIT_TESTS=os.environ.get('DD_OVERRIDE_RUN_UNIT_TESTS'),
        DD_OVERRIDE_RUN_SR_UNIT_TESTS=os.environ.get('DD_OVERRIDE_RUN_SR_UNIT_TESTS'),
        DD_OVERRIDE_RUN_INTEGRATION_TESTS=os.environ.get('DD_OVERRIDE_RUN_INTEGRATION_TESTS'),
        DD_OVERRIDE_RUN_SMOKE_TESTS=os.environ.get('DD_OVERRIDE_RUN_SMOKE_TESTS'),
        DD_OVERRIDE_RUN_TOOLS_TESTS=os.environ.get('DD_OVERRIDE_RUN_TOOLS_TESTS')
    )

    if pull_request_id := os.environ.get('BITRISE_PULL_REQUEST'):
        # Fetch PR details with GH CLI (ref.: https://cli.github.com/manual/gh_pr_view)
        gh_cli_output = shell_output(f'gh pr view {pull_request_id} --json body,files')
        pr_json = json.loads(gh_cli_output)
        pull_request = PullRequest(
            description=PullRequestDescription(pr_json['body']),
            modified_files=PullRequestFiles(list(map(lambda file: file['path'], pr_json['files'])))
        )
    else:
        pull_request = None

    return CIContext(
        trigger_env=trigger_env,
        build_env=build_env,
        pull_request=pull_request
    )
