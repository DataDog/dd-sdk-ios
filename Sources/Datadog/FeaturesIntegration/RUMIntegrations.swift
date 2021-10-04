/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Global `RUMMonitor` (if registered).
private var rumMonitor: RUMMonitor? { Global.rum as? RUMMonitor }

/// Integration providing the current RUM context attributes.
internal struct RUMContextIntegration {
    struct Attributes {
        static let applicationID = "application_id"
        static let sessionID = "session_id"
        static let viewID = "view.id"
        static let actionID = "user_action.id"
    }

    /// Returns attributes describing the current RUM context or `nil`if global `RUMMonitor` is not registered.
    var currentRUMContextAttributes: [String: Encodable]? {
        guard let rumContext = rumMonitor?.contextProvider.context else {
            return nil
        }

        if rumContext.sessionID == .nullUUID { // if Session was sampled or not yet started
            return [:]
        }

        return [
            Attributes.applicationID: rumContext.rumApplicationID,
            Attributes.sessionID: rumContext.sessionID.rawValue.uuidString.lowercased(),
            Attributes.viewID: rumContext.activeViewID?.rawValue.uuidString.lowercased(),
            Attributes.actionID: rumContext.activeUserActionID?.rawValue.uuidString.lowercased(),
        ]
    }
}

/// Creates RUM Errors with given message.
internal struct RUMErrorsIntegration {
    /// Adds RUM Error with given message and stack to current RUM View.
    func addError(with message: String, type: String?, stack: String?, source: RUMInternalErrorSource, attributes: [AttributeKey: AttributeValue] = [:]) {
        rumMonitor?.addError(message: message, type: type, stack: stack, source: source, attributes: attributes)
    }
}
