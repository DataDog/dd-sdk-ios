/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// A draft interface of SR configuration.
public struct SessionReplayConfiguration {
    /// Defines the way in which sensitive content (e.g. text or images) should be recorded.
    /// Defaults to `.maskAll`.
    public let privacy: SessionReplayPrivacy

    public init(
        privacy: SessionReplayPrivacy = .maskAll
    ) {
        self.privacy = privacy
    }
}

/// Session Replay content recording policy.
/// It describes the way in which sensitive content (e.g. text or images) should be captured.
public enum SessionReplayPrivacy {
    /// Record all content as it is.
    /// When using this option: all text, images and other information will be recorded and presented in the player.
    case allowAll

    /// Mask all content.
    /// When using this option: all characters in texts will be replaced with "x", images will be
    /// replaced with placeholders and other content will be masked accordingly, so the original
    /// information will not be presented in the player.
    ///
    /// This is the default content policy.
    case maskAll
}
