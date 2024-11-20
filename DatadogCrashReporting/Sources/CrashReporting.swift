/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Enable iOS Crash Reporting and Error Tracking to get comprehensive crash reports and
/// error trends with Real User Monitoring. With this feature, you can access:
///
/// - Aggregated iOS crash dashboards and attributes
/// - Symbolicated iOS crash reports
/// - Trend analysis with iOS error tracking
///
/// In order to symbolicate your stack traces, find and upload your .dSYM files to Datadog.
/// Then, verify your configuration by running a test crash and restarting your application.
///
/// Your crash reports appear in [Error Tracking](https://app.datadoghq.com/rum/error-tracking).
public final class CrashReporting {
    /// Initializes the Datadog Crash Reporter.
    public static func enable(in core: DatadogCoreProtocol = CoreRegistry.default) {
#if canImport(CrashReporter)
        enable(with: PLCrashReporterPlugin(), in: core)
#else
        assertionFailure()
#endif
    }

    public static func enable(with plugin: CrashReportingPlugin, in core: DatadogCoreProtocol = CoreRegistry.default) {
        do {
            let contextProvider = CrashContextCoreProvider()

            let reporter = CrashReportingFeature(
                crashReportingPlugin: plugin,
                crashContextProvider: contextProvider,
                sender: MessageBusSender(core: core),
                messageReceiver: contextProvider,
                telemetry: core.telemetry
            )

            try core.register(feature: reporter)

#if canImport(CrashReporter)
            if let plcr = PLCrashReporterPlugin.thirdPartyCrashReporter {
                try core.register(backtraceReporter: BacktraceReporter(reporter: plcr))
            }
#endif

            reporter.sendCrashReportIfFound()

            core.telemetry
                .configuration(trackErrors: true)
        } catch {
            consolePrint("\(error)", .error)
        }
    }

    public static func send(_ report: DDCrashReport, attributes: [AttributeKey: AttributeValue]? = nil, in core: DatadogCoreProtocol = CoreRegistry.default) {
        core.get(feature: CrashReportingFeature.self)?.send(report, attributes: attributes)
    }
}

/// Enable iOS Crash Reporting and Error Tracking to get comprehensive crash reports and
/// error trends with Real User Monitoring. With this feature, you can access:
///
/// - Aggregated iOS crash dashboards and attributes
/// - Symbolicated iOS crash reports
/// - Trend analysis with iOS error tracking
///
/// In order to symbolicate your stack traces, find and upload your .dSYM files to Datadog.
/// Then, verify your configuration by running a test crash and restarting your application.
///
/// Your crash reports appear in [Error Tracking](https://app.datadoghq.com/rum/error-tracking).
@available(swift, obsoleted: 1)
@objc(DDCrashReporter)
public final class objc_CrashReporting: NSObject {
    /// Initializes the Datadog Crash Reporter.
    @objc
    public static func enable() {
        CrashReporting.enable()
    }
}
