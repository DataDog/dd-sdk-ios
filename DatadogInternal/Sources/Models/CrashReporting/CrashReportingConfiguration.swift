/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// The Crash Reporting shared configuration.
///
/// The Feature object named `crash-reporter` will be registered to the core
/// when enabling Crash Reporting. If available, the configuration can be retrieved
/// with:
///
///     let crashReporting = core.feature(
///         named: Feature.crashReporting,
///         type: CrashReportingConfiguration.self
///     )
///
/// A `nil` result means Crash Reporting was never enabled, which is distinct from it being enabled with a
/// capability turned off. Read it at the moment the capability is needed, as Crash Reporting may be enabled
/// after the Feature doing the reading.
public protocol CrashReportingConfiguration {
    /// Determines whether backtraces may be generated for App Hangs detected by RUM.
    ///
    /// It only gates the App Hangs consumer. Crash reports, binary images attached to logs and RUM view events,
    /// and the public `backtraceReporter` API are unaffected by this value.
    ///
    /// When this configuration is absent, read it as `true`: backtrace generation is then *unavailable* (Crash
    /// Reporting was never enabled) rather than *disabled*, and consumers report the two differently.
    ///
    /// It is read from arbitrary threads - the App Hangs watchdog reads it while the main thread is blocked - so
    /// conforming types must make it safe to read concurrently. Backing it with an immutable value is enough.
    var appHangBacktraceEnabled: Bool { get }
}

extension DatadogFeature where Self: CrashReportingConfiguration {
    public static var name: String { Feature.crashReporting }
}
