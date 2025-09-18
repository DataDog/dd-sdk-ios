/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Message payload used to signal the end of application launch profiling.
///
/// This message is sent to trigger the collection and submission of profiling
/// data captured during application startup. The constructor profiler automatically
/// starts during early app launch and continues until this stop message is received.
///
/// ## Usage
///
/// Send this message through the core messaging system when the application
/// has completed its launch phase:
///
/// ```swift
/// let context = ["launch_duration": 1.5, "view_controller": "MainViewController"]
/// let stopMessage = AppLaunchProfileStop(context: context)
/// core.send(message: .payload(stopMessage))
/// ```
///
/// ## Integration
///
/// This message is handled by `AppLaunchProfiler` which will:
/// 1. Stop the constructor-based profiler
/// 2. Extract the collected profile data
/// 3. Serialize it to pprof format
/// 4. Submit it through the profiling pipeline with the provided context
///
/// ## Context Data
///
/// The context dictionary can contain any additional metadata about the launch.
/// The context will be injected into the profile data for query.
///
/// This context is included as additional attributes in the final profile event.
public struct AppLaunchProfileStop {
    /// Additional context metadata to include with the profile submission.
    ///
    /// This context is merged into the profile event as additional attributes,
    /// allowing custom launch-specific data to be associated with the profile.
    public let context: [String: Encodable]

    /// Creates a new app launch profile stop message.
    ///
    /// - Parameter context: Additional context metadata to include with the profile.
    ///                      Such as RUM context.
    public init(context: [String: Encodable]) {
        self.context = context
    }
}
