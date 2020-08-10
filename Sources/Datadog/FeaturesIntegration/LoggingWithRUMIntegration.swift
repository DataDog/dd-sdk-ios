/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Global `RUMMonitor` (if registered).
private var rumMonitor: RUMMonitor? { RUMMonitor.shared }

/// Provides the current RUM context attributes to produced Logs.
internal struct LoggingWithRUMContextIntegration {
    internal struct RUMLogAttributes {
        static let applicationID = "application_id"
        static let sessionID = "session_id"
        static let viewID = "view.id"
    }

    /// Produces `Log` attributes describing the current RUM context.
    /// Returns `nil` and prints warning if global `RUMMonitor` is not registered.
    var currentRUMContextAttributes: [String: Encodable]? {
        guard let rumContext = rumMonitor?.contextProvider.context else {
            userLogger.warn("No `RUMMonitor` is registered, so RUM integration with Logging will not work.")
            return nil
        }

        return [
            RUMLogAttributes.applicationID: rumContext.rumApplicationID,
            RUMLogAttributes.sessionID: rumContext.sessionID.rawValue.uuidString.lowercased(),
            RUMLogAttributes.viewID: rumContext.activeViewID?.rawValue.uuidString.lowercased(),
        ]
    }
}

/// Creates RUM Errors for Logs.
internal struct LoggingWithRUMErrorsIntegration {
    /// Adds RUM Error with given message to current RUM View.
    func addError(with logMessage: String) {
        rumMonitor?.addViewError(message: logMessage, source: .logger, attributes: nil, file: nil, line: nil)
    }
}
