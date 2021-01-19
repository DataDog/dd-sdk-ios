/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Data migrator which deletes all files in given directory.
internal struct DeleteAllDataMigrator: DataMigrator {
    private let directory: Directory

    init(directory: Directory) {
        self.directory = directory
    }

    func migrate() {
        do {
            try directory.deleteAllFiles()
        } catch {
            developerLogger?.error(
                "🔥 Failed to use `DeleteAllDataMigrator` in directory \(directory.url) due to: \(error)"
            )
        }
    }
}
