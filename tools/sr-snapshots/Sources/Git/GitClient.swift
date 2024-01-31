/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Files
import Shell
import Foundation

public struct GitClientError: Error, CustomStringConvertible {
    public var description: String
}

/// An abstraction over git client.
public protocol GitClient {
    /// Clones git repository to given location or skips if it is already present.
    /// - Parameter directory: directory url for cloning the repo
    func cloneIfNeeded(to directory: URL) throws

    /// Pulls new commits from current branch.
    func pull() throws

    /// Adds new commit on current branch.
    /// - Parameter message: the commit message
    func commit(message: String) throws

    /// Pushes recent commits to remote.
    func push() throws
}

public struct NOPGitClient: GitClient {
    public init() {}
    public func cloneIfNeeded(to directory: URL) throws {}
    public func pull() throws {}
    public func commit(message: String) throws {}
    public func push() throws {}
}

/// Naive implementation of basic git client that uses GitHub CLI under the hood.
///
/// It executes git commands directly in shell and requires `gh` CLI to be preinstalled on host (https://cli.github.com/)
/// and authorised for cloning private repositories.
public class GitHubGitClient: GitClient {
    /// Repo's SSH for git clone.
    private let ssh: String
    /// The name of git branch that this client will operate on.
    private let branch: String
    /// Repo directory URL if cloned successfully.
    private var repoDirectory: URL? = nil
    /// An interface for calling shell commands.
    private let cli = ProcessCommandLine()

    public init(ssh: String, branch: String) {
        self.ssh = ssh
        self.branch = branch
    }

    public func cloneIfNeeded(to directory: URL) throws {
        let directory = try Directory(url: directory) // it also creates directory if not exists
        let repoDirectory = directory.url.resolvingSymlinksInPath()

        if directory.fileExists(at: ".git") {
            let repoBranch = try cli.shell("cd \(repoDirectory.path()) && git rev-parse --abbrev-ref HEAD")
            let isRepoClean = try cli.shell("cd \(repoDirectory.path()) && git status --porcelain") == ""

            if repoBranch == branch && isRepoClean {
                print("ℹ️   Repo exists and uses '\(branch)' branch - skipping `git clone`.")
                self.repoDirectory = repoDirectory
                return
            } else if !isRepoClean {
                print("⚠️   Repo exists but contains unstaged changes. It will be  re-cloned.")
                try directory.deleteAllFiles()
            } else {
                print("⚠️   Repo exists but uses different branch \(repoBranch). It will be re-cloned.")
                try directory.deleteAllFiles()
            }
        } else {
            print("ℹ️   Repo does not exist and will be cloned to \(repoDirectory.path())")
        }

        print("ℹ️   Checking if `gh` CLI is installed")
        guard try cli.shellResult("which gh").status == 0 else {
            throw GitClientError(
                description: """
                `GitHubGitClient` requires `gh` CLI to be preinstalled and authorised on host.
                Download it from https://cli.github.com/
                """
            )
        }
        print("ℹ️   OK")

        print("ℹ️   Checking if `gh` CLI is authorised:")
        try cli.shell("gh auth status")

        print("ℹ️   Cloning repo (branch: '\(branch)'):")
        try cli.shell("gh repo clone \(ssh) '\(repoDirectory.path())' -- --branch \(branch) --single-branch")
        self.repoDirectory = repoDirectory
    }

    public func pull() throws {
        guard let repoDirectory = repoDirectory else {
            fatalError("no repo directory")
        }
        print("ℹ️   Pulling the repo:")
        try cli.shell("cd \(repoDirectory.path()) && git pull")
    }

    public func commit(message: String) throws {
        guard let repoDirectory = repoDirectory else {
            fatalError("no repo directory")
        }
        print("ℹ️   Adding a commit:")
        try cli.shell("cd \(repoDirectory.path()) && git add -A")
        try cli.shell("cd \(repoDirectory.path()) && git commit -m -S '\(message)'")
    }

    public func push() throws {
        guard let repoDirectory = repoDirectory else {
            fatalError("no repo directory")
        }
        print("ℹ️   Pushing changes:")
        try cli.shell("cd \(repoDirectory.path()) && git push")
    }
}
