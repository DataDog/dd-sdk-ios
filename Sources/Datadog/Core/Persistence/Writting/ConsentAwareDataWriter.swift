/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Writes data to different folders depending on the tracking consent value.
/// It synchronizes the work of underlying `FileWriters` on given read/write queue.
internal class ConsentAwareDataWriter: Writer, ConsentSubscriber {
    /// Queue used to synchronize reads and writes for the feature.
    internal let readWriteQueue: DispatchQueue
    /// File writer writting unauthorized data when consent is `.pending`.
    private let unauthorizedFileWriter: Writer
    /// File writer writting authorized data when consent is `.granted`.
    private let authorizedFileWriter: Writer

    /// File writer for current consent value (including `nil` if consent is `.notGranted`).
    private var activeFileWriter: Writer?

    init(
        consentProvider: ConsentProvider,
        readWriteQueue: DispatchQueue,
        unauthorizedFileWriter: Writer,
        authorizedFileWriter: Writer
    ) {
        self.readWriteQueue = readWriteQueue
        self.unauthorizedFileWriter = unauthorizedFileWriter
        self.authorizedFileWriter = authorizedFileWriter
        self.activeFileWriter = resolveActiveFileWriter(
            for: consentProvider.currentValue,
            unauthorizedWriter: unauthorizedFileWriter,
            authorizedWriter: authorizedFileWriter
        )

        consentProvider.subscribe(consentSubscriber: self)
    }

    // MARK: - Writer

    func write<T>(value: T) where T: Encodable {
        readWriteQueue.async {
            self.activeFileWriter?.write(value: value)
        }
    }

    // MARK: - ConsentSubscriber

    func consentChanged(from oldValue: TrackingConsent, to newValue: TrackingConsent) {
        readWriteQueue.async {
            self.activeFileWriter = resolveActiveFileWriter(
                for: newValue,
                unauthorizedWriter: self.unauthorizedFileWriter,
                authorizedWriter: self.authorizedFileWriter
            )
        }
    }
}

// TODO: RUMM-831 Move writer resolution to `DataProcessorFactory`
private func resolveActiveFileWriter(
    for consent: TrackingConsent,
    unauthorizedWriter: Writer,
    authorizedWriter: Writer
) -> Writer? {
    switch consent {
    case .granted: return authorizedWriter
    case .notGranted: return nil
    case .pending: return unauthorizedWriter
    }
}
