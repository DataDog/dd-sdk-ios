/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Git
import Files
import Foundation
import ArgumentParser

/// Git clone ssh for snapshots repo.
private let ssh = "git@github.com:DataDog/dd-mobile-session-replay-snapshots.git"
/// Default branch in snapshots repo.
private let defaultBranch = "main"

internal struct Options: ParsableArguments {
    @Option(help: "The path to snapshots folder in local repo")
    var localFolder: String

    @Option(help: "The path that remote repo will be cloned to")
    var remoteFolder: String

    @Option(help: "The name of git branch to use in remote repo")
    var remoteBranch: String = defaultBranch

    @Flag(help: "Run without performing git operations (useful for debugging)")
    var dryRun = false
}

extension Options {
    /// Determines `<local-repo>/<snapshots>/png` location.
    var pngsSubfolder: URL {
        URL(filePath: localFolder).appending(path: "png", directoryHint: .isDirectory)
    }

    /// Determines `<local-repo>/<snapshots>/pointers` location.
    var pointersSubfolder: URL {
        URL(filePath: localFolder).appending(path: "pointers", directoryHint: .isDirectory)
    }

    /// Determines `<remote-repo>` location.
    var remoteRepoFolder: URL {
        URL(filePath: remoteFolder, directoryHint: .isDirectory)
    }

    /// Determines `<remote-repo>/ios` location.
    var iosSubfolder: URL {
        URL(filePath: remoteFolder).appending(path: "ios", directoryHint: .isDirectory)
    }
}

public struct PullSnapshotsCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "pull",
        abstract: "Pulls snapshots from remote."
    )

    @OptionGroup var options: Options

    public init() {}

    public func run() throws {
        let git: GitClient
        if options.dryRun {
            git = NOPGitClient()
        } else if let token = ProcessInfo.processInfo.environment["GH_TOKEN"] {
            git = GitHubClient(repository: ssh, branch: options.remoteBranch, token: token)
        } else {
            git = BasicGitClient(ssh: ssh, branch: options.remoteBranch)
        }

        try git.cloneIfNeeded(to: options.remoteRepoFolder)
        let remoteRepo = try RemoteRepo(options: options, git: git)
        let localRepo = try LocalRepo(options: options)
        try pullSnapshots(to: localRepo, from: remoteRepo)
        print("✅    Success  🤜🤛")
    }
}

public struct PushSnapshotsCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "push",
        abstract: "Pushes new snapshots to remote."
    )

    @OptionGroup var options: Options

    public init() {}

    public func run() throws {
        let git: GitClient = options.dryRun ? NOPGitClient() : BasicGitClient(ssh: ssh, branch: options.remoteBranch)
        try git.cloneIfNeeded(to: options.remoteRepoFolder)
        let remoteRepo = try RemoteRepo(options: options, git: git)
        let localRepo = try LocalRepo(options: options)
        try pushSnapshots(from: localRepo, to: remoteRepo)
        print("✅    Success  🤜🤛")
    }
}

extension LocalRepo {
    init(options: Options) throws {
        self.init(
            localFilesDirectory: try Directory(url: options.pngsSubfolder),
            pointersDirectory: try Directory(url: options.pointersSubfolder),
            pointersHashing: SHA1Hashing()
        )
    }
}

extension RemoteRepo {
    init(options: Options, git: GitClient) throws {
        self.init(
            git: git,
            remoteFilesDirectory: try Directory(url: options.iosSubfolder)
        )
    }
}
