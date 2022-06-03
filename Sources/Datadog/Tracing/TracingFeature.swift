/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Creates and owns componetns enabling tracing feature.
/// Bundles dependencies for other tracing-related components created later at runtime  (i.e. `Tracer`).
internal final class TracingFeature: V1FeatureInitializable {
    typealias Configuration = FeaturesConfiguration.Tracing

    // MARK: - Configuration

    let configuration: Configuration

    // MARK: - Components

    /// Span files storage.
    let storage: FeatureStorage
    /// Spans upload worker.
    let upload: FeatureUpload

    // MARK: - Initialization

    init(
        storage: FeatureStorage,
        upload: FeatureUpload,
        configuration: FeaturesConfiguration.Tracing,
        /// TODO: RUMM-2169 Remove `commonDependencies` from `V1FeatureInitializable` interface when all Features are migrated to use `DatadogV1Context`:
        commonDependencies: FeaturesCommonDependencies,
        telemetry: Telemetry?
    ) {
        // Configuration
        self.configuration = configuration

        // Initialize stacks
        self.storage = storage
        self.upload = upload
    }

    internal func deinitialize() {
        storage.flushAndTearDown()
        upload.flushAndTearDown()
    }
}
