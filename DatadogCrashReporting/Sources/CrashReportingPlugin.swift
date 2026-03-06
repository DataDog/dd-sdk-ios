/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// An interface for enabling crash reporting feature in Datadog SDK.
///
/// The SDK calls each API on a background thread and succeeding calls are synchronized.
public protocol CrashReportingPlugin: AnyObject, Sendable {
    /// Reads unprocessed crash report if available.
    ///
    /// Returns the pending `DDCrashReport` if one is available, or `nil` otherwise.
    /// After processing the report, call ``deletePendingCrashReports()`` to purge it.
    func readPendingCrashReport() async -> DDCrashReport?

    /// Deletes all pending crash reports from storage.
    ///
    /// Call this after successfully reading and processing a crash report
    /// to prevent it from being reported again on the next launch.
    func deletePendingCrashReports()

    /// Injects custom data for describing the application state in the crash report.
    /// This data will be attached to produced crash report and will be available in `DDCrashReport`.
    ///
    /// The SDK calls this method for each significant application state change.
    /// It is called on a background thread and succeeding calls are synchronized.
    func inject(context: Data)

    /// An instance conforming to `BacktraceReporting` capable of generating backtrace reports.
    var backtraceReporter: BacktraceReporting? { get }
}
