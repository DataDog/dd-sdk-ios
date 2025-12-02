/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Source code integration utilities for reading git information from the app bundle.
internal enum SourceCodeIntegration {
    /// Reads git information from the DatadogSCI.plist file created by the build plugin.
    ///
    /// This property attempts to load the `DatadogSCI.plist` file from the main bundle
    /// and extract the repository URL and commit SHA that were collected during build time.
    ///
    /// - Returns: A `GitInfo` instance if the plist exists and contains valid data, `nil` otherwise
    static var gitInfo: GitInfo? {
        guard
            let path = Bundle.main.path(forResource: "DatadogSCI", ofType: "plist"),
            let plist = NSDictionary(contentsOfFile: path),
            let repo = plist["RepositoryURL"] as? String,
            let commit = plist["CommitSHA"] as? String
        else {
            return nil
        }

        return GitInfo(repositoryURL: repo, commitSHA: commit)
    }
}
