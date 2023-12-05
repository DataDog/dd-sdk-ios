/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal struct Batch {
    /// Data blocks in the batch.
    let dataBlocks: [DataBlock]
    /// File from which `data` was read.
    let file: ReadableFile
}

extension Batch {
    /// Events contained in the batch.
    var events: [Event] {
        let generator = EventGenerator(dataBlocks: dataBlocks)
        return generator.map { $0 }
    }
}

/// A type, reading batched data.
internal protocol Reader {
    /// Reads files from the storage.
    /// - Parameter limit: maximum number of files to read.
    func readFiles(limit: Int) -> [ReadableFile]
    /// Reads batch from given file.
    /// - Parameter file: file to read batch from.
    func readBatch(from file: ReadableFile) -> Batch?
    /// Marks given batch as read.
    /// - Parameter batch: batch to mark as read.
    /// - Parameter reason: reason for removing the batch.
    func markBatchAsRead(_ batch: Batch, reason: BatchDeletedMetric.RemovalReason)
}
