/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Provides the current `FeatureMessageAttributes`.
internal class FeatureAttributesProvider {
    private let publisher: ValuePublisher<[String: FeatureMessageAttributes]>

    /// Creates a `FeatureAttributesProvider` with empty attributes.
    init() {
        self.publisher = ValuePublisher(initialValue: [:])
    }

    // MARK: - `FeatureMessageAttributes` Value

    /// The current Features attributes.
    var attributes: [String: FeatureMessageAttributes] {
        set {
            // Synchronous update ensures that the new value of the user info will be applied immediately
            // to all data sent from the the same thread.
            publisher.publishSync(newValue)
        }
        get { publisher.currentValue }
    }
}
