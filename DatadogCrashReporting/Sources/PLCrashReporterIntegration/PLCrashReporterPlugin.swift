/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if canImport(CrashReporter)

import Foundation
import DatadogInternal

/// The implementation of `Datadog.DDCrashReportingPluginType`.
/// Pass its instance as the crash reporting plugin for Datadog SDK to enable crash reporting feature.
@objc
internal class PLCrashReporterPlugin: NSObject, CrashReportingPlugin {
    static var thirdPartyCrashReporter: ThirdPartyCrashReporter?

    // MARK: - Initialization

    override convenience init() {
        self.init { try PLCrashReporterIntegration() }
    }

    internal init(thirdPartyCrashReporterFactory: () throws -> ThirdPartyCrashReporter) {
        PLCrashReporterPlugin.enableOnce(using: thirdPartyCrashReporterFactory)
    }

    private static func enableOnce(using thirdPartyCrashReporterFactory: () throws -> ThirdPartyCrashReporter) {
        if thirdPartyCrashReporter == nil {
            do {
                thirdPartyCrashReporter = try thirdPartyCrashReporterFactory()
            } catch {
                consolePrint("🔥 DatadogCrashReporting error: failed to enable crash reporter: \(error)", .error)
            }
        }
    }

    // MARK: - DDCrashReportingPluginType

    func readPendingCrashReport(completion: (DDCrashReport?) -> Bool) {
        guard let crashReporter = PLCrashReporterPlugin.thirdPartyCrashReporter,
              crashReporter.hasPendingCrashReport() else {
            _ = completion(nil)
            return
        }

        do {
            let crashReport = try crashReporter.loadPendingCrashReport()
            let wasProcessed = completion(crashReport)

            if wasProcessed {
                try? crashReporter.purgePendingCrashReport()
            }
        } catch {
            _ = completion(nil)
            consolePrint("🔥 DatadogCrashReporting error: failed to load crash report: \(error)", .error)
        }
    }

    func inject(context: Data) {
        PLCrashReporterPlugin.thirdPartyCrashReporter?.inject(context: context)
    }
}

#endif
