/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// An intermediate representation of an App Hang.
internal struct AppHang: Codable {
    /// The result of generating backtrace for this hang.
    enum BacktraceGenerationResult: Codable {
        /// Indicates that backtrace generation succeeded.
        /// The associated `BacktraceReport` includes the snapshot of all running threads during the hang.
        case succeeded(BacktraceReport)
        /// Indicates that backtrace generation failed due to an internal error.
        case failed
        /// Indicates that backtrace generation is unavailable.
        /// It is the case when `BacktraceReportingFeature` is not available in core (when Crash Reporting feature was not enabled).
        case notAvailable
    }

    /// The date of hang start.
    /// It is defined as device time, without considering NTP offset.
    let startDate: Date
    /// The result of generating backtrace for the hang.
    let backtraceResult: BacktraceGenerationResult
}

/// Persisted information on App Hang that may likely become fatal.
///
/// It encodes all information necessary to report error on app restart.
internal struct FatalAppHang: Codable {
    /// An identifier of the process that the hang was recorded in.
    let processID: UUID
    /// The actual hang that was recorded.
    let hang: AppHang
    /// Interval between device and server time at the moment of hang's recording.
    let serverTimeOffset: TimeInterval
    /// The last RUM view at the moment of hang's recording.
    let lastRUMView: RUMViewEvent
    /// The user's consent at the moment of hang's recording.
    let trackingConsent: TrackingConsent
}
