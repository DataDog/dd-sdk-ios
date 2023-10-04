/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// A Datadog Feature that can interact with the core through the message-bus.
public protocol DatadogFeature {
    /// The feature name.
    static var name: String { get }

    /// The message bus receiver.
    ///
    /// The `FeatureMessageReceiver` defines an interface for Feature to receive any message
    /// from a bus that is shared between Features registered in a core.
    var messageReceiver: FeatureMessageReceiver { get }

    /// (Optional) `PerformancePresetOverride` allows overriding certain performance presets if needed.
    var performanceOverride: PerformancePresetOverride? { get }
}

/// A Datadog Feature with remote data store.
public protocol DatadogRemoteFeature: DatadogFeature {
    /// The URL request builder for uploading data.
    ///
    /// The `FeatureRequestBuilder` defines an interface for building a single `URLRequest`
    /// for a list of data events and the current core context.
    ///
    /// A Feature should use this interface for creating requests that needs be sent to its Datadog Intake.
    /// The request will be transported by `DatadogCore`.
    var requestBuilder: FeatureRequestBuilder { get }
}

extension DatadogFeature {
    public var performanceOverride: PerformancePresetOverride? { nil }
}
