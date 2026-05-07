/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal
import TestUtilities
@testable import DatadogCore
@testable import DatadogLogs

extension AppRunner {
    /// Registered loggers, keyed by name. Backed by `state["loggers"]`.
    var loggers: [String: LoggerProtocol] {
        get { state["loggers"] as? [String: LoggerProtocol] ?? [:] }
        set { state["loggers"] = newValue }
    }

    /// The default logger, registered under the `"default"` key in `loggers`.
    /// Crashes (IUO semantics) if read before assignment.
    var logger: LoggerProtocol! {
        get { loggers["default"] }
        set {
            if let newValue {
                loggers["default"] = newValue
            } else {
                loggers.removeValue(forKey: "default")
            }
        }
    }

    /// Returns log matchers for events recorded during the test.
    func recordedLogs() throws -> [LogMatcher] {
        return try core.waitAndReturnLogMatchers()
    }
}
