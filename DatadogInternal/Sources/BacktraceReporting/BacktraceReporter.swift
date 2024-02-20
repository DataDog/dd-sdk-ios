/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// A type representing unique thread identifier for `BacktraceReport` generation.
public struct ThreadID {
    public let thread_t: thread_t
}

/// A protocol for types capable of generating backtrace reports.
public protocol BacktraceReporting {
    /// Generates a backtrace report for given thread ID.
    ///
    /// The thread given by `threadID` will be promoted in the main stack of returned `BacktraceReport` (`report.stack`).
    ///
    /// - Parameter threadID: An ID of the thread that backtrace generation should start on.
    /// - Returns: A `BacktraceReport` starting on the given thread and containing information about all other threads
    ///            running in the process. Returns `nil` if the backtrace report cannot be generated.
    func generateBacktrace(threadID: ThreadID) -> BacktraceReport?
}

public extension BacktraceReporting {
    /// Obtains the `ThreadID` of the caller thread. 
    /// 
    /// Should be used in conjunction with `generateBacktrace(threadID:)` to generate backtrace of particular thread.
    func currentThreadID() -> ThreadID {
        ThreadID(thread_t: pthread_mach_thread_np(pthread_self()))
    }

    /// Generates a backtrace report for current thread.
    ///
    /// The caller thread will be promoted in the main stack of returned `BacktraceReport` (`report.stack`).
    ///
    /// - Returns: A `BacktraceReport` starting on the current thread and containing information about all other threads
    ///            running in the process. Returns `nil` if the backtrace report cannot be generated.
    func generateBacktrace() -> BacktraceReport? {
        let callerThreadID = currentThreadID()
        return generateBacktrace(threadID: callerThreadID)
    }
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

    func generateBacktrace(threadID: ThreadID) -> BacktraceReport? {
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
        return backtraceFeature.reporter.generateBacktrace(threadID: threadID)
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
