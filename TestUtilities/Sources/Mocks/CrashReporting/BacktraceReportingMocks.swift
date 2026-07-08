/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

public struct BacktraceReporterMock: BacktraceReporting, @unchecked Sendable {
    /// The backtrace that will be returned by this mock.
    @ReadWriteLock
    public var backtrace: BacktraceReport?
    /// The error thrown that will be thrown by this mock during backtrace generation. It takes priority over returning the `backtrace` value.
    @ReadWriteLock
    public var backtraceGenerationError: Error?
    /// The binary images returned by this mock. If not set, binary images are derived from `backtrace`.
    @ReadWriteLock
    public var binaryImagesList: [BinaryImage]?

    /// Creates backtrace reporter mock.
    /// - Parameters:
    ///   - backtrace: The backtrace that will be returned.
    ///   - backtraceGenerationError: The error thrown during backtrace generation. It takes priority over returning the `backtrace`.
    ///   - binaryImages: The binary images that will be returned. If `nil`, binary images are derived from `backtrace?.binaryImages`. Pass `[]` to simulate "no binary images" independently of `backtrace`.
    public init(
        backtrace: BacktraceReport? = .mockAny(),
        backtraceGenerationError: Error? = nil,
        binaryImages: [BinaryImage]? = nil
    ) {
        self.backtrace = backtrace
        self.backtraceGenerationError = backtraceGenerationError
        self.binaryImagesList = binaryImages
    }

    public func generateBacktrace(threadID: ThreadID) throws -> BacktraceReport? {
        try throwIfNeeded()
        return backtrace
    }

    public func binaryImages() throws -> [BinaryImage]? {
        try throwIfNeeded()
        return binaryImagesList ?? backtrace?.binaryImages
    }

    private func throwIfNeeded() throws {
        if let error = backtraceGenerationError {
            throw error
        }
    }
}
