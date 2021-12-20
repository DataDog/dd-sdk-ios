/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import CrashReporter
import Datadog

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
#if DD_SDK_ENABLE_INTERNAL_MONITORING
        ddCrashReport.diagnosticInfo = [
            "diagnostic-info": PLCrashReportDiagnosticInfo(crashReport)
        ]
#endif
        return ddCrashReport
    }

    func inject(context: Data) {
        crashReporter.customData = context
    }

    func purgePendingCrashReport() throws {
        try crashReporter.purgePendingCrashReportAndReturnError()
    }
}

#if DD_SDK_ENABLE_INTERNAL_MONITORING
/// Diagnostic information about the crash report, collected for `DatadogCrashReporting` observability.
/// Available only if internal monitoring is enabled, disabled by default.
/// See: `Datadog.Configuration.Builder.enableInternalMonitoring(clientToken:)`.
private struct PLCrashReportDiagnosticInfo: Encodable {
    private let numberOfImages: Int
    private let numberOfSystemImages: Int
    private let numberOfUserImages: Int
    private let hasCrashDate: Bool
    private let numberOfThreads: Int
    private let numberOfStackFramesPerThread: [String: Int]
    private let numberOfStackFramesInCrashedThread: Int

    init(_ crashReport: PLCrashReport) {
        let images = crashReport.images?.compactMap { $0 as? PLCrashReportBinaryImageInfo }
        self.numberOfImages = images?.count ?? -1

        var userImagesCount = 0
        var systemImagesCount = 0
        images?.forEach { image in
            if (image.imageName ?? "").hasPrefix("/private/var") {
                // e.g. `/private/var/containers/Bundle/Application/<UUID>/Example.app/Frameworks/<F>.framework/<F>`
                userImagesCount += 1
            } else {
                // e.g. `/usr/lib/libobjc-trampolines.dylib` or `/System/Library/PrivateFrameworks/AssertionServices.framework/AssertionServices`
                systemImagesCount += 1
            }
        }
        self.numberOfUserImages = userImagesCount
        self.numberOfSystemImages = systemImagesCount

        self.hasCrashDate = crashReport.systemInfo?.timestamp != nil

        let threads = crashReport.threads?.compactMap { $0 as? PLCrashReportThreadInfo }
        self.numberOfThreads = threads?.count ?? -1

        var numberOfStackFramesInCrashedThread = -1
        var stackFramesByThread: [String: Int] = [:]
        threads?.forEach { thread in
            stackFramesByThread["thread-\(thread.threadNumber)"] = thread.stackFrames?.count ?? -1
            if thread.crashed {
                numberOfStackFramesInCrashedThread = thread.stackFrames?.count ?? -1
            }
        }
        self.numberOfStackFramesPerThread = stackFramesByThread
        self.numberOfStackFramesInCrashedThread = numberOfStackFramesInCrashedThread
    }
}

#endif
