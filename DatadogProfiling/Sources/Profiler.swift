/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Represents a captured profiling session with timing information and pprof data.
internal struct Profile {
    /// The start time of the profiling session.
    let start: Date
    /// The end time of the profiling session.
    let end: Date
    /// The profiling data in pprof format.
    let pprof: Data
}

/// Protocol defining the interface for profilers that can capture performance data.
internal protocol Profiler {
    /// Starts the profiling session.
    func start(currentThreadOnly: Bool)
    /// Stops the profiling session and returns the captured profile data.
    /// - Returns: A `Profile` containing the session data, or `nil` if no data was captured.
    /// - Throws: An error if the profiling session could not be stopped properly.
    func stop() throws -> Profile?
}
