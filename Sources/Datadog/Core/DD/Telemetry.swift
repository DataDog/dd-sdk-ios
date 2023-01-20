/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// The `Telemetry` protocol defines methods to collect debug information
/// and detect execution errors of the Datadog SDK.
internal protocol Telemetry {
    /// Collects debug information.
    ///
    /// - Parameters:
    ///   - id: Identity of the debug log, this can be used to prevent duplicates.
    ///   - message: The debug message.
    func debug(id: String, message: String)

    /// Collect execution error.
    /// 
    /// - Parameters:
    ///   - id: Identity of the debug log, this can be used to prevent duplicates.
    ///   - message: The error message.
    ///   - kind: The kind of error.
    ///   - stack: The stack trace.
    func error(id: String, message: String, kind: String?, stack: String?)

    /// Sends a `TelemetryConfigurationEvent` event.
    ///
    /// - Parameters:
    ///   - configuration: The current configuration
    func configuration(configuration: FeaturesConfiguration)
}

extension Telemetry {
    /// Collects debug information.
    ///
    /// - Parameters:
    ///   - message: The debug message.
    ///   - file: The current file name.
    ///   - line: The line number in file.
    func debug(_ message: String, file: String = #file, line: Int = #line) {
        debug(id: "\(file):\(line):\(message)", message: message)
    }

    /// Collect execution error.
    ///
    /// - Parameters:
    ///   - message: The error message.
    ///   - stack: The stack trace.
    ///   - file: The current file name.
    ///   - line: The line number in file.
    ///   - file: The current file name.
    ///   - line: The line number in file.
    func error(_ message: String, kind: String? = nil, stack: String? = nil, file: String = #file, line: Int = #line) {
        error(id: "\(file):\(line):\(message)", message: message, kind: kind, stack: stack)
    }

    /// Collect execution error.
    ///
    /// - Parameters:
    ///   - error: The error.
    ///   - file: The current file name.
    ///   - line: The line number in file.
    func error(_ error: DDError, file: String = #file, line: Int = #line) {
        self.error(error.message, kind: error.type, stack: error.stack, file: file, line: line)
    }

    /// Collect execution error.
    ///
    /// - Parameters:
    ///   - message: The error message.
    ///   - error: The error.
    ///   - file: The current file name.
    ///   - line: The line number in file.
    func error(_ message: String, error: DDError, file: String = #file, line: Int = #line) {
        self.error("\(message) - \(error.message)", kind: error.type, stack: error.stack, file: file, line: line)
    }

    /// Collect execution error.
    ///
    /// - Parameters:
    ///   - error: The error.
    ///   - file: The current file name.
    ///   - line: The line number in file.
    func error(_ error: Error, file: String = #file, line: Int = #line) {
        self.error(DDError(error: error), file: file, line: line)
    }

    /// Collect execution error.
    ///
    /// - Parameters:
    ///   - message: The error message.
    ///   - error: The error.
    ///   - file: The current file name.
    ///   - line: The line number in file.
    func error(_ message: String, error: Error, file: String = #file, line: Int = #line) {
        self.error(message, error: DDError(error: error), file: file, line: line)
    }
}

internal struct NOPTelemetry: Telemetry {
    func debug(id: String, message: String) {}
    func error(id: String, message: String, kind: String?, stack: String?) {}
    func configuration(configuration: FeaturesConfiguration) {}
}
