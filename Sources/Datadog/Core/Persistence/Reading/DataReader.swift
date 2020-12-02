/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Synchronizes the work of `FileReader` on given read/write queue.
internal final class DataReader: Reader {
    /// Queue used to synchronize reads and writes for the feature.
    private let readWriteQueue: DispatchQueue
    private let fileReader: Reader

    init(readWriteQueue: DispatchQueue, fileReader: Reader) {
        self.readWriteQueue = readWriteQueue
        self.fileReader = fileReader
    }

    func readNextBatch() -> Batch? {
        readWriteQueue.sync {
            self.fileReader.readNextBatch()
        }
    }

    func markBatchAsRead(_ batch: Batch) {
        readWriteQueue.sync {
            self.fileReader.markBatchAsRead(batch)
        }
    }
}
