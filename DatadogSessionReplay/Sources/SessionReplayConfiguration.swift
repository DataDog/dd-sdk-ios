/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Session Replay feature configuration.
@objc(DDSessionReplayConfiguration)
public final class SessionReplayConfiguration: NSObject {
    /// The sampling rate for Session Replay. It is applied in addition to the RUM session sample rate.
    ///
    /// It must be a number between 0.0 and 100.0, where 0 means no replays will be recorded
    /// and 100 means all RUM sessions will contain replay.
    ///
    /// Note: This sample rate is applied in addition to the RUM sample rate. For example, if RUM uses a sample rate of 80%
    /// and Session Replay uses a sample rate of 20%, it means that out of all user sessions, 80% will be included in RUM,
    /// and within those sessions, only 20% will have replays.
    @objc public var replaySampleRate: Float

    /// Defines the way sensitive content (e.g. text) should be masked.
    ///
    /// Default: `.mask`.
    @objc public var defaultPrivacyLevel: PrivacyLevel

    /// Custom server url for sending replay data.
    ///
    /// Default: `nil`.
    @objc public var customEndpoint: URL?

    internal var debugSDK: Bool = ProcessInfo.processInfo.arguments.contains(LaunchArguments.Debug)

    /// Creates Session Replay configuration.
    ///
    /// - Parameters:
    ///   - replaySampleRate: The sampling rate for Session Replay. It is applied in addition to the RUM session sample rate.
    ///   - defaultPrivacyLevel: The way sensitive content (e.g. text) should be masked. Default: `.mask`.
    ///   - customEndpoint: Custom server url for sending replay data. Default: `nil`.
    @objc
    public required init(
        replaySampleRate: Float,
        defaultPrivacyLevel: PrivacyLevel = .mask,
        customEndpoint: URL? = nil
    ) {
        self.replaySampleRate = replaySampleRate
        self.defaultPrivacyLevel = defaultPrivacyLevel
        self.customEndpoint = customEndpoint
        super.init()
    }

    /// Creates Session Replay configuration.
    ///
    /// - Parameters:
    ///   - replaySampleRate: The sampling rate for Session Replay. It is applied in addition to the RUM session sample rate.
    @objc
    public convenience init(replaySampleRate: Float) {
        self.init(
            replaySampleRate: replaySampleRate,
            defaultPrivacyLevel: .mask
        )
    }
}

/// Available privacy levels for content masking.
@objc(DDSessionReplayConfigurationPrivacyLevel)
public enum PrivacyLevel: Int {
    /// Record all content.
    case allow

    /// Mask all content.
    case mask

    /// Mask input elements, but record all other content.
    case maskUserInput
}
