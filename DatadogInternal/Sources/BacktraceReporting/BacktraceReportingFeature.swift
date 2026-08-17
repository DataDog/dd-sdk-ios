/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

internal final class BacktraceReportingFeature: DatadogFeature {
    static var name: String = "backtrace-reporting"

    let messageReceiver: FeatureMessageReceiver = NOPFeatureMessageReceiver()

    /// A type capable of generating backtrace reports.
    ///
    /// It is `nil` when Crash Reporting was enabled with a custom plugin that provides no backtrace reporter. The
    /// Feature is still registered in that case, so that `appHangBacktraceEnabled` is recorded and backtrace
    /// generation stays distinguishable from Crash Reporting never having been enabled.
    let reporter: BacktraceReporting?

    /// Determines whether backtraces may be generated for App Hangs detected by RUM.
    ///
    /// It only gates the App Hangs consumer. All other consumers of `reporter` (crash reports, binary images
    /// attached to logs and RUM view events, the public `backtraceReporter` API) are unaffected by this value.
    ///
    /// Only `disableAppHangBacktrace()` can change it after initialization. It is read from the App Hangs watchdog
    /// thread, hence the lock.
    @ReadWriteLock
    private(set) var appHangBacktraceEnabled: Bool

    /// Creates `BacktraceReportingFeature`.
    /// - Parameters:
    ///   - reporter: An external implementation of a type capable of generating backtrace reports, if any.
    ///   - appHangBacktraceEnabled: Whether backtraces may be generated for App Hangs. Default: `true`.
    init(reporter: BacktraceReporting?, appHangBacktraceEnabled: Bool = true) {
        self.reporter = reporter
        self.appHangBacktraceEnabled = appHangBacktraceEnabled
    }

    /// Turns off backtrace generation for App Hangs.
    ///
    /// Needed because only the first registration installs its `reporter`, while an opt-out arriving with a later one
    /// must still take effect — otherwise an app that registered a backtrace reporter before enabling Crash Reporting
    /// would keep snapshotting all threads after explicitly asking it not to.
    ///
    /// Turning it back on is deliberately not offered: `register(backtraceReporter:)` passes `true` as a compatibility
    /// default rather than as an explicit request, so honouring it would silently revert an opt-out. Opting out is
    /// therefore one-way, which also makes the outcome independent of registration order.
    func disableAppHangBacktrace() {
        _appHangBacktraceEnabled.mutate { $0 = false }
    }
}
