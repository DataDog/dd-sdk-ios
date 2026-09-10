/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Message payload sent on the message bus when RUM reports a memory warning.
///
/// A memory warning is a point in time, not a duration, so `error.duration` is `0`. It is carried
/// as a `DurationEvent` of type `.error` so it correlates through the same `error.id` path as an
/// app hang.
public struct MemoryWarningMessage {
    /// Correlation context containing IDs for data correlation.
    public let attributes: [AttributeKey: AttributeValue]
    /// The RUM error reported for this memory warning.
    public let error: DurationEvent

    /// Creates a new message payload.
    ///
    /// - Parameters:
    ///   - attributes: Correlation context containing IDs for data correlation.
    ///   - error: The RUM error reported for this memory warning.
    public init(attributes: [String: AttributeValue], error: DurationEvent) {
        self.attributes = attributes
        self.error = error
    }
}
