#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-Present Datadog, Inc

import re
import subprocess
import sys
import os
import subprocess
from argparse import ArgumentParser, Namespace
from tempfile import TemporaryDirectory
from typing import Tuple

import requests
from git import Repo

TARGET_APP = "app"
TARGET_DEMO = "demo"

REPOSITORIES = {TARGET_APP: "datadog-ios", TARGET_DEMO: "shopist-ios"}


def parse_arguments(args: list) -> Namespace:
    parser = ArgumentParser()

    parser.add_argument("-v", "--version", required=True, help="the version of the SDK")
    parser.add_argument("-t", "--target", required=True,
                        choices=[TARGET_APP, TARGET_DEMO],
                        help="the target repository")

    return parser.parse_args(args)


def github_create_pr(repository: str, branch_name: str, base_name: str, version: str, gh_token: str) -> int:
    headers = {
        'authorization': "Bearer " + gh_token,
        'Accept': 'application/vnd.github.v3+json',
    }
    data = '{"body": "This PR has been created automatically by the CI", ' \
           '"title": "Update to version ' + version + '", ' \
                                                      '"base":"' + base_name + '", "head":"' + branch_name + '"}'

    url = "https://api.github.com/repos/DataDog/" + repository + "/pulls"
    response = requests.post(url=url, headers=headers, data=data)
    if response.status_code == 201:
        print("✔ Pull Request created successfully")
        return 0
    else:
        print("✘ pull request failed " + str(response.status_code) + '\n' + response.text)
        return 1


def generate_target_code(target: str, temp_dir_path: str, version: str) -> int:
    print("… Generating code with version " + version)

    if target == TARGET_APP:
        print("… Updating app's Podfile")
        target_file_path = os.path.join(temp_dir_path, "Podfile")
        content = ""
        with open(target_file_path, 'r') as target_file:
            lines = target_file.readlines()
            for line in lines:
                if "pod 'DatadogSDK'" in line:
                    content = content + "    pod 'DatadogSDK', :git => 'https://github.com/DataDog/dd-sdk-ios.git', :tag => '" + version + "'\n"
                else:
                    content = content + line

        with open(target_file_path, 'w') as target_file:
            target_file.write(content)


        print("… Running `bundle exec pod install`") 
        os.chdir(temp_dir_path)
        cmd_args = ['bundle', 'exec', 'pod', 'install']
        process = subprocess.Popen(cmd_args, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, close_fds=True)
        try:
            output, errlog = process.communicate(timeout=120)
        except subprocess.TimeoutExpired:
            print("✘ generation timeout for " + target + ", version: " + version)
            return 1

        if process.returncode is None:
            print("✘ generation status unknown for " + target + ", version: " + version)
            return 1
        elif process.returncode > 0:
            print("✘ generation failed for " + target + ", version: " + version)
            print(output.decode("utf-8"))
            print(errlog.decode("utf-8"))
            return 1
        else:
            return 0
    # TODO RUMM-1063 elif target == TARGET_DEMO: …
    else:
        print("? unknown generation target: " + target + ", version: " + version)


def git_clone_repository(repo_name: str, gh_token: str, temp_dir_path: str) -> Tuple[Repo, str]:
    print("… Cloning repository " + repo_name)
    url = "https://" + gh_token + ":x-oauth-basic@github.com/DataDog/" + repo_name
    repo = Repo.clone_from(url, temp_dir_path)
    base_name = repo.active_branch.name
    return repo, base_name


def git_push_changes(repo: Repo, version: str):
    print("… Committing changes")
    repo.git.add(update=True)
    repo.index.commit("Update DD SDK to " + version)

    print("⑊ Pushing branch")
    origin = repo.remote(name="origin")
    repo.git.push("--set-upstream", "--force", origin, repo.head.ref)


def update_dependant(version: str, target: str, gh_token: str) -> int:
    branch_name = "update_sdk_" + version
    temp_dir = TemporaryDirectory()
    temp_dir_path = temp_dir.name
    repo_name = REPOSITORIES[target]

    repo, base_name = git_clone_repository(repo_name, gh_token, temp_dir_path)

    print("… Creating branch " + branch_name)
    repo.git.checkout('HEAD', b=branch_name)


    cwd = os.getcwd()
    result = generate_target_code(target, temp_dir_path, version)
    os.chdir(cwd)

    if result > 0:
        return result

    if not repo.is_dirty():
        print("∅ Nothing to commit, all is in order…")
        return 0

    git_push_changes(repo, version)

    return github_create_pr(repo_name, branch_name, base_name, version, gh_token)

def run_main() -> int:
    cli_args = parse_arguments(sys.argv[1:])

    if cli_args.target != TARGET_APP:
        print("Cannot dogfood target : " + cli_args.target)
        return 1

    # This script expects to have a valid Github Token in a "gh_token" text file
    # The token needs the `repo` permissions, and for now is a PAT
    with open('gh_token', 'r') as f:
        gh_token = f.read().strip()

    return update_dependant(cli_args.version, cli_args.target, gh_token)


if __name__ == "__main__":
    sys.exit(run_main())
