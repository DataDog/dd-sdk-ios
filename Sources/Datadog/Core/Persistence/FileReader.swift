/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal struct Batch {
    /// Data read from file, prefixed with `[` and suffixed with `]`.
    let data: Data
    /// File from which `data` was read.
    fileprivate let file: ReadableFile
}

internal final class FileReader {
    /// Data reading format.
    private let dataFormat: DataFormat
    /// Orchestrator producing reference to readable file.
    private let orchestrator: FilesOrchestrator
    /// Queue used to synchronize files access (read / write).
    private let queue: DispatchQueue

    /// Files marked as read.
    private var filesRead: [ReadableFile] = []

    init(dataFormat: DataFormat, orchestrator: FilesOrchestrator, queue: DispatchQueue) {
        self.dataFormat = dataFormat
        self.orchestrator = orchestrator
        self.queue = queue
    }

    // MARK: - Reading batches

    func readNextBatch() -> Batch? {
        queue.sync {
            synchronizedReadNextBatch()
        }
    }

    private func synchronizedReadNextBatch() -> Batch? {
        if let file = orchestrator.getReadableFile(excludingFilesNamed: Set(filesRead.map { $0.name })) {
            do {
                let fileData = try file.read()
                let batchData = dataFormat.prefixData + fileData + dataFormat.suffixData
                return Batch(data: batchData, file: file)
            } catch {
                developerLogger?.error("🔥 Failed to read file: \(error)")
                return nil
            }
        }

        return nil
    }

    // MARK: - Accepting batches

    func markBatchAsRead(_ batch: Batch) {
        queue.sync { [weak self] in
            self?.synchronizedMarkBatchAsRead(batch)
        }
    }

    private func synchronizedMarkBatchAsRead(_ batch: Batch) {
        orchestrator.delete(readableFile: batch.file)
        filesRead.append(batch.file)
    }
}
