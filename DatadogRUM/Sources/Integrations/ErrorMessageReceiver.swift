/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal struct ErrorMessageReceiver: FeatureMessageReceiver {
    /// RUM feature scope.
    let featureScope: FeatureScope
    let monitor: Monitor

    /// Adds RUM Error with given message and stack to current RUM View.
    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        guard case let .payload(error as LogErrorMessage) = message else {
            return false
        }

        monitor._internal?.addError(
            at: error.time,
            message: error.message,
            type: error.type,
            stack: error.stack,
            source: .logger,
            globalAttributes: [:],
            attributes: error.attributes,
            binaryImages: error.binaryImages
        )

        return true
    }
}
