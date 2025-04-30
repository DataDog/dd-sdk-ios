/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Error message sent from Logs on the message-bus.
public struct LogErrorMessage {
    /// The time of the log
    public let time: Date
    /// The Log error message
    public let message: String
    /// The Log error type
    public let type: String?
    /// The Log error stack
    public let stack: String?
    /// The Log attributes
    public let attributes: [String: Encodable]
    /// Binary images if need to decode the stack trace
    public let binaryImages: [BinaryImage]?

    /// Create a Log error message to be sent on the message-bus.
    ///
    /// - Parameters:
    ///   - time: The time of the log
    ///   - message: The Log error message
    ///   - type: The Log error type
    ///   - stack: The Log error stack
    ///   - attributes: The Log attributes
    ///   - binaryImages: Binary images if need to decode the stack trace
    public init(
        time: Date,
        message: String,
        type: String?,
        stack: String?,
        attributes: [String: Encodable],
        binaryImages: [BinaryImage]?
    ) {
        self.time = time
        self.message = message
        self.type = type
        self.stack = stack
        self.attributes = attributes
        self.binaryImages = binaryImages
    }
}
