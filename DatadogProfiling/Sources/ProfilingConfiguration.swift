/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

#if !os(watchOS)

extension Profiling {
    /// Configuration options for the profiling feature.
    public struct Configuration {
        /// Overrides the custom server endpoint where Profiles are sent.
        /// If `nil`, the default Datadog endpoint will be used.
        public var customEndpoint: URL?

        /// The sampling rate for App Launch Profiling.
        ///
        /// It must be a number between 0.0 and 100.0, where 0 means no profiles will be collected.
        ///
        /// Default: `5.0`.
        public var applicationLaunchSampleRate: SampleRate

        // MARK: - Internal

        internal var debugSDK: Bool = ProcessInfo.processInfo.arguments.contains(LaunchArguments.Debug)

        /// Creates the Profiling configuration.
        /// - Parameters:
        ///   - customEndpoint: Optional custom server endpoint for profile uploads.
        ///   - sampleRate: The sampling rate for Profiling.
        public init(
            customEndpoint: URL? = nil,
            applicationLaunchSampleRate: SampleRate = 5
        ) {
            self.customEndpoint = customEndpoint
            self.applicationLaunchSampleRate = applicationLaunchSampleRate
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

            // `continuousSampleRate` has no in-code equivalent in `Profiling.Configuration` yet, so the
            // remote value is intentionally not consumed. Wire it once continuous profiling becomes
            // configurable in-code.
        }
    }
}

#endif
