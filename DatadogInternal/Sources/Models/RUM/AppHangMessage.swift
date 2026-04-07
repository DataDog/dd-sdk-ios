/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Message payload sent on the message bus when RUM reports an app hang
public struct AppHangMessage {
    /// Correlation context containing IDs for data correlation.
    public let attributes: [String: AttributeValue]
    /// Hang info for data correlation.
    public let hang: DurationEvent

    /// Creates a new message payload.
    ///
    /// - Parameters:
    ///   - attributes: Correlation context containing IDs for data correlation.
    ///   - hang: Hang info for data correlation.
    public init(attributes: [String: AttributeValue], hang: DurationEvent) {
        self.attributes = attributes
        self.hang = hang
    }
}
