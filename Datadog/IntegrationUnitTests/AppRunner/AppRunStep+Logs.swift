/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
@testable import DatadogCore
@testable import DatadogLogs

extension AppRunStep {
    // MARK: - Logs Use Cases

    /// Enables the Logs feature. Assumes the SDK has been initialized via `initializeSDK(...)`.
    static func enableLogs(logsSetup: AppRunner.LogsSetup? = nil) -> AppRunStep {
        return AppRunStep({ app in
            app.enableLogs { logsConfig in
                logsSetup?(&logsConfig)
            }
        })
    }

    /// Registers a persistent named logger with optional configuration. Subsequent
    /// `withLogger(_ name:)` calls reuse this instance, preserving stateful
    /// modifications (tags, attributes) between steps.
    /// Must be called before the first `withLogger(_ name:)` for the same name.
    static func createLogger(
        _ name: String = "default",
        setup: AppRunner.LoggerSetup? = nil
    ) -> AppRunStep {
        return AppRunStep({ app in
            app.createLogger(name: name, setup: setup ?? { _ in })
        })
    }

    /// Performs an action against a named logger. The block can call any public
    /// API on the logger (debug/info/warn/error, addTag, addAttribute, …).
    /// Crashes if the logger was not registered first via `createLogger(_:setup:)`.
    /// To advance simulated time before the action, use a separate `advanceTime(by:)` step.
    static func withLogger(
        _ name: String = "default",
        _ block: @escaping (LoggerProtocol) -> Void
    ) -> AppRunStep {
        return AppRunStep({ app in
            block(app.logger(name: name))
        })
    }
}
