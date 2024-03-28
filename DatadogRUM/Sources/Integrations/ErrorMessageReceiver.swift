/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal struct ErrorMessageReceiver: FeatureMessageReceiver {
    static let errorMessageKey = "error"

    struct ErrorMessage: Decodable {
        static let key = "error"

        /// The Log error message
        let message: String
        /// The Log error kind
        let type: String?
        /// The Log error stack
        let stack: String?
        /// The Log error stack
        let source: RUMInternalErrorSource
        /// The Log attributes
        let attributes: [String: AnyCodable]?
    }

    /// RUM feature scope.
    let featureScope: FeatureScope
    let monitor: Monitor

    /// Adds RUM Error with given message and stack to current RUM View.
    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        do {
            guard
                let error = try message.baggage(forKey: ErrorMessage.key, type: ErrorMessage.self)
            else {
                return false
            }

            monitor.addError(
                message: error.message,
                type: error.type,
                stack: error.stack,
                source: error.source,
                attributes: error.attributes ?? [:]
            )

            return true
        } catch {
            featureScope.telemetry
                .error("Fails to decode error message", error: error)
            return false
        }
    }
}
