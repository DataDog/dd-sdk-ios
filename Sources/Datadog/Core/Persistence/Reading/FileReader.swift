/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Reads data from files.
internal final class FileReader: Reader {
    /// Data reading format.
    private let dataFormat: DataFormat
    /// Orchestrator producing reference to readable file.
    private let orchestrator: FilesOrchestrator
    private let internalMonitor: InternalMonitor?

    /// Files marked as read.
    private var filesRead: [ReadableFile] = []

    init(
        dataFormat: DataFormat,
        orchestrator: FilesOrchestrator,
        internalMonitor: InternalMonitor? = nil
    ) {
        self.dataFormat = dataFormat
        self.orchestrator = orchestrator
        self.internalMonitor = internalMonitor
    }

    // MARK: - Reading batches

    func readNextBatch() -> Batch? {
        if let file = orchestrator.getReadableFile(excludingFilesNamed: Set(filesRead.map { $0.name })) {
            do {
                let fileData = try file.read()
                let batchData = dataFormat.prefixData + fileData + dataFormat.suffixData
                return Batch(data: batchData, file: file)
            } catch {
                internalMonitor?.sdkLogger.error("Failed to read data from file", error: error)
                return nil
            }
        }

        return nil
    }

    // MARK: - Accepting batches

    func markBatchAsRead(_ batch: Batch) {
        orchestrator.delete(readableFile: batch.file)
        filesRead.append(batch.file)
    }
}
