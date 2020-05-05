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
/// Bundles dependencies for other tracing-related components created later at runtime  (i.e. `DDTracer`).
internal final class TracingFeature {
    /// Single, shared instance of `TracingFeatureFeature`.
    internal static var instance: TracingFeature?

    // MARK: - Dependencies

    let appContext: AppContext
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
            appContext: AppContext,
            performance: PerformancePreset,
            httpClient: HTTPClient,
            tracesUploadURLProvider: UploadURLProvider,
            networkConnectionInfoProvider: NetworkConnectionInfoProviderType,
            uploadQueue: DispatchQueue
        ) {
            let httpHeaders: HTTPHeaders
            let uploadConditions: DataUploadConditions

            if let mobileDevice = appContext.mobileDevice { // mobile device
                httpHeaders = HTTPHeaders(
                    headers: [
                        .contentTypeHeader(contentType: .textPlainUTF8),
                        .userAgentHeader(for: mobileDevice, appName: appContext.executableName, appVersion: appContext.bundleVersion)
                    ]
                )
                uploadConditions = DataUploadConditions(
                    batteryStatus: BatteryStatusProvider(mobileDevice: mobileDevice),
                    networkConnectionInfo: networkConnectionInfoProvider
                )
            } else { // other device (i.e. iOS Simulator)
                httpHeaders = HTTPHeaders(
                    headers: [
                        .contentTypeHeader(contentType: .textPlainUTF8)
                        // UA http header will default to the one produced by the OS
                    ]
                )
                uploadConditions = DataUploadConditions(
                    batteryStatus: nil, // uploads do not depend on battery status
                    networkConnectionInfo: networkConnectionInfoProvider
                )
            }

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
        appContext: AppContext,
        performance: PerformancePreset,
        httpClient: HTTPClient,
        tracesUploadURLProvider: UploadURLProvider,
        dateProvider: DateProvider,
        tracingUUIDGenerator: TracingUUIDGenerator,
        userInfoProvider: UserInfoProvider,
        networkConnectionInfoProvider: NetworkConnectionInfoProviderType,
        carrierInfoProvider: CarrierInfoProviderType
    ) {
        // Bundle dependencies
        self.appContext = appContext
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
            appContext: appContext,
            performance: performance,
            httpClient: httpClient,
            tracesUploadURLProvider: tracesUploadURLProvider,
            networkConnectionInfoProvider: networkConnectionInfoProvider,
            uploadQueue: uploadQueue
        )
    }
}
