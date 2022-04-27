/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2022 Datadog, Inc.
 */

import Foundation

/// The `Telemetry` protocol defines methods to collect debug information
/// and detect execution errors of the Datadog SDK.
internal protocol Telemetry {
    /// Collects debug information.
    ///
    /// - Parameter message: The debug message.
    func debug(_ message: String)

    /// Collect execution error.
    /// 
    /// - Parameters:
    ///   - message: The error message.
    ///   - kind: The kind of error.
    ///   - stack: The stack trace.
    func error(_ message: String, kind: String?, stack: String?)
}

extension Telemetry {
    /// Collect execution error.
    ///
    /// - Parameters:
    ///   - message: The error message.
    ///   - kind: The kind of error.
    func error(_ message: String, kind: String) {
        error(message, kind: kind, stack: nil)
    }

    /// Collect execution error.
    ///
    /// - Parameters:
    ///   - message: The error message.
    ///   - stack: The stack trace.
    func error(_ message: String, stack: String? = nil) {
        error(message, kind: nil, stack: stack)
    }
}
