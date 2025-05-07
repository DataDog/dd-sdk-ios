/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

public struct LogMessage {
    /// Log levels ordered by their severity, with `.debug` being the least severe and
    /// `.critical` being the most severe.
    public enum Level: Int {
        case debug
        case info
        case notice
        case warn
        case error
        case critical
    }

    /// The Logger name
    public let logger: String
    /// The Logger service
    public let service: String?
    /// The Log date
    public let date: Date
    /// The Log message
    public let message: String
    /// The Log error
    public let error: DDError?
    /// The Log level
    public let level: Level
    /// The thread name
    public let thread: String
    /// `true` if network information should be added to the log entry
    public let networkInfoEnabled: Bool?
    /// The Log user custom attributes
    public let userAttributes: [String: Encodable]?
    /// The Log internal attributes
    public let internalAttributes: [String: Encodable]?

    /// Creates a Log Message to be dispatched on the message-bus.
    ///
    /// - Parameters:
    ///   - logger: The Logger name
    ///   - service: The Logger service
    ///   - date: The Log date
    ///   - message: The Log message
    ///   - error: The Log error
    ///   - level: The Log level
    ///   - thread: The thread name
    ///   - networkInfoEnabled: `true` if network information should be added to the log entry
    ///   - userAttributes: The Log user custom attributes
    ///   - internalAttributes: The Log internal attributes
    public init(
        logger: String,
        service: String?,
        date: Date,
        message: String,
        error: DDError?,
        level: Level,
        thread: String,
        networkInfoEnabled: Bool?,
        userAttributes: [String: Encodable]?,
        internalAttributes: [String: Encodable]?
    ) {
        self.logger = logger
        self.service = service
        self.date = date
        self.message = message
        self.error = error
        self.level = level
        self.thread = thread
        self.networkInfoEnabled = networkInfoEnabled
        self.userAttributes = userAttributes
        self.internalAttributes = internalAttributes
    }
}
