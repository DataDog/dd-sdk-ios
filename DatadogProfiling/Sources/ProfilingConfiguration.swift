/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

@_exported import enum DatadogInternal.SamplingOption

#if !os(watchOS)

extension Profiling {
    /// Configuration options for the profiling feature.
    public struct Configuration {
        /// Overrides the custom server endpoint where Profiles are sent.
        /// If `nil`, the default Datadog endpoint will be used.
        public var customEndpoint: URL?

        /// Sampling option for the application launch profiling.
        ///
        /// Default: Feature enabled with `5.0%` sample rate.
        public var applicationLaunch: SamplingOption

        /// Sampling option for the continuous profiling.
        ///
        /// Default: Feature enabled with `5.0%` sample rate.
        public var continuous: SamplingOption

        // MARK: - Internal

        internal var debugSDK: Bool = ProcessInfo.processInfo.arguments.contains(LaunchArguments.Debug)

        /// Creates the Profiling configuration.
        /// - Parameters:
        ///   - customEndpoint: Optional custom server endpoint for profile uploads.
        ///   - applicationLaunch: Sampling option for the application launch profiling.
        ///   - continuous: Sampling option for the continuous profiling.
        public init(
            customEndpoint: URL? = nil,
            applicationLaunch: SamplingOption = .enabled(sampleRate: 5.0),
            continuous: SamplingOption = .enabled(sampleRate: 5.0)
        ) {
            self.customEndpoint = customEndpoint
            self.applicationLaunch = applicationLaunch
            self.continuous = continuous
        }
    }
}

#endif
