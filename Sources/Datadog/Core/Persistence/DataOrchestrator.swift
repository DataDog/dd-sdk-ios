/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Orchestrates data in authorised and unauthorised directories of a single feature.
internal protocol DataOrchestratorType {
    func deleteAllData()
}

internal struct DataOrchestrator: DataOrchestratorType {
    /// Queue used to synchronize reads and writes for the feature.
    let queue: DispatchQueue
    /// Orchestrates files in `.granted` directory.
    let authorizedFilesOrchestrator: FilesOrchestrator
    /// Orchestrates files in `.pending` directory.
    let unauthorizedFilesOrchestrator: FilesOrchestrator

    func deleteAllData() {
        queue.async {
            authorizedFilesOrchestrator.deleteAllReadableFiles()
            unauthorizedFilesOrchestrator.deleteAllReadableFiles()
        }
    }

    internal func markAllFilesAsReadable() {
        queue.sync {
            authorizedFilesOrchestrator.ignoreFilesAgeWhenReading = true
            unauthorizedFilesOrchestrator.ignoreFilesAgeWhenReading = true
        }
    }
}
