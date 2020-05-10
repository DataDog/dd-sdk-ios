/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Obtains a subdirectory in `/Library/Caches` where log files are stored.
internal func obtainLoggingFeatureDirectory() throws -> Directory {
    return try Directory(withSubdirectoryPath: "com.datadoghq.logs/v1")
}

/// Creates and owns componetns enabling logging feature.
/// Bundles dependencies for other logging-related components created later at runtime  (i.e. `Logger`).
internal final class LoggingFeature {
    /// Single, shared instance of `LoggingFeature`.
    internal static var instance: LoggingFeature?

    // MARK: - Configuration

    let configuration: Datadog.ValidConfiguration

    // MARK: - Dependencies

    let dateProvider: DateProvider
    let userInfoProvider: UserInfoProvider
    let networkConnectionInfoProvider: NetworkConnectionInfoProviderType
    let carrierInfoProvider: CarrierInfoProviderType

    // MARK: - Components

    /// Log files storage.
    let storage: Storage
    /// Logs upload worker.
    let upload: Upload

    /// Encapsulates  storage stack setup for `LoggingFeature`.
    class Storage {
        /// Writes logs to files.
        let writer: FileWriter
        /// Reads logs from files.
        let reader: FileReader

        init(
            directory: Directory,
            performance: PerformancePreset,
            dateProvider: DateProvider
        ) {
            let readWriteQueue = DispatchQueue(
                label: "com.datadoghq.ios-sdk-logs-read-write",
                target: .global(qos: .utility)
            )
            let orchestrator = FilesOrchestrator(
                directory: directory,
                writeConditions: WritableFileConditions(performance: performance),
                readConditions: ReadableFileConditions(performance: performance),
                dateProvider: dateProvider
            )

            self.writer = FileWriter(orchestrator: orchestrator, queue: readWriteQueue)
            self.reader = FileReader(orchestrator: orchestrator, queue: readWriteQueue)
        }
    }

    /// Encapsulates upload stack setup for `LoggingFeature`.
    class Upload {
        /// Uploads logs server.
        let uploader: DataUploadWorker

        init(
            storage: Storage,
            configuration: Datadog.ValidConfiguration,
            performance: PerformancePreset,
            mobileDevice: MobileDevice,
            httpClient: HTTPClient,
            logsUploadURLProvider: UploadURLProvider,
            networkConnectionInfoProvider: NetworkConnectionInfoProviderType
        ) {
            let dataUploader = DataUploader(
                urlProvider: logsUploadURLProvider,
                httpClient: httpClient,
                httpHeaders: HTTPHeaders(
                    appName: configuration.applicationName,
                    appVersion: configuration.applicationVersion,
                    device: mobileDevice
                )
            )

            let uploadQueue = DispatchQueue(
                label: "com.datadoghq.ios-sdk-logs-upload",
                target: .global(qos: .utility)
            )

            let uploadConditions = DataUploadConditions(
                batteryStatus: BatteryStatusProvider(mobileDevice: mobileDevice),
                networkConnectionInfo: networkConnectionInfoProvider
            )

            self.uploader = DataUploadWorker(
                queue: uploadQueue,
                fileReader: storage.reader,
                dataUploader: dataUploader,
                uploadConditions: uploadConditions,
                delay: DataUploadDelay(performance: performance)
            )
        }
    }

    // MARK: - Initialization

    init(
        directory: Directory,
        configuration: Datadog.ValidConfiguration,
        performance: PerformancePreset,
        mobileDevice: MobileDevice,
        httpClient: HTTPClient,
        logsUploadURLProvider: UploadURLProvider,
        dateProvider: DateProvider,
        userInfoProvider: UserInfoProvider,
        networkConnectionInfoProvider: NetworkConnectionInfoProviderType,
        carrierInfoProvider: CarrierInfoProviderType
    ) {
        // Configuration
        self.configuration = configuration

        // Bundle dependencies
        self.dateProvider = dateProvider
        self.userInfoProvider = userInfoProvider
        self.networkConnectionInfoProvider = networkConnectionInfoProvider
        self.carrierInfoProvider = carrierInfoProvider

        // Initialize components
        self.storage = Storage(
            directory: directory,
            performance: performance,
            dateProvider: dateProvider
        )
        self.upload = Upload(
            storage: self.storage,
            configuration: configuration,
            performance: performance,
            mobileDevice: mobileDevice,
            httpClient: httpClient,
            logsUploadURLProvider: logsUploadURLProvider,
            networkConnectionInfoProvider: networkConnectionInfoProvider
        )
    }
}
