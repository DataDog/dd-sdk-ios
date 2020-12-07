/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// File writer which writes data to different folders depending on the tracking consent value.
internal class ConsentAwareDataWriter: FileWriterType, ConsentSubscriber {
    /// Queue used to synchronize reads and writes for the feature.
    /// TODO: RUMM-832 will be used to synchornize data migration with reads and writes.
    internal let queue: DispatchQueue
    /// File writer writting unauthorized data when consent is `.pending`.
    private let unauthorizedFileWriter: FileWriterType
    /// File writer writting authorized data when consent is `.granted`.
    private let authorizedFileWriter: FileWriterType

    /// File writer for current consent value (including `nil` if consent is `.notGranted`).
    private var activeFileWriter: FileWriterType?

    init(
        consentProvider: ConsentProvider,
        queue: DispatchQueue,
        unauthorizedFileWriter: FileWriterType,
        authorizedFileWriter: FileWriterType
    ) {
        self.queue = queue
        self.unauthorizedFileWriter = unauthorizedFileWriter
        self.authorizedFileWriter = authorizedFileWriter
        self.activeFileWriter = resolveActiveFileWriter(
            for: consentProvider.currentValue,
            unauthorizedWriter: unauthorizedFileWriter,
            authorizedWriter: authorizedFileWriter
        )

        consentProvider.subscribe(consentSubscriber: self)
    }

    // MARK: - FileWriterType

    func write<T>(value: T) where T: Encodable {
        synchronized {
            activeFileWriter?.write(value: value)
        }
    }

    // MARK: - ConsentSubscriber

    func consentChanged(from oldValue: TrackingConsent, to newValue: TrackingConsent) {
        synchronized {
            activeFileWriter = resolveActiveFileWriter(
                for: newValue,
                unauthorizedWriter: unauthorizedFileWriter,
                authorizedWriter: authorizedFileWriter
            )
        }
    }

    // MARK: - Private

    private func synchronized(block: () -> Void) {
        objc_sync_enter(self)
        block()
        objc_sync_exit(self)
    }
}

// TODO: RUMM-831 Move writer resolution to `DataProcessorFactory`
private func resolveActiveFileWriter(
    for consent: TrackingConsent,
    unauthorizedWriter: FileWriterType,
    authorizedWriter: FileWriterType
) -> FileWriterType? {
    switch consent {
    case .granted: return authorizedWriter
    case .notGranted: return nil
    case .pending: return unauthorizedWriter
    }
}
