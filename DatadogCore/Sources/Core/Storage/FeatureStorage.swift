/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal struct FeatureStorage {
    /// The name of this Feature, used to distinguish storage instances in telemetry and logs.
    let featureName: String
    /// Queue for performing all I/O operations (writes, reads and files management).
    let queue: DispatchQueue
    /// Directories for managing data in this Feature.
    let directories: FeatureDirectories
    /// Orchestrates files collected in `.granted` consent.
    let authorizedFilesOrchestrator: FilesOrchestratorType
    /// Orchestrates files collected in `.pending` consent.
    let unauthorizedFilesOrchestrator: FilesOrchestratorType
    /// Encryption algorithm applied to persisted data.
    let encryption: DataEncryption?
    /// Telemetry interface.
    let telemetry: Telemetry

    func writer(for trackingConsent: TrackingConsent, forceNewBatch: Bool) -> Writer {
        switch trackingConsent {
        case .granted:
            return AsyncWriter(
                execute: FileWriter(
                    orchestrator: authorizedFilesOrchestrator,
                    forceNewFile: forceNewBatch,
                    encryption: encryption,
                    telemetry: telemetry
                ),
                on: queue
            )
        case .notGranted:
            return NOPWriter()
        case .pending:
            return AsyncWriter(
                execute: FileWriter(
                    orchestrator: unauthorizedFilesOrchestrator,
                    forceNewFile: forceNewBatch,
                    encryption: encryption,
                    telemetry: telemetry
                ),
                on: queue
            )
        }
    }

    var reader: Reader {
        DataReader(
            readWriteQueue: queue,
            fileReader: FileReader(
                orchestrator: authorizedFilesOrchestrator,
                encryption: encryption,
                telemetry: telemetry
            )
        )
    }

    func migrateUnauthorizedData(toConsent consent: TrackingConsent) {
        queue.async {
            do {
                switch consent {
                case .notGranted:
                    try directories.unauthorized.deleteAllFiles()
                case .granted:
                    try directories.unauthorized.moveAllFiles(to: directories.authorized)
                case .pending:
                    break
                }
            } catch {
                telemetry.error(
                    "Failed to migrate unauthorized data in \(featureName) after consent change to to \(consent)",
                    error: error
                )
            }
        }
    }

    func clearUnauthorizedData() {
        queue.async {
            do {
                try directories.unauthorized.deleteAllFiles()
            } catch {
                telemetry.error("Failed clear unauthorized data in \(featureName)", error: error)
            }
        }
    }

    func clearAllData() {
        queue.async {
            do {
                try directories.unauthorized.deleteAllFiles()
                try directories.authorized.deleteAllFiles()
            } catch {
                telemetry.error("Failed clear all data in \(featureName)", error: error)
            }
        }
    }

    func setIgnoreFilesAgeWhenReading(to value: Bool) {
        queue.sync {
            authorizedFilesOrchestrator.ignoreFilesAgeWhenReading = value
            unauthorizedFilesOrchestrator.ignoreFilesAgeWhenReading = value
        }
    }
}

extension FeatureStorage {
    init(
        featureName: String,
        contextProvider: DatadogContextProvider,
        queue: DispatchQueue,
        directories: FeatureDirectories,
        dateProvider: DateProvider,
        performance: PerformancePreset,
        encryption: DataEncryption?,
        telemetry: Telemetry
    ) {
        let authorizedFilesOrchestrator = FilesOrchestrator(
            directory: directories.authorized,
            performance: performance,
            dateProvider: dateProvider,
            contextProvider: contextProvider,
            telemetry: telemetry,
            metricsData: {
                guard let trackName = BatchMetric.trackValue(for: featureName) else {
                    DD.logger.error("Can't determine track name for feature named '\(featureName)'")
                    return nil
                }
                return FilesOrchestrator.MetricsData(trackName: trackName, uploaderPerformance: performance)
            }()
        )
        let unauthorizedFilesOrchestrator = FilesOrchestrator(
            directory: directories.unauthorized,
            performance: performance,
            dateProvider: dateProvider,
            contextProvider: contextProvider,
            telemetry: telemetry,
            metricsData: nil // do not send metrics for unauthorized orchestrator
        )

        self.init(
            featureName: featureName,
            queue: queue,
            directories: directories,
            authorizedFilesOrchestrator: authorizedFilesOrchestrator,
            unauthorizedFilesOrchestrator: unauthorizedFilesOrchestrator,
            encryption: encryption,
            telemetry: telemetry
        )
    }
}
