/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// The `FeatureMessageReceiver` defines an interface for a Feature to receive messages
/// from a bus that is shared between Features registered to same instance of the core.
///
/// The message is composed of a key and a dictionary of attributes. The message format is a loose
/// agreement between Features - all messages supported by a Feature should be properly documented.
public protocol FeatureMessageReceiver {
    /// Receives messages from the message bus.
    ///
    /// The message can be used to build an event or execute custom routine in the Feature.
    ///
    /// This method is always called on the same thread managed by core. If the implementation
    /// of `FeatureMessageReceiver` needs to manage a state it can consider its mutations started
    /// from `receive(message:from:)` to be thread-safe. The implementation should be mindful of
    /// not blocking the caller thread to not delay processing of other messages in the system.
    ///
    /// - Parameters:
    ///   - message: The message.
    ///   - core: An instance of the core from which the message is transmitted.
    /// - Returns: `true` if the message was processed by the receiver;`false` if it was ignored.
    @discardableResult
    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool
    // ^ TODO: RUM-3717
    // Remove `core:` parameter from this API once all features are migrated to depend on `FeatureScope` interface
    // instead of depending on directly on `core`.
}

public struct NOPFeatureMessageReceiver: FeatureMessageReceiver {
    public init() { }

    /// no-op: returns `false`
    public func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        return false
    }
}

/// A receiver that combines multiple receivers. It will loop though receivers and stop on the first that is able to
/// consume the given message.
public struct CombinedFeatureMessageReceiver: FeatureMessageReceiver {
    let receivers: [FeatureMessageReceiver]

    /// Creates an instance initialized with the given receivers.
    public init(_ receivers: FeatureMessageReceiver...) {
        self.receivers = Array(receivers)
    }

    /// Creates an instance initialized with the given receivers.
    public init(_ receivers: [FeatureMessageReceiver]) {
        self.receivers = receivers
    }

    /// Receiving a message will loop though receivers and stop on the first that is able to
    /// consume the given message.
    ///
    /// - Parameters:
    ///   - message: The message.
    ///   - core: An instance of the core from which the message is transmitted.
    /// - Returns: `true` if the message was processed by one of the receiver; `false` if it was ignored.
    public func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        receivers.contains(where: { $0.receive(message: message, from: core) })
    }
}
