# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-2020 Datadog, Inc.
# -----------------------------------------------------------

import os
from git import Repo, Actor


class DogfoodedCommit:
    """
    Reads the git information for the commit being dogfooded.
    * when running on CI - reads it from CI ENV
    * when running locally - reads it from `dd-sdk-ios` repo git info
    """

    def __init__(self):
        if 'CI' in os.environ:
            print('ℹ️ Running on CI')
            print('    → reading git author from ENV')
            self.author = Actor(
                name=os.environ['GIT_CLONE_COMMIT_AUTHOR_NAME'],
                email=os.environ['GIT_CLONE_COMMIT_AUTHOR_EMAIL']
            )
            self.hash = os.environ['GIT_CLONE_COMMIT_HASH']
            self.message = os.environ['GIT_CLONE_COMMIT_MESSAGE_SUBJECT']
        else:
            print('ℹ️ Running locally')
            print('    → reading git author from the last commit in dd-sdk-ios')
            dd_sdk_ios_repo = Repo(path='../../')
            self.author = dd_sdk_ios_repo.head.commit.author
            self.hash = dd_sdk_ios_repo.head.commit.hexsha
            self.message = dd_sdk_ios_repo.head.commit.message

        self.hash_short = self.hash[0:8]
