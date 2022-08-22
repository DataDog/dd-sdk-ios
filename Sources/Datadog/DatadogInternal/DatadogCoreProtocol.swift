/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

public internal(set) var defaultDatadogCore: DatadogCoreProtocol = NOPDatadogCore()

/// A Datadog Core holds a set of features and is responsible of managing their storage
/// and upload mechanism. It also provides a thread-safe scope for writing events.
public protocol DatadogCoreProtocol {
    /// Sends a message on the bus shared by features registered in this core.
    ///
    /// If the message could not be processed by any registered feature, the fallback closure
    /// will be invoked. Do not make any assumption on which thread the fallback is called.
    ///
    /// - Parameters:
    ///   - message: The message.
    ///   - fallback: The fallback closure to call when the message could not be
    ///               processed by any Features on the bus.
    func send(message: FeatureMessage, else fallback: @escaping () -> Void)
}

extension DatadogCoreProtocol {
    /// Sends a message on the bus shared by features registered in this core.
    ///
    /// - Parameters:
    ///   - message: The message.
    func send(message: FeatureMessage) {
        send(message: message, else: {})
    }
}

/// A datadog feature providing thread-safe scope for writing events.
public protocol FeatureScope {
    // TODO: RUMM-2133
}

/// No-op implementation of `DatadogFeatureRegistry`.
internal struct NOPDatadogCore: DatadogCoreProtocol {
    /// no-op
    func send(message: FeatureMessage, else fallback: @escaping () -> Void) { }
}
