/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Receives flag exposure messages and adds them as custom RUM actions.
internal struct FlagExposureReceiver: FeatureMessageReceiver {
    private enum Constants {
        static let exposureActionName = "__dd_exposure"
    }
    /// The RUM monitor instance.
    let monitor: Monitor

    /// Adds flag exposure as a custom RUM action.
    func receive(message: FeatureMessage, from core: any DatadogCoreProtocol) -> Bool {
        guard case let .payload(exposure as RUMFlagExposureMessage) = message else {
            return false
        }

        monitor.addAction(
            type: .custom,
            name: Constants.exposureActionName,
            attributes: [
                "timestamp": exposure.timestamp.toInt64Milliseconds,
                "flag_key": exposure.flagKey,
                "allocation_key": exposure.allocationKey,
                "exposure_key": exposure.exposureKey,
                "subject_key": exposure.subjectKey,
                "variant_key": exposure.variantKey,
                "subject_attributes": AnyEncodable(exposure.subjectAttributes)
            ]
        )

        return true
    }
}
