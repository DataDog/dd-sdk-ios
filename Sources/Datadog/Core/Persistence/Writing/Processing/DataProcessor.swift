/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal struct DataProcessorFactory {
    /// File writer writing unauthorized data when consent is `.pending`.
    let unauthorizedFileWriter: Writer
    /// File writer writing authorized data when consent is `.granted`.
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
/// It uses `EventMapper` to redact or drop data before it gets written.
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
