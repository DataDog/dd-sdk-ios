/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
import DatadogInternal

// swiftlint:disable duplicate_imports
@_exported import enum DatadogInternal.SessionReplayPrivacyLevel
@_exported import enum DatadogInternal.TextAndInputPrivacyLevel
@_exported import enum DatadogInternal.ImagePrivacyLevel
@_exported import enum DatadogInternal.TouchPrivacyLevel
// swiftlint:enable duplicate_imports

extension SessionReplay {
    /// Session Replay feature configuration.
    public struct Configuration {
        /// The sampling rate for Session Replay. It is applied in addition to the RUM session sample rate.
        ///
        /// It must be a number between 0.0 and 100.0, where 0 means no replays will be recorded
        /// and 100 means all RUM sessions will contain replay.
        ///
        /// Note: This sample rate is applied in addition to the RUM sample rate. For example, if RUM uses a sample rate of 80%
        /// and Session Replay uses a sample rate of 20%, it means that out of all user sessions, 80% will be included in RUM,
        /// and within those sessions, only 20% will have replays.
        public var replaySampleRate: Float

        /// Defines the way text and input (e.g. textfields, checkboxes) should be masked.
        ///
        /// Default: `.maskAll`.
        public var textAndInputPrivacyLevel: TextAndInputPrivacyLevel

        /// Defines image privacy level.
        ///
        /// Default: `.maskAll`.
        public var imagePrivacyLevel: ImagePrivacyLevel

        /// Defines the way user touches (e.g. tap) should be masked.
        ///
        /// Default: `.hide`.
        public var touchPrivacyLevel: TouchPrivacyLevel

        /// Defines it the recording should start automatically. When `true`, the recording starts automatically; when `false` it doesn't, and the recording will need to be started manually.
        ///
        /// Default: `true`.
        public var startRecordingImmediately: Bool

        /// Custom server url for sending replay data.
        ///
        /// Default: `nil`.
        public var customEndpoint: URL?

        /// Feature flags to preview features in Session Replay.
        public var featureFlags: FeatureFlags

        // MARK: - Internal

        internal var debugSDK: Bool = ProcessInfo.processInfo.arguments.contains(LaunchArguments.Debug)

        internal var _additionalNodeRecorders: [NodeRecorder] = []

        // swiftlint:disable function_default_parameter_at_end

        /// Creates Session Replay configuration
        /// - Parameters:
        ///   - replaySampleRate: The sampling rate for Session Replay. It is applied in addition to the RUM session sample rate.
        ///   - textAndInputPrivacyLevel: The way texts and inputs (e.g. label, textfield, checkbox) should be masked. Default: `.maskAll`.
        ///   - imagePrivacyLevel: The way images should be masked. Default: `.maskAll`.
        ///   - touchPrivacyLevel: The way user touches (e.g. tap) should be masked. Default: `.hide`.
        ///   - startRecordingImmediately: If the recording should start automatically. When `true`, the recording starts automatically; when `false` it doesn't, and the recording will need to be started manually. Default: `true`.
        ///   - customEndpoint: Custom server url for sending replay data. Default: `nil`.
        ///   - featureFlags: Experimental feature flags.
        public init(
            replaySampleRate: SampleRate = .maxSampleRate,
            textAndInputPrivacyLevel: TextAndInputPrivacyLevel = .maskAll,
            imagePrivacyLevel: ImagePrivacyLevel = .maskAll,
            touchPrivacyLevel: TouchPrivacyLevel = .hide,
            startRecordingImmediately: Bool = true,
            customEndpoint: URL? = nil,
            featureFlags: FeatureFlags = .defaults
        ) {
            self.replaySampleRate = replaySampleRate
            self.textAndInputPrivacyLevel = textAndInputPrivacyLevel
            self.imagePrivacyLevel = imagePrivacyLevel
            self.touchPrivacyLevel = touchPrivacyLevel
            self.startRecordingImmediately = startRecordingImmediately
            self.customEndpoint = customEndpoint
            self.featureFlags = featureFlags
        }

        // swiftlint:enable function_default_parameter_at_end

        @_spi(Internal)
        public mutating func setAdditionalNodeRecorders(_ additionalNodeRecorders: [SessionReplayNodeRecorder]) {
            self._additionalNodeRecorders = additionalNodeRecorders
        }
    }
}

extension SessionReplay.Configuration {
    public typealias FeatureFlags = [FeatureFlag: Bool]

    /// Feature Flag available in Session Replay
    public enum FeatureFlag: String {
        /// SwiftUI Recording
        case swiftui
    }
}

extension SessionReplay.Configuration.FeatureFlags {
    /// The defaults Feature Flags applied to Session Replay Configuration
    public static var defaults: Self {
        [
            .swiftui: false
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
