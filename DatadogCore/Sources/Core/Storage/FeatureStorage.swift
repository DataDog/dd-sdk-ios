/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Actor that manages file storage for a single SDK feature.
///
/// Each feature has its own actor-isolated storage, eliminating cross-feature contention.
/// Writers are cached (one per consent directory) so that a single `AsyncStream` + drain
/// `Task` handles all writes for each consent level, instead of allocating a new pair on
/// every event write.
internal actor FeatureStorage {
    /// The name of this Feature, used to distinguish storage instances in telemetry and logs.
    nonisolated let featureName: String
    /// Directories for managing data in this Feature.
    nonisolated let directories: FeatureDirectories
    /// Orchestrates files collected in `.granted` consent.
    nonisolated let authorizedFilesOrchestrator: FilesOrchestratorType
    /// Orchestrates files collected in `.pending` consent.
    nonisolated let unauthorizedFilesOrchestrator: FilesOrchestratorType
    /// Encryption algorithm applied to persisted data.
    nonisolated let encryption: DataEncryption?
    /// Telemetry interface.
    nonisolated let telemetry: Telemetry

    /// Cached writer for `.granted` consent (writes to authorized directory).
    private lazy var authorizedWriter = FileWriter(
        orchestrator: authorizedFilesOrchestrator,
        encryption: encryption,
        telemetry: telemetry
    )

    /// Cached writer for `.pending` consent (writes to unauthorized directory).
    private lazy var unauthorizedWriter = FileWriter(
        orchestrator: unauthorizedFilesOrchestrator,
        encryption: encryption,
        telemetry: telemetry
    )

    init(
        featureName: String,
        directories: FeatureDirectories,
        authorizedFilesOrchestrator: FilesOrchestratorType,
        unauthorizedFilesOrchestrator: FilesOrchestratorType,
        encryption: DataEncryption?,
        telemetry: Telemetry
    ) {
        self.featureName = featureName
        self.directories = directories
        self.authorizedFilesOrchestrator = authorizedFilesOrchestrator
        self.unauthorizedFilesOrchestrator = unauthorizedFilesOrchestrator
        self.encryption = encryption
        self.telemetry = telemetry
    }

    func writer(for trackingConsent: TrackingConsent) -> Writer {
        switch trackingConsent {
        case .granted:
            return authorizedWriter
        case .notGranted:
            return NOPWriter()
        case .pending:
            return unauthorizedWriter
        }
    }

    nonisolated var reader: Reader {
        FileReader(
            orchestrator: authorizedFilesOrchestrator,
            encryption: encryption,
            telemetry: telemetry
        )
    }

    func migrateUnauthorizedData(toConsent consent: TrackingConsent) {
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

    func clearUnauthorizedData() {
        do {
            try directories.unauthorized.deleteAllFiles()
        } catch {
            telemetry.error("Failed clear unauthorized data in \(featureName)", error: error)
        }
    }

    func clearAllData() {
        do {
            try directories.unauthorized.deleteAllFiles()
            try directories.authorized.deleteAllFiles()
        } catch {
            telemetry.error("Failed clear all data in \(featureName)", error: error)
        }
    }

    func setIgnoreFilesAgeWhenReading(to value: Bool) async {
        await authorizedFilesOrchestrator.setIgnoreFilesAgeWhenReading(value)
        await unauthorizedFilesOrchestrator.setIgnoreFilesAgeWhenReading(value)
    }
}

extension FeatureStorage {
    init(
        featureName: String,
        directories: FeatureDirectories,
        dateProvider: DateProvider,
        performance: PerformancePreset,
        encryption: DataEncryption?,
        backgroundTasksEnabled: Bool,
        telemetry: Telemetry
    ) {
        let trackName = BatchMetric.trackValue(for: featureName)

        if trackName == nil {
            DD.logger.error("Can't determine track name for feature named '\(featureName)'")
        }

        let authorizedFilesOrchestrator = FilesOrchestrator(
            directory: directories.authorized,
            performance: performance,
            dateProvider: dateProvider,
            telemetry: telemetry,
            metricsData: trackName.map { trackName in
                return FilesOrchestrator.MetricsData(
                    trackName: trackName,
                    consentLabel: BatchMetric.consentGrantedValue,
                    uploaderPerformance: performance,
                    backgroundTasksEnabled: backgroundTasksEnabled
                )
            }
        )
        let unauthorizedFilesOrchestrator = FilesOrchestrator(
            directory: directories.unauthorized,
            performance: performance,
            dateProvider: dateProvider,
            telemetry: telemetry,
            metricsData: trackName.map { trackName in
                return FilesOrchestrator.MetricsData(
                    trackName: trackName,
                    consentLabel: BatchMetric.consentPendingValue,
                    uploaderPerformance: performance,
                    backgroundTasksEnabled: backgroundTasksEnabled
                )
            }
        )

        self.init(
            featureName: featureName,
            directories: directories,
            authorizedFilesOrchestrator: authorizedFilesOrchestrator,
            unauthorizedFilesOrchestrator: unauthorizedFilesOrchestrator,
            encryption: encryption,
            telemetry: telemetry
        )
    }
}
