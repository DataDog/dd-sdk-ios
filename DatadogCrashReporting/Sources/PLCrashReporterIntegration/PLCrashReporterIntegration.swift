/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

@preconcurrency import CrashReporter

internal extension PLCrashReporterConfig {
    struct Constants {
        /// The maximum number of bytes each stack trace can not exceed.
        /// When stack trace exceeds this limit, it will throw an error.
        static let maxReportBytes: UInt = 2 * 1_024 * 1_024 // 2MB
    }

    /// `PLCR` configuration used for `DatadogCrashReporting`
    static func ddConfiguration(maxReportBytes: UInt = Constants.maxReportBytes) throws -> PLCrashReporterConfig {
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
            // Flag indicating if the uncaughtExceptionHandler should be initialized or not. It usually is, except in a Xamarin environment.
            shouldRegisterUncaughtExceptionHandler: true,
            // Set a custom path to avoid conflicts with other PLC instances
            basePath: directory.path,
            // Set the maximum number of bytes if the crash report exceeds MAX_REPORT_BYTES
            maxReportBytes: maxReportBytes
        )
    }
}

internal final class PLCrashReporterIntegration: ThirdPartyCrashReporter {
    private let crashReporter: PLCrashReporter
    private let backtraceReporter: PLCrashReporter
    private let builder = DDCrashReportBuilder()

    init() throws {
        let configuration: PLCrashReporterConfig = try .ddConfiguration()
        self.crashReporter = PLCrashReporter(configuration: configuration)
        try crashReporter.enableAndReturnError()

        // Secondary instance for collecting Live Report for backtraces to prevent
        // race condition while accessing customData: PLCrashReporter's customData
        // is not thread-safe and is actually not needed for backtraces.
        //
        // This secondary instance doesn't need to and should not be enabled as it
        // will conflict with the primary one.
        self.backtraceReporter = PLCrashReporter(configuration: configuration)
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
        let liveReportData = try backtraceReporter.generateLiveReport(withThread: threadID, exception: nil)
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
