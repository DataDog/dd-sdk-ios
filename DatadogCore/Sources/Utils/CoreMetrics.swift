/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Definition of "Batch Deleted" telemetry.
internal enum BatchDeletedMetric {
    /// The name of this metric, included in telemetry log.
    /// Note: the "[Mobile Metric]" prefix is added when sending this telemetry in RUM.
    static let name = "Batch Deleted"

    /// Metric type key.
    static let typeKey = "metric_type"
    /// Metric type value.
    static let typeValue = "batch deleted"

    /// Track name key
    static let trackKey = "track"
    /// Track name value.
    /// Returns the corresponding track value based on the given feature name.
    static func trackValue(for featureName: String) -> String? {
        switch featureName {
        case "rum":             return "rum"
        case "logging":         return "logs"
        case "tracing":         return "trace"
        case "session-replay":  return "sr"
        default:                return nil
        }
    }

    /// The key for uploader's delay options.
    static let uploaderDelayKey = "uploader_delay"
    /// The min delay of uploads for this track (in ms).
    static let uploaderDelayMinKey = "min"
    /// The min delay of uploads for this track (in ms).
    static let uploaderDelayMaxKey = "max"
    /// The default duration since last write (in ms) after which the uploader considers the file to be "ready for upload".
    static let uploaderWindowKey = "uploader_window"

    /// The duration from batch creation to batch deletion (in ms).
    static let batchAgeKey = "batch_age"
    /// The reason of batch deletion.
    static let batchRemovalReasonKey = "batch_removal_reason"
    /// If the batch was deleted in the background.
    static let inBackgroundKey = "in_background"

    /// Allowed values for `batchRemovalReasonKey`.
    enum RemovalReason {
        /// The batch was delivered to Intake and deleted upon receiving given `responseCode`.
        ///
        /// The intake-code-202 represents a successful delivery. While some status codes, such as 401, indicate unrecoverable
        /// user errors, others, like 400, will indicate faults within the SDK. It is important to note that not all status codes will appear
        /// in this field, as the SDKs implement retry mechanisms for certain codes, e.g. 503 (see: ``DataUploadStatus``).
        case intakeCode(responseCode: Int)
        /// The batch become obsolete (older than allowed limit for this track's intake).
        case obsolete
        /// The batch was deleted due to exceeding allowed max size for batches directory.
        case purged
        /// The feature failed to create request for that batch (e.g. data was malformed).
        case invalid
        /// The batch was deleted arbitrarily without considering its delivery status. This option is only used in test logic
        /// and we don't send "Batch Deleted" metric for this case.
        case flushed

        /// Converts the removal reason to the string value expected for `batchRemovalReasonKey`.
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

        /// Indicates whether the metric should be sent for this removal reason.
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
