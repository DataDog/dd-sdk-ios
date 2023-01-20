/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

/// An object for sending crash reports.
internal protocol CrashReportSender {
    /// Send the crash report et context to integrations.
    ///
    /// - Parameters:
    ///   - report: The crash report.
    ///   - context: The crash context
    func send(report: DDCrashReport, with context: CrashContext)
}

/// An object for sending crash reports on the Core message-bus.
internal struct MessageBusSender: CrashReportSender {
    /// Defines keys referencing Crash Report message on the bus.
    internal enum MessageKeys {
        /// The key for a crash message.
        ///
        /// Use this key when the crash should be reported
        /// as a RUM event.
        static let crash = "crash"

        /// The key for a crash log message.
        ///
        /// Use this key when the crash should be reported
        /// as a log event.
        static let crashLog = "crash-log"
    }

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
        guard context.trackingConsent == .granted else {
            return
        }

        sendRUM(
            baggage: [
                "report": report,
                "context": context
            ]
        )
    }

    private func sendRUM(baggage: FeatureBaggage) {
        core?.send(
            message: .custom(key: MessageKeys.crash, baggage: baggage),
            else: { self.sendLog(baggage: baggage) }
        )
    }

    private func sendLog(baggage: FeatureBaggage) {
        core?.send(
            message: .custom(key: MessageKeys.crashLog, baggage: baggage),
            else: printError
        )
    }

    private func printError() {
        // This case is not reachable in higher abstraction but we add sanity warning.
        DD.logger.error(
            """
            In order to use Crash Reporting, RUM or Logging feature must be enabled.
            Make sure `.enableRUM(true)` or `.enableLogging(true)` are configured
            when initializing Datadog SDK.
            """
        )
    }
}
