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

    let vitalCPUReader: SamplingBasedVitalReader // VitalCPUReader
    let vitalMemoryReader: SamplingBasedVitalReader // VitalMemoryReader
    let vitalRefreshRateReader: ContinuousVitalReader // VitalRefreshRateReader

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

    static func createStorage(
        directories: FeatureDirectories,
        commonDependencies: FeaturesCommonDependencies,
        internalMonitor: InternalMonitor? = nil
    ) -> FeatureStorage {
        return FeatureStorage(
            featureName: RUMFeature.featureName,
            dataFormat: RUMFeature.dataFormat,
            directories: directories,
            commonDependencies: commonDependencies,
            internalMonitor: internalMonitor
        )
    }

    static func createUpload(
        storage: FeatureStorage,
        configuration: FeaturesConfiguration.RUM,
        commonDependencies: FeaturesCommonDependencies,
        internalMonitor: InternalMonitor? = nil
    ) -> FeatureUpload {
        return FeatureUpload(
            featureName: RUMFeature.featureName,
            storage: storage,
            requestBuilder: RequestBuilder(
                url: configuration.uploadURL,
                queryItems: [
                    .ddsource(source: configuration.common.source),
                    .ddtags(
                        tags: [
                            "service:\(configuration.common.serviceName)",
                            "version:\(configuration.common.applicationVersion)",
                            "sdk_version:\(sdkVersion)",
                            "env:\(configuration.common.environment)"
                        ]
                    )
                ],
                headers: [
                    .contentTypeHeader(contentType: .textPlainUTF8),
                    .userAgentHeader(
                        appName: configuration.common.applicationName,
                        appVersion: configuration.common.applicationVersion,
                        device: commonDependencies.mobileDevice
                    ),
                    .ddAPIKeyHeader(clientToken: configuration.clientToken),
                    .ddEVPOriginHeader(source: configuration.common.source),
                    .ddEVPOriginVersionHeader(),
                    .ddRequestIDHeader(),
                ]
            ),
            commonDependencies: commonDependencies,
            internalMonitor: internalMonitor
        )
    }

    convenience init(
        directories: FeatureDirectories,
        configuration: FeaturesConfiguration.RUM,
        commonDependencies: FeaturesCommonDependencies,
        internalMonitor: InternalMonitor? = nil
    ) {
        let eventsMapper = RUMEventsMapper(
            viewEventMapper: configuration.viewEventMapper,
            errorEventMapper: configuration.errorEventMapper,
            resourceEventMapper: configuration.resourceEventMapper,
            actionEventMapper: configuration.actionEventMapper,
            internalMonitor: internalMonitor
        )
        let storage = RUMFeature.createStorage(
            directories: directories,
            commonDependencies: commonDependencies,
            internalMonitor: internalMonitor
        )
        let upload = RUMFeature.createUpload(
            storage: storage,
            configuration: configuration,
            commonDependencies: commonDependencies,
            internalMonitor: internalMonitor
        )
        self.init(
            eventsMapper: eventsMapper,
            storage: storage,
            upload: upload,
            configuration: configuration,
            commonDependencies: commonDependencies,
            vitalCPUReader: VitalCPUReader(),
            vitalMemoryReader: VitalMemoryReader(),
            vitalRefreshRateReader: VitalRefreshRateReader()
        )
    }

    init(
        eventsMapper: RUMEventsMapper,
        storage: FeatureStorage,
        upload: FeatureUpload,
        configuration: FeaturesConfiguration.RUM,
        commonDependencies: FeaturesCommonDependencies,
        vitalCPUReader: SamplingBasedVitalReader,
        vitalMemoryReader: SamplingBasedVitalReader,
        vitalRefreshRateReader: ContinuousVitalReader
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
        self.eventsMapper = eventsMapper
        self.storage = storage
        self.upload = upload

        self.vitalCPUReader = vitalCPUReader
        self.vitalMemoryReader = vitalMemoryReader
        self.vitalRefreshRateReader = vitalRefreshRateReader
    }

#if DD_SDK_COMPILED_FOR_TESTING
    func deinitialize() {
        storage.flushAndTearDown()
        upload.flushAndTearDown()
        RUMFeature.instance = nil
    }
#endif
}
