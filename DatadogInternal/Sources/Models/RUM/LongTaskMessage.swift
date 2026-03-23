/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Message payload sent on the message bus when RUM reports a long task
public struct LongTaskMessage {
    /// Correlation context containing IDs for data correlation.
    public let attributes: [AttributeKey: AttributeValue]
    /// Long task info for data correlation.
    public let longTask: DurationEvent

    /// Creates a new message payload.
    ///
    /// - Parameters:
    ///   - attributes: Correlation context containing IDs for data correlation.
    ///   - longTask: Long task info for data correlation.
    public init(attributes: [String: AttributeValue], longTask: DurationEvent) {
        self.attributes = attributes
        self.longTask = longTask
    }
}
