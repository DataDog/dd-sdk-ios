/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Message payload used to signal the occurrence of an event.
public struct RUMMessage {
    /// Correlation context containing IDs for data correlation.
    public let context: [String: AttributeValue]
    /// Event info for data correlation.
    public let event: Codable

    /// Creates a new message payload.
    ///
    /// - Parameters
    ///   - context: Correlation context containing IDs for data correlation.
    ///   - event: Event info for data correlation.
    public init(context: [String: AttributeValue], event: Codable) {
        self.context = context
        self.event = event
    }
}
