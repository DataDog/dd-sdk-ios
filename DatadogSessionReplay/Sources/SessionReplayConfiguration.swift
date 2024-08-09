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

        /// Defines the way sensitive content (e.g. text) should be masked.
        ///
        /// Default: `.mask`.
        public var defaultPrivacyLevel: SessionReplayPrivacyLevel

        /// Defines it the recording should start automatically. When `true`, the recording starts automatically; when `false` it doesn't, and the recording will need to be started manually.
        ///
        /// Default: `true`.
        public var startRecordingImmediately: Bool

        /// Custom server url for sending replay data.
        ///
        /// Default: `nil`.
        public var customEndpoint: URL?

        // MARK: - Internal

        internal var debugSDK: Bool = ProcessInfo.processInfo.arguments.contains(LaunchArguments.Debug)

        internal var _additionalNodeRecorders: [NodeRecorder] = []

        /// Creates Session Replay configuration
        /// - Parameters:
        ///   - replaySampleRate: The sampling rate for Session Replay. It is applied in addition to the RUM session sample rate.
        ///   - defaultPrivacyLevel: The way sensitive content (e.g. text) should be masked. Default: `.mask`.
        ///   - startRecordingImmediately: If the recording should start automatically. When `true`, the recording starts automatically; when `false` it doesn't, and the recording will need to be started manually. Default: `true`.
        ///   - customEndpoint: Custom server url for sending replay data. Default: `nil`.
        public init(
            replaySampleRate: Float,
            defaultPrivacyLevel: SessionReplayPrivacyLevel = .mask,
            startRecordingImmediately: Bool = true,
            customEndpoint: URL? = nil
        ) {
            self.replaySampleRate = replaySampleRate
            self.defaultPrivacyLevel = defaultPrivacyLevel
            self.startRecordingImmediately = startRecordingImmediately
            self.customEndpoint = customEndpoint
        }

        @_spi(Internal)
        public mutating func setAdditionalNodeRecorders(_ additionalNodeRecorders: [SessionReplayNodeRecorder]) {
            self._additionalNodeRecorders = additionalNodeRecorders
        }
    }
}
#endif
