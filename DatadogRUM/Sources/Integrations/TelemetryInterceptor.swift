/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Intercepts telemetry events sent through message bus.
internal struct TelemetryInterceptor: FeatureMessageReceiver {
    /// "RUM Session Ended" controller to count SDK errors.
    let sessionEndedMetric: SessionEndedMetricController

    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        guard case .telemetry(let telemetry) = message else {
            return false
        }

        switch telemetry {
        case .error(let id, let message, let kind, let stack):
            interceptError(id: id, message: message, kind: kind, stack: stack)
        case let .metric(.report(metric)) where metric.name == UploadCycleMetric.name:
            // Intercept the 'upload_cycle' metric for aggregation in the rse
            // metric
            interceptUploadCycleMetric(attributes: metric.attributes)
            return true // do not forward the message

        default:
            break
        }

        return false // do not consume, pass to next receivers
    }

    private func interceptError(id: String, message: String, kind: String, stack: String) {
        sessionEndedMetric.track(sdkErrorKind: kind, in: nil) // `nil` - track in current session
    }

    private func interceptUploadCycleMetric(attributes: [String: Encodable]) {
        sessionEndedMetric.track(uploadCycle: attributes, in: nil) // `nil` - track in current session
    }
}
