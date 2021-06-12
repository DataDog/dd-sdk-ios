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
    /// Creates data processors depending on the tracking consent value.
    private let dataProcessorFactory: DataProcessorFactory
    /// Creates data migrators depending on the tracking consent transition.
    private let dataMigratorFactory: DataMigratorFactory

    /// Data processor for current tracking consent.
    private var processor: DataProcessor?

    init(
        consentProvider: ConsentProvider,
        readWriteQueue: DispatchQueue,
        dataProcessorFactory: DataProcessorFactory,
        dataMigratorFactory: DataMigratorFactory
    ) {
        self.queue = readWriteQueue
        self.dataProcessorFactory = dataProcessorFactory
        self.dataMigratorFactory = dataMigratorFactory
        self.processor = dataProcessorFactory.resolveProcessor(for: consentProvider.currentValue)

        consentProvider.subscribe(self)

        let initialDataMigrator = dataMigratorFactory.resolveInitialMigrator()
        readWriteQueue.async { initialDataMigrator.migrate() }
    }

    // MARK: - Writer

    func write<T>(value: T) where T: Encodable {
        queue.async {
            self.processor?.write(value: value)
        }
    }

    // MARK: - TrackingConsentObserver

    func onValueChanged(oldValue: TrackingConsent, newValue: TrackingConsent) {
        queue.async {
            #if DD_SDK_COMPILED_FOR_TESTING
            assert(!self.isCanceled, "Trying to change consent, but the writer is canceled.")
            #endif
            self.processor = self.dataProcessorFactory.resolveProcessor(for: newValue)
            self.dataMigratorFactory
                .resolveMigratorForConsentChange(from: oldValue, to: newValue)?
                .migrate()
        }
    }

#if DD_SDK_COMPILED_FOR_TESTING
    private var isCanceled = false

    func flushAndCancelSynchronously() {
        queue.sync {
            self.processor = nil
            self.isCanceled = true
        }
    }
#endif
}
