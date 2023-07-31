/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal struct ErrorMessageReceiver: FeatureMessageReceiver {
    let monitor: Monitor

    /// Adds RUM Error with given message and stack to current RUM View.
    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        guard
            case let .error(message, attributes) = message,
            let source = attributes["source", type: RUMInternalErrorSource.self]
        else {
            return false
        }

        monitor.addError(
            message: message,
            type: attributes["type"],
            stack: attributes["stack"],
            source: source,
            attributes: attributes["attributes"] ?? [String: AnyCodable]()
        )

        return true
    }
}
