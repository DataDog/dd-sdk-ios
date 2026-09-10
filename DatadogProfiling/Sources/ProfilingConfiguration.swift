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

        /// Feature flags to preview features in Profiling.
        public var featureFlags: FeatureFlags

        // MARK: - Internal

        internal var debugSDK: Bool = ProcessInfo.processInfo.arguments.contains(LaunchArguments.Debug)
        internal var minProfileDuration: TimeInterval = DatadogProfiler.Constants.minProfileDuration

        /// Creates the Profiling configuration.
        /// - Parameters:
        ///   - customEndpoint: Optional custom server endpoint for profile uploads.
        ///   - applicationLaunchSampleRate: The sampling rate for the application launch profiling.
        public init(
            customEndpoint: URL? = nil,
            applicationLaunchSampleRate: SampleRate = 5,
            continuousSampleRate: SampleRate = 5,
            featureFlags: FeatureFlags = .defaults
        ) {
            self.customEndpoint = customEndpoint
            self.applicationLaunchSampleRate = applicationLaunchSampleRate
            self.continuousSampleRate = continuousSampleRate
            self.featureFlags = featureFlags
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

extension Profiling.Configuration {
    public typealias FeatureFlags = [FeatureFlag: Bool]

    /// Feature flags available in Profiling.
    public enum FeatureFlag: String, Sendable {
        /// Adds CPU-time sample values alongside wall-time sample values.
        case cpuTimeSamples
    }
}

extension Profiling.Configuration.FeatureFlags {
    /// The default feature flags applied to Profiling configuration.
    public static var defaults: Self {
        [
            .cpuTimeSamples: false,
        ]
    }

    /// Accesses a feature flag value.
    ///
    /// Returns false by default.
    public subscript(flag: Key) -> Bool {
        self[flag, default: false]
    }
}

#endif
