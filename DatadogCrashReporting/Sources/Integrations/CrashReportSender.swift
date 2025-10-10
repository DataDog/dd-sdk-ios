/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogInternal

/// An object for sending crash reports.
internal protocol CrashReportSender {
    /// Send the crash report and context to integrations.
    ///
    /// - Parameters:
    ///   - report: The crash report.
    ///   - context: The crash context
    func send(report: DDCrashReport, with context: CrashContext)

    /// Send the launch report and context to integrations.
    ///
    /// - Parameters:
    ///   - launch: The launch report.
    func send(launch: LaunchReport)
}

/// An object for sending crash reports on the Core message-bus.
internal struct MessageBusSender: CrashReportSender {
    /// The core for sending crash report and context.
    ///
    /// It must be a weak reference to avoid retain cycle (the `CrashReportSender` is held by crash reporting
    /// integration kept by core).
    weak var core: DatadogCoreProtocol?

    /// Send the crash report et context on the bus of the core.
    ///
    /// - Parameters:
    ///   - report: The crash report.
    ///   - context: The crash context
    func send(report: DDCrashReport, with context: CrashContext) {
        guard let core = core, context.trackingConsent == .granted else {
            DD.logger.debug("Skipped sending Crash Report as it was recorded with \(context.trackingConsent) consent")
            return
        }

        core.send(
            message: .payload(
                Crash(report: report, context: context)
            ),
            else: {
                DD.logger.warn(
                    """
                    In order to use Crash Reporting, RUM feature must be enabled.
                    Make sure `RUM.enable(with:)` is called when initializing Datadog SDK.
                    """
                )
            }
        )
    }

    /// Send the launch report and context to integrations.
    ///
    /// - Parameters:
    ///   - launch: The launch report.
    func send(launch: DatadogInternal.LaunchReport) {
        core?.set(context: launch)
    }
}
