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
}

/// A Datadog Feature that holds data in memory before writing it to storage.
///
/// When the core clears all data, it asks conforming features to drop what they hold in memory, then
/// clears every feature's storage and data store. Otherwise, data collected before the request could
/// still be written and uploaded after it.
public protocol DataClearable {
    /// Drops the data held in memory that has not been written to storage yet.
    func clearAllData()
}

/// A Datadog Feature that holds data in memory before writing it to storage.
///
/// When a macOS app terminates, the core asks conforming features to write what they hold in memory, then
/// waits until it is stored. Otherwise, the data would be lost when the app exits.
public protocol BufferedDataWritable {
    /// Writes the data held in memory that has not been written to storage yet.
    ///
    /// **Blocks the caller thread** until the event write context for that data is open. The core calls it on the
    /// main thread, so it must not wait for the main thread.
    ///
    /// The app is terminating: the process exits once nothing holds sudden termination. After this call, the
    /// feature must stop collecting, or write new data right away, so that new data does not delay the exit.
    func writeBufferedData()
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

    /// (Optional) `PerformancePresetOverride` allows overriding certain performance presets if needed.
    var performanceOverride: PerformancePresetOverride? { get }
}
