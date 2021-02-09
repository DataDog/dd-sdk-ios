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
    /// Event mapper performing eventual modification (or dropping) the event before it gets written.
    /// It may be `nil` if not available for this feature.
    let eventMapper: EventMapper?

    func resolveProcessor(for consent: TrackingConsent) -> DataProcessor? {
        switch consent {
        case .granted: return DataProcessor(fileWriter: authorizedFileWriter, eventMapper: eventMapper)
        case .notGranted: return nil
        case .pending: return DataProcessor(fileWriter: unauthorizedFileWriter, eventMapper: eventMapper)
        }
    }
}

/// The processing pipeline for writing data.
/// It uses `EventMapper` to redact or drop data before it gets written.
internal final class DataProcessor: Writer {
    private let fileWriter: Writer
    private let eventMapper: EventMapper?

    init(fileWriter: Writer, eventMapper: EventMapper?) {
        self.fileWriter = fileWriter
        self.eventMapper = eventMapper
    }

    // MARK: - Writer

    func write<T>(value: T) where T: Encodable {
        if let eventMapper = eventMapper {
            if let mappedValue = eventMapper.map(event: value) {
                fileWriter.write(value: mappedValue)
            }
        } else {
            fileWriter.write(value: value)
        }
    }
}
