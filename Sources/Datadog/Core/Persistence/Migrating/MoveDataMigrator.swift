/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Data migrator which moves files from source directory to destination directory.
/// Existing files in target direcory remain untouched.
internal struct MoveDataMigrator: DataMigrator {
    private let sourceDirectory: Directory
    private let destinationDirectory: Directory

    init(sourceDirectory: Directory, destinationDirectory: Directory) {
        self.sourceDirectory = sourceDirectory
        self.destinationDirectory = destinationDirectory
    }

    func migrate() {
        do {
            try sourceDirectory.moveAllFilesTo(destinationDirectory)
        } catch {
            developerLogger?.error(
                """
                🔥 Failed to use `MoveDataMigrator` for source directory \(sourceDirectory.url)
                and destination directory \(destinationDirectory.url) due to: \(error)
                """
            )
        }
    }
}
