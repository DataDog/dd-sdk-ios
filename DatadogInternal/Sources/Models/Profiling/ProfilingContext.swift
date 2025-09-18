/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Profiling context information that can be attached to Datadog core context.
///
/// This context provides visibility into the current state of profiling operations,
/// particularly for constructor-based application launch profiling. It allows
/// other components and telemetry systems to understand whether profiling is
/// active and its current status.
///
/// ## Usage
///
/// The context is typically set automatically by profiling components:
///
/// ```swift
/// // Automatically set when profiler starts
/// core.set(context: ProfilingContext(status: .running))
///
/// // Updated when profiler stops
/// core.set(context: ProfilingContext(status: .stopped))
/// ```
///
/// ## Integration with Other Features
///
/// This context can be queried by other Datadog features to understand
/// profiling state and adjust their behavior accordingly. For example,
/// RUM might include profiling status in error reports or performance metrics.
public struct ProfilingContext: AdditionalContext {
    /// The context key used to identify profiling context in the core context.
    public static let key = "profiling"

    /// Represents the current status of profiling operations.
    ///
    /// This enum maps directly to the underlying C profiler status codes
    /// from the constructor profiler implementation.
    public enum Status {
        /// Profiling has not been started or initialized.
        case notStarted

        /// Profiling is currently active and collecting samples.
        case running

        /// Profiling was manually stopped via API call.
        case stopped

        /// Profiling was automatically stopped due to timeout.
        case timedOut

        /// Profiling encountered an error during operation.
        case error

        /// Profiling was not started due to app prewarming detection.
        case prewarmed

        /// Profiling was not started due to probabilistic sampling decision.
        case sampledOut
    }

    /// The current profiling status.
    public let status: Status

    /// Creates a new profiling context with the specified status.
    ///
    /// - Parameter status: The current profiling status to be included in the context.
    public init(status: Status) {
        self.status = status
    }
}
