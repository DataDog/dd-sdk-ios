/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Obtains a subdirectory in `/Library/Caches` where span files are stored.
internal func obtainTracingFeatureDirectory() throws -> Directory {
    return try Directory(withSubdirectoryPath: "com.datadoghq.traces/v1")
}

/// Creates and owns componetns enabling tracing feature.
/// Bundles dependencies for other tracing-related components created later at runtime  (i.e. `Tracer`).
internal final class TracingFeature {
    /// Single, shared instance of `TracingFeatureFeature`.
    internal static var instance: TracingFeature?

    // MARK: - Configuration

    let configuration: Datadog.ValidConfiguration

    // MARK: - Integration With Other Features

    /// Integration with Logging feature, which enables the `span.log()` functionality.
    /// Equals `nil` if Logging feature is disabled.
    let loggingFeatureAdapter: LoggingForTracingAdapter?

    // MARK: - Dependencies

    let dateProvider: DateProvider
    let tracingUUIDGenerator: TracingUUIDGenerator
    let userInfoProvider: UserInfoProvider
    let networkConnectionInfoProvider: NetworkConnectionInfoProviderType
    let carrierInfoProvider: CarrierInfoProviderType

    // MARK: - Components

    /// Span files storage.
    let storage: Storage
    /// Spans upload worker.
    let upload: Upload

    /// Encapsulates  storage stack setup for `TracingFeature`.
    class Storage {
        /// Writes spans to files.
        let writer: FileWriter
        /// Reads spans from files.
        let reader: FileReader

        /// NOTE: any change to tracing data format requires updating the tracing directory url to be unique
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

    /// Encapsulates upload stack setup for `TracingFeature`.
    class Upload {
        /// Uploads spans to server.
        let uploader: DataUploadWorker

        init(
            storage: Storage,
            configuration: Datadog.ValidConfiguration,
            performance: PerformancePreset,
            mobileDevice: MobileDevice,
            httpClient: HTTPClient,
            tracesUploadURLProvider: UploadURLProvider,
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
                urlProvider: tracesUploadURLProvider,
                httpClient: httpClient,
                httpHeaders: httpHeaders
            )

            self.uploader = DataUploadWorker(
                queue: uploadQueue,
                fileReader: storage.reader,
                dataUploader: dataUploader,
                uploadConditions: uploadConditions,
                delay: DataUploadDelay(performance: performance),
                featureName: "tracing"
            )
        }
    }

    // MARK: - Initialization

    init(
        directory: Directory,
        configuration: Datadog.ValidConfiguration,
        performance: PerformancePreset,
        loggingFeatureAdapter: LoggingForTracingAdapter?,
        mobileDevice: MobileDevice,
        httpClient: HTTPClient,
        tracesUploadURLProvider: UploadURLProvider,
        dateProvider: DateProvider,
        tracingUUIDGenerator: TracingUUIDGenerator,
        userInfoProvider: UserInfoProvider,
        networkConnectionInfoProvider: NetworkConnectionInfoProviderType,
        carrierInfoProvider: CarrierInfoProviderType
    ) {
        // Configuration
        self.configuration = configuration

        // Integration with other features
        self.loggingFeatureAdapter = loggingFeatureAdapter

        // Bundle dependencies
        self.dateProvider = dateProvider
        self.tracingUUIDGenerator = tracingUUIDGenerator
        self.userInfoProvider = userInfoProvider
        self.networkConnectionInfoProvider = networkConnectionInfoProvider
        self.carrierInfoProvider = carrierInfoProvider

        // Initialize components
        let readWriteQueue = DispatchQueue(
            label: "com.datadoghq.ios-sdk-spans-read-write",
            target: .global(qos: .utility)
        )
        self.storage = Storage(
            directory: directory,
            performance: performance,
            dateProvider: dateProvider,
            readWriteQueue: readWriteQueue
        )

        let uploadQueue = DispatchQueue(
            label: "com.datadoghq.ios-sdk-spans-upload",
            target: .global(qos: .utility)
        )
        self.upload = Upload(
            storage: self.storage,
            configuration: configuration,
            performance: performance,
            mobileDevice: mobileDevice,
            httpClient: httpClient,
            tracesUploadURLProvider: tracesUploadURLProvider,
            networkConnectionInfoProvider: networkConnectionInfoProvider,
            uploadQueue: uploadQueue
        )
    }
}
