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

    func receive(message: FeatureMessage) {
        guard case .telemetry(let telemetry) = message else {
            return
        }

        switch telemetry {
        case .error(_, _, let kind, _):
            interceptError(kind: kind)
        case .metric(let metric) where metric.name == UploadQualityMetric.name:
            interceptUploadQualityMetric(attributes: metric.attributes)
        default:
            break
        }
    }

    private func interceptError(kind: String) {
        sessionEndedMetric.track(sdkErrorKind: kind, in: nil) // `nil` - track in current session
    }

    private func interceptUploadQualityMetric(attributes: [String: Encodable]) {
        sessionEndedMetric.track(uploadQuality: attributes, in: nil) // `nil` - track in current session
    }
}
