/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Datadog
import Foundation

/// The implementation of `Datadog.DDCrashReportingPluginType`.
/// Pass its instance as the crash reporting plugin for Datadog SDK to enable crash reporting feature.
@objc
public class DDCrashReportingPlugin: NSObject, DDCrashReportingPluginType {
    static var thirdPartyCrashReporter: ThirdPartyCrashReporter?

    // MARK: - Initialization

    override public convenience init() {
        self.init { try PLCrashReporterIntegration() }
    }

    internal init(thirdPartyCrashReporterFactory: () throws -> ThirdPartyCrashReporter) {
        DDCrashReportingPlugin.enableOnce(using: thirdPartyCrashReporterFactory)
    }

    private static func enableOnce(using thirdPartyCrashReporterFactory: () throws -> ThirdPartyCrashReporter) {
        if thirdPartyCrashReporter == nil {
            do {
                thirdPartyCrashReporter = try thirdPartyCrashReporterFactory()
            } catch {
                consolePrint("🔥 DatadogCrashReporting error: failed to enable crash reporter: \(error)")
            }
        }
    }

    // MARK: - DDCrashReportingPluginType

    public func readPendingCrashReport(completion: (DDCrashReport?) -> Bool) {
        guard let crashReporter = DDCrashReportingPlugin.thirdPartyCrashReporter,
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
            consolePrint("🔥 DatadogCrashReporting error: failed to load crash report: \(error)")
        }
    }

    public func inject(context: Data) {
        DDCrashReportingPlugin.thirdPartyCrashReporter?.inject(context: context)
    }
}

// MARK: - Utils

/// Function printing `String` content to console.
internal var consolePrint: (String) -> Void = { content in
    print(content)
}
