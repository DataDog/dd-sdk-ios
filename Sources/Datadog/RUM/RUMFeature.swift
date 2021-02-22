/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Obtains subdirectories in `/Library/Caches` where RUM data is stored.
internal func obtainRUMFeatureDirectories() throws -> FeatureDirectories {
    let version = "v1"
    return FeatureDirectories(
        unauthorized: try Directory(withSubdirectoryPath: "com.datadoghq.rum/intermediate-\(version)"),
        authorized: try Directory(withSubdirectoryPath: "com.datadoghq.rum/\(version)")
    )
}

/// Creates and owns componetns enabling RUM feature.
/// Bundles dependencies for other RUM-related components created later at runtime  (i.e. `RUMMonitor`).
internal final class RUMFeature {
    /// Single, shared instance of `RUMFeature`.
    internal static var instance: RUMFeature?

    /// Tells if the feature was enabled by the user in the SDK configuration.
    static var isEnabled: Bool { instance != nil }

    // MARK: - Configuration

    let configuration: FeaturesConfiguration.RUM

    // MARK: - Dependencies

    let dateProvider: DateProvider
    let dateCorrector: DateCorrectorType
    let userInfoProvider: UserInfoProvider
    let networkConnectionInfoProvider: NetworkConnectionInfoProviderType
    let carrierInfoProvider: CarrierInfoProviderType
    let launchTimeProvider: LaunchTimeProviderType

    // MARK: - Components

    static let featureName = "rum"
    /// NOTE: any change to data format requires updating the directory url to be unique
    static let dataFormat = DataFormat(prefix: "", suffix: "", separator: "\n")

    /// RUM files storage.
    let storage: FeatureStorage
    /// RUM upload worker.
    let upload: FeatureUpload

    /// RUM events mapper.
    let eventsMapper: RUMEventsMapper

    // MARK: - Initialization

    static func createEventsMapper(
        configuration: FeaturesConfiguration.RUM,
        commonDependencies: FeaturesCommonDependencies
    ) -> RUMEventsMapper {
        return RUMEventsMapper(
            dateProvider: commonDependencies.dateProvider,
            viewEventMapper: configuration.eventMapper.viewEventMapper,
            errorEventMapper: configuration.eventMapper.errorEventMapper,
            resourceEventMapper: configuration.eventMapper.resourceEventMapper,
            actionEventMapper: configuration.eventMapper.actionEventMapper
        )
    }

    static func createStorage(
        directories: FeatureDirectories,
        eventMapper: RUMEventsMapper,
        commonDependencies: FeaturesCommonDependencies
    ) -> FeatureStorage {
        return FeatureStorage(
            featureName: RUMFeature.featureName,
            dataFormat: RUMFeature.dataFormat,
            directories: directories,
            eventMapper: eventMapper,
            commonDependencies: commonDependencies
        )
    }

    static func createUpload(
        storage: FeatureStorage,
        configuration: FeaturesConfiguration.RUM,
        commonDependencies: FeaturesCommonDependencies
    ) -> FeatureUpload {
        return FeatureUpload(
            featureName: RUMFeature.featureName,
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
                    .ddsource(),
                    .ddtags(
                        tags: [
                            "service:\(configuration.common.serviceName)",
                            "version:\(configuration.common.applicationVersion)",
                            "sdk_version:\(sdkVersion)",
                            "env:\(configuration.common.environment)"
                        ]
                    )
                ]
            ),
            commonDependencies: commonDependencies
        )
    }

    convenience init(
        directories: FeatureDirectories,
        configuration: FeaturesConfiguration.RUM,
        commonDependencies: FeaturesCommonDependencies
    ) {
        let eventsMapper = RUMFeature.createEventsMapper(
            configuration: configuration,
            commonDependencies: commonDependencies
        )
        let storage = RUMFeature.createStorage(
            directories: directories,
            eventMapper: eventsMapper,
            commonDependencies: commonDependencies
        )
        let upload = RUMFeature.createUpload(storage: storage, configuration: configuration, commonDependencies: commonDependencies)
        self.init(
            storage: storage,
            upload: upload,
            eventsMapper: eventsMapper,
            configuration: configuration,
            commonDependencies: commonDependencies
        )
    }

    init(
        storage: FeatureStorage,
        upload: FeatureUpload,
        eventsMapper: RUMEventsMapper,
        configuration: FeaturesConfiguration.RUM,
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
        self.launchTimeProvider = commonDependencies.launchTimeProvider

        // Initialize stacks
        self.storage = storage
        self.upload = upload
        self.eventsMapper = eventsMapper
    }
}
