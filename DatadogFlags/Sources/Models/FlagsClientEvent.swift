/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

/// A notification from a feature flag client.
public struct FlagsClientEvent: Sendable {
    /// The kind of notification.
    public let type: FlagsClientEventType
    /// Complete keys of the first accepted configuration, not a per-flag change or all server flags.
    /// An empty array represents a valid empty configuration. These keys do not pin assignment values.
    public let flagsChanged: [String]?

    internal init(type: FlagsClientEventType, flagsChanged: [String]? = nil) {
        self.type = type
        self.flagsChanged = flagsChanged
    }
}

/// Supported feature flag client notifications.
public enum FlagsClientEventType: String, Sendable {
    case configurationChanged = "CONFIGURATION_CHANGED"
}

/// A nonthrowing listener that may run on the installing thread or the registering thread.
/// Capture only Sendable values; access actor-owned state through an explicit actor hop.
public typealias FlagsClientEventListener = @Sendable (FlagsClientEvent) -> Void

/// Explicit cancellation of a single first-flags registration.
///
/// Call `cancel()` to release a pending listener. Discarding this subscription does not cancel it.
/// Retaining a subscription does not keep the client alive. Cancellation cannot interrupt or wait
/// for a listener already claimed for delivery, and does not cancel initialization or fetching.
public protocol FlagsSubscription: Sendable {
    /// Cancels pending delivery. Thread-safe and idempotent; completed delivery is unaffected.
    func cancel()
}

internal struct NOPFlagsSubscription: FlagsSubscription {
    func cancel() {}
}
