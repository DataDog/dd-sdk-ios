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

    public init(
        privacy: SessionReplayPrivacy = .maskAll,
        customUploadURL: URL? = nil
    ) {
        self.privacy = privacy
        self.customUploadURL = customUploadURL
    }
}
