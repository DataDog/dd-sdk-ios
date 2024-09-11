/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal
@preconcurrency import CrashReporter

internal extension PLCrashReporterConfig {
    /// `PLCR` configuration used for `DatadogCrashReporting`
    static func ddConfiguration() throws -> PLCrashReporterConfig {
        let version = "v1"

        guard let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            throw CrashReportException(description: "Cannot obtain `/Library/Caches/` url.")
        }

        let directory = cache.appendingPathComponent("com.datadoghq.crash-reporting/\(version)", isDirectory: true)

        return PLCrashReporterConfig(
            // The choice of `.BSD` over `.mach` is well discussed here:
            // https://github.com/microsoft/PLCrashReporter/blob/7f27b272d5ff0d6650fc41317127bb2378ed6e88/Source/CrashReporter.h#L238-L363
            signalHandlerType: .BSD,
            // We don't symbolicate on device. All symbolication will happen backend-side.
            symbolicationStrategy: [],
            // Set a custom path to avoid conflicts with other PLC instances
            basePath: directory.path
        )
    }
}

internal final class PLCrashReporterIntegration: ThirdPartyCrashReporter {
    private let crashReporter: PLCrashReporter
    private let builder = DDCrashReportBuilder()

    init() throws {
        self.crashReporter = try PLCrashReporter(configuration: .ddConfiguration())
        try crashReporter.enableAndReturnError()
    }

    func hasPendingCrashReport() -> Bool {
        return crashReporter.hasPendingCrashReport()
    }

    func loadPendingCrashReport() throws -> DDCrashReport {
        let crashReportData = try crashReporter.loadPendingCrashReportDataAndReturnError()
        let crashReport = try PLCrashReport(data: crashReportData)
        let ddCrashReport = try builder.createDDCrashReport(from: crashReport)
        return ddCrashReport
    }

    func inject(context: Data) {
        crashReporter.customData = context
    }

    func purgePendingCrashReport() throws {
        try crashReporter.purgePendingCrashReportAndReturnError()
    }

    func generateBacktrace(threadID: ThreadID) throws -> BacktraceReport {
        let liveReportData = crashReporter.generateLiveReport(withThread: threadID)
        let liveReport = try PLCrashReport(data: liveReportData)

        // This is quite opportunistic - we map PLCR's live report through existing `DDCrashReport` builder to
        // then extract essential elements for assembling `BacktraceReport`. It works for now, but be careful
        // with how this evolves. We may need a dedicated `BacktraceReport` builder that only shares some code
        // with `DDCrashReport` builder.
        let crashReport = try builder.createDDCrashReport(from: liveReport)
        return BacktraceReport(
            stack: crashReport.stack,
            threads: crashReport.threads.map { thread in
                var thread = thread
                // PLCR sets `crashed` flag for the primary thread in `liveReport`. Because we're not dealing with the crash situation
                // we reset this flag accordingly.
                thread.crashed = false
                return thread
            },
            binaryImages: crashReport.binaryImages,
            wasTruncated: crashReport.wasTruncated
        )
    }
}
