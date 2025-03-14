/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Common definitions for batch telemetries.
internal enum BatchMetric {
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
        case "session-replay-resources":  return "sr-resources"
        default:                return nil
        }
    }
    /// Consent label key.
    /// It is added to differentiate telemetries for batches handled in `pending` and `granted` consents.
    static let consentKey = "consent"
    /// "granted" consent value.
    static let consentGrantedValue = "granted"
    /// "pending" consent value.
    static let consentPendingValue = "pending"
}

/// Definition of "Batch Deleted" telemetry.
internal enum BatchDeletedMetric {
    /// The name of this metric, included in telemetry log.
    /// Note: the "[Mobile Metric]" prefix is added when sending this telemetry in RUM.
    static let name = "Batch Deleted"
    /// Metric type value.
    static let typeValue = "batch deleted"
    /// The sample rate for this metric.
    /// It is applied in addition to the telemetry sample rate (20% by default).
    static let sampleRate: Float = 1.5 // 1.5%
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
    /// If the background tasks were enabled.
    static let backgroundTasksEnabled = "background_tasks_enabled"

    /// Count of pending batches left on track.
    static let pendingBatches = "pending_batches"

    /// Allowed values for `batchRemovalReasonKey`.
    enum RemovalReason {
        /// The batch was delivered to Intake and deleted upon receiving given `responseCode`.
        ///
        /// The intake-code-202 represents a successful delivery. While some status codes, such as 401, indicate unrecoverable
        /// user errors, others, like 400, will indicate faults within the SDK. It is important to note that not all status codes will appear
        /// in this field, as the SDKs implement retry mechanisms for certain codes, e.g. 503 (see: ``DataUploadStatus``).
        case intakeCode(responseCode: Int?)
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
        func toString() -> String {
            switch self {
            case .intakeCode(let responseCode):
                return "intake-code-\(responseCode.map { String($0) } ?? "unknown")"
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

/// Definition of "Batch Closed" telemetry.
internal enum BatchClosedMetric {
    /// The name of this metric, included in telemetry log.
    /// Note: the "[Mobile Metric]" prefix is added when sending this telemetry in RUM.
    static let name = "Batch Closed"
    /// Metric type value.
    static let typeValue = "batch closed"
    /// The sample rate for this metric.
    /// It is applied in addition to the telemetry sample rate (20% by default).
    static let sampleRate: Float = 1.5 // 1.5%
    /// The default duration since last write (in ms) after which the uploader considers the file to be "ready for upload".
    static let uploaderWindowKey = "uploader_window"

    /// The size of batch at closing (in bytes).
    static let batchSizeKey = "batch_size"
    /// The number of events written to this batch before closing.
    static let batchEventsCountKey = "batch_events_count"
    /// The duration from batch creation to batch closing (in ms).
    static let batchDurationKey = "batch_duration"
    /// If the batch was closed by core or after new batch was forced by the feature.
    static let forcedNewKey = "forced_new"
}

/// Definition of "Batch Blocked" telemetry.
internal enum BatchBlockedMetric {
    /// The name of this metric, included in telemetry log.
    /// Note: the "[Mobile Metric]" prefix is added when sending this telemetry in RUM.
    static let name = "Batch Blocked"
    /// Metric type value.
    static let typeValue = "batch blocked"
    /// The sample rate for this metric.
    /// It is applied in addition to the telemetry sample rate (20% by default).
    static let sampleRate: Float = 1.5 // 1.5%
    /// The key for uploader's current delay.
    static let uploaderDelayKey = "uploader_delay.current"
    /// The key for count of bacthes being blocked.
    static let batchCount = "batch_count"

    /// List of upload blockers
    static let blockers = "blockers"
    static let failure = "failure"
}
