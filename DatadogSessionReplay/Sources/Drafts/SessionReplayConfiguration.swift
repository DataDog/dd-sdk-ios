/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// A draft interface of SR configuration.
public struct SessionReplayConfiguration {
    /// Defines the way in which sensitive content (e.g. text or images) should be recorded.
    /// Defaults to `.maskAll`.
    public var privacy: SessionReplayPrivacy

    /// Defines a custom URL for uploading data to.
    ///
    /// Defaults to `nil` which makes the Session Replay upload data to Datadog Site configured in
    /// the target instance of Datadog SDK.
    public var customUploadURL: URL?

    /// Defines the percentage of sessions that should be tracked by Session Replay.
    ///
    /// It should be a number between 0.0 and 100.0, where 0.0 indicates that no sessions should be tracked and 100.0 indicates that all sessions should be tracked.
    /// By default, it is set to 0.0. Adjust the `samplingRate` based on the needs of your application and any resource constraints.
    public var samplingRate: Float = 0.0

    public init(
        privacy: SessionReplayPrivacy = .maskAll,
        customUploadURL: URL? = nil,
        samplingRate: Float = 0.0
    ) {
        self.privacy = privacy
        self.customUploadURL = customUploadURL
        self.samplingRate = samplingRate
    }
}
