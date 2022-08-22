/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// The `FeatureMessageReceiver` defines an interface for Feature to receive any message
/// from a bus that is shared between Features registered in a core.
///
/// A message is composed of a key and a dictionary of attributes. A message format is a loose
/// agreement between Features, any supported messages by a Feature should be properly
/// documented.
/* public */ internal protocol FeatureMessageReceiver {
    /// Receive a message from the message bus of a given core.
    ///
    /// The message can be used to build an event or run a process.
    /// Be mindful of not blocking the caller thread.
    ///
    /// - Parameters:
    ///   - message: The Feature message
    ///   - core: The core from which the message is transmitted.
    /// - Returns: Returns `true` if the message was processed by the receiver. `false` if it was
    ///            ignored.
    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool
}

/* public */ internal struct NOPFeatureMessageReceiver: FeatureMessageReceiver {
    /// no-op: returns `false`
    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        return false
    }
}
