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
    public enum Status: Equatable {
        /// Reasons why profiling was stopped.
        public enum StopReason: String, Equatable {
            /// Profiling was manually stopped by explicit API call.
            case manual

            /// Profiling was never started in the first place.
            case notStarted

            /// Profiling stopped due to configured timeout being reached.
            case timeout

            /// Profiling stopped because app was pre-warmed (iOS 15+ app launch optimization).
            case prewarmed

            /// Profiling was not started due to sampling configuration (profiling was sampled out).
            case sampledOut
        }

        /// Errors that can occur during profiling operations.
        public enum ErrorReason: String, Equatable {
            /// Failed to allocate required memory for profiling operations.
            case memoryAllocationFailed

            /// Attempted to start profiling when it was already running.
            case alreadyStarted
        }

        /// Profiling is currently active and collecting samples.
        case running

        /// Profiling was manually stopped via API call.
        case stopped(reason: StopReason)

        /// Profiling encountered an error during operation.
        case error(reason: ErrorReason)

        /// Profiling status is unknown or could not be determined.
        case unknown
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
