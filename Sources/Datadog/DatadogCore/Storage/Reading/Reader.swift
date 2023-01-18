/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

internal struct Batch {
    let events: [Data]
    /// File from which `data` was read.
    let file: ReadableFile
}

/// A type, reading batched data.
internal protocol Reader {
    func readNextBatch() -> Batch?
    func markBatchAsRead(_ batch: Batch)
}
