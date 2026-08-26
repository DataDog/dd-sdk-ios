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
    /// The Crash Reporting configuration.
    public struct Configuration {
        /// Determines whether backtraces are generated for App Hangs detected by RUM.
        ///
        /// Set this to `false` to keep receiving App Hang errors without a stack trace. Crash reports and every other
        /// stack trace collected by the SDK are unaffected.
        ///
        /// The backtrace is generated while the main thread is still blocked, so the cost of walking and symbolicating
        /// its stack adds to the duration of the hang being measured. Turning it off trades stack traces in App Hang
        /// errors for a smaller footprint, which matters most for apps setting a small
        /// `RUM.Configuration.appHangThreshold`.
        ///
        /// Default: `true`.
        public var appHangBacktraceEnabled: Bool

        /// Creates a Crash Reporting configuration object.
        ///
        /// - Parameter appHangBacktraceEnabled: Whether backtraces are generated for App Hangs detected by RUM.
        public init(appHangBacktraceEnabled: Bool = true) {
            self.appHangBacktraceEnabled = appHangBacktraceEnabled
        }
    }

    /// Initializes the Datadog Crash Reporter using the default
    /// `KSCrash` plugin.
    public static func enable(in core: DatadogCoreProtocol = CoreRegistry.default) {
        enable(with: Configuration(), in: core)
    }

    /// Initializes the Datadog Crash Reporter using the default
    /// `KSCrash` plugin.
    ///
    /// - Parameters:
    ///   - configuration: The Crash Reporting configuration.
    ///   - core: The instance of Datadog SDK to enable Crash Reporting in (global instance by default).
    public static func enable(with configuration: Configuration, in core: DatadogCoreProtocol = CoreRegistry.default) {
        enable(with: try KSCrashPlugin(telemetry: core.telemetry), configuration: configuration, in: core)
    }

    /// Initializes the Datadog Crash Reporter with a custom Crash Reporting Plugin.
    ///
    /// The custom plugin will be responsible for:
    /// - Provide crash report
    /// - Store context data associated with crashes
    /// - Provide backtraces
    public static func enable(with plugin: @autoclosure () throws -> CrashReportingPlugin, in core: DatadogCoreProtocol = CoreRegistry.default) {
        enable(with: try plugin(), configuration: Configuration(), in: core)
    }

    /// Initializes the Datadog Crash Reporter with a custom Crash Reporting Plugin.
    ///
    /// The custom plugin will be responsible for:
    /// - Provide crash report
    /// - Store context data associated with crashes
    /// - Provide backtraces
    ///
    /// - Parameters:
    ///   - plugin: The custom Crash Reporting Plugin.
    ///   - configuration: The Crash Reporting configuration.
    ///   - core: The instance of Datadog SDK to enable Crash Reporting in (global instance by default).
    public static func enable(
        with plugin: @autoclosure () throws -> CrashReportingPlugin,
        configuration: Configuration,
        in core: DatadogCoreProtocol = CoreRegistry.default
    ) {
        do {
            // To ensure the correct registration order between Core and Features,
            // the entire initialization flow is synchronized on the main thread.
            try runOnMainThreadSync {
                try enableOrThrow(with: plugin(), in: core, configuration: configuration)
            }
        } catch let error {
            consolePrint("\(error)", .error)
        }
    }

    internal static func enableOrThrow(
        with plugin: CrashReportingPlugin,
        in core: DatadogCoreProtocol,
        configuration: Configuration = .init()
    ) throws {
        guard !(core is NOPDatadogCore) else {
            throw ProgrammerError(
                description: "Datadog SDK must be initialized before calling `CrashReporting.enable()`."
            )
        }

        let contextProvider = CrashContextCoreProvider()

        let reporter = CrashReportingFeature(
            crashReportingPlugin: plugin,
            crashContextProvider: contextProvider,
            sender: MessageBusSender(core: core),
            messageReceiver: contextProvider,
            telemetry: core.telemetry,
            appHangBacktraceEnabled: configuration.appHangBacktraceEnabled
        )

        // `reporter` carries `appHangBacktraceEnabled` and is registered unconditionally, so the setting reaches RUM
        // through `CrashReportingConfiguration` whether or not the plugin provides a backtrace reporter, and
        // regardless of the order the two Features are registered in.
        try core.register(feature: reporter)

        if let backtraceReporter = plugin.backtraceReporter {
            try core.register(backtraceReporter: backtraceReporter)
        }

        reporter.sendCrashReportIfFound()

        core.telemetry.configuration(trackErrors: true)
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

    /// Initializes the Datadog Crash Reporter with the given configuration.
    /// - Parameter configuration: The Crash Reporting configuration.
    @objc
    public static func enable(with configuration: objc_CrashReportingConfiguration) {
        CrashReporting.enable(with: configuration.configuration)
    }
}

/// The Crash Reporting configuration.
@available(swift, obsoleted: 1)
@objc(DDCrashReporterConfiguration)
@objcMembers
public final class objc_CrashReportingConfiguration: NSObject {
    internal var configuration: CrashReporting.Configuration

    /// Determines whether backtraces are generated for App Hangs detected by RUM.
    ///
    /// Set this to `NO` to keep receiving App Hang errors without a stack trace. Crash reports and every other
    /// stack trace collected by the SDK are unaffected.
    ///
    /// Default: `YES`.
    public var appHangBacktraceEnabled: Bool {
        get { configuration.appHangBacktraceEnabled }
        set { configuration.appHangBacktraceEnabled = newValue }
    }

    /// Creates a Crash Reporting configuration object.
    override public init() {
        configuration = .init()
    }
}
