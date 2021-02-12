/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Writes data to single folder, regardless of the value of `TrackingConsent`.
/// It synchronizes the work of underlying `FileWriter` on given read/write queue.
internal class ArbitraryDataWriter: Writer {
    /// Queue used to synchronize reads and writes for the feature.
    internal let readWriteQueue: DispatchQueue
    /// Data processor for used to process & write data.
    private let dataProcessor: DataProcessor

    init(
        readWriteQueue: DispatchQueue,
        dataProcessor: DataProcessor
    ) {
        self.readWriteQueue = readWriteQueue
        self.dataProcessor = dataProcessor
    }

    // MARK: - Writer

    func write<T>(value: T) where T: Encodable {
        readWriteQueue.async {
            self.dataProcessor.write(value: value)
        }
    }
}
