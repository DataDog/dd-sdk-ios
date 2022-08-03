/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Data migrator which moves files from source directory to destination directory.
/// Existing files in target direcory remain untouched.
internal struct MoveDataMigrator: DataMigrator {
    let sourceDirectory: Directory
    let destinationDirectory: Directory

    func migrate() {
        do {
            try sourceDirectory.moveAllFiles(to: destinationDirectory)
        } catch {
            DD.telemetry.error(
                """
                🔥 Failed to use `MoveDataMigrator` for source directory \(sourceDirectory.url)
                and destination directory \(destinationDirectory.url)
                """,
                error: error
            )
        }
    }
}
