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

/// GitHub client using gh CLI with token authentication (read-only: clone and pull only)
public class GitHubClient: GitClient {
    /// GitHub repository (e.g., "owner/repo" or full URL)
    private let repository: String
    /// The name of git branch that this client will operate on.
    private let branch: String
    /// GitHub Personal Access Token for authentication.
    private let token: String
    /// Repo directory URL if cloned successfully.
    private var repoDirectory: URL? = nil
    /// An interface for calling shell commands.
    private let cli = ProcessCommandLine()

    public init(repository: String, branch: String, token: String) {
        self.repository = repository
        self.branch = branch
        self.token = token
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
                print("⚠️   Repo exists but contains unstaged changes. It will be re-cloned.")
                try directory.deleteAllFiles()
            } else {
                print("⚠️   Repo exists but uses different branch \(repoBranch). It will be re-cloned.")
                try directory.deleteAllFiles()
            }
        } else {
            print("ℹ️   Repo does not exist and will be cloned to \(repoDirectory.path())")
        }

        print("ℹ️   Cloning repo (branch: '\(branch)') using gh CLI:")
        try cli.shell("GH_TOKEN=\(token) gh repo clone \(repository) '\(repoDirectory.path())' -- --branch \(branch) --single-branch")
        self.repoDirectory = repoDirectory
    }

    public func pull() throws {
        guard let repoDirectory = repoDirectory else {
            fatalError("no repo directory")
        }

        struct RepoView: Decodable {
            let url: String
            let sshUrl: String
        }

        // IMPORTANT: gh repo sync uses the local git remote URL for fetching, before syncing with --source parameter.
        // If the repo was previously cloned with SSH (e.g., by BasicGitClient), the remote will still
        // be configured as SSH. On CI, where we use token authentication and don't have SSH keys,
        // this causes "Repository not found" errors.
        //
        // Solution: Query GitHub for both HTTPS (url) and SSH (sshUrl) URLs, check the current
        // remote configuration, and update it from SSH to HTTPS if needed before calling gh repo sync.

        // Get repository URLs from GitHub
        let viewOutput = try cli.shell("GH_TOKEN=\(token) gh repo view \(repository) --json url,sshUrl")
        guard let jsonData = viewOutput.data(using: .utf8) else {
            throw GitClientError(description: "Failed to parse repository info from: \(viewOutput)")
        }

        let repoInfo = try JSONDecoder().decode(RepoView.self, from: jsonData)

        // Check current remote URL and update if it's SSH
        let origin = try cli.shell("cd \(repoDirectory.path()) && git remote get-url origin")
        if origin == repoInfo.sshUrl {
            print("ℹ️   Updating remote URL from SSH to HTTPS for token authentication")
            try cli.shell("cd \(repoDirectory.path()) && git remote set-url origin \(repoInfo.url)")
        }

        print("ℹ️   Pulling the repo using gh CLI:")
        try cli.shell("cd \(repoDirectory.path()) && GH_TOKEN=\(token) gh repo sync --source \(repository) --branch \(branch)")
    }

    public func commit(message: String) throws {
        print("⚠️   GitHubClient does not support commit operations (read-only, clone only)")
    }

    public func push() throws {
        print("⚠️   GitHubClient does not support push operations (read-only, clone only)")
    }
}

/// Basic git client
public class BasicGitClient: GitClient {
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

        print("ℹ️   Cloning repo (branch: '\(branch)'):")
        try cli.shell("git clone --branch \(branch) --single-branch \(ssh) '\(repoDirectory.path())'")
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
        try cli.shell("cd \(repoDirectory.path()) && git commit -S -m '\(message)'")
    }

    public func push() throws {
        guard let repoDirectory = repoDirectory else {
            fatalError("no repo directory")
        }
        print("ℹ️   Pushing changes:")
        try cli.shell("cd \(repoDirectory.path()) && git push")
    }
}
