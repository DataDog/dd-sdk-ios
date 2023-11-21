# -----------------------------------------------------------
# Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2019-Present Datadog, Inc.
# -----------------------------------------------------------


import os
from typing import Union
from git import Repo, Actor


default_git_author = Actor(name='mobile-app-ci', email='')


class Repository:
    """
    Abstracts operations on the target repository.
    """

    def __init__(self, repo: Repo):
        self.repo = repo

    @staticmethod
    def clone(ssh: str, repository_name: str, temp_dir: str):
        """
        Clones the git repository using GH CLI.
        The GH CLI must be authentication by the environment.
        :returns git.Repo object
        """
        print('ℹ️️ Logging GH CLI authentication status:')
        os.system('gh auth status')

        print(f'ℹ️️ Changing current directory to: {temp_dir}')
        os.chdir(temp_dir)

        print(f'⚙️ Cloning {ssh}')
        result = os.system(f'gh repo clone {ssh}')

        if result > 0:
            raise Exception(
                f'Unable to clone GH repository ({ssh}). Check GH CLI authentication status in above logs.'
            )
        else:
            print(f'    → changing current directory to: {os.getcwd()}/{repository_name}')
            os.chdir(repository_name)
            return Repository(repo=Repo(path=os.getcwd()))

    def create_branch(self, branch_name):
        """
        Creates and checks out a git branch.
        :param branch_name: the name of the branch
        """
        print(f'⚙️️️️ Creating git branch: {branch_name}')
        self.repo.git.checkout('HEAD', b=branch_name)

    def commit(self, message: str, author: Union[None, 'Actor'] = None):
        """
        Creates commit with current changes.
        :param message: commit message
        :param author: author of the commit (git.Actor object) or None (will be read from git config)
        """
        if author:
            print(f'⚙️️️️ Committing changes on behalf of {author.name} ({author.email})')
        else:
            print(f'⚙️️️️ Committing changes using git user from current git config')
        print('    → commit message:')
        print(message)

        # Add GPG signing
        signer = self.repo.config_reader().get_value("user", "signingkey")
        self.repo.head.commit.sign(signer)

        self.repo.git.add(update=True)
        self.repo.index.commit(message=message, author=author, committer=author)

    def push(self):
        """
        Pushes current branch to the remote.
        """
        print(f'⚙️️️️ Pushing to remote')
        origin = self.repo.remote(name="origin")
        self.repo.git.push("--set-upstream", "--force", origin, self.repo.head.ref)

    def create_pr(self, title: str, description: str):
        print(f'⚙️️ Creating draft PR')
        print(f'    → title: {title}')
        print(f'    → description: {description}')
        os.system(f'gh pr create --title "{title}" --body "{description}" --draft')
