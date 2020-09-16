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

    /// Tells if the feature was enabled by the user in the SDK configuration.
    static var isEnabled: Bool { instance != nil }

    // MARK: - Configuration

    let configuration: FeaturesConfiguration.Tracing

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

    static let featureName = "tracing"
    /// NOTE: any change to data format requires updating the directory url to be unique
    static let dataFormat = DataFormat(prefix: "", suffix: "", separator: "\n")

    /// Span files storage.
    let storage: FeatureStorage
    /// Spans upload worker.
    let upload: FeatureUpload

    // MARK: - Initialization

    static func createStorage(directory: Directory, commonDependencies: FeaturesCommonDependencies) -> FeatureStorage {
        return FeatureStorage(
            featureName: TracingFeature.featureName,
            dataFormat: TracingFeature.dataFormat,
            directory: directory,
            commonDependencies: commonDependencies
        )
    }

    static func createUpload(
        storage: FeatureStorage,
        directory: Directory,
        configuration: FeaturesConfiguration.Tracing,
        commonDependencies: FeaturesCommonDependencies
    ) -> FeatureUpload {
        return FeatureUpload(
            featureName: TracingFeature.featureName,
            storage: storage,
            uploadHTTPHeaders: HTTPHeaders(
                headers: [
                    .contentTypeHeader(contentType: .textPlainUTF8),
                    .userAgentHeader(
                        appName: configuration.common.applicationName,
                        appVersion: configuration.common.applicationVersion,
                        device: commonDependencies.mobileDevice
                    )
                ]
            ),
            uploadURLProvider: UploadURLProvider(
                urlWithClientToken: configuration.uploadURLWithClientToken,
                queryItemProviders: [
                    .batchTime(using: commonDependencies.dateProvider)
                ]
            ),
            commonDependencies: commonDependencies
        )
    }

    convenience init(
        directory: Directory,
        configuration: FeaturesConfiguration.Tracing,
        commonDependencies: FeaturesCommonDependencies,
        loggingFeatureAdapter: LoggingForTracingAdapter?,
        tracingUUIDGenerator: TracingUUIDGenerator
    ) {
        let storage = TracingFeature.createStorage(directory: directory, commonDependencies: commonDependencies)
        let upload = TracingFeature.createUpload(storage: storage, directory: directory, configuration: configuration, commonDependencies: commonDependencies)
        self.init(
            storage: storage,
            upload: upload,
            configuration: configuration,
            commonDependencies: commonDependencies,
            loggingFeatureAdapter: loggingFeatureAdapter,
            tracingUUIDGenerator: tracingUUIDGenerator
        )
    }

    init(
        storage: FeatureStorage,
        upload: FeatureUpload,
        configuration: FeaturesConfiguration.Tracing,
        commonDependencies: FeaturesCommonDependencies,
        loggingFeatureAdapter: LoggingForTracingAdapter?,
        tracingUUIDGenerator: TracingUUIDGenerator
    ) {
        // Configuration
        self.configuration = configuration

        // Integration with other features
        self.loggingFeatureAdapter = loggingFeatureAdapter

        // Bundle dependencies
        self.dateProvider = commonDependencies.dateProvider
        self.tracingUUIDGenerator = tracingUUIDGenerator
        self.userInfoProvider = commonDependencies.userInfoProvider
        self.networkConnectionInfoProvider = commonDependencies.networkConnectionInfoProvider
        self.carrierInfoProvider = commonDependencies.carrierInfoProvider

        // Initialize stacks
        self.storage = storage
        self.upload = upload
    }
}
