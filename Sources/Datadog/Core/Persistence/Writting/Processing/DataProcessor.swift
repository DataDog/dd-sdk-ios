/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Data scrubbing interface.
/// It takes an `event` and returns its modified representation or `nil` (for dropping the event).
internal protocol EventMapper {
    func map<T: Encodable>(event: T) -> T?
}

internal struct DataProcessorFactory {
    /// File writer writting unauthorized data when consent is `.pending`.
    let unauthorizedFileWriter: Writer
    /// File writer writting authorized data when consent is `.granted`.
    let authorizedFileWriter: Writer

    func resolveProcessor(for consent: TrackingConsent) -> DataProcessor? {
        switch consent {
        case .granted: return DataProcessor(fileWriter: authorizedFileWriter)
        case .notGranted: return nil
        case .pending: return DataProcessor(fileWriter: unauthorizedFileWriter)
        }
    }
}

/// The processing pipeline for writing data.
internal final class DataProcessor: Writer {
    private let fileWriter: Writer

    init(fileWriter: Writer) {
        self.fileWriter = fileWriter
    }

    // MARK: - Writer

    func write<T>(value: T) where T: Encodable {
        fileWriter.write(value: value)
    }
}
