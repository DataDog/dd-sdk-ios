/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

extension Profiling {
    /// Configuration options for the profiling feature.
    public struct Configuration {
        /// Overrides the custom server endpoint where Profiles are sent.
        /// If `nil`, the default Datadog endpoint will be used.
        public var customEndpoint: URL?

        /// Application launch profiling option.
        ///
        /// Default: Option enabled with `5.0%` sample rate.
        public var applicationLaunch: ProfilingOption
        /// Continuous profiling option.
        ///
        /// Default: Option disabled.
        public var continuous: ProfilingOption

        // MARK: - Internal

        internal var debugSDK: Bool = ProcessInfo.processInfo.arguments.contains(LaunchArguments.Debug)

        /// Creates the Profiling configuration.
        /// - Parameters:
        ///   - customEndpoint: Optional custom server endpoint for profile uploads.
        ///   - sampleRate: The sampling rate for Profiling.
        public init(
            customEndpoint: URL? = nil,
            applicationLaunch: ProfilingOption = .enabled(sampleRate: 5.0),
            continuous: ProfilingOption = .disabled
        ) {
            self.customEndpoint = customEndpoint
            self.applicationLaunch = applicationLaunch
            self.continuous = continuous
        }
    }
}
