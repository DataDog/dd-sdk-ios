/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

public struct TraceLogMessage {
    /// The Tracer service
    public let service: String?
    /// The Log date
    public let date: Date
    /// The Log message
    public let message: String
    /// The Log error
    public let error: DDError?
    /// The thread name
    public let thread: String
    /// Should include network info
    public let networkInfoEnabled: Bool
    /// The Log user custom attributes
    public let userAttributes: [String: Encodable]
    /// The Log internal attributes
    public let internalAttributes: [String: Encodable]?

    /// Create a Trace log message.
    ///
    /// - Parameters:
    ///   - service: The Tracer service
    ///   - date: The Log date
    ///   - message: The Log message
    ///   - error: The Log error
    ///   - thread: The thread name
    ///   - networkInfoEnabled: Should include network info
    ///   - userAttributes: The Log user custom attributes
    ///   - internalAttributes: The Log internal custom attributes
    public init(
        service: String?,
        date: Date,
        message: String,
        error: DDError?,
        thread: String,
        networkInfoEnabled: Bool,
        userAttributes: [String: Encodable],
        internalAttributes: [String: Encodable]?
    ) {
        self.service = service
        self.date = date
        self.message = message
        self.error = error
        self.thread = thread
        self.networkInfoEnabled = networkInfoEnabled
        self.userAttributes = userAttributes
        self.internalAttributes = internalAttributes
    }
}
