/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Provides the current RUM context attributes for produced `Logs`.
internal struct LoggingWithRUMContextIntegration {
    private let rumContextIntegration = RUMContextIntegration()

    /// Produces `Log` attributes describing the current RUM context.
    /// Returns `nil` and prints warning if global `RUMMonitor` is not registered.
    var currentRUMContextAttributes: [String: Encodable]? {
        guard let attributes = rumContextIntegration.currentRUMContextAttributes else {
            DD.logger.warn("RUM feature is enabled, but no `RUMMonitor` is registered. The RUM integration with Logging will not work.")
            return nil
        }

        return attributes
    }
}

/// Sends given `Log` as RUM Errors.
internal struct LoggingWithRUMErrorsIntegration {
    private let rumErrorsIntegration = RUMErrorsIntegration()

    func addError(for log: LogEvent) {
        rumErrorsIntegration.addError(
            with: log.error?.message ?? log.message,
            type: log.error?.kind,
            stack: log.error?.stack,
            source: .logger
        )
    }
}
