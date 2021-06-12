/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

@testable import DatadogCrashReporting
@testable import Datadog

internal class ThirdPartyCrashReporterMock: ThirdPartyCrashReporter {
    static var initializationError: Error?

    var pendingCrashReport: DDCrashReport?
    var pendingCrashReportError: Error?

    var injectedContext: Data?

    var hasPurgedPendingCrashReport = false
    var hasPurgedPendingCrashReportError: Error?

    required init() throws {
        if let error = ThirdPartyCrashReporterMock.initializationError {
            throw error
        }
    }

    func hasPendingCrashReport() -> Bool {
        return pendingCrashReport != nil
    }

    func loadPendingCrashReport() throws -> DDCrashReport {
        if let error = pendingCrashReportError {
            throw error
        }
        return pendingCrashReport!
    }

    func inject(context: Data) {
        injectedContext = context
    }

    func purgePendingCrashReport() throws {
        if let error = hasPurgedPendingCrashReportError {
            throw error
        }
        hasPurgedPendingCrashReport = true
    }
}

internal extension DDCrashReport {
    static func mockAny() -> DDCrashReport {
        return DDCrashReport(
            date: Date(),
            type: "any type",
            message: "any message",
            stackTrace: "any stack trace",
            context: "any context".data(using: .utf8)
        )
    }
}

internal struct ErrorMock: Error, CustomStringConvertible {
    let description: String
}
