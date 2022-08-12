/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

public internal(set) var defaultDatadogCore: DatadogCoreProtocol = NOOPDatadogCore()

/// A Datadog Core holds a set of features and is responsible of managing their storage
/// and upload mechanism. It also provides a thread-safe scope for writing events.
public protocol DatadogCoreProtocol {
    /// Sends a message on the bus shared by features registered in this core.
    ///
    /// The message is composed of a key and attributes that the feature can use to build an
    /// event or run a process. Be mindful of not blocking the caller thread.
    ///
    /// - Parameters:
    ///   - message: The message key.
    ///   - attributes: The message attributes.
    func send(message: String, attributes: [String: Any]?)
}

/// A datadog feature providing thread-safe scope for writing events.
public protocol FeatureScope {
    // TODO: RUMM-2133
}

/// No-op implementation of `DatadogFeatureRegistry`.
internal struct NOOPDatadogCore: DatadogCoreProtocol {
    /// no-op
    func send(message: String, attributes: [String: Any]?) { }
}
