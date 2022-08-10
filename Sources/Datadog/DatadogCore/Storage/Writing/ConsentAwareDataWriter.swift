/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Writes data to different folders depending on current the value of the `TrackingConsent`.
/// When the value of `TrackingConsent` changes, it may move data from unauthorized folder to the authorized one or wipe it out entirely.
/// It synchronizes the work of underlying `FileWriters` on given read/write queue.
internal class ConsentAwareDataWriter: AsyncWriter, TrackingConsentObserver {
    /// Queue used to synchronize reads and writes for the feature.
    internal let queue: DispatchQueue
    /// Creates data migrators depending on the tracking consent transition.
    private let dataMigratorFactory: DataMigratorFactory
    /// File writer writing unauthorized data when consent is `.pending`.
    let unauthorizedWriter: Writer
    /// File writer writing authorized data when consent is `.granted`.
    let authorizedWriter: Writer
    /// Data writer for current tracking consent.
    private var currentWriter: Writer?

    init(
        consentProvider: ConsentProvider,
        readWriteQueue: DispatchQueue,
        unauthorizedWriter: Writer,
        authorizedWriter: Writer,
        dataMigratorFactory: DataMigratorFactory
    ) {
        self.queue = readWriteQueue
        self.unauthorizedWriter = unauthorizedWriter
        self.authorizedWriter = authorizedWriter
        self.dataMigratorFactory = dataMigratorFactory

        resolveWriter(for: consentProvider.currentValue)
        consentProvider.subscribe(self)

        let initialDataMigrator = dataMigratorFactory.resolveInitialMigrator()
        readWriteQueue.async { initialDataMigrator.migrate() }
    }

    // MARK: - Writer

    func write<T>(value: T) where T: Encodable {
        queue.async {
            self.currentWriter?.write(value: value)
        }
    }

    // MARK: - TrackingConsentObserver

    func onValueChanged(oldValue: TrackingConsent, newValue: TrackingConsent) {
        queue.async {
            #if DD_SDK_COMPILED_FOR_TESTING
            assert(!self.isCanceled, "Trying to change consent, but the writer is canceled.")
            #endif
            self.resolveWriter(for: newValue)
            self.dataMigratorFactory
                .resolveMigratorForConsentChange(from: oldValue, to: newValue)?
                .migrate()
        }
    }

    private func resolveWriter(for consent: TrackingConsent) {
        switch consent {
        case .granted: currentWriter = authorizedWriter
        case .notGranted: currentWriter = nil
        case .pending: currentWriter = unauthorizedWriter
        }
    }

    private var isCanceled = false

    internal func flushAndCancelSynchronously() {
        queue.sync {
            self.currentWriter = nil
            self.isCanceled = true
        }
    }
}
