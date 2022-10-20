/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// A draft interface of SR feature.
public class SessionReplayFeature {
    public static var instance: SessionReplayFeature?

    private let recorder: Recorder

    public init() {
        self.recorder = Recorder()
    }

    public func start() { recorder.start() }
    public func stop() { recorder.stop() }

    /// The content recording policy for Session Replay. It describes the way in which sensitive content (e.g. text or images) should be recorded.
    /// Uses `.maskAll` by default.
    ///
    /// **Note**: It must be changed from the main thread.
    public var privacy: SessionReplayPrivacy {
        set { recorder.privacy = newValue }
        get { recorder.privacy }
    }
}

/// Session Replay content policy. It describes the way in which sensitive content (e.g. text or images) should be recorded.
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
