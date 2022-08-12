/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// The `FeatureMessageReceiver` defines an interface for feature to receive any message
/// from a bus that is shared between feature registered in a core.
///
/// A message is composed of a key and a dictionary of attributes. A message format is a loose
/// agreement between features, any supported messages by a feature should be properly
/// documented.
/* public */ internal protocol FeatureMessageReceiver {
    /// Receive a message from the bus.
    ///
    /// The message is composed of a key and attributes that the feature can use to build an
    /// event or run a process. Be mindful of not blocking the caller thread.
    ///
    /// - Parameters:
    ///   - message: The message key.
    ///   - attributes: The message attributes.
    func receive(message: String, attributes: [String: Any]?)
}

/* public */ internal struct NOOPFeatureMessageReceiver: FeatureMessageReceiver {
    /// no-op
    func receive(message: String, attributes: [String: Any]?) { }
}
