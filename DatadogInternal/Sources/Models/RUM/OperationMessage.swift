/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Message payload sent on the message bus when RUM reports an operation start/end
public struct OperationMessage {
    /// Correlation context containing IDs for data correlation.
    public let attributes: [AttributeKey: AttributeValue]
    /// Operation info for data correlation.
    public let operation: Vital

    /// Creates a new message payload.
    ///
    /// - Parameters:
    ///   - attributes: Correlation context containing IDs for data correlation.
    ///   - operation: Operation info for data correlation.
    public init(attributes: [AttributeKey: AttributeValue], operation: Vital) {
        self.attributes = attributes
        self.operation = operation
    }
}
