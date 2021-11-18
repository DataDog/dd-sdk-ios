/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Obtains subdirectories in `/Library/Caches` where tracing data is stored.
internal func obtainTracingFeatureDirectories() throws -> FeatureDirectories {
    let version = "v1"
    return FeatureDirectories(
        unauthorized: try Directory(withSubdirectoryPath: "com.datadoghq.traces/intermediate-\(version)"),
        authorized: try Directory(withSubdirectoryPath: "com.datadoghq.traces/\(version)")
    )
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
    let dateCorrector: DateCorrectorType
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

    static func createStorage(
        directories: FeatureDirectories,
        commonDependencies: FeaturesCommonDependencies,
        internalMonitor: InternalMonitor? = nil
    ) -> FeatureStorage {
        return FeatureStorage(
            featureName: TracingFeature.featureName,
            dataFormat: TracingFeature.dataFormat,
            directories: directories,
            commonDependencies: commonDependencies,
            internalMonitor: internalMonitor
        )
    }

    static func createUpload(
        storage: FeatureStorage,
        configuration: FeaturesConfiguration.Tracing,
        commonDependencies: FeaturesCommonDependencies,
        internalMonitor: InternalMonitor? = nil
    ) -> FeatureUpload {
        return FeatureUpload(
            featureName: TracingFeature.featureName,
            storage: storage,
            requestBuilder: RequestBuilder(
                url: configuration.uploadURL,
                queryItems: [],
                headers: [
                    .contentTypeHeader(contentType: .textPlainUTF8),
                    .userAgentHeader(
                        appName: configuration.common.applicationName,
                        appVersion: configuration.common.applicationVersion,
                        device: commonDependencies.mobileDevice
                    ),
                    .ddAPIKeyHeader(clientToken: configuration.clientToken),
                    .ddEVPOriginHeader(source: configuration.common.source),
                    .ddEVPOriginVersionHeader(sdkVersion: configuration.common.sdkVersion),
                    .ddRequestIDHeader(),
                ],
                internalMonitor: internalMonitor
            ),
            commonDependencies: commonDependencies,
            internalMonitor: internalMonitor
        )
    }

    convenience init(
        directories: FeatureDirectories,
        configuration: FeaturesConfiguration.Tracing,
        commonDependencies: FeaturesCommonDependencies,
        loggingFeatureAdapter: LoggingForTracingAdapter?,
        tracingUUIDGenerator: TracingUUIDGenerator,
        internalMonitor: InternalMonitor? = nil
    ) {
        let storage = TracingFeature.createStorage(
            directories: directories,
            commonDependencies: commonDependencies,
            internalMonitor: internalMonitor
        )
        let upload = TracingFeature.createUpload(
            storage: storage,
            configuration: configuration,
            commonDependencies: commonDependencies,
            internalMonitor: internalMonitor
        )
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
        self.dateCorrector = commonDependencies.dateCorrector
        self.tracingUUIDGenerator = tracingUUIDGenerator
        self.userInfoProvider = commonDependencies.userInfoProvider
        self.networkConnectionInfoProvider = commonDependencies.networkConnectionInfoProvider
        self.carrierInfoProvider = commonDependencies.carrierInfoProvider

        // Initialize stacks
        self.storage = storage
        self.upload = upload
    }

#if DD_SDK_COMPILED_FOR_TESTING
    func deinitialize() {
        storage.flushAndTearDown()
        upload.flushAndTearDown()
        TracingFeature.instance = nil
    }
#endif
}
