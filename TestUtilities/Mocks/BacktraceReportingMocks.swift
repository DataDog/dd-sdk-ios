/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

public struct BacktraceReporterMock: BacktraceReporting {
    /// The backtrace that will be returned by this mock.
    public var backtrace: BacktraceReport?
    /// The error thrown that will be thrown by this mock during backtrace generation. It takes priority over returning the `backtrace` value.
    public var backtraceGenerationError: Error?
    
    /// Creates backtrace reporter mock.
    /// - Parameters:
    ///   - backtrace: The backtrace that will be returned.
    ///   - backtraceGenerationError: The error thrown during backtrace generation. It takes priority over returning the `backtrace`.
    public init(backtrace: BacktraceReport? = .mockAny(), backtraceGenerationError: Error? = nil) {
        self.backtrace = backtrace
        self.backtraceGenerationError = backtraceGenerationError
    }

    public func generateBacktrace(threadID: ThreadID) throws -> BacktraceReport? {
        if let error = backtraceGenerationError {
            throw error
        }
        return backtrace
    }
}
