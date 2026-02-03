/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

public struct Crash {
    /// The crash report.
    public let report: DDCrashReport
    /// The crash context
    public let context: CrashContext

    /// Creates a Crash to be transmited on the message-bus.
    ///
    /// - Parameters:
    ///   - report: The crash report.
    ///   - context: The crash context
    public init(report: DDCrashReport, context: CrashContext) {
        self.report = report
        self.context = context
    }
}
