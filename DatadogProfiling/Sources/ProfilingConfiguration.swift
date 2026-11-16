/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

#if !os(watchOS) && !os(macOS)

extension Profiling {
    /// Configuration options for the profiling feature.
    public struct Configuration: Sendable {
        /// Overrides the custom server endpoint where Profiles are sent.
        /// If `nil`, the default Datadog endpoint will be used.
        public var customEndpoint: URL?

        /// The sampling rate for App Launch Profiling.
        ///
        /// It must be a number between 0.0 and 100.0, where 0 means no profiles will be collected.
        ///
        /// Default: `5.0`.
        public var applicationLaunchSampleRate: SampleRate

        /// The sampling rate for continuous Profiling.
        ///
        /// It must be a number between 0.0 and 100.0, where 0 means no profiles will be collected.
        ///
        /// Default: `5.0`.
        public var continuousSampleRate: SampleRate

        /// The per-session sampling rate for continuous memory (heap) profiling.
        ///
        /// It must be a number between 0.0 and 100.0, where 0 disables memory profiling.
        /// The rate is composed with the RUM session sampler, separately from `continuousSampleRate`.
        /// A session can collect memory profiles even when continuous CPU profiling is sampled out.
        ///
        /// Opting in installs Objective-C allocation/deallocation swizzles and Swift runtime symbol
        /// rebinding together. Installation or runtime failures disable memory profiling without stopping
        /// CPU profiling or RUM. The rate also controls early memory profiling on the next process launch.
        ///
        /// Default: `0.0` (disabled).
        public var memorySampleRate: SampleRate

        // MARK: - Internal

        internal var debugSDK: Bool = ProcessInfo.processInfo.arguments.contains(LaunchArguments.Debug)
        internal var minProfileDuration: TimeInterval = DatadogProfiler.Constants.minProfileDuration

        /// Creates the Profiling configuration.
        /// - Parameters:
        ///   - customEndpoint: Optional custom server endpoint for profile uploads.
        ///   - applicationLaunchSampleRate: The sampling rate for the application launch profiling.
        ///   - continuousSampleRate: The per-session sampling rate for continuous CPU profiling.
        ///   - memorySampleRate: The per-session sampling rate for continuous memory profiling. Defaults to disabled.
        public init(
            customEndpoint: URL? = nil,
            applicationLaunchSampleRate: SampleRate = 5,
            continuousSampleRate: SampleRate = 5,
            memorySampleRate: SampleRate = 0
        ) {
            self.customEndpoint = customEndpoint
            self.applicationLaunchSampleRate = applicationLaunchSampleRate
            self.continuousSampleRate = continuousSampleRate
            self.memorySampleRate = memorySampleRate
        }

        /// Merges the remote configuration on top of this in-code configuration.
        ///
        /// Remote values take precedence for the supported behavioral parameters; any parameter the
        /// remote configuration omits keeps its in-code value. Passing `nil` (no remote configuration was
        /// fetched) therefore leaves the configuration entirely unchanged.
        ///
        /// The merge happens once, at `Profiling.enable(with:)` time; live updates after initialization
        /// are out of scope.
        ///
        /// - Parameter remoteConfiguration: The remote configuration to merge, or `nil` when none is
        ///   available (leaving this configuration unchanged).
        mutating func apply(remoteConfiguration: RemoteConfiguration?) {
            if let applicationLaunchSampleRate = remoteConfiguration?.profiling?.applicationLaunchSampleRate {
                self.applicationLaunchSampleRate = SampleRate(applicationLaunchSampleRate)
            }

            if let continuousSampleRate = remoteConfiguration?.profiling?.continuousSampleRate {
                self.continuousSampleRate = SampleRate(continuousSampleRate)
            }
        }
    }
}

#endif
