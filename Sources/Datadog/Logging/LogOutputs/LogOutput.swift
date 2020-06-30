/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

internal struct LogAttributes {
    /// Log attributes received from the user. They are subject for sanitization.
    let userAttributes: [String: Encodable]
    /// Log attributes added internally by the SDK. They are not a subject for sanitization.
    let internalAttributes: [String: Encodable]?
}

/// Type writting logs to some destination.
internal protocol LogOutput {
    func writeLogWith(level: LogLevel, message: String, date: Date, attributes: LogAttributes, tags: Set<String>)
}
