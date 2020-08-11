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

    // MARK: - Dependencies

    let dateProvider: DateProvider
    let userInfoProvider: UserInfoProvider
    let networkConnectionInfoProvider: NetworkConnectionInfoProviderType
    let carrierInfoProvider: CarrierInfoProviderType

    // MARK: - Components

    static let featureName = "rum"
    /// NOTE: any change to data format requires updating the directory url to be unique
    static let dataFormat = DataFormat(prefix: "", suffix: "", separator: "\n")

    /// RUM files storage.
    let storage: FeatureStorage
    /// RUM upload worker.
    let upload: FeatureUpload

    // MARK: - Initialization

    convenience init(
        directory: Directory,
        commonDependencies: FeaturesCommonDependencies
    ) {
        let storage = FeatureStorage(
            featureName: RUMFeature.featureName,
            dataFormat: RUMFeature.dataFormat,
            directory: directory,
            commonDependencies: commonDependencies
        )
        let upload = FeatureUpload(
            featureName: RUMFeature.featureName,
            storage: storage,
            uploadHTTPHeaders: HTTPHeaders(
                headers: [
                    .contentTypeHeader(contentType: .textPlainUTF8),
                    .userAgentHeader(
                        appName: commonDependencies.configuration.applicationName,
                        appVersion: commonDependencies.configuration.applicationVersion,
                        device: commonDependencies.mobileDevice
                    )
                ]
            ),
            uploadURLProvider: UploadURLProvider(
                urlWithClientToken: commonDependencies.configuration.rumUploadURLWithClientToken,
                queryItemProviders: [
                    .ddsource(),
                    .batchTime(using: commonDependencies.dateProvider),
                    .ddtags(
                        tags: [
                            "service:\(commonDependencies.configuration.serviceName)",
                            "version:\(commonDependencies.configuration.applicationVersion)",
                            "sdk_version:\(sdkVersion)",
                            "env:\(commonDependencies.configuration.environment)"
                        ]
                    )
                ]
            ),
            commonDependencies: commonDependencies
        )
        self.init(
            storage: storage,
            upload: upload,
            commonDependencies: commonDependencies
        )
    }

    init(
        storage: FeatureStorage,
        upload: FeatureUpload,
        commonDependencies: FeaturesCommonDependencies
    ) {
        // Configuration
        self.configuration = commonDependencies.configuration

        // Bundle dependencies
        self.dateProvider = commonDependencies.dateProvider
        self.userInfoProvider = commonDependencies.userInfoProvider
        self.networkConnectionInfoProvider = commonDependencies.networkConnectionInfoProvider
        self.carrierInfoProvider = commonDependencies.carrierInfoProvider

        // Initialize stacks
        self.storage = storage
        self.upload = upload
    }
}
