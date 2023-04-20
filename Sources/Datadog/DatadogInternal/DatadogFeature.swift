/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/* public */ internal struct DatadogFeatureConfiguration {
    /// The Feature name.
    let name: String

    /// The URL request builder for uploading data in this Feature.
    ///
    /// This builder currently use the v1 context, but will be soon migrated to v2
    let requestBuilder: FeatureRequestBuilder

    /// The message bus receiver.
    ///
    /// The `FeatureMessageReceiver` defines an interface for Feature to receive any message
    /// from a bus that is shared between Features registered in a core.
    let messageReceiver: FeatureMessageReceiver
}

public protocol DatadogFeature {
    /// The feature name.
    var name: String { get }

    /// The URL request builder for uploading data in this Feature.
    var requestBuilder: FeatureRequestBuilder { get }

    /// The message bus receiver.
    ///
    /// The `FeatureMessageReceiver` defines an interface for Feature to receive any message
    /// from a bus that is shared between all Features registered in the core.
    var messageReceiver: FeatureMessageReceiver { get }

    /// (Optional) `PerformancePresetOverride` allows overriding certain performance presets if needed.
    var performanceOverride: PerformancePresetOverride? { get }
}

extension DatadogFeature {
    public var performanceOverride: PerformancePresetOverride? { nil }
}

public protocol DatadogFeatureIntegration {
    /// The feature name.
    var name: String { get }

    /// The message bus receiver.
    ///
    /// The `FeatureMessageReceiver` defines an interface for Feature to receive any message
    /// from a bus that is shared between Features registered in a core.
    var messageReceiver: FeatureMessageReceiver { get }
}
