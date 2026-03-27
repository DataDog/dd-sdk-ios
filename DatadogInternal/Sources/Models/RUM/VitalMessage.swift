/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Message payload used to signal the occurrence of a vital.
public struct VitalMessage {
    /// Correlation context containing IDs for data correlation.
    public let attributes: [String: AttributeValue]
    /// Vital info for data correlation.
    public let vital: Vital

    /// Creates a new message payload.
    ///
    /// - Parameters
    ///   - attributes: Correlation context containing IDs for data correlation.
    ///   - vital: Vital info for data correlation.
    public init(attributes: [String: AttributeValue], vital: Vital) {
        self.attributes = attributes
        self.vital = vital
    }
}
