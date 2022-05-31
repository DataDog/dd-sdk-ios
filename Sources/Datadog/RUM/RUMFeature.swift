/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Creates and owns componetns enabling RUM feature.
/// Bundles dependencies for other RUM-related components created later at runtime  (i.e. `RUMMonitor`).
internal final class RUMFeature: V1Feature {
    typealias Configuration = FeaturesConfiguration.RUM

    // MARK: - Configuration

    let configuration: Configuration

    // MARK: - Dependencies

    let sdkInitDate: Date
    let dateProvider: DateProvider
    let dateCorrector: DateCorrectorType
    let appStateListener: AppStateListening
    let userInfoProvider: UserInfoProvider
    let networkConnectionInfoProvider: NetworkConnectionInfoProviderType
    let carrierInfoProvider: CarrierInfoProviderType
    let launchTimeProvider: LaunchTimeProviderType

    let vitalCPUReader: SamplingBasedVitalReader
    let vitalMemoryReader: SamplingBasedVitalReader
    let vitalRefreshRateReader: ContinuousVitalReader

    let onSessionStart: RUMSessionListener?

    // MARK: - Components

    /// RUM files storage.
    let storage: FeatureStorage
    /// RUM upload worker.
    let upload: FeatureUpload

    /// RUM events mapper.
    let eventsMapper: RUMEventsMapper

    // MARK: - Initialization

    convenience init(
        storage: FeatureStorage,
        upload: FeatureUpload,
        configuration: Configuration,
        commonDependencies: FeaturesCommonDependencies,
        telemetry: Telemetry?
    ) {
        self.init(
            eventsMapper: RUMEventsMapper(
                viewEventMapper: configuration.viewEventMapper,
                errorEventMapper: configuration.errorEventMapper,
                resourceEventMapper: configuration.resourceEventMapper,
                actionEventMapper: configuration.actionEventMapper,
                longTaskEventMapper: configuration.longTaskEventMapper,
                telemetry: telemetry
            ),
            storage: storage,
            upload: upload,
            configuration: configuration,
            commonDependencies: commonDependencies,
            vitalCPUReader: VitalCPUReader(telemetry: telemetry),
            vitalMemoryReader: VitalMemoryReader(),
            vitalRefreshRateReader: VitalRefreshRateReader(),
            onSessionStart: configuration.onSessionStart
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
        vitalRefreshRateReader: ContinuousVitalReader,
        onSessionStart: RUMSessionListener?
    ) {
        // Configuration
        self.configuration = configuration

        // Bundle dependencies
        self.sdkInitDate = commonDependencies.sdkInitDate
        self.dateProvider = commonDependencies.dateProvider
        self.dateCorrector = commonDependencies.dateCorrector
        self.appStateListener = commonDependencies.appStateListener
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
        self.onSessionStart = onSessionStart
    }

    internal func deinitialize() {
        storage.flushAndTearDown()
        upload.flushAndTearDown()
    }
}
