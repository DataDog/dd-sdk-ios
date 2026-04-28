/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */
import Foundation

class TimeseriesBatcher {
    private let batchSize: Int
    private var buffer: [Sample] = []

    init(batchSize: Int = 30) {
        self.batchSize = batchSize
    }

    func add(_ sample: Sample) {
        buffer.append(sample)
    }

    func shouldFlush() -> Bool {
        buffer.count >= batchSize
    }

    func flush() -> [Sample] {
        let batch = buffer
        buffer = []
        return batch
    }

    func flushRemaining() -> [Sample]? {
        guard !buffer.isEmpty else { return nil }
        return flush()
    }
}
