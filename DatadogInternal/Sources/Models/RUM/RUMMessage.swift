/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Message payload used to signal the occurrence of an event.
public struct RUMMessage {
    /// Correlation context containing IDs for data correlation.
    public let attributes: [String: AttributeValue]
    /// Vital info for data correlation.
    public let event: Codable

    /// Creates a new message payload.
    ///
    /// - Parameters
    ///   - attributes: Correlation context containing IDs for data correlation.
    ///   - vital: Vital info for data correlation.
    public init(attributes: [String: AttributeValue], event: Codable) {
        self.attributes = attributes
        self.event = event
    }
}
