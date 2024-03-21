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
    let startDate: Date
    /// The result of generating backtrace for the hang.
    let backtraceResult: BacktraceGenerationResult
}
