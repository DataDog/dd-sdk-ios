/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import CrashReporter
import Datadog

internal final class PLCrashReporterIntegration: ThirdPartyCrashReporter {
    private let crashReporter: PLCrashReporter
    private let formatter = PLCrashReportFormatter()

    init() throws {
        self.crashReporter = PLCrashReporter(
            configuration: PLCrashReporterConfig(
                // The choice of `.BSD` over `.mach` is well discussed here:
                // https://github.com/ChatSecure/PLCrashReporter/blob/7f27b272d5ff0d6650fc41317127bb2378ed6e88/Source/CrashReporter.h#L238-L363
                signalHandlerType: .BSD,
                // We don't symbolicate on device. All symbolication will happen backend-side.
                symbolicationStrategy: []
            )
        )
        try crashReporter.enableAndReturnError()
    }

    func hasPendingCrashReport() -> Bool {
        return crashReporter.hasPendingCrashReport()
    }

    func loadPendingCrashReport() throws -> DDCrashReport {
        let crashReportData = try crashReporter.loadPendingCrashReportDataAndReturnError()
        let crashReport = try PLCrashReport(data: crashReportData)
        return formatter.ddCrashReport(from: crashReport)
    }

    func inject(context: Data) {
        crashReporter.customData = context
    }

    func purgePendingCrashReport() throws {
        try crashReporter.purgePendingCrashReportAndReturnError()
    }
}
