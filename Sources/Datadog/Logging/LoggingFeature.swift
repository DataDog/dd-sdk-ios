/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Obtains subdirectories in `/Library/Caches` where logging data is stored.
internal func obtainLoggingFeatureDirectories() throws -> FeatureDirectories {
    var version = "v1"
    let deprecated = [
        try Directory(withSubdirectoryPath: "com.datadoghq.logs/intermediate-\(version)"),
        try Directory(withSubdirectoryPath: "com.datadoghq.logs/\(version)")
    ]

    version = "v2"
    return FeatureDirectories(
        deprecated: deprecated,
        unauthorized: try Directory(withSubdirectoryPath: "com.datadoghq.logs/intermediate-\(version)"),
        authorized: try Directory(withSubdirectoryPath: "com.datadoghq.logs/\(version)")
    )
}

/// Creates and owns componetns enabling logging feature.
/// Bundles dependencies for other logging-related components created later at runtime  (i.e. `Logger`).
internal final class LoggingFeature {
    // MARK: - Configuration

    let configuration: FeaturesConfiguration.Logging

    // MARK: - Dependencies

    let dateProvider: DateProvider
    let dateCorrector: DateCorrectorType
    let userInfoProvider: UserInfoProvider
    let networkConnectionInfoProvider: NetworkConnectionInfoProviderType
    let carrierInfoProvider: CarrierInfoProviderType

    // MARK: - Components

    static let featureName = "logging"
    /// NOTE: any change to data format requires updating the directory url to be unique
    static let dataFormat = DataFormat(prefix: "[", suffix: "]", separator: ",")

    /// Log files storage.
    let storage: FeatureStorage
    /// Logs upload worker.
    let upload: FeatureUpload

    // MARK: - Initialization

    static func createStorage(
        directories: FeatureDirectories,
        commonDependencies: FeaturesCommonDependencies,
        telemetry: Telemetry?
    ) -> FeatureStorage {
        return FeatureStorage(
            featureName: LoggingFeature.featureName,
            dataFormat: LoggingFeature.dataFormat,
            directories: directories,
            commonDependencies: commonDependencies,
            telemetry: telemetry
        )
    }

    static func createUpload(
        storage: FeatureStorage,
        configuration: FeaturesConfiguration.Logging,
        commonDependencies: FeaturesCommonDependencies,
        telemetry: Telemetry?
    ) -> FeatureUpload {
        return FeatureUpload(
            featureName: LoggingFeature.featureName,
            storage: storage,
            requestBuilder: RequestBuilder(
                url: configuration.uploadURL,
                queryItems: [
                    .ddsource(source: configuration.common.source)
                ],
                headers: [
                    .contentTypeHeader(contentType: .applicationJSON),
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
        configuration: FeaturesConfiguration.Logging,
        commonDependencies: FeaturesCommonDependencies,
        telemetry: Telemetry?
    ) {
        let storage = LoggingFeature.createStorage(
            directories: directories,
            commonDependencies: commonDependencies,
            telemetry: telemetry
        )
        let upload = LoggingFeature.createUpload(
            storage: storage,
            configuration: configuration,
            commonDependencies: commonDependencies,
            telemetry: telemetry
        )
        self.init(
            storage: storage,
            upload: upload,
            configuration: configuration,
            commonDependencies: commonDependencies
        )
    }

    init(
        storage: FeatureStorage,
        upload: FeatureUpload,
        configuration: FeaturesConfiguration.Logging,
        commonDependencies: FeaturesCommonDependencies
    ) {
        // Configuration
        self.configuration = configuration

        // Bundle dependencies
        self.dateProvider = commonDependencies.dateProvider
        self.dateCorrector = commonDependencies.dateCorrector
        self.userInfoProvider = commonDependencies.userInfoProvider
        self.networkConnectionInfoProvider = commonDependencies.networkConnectionInfoProvider
        self.carrierInfoProvider = commonDependencies.carrierInfoProvider

        // Initialize stacks
        self.storage = storage
        self.upload = upload
    }

    internal func deinitialize() {
        storage.flushAndTearDown()
        upload.flushAndTearDown()
    }
}
