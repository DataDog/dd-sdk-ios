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
    /// from `receive(message:)` to be thread-safe. The implementation should be mindful of
    /// not blocking the caller thread to not delay processing of other messages in the system.
    ///
    /// - Parameter message: The message.
    func receive(message: FeatureMessage)
}

public struct NOPFeatureMessageReceiver: FeatureMessageReceiver {
    public init() { }

    /// no-op
    public func receive(message: FeatureMessage) {}
}

/// A receiver that combines multiple receivers. All receivers get every message
/// and silently ignore irrelevant ones.
public struct CombinedFeatureMessageReceiver: FeatureMessageReceiver {
    public let receivers: [FeatureMessageReceiver]

    /// Creates an instance initialized with the given receivers.
    public init(_ receivers: FeatureMessageReceiver...) {
        self.receivers = Array(receivers)
    }

    /// Creates an instance initialized with the given receivers.
    public init(_ receivers: [FeatureMessageReceiver]) {
        self.receivers = receivers
    }

    /// Forwards the message to all receivers.
    ///
    /// - Parameter message: The message.
    public func receive(message: FeatureMessage) {
        receivers.forEach { $0.receive(message: message) }
    }
}
