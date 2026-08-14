/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// A value identifying the thread for `BacktraceReport` generation.
public typealias ThreadID = thread_t

public extension Thread {
    /// Obtains the `ThreadID` of the caller thread.
    ///
    /// Should be used in conjunction with `BacktraceReporting.generateBacktrace(threadID:)` to generate backtrace of particular thread.
    static var currentThreadID: ThreadID { pthread_mach_thread_np(pthread_self()) }
}

/// A protocol for types capable of generating backtrace reports.
public protocol BacktraceReporting: Sendable {
    /// Generates a backtrace report for given thread ID.
    ///
    /// The thread given by `threadID` will be promoted in the main stack of returned `BacktraceReport` (`report.stack`).
    ///
    /// - Parameter threadID: An ID of the thread that backtrace generation should start on.
    /// - Returns: A `BacktraceReport` starting on the given thread and containing information about all other threads
    ///            running in the process. Returns `nil` if the backtrace report cannot be generated.
    func generateBacktrace(threadID: ThreadID) throws -> BacktraceReport?

    /// Returns binary images loaded in the current process.
    ///
    /// Returns `nil` if binary images cannot be obtained.
    func binaryImages() throws -> [BinaryImage]?
}

public extension BacktraceReporting {
    /// Generates a backtrace report for current thread.
    ///
    /// The caller thread will be promoted in the main stack of returned `BacktraceReport` (`report.stack`).
    ///
    /// - Returns: A `BacktraceReport` starting on the current thread and containing information about all other threads
    ///            running in the process. Returns `nil` if the backtrace report cannot be generated.
    func generateBacktrace() throws -> BacktraceReport? {
        let callerThreadID = Thread.currentThreadID
        return try generateBacktrace(threadID: callerThreadID)
    }

    func binaryImages() throws -> [BinaryImage]? { try generateBacktrace()?.binaryImages }
}

internal struct CoreBacktraceReporter: BacktraceReporting, @unchecked Sendable {
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

    func generateBacktrace(threadID: ThreadID) throws -> BacktraceReport? {
        guard let core = core else {
            return nil
        }

        guard let reporter = core.get(feature: BacktraceReportingFeature.self)?.reporter else {
            DD.logger.warn(
                """
                Backtrace will not be generated as this capability is not available.
                Enable `DatadogCrashReporting` to leverage backtrace generation.
                """
            )
            return nil
        }
        return try reporter.generateBacktrace(threadID: threadID)
    }

    func binaryImages() throws -> [BinaryImage]? {
        try core?.get(feature: BacktraceReportingFeature.self)?.reporter?.binaryImages()
    }
}

/// Adds capability of reporting backtraces.
extension DatadogCoreProtocol {
    /// Registers backtrace reporter in Core.
    /// - Parameters:
    ///   - backtraceReporter: the implementation of backtrace reporter.
    ///   - appHangBacktraceEnabled: whether backtraces may be generated for App Hangs detected by RUM. Default: `true`.
    public func register(backtraceReporter: BacktraceReporting, appHangBacktraceEnabled: Bool = true) throws {
        guard get(feature: BacktraceReportingFeature.self) == nil else {
            DD.logger.debug("Backtrace reporter is already registered to this core. Skipping registration of next one.")
            return
        }

        let feature = BacktraceReportingFeature(reporter: backtraceReporter, appHangBacktraceEnabled: appHangBacktraceEnabled)
        try register(feature: feature)
    }

    /// Registers the App Hang backtrace policy in Core when no backtrace reporter is available.
    ///
    /// Use it when Crash Reporting is enabled with a custom plugin that provides no backtrace reporter: backtraces
    /// cannot be generated at all in that case, but recording the policy keeps "generation was turned off" reportable
    /// as such instead of being mistaken for "Crash Reporting was never enabled".
    ///
    /// - Parameter appHangBacktraceEnabled: whether backtraces may be generated for App Hangs detected by RUM.
    public func register(appHangBacktraceEnabled: Bool) throws {
        guard get(feature: BacktraceReportingFeature.self) == nil else {
            DD.logger.debug("Backtrace reporter is already registered to this core. Skipping registration of next one.")
            return
        }

        let feature = BacktraceReportingFeature(reporter: nil, appHangBacktraceEnabled: appHangBacktraceEnabled)
        try register(feature: feature)
    }

    /// Backtrace reporter. Use it to snapshot all running threads in the current process.
    ///
    /// It requires `BacktraceReportingFeature` registered to Datadog core. Otherwise reported backtraces will be `nil`.
    public var backtraceReporter: BacktraceReporting { CoreBacktraceReporter(core: self) }

    /// Whether backtraces may be generated for App Hangs detected by RUM.
    ///
    /// It is `false` only when a backtrace reporter was registered with App Hang backtraces turned off. Before any
    /// reporter is registered it is `true`: in that state backtrace generation is *unavailable* rather than
    /// *disabled*, and callers must keep distinguishing the two. Read it at the moment a backtrace is needed, as
    /// the reporter may be registered after the reading Feature was enabled.
    public var isAppHangBacktraceEnabled: Bool {
        // `self.` is required: a bare `get(...)` here parses as a `get` accessor.
        self.get(feature: BacktraceReportingFeature.self)?.appHangBacktraceEnabled ?? true
    }
}
