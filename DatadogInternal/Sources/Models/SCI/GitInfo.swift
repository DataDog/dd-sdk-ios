/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Git repository information for source code integration.
///
/// This structure contains git metadata collected during build time by the DatadogSCI plugin.
/// The information is read from the `DatadogSCI.plist` file created in the app bundle.
public struct GitInfo: AdditionalContext, Sendable {
    /// SCI key in core additional context.
    public static var key = "git-info"

    /// The git repository URL
    public let repositoryURL: String

    /// The git commit SHA
    public let commitSHA: String

    /// Creates a new GitInfo instance with repository URL and commit SHA.
    ///
    /// - Parameters:
    ///   - repositoryURL: The git repository URL
    ///   - commitSHA: The git commit SHA
    public init(repositoryURL: String, commitSHA: String) {
        self.repositoryURL = repositoryURL
        self.commitSHA = commitSHA
    }
}
