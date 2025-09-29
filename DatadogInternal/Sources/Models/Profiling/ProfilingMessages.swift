/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Message payload used to signal the end of profiling operations.
///
/// This message is sent to trigger the collection and submission of profiling
/// data captured during various profiling sessions. Profiling may be active
/// for different use cases (such as application startup) and continues until
/// this stop message is received.
///
/// ## Usage
///
/// Send this message through the core messaging system when profiling
/// should be stopped and data collected:
///
/// ```swift
/// let context = ["session.id": "abc123", "view.id": "home_screen"]
/// let stopMessage = ProfilerStop(context: context)
/// core.send(message: .payload(stopMessage))
/// ```
///
/// ## Integration
///
/// This message is handled by profiling components which will:
/// 1. Stop the active profiler
/// 2. Extract the collected profile data
/// 3. Serialize it to pprof format
/// 4. Submit it through the profiling pipeline with the provided context
///
/// ## Context Data
///
/// The context dictionary contains correlation IDs and identifiers that allow
/// linking the profile data with other telemetry data (RUM, logs, traces).
///
/// This context is included as additional attributes in the final profile event.
public struct ProfilerStop {
    /// Correlation context to include with the profile submission.
    ///
    /// This context contains identifiers and correlation IDs that are merged
    /// into the profile event as additional attributes, enabling data correlation
    /// across different telemetry streams.
    public let context: [String: Encodable]

    /// Creates a new profiler stop message.
    ///
    /// - Parameter context: Correlation context containing IDs for data correlation.
    ///                      Such as session IDs, view IDs, or other telemetry identifiers.
    public init(context: [String: Encodable]) {
        self.context = context
    }
}
