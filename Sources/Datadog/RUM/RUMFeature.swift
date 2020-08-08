/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Obtains a subdirectory in `/Library/Caches` for writting RUM events.
internal func obtainRUMFeatureDirectory() throws -> Directory {
    return try Directory(withSubdirectoryPath: "com.datadoghq.rum/v1")
}

/// Creates and owns componetns enabling RUM feature.
/// Bundles dependencies for other RUM-related components created later at runtime  (i.e. `RUMMonitor`).
internal final class RUMFeature {
    /// Single, shared instance of `RUMFeature`.
    internal static var instance: RUMFeature?

    // MARK: - Configuration

    let configuration: Datadog.ValidConfiguration

    // MARK: - Integration With Other Features

    /// Provides global RUM context for other features.
    var contextProvider: RUMContextProvider?

    // MARK: - Dependencies

    let dateProvider: DateProvider
    let userInfoProvider: UserInfoProvider
    let networkConnectionInfoProvider: NetworkConnectionInfoProviderType
    let carrierInfoProvider: CarrierInfoProviderType

    // MARK: - Components

    /// RUM files storage.
    let storage: Storage
    /// RUM upload worker.
    let upload: Upload

    /// Encapsulates  storage stack setup for `RUMFeature`.
    class Storage {
        /// Writes RUM events to files.
        let writer: FileWriter
        /// Reads RUM events from files.
        let reader: FileReader

        /// NOTE: any change to logs data format requires updating the RUM directory url to be unique
        static let dataFormat = DataFormat(prefix: "", suffix: "", separator: "\n")

        init(
            directory: Directory,
            performance: PerformancePreset,
            dateProvider: DateProvider,
            readWriteQueue: DispatchQueue
        ) {
            let orchestrator = FilesOrchestrator(
                directory: directory,
                performance: performance,
                dateProvider: dateProvider
            )

            self.writer = FileWriter(dataFormat: Storage.dataFormat, orchestrator: orchestrator, queue: readWriteQueue)
            self.reader = FileReader(dataFormat: Storage.dataFormat, orchestrator: orchestrator, queue: readWriteQueue)
        }
    }

    /// Encapsulates upload stack setup for `RUMFeature`.
    class Upload {
        /// Uploads RUM events to server.
        let uploader: DataUploadWorker

        init(
            storage: Storage,
            configuration: Datadog.ValidConfiguration,
            performance: PerformancePreset,
            mobileDevice: MobileDevice,
            httpClient: HTTPClient,
            dateProvider: DateProvider,
            networkConnectionInfoProvider: NetworkConnectionInfoProviderType,
            uploadQueue: DispatchQueue
        ) {
            let httpHeaders = HTTPHeaders(
                headers: [
                    .contentTypeHeader(contentType: .textPlainUTF8),
                    .userAgentHeader(
                        appName: configuration.applicationName,
                        appVersion: configuration.applicationVersion,
                        device: mobileDevice
                    )
                ]
            )
            let uploadConditions = DataUploadConditions(
                batteryStatus: BatteryStatusProvider(mobileDevice: mobileDevice),
                networkConnectionInfo: networkConnectionInfoProvider
            )

            let dataUploader = DataUploader(
                urlProvider: UploadURLProvider(
                    urlWithClientToken: configuration.rumUploadURLWithClientToken,
                    queryItemProviders: [
                        .ddsource(),
                        .batchTime(using: dateProvider),
                        .ddtags(
                            tags: [
                                "service:\(configuration.serviceName)",
                                "version:\(configuration.applicationVersion)",
                                "sdk_version:\(sdkVersion)",
                                "env:\(configuration.environment)"
                            ]
                        )
                    ]
                ),
                httpClient: httpClient,
                httpHeaders: httpHeaders
            )

            self.uploader = DataUploadWorker(
                queue: uploadQueue,
                fileReader: storage.reader,
                dataUploader: dataUploader,
                uploadConditions: uploadConditions,
                delay: DataUploadDelay(performance: performance),
                featureName: "RUM"
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
        let readWriteQueue = DispatchQueue(
            label: "com.datadoghq.ios-sdk-rum-read-write",
            target: .global(qos: .utility)
        )
        self.storage = Storage(
            directory: directory,
            performance: performance,
            dateProvider: dateProvider,
            readWriteQueue: readWriteQueue
        )

        let uploadQueue = DispatchQueue(
            label: "com.datadoghq.ios-sdk-rum-upload",
            target: .global(qos: .utility)
        )
        self.upload = Upload(
            storage: self.storage,
            configuration: configuration,
            performance: performance,
            mobileDevice: mobileDevice,
            httpClient: httpClient,
            dateProvider: dateProvider,
            networkConnectionInfoProvider: networkConnectionInfoProvider,
            uploadQueue: uploadQueue
        )
    }
}
