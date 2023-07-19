/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Definition of "Batch Deleted" telemetry.
internal enum BatchDeletedMetric {
    static let name = "[Mobile Metric] Batch Deleted"
    static let typeKey = "metricType"
    static let typeValue = "batch deleted"

    /// The name of the “track” that this batch belonged to.
    static let trackKey = "track"

    static func trackValue(for featureName: String) -> String? {
        switch featureName {
        case "rum":             return "rum"
        case "logging":         return "logs"
        case "tracing":         return "trace"
        case "session-replay":  return "sr"
        default:                return nil
        }
    }

    static let uploaderDelayMinKey = "uploaderDelayMin"
    static let uploaderWindowKey = "uploaderWindow"
    static let batchAgeKey = "batchAge"
    static let batchRemovalReasonKey = "batchRemovalReason"
    static let inBackgroundKey = "inBackground"

    enum RemovalReason {
        case intakeCode(responseCode: Int)
        case obsolete
        case purged
        case invalid
        case flushed

        var asString: String {
            switch self {
            case .intakeCode(let responseCode):
                return "intake-code-\(responseCode)"
            case .obsolete:
                return "obsolete"
            case .purged:
                return "purged"
            case .invalid:
                return "invalid"
            case .flushed:
                return "flushed"
            }
        }

        var includeInMetric: Bool {
            switch self {
            case .intakeCode, .obsolete, .purged, .invalid:
                return true
            case .flushed:
                return false
            }
        }
    }
}
