/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Creates and owns components enabling logging feature.
/// Bundles dependencies for other logging-related components created later at runtime  (i.e. `Logger`).
internal final class LoggingFeature: V1FeatureInitializable, V1Feature {
    typealias Configuration = FeaturesConfiguration.Logging

    // MARK: - Configuration

    let configuration: Configuration

    // MARK: - Components

    /// Log files storage.
    let storage: FeatureStorage
    /// Logs upload worker.
    let upload: FeatureUpload

    let messageReceiver: FeatureMessageReceiver

    // MARK: - Initialization

    init(
        storage: FeatureStorage,
        upload: FeatureUpload,
        configuration: Configuration,
        messageReceiver: FeatureMessageReceiver
    ) {
        // Configuration
        self.configuration = configuration

        // Initialize stacks
        self.storage = storage
        self.upload = upload
        self.messageReceiver = messageReceiver
    }
}
