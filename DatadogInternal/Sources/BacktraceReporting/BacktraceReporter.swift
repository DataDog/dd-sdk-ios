/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// A protocol for types capable of generating backtrace reports.
public protocol BacktraceReporting {
    /// Generates a backtrace report.
    /// - Returns: A `BacktraceReport` containing information about the current state of all running threads in the process,
    ///            focusing on tracing back from the error point to the root cause or the origin of the problem. Returns `nil` if
    ///            the backtrace report cannot be generated.
    func generateBacktrace() -> BacktraceReport?
}

internal struct CoreBacktraceReporter: BacktraceReporting {
    /// A weak core reference.
    private weak var core: DatadogCoreProtocol?

    /// Creates backtrace reporter associated with a core instance.
    ///
    /// The `CoreBacktraceReporter` keeps a weak reference to the provided core.
    ///
    /// - Parameter core: The core instance.
    init(core: DatadogCoreProtocol) {
        self.core = core
    }

    func generateBacktrace() -> BacktraceReport? {
        guard let core = core else {
            return nil
        }
        guard let backtraceFeature = core.get(feature: BacktraceReportingFeature.self) else {
            DD.logger.warn(
                """
                Backtrace will not be generated as this capability is not available.
                Enable `DatadogCrashReporting` to leverage backtrace generation.
                """
            )
            return nil
        }
        return backtraceFeature.generateBacktrace()
    }
}

/// Adds capability of reporting backtraces.
extension DatadogCoreProtocol {
    /// Registers backtrace reporter in Core.
    /// - Parameter backtraceReporter: the implementation of backtrace reporter.
    public func register(backtraceReporter: BacktraceReporting) throws {
        guard get(feature: BacktraceReportingFeature.self) == nil else {
            DD.logger.debug("Backtrace reporter is already registered to this core. Skipping registration of next one.")
            return
        }

        let feature = BacktraceReportingFeature(reporter: backtraceReporter)
        try register(feature: feature)
    }

    /// Backtrace reporter. Use it to snapshot all running threads in the current process.
    ///
    /// It requires `BacktraceReportingFeature` registered to Datadog core. Otherwise reported backtraces will be `nil`.
    public var backtraceReporter: BacktraceReporting { CoreBacktraceReporter(core: self) }
}
