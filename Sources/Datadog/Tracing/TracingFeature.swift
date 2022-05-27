/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Obtains subdirectories in `/Library/Caches` where tracing data is stored.
internal func obtainTracingFeatureDirectories() throws -> FeatureDirectories {
    var version = "v1"
    let deprecated = [
        try Directory(withSubdirectoryPath: "com.datadoghq.traces/intermediate-\(version)"),
        try Directory(withSubdirectoryPath: "com.datadoghq.traces/\(version)")
    ]

    version = "v2"
    return FeatureDirectories(
        deprecated: deprecated,
        unauthorized: try Directory(withSubdirectoryPath: "com.datadoghq.traces/intermediate-\(version)"),
        authorized: try Directory(withSubdirectoryPath: "com.datadoghq.traces/\(version)")
    )
}

/// Creates and owns componetns enabling tracing feature.
/// Bundles dependencies for other tracing-related components created later at runtime  (i.e. `Tracer`).
internal final class TracingFeature {
    // MARK: - Configuration

    let configuration: FeaturesConfiguration.Tracing

    // MARK: - Dependencies

    let dateProvider: DateProvider
    let dateCorrector: DateCorrectorType
    let tracingUUIDGenerator: TracingUUIDGenerator
    let userInfoProvider: UserInfoProvider
    let networkConnectionInfoProvider: NetworkConnectionInfoProviderType
    let carrierInfoProvider: CarrierInfoProviderType
    let telemetry: Telemetry?

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
        telemetry: Telemetry?
    ) -> FeatureStorage {
        return FeatureStorage(
            featureName: TracingFeature.featureName,
            dataFormat: TracingFeature.dataFormat,
            directories: directories,
            commonDependencies: commonDependencies,
            telemetry: telemetry
        )
    }

    static func createUpload(
        storage: FeatureStorage,
        configuration: FeaturesConfiguration.Tracing,
        commonDependencies: FeaturesCommonDependencies,
        telemetry: Telemetry?
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
                    .ddAPIKeyHeader(clientToken: configuration.common.clientToken),
                    .ddEVPOriginHeader(source: configuration.common.origin ?? configuration.common.source),
                    .ddEVPOriginVersionHeader(sdkVersion: configuration.common.sdkVersion),
                    .ddRequestIDHeader(),
                ],
                telemetry: telemetry
            ),
            commonDependencies: commonDependencies,
            telemetry: telemetry
        )
    }

    convenience init(
        directories: FeatureDirectories,
        configuration: FeaturesConfiguration.Tracing,
        commonDependencies: FeaturesCommonDependencies,
        telemetry: Telemetry?
    ) {
        let storage = TracingFeature.createStorage(
            directories: directories,
            commonDependencies: commonDependencies,
            telemetry: telemetry
        )
        let upload = TracingFeature.createUpload(
            storage: storage,
            configuration: configuration,
            commonDependencies: commonDependencies,
            telemetry: telemetry
        )
        self.init(
            storage: storage,
            upload: upload,
            configuration: configuration,
            commonDependencies: commonDependencies,
            telemetry: telemetry
        )
    }

    init(
        storage: FeatureStorage,
        upload: FeatureUpload,
        configuration: FeaturesConfiguration.Tracing,
        commonDependencies: FeaturesCommonDependencies,
        telemetry: Telemetry?
    ) {
        // Configuration
        self.configuration = configuration

        // Bundle dependencies
        self.dateProvider = commonDependencies.dateProvider
        self.dateCorrector = commonDependencies.dateCorrector
        self.tracingUUIDGenerator = configuration.uuidGenerator
        self.userInfoProvider = commonDependencies.userInfoProvider
        self.networkConnectionInfoProvider = commonDependencies.networkConnectionInfoProvider
        self.carrierInfoProvider = commonDependencies.carrierInfoProvider
        self.telemetry = telemetry

        // Initialize stacks
        self.storage = storage
        self.upload = upload
    }

    internal func deinitialize() {
        storage.flushAndTearDown()
        upload.flushAndTearDown()
    }
}
