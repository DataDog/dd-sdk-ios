/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Obtains subdirectories in `/Library/Caches` where logging data is stored.
internal func obtainLoggingFeatureDirectories() throws -> FeatureDirectories {
    let version = "v1"
    return FeatureDirectories(
        unauthorized: try Directory(withSubdirectoryPath: "com.datadoghq.logs/intermediate-\(version)"),
        authorized: try Directory(withSubdirectoryPath: "com.datadoghq.logs/\(version)")
    )
}

/// Creates and owns componetns enabling logging feature.
/// Bundles dependencies for other logging-related components created later at runtime  (i.e. `Logger`).
internal final class LoggingFeature {
    /// Single, shared instance of `LoggingFeature`.
    internal static var instance: LoggingFeature?

    /// Tells if the feature was enabled by the user in the SDK configuration.
    static var isEnabled: Bool { instance != nil }

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
        internalMonitor: InternalMonitor? = nil
    ) -> FeatureStorage {
        return FeatureStorage(
            featureName: LoggingFeature.featureName,
            dataFormat: LoggingFeature.dataFormat,
            directories: directories,
            commonDependencies: commonDependencies,
            internalMonitor: internalMonitor
        )
    }

    static func createUpload(
        storage: FeatureStorage,
        configuration: FeaturesConfiguration.Logging,
        commonDependencies: FeaturesCommonDependencies,
        internalMonitor: InternalMonitor? = nil
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
                    .ddAPIKeyHeader(clientToken: configuration.clientToken),
                    .ddEVPOriginHeader(source: configuration.common.source),
                    .ddEVPOriginVersionHeader(),
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
        configuration: FeaturesConfiguration.Logging,
        commonDependencies: FeaturesCommonDependencies,
        internalMonitor: InternalMonitor? = nil
    ) {
        let storage = LoggingFeature.createStorage(
            directories: directories,
            commonDependencies: commonDependencies,
            internalMonitor: internalMonitor
        )
        let upload = LoggingFeature.createUpload(
            storage: storage,
            configuration: configuration,
            commonDependencies: commonDependencies,
            internalMonitor: internalMonitor
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

#if DD_SDK_COMPILED_FOR_TESTING
    func deinitialize() {
        storage.flushAndTearDown()
        upload.flushAndTearDown()
        LoggingFeature.instance = nil
    }
#endif
}
