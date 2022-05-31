/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Creates and owns components enabling logging feature.
/// Bundles dependencies for other logging-related components created later at runtime  (i.e. `Logger`).
internal final class LoggingFeature: V1Feature {
    typealias Configuration = FeaturesConfiguration.Logging

    // MARK: - Configuration

    let configuration: Configuration

    // MARK: - Dependencies

    let dateProvider: DateProvider
    let dateCorrector: DateCorrectorType
    let userInfoProvider: UserInfoProvider
    let networkConnectionInfoProvider: NetworkConnectionInfoProviderType
    let carrierInfoProvider: CarrierInfoProviderType

    // MARK: - Components

    /// Log files storage.
    let storage: FeatureStorage
    /// Logs upload worker.
    let upload: FeatureUpload

    // MARK: - Initialization

    init(
        storage: FeatureStorage,
        upload: FeatureUpload,
        configuration: Configuration,
        commonDependencies: FeaturesCommonDependencies,
        telemetry: Telemetry?
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
