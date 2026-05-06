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
    typealias LogsSetup = (inout Logs.Configuration) -> Void
    typealias LoggerSetup = (inout Logger.Configuration) -> Void

    /// Enables the Logs feature. Assumes the SDK has been initialized via `initializeSDK(...)`.
    func enableLogs(_ logsSetup: LogsSetup = { _ in }) {
        var config = Logs.Configuration()
        logsSetup(&config)
        Logs.enable(with: config, in: core)
    }

    /// Registers a persistent named logger. The logger is shared across all
    /// `withLogger(name:)` calls referencing the same name, preserving stateful
    /// modifications (tags, attributes) between steps.
    func createLogger(name: String = "default", setup: LoggerSetup = { _ in }) {
        var config = Logger.Configuration()
        setup(&config)
        loggers[name] = Logger.create(with: config, in: core)
    }

    /// Returns the named logger. Crashes via precondition if the logger was not
    /// registered first via `createLogger(name:)`.
    func logger(name: String = "default") -> LoggerProtocol {
        guard let existing = loggers[name] else {
            preconditionFailure("Logger '\(name)' was not registered. Call createLogger(name: \"\(name)\") first.")
        }
        return existing
    }

    /// Returns log matchers for events recorded during the test.
    func recordedLogs() throws -> [LogMatcher] {
        return try core.waitAndReturnLogMatchers()
    }
}
