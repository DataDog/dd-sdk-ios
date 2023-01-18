#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-Present Datadog, Inc.
# -----------------------------------------------------------

import os


def clone_repo(repo_ssh: str, repo_name: str, git_tag: str):
    """
    Clones given repo to current directory using GH CLI.
    The GH CLI must be authentication by ENV.
    """
    print('ℹ️️ Logging GH CLI authentication status:')
    os.system('gh auth status')

    print(f'⚙️ Cloning `{repo_name}` (`gh repo clone {repo_ssh} -- -b {git_tag}`)')
    result = os.system(f'gh repo clone {repo_ssh} -- -b {git_tag}')

    if result > 0:
        raise Exception(f'Failed to clone `{repo_name}`. Check GH CLI authentication status in above logs.')
    else:
        print(f'    → successfully cloned `{repo_name}` (`{git_tag}`) to: {os.getcwd()}')
