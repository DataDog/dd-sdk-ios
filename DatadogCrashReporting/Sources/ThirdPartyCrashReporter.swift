/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// An interface of 3rd party crash reporter used by the DatadogCrashReporting.
internal protocol ThirdPartyCrashReporter {
    /// Initializes and enables the crash reporter.
    init() throws

    /// Tells if there is a crash report available.
    func hasPendingCrashReport() -> Bool

    /// Loads pending crash report.
    func loadPendingCrashReport() throws -> DDCrashReport

    /// Injects custom `context` to the crash reporter so it will be attached to the `DDCrashReport`.
    func inject(context: Data)

    /// Deletes the available crash report.
    func purgePendingCrashReport() throws
}
