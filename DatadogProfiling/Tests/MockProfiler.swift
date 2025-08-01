/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

@testable import DatadogProfiling

/// A mock implementation of the `Profiler` protocol for testing purposes.
///
/// This mock allows tests to simulate different profiler behaviors by controlling
/// the returned profile data and error conditions without performing actual profiling.
internal struct MockProfiler: Profiler {
    /// The profile data to return when `stop()` is called, or `nil` if no profile should be returned.
    let profile: Profile?
    /// The error to throw when `stop()` is called, or `nil` if no error should be thrown.
    let error: Error?

    /// Creates a new mock profiler with configurable behavior.
    /// - Parameters:
    ///   - profile: The profile data to return from `stop()`. Defaults to `nil`.
    ///   - error: The error to throw from `stop()`. Defaults to `nil`.
    init(
        profile: Profile? = nil,
        error: Error? = nil
    ) {
        self.profile = profile
        self.error = error
    }

    /// Starts the mock profiling session.
    /// This is a no-op implementation for testing purposes.
    func start() {
        // no-op
    }

    /// Stops the mock profiling session and returns the configured result.
    /// - Returns: The configured `profile` if no error is set, or `nil` if configured to return `nil`.
    /// - Throws: The configured `error` if one is set.
    func stop() throws -> Profile? {
        try error.map { throw $0 } ?? profile
    }
}
